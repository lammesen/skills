# ElysiaJS Lifecycle Hooks Reference

Complete reference for Elysia lifecycle hooks and their execution order.

## Hook Execution Order

```
Request
   │
   ▼
┌──────────────┐
│  onRequest   │  ← Global, before routing
└──────────────┘
   │
   ▼
┌──────────────┐
│   onParse    │  ← Body parsing
└──────────────┘
   │
   ▼
┌──────────────┐
│ onTransform  │  ← Before validation
└──────────────┘
   │
   ▼
┌──────────────┐
│   derive     │  ← Create context (pre-validation)
└──────────────┘
   │
   ▼
┌──────────────┐
│  Validation  │  ← Schema validation
└──────────────┘
   │
   ▼
┌──────────────┐
│   resolve    │  ← Create context (post-validation)
└──────────────┘
   │
   ▼
┌──────────────┐
│beforeHandle  │  ← Pre-handler logic
└──────────────┘
   │
   ▼
┌──────────────┐
│   Handler    │  ← Route handler
└──────────────┘
   │
   ▼
┌──────────────┐
│ afterHandle  │  ← Transform response
└──────────────┘
   │
   ▼
┌──────────────┐
│ mapResponse  │  ← Custom response mapping
└──────────────┘
   │
   ▼
┌──────────────┐
│afterResponse │  ← Cleanup/logging
└──────────────┘
   │
   ▼
Response
```

## Hook Scoping

All hooks support three scoping levels:

```typescript
// Local: Only current instance (default)
.onBeforeHandle({ as: 'local' }, handler)

// Scoped: Parent + current + direct children
.onBeforeHandle({ as: 'scoped' }, handler)

// Global: All instances in application
.onBeforeHandle({ as: 'global' }, handler)
```

## onRequest

Executes immediately when request is received, before routing.

```typescript
.onRequest(handler)
.onRequest({ as: 'global' }, handler)

interface OnRequestContext {
  request: Request
  ip: string | null
  set: ResponseSetters
  store: Store
  status: StatusFunction
}
```

### Use Cases

- Rate limiting
- Request logging
- CORS preflight handling
- IP blocking
- Request ID generation

### Examples

```typescript
// Rate limiting
const rateLimiter = new Map<string, number>()

.onRequest(({ ip, status }) => {
  const count = rateLimiter.get(ip) ?? 0
  if (count > 100) return status(429, 'Too many requests')
  rateLimiter.set(ip, count + 1)
})

// Request logging
.onRequest(({ request }) => {
  console.log(`${new Date().toISOString()} ${request.method} ${request.url}`)
})

// Add request ID
.onRequest(({ set }) => {
  set.headers['x-request-id'] = crypto.randomUUID()
})
```

## onParse

Custom body parsing logic.

```typescript
.onParse(handler)
.onParse({ as: 'local' }, handler)

interface OnParseContext {
  request: Request
  contentType: string
}
```

### Built-in Parsers

```typescript
// Specify parser type
.post('/', handler, { parse: 'json' })     // application/json
.post('/', handler, { parse: 'text' })     // text/plain
.post('/', handler, { parse: 'formdata' }) // multipart/form-data
.post('/', handler, { parse: 'urlencoded' }) // application/x-www-form-urlencoded
.post('/', handler, { parse: 'none' })     // Skip parsing
```

### Custom Parser

```typescript
.onParse(async ({ request, contentType }) => {
  if (contentType === 'application/xml') {
    const text = await request.text()
    return parseXML(text)
  }
})

// Multiple parsers
.onParse([xmlParser, csvParser])
```

## onTransform

Transform context before validation.

```typescript
.onTransform(handler)

interface OnTransformContext extends Context {
  // Full context, but body/query/params may be unparsed
}
```

### Use Cases

- Type coercion before validation
- Default value injection
- Request normalization

### Examples

```typescript
// Convert string to number
.get('/user/:id', handler, {
  transform({ params }) {
    params.id = +params.id
  }
})

// Normalize query
.get('/search', handler, {
  transform({ query }) {
    if (query.q) query.q = query.q.toLowerCase().trim()
  }
})
```

## derive

Create new context properties before validation.

```typescript
.derive(handler)
.derive({ as: 'scoped' }, handler)

// Must return an object
.derive(({ headers }) => ({
  bearer: headers.authorization?.slice(7)
}))
```

### Key Points

- Runs before validation
- Properties added to context
- Can access decorated/state values
- Cannot access validated body

### Examples

```typescript
// Extract bearer token
.derive(({ headers }) => ({
  bearer: headers.authorization?.startsWith('Bearer ')
    ? headers.authorization.slice(7)
    : null
}))

// Request metadata
.derive(({ request }) => ({
  requestedAt: Date.now(),
  userAgent: request.headers.get('user-agent')
}))
```

## resolve

Create context properties after validation.

```typescript
.resolve(handler)
.resolve({ as: 'scoped' }, handler)
```

### Key Differences from derive

| derive | resolve |
|--------|---------|
| Before validation | After validation |
| Can't access validated body | Has validated body |
| Properties not type-safe | Properties are type-safe |

### Examples

```typescript
// User from validated token
.guard({
  headers: t.Object({
    authorization: t.TemplateLiteral('Bearer ${string}')
  })
})
.resolve(async ({ headers }) => ({
  user: await getUserFromToken(headers.authorization.slice(7))
}))
.get('/me', ({ user }) => user)

// Computed values from body
.post('/order', handler, {
  body: t.Object({
    items: t.Array(t.Object({
      price: t.Number(),
      quantity: t.Number()
    }))
  }),
  resolve({ body }) {
    return {
      total: body.items.reduce((sum, i) => sum + i.price * i.quantity, 0)
    }
  }
})
```

## onBeforeHandle

Execute logic before the route handler.

```typescript
.onBeforeHandle(handler)
.onBeforeHandle({ as: 'local' }, handler)

// Local hook
.get('/path', handler, {
  beforeHandle: localHandler
})
```

### Use Cases

- Authentication checks
- Authorization
- Request validation (beyond schema)
- Early response

### Examples

```typescript
// Authentication
.onBeforeHandle(({ bearer, status }) => {
  if (!bearer) return status(401, 'Unauthorized')
})

// Role check
.get('/admin', handler, {
  beforeHandle({ user, status }) {
    if (user.role !== 'admin') return status(403, 'Forbidden')
  }
})

// Multiple handlers (run in order)
.onBeforeHandle([
  checkRateLimit,
  checkAuth,
  checkPermissions
])
```

## Route Handler

The main route handler.

```typescript
.get('/path', (context) => response)

// Can return:
// - Primitives (string, number)
// - Objects (auto-JSON)
// - Response objects
// - Streams/generators
// - Files
// - Status responses
```

## onAfterHandle

Transform response after handler.

```typescript
.onAfterHandle(handler)

interface OnAfterHandleContext extends Context {
  responseValue: unknown  // Handler return value
}
```

### Examples

```typescript
// Wrap in envelope
.onAfterHandle(({ responseValue }) => ({
  success: true,
  data: responseValue,
  timestamp: Date.now()
}))

// Set content type
.onAfterHandle(({ responseValue, set }) => {
  if (typeof responseValue === 'string' && responseValue.startsWith('<'))
    set.headers['content-type'] = 'text/html'
})

// Caching
.onAfterHandle(({ responseValue, set, path }) => {
  if (shouldCache(path)) {
    cache.set(path, responseValue)
    set.headers['cache-control'] = 'max-age=3600'
  }
})
```

## mapResponse

Custom response serialization.

```typescript
.mapResponse(handler)

interface MapResponseContext extends Context {
  responseValue: unknown
  // Can return raw Response
}
```

### Examples

```typescript
// Gzip compression
.mapResponse(({ responseValue, set }) => {
  const json = JSON.stringify(responseValue)
  set.headers['content-encoding'] = 'gzip'
  return new Response(Bun.gzipSync(json))
})

// Custom serialization
.mapResponse(({ responseValue }) => {
  if (responseValue instanceof MyCustomClass) {
    return new Response(responseValue.serialize())
  }
})
```

## onError

Handle errors globally or locally.

```typescript
.onError(handler)

interface OnErrorContext extends Context {
  code: ErrorCode
  error: Error
}

type ErrorCode =
  | 'NOT_FOUND'
  | 'VALIDATION'
  | 'PARSE'
  | 'INTERNAL_SERVER_ERROR'
  | 'UNKNOWN'
  | string // Custom error codes
```

### Examples

```typescript
.onError(({ code, error, status }) => {
  switch (code) {
    case 'NOT_FOUND':
      return status(404, { message: 'Not Found' })

    case 'VALIDATION':
      return status(400, {
        message: 'Validation failed',
        errors: error.all
      })

    case 'PARSE':
      return status(400, { message: 'Invalid request body' })

    case 'INTERNAL_SERVER_ERROR':
      console.error(error)
      return status(500, { message: 'Internal server error' })

    default:
      return status(500, { message: error.message })
  }
})

// Custom error type
class CustomError extends Error {
  constructor(message: string, public code = 'CUSTOM_ERROR') {
    super(message)
  }
}

.onError(({ error, status }) => {
  if (error instanceof CustomError)
    return status(400, { code: error.code, message: error.message })
})
```

## onAfterResponse

Execute after response is sent.

```typescript
.onAfterResponse(handler)

interface OnAfterResponseContext extends Context {
  // Response already sent
}
```

### Use Cases

- Response logging
- Analytics
- Cleanup
- Metrics

### Examples

```typescript
// Response logging
.onAfterResponse(({ request, set }) => {
  console.log(`${request.method} ${request.url} - ${set.status}`)
})

// Metrics
.onAfterResponse(({ path, set }) => {
  metrics.record({
    path,
    status: set.status,
    duration: Date.now() - requestStart
  })
})

// Cleanup
.onAfterResponse(() => {
  // Release resources, close connections
})
```

## Local vs Global Hooks

### Local Hooks (Route-Specific)

```typescript
.get('/path', handler, {
  beforeHandle: handler,
  afterHandle: handler,
  transform: handler,
  parse: handler,
  error: handler
})
```

### Instance Hooks (Global to Instance)

```typescript
.onRequest(handler)
.onParse(handler)
.onTransform(handler)
.onBeforeHandle(handler)
.onAfterHandle(handler)
.mapResponse(handler)
.onError(handler)
.onAfterResponse(handler)
```

### Hook Priority

Local hooks run after global hooks:

```
Global onBeforeHandle → Local beforeHandle → Handler
```

Multiple hooks of same type run in registration order:

```typescript
.onBeforeHandle(first)
.onBeforeHandle(second)  // first runs before second
```

## Early Return

Any hook can return early to skip subsequent hooks and handler:

```typescript
.onBeforeHandle(({ status }) => {
  if (condition) return status(403)  // Skip handler
  // Continue if no return
})
```

Returning `undefined` or nothing continues execution.
