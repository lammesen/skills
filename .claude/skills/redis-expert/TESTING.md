# Redis Testing Patterns

Testing strategies for Redis operations using Bun's test runner.

---

## Test Setup

### Basic Test Configuration

```typescript
import { describe, test, expect, beforeAll, afterAll, beforeEach } from "bun:test";
import { RedisClient, redis } from "bun";

describe("Redis operations", () => {
  // Use unique prefix to avoid conflicts with other tests
  const testPrefix = `test:${Date.now()}:`;

  beforeAll(async () => {
    // Verify connection
    const pong = await redis.send("PING", []);
    expect(pong).toBe("PONG");
  });

  afterAll(async () => {
    // Clean up all test keys
    await cleanupTestKeys(testPrefix);
  });

  beforeEach(async () => {
    // Optional: clean specific keys before each test
  });

  // Tests go here...
});

async function cleanupTestKeys(prefix: string): Promise<number> {
  let cursor = "0";
  let deleted = 0;

  do {
    const [newCursor, keys] = await redis.send("SCAN", [
      cursor, "MATCH", `${prefix}*`, "COUNT", "100"
    ]) as [string, string[]];

    cursor = newCursor;

    if (keys.length > 0) {
      deleted += await redis.send("DEL", keys) as number;
    }
  } while (cursor !== "0");

  return deleted;
}
```

### Test Helper Class

```typescript
export class RedisTestHelper {
  private prefix: string;
  private keys: Set<string> = new Set();

  constructor(testName: string) {
    this.prefix = `test:${testName}:${Date.now()}:`;
  }

  // Generate unique key and track it
  key(name: string): string {
    const fullKey = `${this.prefix}${name}`;
    this.keys.add(fullKey);
    return fullKey;
  }

  // Clean up all tracked keys
  async cleanup(): Promise<void> {
    if (this.keys.size > 0) {
      await redis.send("DEL", [...this.keys]);
      this.keys.clear();
    }
  }

  // Seed test data
  async seed(data: Record<string, string>): Promise<void> {
    const args: string[] = [];
    for (const [k, v] of Object.entries(data)) {
      const key = this.key(k);
      args.push(key, v);
    }
    if (args.length > 0) {
      await redis.send("MSET", args);
    }
  }

  // Wait for key to exist (useful for async operations)
  async waitForKey(name: string, timeoutMs: number = 5000): Promise<boolean> {
    const key = `${this.prefix}${name}`;
    const start = Date.now();

    while (Date.now() - start < timeoutMs) {
      const exists = await redis.exists(key);
      if (exists) return true;
      await Bun.sleep(50);
    }

    return false;
  }
}
```

---

## Unit Testing Redis Operations

### String Operations

```typescript
import { describe, test, expect, afterEach } from "bun:test";
import { redis } from "bun";

describe("String operations", () => {
  const helper = new RedisTestHelper("strings");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("set and get string", async () => {
    const key = helper.key("simple");

    await redis.set(key, "hello");
    const value = await redis.get(key);

    expect(value).toBe("hello");
  });

  test("set with expiration", async () => {
    const key = helper.key("expiring");

    await redis.set(key, "temporary");
    await redis.expire(key, 1);

    // Should exist immediately
    expect(await redis.exists(key)).toBe(1);

    // Wait for expiration
    await Bun.sleep(1100);

    // Should be gone
    expect(await redis.exists(key)).toBe(0);
  });

  test("increment counter", async () => {
    const key = helper.key("counter");

    await redis.set(key, "0");

    const val1 = await redis.incr(key);
    const val2 = await redis.incr(key);
    const val3 = await redis.incr(key);

    expect(val1).toBe(1);
    expect(val2).toBe(2);
    expect(val3).toBe(3);
  });

  test("get non-existent key returns null", async () => {
    const key = helper.key("nonexistent");
    const value = await redis.get(key);
    expect(value).toBeNull();
  });
});
```

### Hash Operations

```typescript
describe("Hash operations", () => {
  const helper = new RedisTestHelper("hashes");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("set and get hash fields", async () => {
    const key = helper.key("user");

    await redis.hmset(key, [
      "name", "Alice",
      "email", "alice@example.com",
      "age", "30"
    ]);

    const name = await redis.hget(key, "name");
    const fields = await redis.hmget(key, ["name", "email", "age"]);

    expect(name).toBe("Alice");
    expect(fields).toEqual(["Alice", "alice@example.com", "30"]);
  });

  test("increment hash field", async () => {
    const key = helper.key("stats");

    await redis.hmset(key, ["views", "0", "likes", "10"]);

    const newViews = await redis.hincrby(key, "views", 1);
    const newLikes = await redis.hincrby(key, "likes", 5);

    expect(newViews).toBe(1);
    expect(newLikes).toBe(15);
  });

  test("get non-existent hash field returns null", async () => {
    const key = helper.key("partial");

    await redis.hmset(key, ["exists", "yes"]);

    const value = await redis.hget(key, "nonexistent");
    expect(value).toBeNull();
  });
});
```

### Set Operations

```typescript
describe("Set operations", () => {
  const helper = new RedisTestHelper("sets");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("add and check members", async () => {
    const key = helper.key("tags");

    await redis.sadd(key, "redis", "database", "cache");

    const isMember = await redis.sismember(key, "redis");
    const notMember = await redis.sismember(key, "mysql");

    expect(isMember).toBe(1);
    expect(notMember).toBe(0);
  });

  test("get all members", async () => {
    const key = helper.key("items");

    await redis.sadd(key, "a", "b", "c");

    const members = await redis.smembers(key);

    expect(members.sort()).toEqual(["a", "b", "c"]);
  });

  test("set operations", async () => {
    const key1 = helper.key("set1");
    const key2 = helper.key("set2");
    const destKey = helper.key("intersection");

    await redis.sadd(key1, "a", "b", "c");
    await redis.sadd(key2, "b", "c", "d");

    const intersection = await redis.send("SINTER", [key1, key2]) as string[];

    expect(intersection.sort()).toEqual(["b", "c"]);
  });
});
```

### Sorted Set Operations

```typescript
describe("Sorted set operations", () => {
  const helper = new RedisTestHelper("zsets");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("add scores and get ranking", async () => {
    const key = helper.key("leaderboard");

    await redis.send("ZADD", [key, "100", "player1", "85", "player2", "92", "player3"]);

    const score = await redis.send("ZSCORE", [key, "player1"]);
    const rank = await redis.send("ZREVRANK", [key, "player1"]);

    expect(score).toBe("100");
    expect(rank).toBe(0);  // Top ranked (0-indexed)
  });

  test("get top entries", async () => {
    const key = helper.key("scores");

    await redis.send("ZADD", [key, "10", "a", "20", "b", "30", "c"]);

    const top2 = await redis.send("ZREVRANGE", [key, "0", "1", "WITHSCORES"]);

    expect(top2).toEqual(["c", "30", "b", "20"]);
  });
});
```

---

## Testing Lua Scripts

```typescript
describe("Lua scripts", () => {
  const helper = new RedisTestHelper("lua");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("compare and swap", async () => {
    const key = helper.key("cas");
    const script = `
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        redis.call("SET", KEYS[1], ARGV[2])
        return 1
      end
      return 0
    `;

    await redis.set(key, "oldvalue");

    // Successful swap
    const success = await redis.send("EVAL", [script, "1", key, "oldvalue", "newvalue"]);
    expect(success).toBe(1);

    const newVal = await redis.get(key);
    expect(newVal).toBe("newvalue");

    // Failed swap (wrong expected value)
    const failure = await redis.send("EVAL", [script, "1", key, "wrongvalue", "anothervalue"]);
    expect(failure).toBe(0);

    // Value unchanged
    expect(await redis.get(key)).toBe("newvalue");
  });

  test("atomic increment with limit", async () => {
    const key = helper.key("limited");
    const script = `
      local current = tonumber(redis.call("GET", KEYS[1]) or "0")
      local limit = tonumber(ARGV[1])

      if current >= limit then
        return {0, current}
      end

      local new = redis.call("INCR", KEYS[1])
      return {1, new}
    `;

    await redis.set(key, "8");

    // Can increment (under limit)
    const [allowed1, value1] = await redis.send("EVAL", [script, "1", key, "10"]) as [number, number];
    expect(allowed1).toBe(1);
    expect(value1).toBe(9);

    // Can increment (at limit - 1)
    const [allowed2, value2] = await redis.send("EVAL", [script, "1", key, "10"]) as [number, number];
    expect(allowed2).toBe(1);
    expect(value2).toBe(10);

    // Cannot increment (at limit)
    const [allowed3, value3] = await redis.send("EVAL", [script, "1", key, "10"]) as [number, number];
    expect(allowed3).toBe(0);
    expect(value3).toBe(10);
  });
});
```

---

## Testing Patterns

### Caching Tests

```typescript
describe("Cache operations", () => {
  const helper = new RedisTestHelper("cache");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("cache hit", async () => {
    const key = helper.key("user:123");
    const userData = { id: 123, name: "Test" };

    // Prime cache
    await redis.set(key, JSON.stringify(userData));
    await redis.expire(key, 3600);

    // Verify cache hit
    const cached = await redis.get(key);
    expect(cached).not.toBeNull();
    expect(JSON.parse(cached!)).toEqual(userData);
  });

  test("cache miss", async () => {
    const key = helper.key("user:nonexistent");

    const cached = await redis.get(key);
    expect(cached).toBeNull();
  });

  test("cache expiration", async () => {
    const key = helper.key("temp");

    await redis.set(key, "data");
    await redis.expire(key, 1);

    // Verify TTL is set
    const ttl = await redis.ttl(key);
    expect(ttl).toBeGreaterThan(0);
    expect(ttl).toBeLessThanOrEqual(1);

    // Wait for expiration
    await Bun.sleep(1100);

    // Should be expired
    expect(await redis.get(key)).toBeNull();
  });
});
```

### Rate Limiting Tests

```typescript
describe("Rate limiting", () => {
  const helper = new RedisTestHelper("ratelimit");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("allows requests under limit", async () => {
    const key = helper.key("user:123");
    const limit = 5;
    const window = 60;

    for (let i = 0; i < limit; i++) {
      const count = await redis.incr(key);
      if (count === 1) {
        await redis.expire(key, window);
      }
      expect(count).toBeLessThanOrEqual(limit);
    }
  });

  test("blocks requests over limit", async () => {
    const key = helper.key("user:456");
    const limit = 3;

    // Use up all requests
    for (let i = 0; i < limit; i++) {
      await redis.incr(key);
    }

    // Next request should exceed limit
    const count = await redis.incr(key);
    expect(count).toBe(limit + 1);
    expect(count > limit).toBe(true);
  });
});
```

### Distributed Lock Tests

```typescript
describe("Distributed locking", () => {
  const helper = new RedisTestHelper("lock");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("acquires lock successfully", async () => {
    const lockKey = helper.key("resource:123");
    const token = crypto.randomUUID();

    const result = await redis.send("SET", [lockKey, token, "NX", "PX", "10000"]);

    expect(result).toBe("OK");
  });

  test("fails to acquire already held lock", async () => {
    const lockKey = helper.key("resource:456");

    // First acquisition
    await redis.send("SET", [lockKey, "token1", "NX", "PX", "10000"]);

    // Second acquisition should fail
    const result = await redis.send("SET", [lockKey, "token2", "NX", "PX", "10000"]);

    expect(result).toBeNull();
  });

  test("releases lock correctly", async () => {
    const lockKey = helper.key("resource:789");
    const token = crypto.randomUUID();
    const releaseScript = `
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      end
      return 0
    `;

    // Acquire
    await redis.send("SET", [lockKey, token, "NX", "PX", "10000"]);

    // Release
    const released = await redis.send("EVAL", [releaseScript, "1", lockKey, token]);
    expect(released).toBe(1);

    // Verify released
    expect(await redis.exists(lockKey)).toBe(0);
  });

  test("does not release lock held by another", async () => {
    const lockKey = helper.key("resource:abc");
    const releaseScript = `
      if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
      end
      return 0
    `;

    // Acquire with token1
    await redis.send("SET", [lockKey, "token1", "NX", "PX", "10000"]);

    // Try to release with wrong token
    const released = await redis.send("EVAL", [releaseScript, "1", lockKey, "wrong-token"]);
    expect(released).toBe(0);

    // Lock should still be held
    expect(await redis.get(lockKey)).toBe("token1");
  });
});
```

---

## Mock Redis for Unit Tests

```typescript
// mock-redis.ts
export class MockRedis {
  private store: Map<string, any> = new Map();
  private expires: Map<string, number> = new Map();

  async get(key: string): Promise<string | null> {
    this.checkExpiry(key);
    return this.store.get(key) ?? null;
  }

  async set(key: string, value: string): Promise<"OK"> {
    this.store.set(key, value);
    return "OK";
  }

  async del(...keys: string[]): Promise<number> {
    let count = 0;
    for (const key of keys) {
      if (this.store.delete(key)) count++;
      this.expires.delete(key);
    }
    return count;
  }

  async exists(...keys: string[]): Promise<number> {
    let count = 0;
    for (const key of keys) {
      this.checkExpiry(key);
      if (this.store.has(key)) count++;
    }
    return count;
  }

  async incr(key: string): Promise<number> {
    const current = parseInt(this.store.get(key) ?? "0", 10);
    const next = current + 1;
    this.store.set(key, next.toString());
    return next;
  }

  async expire(key: string, seconds: number): Promise<number> {
    if (!this.store.has(key)) return 0;
    this.expires.set(key, Date.now() + seconds * 1000);
    return 1;
  }

  async ttl(key: string): Promise<number> {
    this.checkExpiry(key);
    if (!this.store.has(key)) return -2;
    const exp = this.expires.get(key);
    if (!exp) return -1;
    return Math.ceil((exp - Date.now()) / 1000);
  }

  async hmset(key: string, fields: string[]): Promise<"OK"> {
    const hash = this.store.get(key) ?? {};
    for (let i = 0; i < fields.length; i += 2) {
      hash[fields[i]] = fields[i + 1];
    }
    this.store.set(key, hash);
    return "OK";
  }

  async hget(key: string, field: string): Promise<string | null> {
    const hash = this.store.get(key);
    return hash?.[field] ?? null;
  }

  async hmget(key: string, fields: string[]): Promise<(string | null)[]> {
    const hash = this.store.get(key) ?? {};
    return fields.map(f => hash[f] ?? null);
  }

  async sadd(key: string, ...members: string[]): Promise<number> {
    let set = this.store.get(key);
    if (!(set instanceof Set)) {
      set = new Set();
      this.store.set(key, set);
    }
    let added = 0;
    for (const m of members) {
      if (!set.has(m)) {
        set.add(m);
        added++;
      }
    }
    return added;
  }

  async smembers(key: string): Promise<string[]> {
    const set = this.store.get(key);
    return set instanceof Set ? [...set] : [];
  }

  async sismember(key: string, member: string): Promise<number> {
    const set = this.store.get(key);
    return set instanceof Set && set.has(member) ? 1 : 0;
  }

  private checkExpiry(key: string): void {
    const exp = this.expires.get(key);
    if (exp && Date.now() > exp) {
      this.store.delete(key);
      this.expires.delete(key);
    }
  }

  clear(): void {
    this.store.clear();
    this.expires.clear();
  }
}

// Usage in tests
describe("Service with mock Redis", () => {
  const mockRedis = new MockRedis();

  beforeEach(() => {
    mockRedis.clear();
  });

  test("caches user data", async () => {
    // Inject mock
    const service = new UserService(mockRedis as any);

    await service.cacheUser({ id: "123", name: "Test" });

    const cached = await mockRedis.get("user:123");
    expect(JSON.parse(cached!)).toEqual({ id: "123", name: "Test" });
  });
});
```

---

## Integration Test Patterns

### Testing with Real Redis

```typescript
// integration.test.ts
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { redis } from "bun";

describe("Integration tests", () => {
  const testId = Date.now();

  beforeAll(async () => {
    // Verify Redis is available
    try {
      await redis.send("PING", []);
    } catch (error) {
      throw new Error("Redis not available. Start Redis before running integration tests.");
    }
  });

  afterAll(async () => {
    // Cleanup all test keys
    let cursor = "0";
    do {
      const [newCursor, keys] = await redis.send("SCAN", [
        cursor, "MATCH", `test:${testId}:*`, "COUNT", "100"
      ]) as [string, string[]];
      cursor = newCursor;
      if (keys.length > 0) {
        await redis.send("DEL", keys);
      }
    } while (cursor !== "0");
  });

  test("full workflow", async () => {
    const prefix = `test:${testId}:workflow`;

    // Create user
    await redis.hmset(`${prefix}:user:1`, [
      "name", "Alice",
      "email", "alice@test.com"
    ]);

    // Add to user set
    await redis.sadd(`${prefix}:users`, "1");

    // Increment counter
    await redis.incr(`${prefix}:user_count`);

    // Verify
    const name = await redis.hget(`${prefix}:user:1`, "name");
    const users = await redis.smembers(`${prefix}:users`);
    const count = await redis.get(`${prefix}:user_count`);

    expect(name).toBe("Alice");
    expect(users).toContain("1");
    expect(count).toBe("1");
  });
});
```

### Concurrent Operation Tests

```typescript
describe("Concurrent operations", () => {
  const helper = new RedisTestHelper("concurrent");

  afterEach(async () => {
    await helper.cleanup();
  });

  test("atomic counter under concurrency", async () => {
    const key = helper.key("counter");
    const iterations = 100;

    await redis.set(key, "0");

    // Run concurrent increments
    await Promise.all(
      Array.from({ length: iterations }, () => redis.incr(key))
    );

    const final = await redis.get(key);
    expect(parseInt(final!, 10)).toBe(iterations);
  });

  test("lock prevents concurrent access", async () => {
    const lockKey = helper.key("lock");
    const dataKey = helper.key("data");
    const results: string[] = [];

    await redis.set(dataKey, "0");

    async function criticalSection(id: string): Promise<void> {
      const token = crypto.randomUUID();

      // Try to acquire lock with retry
      let acquired = false;
      for (let i = 0; i < 50 && !acquired; i++) {
        const result = await redis.send("SET", [lockKey, token, "NX", "PX", "5000"]);
        acquired = result === "OK";
        if (!acquired) await Bun.sleep(10);
      }

      if (!acquired) {
        results.push(`${id}:failed`);
        return;
      }

      try {
        // Critical section
        const current = parseInt(await redis.get(dataKey) || "0", 10);
        await Bun.sleep(5);  // Simulate work
        await redis.set(dataKey, (current + 1).toString());
        results.push(`${id}:success`);
      } finally {
        // Release lock
        await redis.send("EVAL", [
          `if redis.call("GET", KEYS[1]) == ARGV[1] then return redis.call("DEL", KEYS[1]) end return 0`,
          "1", lockKey, token
        ]);
      }
    }

    // Run concurrent operations
    await Promise.all([
      criticalSection("A"),
      criticalSection("B"),
      criticalSection("C"),
    ]);

    const finalValue = parseInt(await redis.get(dataKey) || "0", 10);
    const successes = results.filter(r => r.includes("success")).length;

    expect(finalValue).toBe(successes);
  });
});
```

---

## Best Practices

1. **Use unique prefixes** - Prevent test interference
2. **Clean up after tests** - Don't leave test data
3. **Test edge cases** - Null values, expiration, concurrency
4. **Mock for unit tests** - Use real Redis for integration
5. **Test Lua scripts separately** - They're complex logic
6. **Use short TTLs in tests** - Don't wait too long
7. **Verify cleanup in CI** - Tests should be isolated
