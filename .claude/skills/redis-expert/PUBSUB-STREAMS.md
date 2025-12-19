# Redis Pub/Sub and Streams Reference

Real-time messaging patterns using Redis Pub/Sub and Streams.

---

## Pub/Sub Overview

Redis Pub/Sub provides fire-and-forget messaging. Messages are not persisted; if no subscriber is listening, messages are lost.

**Use Cases:**
- Real-time notifications
- Cache invalidation broadcasts
- Live updates (chat, presence)
- Event broadcasting

**Limitations:**
- No message persistence
- No acknowledgments
- At-most-once delivery
- Cannot replay messages

---

## Basic Pub/Sub

### Publisher

```typescript
import { redis } from "bun";

// Publish message
await redis.publish("events", JSON.stringify({
  type: "user.created",
  userId: "123",
  timestamp: Date.now()
}));

// Publish returns number of subscribers who received the message
const subscribers = await redis.publish("notifications", "Hello!");
console.log(`Message sent to ${subscribers} subscribers`);
```

### Subscriber

```typescript
import { RedisClient } from "bun";

// Create dedicated connection for subscribing
// (subscribed connections can only receive messages, not send commands)
const subscriber = new RedisClient();
await subscriber.connect();

// Subscribe to channel
await subscriber.subscribe("events", (message, channel) => {
  const event = JSON.parse(message);
  console.log(`[${channel}] Event:`, event);
});

// Subscribe to multiple channels
await subscriber.subscribe("channel1", handler);
await subscriber.subscribe("channel2", handler);

// Unsubscribe
await subscriber.unsubscribe("events");
```

### Pattern Subscriptions

```typescript
// Subscribe to pattern
await subscriber.send("PSUBSCRIBE", ["user.*"]);

// This will receive messages from:
// - user.created
// - user.updated
// - user.deleted
// etc.

// Unsubscribe from pattern
await subscriber.send("PUNSUBSCRIBE", ["user.*"]);
```

---

## Pub/Sub Patterns

### Event Bus

```typescript
import { RedisClient } from "bun";

type EventHandler = (event: any) => void | Promise<void>;

class EventBus {
  private publisher: RedisClient;
  private subscriber: RedisClient;
  private handlers: Map<string, Set<EventHandler>> = new Map();
  private connected = false;

  constructor(redisUrl?: string) {
    this.publisher = new RedisClient(redisUrl);
    this.subscriber = new RedisClient(redisUrl);
  }

  async connect(): Promise<void> {
    if (this.connected) return;

    await this.publisher.connect();
    await this.subscriber.connect();
    this.connected = true;
  }

  async subscribe(channel: string, handler: EventHandler): Promise<void> {
    if (!this.handlers.has(channel)) {
      this.handlers.set(channel, new Set());

      await this.subscriber.subscribe(channel, async (message) => {
        const event = JSON.parse(message);
        const handlers = this.handlers.get(channel);

        if (handlers) {
          for (const h of handlers) {
            try {
              await h(event);
            } catch (error) {
              console.error(`Handler error for ${channel}:`, error);
            }
          }
        }
      });
    }

    this.handlers.get(channel)!.add(handler);
  }

  unsubscribe(channel: string, handler: EventHandler): void {
    const handlers = this.handlers.get(channel);
    if (handlers) {
      handlers.delete(handler);
      if (handlers.size === 0) {
        this.subscriber.unsubscribe(channel);
        this.handlers.delete(channel);
      }
    }
  }

  async publish(channel: string, event: any): Promise<number> {
    return await this.publisher.publish(channel, JSON.stringify(event));
  }

  close(): void {
    this.publisher.close();
    this.subscriber.close();
    this.connected = false;
  }
}

// Usage
const bus = new EventBus();
await bus.connect();

bus.subscribe("orders", (event) => {
  console.log("Order event:", event);
});

await bus.publish("orders", { type: "created", orderId: "123" });
```

### Cache Invalidation

```typescript
class CacheInvalidator {
  private subscriber: RedisClient;
  private localCache: Map<string, any> = new Map();

  constructor() {
    this.subscriber = new RedisClient();
  }

  async start(): Promise<void> {
    await this.subscriber.connect();

    await this.subscriber.subscribe("cache:invalidate", (message) => {
      const { pattern, keys } = JSON.parse(message);

      if (keys) {
        // Invalidate specific keys
        for (const key of keys) {
          this.localCache.delete(key);
        }
      } else if (pattern) {
        // Invalidate by pattern
        const regex = new RegExp(pattern.replace("*", ".*"));
        for (const key of this.localCache.keys()) {
          if (regex.test(key)) {
            this.localCache.delete(key);
          }
        }
      }
    });
  }

  // Call this when data changes
  static async broadcast(keys: string[]): Promise<void> {
    const { redis } = await import("bun");
    await redis.publish("cache:invalidate", JSON.stringify({ keys }));
  }

  static async broadcastPattern(pattern: string): Promise<void> {
    const { redis } = await import("bun");
    await redis.publish("cache:invalidate", JSON.stringify({ pattern }));
  }
}
```

### Real-Time Notifications

```typescript
import { Elysia } from "elysia";
import { RedisClient } from "bun";

const app = new Elysia()
  .ws("/notifications/:userId", {
    async open(ws) {
      const { userId } = ws.data.params;

      // Create subscriber for this user
      const subscriber = new RedisClient();
      await subscriber.connect();

      // Store subscriber reference for cleanup
      (ws as any).subscriber = subscriber;

      // Subscribe to user's notification channel
      await subscriber.subscribe(`notifications:${userId}`, (message) => {
        ws.send(message);
      });

      // Also subscribe to broadcast channel
      await subscriber.subscribe("notifications:broadcast", (message) => {
        ws.send(message);
      });
    },

    close(ws) {
      const subscriber = (ws as any).subscriber as RedisClient;
      if (subscriber) {
        subscriber.close();
      }
    }
  });

// Send notification to specific user
async function notifyUser(userId: string, notification: any): Promise<void> {
  const { redis } = await import("bun");
  await redis.publish(`notifications:${userId}`, JSON.stringify(notification));
}

// Broadcast to all users
async function broadcast(notification: any): Promise<void> {
  const { redis } = await import("bun");
  await redis.publish("notifications:broadcast", JSON.stringify(notification));
}
```

---

## Streams Overview

Redis Streams provide persistent, replayable message logs with consumer groups for distributed processing.

**Use Cases:**
- Event sourcing
- Message queues with acknowledgment
- Activity feeds
- Log aggregation
- Real-time analytics

**Advantages over Pub/Sub:**
- Message persistence
- Message acknowledgment
- Consumer groups for load balancing
- Message replay
- At-least-once delivery

---

## Basic Streams

### Adding Messages

```typescript
import { redis } from "bun";

// Add message with auto-generated ID
const id = await redis.send("XADD", [
  "events",              // Stream name
  "*",                   // Auto-generate ID
  "type", "purchase",    // Field-value pairs
  "userId", "123",
  "amount", "99.99"
]);
// Returns: "1703001234567-0"

// Add with max length (prevents unbounded growth)
await redis.send("XADD", [
  "events",
  "MAXLEN", "~", "10000",  // ~ = approximate (faster)
  "*",
  "type", "event"
]);

// Add with exact max length
await redis.send("XADD", [
  "events",
  "MAXLEN", "10000",
  "*",
  "type", "event"
]);

// Add with minimum ID trimming
await redis.send("XADD", [
  "events",
  "MINID", "~", "1703001234567-0",
  "*",
  "type", "event"
]);
```

### Reading Messages

```typescript
// Read from beginning
const entries = await redis.send("XREAD", [
  "COUNT", "10",
  "STREAMS", "events",
  "0"  // Start from ID 0 (beginning)
]);

// Read from specific ID
await redis.send("XREAD", [
  "COUNT", "10",
  "STREAMS", "events",
  "1703001234567-0"  // Start after this ID
]);

// Block for new messages
const newEntries = await redis.send("XREAD", [
  "BLOCK", "5000",   // Block for 5 seconds
  "COUNT", "10",
  "STREAMS", "events",
  "$"                // Only new messages
]);

// Read from multiple streams
await redis.send("XREAD", [
  "COUNT", "10",
  "STREAMS", "events", "orders", "payments",
  "0", "0", "0"  // Starting IDs for each stream
]);

// Get range
await redis.send("XRANGE", ["events", "-", "+"]);  // All
await redis.send("XRANGE", ["events", "1703001234567-0", "+", "COUNT", "10"]);

// Get range in reverse
await redis.send("XREVRANGE", ["events", "+", "-", "COUNT", "10"]);
```

### Parsing Stream Results

```typescript
interface StreamEntry {
  id: string;
  fields: Record<string, string>;
}

function parseStreamEntries(result: any): StreamEntry[] {
  if (!result) return [];

  const entries: StreamEntry[] = [];

  // XREAD returns: [[streamName, [[id, [field, value, ...]], ...]]]
  // XRANGE returns: [[id, [field, value, ...]], ...]

  const items = Array.isArray(result[0]?.[1]) ? result[0][1] : result;

  for (const [id, fieldArray] of items) {
    const fields: Record<string, string> = {};
    for (let i = 0; i < fieldArray.length; i += 2) {
      fields[fieldArray[i]] = fieldArray[i + 1];
    }
    entries.push({ id, fields });
  }

  return entries;
}
```

---

## Consumer Groups

Consumer groups enable distributed processing with load balancing and acknowledgment.

### Setup

```typescript
// Create consumer group
async function createConsumerGroup(
  stream: string,
  group: string,
  startId: string = "$"  // $ = only new messages, 0 = from beginning
): Promise<void> {
  try {
    await redis.send("XGROUP", [
      "CREATE", stream, group, startId, "MKSTREAM"
    ]);
  } catch (e: any) {
    if (!e.message.includes("BUSYGROUP")) throw e;
    // Group already exists
  }
}

// Delete consumer group
async function deleteConsumerGroup(stream: string, group: string): Promise<void> {
  await redis.send("XGROUP", ["DESTROY", stream, group]);
}

// Delete consumer from group
async function deleteConsumer(
  stream: string,
  group: string,
  consumer: string
): Promise<number> {
  return await redis.send("XGROUP", ["DELCONSUMER", stream, group, consumer]) as number;
}
```

### Consumer Worker

```typescript
interface StreamMessage {
  id: string;
  stream: string;
  fields: Record<string, string>;
}

async function startConsumer(
  stream: string,
  group: string,
  consumer: string,
  handler: (message: StreamMessage) => Promise<void>,
  options: { batchSize?: number; blockMs?: number } = {}
): Promise<void> {
  const { batchSize = 10, blockMs = 5000 } = options;

  console.log(`Consumer ${consumer} started for ${group}/${stream}`);

  while (true) {
    try {
      // Read new messages assigned to this consumer
      const result = await redis.send("XREADGROUP", [
        "GROUP", group, consumer,
        "COUNT", batchSize.toString(),
        "BLOCK", blockMs.toString(),
        "STREAMS", stream,
        ">"  // Only undelivered messages
      ]);

      if (!result) continue;

      // Process messages
      for (const [streamName, entries] of result as any) {
        for (const [id, fieldArray] of entries) {
          const fields: Record<string, string> = {};
          for (let i = 0; i < fieldArray.length; i += 2) {
            fields[fieldArray[i]] = fieldArray[i + 1];
          }

          const message: StreamMessage = { id, stream: streamName, fields };

          try {
            await handler(message);
            // Acknowledge successful processing
            await redis.send("XACK", [stream, group, id]);
          } catch (error) {
            console.error(`Failed to process message ${id}:`, error);
            // Message remains unacknowledged, will be re-delivered
          }
        }
      }
    } catch (error) {
      console.error("Consumer error:", error);
      await Bun.sleep(1000);  // Backoff on error
    }
  }
}

// Usage
await createConsumerGroup("orders", "order-processors");

// Start multiple workers
startConsumer("orders", "order-processors", "worker-1", async (msg) => {
  console.log("Processing order:", msg.fields);
  await processOrder(msg.fields);
});

startConsumer("orders", "order-processors", "worker-2", async (msg) => {
  console.log("Processing order:", msg.fields);
  await processOrder(msg.fields);
});
```

### Handling Pending Messages

Messages that were delivered but not acknowledged.

```typescript
// Get pending messages summary
async function getPendingSummary(stream: string, group: string) {
  return await redis.send("XPENDING", [stream, group]);
}

// Get detailed pending messages
async function getPendingMessages(
  stream: string,
  group: string,
  count: number = 10
) {
  return await redis.send("XPENDING", [
    stream, group,
    "-", "+",      // ID range
    count.toString()
  ]);
}

// Claim idle messages (for failover)
async function claimIdleMessages(
  stream: string,
  group: string,
  consumer: string,
  minIdleTimeMs: number,
  count: number = 10
): Promise<any[]> {
  // Get idle pending messages
  const pending = await redis.send("XPENDING", [
    stream, group,
    "IDLE", minIdleTimeMs.toString(),
    "-", "+",
    count.toString()
  ]) as any[];

  if (!pending || pending.length === 0) return [];

  const ids = pending.map(p => p[0]);

  // Claim the messages
  return await redis.send("XCLAIM", [
    stream, group, consumer,
    minIdleTimeMs.toString(),
    ...ids
  ]);
}

// Auto-claim (Redis 6.2+) - combines pending check and claim
async function autoClaimMessages(
  stream: string,
  group: string,
  consumer: string,
  minIdleTimeMs: number,
  startId: string = "0-0",
  count: number = 10
) {
  return await redis.send("XAUTOCLAIM", [
    stream, group, consumer,
    minIdleTimeMs.toString(),
    startId,
    "COUNT", count.toString()
  ]);
}
```

### Dead Letter Queue

```typescript
async function moveToDeadLetter(
  stream: string,
  group: string,
  deadLetterStream: string,
  messageId: string,
  reason: string
): Promise<void> {
  // Get the original message
  const [entry] = await redis.send("XRANGE", [
    stream, messageId, messageId
  ]) as any[];

  if (!entry) return;

  const [id, fields] = entry;

  // Add to dead letter stream with metadata
  await redis.send("XADD", [
    deadLetterStream, "*",
    "original_stream", stream,
    "original_id", id,
    "original_group", group,
    "reason", reason,
    "moved_at", Date.now().toString(),
    ...fields
  ]);

  // Acknowledge original message
  await redis.send("XACK", [stream, group, messageId]);
}

// Process dead letters
async function processDeadLetters(
  deadLetterStream: string,
  handler: (entry: any) => Promise<boolean>  // Return true to remove
): Promise<void> {
  const entries = await redis.send("XRANGE", [
    deadLetterStream, "-", "+", "COUNT", "100"
  ]) as any[];

  for (const [id, fields] of entries) {
    const fieldsObj: Record<string, string> = {};
    for (let i = 0; i < fields.length; i += 2) {
      fieldsObj[fields[i]] = fields[i + 1];
    }

    const shouldRemove = await handler(fieldsObj);
    if (shouldRemove) {
      await redis.send("XDEL", [deadLetterStream, id]);
    }
  }
}
```

---

## Event Sourcing Pattern

```typescript
interface Event {
  type: string;
  aggregateId: string;
  data: any;
  metadata?: Record<string, any>;
}

class EventStore {
  private stream: string;

  constructor(streamName: string = "events") {
    this.stream = streamName;
  }

  async append(event: Event): Promise<string> {
    const id = await redis.send("XADD", [
      this.stream,
      "MAXLEN", "~", "1000000",
      "*",
      "type", event.type,
      "aggregateId", event.aggregateId,
      "data", JSON.stringify(event.data),
      "metadata", JSON.stringify(event.metadata || {}),
      "timestamp", Date.now().toString()
    ]);

    return id as string;
  }

  async getEventsForAggregate(aggregateId: string): Promise<Event[]> {
    // This requires a secondary index or full scan
    // For production, consider using RediSearch or separate streams per aggregate type
    const entries = await redis.send("XRANGE", [this.stream, "-", "+"]) as any[];

    return entries
      .filter(([, fields]) => {
        const fieldsObj = this.fieldsToObject(fields);
        return fieldsObj.aggregateId === aggregateId;
      })
      .map(([id, fields]) => this.entryToEvent(id, fields));
  }

  async getEventsSince(lastEventId: string, count: number = 100): Promise<Event[]> {
    const entries = await redis.send("XRANGE", [
      this.stream,
      `(${lastEventId}`,  // Exclusive
      "+",
      "COUNT", count.toString()
    ]) as any[];

    return entries.map(([id, fields]) => this.entryToEvent(id, fields));
  }

  async subscribe(
    group: string,
    consumer: string,
    handler: (event: Event & { id: string }) => Promise<void>
  ): Promise<void> {
    // Create consumer group if not exists
    try {
      await redis.send("XGROUP", ["CREATE", this.stream, group, "0", "MKSTREAM"]);
    } catch (e: any) {
      if (!e.message.includes("BUSYGROUP")) throw e;
    }

    while (true) {
      const result = await redis.send("XREADGROUP", [
        "GROUP", group, consumer,
        "COUNT", "10",
        "BLOCK", "5000",
        "STREAMS", this.stream, ">"
      ]);

      if (!result) continue;

      for (const [, entries] of result as any) {
        for (const [id, fields] of entries) {
          const event = { ...this.entryToEvent(id, fields), id };

          try {
            await handler(event);
            await redis.send("XACK", [this.stream, group, id]);
          } catch (error) {
            console.error(`Failed to handle event ${id}:`, error);
          }
        }
      }
    }
  }

  private fieldsToObject(fields: string[]): Record<string, string> {
    const obj: Record<string, string> = {};
    for (let i = 0; i < fields.length; i += 2) {
      obj[fields[i]] = fields[i + 1];
    }
    return obj;
  }

  private entryToEvent(id: string, fields: string[]): Event {
    const obj = this.fieldsToObject(fields);
    return {
      type: obj.type,
      aggregateId: obj.aggregateId,
      data: JSON.parse(obj.data),
      metadata: JSON.parse(obj.metadata || "{}")
    };
  }
}

// Usage
const store = new EventStore("domain-events");

// Append events
await store.append({
  type: "OrderCreated",
  aggregateId: "order-123",
  data: { items: [], total: 0 }
});

await store.append({
  type: "ItemAdded",
  aggregateId: "order-123",
  data: { productId: "prod-1", quantity: 2 }
});

// Subscribe to events
store.subscribe("projections", "read-model-updater", async (event) => {
  console.log("Processing event:", event.type, event.id);
  // Update read models, send notifications, etc.
});
```

---

## Stream Info and Management

```typescript
// Get stream info
async function getStreamInfo(stream: string) {
  return await redis.send("XINFO", ["STREAM", stream]);
}

// Get stream info with entries
async function getStreamInfoFull(stream: string, count: number = 10) {
  return await redis.send("XINFO", ["STREAM", stream, "FULL", "COUNT", count.toString()]);
}

// Get all groups for a stream
async function getGroups(stream: string) {
  return await redis.send("XINFO", ["GROUPS", stream]);
}

// Get consumers in a group
async function getConsumers(stream: string, group: string) {
  return await redis.send("XINFO", ["CONSUMERS", stream, group]);
}

// Get stream length
async function getStreamLength(stream: string): Promise<number> {
  return await redis.send("XLEN", [stream]) as number;
}

// Trim stream
async function trimStream(stream: string, maxLen: number): Promise<number> {
  return await redis.send("XTRIM", [stream, "MAXLEN", "~", maxLen.toString()]) as number;
}

// Trim by minimum ID
async function trimByMinId(stream: string, minId: string): Promise<number> {
  return await redis.send("XTRIM", [stream, "MINID", "~", minId]) as number;
}

// Delete specific entries
async function deleteEntries(stream: string, ...ids: string[]): Promise<number> {
  return await redis.send("XDEL", [stream, ...ids]) as number;
}
```
