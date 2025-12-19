# Eden Treaty Client Reference

Complete reference for Eden, Elysia's type-safe client.

## Overview

Eden provides end-to-end type safety between Elysia server and client. Changes to the server API are immediately reflected in client code.

## Installation

```bash
bun add @elysiajs/eden
```

## Server Setup

```typescript
// server.ts
import { Elysia, t } from 'elysia'

const app = new Elysia()
  .get('/', () => 'Hello')
  .get('/user/:id', ({ params }) => ({ id: params.id, name: 'John' }))
  .post('/user', ({ body }) => body, {
    body: t.Object({
      name: t.String(),
      email: t.String({ format: 'email' })
    })
  })
  .listen(3000)

// Export type for client
export type App = typeof app
```

## Client Setup

```typescript
// client.ts
import { treaty } from '@elysiajs/eden'
import type { App } from './server'

// Create typed client
const api = treaty<App>('localhost:3000')
```

## Path Syntax

Eden converts URL paths to method chains:

```typescript
// Path mapping
api.index.get()                    // GET /
api.user.get()                     // GET /user
api.user.post()                    // POST /user
api.deep.nested.path.get()         // GET /deep/nested/path
```

### Path Parameters

```typescript
// Server: .get('/user/:id', handler)
// Client: Use function call with params object
const { data } = await api.user({ id: '123' }).get()

// Server: .get('/org/:org/repo/:repo', handler)
const { data } = await api.org({ org: 'elysia' }).repo({ repo: 'elysia' }).get()

// Multiple params in single call
const { data } = await api.org({ org: 'elysia', repo: 'elysia' }).get()
```

## Making Requests

### GET Requests

```typescript
// Simple GET
const { data, error } = await api.user.get()

// GET with query parameters
const { data } = await api.users.get({
  query: {
    page: 1,
    limit: 10,
    search: 'john'
  }
})

// GET with headers
const { data } = await api.protected.get({
  headers: {
    authorization: 'Bearer token'
  }
})
```

### POST Requests

```typescript
// POST with body
const { data, error } = await api.user.post({
  name: 'John',
  email: 'john@example.com'
})

// POST with body, headers, and query
const { data } = await api.user.post(
  { name: 'John' },  // body
  {
    headers: { 'x-api-key': 'key' },
    query: { source: 'web' }
  }
)
```

### Other Methods

```typescript
// PUT
const { data } = await api.user({ id: '123' }).put({ name: 'Jane' })

// PATCH
const { data } = await api.user({ id: '123' }).patch({ name: 'Jane' })

// DELETE
const { data } = await api.user({ id: '123' }).delete()
```

## Response Handling

### Basic Response

```typescript
const { data, error, status, headers, response } = await api.user.get()

// data: Response body (typed)
// error: Error object if request failed
// status: HTTP status code
// headers: Response headers
// response: Raw Response object
```

### Error Handling

```typescript
const { data, error } = await api.user.post({ name: 'John' })

if (error) {
  // error.status: HTTP status code
  // error.value: Error response body (typed per status)

  switch (error.status) {
    case 400:
      console.log('Validation error:', error.value)
      break
    case 401:
      console.log('Unauthorized:', error.value)
      break
    case 404:
      console.log('Not found:', error.value)
      break
    default:
      console.log('Error:', error.value)
  }
  return
}

// data is non-null here (type narrowing)
console.log(data.name)
```

### Type-Safe Error Responses

```typescript
// Server with typed error responses
.get('/user/:id', handler, {
  response: {
    200: t.Object({ id: t.String(), name: t.String() }),
    404: t.Object({ message: t.String() })
  }
})

// Client
const { data, error } = await api.user({ id: '123' }).get()

if (error) {
  if (error.status === 404) {
    // error.value is typed as { message: string }
    console.log(error.value.message)
  }
}
```

## Configuration

### Client Options

```typescript
const api = treaty<App>('localhost:3000', {
  // Fetch options
  fetch: {
    credentials: 'include',
    mode: 'cors'
  },

  // Static headers
  headers: {
    authorization: 'Bearer token',
    'x-api-key': 'key'
  },

  // Dynamic headers (per request)
  headers: (path, options) => ({
    authorization: getToken(),
    'x-request-id': crypto.randomUUID()
  }),

  // Request interceptor
  onRequest: (path, options) => {
    console.log(`Requesting ${path}`)
    // Can modify options
    return options
  },

  // Response interceptor
  onResponse: (response) => {
    console.log(`Response: ${response.status}`)
    // Can modify or return new response
    return response
  }
})
```

### Base URL Patterns

```typescript
// With protocol
const api = treaty<App>('http://localhost:3000')
const api = treaty<App>('https://api.example.com')

// Without protocol (defaults to http)
const api = treaty<App>('localhost:3000')

// With path prefix
const api = treaty<App>('api.example.com/v1')
```

## WebSocket Client

### Server Setup

```typescript
.ws('/chat', {
  body: t.Object({ message: t.String() }),
  message(ws, { message }) {
    ws.send({ reply: message })
  }
})
```

### Client Usage

```typescript
const chat = api.chat.subscribe()

// Connection events
chat.on('open', () => {
  console.log('Connected')
  chat.send({ message: 'Hello' })
})

chat.on('close', () => {
  console.log('Disconnected')
})

chat.on('error', (error) => {
  console.error('WebSocket error:', error)
})

// Message handling
chat.subscribe((data) => {
  // data is typed based on server response
  console.log('Received:', data)
})

// Send messages (typed)
chat.send({ message: 'Hello World' })

// Close connection
chat.close()

// Access raw WebSocket
chat.raw  // Native WebSocket instance
```

### WebSocket with Query Parameters

```typescript
// Server
.ws('/chat', {
  query: t.Object({ room: t.String() }),
  open(ws) {
    ws.subscribe(ws.data.query.room)
  }
})

// Client
const chat = api.chat.subscribe({
  query: { room: 'general' }
})
```

## Streaming

### Server-Sent Events

```typescript
// Server
.get('/events', async function* () {
  for (let i = 0; i < 10; i++) {
    yield { event: i }
    await Bun.sleep(100)
  }
})

// Client
const { data } = await api.events.get()

for await (const event of data) {
  console.log(event)  // { event: 0 }, { event: 1 }, ...
}
```

### Response Streaming

```typescript
// Server
.get('/stream', () => new Response(
  new ReadableStream({
    async start(controller) {
      for (let i = 0; i < 10; i++) {
        controller.enqueue(`data: ${i}\n\n`)
        await Bun.sleep(100)
      }
      controller.close()
    }
  })
))

// Client
const { data, response } = await api.stream.get()

const reader = response.body?.getReader()
while (true) {
  const { done, value } = await reader.read()
  if (done) break
  console.log(new TextDecoder().decode(value))
}
```

## File Upload

```typescript
// Server
.post('/upload', ({ body }) => {
  return { filename: body.file.name, size: body.file.size }
}, {
  body: t.Object({
    file: t.File()
  })
})

// Client
const file = new File(['content'], 'test.txt', { type: 'text/plain' })
const { data } = await api.upload.post({ file })
```

## Testing with Eden

### Unit Testing

```typescript
import { describe, expect, it } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import { app } from './server'

describe('API', () => {
  // Pass app instance directly - no network calls!
  const api = treaty(app)

  it('should get user', async () => {
    const { data, error } = await api.user({ id: '123' }).get()

    expect(error).toBeNull()
    expect(data?.id).toBe('123')
  })

  it('should create user', async () => {
    const { data, error } = await api.user.post({
      name: 'John',
      email: 'john@example.com'
    })

    expect(error).toBeNull()
    expect(data?.name).toBe('John')
  })

  it('should handle validation errors', async () => {
    const { error } = await api.user.post({
      name: '',  // Invalid
      email: 'not-an-email'  // Invalid
    })

    expect(error).not.toBeNull()
    expect(error?.status).toBe(400)
  })
})
```

### Integration Testing

```typescript
import { treaty } from '@elysiajs/eden'
import type { App } from './server'

// Test against running server
const api = treaty<App>('localhost:3000')

describe('Integration', () => {
  it('should work end-to-end', async () => {
    const { data } = await api.health.get()
    expect(data).toEqual({ status: 'ok' })
  })
})
```

## Eden Fetch (Alternative API)

For more control, use `edenFetch`:

```typescript
import { edenFetch } from '@elysiajs/eden'
import type { App } from './server'

const api = edenFetch<App>('http://localhost:3000')

// Similar to native fetch
const response = await api('/user/:id', {
  method: 'GET',
  params: { id: '123' }
})

const response = await api('/user', {
  method: 'POST',
  body: { name: 'John' }
})
```

## Type Inference

### Extracting Types

```typescript
import type { App } from './server'
import type { InferRouteBody, InferRouteResponse } from '@elysiajs/eden'

// Get request body type
type CreateUserBody = InferRouteBody<App, '/user', 'POST'>

// Get response type
type UserResponse = InferRouteResponse<App, '/user/:id', 'GET'>
```

### Generic Client

```typescript
// Create reusable typed fetch wrapper
async function apiCall<T>(
  fn: () => Promise<{ data: T; error: unknown }>
): Promise<T> {
  const { data, error } = await fn()
  if (error) throw error
  return data!
}

// Usage
const user = await apiCall(() => api.user({ id: '123' }).get())
```

## Best Practices

1. **Export App Type from Server**
   ```typescript
   export type App = typeof app
   ```

2. **Use Direct Instance for Testing**
   ```typescript
   const api = treaty(app)  // No network calls
   ```

3. **Handle Errors Consistently**
   ```typescript
   const { data, error } = await api.resource.get()
   if (error) return handleError(error)
   return data
   ```

4. **Configure Headers Dynamically**
   ```typescript
   const api = treaty<App>('localhost:3000', {
     headers: () => ({
       authorization: `Bearer ${getToken()}`
     })
   })
   ```

5. **Type Narrow After Error Check**
   ```typescript
   if (error) throw error
   // data is guaranteed non-null here
   console.log(data.property)
   ```
