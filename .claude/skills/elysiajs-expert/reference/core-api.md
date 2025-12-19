# ElysiaJS Core API Reference

Complete API reference for Elysia core functionality.

## Elysia Class

### Constructor

```typescript
import { Elysia } from 'elysia'

new Elysia(options?: ElysiaOptions)
```

### ElysiaOptions

```typescript
interface ElysiaOptions {
  name?: string                    // Plugin identifier for deduplication
  prefix?: string                  // Route prefix
  seed?: unknown                   // Deduplication checksum seed
  serve?: Serve                    // Bun serve options
  websocket?: WebSocketOptions     // WebSocket configuration
  cookie?: CookieOptions           // Default cookie options
  nativeStaticResponse?: boolean   // Use native Bun static responses
  precompile?: boolean             // Precompile routes
  strictPath?: boolean             // Strict path matching
  tags?: string[]                  // OpenAPI tags
  detail?: OpenAPIDetail           // OpenAPI route detail
  normalize?: boolean              // Normalize response
  scoped?: boolean                 // Default scoping behavior
}
```

### WebSocket Options

```typescript
interface WebSocketOptions {
  idleTimeout?: number             // Default: 120 (seconds)
  maxPayloadLength?: number        // Default: 16MB
  backpressureLimit?: number       // Default: 16KB
  closeOnBackpressureLimit?: boolean
  perMessageDeflate?: boolean | PerMessageDeflateOptions
}
```

### Cookie Options

```typescript
interface CookieOptions {
  secure?: boolean
  httpOnly?: boolean
  sameSite?: 'strict' | 'lax' | 'none'
  path?: string
  domain?: string
  maxAge?: number
  expires?: Date
  priority?: 'low' | 'medium' | 'high'
  partitioned?: boolean
  secrets?: string | string[]      // For signing
  sign?: string[]                  // Cookies to sign
}
```

## Route Methods

### Basic Routes

```typescript
.get(path: string, handler: Handler, options?: RouteOptions)
.post(path: string, handler: Handler, options?: RouteOptions)
.put(path: string, handler: Handler, options?: RouteOptions)
.delete(path: string, handler: Handler, options?: RouteOptions)
.patch(path: string, handler: Handler, options?: RouteOptions)
.options(path: string, handler: Handler, options?: RouteOptions)
.head(path: string, handler: Handler, options?: RouteOptions)
.all(path: string, handler: Handler, options?: RouteOptions)
.route(method: HTTPMethod | HTTPMethod[], path: string, handler: Handler, options?: RouteOptions)
```

### RouteOptions

```typescript
interface RouteOptions {
  // Validation schemas
  body?: TSchema
  query?: TSchema
  params?: TSchema
  headers?: TSchema
  cookie?: TSchema
  response?: TSchema | Record<number, TSchema>

  // Hooks
  beforeHandle?: Handler | Handler[]
  afterHandle?: AfterHandler | AfterHandler[]
  transform?: TransformHandler | TransformHandler[]
  parse?: Parser | Parser[] | 'json' | 'text' | 'formdata' | 'urlencoded' | 'none'
  error?: ErrorHandler | ErrorHandler[]
  afterResponse?: AfterResponseHandler | AfterResponseHandler[]

  // OpenAPI
  detail?: OpenAPIDetail

  // Type configuration
  type?: 'text' | 'json' | 'formdata' | 'urlencoded' | 'arrayBuffer' | 'none'
}
```

### Path Patterns

```typescript
// Static path
.get('/users', handler)

// Required parameter
.get('/user/:id', handler)
// params.id is string

// Optional parameter
.get('/user/:id?', handler)
// params.id is string | undefined

// Wildcard (catch-all)
.get('/files/*', handler)
// params['*'] captures entire remaining path

// Multiple parameters
.get('/org/:org/repo/:repo', handler)
// params.org, params.repo

// Regex constraint
.get('/id/:id(\\d+)', handler)
// Only matches numeric id
```

## Context Object

### Request Context

```typescript
interface Context {
  // Request data
  body: unknown                    // Parsed body
  query: Record<string, string>    // Query parameters
  params: Record<string, string>   // Path parameters
  headers: Record<string, string>  // Headers (lowercase keys)
  path: string                     // Request path
  request: Request                 // Raw Request object

  // Cookies
  cookie: {
    [name: string]: Cookie
  }

  // Response manipulation
  set: {
    headers: Record<string, string>
    status?: number
    redirect?: string
    cookie?: Record<string, CookieOptions>
  }

  // Utilities
  redirect(url: string, status?: number): Response
  status(code: number): StatusResponse
  status<T>(code: number, response: T): T

  // Server info
  server: Server | null
  ip: string | null

  // State
  store: Store                     // Global mutable state

  // Custom properties from derive/decorate
  [key: string]: unknown
}
```

### Cookie Methods

```typescript
interface Cookie {
  value: string
  get(): string
  set(options: SetCookieOptions): void
  remove(): void
  update(options: Partial<SetCookieOptions>): void
}

interface SetCookieOptions {
  value: string
  expires?: Date
  maxAge?: number
  domain?: string
  path?: string
  secure?: boolean
  httpOnly?: boolean
  sameSite?: 'strict' | 'lax' | 'none'
}
```

## State Management

### state

Add mutable global state:

```typescript
.state(name: string, value: unknown)
.state(record: Record<string, unknown>)

// Access via store
.get('/', ({ store }) => store.counter++)
```

### decorate

Add immutable context properties:

```typescript
.decorate(name: string, value: unknown)
.decorate(record: Record<string, unknown>)

// Access directly on context
.get('/', ({ db }) => db.query())
```

### derive

Create properties from existing context (before validation):

```typescript
.derive(fn: (context) => Record<string, unknown>)
.derive({ as: 'local' | 'scoped' | 'global' }, fn)

// With type inference
.derive(({ headers }) => ({
  token: headers.authorization?.slice(7)
}))
```

### resolve

Create properties from context (after validation):

```typescript
.resolve(fn: (context) => Record<string, unknown>)
.resolve({ as: 'local' | 'scoped' | 'global' }, fn)

// Type-safe with validated context
.resolve(({ userId }) => ({
  user: await getUser(userId)
}))
```

## Grouping and Guards

### group

Create route groups with prefix:

```typescript
.group(prefix: string, app: (app: Elysia) => Elysia)
.group(prefix: string, options: GroupOptions, app: (app: Elysia) => Elysia)

// Example
.group('/api/v1', app => app
  .get('/users', handler)
  .post('/users', handler)
)
```

### guard

Apply shared configuration to routes:

```typescript
.guard(options: GuardOptions, app: (app: Elysia) => Elysia)

interface GuardOptions extends RouteOptions {
  as?: 'local' | 'scoped' | 'global'
}

// Example
.guard({
  headers: t.Object({ authorization: t.String() })
}, app => app
  .get('/protected1', handler)
  .get('/protected2', handler)
)
```

## Plugin System

### use

Register a plugin:

```typescript
.use(plugin: Elysia | ((app: Elysia) => Elysia) | Promise<...>)

// Instance plugin
.use(myPlugin)

// Function plugin
.use(app => app.decorate('version', '1.0'))

// Async/lazy loading
.use(import('./plugin'))
```

### as

Lift plugin scope:

```typescript
.as('scoped')   // Lifts all decorators/state/etc to parent scope
.as('global')   // Lifts to all instances
```

### modules

Wait for all async plugins:

```typescript
await app.modules
```

## Server Methods

### listen

Start the server:

```typescript
.listen(port: number | string)
.listen(options: Serve)

// Example
app.listen(3000)
app.listen({ port: 3000, hostname: '0.0.0.0' })
```

### stop

Stop the server:

```typescript
await app.stop()
```

### handle

Handle a request without starting server:

```typescript
const response = await app.handle(request: Request)

// Useful for testing
const res = await app.handle(new Request('http://localhost/api'))
```

### server

Access the Bun server instance:

```typescript
app.server    // Server | null
app.server?.url
app.server?.hostname
app.server?.port
```

## Utility Functions

### file

Return a file response:

```typescript
import { file } from 'elysia'

.get('/image', () => file('image.png'))
.get('/download', () => file('document.pdf', {
  type: 'application/pdf',
  headers: { 'Content-Disposition': 'attachment' }
}))
```

### redirect

Return a redirect response:

```typescript
import { redirect } from 'elysia'

.get('/old', () => redirect('/new'))
.get('/external', () => redirect('https://example.com', 301))
```

### Error Classes

```typescript
import {
  NotFoundError,
  ParseError,
  ValidationError,
  InternalServerError,
  InvalidCookieSignature
} from 'elysia'

throw new NotFoundError('User not found')
throw new ValidationError('Invalid input', errors)
```

## Type Exports

```typescript
import type {
  Elysia,
  Context,
  Handler,
  RouteOptions,
  ElysiaOptions,
  Cookie,
  CookieOptions,
  PreHandler,
  AfterHandler,
  ErrorHandler,
  TransformHandler,
  LocalHook,
  InputSchema,
  MergeSchema,
  UnwrapRoute
} from 'elysia'
```

## TypeBox Integration

```typescript
import { t } from 'elysia'

// t is re-exported from @sinclair/typebox with Elysia extensions
t.String()
t.Number()
t.Boolean()
t.Object({})
t.Array(t.String())
t.Union([...])
t.Literal('value')
t.Optional(t.String())
t.Nullable(t.String())
t.Numeric()      // Elysia extension
t.File()         // Elysia extension
t.Files()        // Elysia extension
t.Cookie({})     // Elysia extension
```
