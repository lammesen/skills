# ElysiaJS Official Plugins Reference

Complete reference for all official Elysia plugins.

## @elysiajs/openapi

API documentation with Scalar or Swagger UI.

### Installation

```bash
bun add @elysiajs/openapi
```

### Basic Usage

```typescript
import { Elysia } from 'elysia'
import { openapi } from '@elysiajs/openapi'

new Elysia()
  .use(openapi())
  .get('/user', () => 'user')
  .listen(3000)

// Docs at http://localhost:3000/swagger
```

### Configuration

```typescript
.use(openapi({
  // UI Provider
  provider: 'scalar',          // 'scalar' | 'swagger-ui' | null

  // Paths
  path: '/swagger',            // Base path for docs
  specPath: '/swagger/json',   // OpenAPI spec path

  // OpenAPI documentation
  documentation: {
    openapi: '3.1.0',
    info: {
      title: 'My API',
      version: '1.0.0',
      description: 'API Description',
      contact: {
        name: 'Support',
        email: 'support@example.com'
      },
      license: {
        name: 'MIT',
        url: 'https://opensource.org/licenses/MIT'
      }
    },
    servers: [
      { url: 'https://api.example.com', description: 'Production' },
      { url: 'http://localhost:3000', description: 'Development' }
    ],
    tags: [
      { name: 'User', description: 'User management' },
      { name: 'Auth', description: 'Authentication' }
    ],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT'
        },
        apiKey: {
          type: 'apiKey',
          in: 'header',
          name: 'X-API-Key'
        }
      }
    },
    security: [{ bearerAuth: [] }]  // Global security
  },

  // Exclusions
  exclude: {
    methods: ['OPTIONS'],
    paths: ['/health', '/metrics'],
    tags: ['internal']
  },

  // Scalar configuration
  scalarConfig: {
    theme: 'default',
    layout: 'classic',
    darkMode: true
  },

  // Swagger UI configuration
  swaggerOptions: {
    persistAuthorization: true
  }
}))
```

### Route Documentation

```typescript
.get('/user/:id', ({ params }) => getUser(params.id), {
  params: t.Object({ id: t.String() }),
  response: t.Object({
    id: t.String(),
    name: t.String()
  }),
  detail: {
    tags: ['User'],
    summary: 'Get user by ID',
    description: 'Retrieves a user by their unique identifier',
    operationId: 'getUserById',
    deprecated: false,
    security: [{ bearerAuth: [] }],
    responses: {
      200: { description: 'User found' },
      404: { description: 'User not found' }
    }
  }
})
```

## @elysiajs/jwt

JSON Web Token authentication.

### Installation

```bash
bun add @elysiajs/jwt
```

### Basic Usage

```typescript
import { Elysia } from 'elysia'
import { jwt } from '@elysiajs/jwt'

new Elysia()
  .use(jwt({
    name: 'jwt',
    secret: process.env.JWT_SECRET!
  }))
  .post('/login', async ({ jwt, body }) => {
    const token = await jwt.sign({ userId: body.id })
    return { token }
  })
  .get('/profile', async ({ jwt, headers, status }) => {
    const auth = headers.authorization?.slice(7)
    const payload = await jwt.verify(auth)
    if (!payload) return status(401)
    return payload
  })
```

### Configuration

```typescript
.use(jwt({
  name: 'jwt',                 // Property name on context
  secret: 'secret',            // Required: signing secret

  // Algorithm
  alg: 'HS256',               // HS256 | HS384 | HS512 | RS256 | etc.

  // Claims
  iss: 'my-app',              // Issuer
  sub: 'user',                // Subject
  aud: 'api',                 // Audience
  exp: '7d',                  // Expiration (string or seconds)
  nbf: Date.now() / 1000,     // Not before
  iat: true,                  // Include issued at
  jti: true,                  // Include JWT ID

  // RS256 configuration
  privateKey: rsaPrivateKey,
  publicKey: rsaPublicKey
}))
```

### JWT Methods

```typescript
// Sign a payload
const token = await jwt.sign({
  userId: '123',
  role: 'admin'
})

// Verify a token
const payload = await jwt.verify(token)
// Returns payload or false if invalid

// Sign with custom expiration
const token = await jwt.sign({ userId: '123' }, { exp: '1h' })
```

### Multiple JWT Configurations

```typescript
.use(jwt({ name: 'accessJwt', secret: ACCESS_SECRET, exp: '15m' }))
.use(jwt({ name: 'refreshJwt', secret: REFRESH_SECRET, exp: '7d' }))

.post('/login', async ({ accessJwt, refreshJwt }) => ({
  accessToken: await accessJwt.sign({ userId: '123' }),
  refreshToken: await refreshJwt.sign({ userId: '123' })
}))
```

## @elysiajs/bearer

Bearer token extraction.

### Installation

```bash
bun add @elysiajs/bearer
```

### Usage

```typescript
import { Elysia } from 'elysia'
import { bearer } from '@elysiajs/bearer'

new Elysia()
  .use(bearer())
  .get('/protected', ({ bearer, status }) => {
    if (!bearer) return status(401, 'Unauthorized')
    return `Token: ${bearer}`
  })
```

### Combined with JWT

```typescript
.use(jwt({ name: 'jwt', secret: 'secret' }))
.use(bearer())
.derive(async ({ jwt, bearer, status }) => {
  if (!bearer) return status(401)
  const payload = await jwt.verify(bearer)
  if (!payload) return status(401)
  return { user: payload }
})
.get('/me', ({ user }) => user)
```

## @elysiajs/cors

Cross-Origin Resource Sharing.

### Installation

```bash
bun add @elysiajs/cors
```

### Basic Usage

```typescript
import { Elysia } from 'elysia'
import { cors } from '@elysiajs/cors'

new Elysia()
  .use(cors())
  .listen(3000)
```

### Configuration

```typescript
.use(cors({
  // Origins
  origin: true,                        // Allow all
  origin: 'https://example.com',       // Single origin
  origin: ['https://a.com', 'https://b.com'],  // Multiple
  origin: /\.example\.com$/,           // Regex
  origin: (request) => true,           // Function

  // Methods
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],

  // Headers
  allowedHeaders: ['Content-Type', 'Authorization'],
  exposedHeaders: ['X-Request-Id'],

  // Credentials
  credentials: true,

  // Cache
  maxAge: 600,                         // Preflight cache (seconds)

  // Preflight
  preflight: true                      // Handle OPTIONS automatically
}))
```

### Per-Route CORS

```typescript
import { cors } from '@elysiajs/cors'

.group('/api', app => app
  .use(cors({ origin: 'https://app.example.com' }))
  .get('/data', handler)
)
```

## @elysiajs/static

Static file serving.

### Installation

```bash
bun add @elysiajs/static
```

### Basic Usage

```typescript
import { Elysia } from 'elysia'
import { staticPlugin } from '@elysiajs/static'

new Elysia()
  .use(staticPlugin())  // Serves ./public
  .listen(3000)
```

### Configuration

```typescript
.use(staticPlugin({
  assets: 'public',              // Directory to serve
  prefix: '/static',             // URL prefix
  indexHTML: true,               // Serve index.html for directories
  noCache: false,                // Disable caching
  headers: {                     // Custom headers
    'Cache-Control': 'max-age=3600'
  },
  alwaysStatic: false,           // Skip routing for static files
  staticLimit: 1024,             // Max static routes before fallback
  ignorePatterns: ['*.ts'],      // Patterns to ignore
  enableDecodeURI: true          // Decode URI components
}))
```

### Multiple Static Directories

```typescript
.use(staticPlugin({ assets: 'public', prefix: '/public' }))
.use(staticPlugin({ assets: 'uploads', prefix: '/uploads' }))
```

## @elysiajs/html

HTML responses and JSX support.

### Installation

```bash
bun add @elysiajs/html
```

### Basic Usage

```typescript
import { Elysia } from 'elysia'
import { html } from '@elysiajs/html'

new Elysia()
  .use(html())
  .get('/', () => `
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Hello World</h1>
      </body>
    </html>
  `)
```

### Configuration

```typescript
.use(html({
  autoDetect: true,              // Auto-detect HTML content
  autoDoctype: true,             // Add DOCTYPE automatically
  contentType: 'text/html; charset=utf-8',
  isHtml: (value) => typeof value === 'string' && value.includes('<')
}))
```

### JSX Support

```typescript
// Add to tsconfig.json:
// "jsx": "react-jsx",
// "jsxImportSource": "@elysiajs/html"

import { Elysia } from 'elysia'
import { html } from '@elysiajs/html'

new Elysia()
  .use(html())
  .get('/', () => (
    <html>
      <body>
        <h1>Hello JSX</h1>
      </body>
    </html>
  ))
```

## @elysiajs/cron

Scheduled task execution.

### Installation

```bash
bun add @elysiajs/cron
```

### Basic Usage

```typescript
import { Elysia } from 'elysia'
import { cron } from '@elysiajs/cron'

new Elysia()
  .use(cron({
    name: 'heartbeat',
    pattern: '*/10 * * * * *',   // Every 10 seconds
    run() {
      console.log('tick')
    }
  }))
```

### Cron Pattern Format

```
┌────────────── second (0-59) [optional]
│ ┌──────────── minute (0-59)
│ │ ┌────────── hour (0-23)
│ │ │ ┌──────── day of month (1-31)
│ │ │ │ ┌────── month (1-12)
│ │ │ │ │ ┌──── day of week (0-7, 0 or 7 is Sunday)
│ │ │ │ │ │
* * * * * *
```

### Examples

```typescript
// Every minute
.use(cron({ name: 'minute', pattern: '* * * * *', run() {} }))

// Every hour
.use(cron({ name: 'hourly', pattern: '0 * * * *', run() {} }))

// Every day at midnight
.use(cron({ name: 'daily', pattern: '0 0 * * *', run() {} }))

// Every Monday at 9am
.use(cron({ name: 'weekly', pattern: '0 9 * * 1', run() {} }))

// Multiple jobs
.use(cron({ name: 'job1', pattern: '*/5 * * * *', run: job1 }))
.use(cron({ name: 'job2', pattern: '0 * * * *', run: job2 }))
```

### Accessing Store

```typescript
.state('count', 0)
.use(cron({
  name: 'counter',
  pattern: '* * * * * *',
  run() {
    this.store.count++
  }
}))
```

## @elysiajs/graphql-yoga

GraphQL integration with GraphQL Yoga.

### Installation

```bash
bun add @elysiajs/graphql-yoga graphql
```

### Basic Usage

```typescript
import { Elysia } from 'elysia'
import { yoga } from '@elysiajs/graphql-yoga'

new Elysia()
  .use(yoga({
    typeDefs: `
      type Query {
        hello: String
      }
    `,
    resolvers: {
      Query: {
        hello: () => 'Hello World'
      }
    }
  }))
  .listen(3000)

// GraphQL at http://localhost:3000/graphql
```

### Configuration

```typescript
.use(yoga({
  path: '/graphql',              // GraphQL endpoint
  typeDefs: schema,
  resolvers: resolvers,

  // Context function
  context: ({ request }) => ({
    user: getUserFromRequest(request)
  }),

  // GraphQL Yoga options
  maskedErrors: true,
  cors: true,
  graphiql: true
}))
```

### With Elysia Context

```typescript
.use(jwt({ name: 'jwt', secret: 'secret' }))
.use(yoga({
  typeDefs: `
    type Query {
      me: User
    }
    type User {
      id: ID!
      name: String!
    }
  `,
  resolvers: {
    Query: {
      me: (_, __, { jwt, request }) => {
        // Access Elysia context
        const token = request.headers.get('authorization')?.slice(7)
        return jwt.verify(token)
      }
    }
  }
}))
```

## @elysiajs/trpc

tRPC integration.

### Installation

```bash
bun add @elysiajs/trpc @trpc/server
```

### Basic Usage

```typescript
import { Elysia, t } from 'elysia'
import { trpc, compile as c } from '@elysiajs/trpc'
import { initTRPC } from '@trpc/server'

const tr = initTRPC.create()

const router = tr.router({
  greet: tr.procedure
    .input(c(t.String()))
    .query(({ input }) => `Hello ${input}`)
})

new Elysia()
  .use(trpc(router))
  .listen(3000)

// tRPC at http://localhost:3000/trpc
```

### Configuration

```typescript
.use(trpc(router, {
  endpoint: '/trpc',              // tRPC endpoint
  createContext: ({ request }) => ({
    user: getUser(request)
  })
}))
```

### Using TypeBox Schemas

```typescript
import { compile as c } from '@elysiajs/trpc'
import { t } from 'elysia'

const router = tr.router({
  createUser: tr.procedure
    .input(c(t.Object({
      name: t.String(),
      email: t.String({ format: 'email' })
    })))
    .mutation(({ input }) => createUser(input))
})
```

## @elysiajs/server-timing

Server timing headers for performance monitoring.

### Installation

```bash
bun add @elysiajs/server-timing
```

### Usage

```typescript
import { Elysia } from 'elysia'
import { serverTiming } from '@elysiajs/server-timing'

new Elysia()
  .use(serverTiming({
    enabled: process.env.NODE_ENV !== 'production',
    allow: true                  // Or function to filter
  }))
  .get('/api', () => 'Hello')
```

### Response Header

```
Server-Timing: elysia;dur=0.5
```

## @elysiajs/stream

Server-Sent Events and streaming.

### Installation

```bash
bun add @elysiajs/stream
```

### Server-Sent Events

```typescript
import { Elysia } from 'elysia'
import { Stream } from '@elysiajs/stream'

new Elysia()
  .get('/sse', () =>
    new Stream(async (stream) => {
      for (let i = 0; i < 10; i++) {
        stream.send({ event: 'message', data: `Event ${i}` })
        await Bun.sleep(1000)
      }
      stream.close()
    })
  )
```

### Generator Streaming

```typescript
.get('/stream', async function* () {
  for (let i = 0; i < 10; i++) {
    yield `data: Event ${i}\n\n`
    await Bun.sleep(100)
  }
})
```

## Plugin Ordering

Plugins should be registered in this order:

1. **Infrastructure** (CORS, compression)
2. **Authentication** (JWT, bearer)
3. **Documentation** (OpenAPI)
4. **Features** (static, cron)
5. **Routes**

```typescript
new Elysia()
  .use(cors())
  .use(jwt({ name: 'jwt', secret: 'secret' }))
  .use(bearer())
  .use(openapi())
  .use(staticPlugin())
  .use(userRoutes)
  .use(authRoutes)
  .listen(3000)
```
