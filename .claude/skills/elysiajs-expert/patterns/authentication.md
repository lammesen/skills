# Authentication Patterns

Comprehensive authentication patterns for Elysia applications.

## JWT Authentication

### Basic JWT Setup

```typescript
import { Elysia, t } from 'elysia'
import { jwt } from '@elysiajs/jwt'
import { bearer } from '@elysiajs/bearer'

const app = new Elysia()
  .use(jwt({
    name: 'jwt',
    secret: process.env.JWT_SECRET!,
    exp: '7d'
  }))
  .use(bearer())
```

### Login Endpoint

```typescript
.post('/auth/login', async ({ jwt, body, status }) => {
  // Validate credentials
  const user = await validateCredentials(body.email, body.password)
  if (!user) {
    return status(401, { error: 'Invalid credentials' })
  }

  // Generate token
  const token = await jwt.sign({
    sub: user.id,
    email: user.email,
    role: user.role
  })

  return { token, user: { id: user.id, email: user.email } }
}, {
  body: t.Object({
    email: t.String({ format: 'email' }),
    password: t.String({ minLength: 8 })
  })
})
```

### Protected Route Pattern

```typescript
// Auth middleware plugin
const authMiddleware = new Elysia({ name: 'auth-middleware' })
  .use(jwt({ name: 'jwt', secret: process.env.JWT_SECRET! }))
  .use(bearer())
  .derive(async ({ jwt, bearer, status }) => {
    if (!bearer) {
      return status(401, { error: 'No token provided' })
    }

    const payload = await jwt.verify(bearer)
    if (!payload) {
      return status(401, { error: 'Invalid token' })
    }

    return {
      userId: payload.sub as string,
      userEmail: payload.email as string,
      userRole: payload.role as string
    }
  })

// Usage
new Elysia()
  .use(authMiddleware)
  .get('/me', ({ userId, userEmail }) => ({
    id: userId,
    email: userEmail
  }))
```

## Cookie-Based Sessions

### Session Cookie Setup

```typescript
import { Elysia, t } from 'elysia'
import { jwt } from '@elysiajs/jwt'

new Elysia()
  .use(jwt({ name: 'jwt', secret: process.env.JWT_SECRET!, exp: '7d' }))
  .post('/auth/login', async ({ jwt, body, cookie: { session }, status }) => {
    const user = await validateCredentials(body.email, body.password)
    if (!user) return status(401)

    const token = await jwt.sign({ sub: user.id })

    // Set HTTP-only cookie
    session.set({
      value: token,
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 7 * 24 * 60 * 60, // 7 days
      path: '/'
    })

    return { success: true }
  }, {
    body: t.Object({
      email: t.String({ format: 'email' }),
      password: t.String()
    })
  })
  .post('/auth/logout', ({ cookie: { session } }) => {
    session.remove()
    return { success: true }
  })
```

### Session Validation

```typescript
.derive(async ({ jwt, cookie: { session }, status }) => {
  if (!session.value) {
    return status(401, { error: 'Not authenticated' })
  }

  const payload = await jwt.verify(session.value)
  if (!payload) {
    session.remove()
    return status(401, { error: 'Session expired' })
  }

  return { userId: payload.sub as string }
})
```

## Token Refresh Pattern

### Dual Token System

```typescript
const app = new Elysia()
  .use(jwt({ name: 'accessJwt', secret: process.env.ACCESS_SECRET!, exp: '15m' }))
  .use(jwt({ name: 'refreshJwt', secret: process.env.REFRESH_SECRET!, exp: '7d' }))
  .post('/auth/login', async ({ accessJwt, refreshJwt, body }) => {
    const user = await validateCredentials(body.email, body.password)
    if (!user) return { error: 'Invalid credentials' }

    return {
      accessToken: await accessJwt.sign({ sub: user.id, type: 'access' }),
      refreshToken: await refreshJwt.sign({ sub: user.id, type: 'refresh' }),
      expiresIn: 900 // 15 minutes
    }
  })
  .post('/auth/refresh', async ({ accessJwt, refreshJwt, body, status }) => {
    const payload = await refreshJwt.verify(body.refreshToken)
    if (!payload || payload.type !== 'refresh') {
      return status(401, { error: 'Invalid refresh token' })
    }

    // Optionally: Invalidate old refresh token and issue new one
    return {
      accessToken: await accessJwt.sign({ sub: payload.sub, type: 'access' }),
      refreshToken: await refreshJwt.sign({ sub: payload.sub, type: 'refresh' }),
      expiresIn: 900
    }
  }, {
    body: t.Object({ refreshToken: t.String() })
  })
```

## Role-Based Access Control (RBAC)

### Role Middleware

```typescript
type Role = 'user' | 'admin' | 'superadmin'

const requireRole = (...allowedRoles: Role[]) =>
  new Elysia({ name: `require-role-${allowedRoles.join('-')}` })
    .derive(({ userRole, status }) => {
      if (!userRole || !allowedRoles.includes(userRole as Role)) {
        return status(403, { error: 'Insufficient permissions' })
      }
    })

// Usage
new Elysia()
  .use(authMiddleware)
  .group('/admin', app => app
    .use(requireRole('admin', 'superadmin'))
    .get('/users', listUsers)
    .delete('/users/:id', deleteUser)
  )
  .group('/superadmin', app => app
    .use(requireRole('superadmin'))
    .post('/promote', promoteToAdmin)
  )
```

### Permission-Based Access

```typescript
const permissions = {
  'users:read': ['user', 'admin', 'superadmin'],
  'users:write': ['admin', 'superadmin'],
  'users:delete': ['superadmin'],
  'settings:read': ['admin', 'superadmin'],
  'settings:write': ['superadmin']
} as const

type Permission = keyof typeof permissions

const requirePermission = (permission: Permission) =>
  new Elysia({ name: `require-permission-${permission}` })
    .derive(({ userRole, status }) => {
      const allowedRoles = permissions[permission]
      if (!userRole || !allowedRoles.includes(userRole)) {
        return status(403, { error: `Missing permission: ${permission}` })
      }
    })

// Usage
.get('/users', listUsers, { beforeHandle: requirePermission('users:read') })
.delete('/users/:id', deleteUser, { beforeHandle: requirePermission('users:delete') })
```

## API Key Authentication

### Header-Based API Key

```typescript
const apiKeyAuth = new Elysia({ name: 'api-key-auth' })
  .derive(async ({ headers, status }) => {
    const apiKey = headers['x-api-key']
    if (!apiKey) {
      return status(401, { error: 'API key required' })
    }

    const keyData = await validateApiKey(apiKey)
    if (!keyData) {
      return status(401, { error: 'Invalid API key' })
    }

    return {
      apiKeyId: keyData.id,
      clientId: keyData.clientId,
      permissions: keyData.permissions
    }
  })

// Usage
new Elysia()
  .use(apiKeyAuth)
  .get('/api/data', ({ clientId }) => getData(clientId))
```

### API Key Management

```typescript
.post('/api-keys', async ({ userId, body }) => {
  const key = crypto.randomUUID()
  const hashedKey = await Bun.password.hash(key)

  await db.apiKeys.create({
    id: crypto.randomUUID(),
    userId,
    name: body.name,
    hashedKey,
    permissions: body.permissions,
    createdAt: new Date()
  })

  // Only return key once!
  return { key, name: body.name }
}, {
  body: t.Object({
    name: t.String(),
    permissions: t.Array(t.String())
  })
})
```

## OAuth 2.0 Integration

### OAuth Flow

```typescript
const OAUTH_CONFIG = {
  clientId: process.env.OAUTH_CLIENT_ID!,
  clientSecret: process.env.OAUTH_CLIENT_SECRET!,
  redirectUri: process.env.OAUTH_REDIRECT_URI!,
  authorizationUrl: 'https://provider.com/oauth/authorize',
  tokenUrl: 'https://provider.com/oauth/token',
  userInfoUrl: 'https://provider.com/api/user'
}

new Elysia()
  .get('/auth/oauth/authorize', ({ redirect, query }) => {
    const state = crypto.randomUUID()
    // Store state in session for CSRF protection

    const params = new URLSearchParams({
      client_id: OAUTH_CONFIG.clientId,
      redirect_uri: OAUTH_CONFIG.redirectUri,
      response_type: 'code',
      scope: 'openid profile email',
      state
    })

    return redirect(`${OAUTH_CONFIG.authorizationUrl}?${params}`)
  })
  .get('/auth/oauth/callback', async ({ query, jwt, cookie: { session }, status }) => {
    const { code, state } = query
    // Validate state matches stored state

    // Exchange code for tokens
    const tokenResponse = await fetch(OAUTH_CONFIG.tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: OAUTH_CONFIG.redirectUri,
        client_id: OAUTH_CONFIG.clientId,
        client_secret: OAUTH_CONFIG.clientSecret
      })
    })

    const tokens = await tokenResponse.json()
    if (!tokens.access_token) {
      return status(400, { error: 'OAuth failed' })
    }

    // Get user info
    const userResponse = await fetch(OAUTH_CONFIG.userInfoUrl, {
      headers: { Authorization: `Bearer ${tokens.access_token}` }
    })
    const oauthUser = await userResponse.json()

    // Find or create user
    let user = await db.users.findByEmail(oauthUser.email)
    if (!user) {
      user = await db.users.create({
        email: oauthUser.email,
        name: oauthUser.name,
        oauthProvider: 'provider',
        oauthId: oauthUser.id
      })
    }

    // Create session
    const token = await jwt.sign({ sub: user.id })
    session.set({ value: token, httpOnly: true, secure: true })

    return redirect('/dashboard')
  }, {
    query: t.Object({
      code: t.String(),
      state: t.String()
    })
  })
```

## Password Hashing

### Using Bun.password

```typescript
// Hash password
const hash = await Bun.password.hash(password, {
  algorithm: 'argon2id',
  memoryCost: 65536,
  timeCost: 3
})

// Verify password
const isValid = await Bun.password.verify(password, hash)
```

### Registration with Password

```typescript
.post('/auth/register', async ({ body, status }) => {
  // Check if user exists
  const existing = await db.users.findByEmail(body.email)
  if (existing) {
    return status(400, { error: 'Email already registered' })
  }

  // Hash password
  const hashedPassword = await Bun.password.hash(body.password, {
    algorithm: 'argon2id'
  })

  // Create user
  const user = await db.users.create({
    email: body.email,
    password: hashedPassword,
    name: body.name
  })

  return { id: user.id, email: user.email }
}, {
  body: t.Object({
    email: t.String({ format: 'email' }),
    password: t.String({ minLength: 8 }),
    name: t.String({ minLength: 2 })
  })
})
```

## Rate Limiting

### Per-User Rate Limiting

```typescript
const rateLimiter = new Map<string, { count: number; resetAt: number }>()

const rateLimit = (limit: number, windowMs: number) =>
  new Elysia({ name: 'rate-limit' })
    .derive(({ ip, status }) => {
      const key = ip ?? 'unknown'
      const now = Date.now()
      const record = rateLimiter.get(key)

      if (!record || now > record.resetAt) {
        rateLimiter.set(key, { count: 1, resetAt: now + windowMs })
        return
      }

      if (record.count >= limit) {
        return status(429, {
          error: 'Too many requests',
          retryAfter: Math.ceil((record.resetAt - now) / 1000)
        })
      }

      record.count++
    })

// Usage - 100 requests per minute
new Elysia()
  .use(rateLimit(100, 60000))
  .post('/auth/login', loginHandler)
```

## Complete Auth Plugin

```typescript
// auth.plugin.ts
import { Elysia, t } from 'elysia'
import { jwt } from '@elysiajs/jwt'
import { bearer } from '@elysiajs/bearer'

export const authPlugin = new Elysia({ name: 'auth' })
  .use(jwt({ name: 'jwt', secret: process.env.JWT_SECRET!, exp: '7d' }))
  .use(bearer())
  .macro({
    isAuth: {
      async resolve({ jwt, bearer, status }) {
        if (!bearer) return status(401, { error: 'Unauthorized' })
        const payload = await jwt.verify(bearer)
        if (!payload) return status(401, { error: 'Invalid token' })
        return { user: payload }
      }
    },
    hasRole: (roles: string[]) => ({
      async resolve({ user, status }) {
        if (!user || !roles.includes(user.role)) {
          return status(403, { error: 'Forbidden' })
        }
      }
    })
  })

// Usage
new Elysia()
  .use(authPlugin)
  .get('/profile', ({ user }) => user, { isAuth: true })
  .get('/admin', ({ user }) => user, { isAuth: true, hasRole: ['admin'] })
```
