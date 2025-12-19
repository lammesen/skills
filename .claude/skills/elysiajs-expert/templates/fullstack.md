# Full-Stack Elysia + Eden Template

A template for building full-stack type-safe applications with Elysia backend and any frontend using Eden client.

## Project Structure

```
project/
├── backend/
│   ├── src/
│   │   ├── index.ts
│   │   ├── modules/
│   │   │   ├── user/
│   │   │   │   ├── index.ts
│   │   │   │   └── model.ts
│   │   │   └── todo/
│   │   │       ├── index.ts
│   │   │       └── model.ts
│   │   └── shared/
│   │       └── database.ts
│   ├── package.json
│   └── tsconfig.json
├── frontend/
│   ├── src/
│   │   ├── api.ts         # Eden client
│   │   ├── App.tsx
│   │   └── main.tsx
│   ├── package.json
│   └── tsconfig.json
├── shared/
│   └── types.ts           # Shared types (optional)
└── package.json           # Root package.json
```

## Backend Files

### backend/package.json

```json
{
  "name": "backend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "bun --watch src/index.ts",
    "start": "bun src/index.ts",
    "build": "bun build --compile src/index.ts --outfile server"
  },
  "dependencies": {
    "elysia": "^1.0.0",
    "@elysiajs/cors": "^1.0.0",
    "@elysiajs/jwt": "^1.0.0",
    "@elysiajs/bearer": "^1.0.0"
  },
  "devDependencies": {
    "@types/bun": "latest"
  }
}
```

### backend/src/shared/database.ts

```typescript
// In-memory database (replace with real database)
interface Todo {
  id: string
  title: string
  completed: boolean
  userId: string
  createdAt: string
}

interface User {
  id: string
  email: string
  password: string
  name: string
}

const todos = new Map<string, Todo>()
const users = new Map<string, User>()

export const db = {
  todos: {
    findByUser: (userId: string) =>
      [...todos.values()].filter(t => t.userId === userId),
    findById: (id: string) => todos.get(id),
    create: (data: Omit<Todo, 'id' | 'createdAt'>) => {
      const todo: Todo = {
        ...data,
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString()
      }
      todos.set(todo.id, todo)
      return todo
    },
    update: (id: string, data: Partial<Todo>) => {
      const todo = todos.get(id)
      if (!todo) return null
      const updated = { ...todo, ...data }
      todos.set(id, updated)
      return updated
    },
    delete: (id: string) => todos.delete(id)
  },
  users: {
    findByEmail: (email: string) =>
      [...users.values()].find(u => u.email === email),
    findById: (id: string) => users.get(id),
    create: (data: Omit<User, 'id'>) => {
      const user: User = { ...data, id: crypto.randomUUID() }
      users.set(user.id, user)
      return user
    }
  }
}
```

### backend/src/modules/todo/model.ts

```typescript
import { t } from 'elysia'

export const TodoSchema = t.Object({
  id: t.String(),
  title: t.String(),
  completed: t.Boolean(),
  userId: t.String(),
  createdAt: t.String()
})

export const CreateTodoSchema = t.Object({
  title: t.String({ minLength: 1, maxLength: 200 })
})

export const UpdateTodoSchema = t.Object({
  title: t.Optional(t.String({ minLength: 1, maxLength: 200 })),
  completed: t.Optional(t.Boolean())
})
```

### backend/src/modules/todo/index.ts

```typescript
import { Elysia, t } from 'elysia'
import { db } from '../../shared/database'
import { CreateTodoSchema, UpdateTodoSchema, TodoSchema } from './model'

export const todoRoutes = new Elysia({ prefix: '/todos' })
  // Get all todos for user
  .get('/', ({ userId }) => {
    return db.todos.findByUser(userId)
  }, {
    response: t.Array(TodoSchema)
  })

  // Create todo
  .post('/', ({ userId, body }) => {
    return db.todos.create({
      ...body,
      userId,
      completed: false
    })
  }, {
    body: CreateTodoSchema,
    response: TodoSchema
  })

  // Update todo
  .patch('/:id', ({ userId, params, body, status }) => {
    const todo = db.todos.findById(params.id)
    if (!todo || todo.userId !== userId) {
      return status(404, { error: 'Todo not found' })
    }
    return db.todos.update(params.id, body)
  }, {
    params: t.Object({ id: t.String() }),
    body: UpdateTodoSchema,
    response: TodoSchema
  })

  // Delete todo
  .delete('/:id', ({ userId, params, status }) => {
    const todo = db.todos.findById(params.id)
    if (!todo || todo.userId !== userId) {
      return status(404, { error: 'Todo not found' })
    }
    db.todos.delete(params.id)
    return { success: true }
  }, {
    params: t.Object({ id: t.String() })
  })

  // Toggle completed
  .post('/:id/toggle', ({ userId, params, status }) => {
    const todo = db.todos.findById(params.id)
    if (!todo || todo.userId !== userId) {
      return status(404, { error: 'Todo not found' })
    }
    return db.todos.update(params.id, { completed: !todo.completed })
  }, {
    params: t.Object({ id: t.String() }),
    response: TodoSchema
  })
```

### backend/src/modules/user/model.ts

```typescript
import { t } from 'elysia'

export const LoginSchema = t.Object({
  email: t.String({ format: 'email' }),
  password: t.String()
})

export const RegisterSchema = t.Object({
  email: t.String({ format: 'email' }),
  password: t.String({ minLength: 8 }),
  name: t.String({ minLength: 2 })
})
```

### backend/src/modules/user/index.ts

```typescript
import { Elysia, t } from 'elysia'
import { jwt } from '@elysiajs/jwt'
import { db } from '../../shared/database'
import { LoginSchema, RegisterSchema } from './model'

export const userRoutes = new Elysia({ prefix: '/auth' })
  .use(jwt({
    name: 'jwt',
    secret: process.env.JWT_SECRET ?? 'dev-secret',
    exp: '7d'
  }))

  .post('/register', async ({ jwt, body, status }) => {
    if (db.users.findByEmail(body.email)) {
      return status(400, { error: 'Email already exists' })
    }

    const hashedPassword = await Bun.password.hash(body.password)
    const user = db.users.create({
      email: body.email,
      password: hashedPassword,
      name: body.name
    })

    const token = await jwt.sign({ sub: user.id })
    return { token, user: { id: user.id, email: user.email, name: user.name } }
  }, {
    body: RegisterSchema
  })

  .post('/login', async ({ jwt, body, status }) => {
    const user = db.users.findByEmail(body.email)
    if (!user) {
      return status(401, { error: 'Invalid credentials' })
    }

    const valid = await Bun.password.verify(body.password, user.password)
    if (!valid) {
      return status(401, { error: 'Invalid credentials' })
    }

    const token = await jwt.sign({ sub: user.id })
    return { token, user: { id: user.id, email: user.email, name: user.name } }
  }, {
    body: LoginSchema
  })
```

### backend/src/index.ts

```typescript
import { Elysia } from 'elysia'
import { cors } from '@elysiajs/cors'
import { jwt } from '@elysiajs/jwt'
import { bearer } from '@elysiajs/bearer'
import { userRoutes } from './modules/user'
import { todoRoutes } from './modules/todo'
import { db } from './shared/database'

const app = new Elysia()
  .use(cors({
    origin: process.env.FRONTEND_URL ?? 'http://localhost:5173',
    credentials: true
  }))
  .get('/health', () => ({ status: 'ok' }))
  .use(userRoutes)
  // Protected routes
  .use(jwt({
    name: 'jwt',
    secret: process.env.JWT_SECRET ?? 'dev-secret'
  }))
  .use(bearer())
  .derive(async ({ jwt, bearer, status }) => {
    if (!bearer) {
      return status(401, { error: 'Unauthorized' })
    }
    const payload = await jwt.verify(bearer)
    if (!payload) {
      return status(401, { error: 'Invalid token' })
    }
    return { userId: payload.sub as string }
  })
  .use(todoRoutes)
  .listen(process.env.PORT ?? 3000)

console.log(`🦊 Backend running at ${app.server?.url}`)

export type App = typeof app
```

## Frontend Files

### frontend/package.json

```json
{
  "name": "frontend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "@elysiajs/eden": "^1.0.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "@vitejs/plugin-react": "^4.2.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0"
  }
}
```

### frontend/vite.config.ts

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, '')
      }
    }
  }
})
```

### frontend/src/api.ts

```typescript
import { treaty } from '@elysiajs/eden'
import type { App } from '../../backend/src'

const getToken = () => localStorage.getItem('token')

export const api = treaty<App>('localhost:3000', {
  headers: () => {
    const token = getToken()
    return token ? { authorization: `Bearer ${token}` } : {}
  }
})

// Auth helpers
export const auth = {
  login: async (email: string, password: string) => {
    const { data, error } = await api.auth.login.post({ email, password })
    if (error) throw new Error(error.value.error)
    localStorage.setItem('token', data.token)
    return data.user
  },

  register: async (email: string, password: string, name: string) => {
    const { data, error } = await api.auth.register.post({ email, password, name })
    if (error) throw new Error(error.value.error)
    localStorage.setItem('token', data.token)
    return data.user
  },

  logout: () => {
    localStorage.removeItem('token')
  },

  isAuthenticated: () => !!getToken()
}

// Todo helpers
export const todos = {
  list: async () => {
    const { data, error } = await api.todos.get()
    if (error) throw new Error('Failed to fetch todos')
    return data
  },

  create: async (title: string) => {
    const { data, error } = await api.todos.post({ title })
    if (error) throw new Error('Failed to create todo')
    return data
  },

  update: async (id: string, updates: { title?: string; completed?: boolean }) => {
    const { data, error } = await api.todos({ id }).patch(updates)
    if (error) throw new Error('Failed to update todo')
    return data
  },

  toggle: async (id: string) => {
    const { data, error } = await api.todos({ id }).toggle.post()
    if (error) throw new Error('Failed to toggle todo')
    return data
  },

  delete: async (id: string) => {
    const { error } = await api.todos({ id }).delete()
    if (error) throw new Error('Failed to delete todo')
  }
}
```

### frontend/src/App.tsx

```tsx
import { useState, useEffect } from 'react'
import { auth, todos } from './api'

interface Todo {
  id: string
  title: string
  completed: boolean
}

interface User {
  id: string
  email: string
  name: string
}

function App() {
  const [user, setUser] = useState<User | null>(null)
  const [todoList, setTodoList] = useState<Todo[]>([])
  const [newTodo, setNewTodo] = useState('')
  const [loading, setLoading] = useState(true)

  // Login form state
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [isRegister, setIsRegister] = useState(false)

  useEffect(() => {
    if (auth.isAuthenticated()) {
      loadTodos()
    } else {
      setLoading(false)
    }
  }, [])

  const loadTodos = async () => {
    try {
      const data = await todos.list()
      setTodoList(data)
      setUser({ id: '', email: '', name: '' }) // Simplified
    } catch {
      auth.logout()
    } finally {
      setLoading(false)
    }
  }

  const handleAuth = async (e: React.FormEvent) => {
    e.preventDefault()
    try {
      if (isRegister) {
        await auth.register(email, password, name)
      } else {
        await auth.login(email, password)
      }
      await loadTodos()
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Auth failed')
    }
  }

  const handleLogout = () => {
    auth.logout()
    setUser(null)
    setTodoList([])
  }

  const handleAddTodo = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newTodo.trim()) return
    const todo = await todos.create(newTodo)
    setTodoList([...todoList, todo])
    setNewTodo('')
  }

  const handleToggle = async (id: string) => {
    const updated = await todos.toggle(id)
    setTodoList(todoList.map(t => t.id === id ? updated : t))
  }

  const handleDelete = async (id: string) => {
    await todos.delete(id)
    setTodoList(todoList.filter(t => t.id !== id))
  }

  if (loading) return <div>Loading...</div>

  if (!user) {
    return (
      <div style={{ maxWidth: 400, margin: '100px auto', padding: 20 }}>
        <h1>{isRegister ? 'Register' : 'Login'}</h1>
        <form onSubmit={handleAuth}>
          {isRegister && (
            <input
              type="text"
              placeholder="Name"
              value={name}
              onChange={e => setName(e.target.value)}
              style={{ width: '100%', padding: 10, marginBottom: 10 }}
            />
          )}
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            style={{ width: '100%', padding: 10, marginBottom: 10 }}
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            style={{ width: '100%', padding: 10, marginBottom: 10 }}
          />
          <button type="submit" style={{ width: '100%', padding: 10 }}>
            {isRegister ? 'Register' : 'Login'}
          </button>
        </form>
        <p style={{ textAlign: 'center', marginTop: 10 }}>
          <button onClick={() => setIsRegister(!isRegister)}>
            {isRegister ? 'Have an account? Login' : 'Need an account? Register'}
          </button>
        </p>
      </div>
    )
  }

  return (
    <div style={{ maxWidth: 600, margin: '50px auto', padding: 20 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1>Todo App</h1>
        <button onClick={handleLogout}>Logout</button>
      </div>

      <form onSubmit={handleAddTodo} style={{ marginBottom: 20 }}>
        <input
          type="text"
          placeholder="Add a todo..."
          value={newTodo}
          onChange={e => setNewTodo(e.target.value)}
          style={{ width: '80%', padding: 10 }}
        />
        <button type="submit" style={{ padding: 10 }}>Add</button>
      </form>

      <ul style={{ listStyle: 'none', padding: 0 }}>
        {todoList.map(todo => (
          <li key={todo.id} style={{
            display: 'flex',
            alignItems: 'center',
            padding: 10,
            borderBottom: '1px solid #eee'
          }}>
            <input
              type="checkbox"
              checked={todo.completed}
              onChange={() => handleToggle(todo.id)}
            />
            <span style={{
              flex: 1,
              marginLeft: 10,
              textDecoration: todo.completed ? 'line-through' : 'none'
            }}>
              {todo.title}
            </span>
            <button onClick={() => handleDelete(todo.id)}>Delete</button>
          </li>
        ))}
      </ul>
    </div>
  )
}

export default App
```

### frontend/src/main.tsx

```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
```

### frontend/index.html

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Todo App</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

## Root Package

### package.json

```json
{
  "name": "fullstack-elysia",
  "private": true,
  "scripts": {
    "dev": "concurrently \"cd backend && bun dev\" \"cd frontend && bun dev\"",
    "build": "cd backend && bun run build && cd ../frontend && bun run build"
  },
  "devDependencies": {
    "concurrently": "^8.2.0"
  }
}
```

## Getting Started

```bash
# Create project structure
mkdir fullstack-elysia && cd fullstack-elysia
mkdir backend frontend

# Setup backend
cd backend
bun init
bun add elysia @elysiajs/cors @elysiajs/jwt @elysiajs/bearer
bun add -d @types/bun

# Setup frontend
cd ../frontend
bun create vite . --template react-ts
bun add @elysiajs/eden

# Setup root
cd ..
bun init
bun add -d concurrently

# Run both
bun dev
```

## Type Safety

The Eden client provides complete type safety:

```typescript
// All method names are type-checked
api.todos.get()           // ✅
api.todoss.get()          // ❌ TypeScript error

// Body types are inferred
api.todos.post({ title: 'Test' })  // ✅
api.todos.post({ name: 'Test' })   // ❌ 'name' not in schema

// Response types are inferred
const { data } = await api.todos.get()
data[0].title     // ✅ string
data[0].invalid   // ❌ TypeScript error
```
