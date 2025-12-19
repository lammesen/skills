# Redis Patterns Reference

Production-ready patterns for caching, sessions, rate limiting, and distributed systems.

---

## Caching Strategies

### Cache-Aside (Lazy Loading)

The most common pattern: application checks cache first, falls back to database.

```typescript
import { redis } from "bun";

interface CacheOptions {
  ttl?: number;        // Time to live in seconds
  prefix?: string;     // Key prefix
}

async function cached<T>(
  key: string,
  fetchFn: () => Promise<T>,
  options: CacheOptions = {}
): Promise<T> {
  const { ttl = 3600, prefix = "cache" } = options;
  const cacheKey = `${prefix}:${key}`;

  // Try cache first
  const cached = await redis.get(cacheKey);
  if (cached) {
    return JSON.parse(cached);
  }

  // Fetch from source
  const data = await fetchFn();

  // Store in cache (fire and forget for performance)
  redis.set(cacheKey, JSON.stringify(data))
    .then(() => redis.expire(cacheKey, ttl))
    .catch(console.error);

  return data;
}

// Usage
const user = await cached(
  `user:${userId}`,
  () => db.query("SELECT * FROM users WHERE id = ?", [userId]),
  { ttl: 1800 }
);
```

### Write-Through

Data is written to cache and database simultaneously.

```typescript
async function writeThrough<T>(
  key: string,
  data: T,
  saveFn: (data: T) => Promise<void>,
  ttl: number = 3600
): Promise<void> {
  // Write to database first (ensures consistency)
  await saveFn(data);

  // Then update cache
  await redis.set(`cache:${key}`, JSON.stringify(data));
  await redis.expire(`cache:${key}`, ttl);
}

// Usage
await writeThrough(
  `user:${userId}`,
  userData,
  (data) => db.query("UPDATE users SET ? WHERE id = ?", [data, userId])
);
```

### Write-Behind (Async Write)

Cache is updated immediately; database write is deferred.

```typescript
const writeQueue = new Map<string, { data: any; timer: Timer }>();

async function writeBehind<T>(
  key: string,
  data: T,
  saveFn: (data: T) => Promise<void>,
  delayMs: number = 5000
): Promise<void> {
  // Update cache immediately
  await redis.set(`cache:${key}`, JSON.stringify(data));

  // Debounce database write
  const existing = writeQueue.get(key);
  if (existing) {
    clearTimeout(existing.timer);
  }

  const timer = setTimeout(async () => {
    try {
      await saveFn(data);
      writeQueue.delete(key);
    } catch (error) {
      console.error(`Failed to persist ${key}:`, error);
      // Optionally retry or alert
    }
  }, delayMs);

  writeQueue.set(key, { data, timer });
}
```

### Cache Stampede Prevention

Prevent multiple simultaneous cache misses from overwhelming the database.

```typescript
async function cachedWithLock<T>(
  key: string,
  fetchFn: () => Promise<T>,
  options: { ttl?: number; lockTimeout?: number; retryDelay?: number } = {}
): Promise<T> {
  const { ttl = 3600, lockTimeout = 5000, retryDelay = 100 } = options;
  const cacheKey = `cache:${key}`;
  const lockKey = `lock:${key}`;

  // Check cache
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached);

  // Try to acquire lock
  const lockToken = crypto.randomUUID();
  const acquired = await redis.send("SET", [
    lockKey, lockToken, "NX", "PX", lockTimeout.toString()
  ]);

  if (acquired === "OK") {
    try {
      // Double-check cache (another request might have populated it)
      const recheckCache = await redis.get(cacheKey);
      if (recheckCache) return JSON.parse(recheckCache);

      // Fetch and cache
      const data = await fetchFn();
      await redis.set(cacheKey, JSON.stringify(data));
      await redis.expire(cacheKey, ttl);
      return data;
    } finally {
      // Release lock safely
      await redis.send("EVAL", [
        `if redis.call("GET", KEYS[1]) == ARGV[1] then return redis.call("DEL", KEYS[1]) else return 0 end`,
        "1", lockKey, lockToken
      ]);
    }
  }

  // Wait and retry if lock not acquired
  await Bun.sleep(retryDelay);
  return cachedWithLock(key, fetchFn, options);
}
```

### Stale-While-Revalidate

Serve stale data while refreshing in background.

```typescript
interface CacheEntry<T> {
  data: T;
  staleAt: number;  // Timestamp when data becomes stale
}

async function staleWhileRevalidate<T>(
  key: string,
  fetchFn: () => Promise<T>,
  options: { freshFor?: number; staleFor?: number } = {}
): Promise<T> {
  const { freshFor = 60, staleFor = 300 } = options;  // seconds
  const cacheKey = `cache:${key}`;

  const cached = await redis.get(cacheKey);

  if (cached) {
    const entry: CacheEntry<T> = JSON.parse(cached);
    const now = Date.now();

    // If stale, trigger background refresh
    if (now > entry.staleAt) {
      // Fire and forget refresh
      refreshCache(key, fetchFn, freshFor, staleFor).catch(console.error);
    }

    return entry.data;
  }

  // Cache miss - fetch synchronously
  return refreshCache(key, fetchFn, freshFor, staleFor);
}

async function refreshCache<T>(
  key: string,
  fetchFn: () => Promise<T>,
  freshFor: number,
  staleFor: number
): Promise<T> {
  const data = await fetchFn();
  const entry: CacheEntry<T> = {
    data,
    staleAt: Date.now() + freshFor * 1000
  };

  await redis.set(`cache:${key}`, JSON.stringify(entry));
  await redis.expire(`cache:${key}`, staleFor);

  return data;
}
```

### Cache Invalidation

```typescript
// Invalidate single key
async function invalidate(key: string): Promise<void> {
  await redis.del(`cache:${key}`);
}

// Invalidate by pattern
async function invalidatePattern(pattern: string): Promise<number> {
  let cursor = "0";
  let deleted = 0;

  do {
    const [newCursor, keys] = await redis.send("SCAN", [
      cursor, "MATCH", `cache:${pattern}`, "COUNT", "100"
    ]) as [string, string[]];

    cursor = newCursor;

    if (keys.length > 0) {
      deleted += await redis.del(...keys);
    }
  } while (cursor !== "0");

  return deleted;
}

// Invalidate on entity update
async function updateUser(userId: string, data: any) {
  await db.updateUser(userId, data);

  // Invalidate related caches
  await Promise.all([
    invalidate(`user:${userId}`),
    invalidate(`user:${userId}:profile`),
    invalidatePattern(`user:${userId}:posts:*`),
  ]);
}
```

---

## Session Storage

### Basic Session Store

```typescript
import { redis } from "bun";

interface Session {
  userId: string;
  data: Record<string, any>;
  createdAt: number;
  lastAccess: number;
}

const SESSION_TTL = 86400;  // 24 hours

async function createSession(userId: string, data: Record<string, any> = {}): Promise<string> {
  const sessionId = crypto.randomUUID();
  const now = Date.now();

  const session: Session = {
    userId,
    data,
    createdAt: now,
    lastAccess: now
  };

  await redis.hmset(`session:${sessionId}`, [
    "userId", userId,
    "data", JSON.stringify(data),
    "createdAt", now.toString(),
    "lastAccess", now.toString()
  ]);
  await redis.expire(`session:${sessionId}`, SESSION_TTL);

  // Track user sessions for multi-device support
  await redis.sadd(`user:${userId}:sessions`, sessionId);

  return sessionId;
}

async function getSession(sessionId: string): Promise<Session | null> {
  const exists = await redis.exists(`session:${sessionId}`);
  if (!exists) return null;

  const [userId, data, createdAt, lastAccess] = await redis.hmget(
    `session:${sessionId}`,
    ["userId", "data", "createdAt", "lastAccess"]
  );

  if (!userId) return null;

  // Update last access (sliding expiration)
  const now = Date.now();
  await redis.hmset(`session:${sessionId}`, ["lastAccess", now.toString()]);
  await redis.expire(`session:${sessionId}`, SESSION_TTL);

  return {
    userId,
    data: JSON.parse(data || "{}"),
    createdAt: Number(createdAt),
    lastAccess: Number(lastAccess)
  };
}

async function updateSessionData(sessionId: string, updates: Record<string, any>): Promise<void> {
  const session = await getSession(sessionId);
  if (!session) throw new Error("Session not found");

  const newData = { ...session.data, ...updates };
  await redis.hmset(`session:${sessionId}`, ["data", JSON.stringify(newData)]);
}

async function destroySession(sessionId: string): Promise<void> {
  const session = await getSession(sessionId);
  if (session) {
    await redis.srem(`user:${session.userId}:sessions`, sessionId);
    await redis.del(`session:${sessionId}`);
  }
}

async function destroyAllUserSessions(userId: string): Promise<void> {
  const sessionIds = await redis.smembers(`user:${userId}:sessions`);

  if (sessionIds.length > 0) {
    await Promise.all([
      ...sessionIds.map(id => redis.del(`session:${id}`)),
      redis.del(`user:${userId}:sessions`)
    ]);
  }
}

async function getActiveSessionCount(userId: string): Promise<number> {
  return await redis.send("SCARD", [`user:${userId}:sessions`]) as number;
}
```

### Session Middleware for Elysia

```typescript
import { Elysia } from "elysia";

const sessionMiddleware = new Elysia({ name: "session" })
  .derive(async ({ cookie, set }) => {
    const sessionId = cookie.session?.value;

    if (!sessionId) {
      return { session: null };
    }

    const session = await getSession(sessionId);

    if (!session) {
      // Invalid session, clear cookie
      cookie.session.remove();
      return { session: null };
    }

    return { session };
  })
  .macro({
    requireSession: () => ({
      beforeHandle({ session, set }) {
        if (!session) {
          set.status = 401;
          return { error: "Unauthorized" };
        }
      }
    })
  });
```

---

## Rate Limiting

### Fixed Window

Simple but has boundary issues (2x burst at window edges).

```typescript
interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetIn: number;
}

async function fixedWindowLimit(
  identifier: string,
  limit: number,
  windowSecs: number
): Promise<RateLimitResult> {
  const window = Math.floor(Date.now() / 1000 / windowSecs);
  const key = `ratelimit:${identifier}:${window}`;

  const count = await redis.incr(key);

  if (count === 1) {
    await redis.expire(key, windowSecs);
  }

  const ttl = await redis.ttl(key);

  return {
    allowed: count <= limit,
    remaining: Math.max(0, limit - count),
    resetIn: ttl
  };
}
```

### Sliding Window Log

More accurate but uses more memory.

```typescript
async function slidingWindowLimit(
  identifier: string,
  limit: number,
  windowMs: number
): Promise<{ allowed: boolean; remaining: number }> {
  const key = `ratelimit:sliding:${identifier}`;
  const now = Date.now();
  const windowStart = now - windowMs;

  // Lua script for atomic sliding window
  const script = `
    -- Remove old entries
    redis.call("ZREMRANGEBYSCORE", KEYS[1], 0, ARGV[1])

    -- Count current window
    local count = redis.call("ZCARD", KEYS[1])

    if count < tonumber(ARGV[2]) then
      -- Add new entry
      redis.call("ZADD", KEYS[1], ARGV[3], ARGV[3])
      redis.call("PEXPIRE", KEYS[1], ARGV[4])
      return {1, tonumber(ARGV[2]) - count - 1}
    end

    return {0, 0}
  `;

  const [allowed, remaining] = await redis.send("EVAL", [
    script, "1", key,
    windowStart.toString(),
    limit.toString(),
    now.toString(),
    windowMs.toString()
  ]) as [number, number];

  return { allowed: allowed === 1, remaining };
}
```

### Token Bucket

Allows bursting while maintaining average rate.

```typescript
async function tokenBucketLimit(
  identifier: string,
  capacity: number,      // Max tokens (burst size)
  refillRate: number,    // Tokens per second
  tokensRequired: number = 1
): Promise<{ allowed: boolean; remaining: number }> {
  const key = `bucket:${identifier}`;
  const now = Date.now() / 1000;

  const script = `
    local key = KEYS[1]
    local capacity = tonumber(ARGV[1])
    local refill_rate = tonumber(ARGV[2])
    local tokens_required = tonumber(ARGV[3])
    local now = tonumber(ARGV[4])

    -- Get current state
    local tokens = tonumber(redis.call("HGET", key, "tokens")) or capacity
    local last_refill = tonumber(redis.call("HGET", key, "last")) or now

    -- Calculate tokens to add since last refill
    local elapsed = now - last_refill
    tokens = math.min(capacity, tokens + elapsed * refill_rate)

    if tokens >= tokens_required then
      tokens = tokens - tokens_required
      redis.call("HMSET", key, "tokens", tokens, "last", now)
      redis.call("EXPIRE", key, 3600)
      return {1, math.floor(tokens)}
    end

    -- Update state even if request denied (for accurate refill tracking)
    redis.call("HMSET", key, "tokens", tokens, "last", now)
    redis.call("EXPIRE", key, 3600)
    return {0, math.floor(tokens)}
  `;

  const [allowed, remaining] = await redis.send("EVAL", [
    script, "1", key,
    capacity.toString(),
    refillRate.toString(),
    tokensRequired.toString(),
    now.toString()
  ]) as [number, number];

  return { allowed: allowed === 1, remaining };
}
```

### Rate Limit Middleware

```typescript
import { Elysia } from "elysia";

interface RateLimitOptions {
  limit: number;
  window: number;
  keyGenerator?: (ctx: any) => string;
}

function rateLimit(options: RateLimitOptions) {
  const { limit, window, keyGenerator } = options;

  return new Elysia()
    .derive(async (ctx) => {
      const key = keyGenerator
        ? keyGenerator(ctx)
        : ctx.request.headers.get("x-forwarded-for") || "anonymous";

      const result = await slidingWindowLimit(key, limit, window * 1000);

      return { rateLimit: result };
    })
    .onBeforeHandle(({ rateLimit, set }) => {
      set.headers["X-RateLimit-Limit"] = limit.toString();
      set.headers["X-RateLimit-Remaining"] = rateLimit.remaining.toString();

      if (!rateLimit.allowed) {
        set.status = 429;
        return { error: "Rate limit exceeded" };
      }
    });
}

// Usage
const app = new Elysia()
  .use(rateLimit({ limit: 100, window: 60 }))  // 100 req/min
  .get("/api/data", () => ({ data: "Hello" }));
```

---

## Distributed Locking

### Basic Lock

```typescript
interface Lock {
  resource: string;
  token: string;
  ttlMs: number;
}

async function acquireLock(
  resource: string,
  ttlMs: number = 10000
): Promise<Lock | null> {
  const token = crypto.randomUUID();

  const result = await redis.send("SET", [
    `lock:${resource}`,
    token,
    "NX",           // Only if not exists
    "PX",           // Milliseconds
    ttlMs.toString()
  ]);

  return result === "OK" ? { resource, token, ttlMs } : null;
}

async function releaseLock(lock: Lock): Promise<boolean> {
  // Lua script ensures we only delete our own lock
  const script = `
    if redis.call("GET", KEYS[1]) == ARGV[1] then
      return redis.call("DEL", KEYS[1])
    end
    return 0
  `;

  const result = await redis.send("EVAL", [
    script, "1", `lock:${lock.resource}`, lock.token
  ]);

  return result === 1;
}

async function extendLock(lock: Lock, additionalMs: number): Promise<boolean> {
  const script = `
    if redis.call("GET", KEYS[1]) == ARGV[1] then
      return redis.call("PEXPIRE", KEYS[1], ARGV[2])
    end
    return 0
  `;

  const result = await redis.send("EVAL", [
    script, "1", `lock:${lock.resource}`, lock.token, additionalMs.toString()
  ]);

  return result === 1;
}
```

### Auto-Releasing Lock Wrapper

```typescript
async function withLock<T>(
  resource: string,
  fn: () => Promise<T>,
  options: { ttlMs?: number; retryMs?: number; maxRetries?: number } = {}
): Promise<T> {
  const { ttlMs = 10000, retryMs = 100, maxRetries = 50 } = options;

  let attempts = 0;
  let lock: Lock | null = null;

  // Try to acquire lock with retries
  while (!lock && attempts < maxRetries) {
    lock = await acquireLock(resource, ttlMs);
    if (!lock) {
      attempts++;
      await Bun.sleep(retryMs);
    }
  }

  if (!lock) {
    throw new Error(`Failed to acquire lock for ${resource} after ${maxRetries} attempts`);
  }

  try {
    return await fn();
  } finally {
    await releaseLock(lock);
  }
}

// Usage
const result = await withLock("order:123", async () => {
  // Critical section
  const order = await db.getOrder("123");
  order.status = "processing";
  await db.saveOrder(order);
  return order;
});
```

### Lock with Auto-Extension

For long-running operations, extend lock periodically.

```typescript
async function withAutoExtendLock<T>(
  resource: string,
  fn: () => Promise<T>,
  ttlMs: number = 10000
): Promise<T> {
  const lock = await acquireLock(resource, ttlMs);
  if (!lock) throw new Error(`Failed to acquire lock for ${resource}`);

  // Extend lock at half the TTL interval
  const extendInterval = setInterval(async () => {
    const extended = await extendLock(lock, ttlMs);
    if (!extended) {
      clearInterval(extendInterval);
      console.error(`Lost lock for ${resource}`);
    }
  }, ttlMs / 2);

  try {
    return await fn();
  } finally {
    clearInterval(extendInterval);
    await releaseLock(lock);
  }
}
```

---

## Job Queues

### Simple FIFO Queue

```typescript
async function enqueue(queue: string, job: any): Promise<void> {
  await redis.send("RPUSH", [`queue:${queue}`, JSON.stringify(job)]);
}

async function dequeue(queue: string, timeout: number = 0): Promise<any | null> {
  const result = await redis.send("BLPOP", [`queue:${queue}`, timeout.toString()]);

  if (!result) return null;

  const [, data] = result as [string, string];
  return JSON.parse(data);
}

// Worker
async function startWorker(queue: string, handler: (job: any) => Promise<void>) {
  console.log(`Worker started for queue: ${queue}`);

  while (true) {
    const job = await dequeue(queue, 30);  // 30s timeout

    if (job) {
      try {
        await handler(job);
      } catch (error) {
        console.error("Job failed:", error);
        // Optionally re-queue or send to dead letter queue
        await enqueue(`${queue}:failed`, { job, error: String(error), time: Date.now() });
      }
    }
  }
}
```

### Priority Queue

```typescript
async function enqueuePriority(queue: string, job: any, priority: number): Promise<void> {
  // Higher priority = lower score (processed first)
  await redis.send("ZADD", [
    `pqueue:${queue}`,
    priority.toString(),
    JSON.stringify({ ...job, _id: crypto.randomUUID() })
  ]);
}

async function dequeuePriority(queue: string): Promise<any | null> {
  // Pop lowest score (highest priority)
  const result = await redis.send("ZPOPMIN", [`pqueue:${queue}`, "1"]) as string[];

  if (!result || result.length === 0) return null;

  return JSON.parse(result[0]);
}
```

### Delayed Queue

```typescript
async function enqueueDelayed(queue: string, job: any, delayMs: number): Promise<void> {
  const executeAt = Date.now() + delayMs;

  await redis.send("ZADD", [
    `delayed:${queue}`,
    executeAt.toString(),
    JSON.stringify({ ...job, _id: crypto.randomUUID() })
  ]);
}

// Move ready jobs to main queue
async function processDelayedQueue(queue: string): Promise<void> {
  const now = Date.now();

  // Get ready jobs
  const jobs = await redis.send("ZRANGEBYSCORE", [
    `delayed:${queue}`,
    "0",
    now.toString(),
    "LIMIT", "0", "100"
  ]) as string[];

  for (const job of jobs) {
    // Move to main queue
    await redis.send("RPUSH", [`queue:${queue}`, job]);
    await redis.send("ZREM", [`delayed:${queue}`, job]);
  }
}
```

---

## Leaderboards

```typescript
interface LeaderboardEntry {
  member: string;
  score: number;
  rank: number;
}

class Leaderboard {
  private key: string;

  constructor(name: string) {
    this.key = `leaderboard:${name}`;
  }

  async addScore(member: string, score: number): Promise<void> {
    await redis.send("ZADD", [this.key, score.toString(), member]);
  }

  async incrementScore(member: string, increment: number): Promise<number> {
    const newScore = await redis.send("ZINCRBY", [this.key, increment.toString(), member]);
    return parseFloat(newScore as string);
  }

  async getScore(member: string): Promise<number | null> {
    const score = await redis.send("ZSCORE", [this.key, member]);
    return score ? parseFloat(score as string) : null;
  }

  async getRank(member: string): Promise<number | null> {
    // 0-indexed, null if not in leaderboard
    const rank = await redis.send("ZREVRANK", [this.key, member]);
    return rank !== null ? (rank as number) + 1 : null;  // 1-indexed
  }

  async getTop(count: number = 10): Promise<LeaderboardEntry[]> {
    const results = await redis.send("ZREVRANGE", [
      this.key, "0", (count - 1).toString(), "WITHSCORES"
    ]) as string[];

    const entries: LeaderboardEntry[] = [];
    for (let i = 0; i < results.length; i += 2) {
      entries.push({
        member: results[i],
        score: parseFloat(results[i + 1]),
        rank: entries.length + 1
      });
    }
    return entries;
  }

  async getRange(start: number, end: number): Promise<LeaderboardEntry[]> {
    const results = await redis.send("ZREVRANGE", [
      this.key, (start - 1).toString(), (end - 1).toString(), "WITHSCORES"
    ]) as string[];

    const entries: LeaderboardEntry[] = [];
    for (let i = 0; i < results.length; i += 2) {
      entries.push({
        member: results[i],
        score: parseFloat(results[i + 1]),
        rank: start + entries.length
      });
    }
    return entries;
  }

  async getAroundMember(member: string, range: number = 5): Promise<LeaderboardEntry[]> {
    const rank = await redis.send("ZREVRANK", [this.key, member]) as number | null;
    if (rank === null) return [];

    const start = Math.max(0, rank - range);
    const end = rank + range;

    return this.getRange(start + 1, end + 1);
  }

  async getCount(): Promise<number> {
    return await redis.send("ZCARD", [this.key]) as number;
  }

  async remove(member: string): Promise<boolean> {
    const removed = await redis.send("ZREM", [this.key, member]);
    return removed === 1;
  }
}

// Usage
const leaderboard = new Leaderboard("weekly");
await leaderboard.addScore("player1", 1000);
await leaderboard.incrementScore("player1", 50);
const top10 = await leaderboard.getTop(10);
const myRank = await leaderboard.getRank("player1");
```

---

## Counting and Analytics

### Real-Time Counters

```typescript
// Simple counter
async function increment(counter: string, by: number = 1): Promise<number> {
  return await redis.send("INCRBY", [`counter:${counter}`, by.toString()]) as number;
}

// Time-bucketed counters
async function incrementTimeBucket(
  counter: string,
  bucketSize: "minute" | "hour" | "day"
): Promise<void> {
  const now = Date.now();
  const bucket = {
    minute: Math.floor(now / 60000),
    hour: Math.floor(now / 3600000),
    day: Math.floor(now / 86400000)
  }[bucketSize];

  const key = `counter:${counter}:${bucketSize}:${bucket}`;

  await redis.incr(key);

  // Set expiration based on bucket size
  const ttl = { minute: 3600, hour: 86400, day: 2592000 }[bucketSize];
  await redis.expire(key, ttl);
}

// Get count for time range
async function getCountForRange(
  counter: string,
  bucketSize: "minute" | "hour" | "day",
  startBucket: number,
  endBucket: number
): Promise<number> {
  const keys: string[] = [];
  for (let b = startBucket; b <= endBucket; b++) {
    keys.push(`counter:${counter}:${bucketSize}:${b}`);
  }

  const values = await redis.send("MGET", keys) as (string | null)[];
  return values.reduce((sum, v) => sum + (parseInt(v || "0", 10)), 0);
}
```

### Unique Counting with HyperLogLog

```typescript
async function trackUniqueVisitor(page: string, visitorId: string): Promise<void> {
  const today = new Date().toISOString().split("T")[0];
  await redis.send("PFADD", [`unique:${page}:${today}`, visitorId]);
}

async function getUniqueCount(page: string, date: string): Promise<number> {
  return await redis.send("PFCOUNT", [`unique:${page}:${date}`]) as number;
}

async function getUniqueCountRange(page: string, dates: string[]): Promise<number> {
  const keys = dates.map(d => `unique:${page}:${d}`);
  return await redis.send("PFCOUNT", keys) as number;
}
```

---

## Feature Flags

```typescript
interface FeatureFlag {
  enabled: boolean;
  percentage?: number;  // Rollout percentage
  allowlist?: string[]; // Specific users always enabled
  blocklist?: string[]; // Specific users always disabled
}

async function setFeatureFlag(name: string, config: FeatureFlag): Promise<void> {
  await redis.set(`feature:${name}`, JSON.stringify(config));
}

async function isFeatureEnabled(name: string, userId?: string): Promise<boolean> {
  const config = await redis.get(`feature:${name}`);
  if (!config) return false;

  const flag: FeatureFlag = JSON.parse(config);

  if (!flag.enabled) return false;

  if (userId) {
    // Check blocklist
    if (flag.blocklist?.includes(userId)) return false;

    // Check allowlist
    if (flag.allowlist?.includes(userId)) return true;

    // Percentage rollout (deterministic per user)
    if (flag.percentage !== undefined && flag.percentage < 100) {
      const hash = await hashUserId(userId);
      return (hash % 100) < flag.percentage;
    }
  }

  return true;
}

async function hashUserId(userId: string): Promise<number> {
  const hash = Bun.hash(userId);
  return Math.abs(Number(hash % 100n));
}
```
