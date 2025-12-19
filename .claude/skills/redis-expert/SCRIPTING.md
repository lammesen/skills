# Redis Lua Scripting Reference

Atomic operations with Lua scripts for complex Redis workflows.

---

## Lua Scripting Fundamentals

### Why Lua Scripts?

- **Atomicity**: Script executes as single atomic operation
- **Performance**: Reduces network round-trips
- **Complex Logic**: Conditional operations, loops, calculations
- **Consistency**: No race conditions between commands

### Basic EVAL

```typescript
import { redis } from "bun";

// Basic script execution
const result = await redis.send("EVAL", [
  `return redis.call("GET", KEYS[1])`,
  "1",           // Number of keys
  "mykey"        // KEYS[1]
]);

// With arguments
await redis.send("EVAL", [
  `return redis.call("SET", KEYS[1], ARGV[1])`,
  "1",           // Number of keys
  "mykey",       // KEYS[1]
  "myvalue"      // ARGV[1]
]);

// Multiple keys and arguments
await redis.send("EVAL", [
  `
    redis.call("SET", KEYS[1], ARGV[1])
    redis.call("SET", KEYS[2], ARGV[2])
    return "OK"
  `,
  "2",           // Number of keys
  "key1",        // KEYS[1]
  "key2",        // KEYS[2]
  "value1",      // ARGV[1]
  "value2"       // ARGV[2]
]);
```

### Script Caching with EVALSHA

```typescript
// Load script and get SHA1 hash
const sha = await redis.send("SCRIPT", ["LOAD", `
  local current = redis.call("GET", KEYS[1])
  return current
`]) as string;

// Execute cached script by SHA
await redis.send("EVALSHA", [sha, "1", "mykey"]);

// Check if script exists
const [exists] = await redis.send("SCRIPT", ["EXISTS", sha]) as number[];

// Flush all scripts
await redis.send("SCRIPT", ["FLUSH"]);

// Kill running script (if taking too long)
await redis.send("SCRIPT", ["KILL"]);
```

---

## Lua Syntax for Redis

### Redis Commands

```lua
-- Call Redis commands
redis.call("SET", "key", "value")        -- Raises error on failure
redis.pcall("SET", "key", "value")       -- Returns error object on failure

-- Get values
local value = redis.call("GET", "key")

-- Multiple commands
redis.call("MULTI")
redis.call("SET", "k1", "v1")
redis.call("SET", "k2", "v2")
redis.call("EXEC")
```

### Variables and Types

```lua
-- Variables
local count = 0
local name = "test"
local flag = true
local nothing = nil

-- Type conversion
local num = tonumber("42")               -- String to number
local str = tostring(42)                 -- Number to string

-- Get type
type(value)                              -- "string", "number", "table", "nil"
```

### Tables (Arrays and Objects)

```lua
-- Array (1-indexed!)
local arr = {"a", "b", "c"}
arr[1]                                   -- "a" (not arr[0]!)
#arr                                     -- 3 (length)

-- Object/Map
local obj = {name = "test", count = 42}
obj.name                                 -- "test"
obj["name"]                              -- "test"

-- Iterate array
for i, v in ipairs(arr) do
  -- i = index, v = value
end

-- Iterate object
for k, v in pairs(obj) do
  -- k = key, v = value
end
```

### Control Flow

```lua
-- If/else
if value == nil then
  return 0
elseif value > 100 then
  return 100
else
  return value
end

-- While loop
local i = 0
while i < 10 do
  i = i + 1
end

-- For loop
for i = 1, 10 do
  -- i goes from 1 to 10
end

for i = 10, 1, -1 do
  -- i goes from 10 to 1
end
```

### String Operations

```lua
-- Concatenation
local s = "Hello " .. "World"

-- Length
#s                                       -- 11

-- Substring
string.sub(s, 1, 5)                      -- "Hello"

-- Find
string.find(s, "World")                  -- 7

-- Pattern matching
string.match(s, "(%w+)")                 -- "Hello"

-- Replace
string.gsub(s, "World", "Lua")           -- "Hello Lua"
```

### Math Operations

```lua
local a = 10
local b = 3

a + b                                    -- 13
a - b                                    -- 7
a * b                                    -- 30
a / b                                    -- 3.333...
a % b                                    -- 1 (modulo)
a ^ b                                    -- 1000 (power)

math.floor(3.7)                          -- 3
math.ceil(3.2)                           -- 4
math.max(1, 2, 3)                        -- 3
math.min(1, 2, 3)                        -- 1
math.random()                            -- 0-1
math.random(10)                          -- 1-10
```

---

## Common Script Patterns

### Compare and Swap (CAS)

```typescript
const casScript = `
  local key = KEYS[1]
  local expected = ARGV[1]
  local new_value = ARGV[2]

  local current = redis.call("GET", key)

  if current == expected then
    redis.call("SET", key, new_value)
    return 1
  end

  return 0
`;

const success = await redis.send("EVAL", [
  casScript, "1", "mykey", "oldvalue", "newvalue"
]);
```

### Conditional Set with TTL

```typescript
const setIfNotExistsWithTTL = `
  local key = KEYS[1]
  local value = ARGV[1]
  local ttl = tonumber(ARGV[2])

  if redis.call("EXISTS", key) == 0 then
    redis.call("SET", key, value)
    redis.call("EXPIRE", key, ttl)
    return 1
  end

  return 0
`;
```

### Increment with Limit

```typescript
const incrementWithLimit = `
  local key = KEYS[1]
  local increment = tonumber(ARGV[1])
  local max_value = tonumber(ARGV[2])

  local current = tonumber(redis.call("GET", key) or "0")
  local new_value = current + increment

  if new_value > max_value then
    new_value = max_value
  end

  redis.call("SET", key, new_value)
  return new_value
`;

const newValue = await redis.send("EVAL", [
  incrementWithLimit, "1", "counter", "5", "100"
]);
```

### Get or Set (with lazy initialization)

```typescript
const getOrSet = `
  local key = KEYS[1]
  local default_value = ARGV[1]
  local ttl = tonumber(ARGV[2])

  local value = redis.call("GET", key)

  if value == false then
    redis.call("SET", key, default_value)
    if ttl > 0 then
      redis.call("EXPIRE", key, ttl)
    end
    return default_value
  end

  return value
`;
```

### Atomic Counter with Reset

```typescript
const counterWithReset = `
  local key = KEYS[1]
  local reset_threshold = tonumber(ARGV[1])
  local reset_value = tonumber(ARGV[2])

  local current = tonumber(redis.call("INCR", key))

  if current >= reset_threshold then
    redis.call("SET", key, reset_value)
    return reset_value
  end

  return current
`;
```

---

## Distributed Lock Scripts

### Safe Lock Release

```typescript
const releaseLock = `
  local lock_key = KEYS[1]
  local lock_token = ARGV[1]

  -- Only delete if we own the lock
  if redis.call("GET", lock_key) == lock_token then
    return redis.call("DEL", lock_key)
  end

  return 0
`;

async function releaseLockSafe(resource: string, token: string): Promise<boolean> {
  const result = await redis.send("EVAL", [
    releaseLock, "1", `lock:${resource}`, token
  ]);
  return result === 1;
}
```

### Lock Extension

```typescript
const extendLock = `
  local lock_key = KEYS[1]
  local lock_token = ARGV[1]
  local new_ttl_ms = tonumber(ARGV[2])

  if redis.call("GET", lock_key) == lock_token then
    return redis.call("PEXPIRE", lock_key, new_ttl_ms)
  end

  return 0
`;
```

### Acquire Lock with Retry Info

```typescript
const acquireLockWithInfo = `
  local lock_key = KEYS[1]
  local lock_token = ARGV[1]
  local ttl_ms = tonumber(ARGV[2])

  local result = redis.call("SET", lock_key, lock_token, "NX", "PX", ttl_ms)

  if result then
    return {1, 0}  -- Acquired, 0 wait time
  end

  local remaining = redis.call("PTTL", lock_key)
  return {0, remaining}  -- Not acquired, remaining TTL
`;
```

---

## Rate Limiting Scripts

### Sliding Window Rate Limit

```typescript
const slidingWindowRateLimit = `
  local key = KEYS[1]
  local window_ms = tonumber(ARGV[1])
  local limit = tonumber(ARGV[2])
  local now = tonumber(ARGV[3])

  local window_start = now - window_ms

  -- Remove old entries
  redis.call("ZREMRANGEBYSCORE", key, 0, window_start)

  -- Count current window
  local count = redis.call("ZCARD", key)

  if count < limit then
    -- Add new request
    redis.call("ZADD", key, now, now .. "-" .. math.random(1000000))
    redis.call("PEXPIRE", key, window_ms)
    return {1, limit - count - 1}  -- allowed, remaining
  end

  return {0, 0}  -- denied, no remaining
`;

async function checkRateLimit(
  identifier: string,
  windowMs: number,
  limit: number
): Promise<{ allowed: boolean; remaining: number }> {
  const [allowed, remaining] = await redis.send("EVAL", [
    slidingWindowRateLimit,
    "1",
    `ratelimit:${identifier}`,
    windowMs.toString(),
    limit.toString(),
    Date.now().toString()
  ]) as [number, number];

  return { allowed: allowed === 1, remaining };
}
```

### Token Bucket Rate Limit

```typescript
const tokenBucketRateLimit = `
  local key = KEYS[1]
  local capacity = tonumber(ARGV[1])
  local refill_rate = tonumber(ARGV[2])  -- tokens per second
  local tokens_needed = tonumber(ARGV[3])
  local now = tonumber(ARGV[4])

  -- Get current state
  local data = redis.call("HMGET", key, "tokens", "last_refill")
  local tokens = tonumber(data[1]) or capacity
  local last_refill = tonumber(data[2]) or now

  -- Calculate refill
  local elapsed = (now - last_refill) / 1000  -- Convert to seconds
  tokens = math.min(capacity, tokens + elapsed * refill_rate)

  -- Check and consume
  if tokens >= tokens_needed then
    tokens = tokens - tokens_needed
    redis.call("HMSET", key, "tokens", tokens, "last_refill", now)
    redis.call("EXPIRE", key, 3600)
    return {1, math.floor(tokens)}
  end

  -- Update state even if denied
  redis.call("HMSET", key, "tokens", tokens, "last_refill", now)
  redis.call("EXPIRE", key, 3600)

  -- Calculate wait time for next token
  local wait_ms = ((tokens_needed - tokens) / refill_rate) * 1000
  return {0, math.floor(wait_ms)}
`;
```

---

## Hash Operations Scripts

### Hash Increment with Bounds

```typescript
const hashIncrWithBounds = `
  local key = KEYS[1]
  local field = ARGV[1]
  local delta = tonumber(ARGV[2])
  local min_val = tonumber(ARGV[3])
  local max_val = tonumber(ARGV[4])

  local current = tonumber(redis.call("HGET", key, field) or "0")
  local new_val = current + delta

  -- Apply bounds
  if new_val < min_val then new_val = min_val end
  if new_val > max_val then new_val = max_val end

  redis.call("HSET", key, field, new_val)
  return new_val
`;
```

### Hash Set If Greater

```typescript
const hashSetIfGreater = `
  local key = KEYS[1]
  local field = ARGV[1]
  local new_value = tonumber(ARGV[2])

  local current = tonumber(redis.call("HGET", key, field) or "0")

  if new_value > current then
    redis.call("HSET", key, field, new_value)
    return 1
  end

  return 0
`;
```

### Hash Get Multiple with Defaults

```typescript
const hashGetWithDefaults = `
  local key = KEYS[1]
  local results = {}

  for i = 1, #ARGV, 2 do
    local field = ARGV[i]
    local default_val = ARGV[i + 1]

    local value = redis.call("HGET", key, field)
    if value == false then
      table.insert(results, default_val)
    else
      table.insert(results, value)
    end
  end

  return results
`;
```

---

## List Operations Scripts

### List Pop with Minimum Size

```typescript
const listPopWithMinSize = `
  local key = KEYS[1]
  local min_size = tonumber(ARGV[1])

  local current_size = redis.call("LLEN", key)

  if current_size > min_size then
    return redis.call("LPOP", key)
  end

  return nil
`;
```

### Circular Buffer

```typescript
const circularBufferAdd = `
  local key = KEYS[1]
  local value = ARGV[1]
  local max_size = tonumber(ARGV[2])

  -- Add to end
  redis.call("RPUSH", key, value)

  -- Trim from front if over size
  local current_size = redis.call("LLEN", key)
  if current_size > max_size then
    redis.call("LTRIM", key, current_size - max_size, -1)
  end

  return redis.call("LLEN", key)
`;
```

---

## Script Manager Class

```typescript
class ScriptManager {
  private scripts: Map<string, { script: string; sha?: string }> = new Map();

  register(name: string, script: string): void {
    this.scripts.set(name, { script });
  }

  async load(name: string): Promise<string> {
    const entry = this.scripts.get(name);
    if (!entry) throw new Error(`Script not found: ${name}`);

    if (!entry.sha) {
      entry.sha = await redis.send("SCRIPT", ["LOAD", entry.script]) as string;
    }

    return entry.sha;
  }

  async exec(name: string, keys: string[], args: string[]): Promise<any> {
    const sha = await this.load(name);

    try {
      return await redis.send("EVALSHA", [
        sha,
        keys.length.toString(),
        ...keys,
        ...args
      ]);
    } catch (error: any) {
      if (error.message.includes("NOSCRIPT")) {
        // Script was flushed, reload and retry
        const entry = this.scripts.get(name)!;
        entry.sha = undefined;
        return this.exec(name, keys, args);
      }
      throw error;
    }
  }

  async loadAll(): Promise<void> {
    for (const name of this.scripts.keys()) {
      await this.load(name);
    }
  }
}

// Usage
const scripts = new ScriptManager();

scripts.register("cas", `
  if redis.call("GET", KEYS[1]) == ARGV[1] then
    redis.call("SET", KEYS[1], ARGV[2])
    return 1
  end
  return 0
`);

scripts.register("getOrSet", `
  local v = redis.call("GET", KEYS[1])
  if v == false then
    redis.call("SET", KEYS[1], ARGV[1])
    return ARGV[1]
  end
  return v
`);

// Preload all scripts at startup
await scripts.loadAll();

// Execute
const result = await scripts.exec("cas", ["mykey"], ["old", "new"]);
```

---

## Debugging Scripts

### Debug Logging

```lua
-- Use redis.log for debugging (appears in Redis log)
redis.log(redis.LOG_WARNING, "Debug: value = " .. tostring(value))

-- Log levels:
-- redis.LOG_DEBUG
-- redis.LOG_VERBOSE
-- redis.LOG_NOTICE
-- redis.LOG_WARNING
```

### Error Handling

```lua
-- pcall for error handling
local ok, result = pcall(function()
  return redis.call("GET", "nonexistent:key")
end)

if not ok then
  return {err = result}
end

-- Return structured errors
if value == nil then
  return redis.error_reply("Key not found")
end

-- Return status
return redis.status_reply("OK")
```

### Script Debugging Commands

```typescript
// Debug mode (Redis 3.2+)
// Connect with: redis-cli --ldb --eval script.lua key1 key2 , arg1 arg2

// Check script exists
const [exists] = await redis.send("SCRIPT", ["EXISTS", sha]) as number[];

// Get debug info
await redis.send("SCRIPT", ["DEBUG", "YES"]);  // Enable debug mode
await redis.send("SCRIPT", ["DEBUG", "SYNC"]); // Synchronous debug
await redis.send("SCRIPT", ["DEBUG", "NO"]);   // Disable
```

---

## Best Practices

### Do's

1. **Keep scripts small and focused** - One operation per script
2. **Use KEYS and ARGV** - Never hardcode key names
3. **Cache scripts with EVALSHA** - Avoid sending script text repeatedly
4. **Handle nil values** - Redis returns `false` for nil in Lua
5. **Use pcall for external calls** - Handle errors gracefully

### Don'ts

1. **Don't use blocking commands** - BLPOP, BRPOP, etc.
2. **Don't use non-deterministic commands** - TIME, RANDOMKEY
3. **Don't write very long scripts** - Blocks Redis
4. **Don't use global variables** - Always use `local`
5. **Don't modify KEYS/ARGV tables** - They're read-only

### Performance Tips

```lua
-- Cache frequently used values
local key = KEYS[1]  -- Do this once, not in a loop

-- Avoid unnecessary calls
local exists = redis.call("EXISTS", key)
if exists == 1 then
  -- Only get if exists
  local value = redis.call("GET", key)
end

-- Batch operations when possible
local values = redis.call("MGET", unpack(keys))
```
