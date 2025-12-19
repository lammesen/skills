# WebSocket Patterns

Comprehensive WebSocket implementation patterns for Elysia.

## Basic WebSocket Server

### Simple Echo Server

```typescript
import { Elysia } from 'elysia'

new Elysia()
  .ws('/ws', {
    message(ws, message) {
      ws.send(`Echo: ${message}`)
    }
  })
  .listen(3000)
```

### Full WebSocket Handler

```typescript
.ws('/ws', {
  // Lifecycle hooks
  open(ws) {
    console.log('Client connected:', ws.id)
  },

  message(ws, message) {
    console.log('Received:', message)
    ws.send({ received: message })
  },

  close(ws, code, reason) {
    console.log('Client disconnected:', ws.id, code, reason)
  },

  error(ws, error) {
    console.error('WebSocket error:', error)
  },

  // Options
  idleTimeout: 120,
  maxPayloadLength: 16 * 1024 * 1024
})
```

## Validation

### Message Validation

```typescript
import { Elysia, t } from 'elysia'

.ws('/chat', {
  body: t.Object({
    type: t.UnionEnum(['message', 'typing', 'read']),
    content: t.Optional(t.String()),
    messageId: t.Optional(t.String())
  }),

  message(ws, { type, content, messageId }) {
    switch (type) {
      case 'message':
        // Handle chat message
        break
      case 'typing':
        // Handle typing indicator
        break
      case 'read':
        // Handle read receipt
        break
    }
  }
})
```

### Query Parameter Validation

```typescript
.ws('/room', {
  query: t.Object({
    room: t.String(),
    userId: t.String()
  }),

  open(ws) {
    const { room, userId } = ws.data.query
    ws.subscribe(room)
    ws.publish(room, { type: 'join', userId })
  }
})
```

### Header Validation

```typescript
.ws('/secure', {
  headers: t.Object({
    authorization: t.String()
  }),

  beforeHandle({ headers, status }) {
    if (!validateToken(headers.authorization)) {
      return status(401)
    }
  },

  open(ws) {
    console.log('Authenticated connection')
  }
})
```

## Pub/Sub Patterns

### Room-Based Chat

```typescript
interface ChatMessage {
  type: 'message' | 'join' | 'leave'
  user: string
  content?: string
  timestamp: number
}

.ws('/chat', {
  query: t.Object({
    room: t.String(),
    username: t.String()
  }),

  body: t.Object({
    content: t.String({ maxLength: 1000 })
  }),

  open(ws) {
    const { room, username } = ws.data.query

    // Subscribe to room
    ws.subscribe(room)

    // Announce join
    const message: ChatMessage = {
      type: 'join',
      user: username,
      timestamp: Date.now()
    }
    ws.publish(room, JSON.stringify(message))
  },

  message(ws, { content }) {
    const { room, username } = ws.data.query

    const message: ChatMessage = {
      type: 'message',
      user: username,
      content,
      timestamp: Date.now()
    }

    // Broadcast to room (including sender)
    ws.publish(room, JSON.stringify(message))
  },

  close(ws) {
    const { room, username } = ws.data.query

    const message: ChatMessage = {
      type: 'leave',
      user: username,
      timestamp: Date.now()
    }
    ws.publish(room, JSON.stringify(message))
  }
})
```

### Multi-Room Support

```typescript
const userRooms = new Map<string, Set<string>>()

.ws('/chat', {
  body: t.Object({
    action: t.UnionEnum(['subscribe', 'unsubscribe', 'message']),
    room: t.String(),
    content: t.Optional(t.String())
  }),

  open(ws) {
    userRooms.set(ws.id, new Set())
  },

  message(ws, { action, room, content }) {
    const rooms = userRooms.get(ws.id)!

    switch (action) {
      case 'subscribe':
        ws.subscribe(room)
        rooms.add(room)
        ws.send({ type: 'subscribed', room })
        break

      case 'unsubscribe':
        ws.unsubscribe(room)
        rooms.delete(room)
        ws.send({ type: 'unsubscribed', room })
        break

      case 'message':
        if (rooms.has(room)) {
          ws.publish(room, JSON.stringify({
            room,
            content,
            sender: ws.id,
            timestamp: Date.now()
          }))
        }
        break
    }
  },

  close(ws) {
    // Cleanup
    const rooms = userRooms.get(ws.id)
    rooms?.forEach(room => ws.unsubscribe(room))
    userRooms.delete(ws.id)
  }
})
```

## Authentication

### JWT Authentication

```typescript
import { jwt } from '@elysiajs/jwt'

new Elysia()
  .use(jwt({ name: 'jwt', secret: process.env.JWT_SECRET! }))
  .ws('/secure', {
    query: t.Object({
      token: t.String()
    }),

    async beforeHandle({ jwt, query, status }) {
      const payload = await jwt.verify(query.token)
      if (!payload) {
        return status(401)
      }
    },

    derive({ jwt, query }) {
      return {
        async getUser() {
          const payload = await jwt.verify(query.token)
          return payload
        }
      }
    },

    async open(ws) {
      const user = await ws.data.getUser()
      console.log('User connected:', user.sub)
    }
  })
```

### Cookie Authentication

```typescript
.ws('/chat', {
  cookie: t.Cookie({
    session: t.String()
  }),

  async beforeHandle({ jwt, cookie, status }) {
    const payload = await jwt.verify(cookie.session.value)
    if (!payload) {
      return status(401)
    }
  },

  resolve({ jwt, cookie }) {
    return {
      userId: jwt.verify(cookie.session.value).then(p => p?.sub)
    }
  }
})
```

## Connection Management

### Connection Registry

```typescript
interface Connection {
  ws: any
  userId: string
  connectedAt: number
  metadata: Record<string, unknown>
}

const connections = new Map<string, Connection>()

.ws('/app', {
  query: t.Object({
    userId: t.String()
  }),

  open(ws) {
    const { userId } = ws.data.query

    connections.set(ws.id, {
      ws,
      userId,
      connectedAt: Date.now(),
      metadata: {}
    })

    // Track user connections
    ws.subscribe(`user:${userId}`)
  },

  close(ws) {
    const conn = connections.get(ws.id)
    if (conn) {
      ws.unsubscribe(`user:${conn.userId}`)
      connections.delete(ws.id)
    }
  }
})

// Helper functions
function sendToUser(userId: string, message: unknown) {
  for (const conn of connections.values()) {
    if (conn.userId === userId) {
      conn.ws.send(JSON.stringify(message))
    }
  }
}

function broadcast(message: unknown) {
  const data = JSON.stringify(message)
  for (const conn of connections.values()) {
    conn.ws.send(data)
  }
}

function getOnlineUsers(): string[] {
  return [...new Set([...connections.values()].map(c => c.userId))]
}
```

### Heartbeat/Ping-Pong

```typescript
const lastPong = new Map<string, number>()

.ws('/app', {
  idleTimeout: 30,

  open(ws) {
    lastPong.set(ws.id, Date.now())

    // Send ping every 15 seconds
    const interval = setInterval(() => {
      if (Date.now() - lastPong.get(ws.id)! > 30000) {
        ws.close()
        return
      }
      ws.send(JSON.stringify({ type: 'ping' }))
    }, 15000)

    ws.data.pingInterval = interval
  },

  message(ws, message) {
    if (typeof message === 'object' && message.type === 'pong') {
      lastPong.set(ws.id, Date.now())
      return
    }
    // Handle other messages
  },

  close(ws) {
    clearInterval(ws.data.pingInterval)
    lastPong.delete(ws.id)
  }
})
```

## Real-Time Patterns

### Presence System

```typescript
interface UserPresence {
  status: 'online' | 'away' | 'busy'
  lastSeen: number
  customStatus?: string
}

const presence = new Map<string, UserPresence>()

.ws('/presence', {
  query: t.Object({ userId: t.String() }),
  body: t.Object({
    type: t.UnionEnum(['status', 'subscribe']),
    status: t.Optional(t.UnionEnum(['online', 'away', 'busy'])),
    userIds: t.Optional(t.Array(t.String()))
  }),

  open(ws) {
    const { userId } = ws.data.query

    // Set online
    presence.set(userId, {
      status: 'online',
      lastSeen: Date.now()
    })

    // Subscribe to own channel
    ws.subscribe(`presence:${userId}`)

    // Broadcast presence update
    ws.publish('presence:updates', JSON.stringify({
      userId,
      ...presence.get(userId)
    }))
  },

  message(ws, { type, status, userIds }) {
    const { userId } = ws.data.query

    switch (type) {
      case 'status':
        if (status) {
          presence.set(userId, {
            status,
            lastSeen: Date.now()
          })
          ws.publish('presence:updates', JSON.stringify({
            userId,
            ...presence.get(userId)
          }))
        }
        break

      case 'subscribe':
        if (userIds) {
          // Send current presence for requested users
          const presenceData = userIds.map(id => ({
            userId: id,
            ...(presence.get(id) ?? { status: 'offline', lastSeen: 0 })
          }))
          ws.send(JSON.stringify({ type: 'presence', data: presenceData }))

          // Subscribe to updates
          userIds.forEach(id => ws.subscribe(`presence:${id}`))
        }
        break
    }
  },

  close(ws) {
    const { userId } = ws.data.query
    presence.set(userId, {
      status: 'offline' as any,
      lastSeen: Date.now()
    })
    ws.publish('presence:updates', JSON.stringify({
      userId,
      status: 'offline',
      lastSeen: Date.now()
    }))
  }
})
```

### Live Updates (Database Changes)

```typescript
// Notify WebSocket clients of database changes
const notifyChange = (entity: string, action: string, data: unknown) => {
  app.server?.publish(`changes:${entity}`, JSON.stringify({
    entity,
    action,
    data,
    timestamp: Date.now()
  }))
}

// In your routes
.post('/posts', async ({ body }) => {
  const post = await db.post.create({ data: body })

  // Notify subscribers
  notifyChange('posts', 'created', post)

  return post
})

// WebSocket subscription
.ws('/changes', {
  query: t.Object({
    entities: t.String() // Comma-separated: "posts,comments"
  }),

  open(ws) {
    const entities = ws.data.query.entities.split(',')
    entities.forEach(entity => {
      ws.subscribe(`changes:${entity}`)
    })
  }
})
```

### Collaborative Editing

```typescript
interface DocumentState {
  content: string
  version: number
  users: Set<string>
}

const documents = new Map<string, DocumentState>()

.ws('/collaborate/:docId', {
  params: t.Object({ docId: t.String() }),
  query: t.Object({ userId: t.String() }),
  body: t.Object({
    type: t.UnionEnum(['edit', 'cursor', 'selection']),
    version: t.Optional(t.Number()),
    operations: t.Optional(t.Array(t.Unknown())),
    cursor: t.Optional(t.Object({ line: t.Number(), ch: t.Number() })),
    selection: t.Optional(t.Object({
      start: t.Object({ line: t.Number(), ch: t.Number() }),
      end: t.Object({ line: t.Number(), ch: t.Number() })
    }))
  }),

  open(ws) {
    const { docId } = ws.data.params
    const { userId } = ws.data.query

    // Initialize document if needed
    if (!documents.has(docId)) {
      documents.set(docId, {
        content: '',
        version: 0,
        users: new Set()
      })
    }

    const doc = documents.get(docId)!
    doc.users.add(userId)

    // Subscribe to document updates
    ws.subscribe(`doc:${docId}`)

    // Send current state
    ws.send(JSON.stringify({
      type: 'init',
      content: doc.content,
      version: doc.version,
      users: [...doc.users]
    }))

    // Notify others of join
    ws.publish(`doc:${docId}`, JSON.stringify({
      type: 'user-joined',
      userId
    }))
  },

  message(ws, data) {
    const { docId } = ws.data.params
    const { userId } = ws.data.query
    const doc = documents.get(docId)!

    switch (data.type) {
      case 'edit':
        if (data.version === doc.version) {
          // Apply operations
          // doc.content = applyOperations(doc.content, data.operations)
          doc.version++

          ws.publish(`doc:${docId}`, JSON.stringify({
            type: 'edit',
            userId,
            version: doc.version,
            operations: data.operations
          }))
        } else {
          // Version conflict - send current state
          ws.send(JSON.stringify({
            type: 'sync',
            content: doc.content,
            version: doc.version
          }))
        }
        break

      case 'cursor':
        ws.publish(`doc:${docId}`, JSON.stringify({
          type: 'cursor',
          userId,
          cursor: data.cursor
        }))
        break
    }
  },

  close(ws) {
    const { docId } = ws.data.params
    const { userId } = ws.data.query
    const doc = documents.get(docId)

    if (doc) {
      doc.users.delete(userId)
      ws.publish(`doc:${docId}`, JSON.stringify({
        type: 'user-left',
        userId
      }))
    }
  }
})
```

## Error Handling

```typescript
.ws('/app', {
  message(ws, message) {
    try {
      // Process message
      const result = processMessage(message)
      ws.send(JSON.stringify({ success: true, data: result }))
    } catch (error) {
      ws.send(JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }))
    }
  },

  error(ws, error) {
    console.error('WebSocket error:', error)
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Connection error occurred'
    }))
  }
})
```

## Client-Side Integration

### Eden WebSocket Client

```typescript
import { treaty } from '@elysiajs/eden'
import type { App } from './server'

const api = treaty<App>('localhost:3000')

// Connect to WebSocket
const chat = api.chat.subscribe({
  query: { room: 'general', username: 'John' }
})

// Events
chat.on('open', () => console.log('Connected'))
chat.on('close', () => console.log('Disconnected'))
chat.on('error', (e) => console.error('Error:', e))

// Receive messages
chat.subscribe((message) => {
  console.log('Message:', message)
})

// Send messages
chat.send({ content: 'Hello world!' })

// Close connection
chat.close()
```

### Native WebSocket Client

```typescript
const ws = new WebSocket('ws://localhost:3000/chat?room=general&username=John')

ws.onopen = () => {
  console.log('Connected')
  ws.send(JSON.stringify({ content: 'Hello!' }))
}

ws.onmessage = (event) => {
  const data = JSON.parse(event.data)
  console.log('Received:', data)
}

ws.onclose = () => console.log('Disconnected')
ws.onerror = (error) => console.error('Error:', error)
```
