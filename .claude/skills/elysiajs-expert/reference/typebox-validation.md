# TypeBox Validation Reference

Complete reference for TypeBox schema validation in Elysia.

## Basic Usage

```typescript
import { Elysia, t } from 'elysia'

new Elysia()
  .post('/user', ({ body }) => body, {
    body: t.Object({
      name: t.String(),
      email: t.String({ format: 'email' })
    })
  })
```

## Primitive Types

### String

```typescript
t.String()
t.String({ minLength: 1 })
t.String({ maxLength: 100 })
t.String({ minLength: 1, maxLength: 100 })
t.String({ pattern: '^[a-z]+$' })
t.String({ format: 'email' })
t.String({ format: 'uri' })
t.String({ format: 'uuid' })
t.String({ format: 'date' })
t.String({ format: 'date-time' })
t.String({ format: 'time' })
t.String({ format: 'ipv4' })
t.String({ format: 'ipv6' })
t.String({ default: 'value' })
```

### Number

```typescript
t.Number()
t.Number({ minimum: 0 })
t.Number({ maximum: 100 })
t.Number({ minimum: 0, maximum: 100 })
t.Number({ exclusiveMinimum: 0 })
t.Number({ exclusiveMaximum: 100 })
t.Number({ multipleOf: 5 })
t.Number({ default: 0 })
```

### Integer

```typescript
t.Integer()
t.Integer({ minimum: 0 })
// Same options as Number
```

### Boolean

```typescript
t.Boolean()
t.Boolean({ default: false })
```

### Null

```typescript
t.Null()
```

## Elysia-Specific Types

### Numeric (String to Number Coercion)

```typescript
// Automatically converts string to number
// Useful for query params and path params
t.Numeric()
t.Numeric({ minimum: 0, maximum: 100 })

// Example
.get('/user/:id', ({ params }) => params.id, {
  params: t.Object({
    id: t.Numeric()  // "123" becomes 123
  })
})
```

### File

```typescript
t.File()
t.File({ type: 'image/*' })
t.File({ type: 'image/png' })
t.File({ type: ['image/png', 'image/jpeg'] })
t.File({ minSize: 1024 })              // bytes
t.File({ maxSize: 1024 * 1024 * 5 })   // 5MB

// Example
.post('/upload', ({ body }) => body.file, {
  body: t.Object({
    file: t.File({ type: 'image/*', maxSize: '5m' })
  })
})
```

### Files (Multiple)

```typescript
t.Files()
t.Files({ type: 'image/*' })
t.Files({ minSize: 1024, maxSize: '5m' })

// Example
.post('/upload-multiple', ({ body }) => body.files, {
  body: t.Object({
    files: t.Files({ type: 'image/*' })
  })
})
```

### Cookie

```typescript
t.Cookie({
  session: t.String(),
  preferences: t.Optional(t.String())
}, {
  secure: true,
  httpOnly: true,
  sameSite: 'strict',
  path: '/',
  maxAge: 86400
})
```

### TemplateLiteral

```typescript
// Validate template literal patterns
t.TemplateLiteral('Bearer ${string}')
t.TemplateLiteral('user-${number}')
t.TemplateLiteral('${string}@${string}.${string}')

// Example
.get('/protected', handler, {
  headers: t.Object({
    authorization: t.TemplateLiteral('Bearer ${string}')
  })
})
```

### UnionEnum

```typescript
// Shorthand for Union of Literals
t.UnionEnum(['draft', 'published', 'archived'])

// Equivalent to:
t.Union([
  t.Literal('draft'),
  t.Literal('published'),
  t.Literal('archived')
])
```

## Complex Types

### Object

```typescript
t.Object({
  name: t.String(),
  age: t.Number()
})

// Additional properties
t.Object({
  name: t.String()
}, {
  additionalProperties: true  // Allow extra properties
})

// Strict object (no extra properties)
t.Object({
  name: t.String()
}, {
  additionalProperties: false
})
```

### Array

```typescript
t.Array(t.String())
t.Array(t.Number(), { minItems: 1 })
t.Array(t.Object({ id: t.String() }), { maxItems: 100 })
t.Array(t.String(), { uniqueItems: true })
```

### Tuple

```typescript
t.Tuple([t.String(), t.Number()])
// Validates: ["hello", 42]
```

### Record

```typescript
t.Record(t.String(), t.Number())
// Validates: { "a": 1, "b": 2 }

t.Record(t.String(), t.Object({
  value: t.String()
}))
```

### Union

```typescript
t.Union([t.String(), t.Number()])
t.Union([
  t.Object({ type: t.Literal('user'), name: t.String() }),
  t.Object({ type: t.Literal('admin'), role: t.String() })
])
```

### Intersect

```typescript
t.Intersect([
  t.Object({ name: t.String() }),
  t.Object({ age: t.Number() })
])
// Result: { name: string, age: number }
```

### Literal

```typescript
t.Literal('exact-value')
t.Literal(42)
t.Literal(true)
```

### Enum (Native)

```typescript
enum Status {
  Active = 'active',
  Inactive = 'inactive'
}
t.Enum(Status)
```

## Modifiers

### Optional

```typescript
t.Optional(t.String())
// Value can be undefined or omitted

t.Object({
  required: t.String(),
  optional: t.Optional(t.String())
})
```

### Nullable

```typescript
t.Nullable(t.String())
// Value can be null

t.Object({
  name: t.Nullable(t.String())
})
// Valid: { name: "test" } or { name: null }
```

### Default

```typescript
t.String({ default: 'default-value' })
t.Number({ default: 0 })
t.Boolean({ default: false })
t.Array(t.String(), { default: [] })
```

## Schema Utilities

### Partial

```typescript
const User = t.Object({
  name: t.String(),
  email: t.String()
})

t.Partial(User)
// All properties become optional
```

### Required

```typescript
const PartialUser = t.Partial(t.Object({
  name: t.String(),
  email: t.String()
}))

t.Required(PartialUser)
// All properties become required
```

### Pick

```typescript
const User = t.Object({
  id: t.String(),
  name: t.String(),
  email: t.String()
})

t.Pick(User, ['name', 'email'])
// { name: string, email: string }
```

### Omit

```typescript
t.Omit(User, ['id'])
// { name: string, email: string }
```

### Extends (Merge)

```typescript
const BaseUser = t.Object({
  name: t.String()
})

const AdminUser = t.Intersect([
  BaseUser,
  t.Object({
    role: t.Literal('admin'),
    permissions: t.Array(t.String())
  })
])
```

## Validation Locations

```typescript
.post('/example', handler, {
  // Request body
  body: t.Object({ ... }),

  // Query string parameters
  query: t.Object({
    page: t.Numeric({ default: 1 }),
    limit: t.Numeric({ default: 10 })
  }),

  // Path parameters
  params: t.Object({
    id: t.String()
  }),

  // Request headers (lowercase keys!)
  headers: t.Object({
    'authorization': t.String(),
    'x-api-key': t.Optional(t.String())
  }),

  // Cookies
  cookie: t.Cookie({
    session: t.String()
  }),

  // Response validation
  response: t.Object({ ... })
})
```

### Response Validation by Status

```typescript
.get('/user/:id', handler, {
  response: {
    200: t.Object({
      id: t.String(),
      name: t.String()
    }),
    400: t.Object({
      error: t.String()
    }),
    404: t.Object({
      message: t.String()
    })
  }
})
```

## Custom Error Messages

### Static Message

```typescript
t.String({
  minLength: 1,
  error: 'Name is required'
})

t.Number({
  minimum: 0,
  error: 'Value must be positive'
})
```

### Dynamic Message

```typescript
t.String({
  minLength: 5,
  error({ value, errors }) {
    return `Expected at least 5 characters, got ${value?.length ?? 0}`
  }
})

t.Number({
  minimum: 18,
  error({ value }) {
    return `Must be 18 or older, got ${value}`
  }
})
```

### Global Error Handler

```typescript
.onError(({ code, error, status }) => {
  if (code === 'VALIDATION') {
    return status(400, {
      message: 'Validation failed',
      errors: error.all.map(e => ({
        path: e.path,
        message: e.message,
        value: e.value
      }))
    })
  }
})
```

## Standard Schema Support

Elysia supports other validation libraries:

### Zod

```typescript
import { z } from 'zod'

.get('/user/:id', handler, {
  params: z.object({
    id: z.coerce.number()
  }),
  body: z.object({
    name: z.string().min(1),
    email: z.string().email()
  })
})
```

### Valibot

```typescript
import * as v from 'valibot'

.post('/user', handler, {
  body: v.object({
    name: v.string([v.minLength(1)]),
    email: v.string([v.email()])
  })
})
```

## Type Inference

```typescript
import { Elysia, t, Static } from 'elysia'

const UserSchema = t.Object({
  name: t.String(),
  email: t.String({ format: 'email' })
})

// Infer TypeScript type from schema
type User = Static<typeof UserSchema>
// { name: string; email: string }
```

## Best Practices

1. **Define schemas once, reuse everywhere**
   ```typescript
   const UserSchema = t.Object({ ... })
   const CreateUserSchema = t.Omit(UserSchema, ['id'])
   const UpdateUserSchema = t.Partial(CreateUserSchema)
   ```

2. **Use Numeric for path/query params**
   ```typescript
   params: t.Object({ id: t.Numeric() })
   ```

3. **Always lowercase header keys**
   ```typescript
   headers: t.Object({ 'authorization': t.String() })
   ```

4. **Use TemplateLiteral for patterns**
   ```typescript
   t.TemplateLiteral('Bearer ${string}')
   ```

5. **Provide custom error messages**
   ```typescript
   t.String({ error: 'User-friendly message' })
   ```

6. **Validate responses in development**
   ```typescript
   response: isDev ? ResponseSchema : undefined
   ```
