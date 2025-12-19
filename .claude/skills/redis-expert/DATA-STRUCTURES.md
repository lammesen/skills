# Redis Data Structures Reference

Complete reference for Redis data structures using Bun.redis client.

---

## Strings

The most basic Redis data type. Can hold text, serialized objects, or binary data up to 512MB.

### Basic Operations

```typescript
// Set and get
await redis.set("key", "value");
const value = await redis.get("key");                    // "value"
const buffer = await redis.getBuffer("key");             // Uint8Array

// Delete
await redis.del("key");                                  // 1 (deleted count)
await redis.del("key1", "key2", "key3");                 // Delete multiple

// Check existence
const exists = await redis.exists("key");                // 1 or 0
const count = await redis.exists("k1", "k2", "k3");      // Count of existing
```

### Expiration

```typescript
// Set with TTL
await redis.set("session", "data");
await redis.expire("session", 3600);                     // Expire in 1 hour

// Set with expiration in one command
await redis.send("SETEX", ["session", "3600", "data"]);  // Seconds
await redis.send("PSETEX", ["session", "3600000", "data"]); // Milliseconds

// Set only if not exists
await redis.send("SETNX", ["lock", "holder"]);           // Returns 1 if set, 0 if exists

// Set with options (NX, XX, EX, PX, EXAT, PXAT, KEEPTTL, GET)
await redis.send("SET", ["key", "value", "NX", "EX", "60"]); // Only if not exists, 60s TTL
await redis.send("SET", ["key", "value", "XX", "KEEPTTL"]);  // Only if exists, keep TTL

// Get TTL
const ttl = await redis.ttl("key");                      // Seconds (-1 = no expire, -2 = not exists)
const pttl = await redis.send("PTTL", ["key"]);          // Milliseconds

// Remove expiration
await redis.send("PERSIST", ["key"]);

// Set expiration time
await redis.send("EXPIREAT", ["key", "1703001234"]);     // Unix timestamp
await redis.send("PEXPIREAT", ["key", "1703001234000"]); // Unix timestamp in ms
```

### Atomic Counters

```typescript
// Increment/Decrement
await redis.set("counter", "0");
await redis.incr("counter");                             // 1
await redis.decr("counter");                             // 0
await redis.send("INCRBY", ["counter", "5"]);            // 5
await redis.send("DECRBY", ["counter", "3"]);            // 2
await redis.send("INCRBYFLOAT", ["counter", "1.5"]);     // "3.5"
```

### Bulk Operations

```typescript
// Multiple set/get
await redis.send("MSET", ["k1", "v1", "k2", "v2", "k3", "v3"]);
const values = await redis.send("MGET", ["k1", "k2", "k3"]); // ["v1", "v2", "v3"]

// Conditional multiple set
await redis.send("MSETNX", ["k1", "v1", "k2", "v2"]);    // Only if NONE exist
```

### String Manipulation

```typescript
// Append
await redis.send("APPEND", ["key", " suffix"]);          // Returns new length

// Get/Set range
await redis.send("GETRANGE", ["key", "0", "4"]);         // Substring
await redis.send("SETRANGE", ["key", "6", "world"]);     // Replace at offset

// Length
await redis.send("STRLEN", ["key"]);                     // String length
```

---

## Hashes

Hash maps containing field-value pairs. Ideal for representing objects.

### Basic Operations

```typescript
// Set fields
await redis.hmset("user:123", [
  "name", "Alice",
  "email", "alice@example.com",
  "visits", "0"
]);

// Alternative: Set single field
await redis.send("HSET", ["user:123", "name", "Alice"]);
await redis.send("HSET", ["user:123", "name", "Alice", "email", "alice@example.com"]);

// Get fields
const name = await redis.hget("user:123", "name");                    // "Alice"
const fields = await redis.hmget("user:123", ["name", "email"]);      // ["Alice", "alice@example.com"]
const all = await redis.send("HGETALL", ["user:123"]);                // ["name", "Alice", "email", "..."]

// Convert HGETALL to object
function hgetallToObject(arr: string[]): Record<string, string> {
  const obj: Record<string, string> = {};
  for (let i = 0; i < arr.length; i += 2) {
    obj[arr[i]] = arr[i + 1];
  }
  return obj;
}
```

### Field Operations

```typescript
// Check field exists
await redis.send("HEXISTS", ["user:123", "name"]);       // 1 or 0

// Delete fields
await redis.send("HDEL", ["user:123", "email"]);         // Delete one
await redis.send("HDEL", ["user:123", "f1", "f2"]);      // Delete multiple

// Get all fields/values
await redis.send("HKEYS", ["user:123"]);                 // ["name", "email", ...]
await redis.send("HVALS", ["user:123"]);                 // ["Alice", "alice@...", ...]
await redis.send("HLEN", ["user:123"]);                  // Field count
```

### Atomic Operations

```typescript
// Increment numeric field
await redis.hincrby("user:123", "visits", 1);            // Returns new value
await redis.hincrbyfloat("user:123", "score", 0.5);      // Float increment

// Set only if field not exists
await redis.send("HSETNX", ["user:123", "created", Date.now().toString()]);
```

### Scanning

```typescript
// Iterate hash fields (production-safe)
let cursor = "0";
do {
  const [newCursor, fields] = await redis.send("HSCAN", [
    "user:123", cursor, "MATCH", "*", "COUNT", "100"
  ]) as [string, string[]];
  cursor = newCursor;
  // Process fields in pairs: [field1, value1, field2, value2, ...]
} while (cursor !== "0");
```

---

## Lists

Ordered collections of strings. Efficient for queues and stacks.

### Push/Pop Operations

```typescript
// Add elements
await redis.send("RPUSH", ["queue", "task1", "task2", "task3"]); // Add to tail
await redis.send("LPUSH", ["queue", "urgent"]);                   // Add to head

// Remove elements
const first = await redis.send("LPOP", ["queue"]);               // Remove from head (FIFO)
const last = await redis.send("RPOP", ["queue"]);                // Remove from tail (LIFO)

// Pop multiple
await redis.send("LPOP", ["queue", "3"]);                        // Pop 3 from head
await redis.send("RPOP", ["queue", "3"]);                        // Pop 3 from tail

// Move between lists
await redis.send("LMOVE", ["src", "dst", "RIGHT", "LEFT"]);      // Atomic move
await redis.send("RPOPLPUSH", ["src", "dst"]);                   // Legacy (use LMOVE)
```

### Access Operations

```typescript
// Get range (0-indexed, -1 = last)
const all = await redis.send("LRANGE", ["queue", "0", "-1"]);    // Get all
const first3 = await redis.send("LRANGE", ["queue", "0", "2"]);  // First 3

// Get by index
const item = await redis.send("LINDEX", ["queue", "0"]);         // First item
const last = await redis.send("LINDEX", ["queue", "-1"]);        // Last item

// Length
const len = await redis.send("LLEN", ["queue"]);

// Set by index
await redis.send("LSET", ["queue", "0", "new-first"]);
```

### Trimming

```typescript
// Keep only first N elements
await redis.send("LTRIM", ["queue", "0", "99"]);                 // Keep first 100

// Keep only last N elements
await redis.send("LTRIM", ["queue", "-100", "-1"]);              // Keep last 100
```

### Blocking Operations

```typescript
// Block until element available (for workers)
const result = await redis.send("BLPOP", ["queue", "30"]);       // Block 30 seconds
// Returns: ["queue", "value"] or null on timeout

// Block pop from multiple queues (priority)
const result = await redis.send("BLPOP", ["high", "medium", "low", "10"]);

// Block move
await redis.send("BLMOVE", ["src", "dst", "RIGHT", "LEFT", "30"]);
```

### Insert Operations

```typescript
// Insert before/after pivot
await redis.send("LINSERT", ["list", "BEFORE", "pivot", "new"]);
await redis.send("LINSERT", ["list", "AFTER", "pivot", "new"]);

// Remove elements by value
await redis.send("LREM", ["list", "0", "value"]);   // Remove all occurrences
await redis.send("LREM", ["list", "2", "value"]);   // Remove first 2 from head
await redis.send("LREM", ["list", "-2", "value"]);  // Remove first 2 from tail

// Get and remove element by index
await redis.send("LPOS", ["list", "value"]);        // Find position
```

---

## Sets

Unordered collections of unique strings.

### Basic Operations

```typescript
// Add members
await redis.sadd("tags", "redis");
await redis.sadd("tags", "database", "cache", "nosql");          // Multiple

// Remove members
await redis.srem("tags", "cache");
await redis.srem("tags", "a", "b", "c");                         // Multiple

// Get all members
const members = await redis.smembers("tags");                    // Unordered array

// Check membership
const isMember = await redis.sismember("tags", "redis");         // 1 or 0
const areMembers = await redis.send("SMISMEMBER", ["tags", "redis", "mysql"]); // [1, 0]

// Count
const count = await redis.send("SCARD", ["tags"]);
```

### Random Operations

```typescript
// Get random members (non-destructive)
const one = await redis.srandmember("tags");                     // One random
const three = await redis.srandmember("tags", 3);                // Three random (may repeat if negative)

// Pop random members (destructive)
const popped = await redis.spop("tags");                         // Pop one
const poppedMany = await redis.spop("tags", 3);                  // Pop three
```

### Set Operations

```typescript
// Intersection
const common = await redis.send("SINTER", ["set1", "set2"]);
await redis.send("SINTERSTORE", ["dest", "set1", "set2"]);       // Store result

// Union
const all = await redis.send("SUNION", ["set1", "set2", "set3"]);
await redis.send("SUNIONSTORE", ["dest", "set1", "set2"]);       // Store result

// Difference (in set1 but not set2)
const diff = await redis.send("SDIFF", ["set1", "set2"]);
await redis.send("SDIFFSTORE", ["dest", "set1", "set2"]);        // Store result

// Cardinality of intersection (without computing full set)
const count = await redis.send("SINTERCARD", ["2", "set1", "set2", "LIMIT", "100"]);
```

### Move Between Sets

```typescript
await redis.send("SMOVE", ["src", "dst", "member"]);
```

### Scanning

```typescript
let cursor = "0";
do {
  const [newCursor, members] = await redis.send("SSCAN", [
    "tags", cursor, "MATCH", "redis*", "COUNT", "100"
  ]) as [string, string[]];
  cursor = newCursor;
  // Process members
} while (cursor !== "0");
```

---

## Sorted Sets

Sets where each member has an associated score for ordering.

### Basic Operations

```typescript
// Add members with scores
await redis.send("ZADD", ["leaderboard", "100", "player1", "85", "player2", "92", "player3"]);

// Add with options
await redis.send("ZADD", ["lb", "NX", "100", "p1"]);  // Only if not exists
await redis.send("ZADD", ["lb", "XX", "110", "p1"]); // Only if exists
await redis.send("ZADD", ["lb", "GT", "120", "p1"]); // Only if new > current
await redis.send("ZADD", ["lb", "LT", "80", "p1"]);  // Only if new < current

// Get score
const score = await redis.send("ZSCORE", ["leaderboard", "player1"]); // "100"

// Get rank (0-indexed)
const rank = await redis.send("ZRANK", ["leaderboard", "player1"]);     // Low to high
const revRank = await redis.send("ZREVRANK", ["leaderboard", "player1"]); // High to low

// Count
const count = await redis.send("ZCARD", ["leaderboard"]);
```

### Score Operations

```typescript
// Increment score
await redis.send("ZINCRBY", ["leaderboard", "5", "player1"]);    // Add 5 points

// Count by score range
await redis.send("ZCOUNT", ["leaderboard", "50", "100"]);        // Score between 50-100
await redis.send("ZCOUNT", ["leaderboard", "(50", "100"]);       // Exclusive lower bound
await redis.send("ZCOUNT", ["leaderboard", "-inf", "+inf"]);     // All

// Get multiple scores
await redis.send("ZMSCORE", ["leaderboard", "p1", "p2", "p3"]);
```

### Range Queries

```typescript
// By rank (position)
await redis.send("ZRANGE", ["leaderboard", "0", "9"]);           // Top 10 (low to high)
await redis.send("ZRANGE", ["leaderboard", "0", "9", "REV"]);    // Top 10 (high to low)
await redis.send("ZRANGE", ["leaderboard", "0", "9", "REV", "WITHSCORES"]); // With scores

// Legacy commands (still work)
await redis.send("ZREVRANGE", ["leaderboard", "0", "9", "WITHSCORES"]);

// By score
await redis.send("ZRANGE", ["leaderboard", "50", "100", "BYSCORE"]);
await redis.send("ZRANGE", ["leaderboard", "(50", "100", "BYSCORE"]);        // Exclusive
await redis.send("ZRANGE", ["leaderboard", "100", "50", "BYSCORE", "REV"]);  // Descending

// By lex (when all scores equal)
await redis.send("ZRANGE", ["myset", "[a", "[m", "BYLEX"]);

// With offset and limit
await redis.send("ZRANGE", ["leaderboard", "0", "100", "BYSCORE", "LIMIT", "0", "10"]);
```

### Remove Operations

```typescript
// Remove by member
await redis.send("ZREM", ["leaderboard", "player1"]);
await redis.send("ZREM", ["leaderboard", "p1", "p2", "p3"]);     // Multiple

// Remove by rank
await redis.send("ZREMRANGEBYRANK", ["leaderboard", "0", "9"]);  // Remove bottom 10

// Remove by score
await redis.send("ZREMRANGEBYSCORE", ["leaderboard", "-inf", "50"]); // Remove score <= 50

// Pop min/max
await redis.send("ZPOPMIN", ["leaderboard", "1"]);               // Remove lowest
await redis.send("ZPOPMAX", ["leaderboard", "1"]);               // Remove highest
await redis.send("BZPOPMIN", ["leaderboard", "30"]);             // Blocking pop
```

### Set Operations

```typescript
// Union
await redis.send("ZUNIONSTORE", ["dest", "2", "zset1", "zset2"]);
await redis.send("ZUNIONSTORE", ["dest", "2", "zset1", "zset2", "WEIGHTS", "1", "2"]);
await redis.send("ZUNIONSTORE", ["dest", "2", "zset1", "zset2", "AGGREGATE", "MAX"]);

// Intersection
await redis.send("ZINTERSTORE", ["dest", "2", "zset1", "zset2"]);

// Difference (Redis 6.2+)
await redis.send("ZDIFFSTORE", ["dest", "2", "zset1", "zset2"]);
```

---

## Streams

Append-only log data structure for event sourcing and messaging.

### Adding Entries

```typescript
// Auto-generate ID
const id = await redis.send("XADD", ["events", "*", "type", "purchase", "amount", "99.99"]);
// Returns: "1703001234567-0"

// With max length (capped stream)
await redis.send("XADD", ["events", "MAXLEN", "~", "10000", "*", "type", "event"]);
// ~ means approximate (more efficient)

// Custom ID (must be greater than last)
await redis.send("XADD", ["events", "1703001234567-0", "type", "event"]);
```

### Reading Entries

```typescript
// Read from beginning
const entries = await redis.send("XREAD", ["COUNT", "10", "STREAMS", "events", "0"]);

// Read new entries only
const newEntries = await redis.send("XREAD", ["BLOCK", "5000", "STREAMS", "events", "$"]);

// Read from multiple streams
await redis.send("XREAD", [
  "COUNT", "10",
  "STREAMS", "events1", "events2",
  "0", "0"
]);

// Get range
await redis.send("XRANGE", ["events", "-", "+"]);                // All entries
await redis.send("XRANGE", ["events", "1703001234567-0", "+"]);  // From ID
await redis.send("XREVRANGE", ["events", "+", "-", "COUNT", "10"]); // Last 10
```

### Consumer Groups

```typescript
// Create consumer group
await redis.send("XGROUP", ["CREATE", "events", "workers", "$", "MKSTREAM"]);
// $ = start from new entries, 0 = from beginning

// Read as consumer
const messages = await redis.send("XREADGROUP", [
  "GROUP", "workers", "worker1",
  "COUNT", "10",
  "BLOCK", "5000",
  "STREAMS", "events", ">"
]);
// > means undelivered messages

// Acknowledge processing
await redis.send("XACK", ["events", "workers", "1703001234567-0"]);

// Read pending messages (already delivered but not ACKed)
const pending = await redis.send("XREADGROUP", [
  "GROUP", "workers", "worker1",
  "STREAMS", "events", "0"
]);
```

### Managing Consumer Groups

```typescript
// List groups
await redis.send("XINFO", ["GROUPS", "events"]);

// List consumers in group
await redis.send("XINFO", ["CONSUMERS", "events", "workers"]);

// Pending entries summary
await redis.send("XPENDING", ["events", "workers"]);

// Pending entries detail
await redis.send("XPENDING", ["events", "workers", "-", "+", "10"]);

// Claim idle messages (for failover)
await redis.send("XCLAIM", [
  "events", "workers", "worker2",
  "60000",  // Min idle time (ms)
  "1703001234567-0"
]);

// Auto-claim idle messages
await redis.send("XAUTOCLAIM", [
  "events", "workers", "worker2",
  "60000", "0-0", "COUNT", "10"
]);

// Delete consumer
await redis.send("XGROUP", ["DELCONSUMER", "events", "workers", "worker1"]);

// Delete group
await redis.send("XGROUP", ["DESTROY", "events", "workers"]);
```

### Stream Info

```typescript
// Stream length
await redis.send("XLEN", ["events"]);

// Stream info
await redis.send("XINFO", ["STREAM", "events"]);
await redis.send("XINFO", ["STREAM", "events", "FULL", "COUNT", "10"]);

// Trim stream
await redis.send("XTRIM", ["events", "MAXLEN", "~", "1000"]);
await redis.send("XTRIM", ["events", "MINID", "~", "1703001234567-0"]);

// Delete specific entries
await redis.send("XDEL", ["events", "1703001234567-0", "1703001234568-0"]);
```

---

## Bitmaps

Strings treated as bit arrays. Efficient for boolean data.

### Basic Operations

```typescript
// Set individual bits
await redis.send("SETBIT", ["active:2024-01-15", "1234", "1"]);  // User 1234 active
await redis.send("SETBIT", ["active:2024-01-15", "5678", "1"]);  // User 5678 active

// Get bit
const isActive = await redis.send("GETBIT", ["active:2024-01-15", "1234"]); // 1 or 0

// Count set bits
const activeCount = await redis.send("BITCOUNT", ["active:2024-01-15"]);

// Count bits in range (bytes, not bits!)
await redis.send("BITCOUNT", ["active:2024-01-15", "0", "100"]);
```

### Bitwise Operations

```typescript
// AND - users active on both days
await redis.send("BITOP", ["AND", "active:both", "active:day1", "active:day2"]);

// OR - users active on either day
await redis.send("BITOP", ["OR", "active:any", "active:day1", "active:day2"]);

// XOR - users active on exactly one day
await redis.send("BITOP", ["XOR", "active:xor", "active:day1", "active:day2"]);

// NOT - inverse
await redis.send("BITOP", ["NOT", "inactive:day1", "active:day1"]);
```

### Finding Bits

```typescript
// Find first bit with value
await redis.send("BITPOS", ["active:2024-01-15", "1"]);      // First set bit
await redis.send("BITPOS", ["active:2024-01-15", "0"]);      // First unset bit
await redis.send("BITPOS", ["active:2024-01-15", "1", "100"]); // Starting from byte 100
```

---

## HyperLogLog

Probabilistic data structure for cardinality estimation (0.81% error, 12KB max).

```typescript
// Add elements
await redis.send("PFADD", ["visitors:today", "user1", "user2", "user3"]);
await redis.send("PFADD", ["visitors:today", "user1"]);  // Duplicate ignored

// Count unique (approximate)
const count = await redis.send("PFCOUNT", ["visitors:today"]);  // ~3

// Count across multiple
await redis.send("PFCOUNT", ["visitors:mon", "visitors:tue", "visitors:wed"]);

// Merge HLLs
await redis.send("PFMERGE", ["visitors:week", "visitors:mon", "visitors:tue", "visitors:wed"]);
```

---

## Geospatial

Location-based indexing using sorted sets internally.

### Adding Locations

```typescript
// Add locations (longitude, latitude, name)
await redis.send("GEOADD", ["locations", "-122.4194", "37.7749", "San Francisco"]);
await redis.send("GEOADD", ["locations", "-73.9857", "40.7484", "New York"]);
await redis.send("GEOADD", ["locations",
  "-118.2437", "34.0522", "Los Angeles",
  "-87.6298", "41.8781", "Chicago"
]);
```

### Querying

```typescript
// Get position
const pos = await redis.send("GEOPOS", ["locations", "San Francisco"]);
// Returns: [[-122.4194, 37.7749]]

// Get geohash
const hash = await redis.send("GEOHASH", ["locations", "San Francisco"]);

// Calculate distance
const dist = await redis.send("GEODIST", ["locations", "San Francisco", "New York", "km"]);
// Units: m, km, mi, ft

// Search by radius from member
await redis.send("GEOSEARCH", [
  "locations",
  "FROMMEMBER", "San Francisco",
  "BYRADIUS", "500", "km",
  "WITHCOORD", "WITHDIST",
  "ASC", "COUNT", "10"
]);

// Search by radius from coordinates
await redis.send("GEOSEARCH", [
  "locations",
  "FROMLONLAT", "-122.4194", "37.7749",
  "BYRADIUS", "100", "km"
]);

// Search by box
await redis.send("GEOSEARCH", [
  "locations",
  "FROMLONLAT", "-122.4194", "37.7749",
  "BYBOX", "400", "400", "km"
]);

// Store search results
await redis.send("GEOSEARCHSTORE", [
  "nearby", "locations",
  "FROMMEMBER", "San Francisco",
  "BYRADIUS", "100", "km"
]);
```

---

## Key Management

### Key Operations

```typescript
// Check existence
const exists = await redis.exists("key");

// Get type
const type = await redis.send("TYPE", ["key"]);  // string, list, set, zset, hash, stream

// Rename
await redis.send("RENAME", ["oldkey", "newkey"]);
await redis.send("RENAMENX", ["oldkey", "newkey"]);  // Only if newkey doesn't exist

// Copy
await redis.send("COPY", ["src", "dst"]);
await redis.send("COPY", ["src", "dst", "REPLACE"]);  // Replace if exists

// Dump and restore (for migration)
const dump = await redis.send("DUMP", ["key"]);
await redis.send("RESTORE", ["newkey", "0", dump]);
```

### Scanning Keys

```typescript
// NEVER use KEYS in production - use SCAN instead
let cursor = "0";
const allKeys: string[] = [];
do {
  const [newCursor, keys] = await redis.send("SCAN", [
    cursor, "MATCH", "user:*", "COUNT", "100"
  ]) as [string, string[]];
  cursor = newCursor;
  allKeys.push(...keys);
} while (cursor !== "0");
```

### Memory Usage

```typescript
// Get memory usage of a key
const bytes = await redis.send("MEMORY", ["USAGE", "mykey"]);

// Debug object info
await redis.send("DEBUG", ["OBJECT", "mykey"]);

// Object encoding
await redis.send("OBJECT", ["ENCODING", "mykey"]);
```
