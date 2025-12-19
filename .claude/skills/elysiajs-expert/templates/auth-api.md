# Authenticated Elysia API Template

A template for Elysia APIs with JWT authentication, protected routes, and role-based access.

## Project Structure

```
project/
├── src/
│   ├── index.ts
│   ├── config/
│   │   └── env.ts
│   ├── modules/
│   │   ├── auth/
│   │   │   ├── index.ts
│   │   │   ├── service.ts
│   │   │   └── model.ts
│   │   └── user/
│   │       ├── index.ts
│   │       └── model.ts
│   └── shared/
│       ├── auth.ts
│       ├── database.ts
│       └── response.ts
├── test/
│   ├── auth.test.ts
│   └── user.test.ts
├── package.json
└── .env
```

## Files

### package.json

```json
{
  "name": "elysia-auth-api",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "bun --watch src/index.ts",
    "start": "bun src/index.ts",
    "test": "bun test",
    "build": "bun build --compile --minify src/index.ts --outfile server"
  },
  "dependencies": {
    "elysia": "^1.0.0",
    "@elysiajs/cors": "^1.0.0",
    "@elysiajs/jwt": "^1.0.0",
    "@elysiajs/bearer": "^1.0.0",
    "@elysiajs/openapi": "^1.0.0"
  },
  "devDependencies": {
    "@types/bun": "latest",
    "@elysiajs/eden": "^1.0.0"
  }
}
```

### .env

```bash
PORT=3000
JWT_SECRET=your-super-secret-jwt-key-change-in-production
JWT_EXPIRES_IN=7d
```

### src/config/env.ts

```typescript
import { t } from 'elysia'

const envSchema = t.Object({
  PORT: t.String({ default: '3000' }),
  JWT_SECRET: t.String({ minLength: 32 }),
  JWT_EXPIRES_IN: t.String({ default: '7d' })
})

function validateEnv() {
  const env = {
    PORT: process.env.PORT ?? '3000',
    JWT_SECRET: process.env.JWT_SECRET,
    JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN ?? '7d'
  }

  if (!env.JWT_SECRET) {
    throw new Error('JWT_SECRET environment variable is required')
  }

  return env as {
    PORT: string
    JWT_SECRET: string
    JWT_EXPIRES_IN: string
  }
}

export const env = validateEnv()
```

### src/shared/database.ts

```typescript
// Simple in-memory database (replace with real database)
interface User {
  id: string
  email: string
  name: string
  password: string
  role: 'user' | 'admin'
  createdAt: string
}

const users = new Map<string, User>()

export const db = {
  users: {
    findByEmail: (email: string) =>
      [...users.values()].find(u => u.email === email),

    findById: (id: string) => users.get(id),

    create: (data: Omit<User, 'id' | 'createdAt'>) => {
      const user: User = {
        ...data,
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString()
      }
      users.set(user.id, user)
      return user
    },

    findAll: () => [...users.values()],

    update: (id: string, data: Partial<User>) => {
      const user = users.get(id)
      if (!user) return null
      const updated = { ...user, ...data }
      users.set(id, updated)
      return updated
    },

    delete: (id: string) => users.delete(id)
  }
}
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

### src/shared/auth.ts

```typescript
import { Elysia } from 'elysia'
import { jwt } from '@elysiajs/jwt'
import { bearer } from '@elysiajs/bearer'
import { env } from '../config/env'
import { db } from './database'
import { error } from './response'

// JWT plugin configuration
export const jwtPlugin = new Elysia({ name: 'jwt' })
  .use(jwt({
    name: 'jwt',
    secret: env.JWT_SECRET,
    exp: env.JWT_EXPIRES_IN
  }))

// Bearer token extraction
export const bearerPlugin = new Elysia({ name: 'bearer' })
  .use(bearer())

// Authentication middleware
export const authPlugin = new Elysia({ name: 'auth' })
  .use(jwtPlugin)
  .use(bearerPlugin)
  .derive(async ({ jwt, bearer, status }) => {
    if (!bearer) {
      return status(401, error('UNAUTHORIZED', 'No token provided'))
    }

    const payload = await jwt.verify(bearer)
    if (!payload) {
      return status(401, error('UNAUTHORIZED', 'Invalid or expired token'))
    }

    const user = db.users.findById(payload.sub as string)
    if (!user) {
      return status(401, error('UNAUTHORIZED', 'User not found'))
    }

    return {
      userId: user.id,
      userEmail: user.email,
      userRole: user.role
    }
  })

// Role-based access control
export const requireRole = (...roles: string[]) =>
  new Elysia({ name: `require-role-${roles.join('-')}` })
    .derive(({ userRole, status }) => {
      if (!userRole || !roles.includes(userRole)) {
        return status(403, error('FORBIDDEN', 'Insufficient permissions'))
      }
    })
```

### src/modules/auth/model.ts

```typescript
import { t } from 'elysia'

export const RegisterSchema = t.Object({
  email: t.String({ format: 'email' }),
  password: t.String({ minLength: 8 }),
  name: t.String({ minLength: 2, maxLength: 100 })
})

export const LoginSchema = t.Object({
  email: t.String({ format: 'email' }),
  password: t.String()
})

export const AuthResponseSchema = t.Object({
  success: t.Boolean(),
  data: t.Object({
    token: t.String(),
    user: t.Object({
      id: t.String(),
      email: t.String(),
      name: t.String(),
      role: t.String()
    })
  })
})
```

### src/modules/auth/service.ts

```typescript
import { db } from '../../shared/database'

export class AuthService {
  static async register(data: { email: string; password: string; name: string }) {
    // Check if user exists
    const existing = db.users.findByEmail(data.email)
    if (existing) {
      return { error: 'Email already registered' }
    }

    // Hash password
    const hashedPassword = await Bun.password.hash(data.password, {
      algorithm: 'argon2id'
    })

    // Create user
    const user = db.users.create({
      email: data.email,
      password: hashedPassword,
      name: data.name,
      role: 'user'
    })

    return { user }
  }

  static async login(email: string, password: string) {
    const user = db.users.findByEmail(email)
    if (!user) {
      return { error: 'Invalid credentials' }
    }

    const valid = await Bun.password.verify(password, user.password)
    if (!valid) {
      return { error: 'Invalid credentials' }
    }

    return { user }
  }
}
```

### src/modules/auth/index.ts

```typescript
import { Elysia, t } from 'elysia'
import { jwtPlugin, authPlugin } from '../../shared/auth'
import { success, error } from '../../shared/response'
import { AuthService } from './service'
import { RegisterSchema, LoginSchema, AuthResponseSchema } from './model'

export const authRoutes = new Elysia({ prefix: '/auth' })
  .use(jwtPlugin)

  .post('/register', async ({ jwt, body, status }) => {
    const result = await AuthService.register(body)

    if (result.error) {
      return status(400, error('REGISTRATION_FAILED', result.error))
    }

    const token = await jwt.sign({
      sub: result.user!.id,
      email: result.user!.email,
      role: result.user!.role
    })

    return success({
      token,
      user: {
        id: result.user!.id,
        email: result.user!.email,
        name: result.user!.name,
        role: result.user!.role
      }
    })
  }, {
    body: RegisterSchema,
    response: AuthResponseSchema,
    detail: {
      tags: ['Auth'],
      summary: 'Register a new user'
    }
  })

  .post('/login', async ({ jwt, body, status }) => {
    const result = await AuthService.login(body.email, body.password)

    if (result.error) {
      return status(401, error('LOGIN_FAILED', result.error))
    }

    const token = await jwt.sign({
      sub: result.user!.id,
      email: result.user!.email,
      role: result.user!.role
    })

    return success({
      token,
      user: {
        id: result.user!.id,
        email: result.user!.email,
        name: result.user!.name,
        role: result.user!.role
      }
    })
  }, {
    body: LoginSchema,
    response: AuthResponseSchema,
    detail: {
      tags: ['Auth'],
      summary: 'Login with email and password'
    }
  })

  .use(authPlugin)
  .get('/me', ({ userId, userEmail, userRole }) => {
    return success({
      id: userId,
      email: userEmail,
      role: userRole
    })
  }, {
    detail: {
      tags: ['Auth'],
      summary: 'Get current user',
      security: [{ bearerAuth: [] }]
    }
  })
```

### src/modules/user/model.ts

```typescript
import { t } from 'elysia'

export const UserSchema = t.Object({
  id: t.String(),
  email: t.String(),
  name: t.String(),
  role: t.String(),
  createdAt: t.String()
})

export const UpdateUserSchema = t.Object({
  name: t.Optional(t.String({ minLength: 2, maxLength: 100 }))
})
```

### src/modules/user/index.ts

```typescript
import { Elysia, t } from 'elysia'
import { authPlugin, requireRole } from '../../shared/auth'
import { db } from '../../shared/database'
import { success, error } from '../../shared/response'
import { UserSchema, UpdateUserSchema } from './model'

export const userRoutes = new Elysia({ prefix: '/users' })
  .use(authPlugin)

  // Admin only: list all users
  .group('', app => app
    .use(requireRole('admin'))
    .get('/', () => {
      const users = db.users.findAll().map(u => ({
        id: u.id,
        email: u.email,
        name: u.name,
        role: u.role,
        createdAt: u.createdAt
      }))
      return success(users)
    }, {
      response: t.Object({
        success: t.Boolean(),
        data: t.Array(UserSchema)
      }),
      detail: {
        tags: ['Users'],
        summary: 'List all users (admin only)',
        security: [{ bearerAuth: [] }]
      }
    })
  )

  // Get own profile
  .get('/me', ({ userId }) => {
    const user = db.users.findById(userId)
    if (!user) {
      return error('NOT_FOUND', 'User not found')
    }
    return success({
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      createdAt: user.createdAt
    })
  }, {
    detail: {
      tags: ['Users'],
      summary: 'Get own profile',
      security: [{ bearerAuth: [] }]
    }
  })

  // Update own profile
  .patch('/me', ({ userId, body, status }) => {
    const updated = db.users.update(userId, body)
    if (!updated) {
      return status(404, error('NOT_FOUND', 'User not found'))
    }
    return success({
      id: updated.id,
      email: updated.email,
      name: updated.name,
      role: updated.role,
      createdAt: updated.createdAt
    })
  }, {
    body: UpdateUserSchema,
    detail: {
      tags: ['Users'],
      summary: 'Update own profile',
      security: [{ bearerAuth: [] }]
    }
  })
```

### src/index.ts

```typescript
import { Elysia } from 'elysia'
import { cors } from '@elysiajs/cors'
import { openapi } from '@elysiajs/openapi'
import { env } from './config/env'
import { authRoutes } from './modules/auth'
import { userRoutes } from './modules/user'

const app = new Elysia()
  .use(cors())
  .use(openapi({
    path: '/docs',
    documentation: {
      info: {
        title: 'Auth API',
        version: '1.0.0'
      },
      components: {
        securitySchemes: {
          bearerAuth: {
            type: 'http',
            scheme: 'bearer',
            bearerFormat: 'JWT'
          }
        }
      }
    }
  }))
  .onError(({ code, error: err, status }) => {
    console.error(`[${code}]`, err)

    if (code === 'VALIDATION') {
      return status(422, {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Validation failed',
          details: err.all
        }
      })
    }

    return status(500, {
      success: false,
      error: {
        code: 'INTERNAL_ERROR',
        message: 'Internal server error'
      }
    })
  })
  .get('/health', () => ({ status: 'ok' }))
  .use(authRoutes)
  .use(userRoutes)
  .listen(env.PORT)

console.log(`🦊 Auth API running at ${app.server?.url}`)
console.log(`📚 API docs at ${app.server?.url}docs`)

export type App = typeof app
export default app
```

### test/auth.test.ts

```typescript
import { describe, expect, it, beforeAll } from 'bun:test'
import { treaty } from '@elysiajs/eden'
import app from '../src'

describe('Auth', () => {
  const api = treaty(app)

  describe('POST /auth/register', () => {
    it('should register a new user', async () => {
      const { data, error } = await api.auth.register.post({
        email: 'new@example.com',
        password: 'password123',
        name: 'New User'
      })

      expect(error).toBeNull()
      expect(data?.success).toBe(true)
      expect(data?.data.token).toBeDefined()
      expect(data?.data.user.email).toBe('new@example.com')
    })

    it('should reject duplicate email', async () => {
      await api.auth.register.post({
        email: 'dup@example.com',
        password: 'password123',
        name: 'Dup User'
      })

      const { error } = await api.auth.register.post({
        email: 'dup@example.com',
        password: 'password123',
        name: 'Dup User 2'
      })

      expect(error?.status).toBe(400)
    })
  })

  describe('POST /auth/login', () => {
    beforeAll(async () => {
      await api.auth.register.post({
        email: 'login@example.com',
        password: 'password123',
        name: 'Login User'
      })
    })

    it('should login with valid credentials', async () => {
      const { data, error } = await api.auth.login.post({
        email: 'login@example.com',
        password: 'password123'
      })

      expect(error).toBeNull()
      expect(data?.success).toBe(true)
      expect(data?.data.token).toBeDefined()
    })

    it('should reject invalid password', async () => {
      const { error } = await api.auth.login.post({
        email: 'login@example.com',
        password: 'wrongpassword'
      })

      expect(error?.status).toBe(401)
    })
  })

  describe('GET /auth/me', () => {
    it('should return current user with valid token', async () => {
      const { data: loginData } = await api.auth.register.post({
        email: 'me@example.com',
        password: 'password123',
        name: 'Me User'
      })

      const authApi = treaty(app, {
        headers: { authorization: `Bearer ${loginData!.data.token}` }
      })

      const { data, error } = await authApi.auth.me.get()

      expect(error).toBeNull()
      expect(data?.success).toBe(true)
    })

    it('should reject without token', async () => {
      const { error } = await api.auth.me.get()

      expect(error?.status).toBe(401)
    })
  })
})
```

## Getting Started

```bash
# Create and enter directory
mkdir auth-api && cd auth-api

# Initialize
bun init

# Install dependencies
bun add elysia @elysiajs/cors @elysiajs/jwt @elysiajs/bearer @elysiajs/openapi
bun add -d @types/bun @elysiajs/eden

# Create .env file
echo "JWT_SECRET=$(openssl rand -hex 32)" > .env

# Create files from template

# Run development
bun dev

# Test endpoints
curl http://localhost:3000/health
```

## Usage

```bash
# Register
curl -X POST http://localhost:3000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","name":"Test"}'

# Login
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Access protected route
curl http://localhost:3000/auth/me \
  -H "Authorization: Bearer <token>"
```
