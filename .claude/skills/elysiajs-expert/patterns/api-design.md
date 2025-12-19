# API Design Patterns

Best practices and patterns for designing REST APIs with Elysia.

## Project Structure

### Recommended Layout

```
src/
├── modules/
│   ├── user/
│   │   ├── index.ts          # Routes
│   │   ├── service.ts        # Business logic
│   │   ├── repository.ts     # Data access
│   │   ├── model.ts          # TypeBox schemas
│   │   └── types.ts          # TypeScript types
│   ├── auth/
│   │   ├── index.ts
│   │   ├── service.ts
│   │   └── model.ts
│   └── product/
├── shared/
│   ├── middleware/
│   │   ├── auth.ts
│   │   ├── logging.ts
│   │   └── validation.ts
│   ├── plugins/
│   │   ├── database.ts
│   │   └── cache.ts
│   └── utils/
│       └── response.ts
├── config/
│   ├── env.ts
│   └── database.ts
├── index.ts                   # Entry point
└── server.ts                  # Elysia app
```

### Module Pattern

```typescript
// src/modules/user/model.ts
import { t } from 'elysia'

export const UserSchema = t.Object({
  id: t.String(),
  email: t.String({ format: 'email' }),
  name: t.String(),
  createdAt: t.String({ format: 'date-time' })
})

export const CreateUserSchema = t.Object({
  email: t.String({ format: 'email' }),
  name: t.String({ minLength: 2, maxLength: 100 }),
  password: t.String({ minLength: 8 })
})

export const UpdateUserSchema = t.Partial(
  t.Omit(CreateUserSchema, ['password'])
)

// src/modules/user/service.ts
export class UserService {
  constructor(private db: Database) {}

  async findById(id: string) {
    return this.db.user.findUnique({ where: { id } })
  }

  async create(data: CreateUserData) {
    const hashedPassword = await Bun.password.hash(data.password)
    return this.db.user.create({
      data: { ...data, password: hashedPassword }
    })
  }

  async update(id: string, data: UpdateUserData) {
    return this.db.user.update({ where: { id }, data })
  }

  async delete(id: string) {
    return this.db.user.delete({ where: { id } })
  }
}

// src/modules/user/index.ts
import { Elysia, t } from 'elysia'
import { UserService } from './service'
import { CreateUserSchema, UpdateUserSchema, UserSchema } from './model'

export const userRoutes = (userService: UserService) =>
  new Elysia({ prefix: '/users' })
    .get('/', async () => userService.findAll(), {
      response: t.Array(UserSchema),
      detail: { tags: ['Users'], summary: 'List all users' }
    })
    .get('/:id', async ({ params }) => userService.findById(params.id), {
      params: t.Object({ id: t.String() }),
      response: UserSchema,
      detail: { tags: ['Users'], summary: 'Get user by ID' }
    })
    .post('/', async ({ body }) => userService.create(body), {
      body: CreateUserSchema,
      response: UserSchema,
      detail: { tags: ['Users'], summary: 'Create user' }
    })
    .patch('/:id', async ({ params, body }) =>
      userService.update(params.id, body), {
      params: t.Object({ id: t.String() }),
      body: UpdateUserSchema,
      response: UserSchema,
      detail: { tags: ['Users'], summary: 'Update user' }
    })
    .delete('/:id', async ({ params, status }) => {
      await userService.delete(params.id)
      return status(204)
    }, {
      params: t.Object({ id: t.String() }),
      detail: { tags: ['Users'], summary: 'Delete user' }
    })
```

## Response Patterns

### Consistent Response Envelope

```typescript
// src/shared/utils/response.ts
import { t, TSchema } from 'elysia'

export const SuccessResponse = <T extends TSchema>(dataSchema: T) =>
  t.Object({
    success: t.Literal(true),
    data: dataSchema
  })

export const ErrorResponse = t.Object({
  success: t.Literal(false),
  error: t.Object({
    code: t.String(),
    message: t.String(),
    details: t.Optional(t.Array(t.Object({
      field: t.String(),
      message: t.String()
    })))
  })
})

export const PaginatedResponse = <T extends TSchema>(itemSchema: T) =>
  t.Object({
    success: t.Literal(true),
    data: t.Array(itemSchema),
    meta: t.Object({
      page: t.Number(),
      limit: t.Number(),
      total: t.Number(),
      totalPages: t.Number()
    })
  })

// Helper functions
export const success = <T>(data: T) => ({
  success: true as const,
  data
})

export const error = (code: string, message: string, details?: unknown) => ({
  success: false as const,
  error: { code, message, details }
})

export const paginated = <T>(
  data: T[],
  page: number,
  limit: number,
  total: number
) => ({
  success: true as const,
  data,
  meta: {
    page,
    limit,
    total,
    totalPages: Math.ceil(total / limit)
  }
})
```

### Usage in Routes

```typescript
import { success, paginated, PaginatedResponse, SuccessResponse } from '../shared/utils/response'

.get('/users', async ({ query }) => {
  const { page, limit } = query
  const [users, total] = await Promise.all([
    userService.findPaginated(page, limit),
    userService.count()
  ])
  return paginated(users, page, limit, total)
}, {
  query: t.Object({
    page: t.Numeric({ default: 1 }),
    limit: t.Numeric({ default: 10, maximum: 100 })
  }),
  response: PaginatedResponse(UserSchema)
})

.get('/users/:id', async ({ params }) => {
  const user = await userService.findById(params.id)
  return success(user)
}, {
  response: SuccessResponse(UserSchema)
})
```

## Error Handling

### Global Error Handler

```typescript
// src/shared/middleware/error.ts
import { Elysia } from 'elysia'
import { error } from '../utils/response'

export const errorHandler = new Elysia({ name: 'error-handler' })
  .onError(({ code, error: err, status }) => {
    console.error(`[${code}]`, err)

    switch (code) {
      case 'NOT_FOUND':
        return status(404, error('NOT_FOUND', 'Resource not found'))

      case 'VALIDATION':
        return status(400, error('VALIDATION_ERROR', 'Validation failed', {
          details: err.all.map(e => ({
            field: e.path,
            message: e.message
          }))
        }))

      case 'PARSE':
        return status(400, error('PARSE_ERROR', 'Invalid request body'))

      default:
        if (err instanceof AppError) {
          return status(err.statusCode, error(err.code, err.message))
        }

        return status(500, error(
          'INTERNAL_ERROR',
          process.env.NODE_ENV === 'production'
            ? 'Internal server error'
            : err.message
        ))
    }
  })

// Custom error class
export class AppError extends Error {
  constructor(
    public code: string,
    message: string,
    public statusCode: number = 400
  ) {
    super(message)
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string) {
    super('NOT_FOUND', `${resource} not found`, 404)
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'Unauthorized') {
    super('UNAUTHORIZED', message, 401)
  }
}
```

## Pagination

### Query Parameters

```typescript
export const PaginationQuery = t.Object({
  page: t.Numeric({ default: 1, minimum: 1 }),
  limit: t.Numeric({ default: 10, minimum: 1, maximum: 100 }),
  sortBy: t.Optional(t.String()),
  sortOrder: t.Optional(t.UnionEnum(['asc', 'desc']))
})

.get('/users', async ({ query }) => {
  const { page, limit, sortBy, sortOrder } = query
  const offset = (page - 1) * limit

  const [users, total] = await Promise.all([
    db.user.findMany({
      skip: offset,
      take: limit,
      orderBy: sortBy ? { [sortBy]: sortOrder ?? 'asc' } : undefined
    }),
    db.user.count()
  ])

  return paginated(users, page, limit, total)
}, {
  query: PaginationQuery
})
```

### Cursor-Based Pagination

```typescript
export const CursorPaginationQuery = t.Object({
  cursor: t.Optional(t.String()),
  limit: t.Numeric({ default: 10, minimum: 1, maximum: 100 })
})

.get('/posts', async ({ query }) => {
  const { cursor, limit } = query

  const posts = await db.post.findMany({
    take: limit + 1,  // Get one extra to determine hasMore
    cursor: cursor ? { id: cursor } : undefined,
    skip: cursor ? 1 : 0,
    orderBy: { createdAt: 'desc' }
  })

  const hasMore = posts.length > limit
  const items = hasMore ? posts.slice(0, -1) : posts
  const nextCursor = hasMore ? items[items.length - 1].id : null

  return {
    data: items,
    nextCursor,
    hasMore
  }
}, {
  query: CursorPaginationQuery
})
```

## Filtering and Search

### Filter Parameters

```typescript
.get('/products', async ({ query }) => {
  const where: Prisma.ProductWhereInput = {}

  if (query.search) {
    where.OR = [
      { name: { contains: query.search, mode: 'insensitive' } },
      { description: { contains: query.search, mode: 'insensitive' } }
    ]
  }

  if (query.category) {
    where.categoryId = query.category
  }

  if (query.minPrice !== undefined) {
    where.price = { ...where.price, gte: query.minPrice }
  }

  if (query.maxPrice !== undefined) {
    where.price = { ...where.price, lte: query.maxPrice }
  }

  if (query.inStock !== undefined) {
    where.stock = query.inStock ? { gt: 0 } : { equals: 0 }
  }

  return db.product.findMany({ where })
}, {
  query: t.Object({
    search: t.Optional(t.String()),
    category: t.Optional(t.String()),
    minPrice: t.Optional(t.Numeric()),
    maxPrice: t.Optional(t.Numeric()),
    inStock: t.Optional(t.BooleanString()),
    ...PaginationQuery.properties
  })
})
```

## API Versioning

### Path-Based Versioning

```typescript
// Recommended approach
new Elysia()
  .group('/api/v1', app => app
    .use(userRoutesV1)
    .use(productRoutesV1)
  )
  .group('/api/v2', app => app
    .use(userRoutesV2)
    .use(productRoutesV2)
  )
```

### Header-Based Versioning

```typescript
.derive(({ headers }) => ({
  apiVersion: headers['api-version'] ?? 'v1'
}))
.get('/users', ({ apiVersion }) => {
  if (apiVersion === 'v2') {
    return usersV2()
  }
  return usersV1()
})
```

## Resource Relationships

### Nested Resources

```typescript
// GET /users/:userId/posts
.get('/users/:userId/posts', async ({ params, query }) => {
  const posts = await postService.findByUser(params.userId, query)
  return success(posts)
}, {
  params: t.Object({ userId: t.String() }),
  query: PaginationQuery
})

// POST /users/:userId/posts
.post('/users/:userId/posts', async ({ params, body }) => {
  const post = await postService.create({
    ...body,
    authorId: params.userId
  })
  return success(post)
}, {
  params: t.Object({ userId: t.String() }),
  body: CreatePostSchema
})
```

### Include Related Data

```typescript
.get('/posts/:id', async ({ params, query }) => {
  const include: Prisma.PostInclude = {}

  if (query.include?.includes('author')) {
    include.author = { select: { id: true, name: true } }
  }

  if (query.include?.includes('comments')) {
    include.comments = { take: 10, orderBy: { createdAt: 'desc' } }
  }

  const post = await db.post.findUnique({
    where: { id: params.id },
    include
  })

  return success(post)
}, {
  params: t.Object({ id: t.String() }),
  query: t.Object({
    include: t.Optional(t.Array(t.UnionEnum(['author', 'comments'])))
  })
})
```

## Bulk Operations

### Batch Create

```typescript
.post('/users/batch', async ({ body }) => {
  const users = await db.user.createMany({
    data: body.users,
    skipDuplicates: true
  })
  return success({ count: users.count })
}, {
  body: t.Object({
    users: t.Array(CreateUserSchema, { maxItems: 100 })
  })
})
```

### Batch Update

```typescript
.patch('/users/batch', async ({ body }) => {
  const results = await Promise.all(
    body.updates.map(({ id, data }) =>
      db.user.update({ where: { id }, data })
    )
  )
  return success(results)
}, {
  body: t.Object({
    updates: t.Array(t.Object({
      id: t.String(),
      data: UpdateUserSchema
    }), { maxItems: 100 })
  })
})
```

### Batch Delete

```typescript
.delete('/users/batch', async ({ body }) => {
  const result = await db.user.deleteMany({
    where: { id: { in: body.ids } }
  })
  return success({ count: result.count })
}, {
  body: t.Object({
    ids: t.Array(t.String(), { maxItems: 100 })
  })
})
```

## Documentation

### OpenAPI Integration

```typescript
import { openapi } from '@elysiajs/openapi'

new Elysia()
  .use(openapi({
    path: '/docs',
    documentation: {
      info: {
        title: 'My API',
        version: '1.0.0',
        description: 'API Documentation'
      },
      tags: [
        { name: 'Users', description: 'User management' },
        { name: 'Products', description: 'Product catalog' },
        { name: 'Orders', description: 'Order processing' }
      ],
      servers: [
        { url: 'https://api.example.com', description: 'Production' },
        { url: 'http://localhost:3000', description: 'Development' }
      ]
    }
  }))
  .get('/users', handler, {
    detail: {
      tags: ['Users'],
      summary: 'List all users',
      description: 'Retrieves a paginated list of users',
      security: [{ bearerAuth: [] }]
    }
  })
```

## Health Checks

```typescript
.get('/health', () => ({ status: 'ok' }))
.get('/health/ready', async () => {
  // Check dependencies
  const checks = await Promise.allSettled([
    db.$queryRaw`SELECT 1`,
    redis.ping(),
    fetch(externalApiUrl)
  ])

  const isHealthy = checks.every(c => c.status === 'fulfilled')

  return {
    status: isHealthy ? 'ready' : 'degraded',
    checks: {
      database: checks[0].status === 'fulfilled',
      cache: checks[1].status === 'fulfilled',
      external: checks[2].status === 'fulfilled'
    }
  }
})
```
