# Node.js to Bun Migration Guide

Complete guide for migrating Node.js applications to Bun.

## Table of Contents

- [Quick Start](#quick-start)
- [Migration Strategies](#migration-strategies)
- [Package Manager Migration](#package-manager-migration)
- [Runtime Migration](#runtime-migration)
- [API Compatibility Matrix](#api-compatibility-matrix)
- [Common Issues & Solutions](#common-issues--solutions)
- [Framework-Specific Guides](#framework-specific-guides)

---

## Quick Start

### 1. Install Bun

```bash
# macOS / Linux
curl -fsSL https://bun.sh/install | bash

# Windows (PowerShell)
powershell -c "irm bun.sh/install.ps1 | iex"

# Homebrew
brew install oven-sh/bun/bun

# npm (not recommended for production)
npm install -g bun
```

### 2. Migrate Package Manager

```bash
# Remove existing lockfiles and node_modules
rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml

# Install with Bun
bun install
```

### 3. Update Scripts

```json
{
  "scripts": {
    "start": "bun run src/index.ts",
    "dev": "bun run --watch src/index.ts",
    "test": "bun test",
    "build": "bun build src/index.ts --outdir dist"
  }
}
```

### 4. Add Bun Types

```bash
bun add -d @types/bun
```

Or in `tsconfig.json`:
```json
{
  "compilerOptions": {
    "types": ["bun-types"]
  }
}
```

---

## Migration Strategies

### Strategy 1: Package Manager Only (Lowest Risk)

Keep Node.js runtime, only use Bun for package management.

**Pros:**
- Minimal changes required
- 10-25x faster installs
- No runtime compatibility concerns

**Steps:**
1. Install Bun
2. Run `bun install`
3. Keep using `node` for execution

```json
{
  "scripts": {
    "start": "node dist/index.js",
    "dev": "node --watch src/index.ts"
  }
}
```

### Strategy 2: Development Only (Low Risk)

Use Bun for development, Node.js for production.

**Pros:**
- Faster development cycle
- Test Bun compatibility gradually
- Production remains stable

**Steps:**
1. Use `bun run` for development
2. Use `bun test` for testing
3. Keep Node.js for production builds

```json
{
  "scripts": {
    "dev": "bun run --watch src/index.ts",
    "test": "bun test",
    "build": "tsc && node dist/index.js",
    "start": "node dist/index.js"
  }
}
```

### Strategy 3: Shadow Deployment (Medium Risk)

Run Bun alongside Node.js in production with traffic splitting.

**Pros:**
- Real-world validation
- Easy rollback
- Gradual traffic migration

**Architecture:**
```
Load Balancer
     ├── 90% → Node.js instances
     └── 10% → Bun instances
```

### Strategy 4: Full Migration (Higher Risk, Higher Reward)

Complete replacement of Node.js with Bun.

**Pros:**
- Maximum performance benefits
- Simplified toolchain
- Single runtime to maintain

**Steps:**
1. Complete compatibility testing
2. Update all scripts
3. Update CI/CD pipelines
4. Update Docker images
5. Deploy and monitor

---

## Package Manager Migration

### Lockfile Conversion

Bun automatically migrates lockfiles:

| Source | Bun Action |
|--------|------------|
| `package-lock.json` | Auto-converts to `bun.lock` |
| `yarn.lock` | Auto-converts to `bun.lock` |
| `pnpm-lock.yaml` | Auto-converts to `bun.lock` |

### Command Equivalents

| npm | yarn | pnpm | bun |
|-----|------|------|-----|
| `npm install` | `yarn` | `pnpm install` | `bun install` |
| `npm install pkg` | `yarn add pkg` | `pnpm add pkg` | `bun add pkg` |
| `npm install -D pkg` | `yarn add -D pkg` | `pnpm add -D pkg` | `bun add -d pkg` |
| `npm remove pkg` | `yarn remove pkg` | `pnpm remove pkg` | `bun remove pkg` |
| `npm run script` | `yarn script` | `pnpm script` | `bun run script` |
| `npx pkg` | `yarn dlx pkg` | `pnpm dlx pkg` | `bunx pkg` |
| `npm ci` | `yarn --frozen-lockfile` | `pnpm install --frozen-lockfile` | `bun install --frozen-lockfile` |

### Workspace Migration

**package.json (same as npm/yarn):**
```json
{
  "workspaces": ["packages/*", "apps/*"]
}
```

**Cross-workspace dependencies:**
```json
{
  "dependencies": {
    "@myorg/shared": "workspace:*",
    "@myorg/utils": "workspace:^1.0.0"
  }
}
```

### Trusted Dependencies

Bun blocks lifecycle scripts by default for security.

**Allow specific packages:**
```bash
bun pm trust <package-name>
```

**In package.json:**
```json
{
  "trustedDependencies": ["esbuild", "sharp"]
}
```

**View blocked packages:**
```bash
bun pm untrusted
```

---

## Runtime Migration

### Entry Point Changes

**Before (Node.js):**
```json
{
  "main": "dist/index.js",
  "scripts": {
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts"
  }
}
```

**After (Bun):**
```json
{
  "main": "src/index.ts",
  "scripts": {
    "start": "bun run src/index.ts",
    "dev": "bun run --watch src/index.ts"
  }
}
```

### TypeScript Configuration

**Recommended tsconfig.json for Bun:**
```json
{
  "compilerOptions": {
    "lib": ["ESNext"],
    "target": "ESNext",
    "module": "ESNext",
    "moduleDetection": "force",
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "verbatimModuleSyntax": true,
    "noEmit": true,
    "strict": true,
    "skipLibCheck": true,
    "noFallthroughCasesInSwitch": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noPropertyAccessFromIndexSignature": true,
    "types": ["bun-types"]
  }
}
```

### Environment Variables

Bun automatically loads `.env` files:

| File | Environment |
|------|-------------|
| `.env` | Always loaded |
| `.env.local` | Always loaded (gitignored) |
| `.env.development` | When `NODE_ENV=development` |
| `.env.production` | When `NODE_ENV=production` |
| `.env.test` | When running `bun test` |

**Load specific file:**
```bash
bun run --env-file .env.staging src/index.ts
```

---

## API Compatibility Matrix

### Fully Compatible (Drop-in Replacement)

| Module | Compatibility | Notes |
|--------|---------------|-------|
| `node:assert` | 100% | Full API support |
| `node:buffer` | 100% | Full API support |
| `node:events` | 100% | Full API support |
| `node:path` | 100% | Full API support |
| `node:url` | 100% | Full API support |
| `node:querystring` | 100% | Full API support |
| `node:string_decoder` | 100% | Full API support |
| `node:util` | 100% | Full API support |

### Highly Compatible

| Module | Compatibility | Notes |
|--------|---------------|-------|
| `node:fs` | 95%+ | Most APIs supported |
| `node:fs/promises` | 95%+ | Full async API |
| `node:http` | 95% | Use Bun.serve() for better performance |
| `node:https` | 95% | TLS fully supported |
| `node:stream` | 95% | Web Streams preferred |
| `node:zlib` | 95% | Compression/decompression |
| `node:crypto` | 90% | Most algorithms supported |
| `node:net` | 90% | TCP/IPC sockets |
| `node:tls` | 90% | TLS connections |
| `node:dns` | 90% | Use Bun.dns for more features |
| `node:os` | 90% | System information |
| `node:process` | 90% | Process globals |

### Partially Compatible

| Module | Compatibility | Limitations |
|--------|---------------|-------------|
| `node:child_process` | 80% | Missing `proc.gid`, `proc.uid`; IPC limited to JSON |
| `node:worker_threads` | 75% | Missing `stdin`, `stdout`, `stderr` options |
| `node:http2` | 75% | Missing `pushStream` |
| `node:cluster` | 60% | Linux-only via SO_REUSEPORT |
| `node:async_hooks` | 50% | AsyncLocalStorage works; createHook limited |
| `node:perf_hooks` | 50% | Basic performance APIs |
| `node:vm` | 40% | Limited sandboxing |
| `node:dgram` | 40% | UDP partially supported |

### Not Implemented

| Module | Alternative |
|--------|-------------|
| `node:inspector` | Use `bun --inspect` |
| `node:repl` | Use Bun's REPL (`bun`) |
| `node:trace_events` | Not available |
| `node:v8` | Some via `bun:jsc` |

---

## Common Issues & Solutions

### 1. Native Modules (node-gyp)

**Problem:** Packages using native bindings fail to install or run.

**Affected packages:** `bcrypt`, `sharp`, `canvas`, `sqlite3`, etc.

**Solutions:**

| Package | Pure JS Alternative |
|---------|---------------------|
| `bcrypt` | `bcryptjs` |
| `better-sqlite3` | `bun:sqlite` (built-in) |
| `node-fetch` | Built-in `fetch` |
| `ws` | Built-in WebSocket |
| `dotenv` | Built-in `.env` loading |

```bash
# Replace bcrypt with bcryptjs
bun remove bcrypt
bun add bcryptjs
```

### 2. Lifecycle Scripts Blocked

**Problem:** `postinstall` scripts don't run.

**Solution:**
```bash
# Trust specific package
bun pm trust esbuild

# Or in package.json
{
  "trustedDependencies": ["esbuild", "sharp"]
}
```

### 3. Module Resolution Differences

**Problem:** Import errors for Node.js internals.

**Solution:** Use `node:` prefix explicitly:
```typescript
// Before (may fail)
import fs from "fs";

// After (always works)
import fs from "node:fs";
```

### 4. __dirname / __filename Not Defined

**Problem:** CommonJS globals not available in ESM.

**Solution:**
```typescript
// Bun provides import.meta alternatives
const __dirname = import.meta.dir;
const __filename = import.meta.path;

// Or use Bun.main
const entryPoint = Bun.main;
```

### 5. require() in ESM

**Problem:** `require` not available in ES modules.

**Solution:**
```typescript
// Bun supports require in ESM!
const pkg = require("./package.json");

// Or use import.meta.require
const data = import.meta.require("./data.json");
```

### 6. process.env Type Issues

**Problem:** TypeScript errors with environment variables.

**Solution:**
```typescript
// Use Bun.env with type narrowing
const port = Bun.env.PORT ?? "3000";

// Or assert type
const apiKey = process.env.API_KEY as string;

// Or check existence
if (!process.env.DATABASE_URL) {
  throw new Error("DATABASE_URL required");
}
```

### 7. Jest Mocks Not Working

**Problem:** Jest-style module mocks fail.

**Solution:**
```typescript
import { mock } from "bun:test";

// Mock modules
mock.module("./api", () => ({
  fetchUser: mock(() => ({ id: 1, name: "Test" }))
}));
```

### 8. Memory Issues with Large File Operations

**Problem:** Memory spikes with many concurrent file reads.

**Solution:**
```typescript
// Use streaming instead of buffering
const file = Bun.file("large.txt");
for await (const chunk of file.stream()) {
  // Process chunk
}

// Or use graceful-fs wrapper
import gracefulFs from "graceful-fs";
```

---

## Framework-Specific Guides

### Express

**Minimal changes required:**
```typescript
import express from "express";

const app = express();
app.get("/", (req, res) => res.send("Hello!"));

// Works in Bun
app.listen(3000);
```

**For better performance, consider Elysia or Hono:**
```typescript
import { Elysia } from "elysia";

new Elysia()
  .get("/", () => "Hello!")
  .listen(3000);
```

### Fastify

**Works with minor adjustments:**
```typescript
import Fastify from "fastify";

const fastify = Fastify({ logger: true });
fastify.get("/", async () => ({ hello: "world" }));

await fastify.listen({ port: 3000 });
```

### Next.js

**Experimental support:**
```bash
bunx create-next-app my-app
cd my-app
bun run dev
```

**Note:** Some features may have issues. Check Bun's Next.js compatibility docs.

### Prisma

**Works with Bun:**
```bash
bun add prisma @prisma/client
bunx prisma generate
bunx prisma migrate dev
```

### GraphQL (Apollo)

**Works with adjustments:**
```typescript
import { ApolloServer } from "@apollo/server";
import { startStandaloneServer } from "@apollo/server/standalone";

const server = new ApolloServer({ typeDefs, resolvers });
const { url } = await startStandaloneServer(server, { listen: { port: 4000 } });
```

---

## CI/CD Updates

### GitHub Actions

```yaml
name: Test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest
      - run: bun install
      - run: bun test
```

### Docker

```dockerfile
FROM oven/bun:1

WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

COPY . .
CMD ["bun", "run", "start"]
```

### GitLab CI

```yaml
test:
  image: oven/bun:1
  script:
    - bun install
    - bun test
```
