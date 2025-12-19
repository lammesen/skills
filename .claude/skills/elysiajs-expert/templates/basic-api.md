# Basic Elysia API Template

A minimal template for starting a new Elysia API project.

## Project Structure

```
project/
├── src/
│   ├── index.ts           # Entry point
│   ├── modules/
│   │   └── user/
│   │       ├── index.ts   # Routes
│   │       └── model.ts   # Schemas
│   └── shared/
│       └── response.ts    # Response helpers
├── test/
│   └── user.test.ts
├── package.json
├── tsconfig.json
└── biome.json
```

## Files

### package.json

```json
{
  "name": "elysia-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "bun --watch src/index.ts",
    "start": "bun src/index.ts",
    "test": "bun test",
    "build": "bun build --compile --minify src/index.ts --outfile server",
    "lint": "bunx biome check src/",
    "format": "bunx biome format --write src/"
  },
  "dependencies": {
    "elysia": "^1.0.0",
    "@elysiajs/cors": "^1.0.0",
    "@elysiajs/openapi": "^1.0.0"
  },
  "devDependencies": {
    "@types/bun": "latest",
    "@biomejs/biome": "latest",
    "@elysiajs/eden": "^1.0.0"
  }
}
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "declaration": true,
    "outDir": "dist",
    "types": ["bun-types"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

### biome.json

```json
{
  "$schema": "https://biomejs.dev/schemas/1.4.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": { "recommended": true }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2
  }
}
```

### src/index.ts

```typescript
import { Elysia } from 'elysia'
import { cors } from '@elysiajs/cors'
import { openapi } from '@elysiajs/openapi'
import { userRoutes } from './modules/user'

const app = new Elysia()
  .use(cors())
  .use(openapi({
    path: '/docs',
    documentation: {
      info: {
        title: 'My API',
        version: '1.0.0'
      }
    }
  }))
  .get('/health', () => ({ status: 'ok', timestamp: new Date().toISOString() }))
  .use(userRoutes)
  .listen(process.env.PORT ?? 3000)

console.log(`🦊 Elysia running at ${app.server?.url}`)
console.log(`📚 API docs at ${app.server?.url}docs`)

export type App = typeof app
export default app
```

### src/shared/response.ts

```typescript
export const success = <T>(data: T) => ({
  success: true as const,
  data
})

export const error = (code: string, message: string) => ({
  success: false as const,
  error: { code, message }
})
```

### src/modules/user/model.ts

```typescript
import { t } from 'elysia'

export const UserSchema = t.Object({
  id: t.String(),
  email: t.String({ format: 'email' }),
  name: t.String(),
  createdAt: t.String({ format: 'date-time' })
})

export const CreateUserSchema = t.Object({
  email: t.String({ format: 'email' }),
  name: t.String({ minLength: 2, maxLength: 100 })
})

export const UpdateUserSchema = t.Partial(CreateUserSchema)
```

### src/modules/user/index.ts

```typescript
import { Elysia, t } from 'elysia'
import { CreateUserSchema, UpdateUserSchema, UserSchema } from './model'
import { success, error } from '../../shared/response'

// In-memory store (replace with database)
const users = new Map<string, any>()

export const userRoutes = new Elysia({ prefix: '/users' })
  .get('/', () => {
    return success([...users.values()])
  }, {
    response: t.Object({
      success: t.Boolean(),
      data: t.Array(UserSchema)
    }),
    detail: {
      tags: ['Users'],
      summary: 'List all users'
    }
  })

  .get('/:id', ({ params, status }) => {
    const user = users.get(params.id)
    if (!user) {
      return status(404, error('NOT_FOUND', 'User not found'))
    }
    return success(user)
  }, {
    params: t.Object({ id: t.String() }),
    detail: {
      tags: ['Users'],
      summary: 'Get user by ID'
    }
  })

  .post('/', ({ body }) => {
    const user = {
      id: crypto.randomUUID(),
      ...body,
      createdAt: new Date().toISOString()
    }
    users.set(user.id, user)
    return success(user)
  }, {
    body: CreateUserSchema,
    response: t.Object({
      success: t.Boolean(),
      data: UserSchema
    }),
    detail: {
      tags: ['Users'],
      summary: 'Create a new user'
    }
  })

  .patch('/:id', ({ params, body, status }) => {
    const user = users.get(params.id)
    if (!user) {
      return status(404, error('NOT_FOUND', 'User not found'))
    }
    const updated = { ...user, ...body }
    users.set(params.id, updated)
    return success(updated)
  }, {
    params: t.Object({ id: t.String() }),
    body: UpdateUserSchema,
    detail: {
      tags: ['Users'],
      summary: 'Update a user'
    }
  })

  .delete('/:id', ({ params, status }) => {
    if (!users.has(params.id)) {
      return status(404, error('NOT_FOUND', 'User not found'))
    }
    users.delete(params.id)
    return status(204)
  }, {
    params: t.Object({ id: t.String() }),
    detail: {
      tags: ['Users'],
      summary: 'Delete a user'
    }
  })
```

### test/user.test.ts

```typescript
import { describe, expect, it, beforeEach } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import app from '../src'

describe('User API', () => {
  const api = treaty(app)

  it('should create a user', async () => {
    const { data, error } = await api.users.post({
      email: 'test@example.com',
      name: 'Test User'
    })

    expect(error).toBeNull()
    expect(data?.success).toBe(true)
    expect(data?.data.email).toBe('test@example.com')
  })

  it('should list users', async () => {
    const { data, error } = await api.users.get()

    expect(error).toBeNull()
    expect(data?.success).toBe(true)
    expect(Array.isArray(data?.data)).toBe(true)
  })

  it('should get user by id', async () => {
    // Create user first
    const { data: created } = await api.users.post({
      email: 'get@example.com',
      name: 'Get User'
    })

    const { data, error } = await api.users({ id: created!.data.id }).get()

    expect(error).toBeNull()
    expect(data?.success).toBe(true)
    expect(data?.data.id).toBe(created!.data.id)
  })

  it('should return 404 for non-existent user', async () => {
    const { error } = await api.users({ id: 'non-existent' }).get()

    expect(error).not.toBeNull()
    expect(error?.status).toBe(404)
  })
})
```

## Getting Started

```bash
# Create project
mkdir my-api && cd my-api

# Initialize
bun init

# Install dependencies
bun add elysia @elysiajs/cors @elysiajs/openapi
bun add -d @types/bun @biomejs/biome @elysiajs/eden

# Create files from template

# Run development server
bun dev

# Run tests
bun test

# Build for production
bun run build
```

## Next Steps

1. Replace in-memory store with a database (see bun-expert skill for SQLite)
2. Add authentication (see auth-api template)
3. Add validation error handling
4. Configure environment variables
5. Set up CI/CD
