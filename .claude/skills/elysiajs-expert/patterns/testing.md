# Testing Patterns

Comprehensive testing patterns for Elysia applications.

## Testing Setup

### Test Configuration

```typescript
// test/setup.ts
import { beforeAll, afterAll, afterEach } from 'bun:test'

// Setup test database
beforeAll(async () => {
  await db.$connect()
  await db.$executeRaw`TRUNCATE TABLE users CASCADE`
})

afterEach(async () => {
  // Clean up between tests
  await db.$executeRaw`TRUNCATE TABLE users CASCADE`
})

afterAll(async () => {
  await db.$disconnect()
})
```

### Test Utilities

```typescript
// test/utils.ts
import { treaty } from '@elysiajs/eden'
import { app } from '../src/server'

export const api = treaty(app)

export const createTestUser = async (data?: Partial<User>) => {
  const { data: user } = await api.users.post({
    email: data?.email ?? `test-${Date.now()}@example.com`,
    name: data?.name ?? 'Test User',
    password: 'password123'
  })
  return user!
}

export const getAuthToken = async (email: string, password: string) => {
  const { data } = await api.auth.login.post({ email, password })
  return data!.token
}

export const authenticatedApi = (token: string) =>
  treaty(app, {
    headers: { authorization: `Bearer ${token}` }
  })
```

## Unit Testing with bun:test

### Basic Route Tests

```typescript
import { describe, expect, it } from 'bun:test'
import { Elysia } from 'elysia'

describe('Routes', () => {
  const app = new Elysia()
    .get('/', () => 'Hello World')
    .get('/user/:id', ({ params }) => ({ id: params.id }))

  it('should return hello world', async () => {
    const response = await app.handle(
      new Request('http://localhost/')
    )

    expect(response.status).toBe(200)
    expect(await response.text()).toBe('Hello World')
  })

  it('should return user by id', async () => {
    const response = await app.handle(
      new Request('http://localhost/user/123')
    )

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({ id: '123' })
  })
})
```

### Testing POST Requests

```typescript
import { describe, expect, it } from 'bun:test'
import { Elysia, t } from 'elysia'

describe('POST /users', () => {
  const app = new Elysia()
    .post('/users', ({ body }) => ({
      id: crypto.randomUUID(),
      ...body
    }), {
      body: t.Object({
        name: t.String(),
        email: t.String({ format: 'email' })
      })
    })

  it('should create a user', async () => {
    const response = await app.handle(
      new Request('http://localhost/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: 'John Doe',
          email: 'john@example.com'
        })
      })
    )

    expect(response.status).toBe(200)
    const user = await response.json()
    expect(user.name).toBe('John Doe')
    expect(user.email).toBe('john@example.com')
    expect(user.id).toBeDefined()
  })

  it('should validate email format', async () => {
    const response = await app.handle(
      new Request('http://localhost/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: 'John Doe',
          email: 'invalid-email'
        })
      })
    )

    expect(response.status).toBe(422)
  })
})
```

## Testing with Eden

### Type-Safe Testing

```typescript
import { describe, expect, it } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import { app } from '../src/server'

describe('User API', () => {
  // Create typed client from app instance (no network!)
  const api = treaty(app)

  it('should list users', async () => {
    const { data, error, status } = await api.users.get()

    expect(error).toBeNull()
    expect(status).toBe(200)
    expect(Array.isArray(data)).toBe(true)
  })

  it('should create a user', async () => {
    const { data, error } = await api.users.post({
      name: 'John Doe',
      email: 'john@example.com',
      password: 'password123'
    })

    expect(error).toBeNull()
    expect(data?.name).toBe('John Doe')
    expect(data?.email).toBe('john@example.com')
  })

  it('should get user by id', async () => {
    // Create user first
    const { data: created } = await api.users.post({
      name: 'Test User',
      email: 'test@example.com',
      password: 'password123'
    })

    // Get user
    const { data, error } = await api.users({ id: created!.id }).get()

    expect(error).toBeNull()
    expect(data?.id).toBe(created!.id)
  })

  it('should return 404 for non-existent user', async () => {
    const { data, error } = await api.users({ id: 'non-existent' }).get()

    expect(data).toBeNull()
    expect(error?.status).toBe(404)
  })
})
```

### Testing with Authentication

```typescript
import { describe, expect, it, beforeAll } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import { app } from '../src/server'

describe('Protected Routes', () => {
  let token: string
  const api = treaty(app)

  beforeAll(async () => {
    // Create user and login
    await api.auth.register.post({
      email: 'test@example.com',
      password: 'password123',
      name: 'Test User'
    })

    const { data } = await api.auth.login.post({
      email: 'test@example.com',
      password: 'password123'
    })

    token = data!.token
  })

  it('should access protected route with token', async () => {
    const authApi = treaty(app, {
      headers: { authorization: `Bearer ${token}` }
    })

    const { data, error } = await authApi.me.get()

    expect(error).toBeNull()
    expect(data?.email).toBe('test@example.com')
  })

  it('should reject without token', async () => {
    const { error } = await api.me.get()

    expect(error).not.toBeNull()
    expect(error?.status).toBe(401)
  })

  it('should reject with invalid token', async () => {
    const badApi = treaty(app, {
      headers: { authorization: 'Bearer invalid-token' }
    })

    const { error } = await badApi.me.get()

    expect(error?.status).toBe(401)
  })
})
```

## Testing Specific Features

### Validation Testing

```typescript
import { describe, expect, it } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import { app } from '../src/server'

describe('Validation', () => {
  const api = treaty(app)

  it('should reject missing required fields', async () => {
    const { error } = await api.users.post({
      name: 'John'
      // missing email and password
    } as any)

    expect(error?.status).toBe(422)
  })

  it('should reject invalid email format', async () => {
    const { error } = await api.users.post({
      name: 'John',
      email: 'not-an-email',
      password: 'password123'
    })

    expect(error?.status).toBe(422)
  })

  it('should reject short password', async () => {
    const { error } = await api.users.post({
      name: 'John',
      email: 'john@example.com',
      password: '123' // too short
    })

    expect(error?.status).toBe(422)
  })

  it('should accept valid input', async () => {
    const { data, error } = await api.users.post({
      name: 'John',
      email: 'john@example.com',
      password: 'password123'
    })

    expect(error).toBeNull()
    expect(data).toBeDefined()
  })
})
```

### Hook Testing

```typescript
import { describe, expect, it } from 'bun:test'
import { Elysia } from 'elysia'

describe('Hooks', () => {
  it('should execute beforeHandle', async () => {
    let hookExecuted = false

    const app = new Elysia()
      .get('/test', () => 'ok', {
        beforeHandle() {
          hookExecuted = true
        }
      })

    await app.handle(new Request('http://localhost/test'))

    expect(hookExecuted).toBe(true)
  })

  it('should execute derive and add context', async () => {
    const app = new Elysia()
      .derive(() => ({ customValue: 'test' }))
      .get('/test', ({ customValue }) => customValue)

    const response = await app.handle(new Request('http://localhost/test'))
    const text = await response.text()

    expect(text).toBe('test')
  })

  it('should execute afterHandle', async () => {
    const app = new Elysia()
      .onAfterHandle(({ responseValue }) => ({
        wrapped: responseValue
      }))
      .get('/test', () => 'original')

    const response = await app.handle(new Request('http://localhost/test'))
    const json = await response.json()

    expect(json).toEqual({ wrapped: 'original' })
  })
})
```

### WebSocket Testing

```typescript
import { describe, expect, it } from 'bun:test'
import { Elysia, t } from 'elysia'

describe('WebSocket', () => {
  const app = new Elysia()
    .ws('/ws', {
      body: t.Object({ message: t.String() }),
      message(ws, { message }) {
        ws.send({ echo: message })
      }
    })

  it('should echo messages', async () => {
    // Start server temporarily
    const server = app.listen(0)
    const port = server.server!.port

    const ws = new WebSocket(`ws://localhost:${port}/ws`)

    const response = await new Promise<any>((resolve) => {
      ws.onmessage = (event) => {
        resolve(JSON.parse(event.data))
        ws.close()
      }
      ws.onopen = () => {
        ws.send(JSON.stringify({ message: 'hello' }))
      }
    })

    expect(response).toEqual({ echo: 'hello' })

    server.stop()
  })
})
```

### Plugin Testing

```typescript
import { describe, expect, it } from 'bun:test'
import { Elysia } from 'elysia'

describe('Plugin', () => {
  const myPlugin = new Elysia({ name: 'my-plugin' })
    .decorate('pluginValue', 'test')
    .get('/plugin-route', ({ pluginValue }) => pluginValue)

  it('should add decorators', async () => {
    const app = new Elysia().use(myPlugin)

    const response = await app.handle(
      new Request('http://localhost/plugin-route')
    )

    expect(await response.text()).toBe('test')
  })

  it('should work with multiple instances', async () => {
    const app1 = new Elysia().use(myPlugin)
    const app2 = new Elysia().use(myPlugin)

    const res1 = await app1.handle(new Request('http://localhost/plugin-route'))
    const res2 = await app2.handle(new Request('http://localhost/plugin-route'))

    expect(await res1.text()).toBe('test')
    expect(await res2.text()).toBe('test')
  })
})
```

## Integration Testing

### Database Integration

```typescript
import { describe, expect, it, beforeEach, afterAll } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import { app } from '../src/server'
import { db } from '../src/db'

describe('User Integration', () => {
  const api = treaty(app)

  beforeEach(async () => {
    await db.user.deleteMany()
  })

  afterAll(async () => {
    await db.$disconnect()
  })

  it('should persist user to database', async () => {
    const { data } = await api.users.post({
      name: 'John Doe',
      email: 'john@example.com',
      password: 'password123'
    })

    const dbUser = await db.user.findUnique({
      where: { id: data!.id }
    })

    expect(dbUser).not.toBeNull()
    expect(dbUser!.email).toBe('john@example.com')
  })

  it('should hash password', async () => {
    const { data } = await api.users.post({
      name: 'John Doe',
      email: 'john@example.com',
      password: 'password123'
    })

    const dbUser = await db.user.findUnique({
      where: { id: data!.id }
    })

    expect(dbUser!.password).not.toBe('password123')
    expect(await Bun.password.verify('password123', dbUser!.password)).toBe(true)
  })
})
```

### E2E Testing

```typescript
import { describe, expect, it, beforeAll, afterAll } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import type { App } from '../src/server'

describe('E2E Flow', () => {
  let api: ReturnType<typeof treaty<App>>
  let server: any

  beforeAll(async () => {
    // Start actual server
    const { app } = await import('../src/server')
    server = app.listen(3001)
    api = treaty<App>('localhost:3001')
  })

  afterAll(() => {
    server.stop()
  })

  it('should complete full user flow', async () => {
    // Register
    const { data: registerData } = await api.auth.register.post({
      email: 'e2e@example.com',
      password: 'password123',
      name: 'E2E User'
    })
    expect(registerData).toBeDefined()

    // Login
    const { data: loginData } = await api.auth.login.post({
      email: 'e2e@example.com',
      password: 'password123'
    })
    expect(loginData?.token).toBeDefined()

    // Access protected route
    const authApi = treaty<App>('localhost:3001', {
      headers: { authorization: `Bearer ${loginData!.token}` }
    })

    const { data: profileData } = await authApi.me.get()
    expect(profileData?.email).toBe('e2e@example.com')

    // Update profile
    const { data: updatedData } = await authApi.me.patch({
      name: 'Updated Name'
    })
    expect(updatedData?.name).toBe('Updated Name')
  })
})
```

## Test Helpers

### Factory Functions

```typescript
// test/factories.ts
import { faker } from '@faker-js/faker'

export const userFactory = (overrides?: Partial<CreateUserInput>) => ({
  email: faker.internet.email(),
  name: faker.person.fullName(),
  password: faker.internet.password({ length: 12 }),
  ...overrides
})

export const postFactory = (overrides?: Partial<CreatePostInput>) => ({
  title: faker.lorem.sentence(),
  content: faker.lorem.paragraphs(3),
  published: faker.datatype.boolean(),
  ...overrides
})
```

### Mock Services

```typescript
// test/mocks.ts
export const mockUserService = {
  findById: vi.fn(),
  create: vi.fn(),
  update: vi.fn(),
  delete: vi.fn()
}

// In tests
import { mockUserService } from './mocks'

mockUserService.findById.mockResolvedValue({
  id: '123',
  name: 'Mock User',
  email: 'mock@example.com'
})
```

## Running Tests

```bash
# Run all tests
bun test

# Run specific test file
bun test test/users.test.ts

# Run tests matching pattern
bun test --grep "should create"

# Watch mode
bun test --watch

# Coverage
bun test --coverage
```
