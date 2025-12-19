# Bun API Reference

Complete reference for all Bun-specific APIs and modules.

## Table of Contents

- [Bun Global Object](#bun-global-object)
- [HTTP & Networking](#http--networking)
- [File System](#file-system)
- [Process & Shell](#process--shell)
- [Data & Storage](#data--storage)
- [Utilities](#utilities)
- [Built-in Modules](#built-in-modules)

---

## Bun Global Object

### Bun.version
```typescript
Bun.version: string  // e.g., "1.2.0"
```

### Bun.revision
```typescript
Bun.revision: string  // Git commit hash of Bun build
```

### Bun.env
```typescript
Bun.env: Record<string, string | undefined>
// Process environment variables (like process.env)
```

### Bun.main
```typescript
Bun.main: string  // Absolute path to entry point file
```

### Bun.cwd()
```typescript
Bun.cwd(): string  // Current working directory
```

### Bun.origin
```typescript
Bun.origin: string  // Base URL for relative imports
```

---

## HTTP & Networking

### Bun.serve()

Create a high-performance HTTP/WebSocket server.

```typescript
interface ServeOptions {
  port?: number;                    // Default: 3000
  hostname?: string;                // Default: "0.0.0.0"
  unix?: string;                    // Unix socket path
  baseURI?: string;                 // Base URI for routing
  maxRequestBodySize?: number;      // Max body size in bytes
  development?: boolean;            // Enable development mode
  tls?: TLSOptions;                 // TLS/HTTPS configuration

  // Route handlers
  fetch: (req: Request, server: Server) => Response | Promise<Response>;
  error?: (error: Error) => Response | Promise<Response>;

  // Static routes (fastest)
  static?: Record<string, Response | Blob | string>;

  // WebSocket handlers
  websocket?: WebSocketHandler;
}

const server = Bun.serve({
  port: 3000,
  fetch(req, server) {
    const url = new URL(req.url);
    if (url.pathname === "/ws" && server.upgrade(req)) {
      return; // Upgraded to WebSocket
    }
    return new Response("Hello!");
  },
  websocket: {
    open(ws) { ws.subscribe("chat"); },
    message(ws, message) { ws.publish("chat", message); },
    close(ws) { ws.unsubscribe("chat"); },
    drain(ws) { /* backpressure relief */ },
    ping(ws, data) { /* ping received */ },
    pong(ws, data) { /* pong received */ },
  },
  error(error) {
    return new Response(`Error: ${error.message}`, { status: 500 });
  }
});

// Server methods
server.stop();                      // Graceful shutdown
server.reload(newOptions);          // Hot reload configuration
server.publish("topic", "message"); // Publish to WebSocket topic
server.upgrade(req, { data: {} });  // Upgrade to WebSocket
```

### Bun.fetch()

Extended Fetch API with additional options.

```typescript
const response = await Bun.fetch(url, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ data: "value" }),

  // Bun-specific options
  proxy: "http://proxy:8080",       // HTTP proxy
  unix: "/var/run/docker.sock",     // Unix socket
  tls: {                            // TLS options
    rejectUnauthorized: false,
    ca: Bun.file("ca.pem"),
  },
  timeout: 30000,                   // Timeout in ms
  decompress: true,                 // Auto-decompress
  verbose: true,                    // Debug logging
});
```

### Bun.connect() / Bun.listen()

TCP/UDP socket APIs.

```typescript
// TCP Client
const socket = await Bun.connect({
  hostname: "localhost",
  port: 8080,
  socket: {
    data(socket, data) { console.log("Received:", data); },
    open(socket) { socket.write("Hello"); },
    close(socket) { console.log("Closed"); },
    error(socket, error) { console.error(error); },
    drain(socket) { /* ready to write more */ },
  },
  tls: true,  // Enable TLS
});

// TCP Server
const server = Bun.listen({
  hostname: "0.0.0.0",
  port: 8080,
  socket: {
    data(socket, data) { socket.write(data); },  // Echo
    open(socket) { console.log("Client connected"); },
    close(socket) { console.log("Client disconnected"); },
  },
});
```

### Bun.dns

DNS resolution utilities.

```typescript
const records = await Bun.dns.lookup("example.com");
const mx = await Bun.dns.resolve("example.com", "MX");
const txt = await Bun.dns.resolve("example.com", "TXT");
```

---

## File System

### Bun.file()

Create a lazy file reference (zero-copy, memory-efficient).

```typescript
const file = Bun.file("path/to/file.txt");

// File properties
file.size;           // Size in bytes
file.type;           // MIME type
file.name;           // File name
file.lastModified;   // Timestamp

// Read methods (all lazy, zero-copy when possible)
await file.text();          // string
await file.json();          // parsed JSON
await file.arrayBuffer();   // ArrayBuffer
await file.bytes();         // Uint8Array
await file.stream();        // ReadableStream
file.writer();              // FileSink (writable)

// Check existence
await file.exists();  // boolean

// Slice (like Blob.slice)
const slice = file.slice(0, 100);
```

### Bun.write()

Optimized file writing.

```typescript
// Write string
await Bun.write("output.txt", "Hello, World!");

// Write Uint8Array
await Bun.write("output.bin", new Uint8Array([1, 2, 3]));

// Write Response body
await Bun.write("download.zip", await fetch(url));

// Write BunFile (copy)
await Bun.write("copy.txt", Bun.file("original.txt"));

// Write with options
await Bun.write("output.txt", data, {
  createPath: true,  // Create parent directories
  mode: 0o644,       // File permissions
});
```

### Bun.stdin / Bun.stdout / Bun.stderr

Standard I/O streams.

```typescript
// Read from stdin
const input = await Bun.stdin.text();

// Write to stdout
await Bun.write(Bun.stdout, "Hello\n");

// Stream processing
for await (const chunk of Bun.stdin.stream()) {
  await Bun.write(Bun.stdout, chunk);
}
```

### FileSink (Bun.file().writer())

Fast, buffered file writing.

```typescript
const file = Bun.file("log.txt");
const writer = file.writer();

writer.write("Line 1\n");
writer.write("Line 2\n");
await writer.flush();  // Flush buffer to disk
writer.end();          // Close writer
```

---

## Process & Shell

### Bun.spawn()

Spawn child processes.

```typescript
const proc = Bun.spawn(["ls", "-la"], {
  cwd: "/home/user",
  env: { ...process.env, CUSTOM: "value" },
  stdin: "inherit",   // "inherit" | "pipe" | "ignore" | Blob | null
  stdout: "pipe",     // "inherit" | "pipe" | "ignore"
  stderr: "pipe",
  onExit(proc, exitCode, signalCode, error) {
    console.log(`Exited with code ${exitCode}`);
  },
});

// Read output
const stdout = await new Response(proc.stdout).text();
const stderr = await new Response(proc.stderr).text();

// Wait for completion
const exitCode = await proc.exited;

// Kill process
proc.kill("SIGTERM");
```

### Bun.spawnSync()

Synchronous process spawning.

```typescript
const result = Bun.spawnSync(["git", "status"], {
  cwd: "/path/to/repo",
});

console.log(result.stdout.toString());
console.log(result.exitCode);
```

### Bun.$ (Shell)

Cross-platform shell scripting with template literals.

```typescript
import { $ } from "bun";

// Basic command
const result = await $`ls -la`.text();

// Chaining
await $`cat file.txt | grep pattern | wc -l`;

// Variables (auto-escaped)
const file = "my file.txt";
await $`cat ${file}`;

// Environment
await $`echo $HOME`.env({ HOME: "/custom/home" });

// Working directory
await $`pwd`.cwd("/tmp");

// Quiet mode (no output)
await $`rm -rf temp`.quiet();

// Get raw output
const buffer = await $`cat binary.bin`.arrayBuffer();

// Check exit code
const { exitCode } = await $`false`.nothrow();

// Built-in commands (cross-platform)
await $`ls`;      // List files
await $`cd dir`;  // Change directory
await $`rm file`; // Remove
await $`cat file`;// Concatenate
await $`echo hi`; // Print
await $`pwd`;     // Print working directory
await $`mkdir d`; // Make directory
await $`touch f`; // Create file
await $`which c`; // Find command
await $`mv a b`;  // Move/rename
```

---

## Data & Storage

### bun:sqlite

High-performance SQLite driver.

```typescript
import { Database } from "bun:sqlite";

// Create/open database
const db = new Database("app.db");           // Persistent
const memDb = new Database(":memory:");      // In-memory
const roDb = new Database("app.db", { readonly: true });

// Execute statements
db.run("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
db.run("INSERT INTO users (name) VALUES (?)", ["Alice"]);

// Prepared statements
const insert = db.prepare("INSERT INTO users (name) VALUES (?)");
insert.run("Bob");
insert.finalize();

// Queries
const getUser = db.prepare("SELECT * FROM users WHERE id = ?");
const user = getUser.get(1);        // Single row
const users = getUser.all();        // All rows

// Iterate results
for (const row of getUser.iterate()) {
  console.log(row);
}

// Transactions
const insertMany = db.transaction((names: string[]) => {
  for (const name of names) {
    insert.run(name);
  }
});
insertMany(["Charlie", "Diana"]);

// WAL mode for performance
db.exec("PRAGMA journal_mode = WAL");

// Close
db.close();
```

### Bun.sql

Unified SQL client for PostgreSQL, MySQL, SQLite.

```typescript
import { sql } from "bun";

// Connection from environment
const db = sql`postgres://${process.env.DATABASE_URL}`;

// Parameterized queries (safe from SQL injection)
const users = await db`SELECT * FROM users WHERE id = ${userId}`;

// Transactions
await db.transaction(async (tx) => {
  await tx`INSERT INTO users (name) VALUES (${"Alice"})`;
  await tx`INSERT INTO logs (action) VALUES (${"user_created"})`;
});

// Close connection
await db.end();
```

### Bun.S3Client / Bun.s3

Native S3-compatible storage client.

```typescript
// Using default S3 client (from environment)
const file = Bun.s3.file("bucket/path/to/file.txt");
const content = await file.text();

// Custom client
const s3 = new Bun.S3Client({
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  region: "us-east-1",
  endpoint: "https://s3.amazonaws.com",  // Or MinIO, R2, etc.
});

// Read
const file = s3.file("my-bucket/data.json");
const data = await file.json();

// Write
await s3.write("my-bucket/output.txt", "Hello S3!");

// List
const objects = await s3.list("my-bucket/prefix/");

// Delete
await s3.delete("my-bucket/file.txt");

// Presigned URLs
const url = await s3.presign("my-bucket/file.txt", {
  expiresIn: 3600,  // seconds
  method: "GET",
});
```

### Bun.redis

Built-in Redis client.

```typescript
import { redis } from "bun";

const client = redis.createClient({
  url: "redis://localhost:6379",
});

await client.set("key", "value");
const value = await client.get("key");

await client.hSet("hash", { field1: "value1", field2: "value2" });
const hash = await client.hGetAll("hash");

await client.quit();
```

---

## Utilities

### Bun.password

Argon2 password hashing.

```typescript
// Hash password
const hash = await Bun.password.hash("myPassword", {
  algorithm: "argon2id",  // "argon2id" | "argon2i" | "argon2d" | "bcrypt"
  memoryCost: 65536,      // KB (for Argon2)
  timeCost: 3,            // Iterations
});

// Verify password
const isValid = await Bun.password.verify("myPassword", hash);
```

### Bun.hash()

Fast hashing (non-cryptographic).

```typescript
// xxHash (default, fastest)
Bun.hash("data");                    // number
Bun.hash.xxHash32("data");           // number
Bun.hash.xxHash64("data");           // bigint

// Murmur
Bun.hash.murmur32v3("data");         // number
Bun.hash.murmur32v2("data");         // number
Bun.hash.murmur64v2("data");         // bigint

// With seed
Bun.hash("data", 12345);
```

### Bun.CryptoHasher

Cryptographic hashing.

```typescript
const hasher = new Bun.CryptoHasher("sha256");
hasher.update("data");
hasher.update("more data");
const digest = hasher.digest("hex");  // or "base64", "buffer"

// One-liner
const hash = new Bun.CryptoHasher("sha256").update("data").digest("hex");

// Algorithms: "sha256", "sha512", "sha1", "md5", "blake2b256", etc.
```

### Bun.Glob

Native glob pattern matching.

```typescript
const glob = new Bun.Glob("**/*.ts");

// Match against path
glob.match("src/index.ts");  // true
glob.match("README.md");     // false

// Scan directory
for await (const file of glob.scan({ cwd: "./src" })) {
  console.log(file);
}

// Synchronous scan
const files = glob.scanSync({ cwd: "./src" });
```

### Bun.semver

Semantic versioning utilities.

```typescript
Bun.semver.satisfies("1.2.3", "^1.0.0");  // true
Bun.semver.order("1.0.0", "2.0.0");       // -1 (less than)
Bun.semver.order("2.0.0", "1.0.0");       // 1 (greater than)
Bun.semver.order("1.0.0", "1.0.0");       // 0 (equal)
```

### Bun.sleep() / Bun.sleepSync()

```typescript
await Bun.sleep(1000);   // Async sleep (ms)
Bun.sleepSync(1000);     // Sync sleep (ms)
```

### Bun.deepEquals()

```typescript
Bun.deepEquals({ a: 1 }, { a: 1 });  // true
Bun.deepEquals([1, 2], [1, 2]);      // true
Bun.deepEquals({ a: 1 }, { a: 2 });  // false
```

### Bun.escapeHTML()

```typescript
Bun.escapeHTML("<script>alert('xss')</script>");
// "&lt;script&gt;alert(&#x27;xss&#x27;)&lt;/script&gt;"
```

### Bun.YAML

Native YAML parsing.

```typescript
const data = Bun.YAML.parse(`
name: example
version: 1.0.0
dependencies:
  - lodash
  - express
`);

const yaml = Bun.YAML.stringify({ name: "example" });
```

### HTMLRewriter

Streaming HTML transformations.

```typescript
const rewriter = new HTMLRewriter()
  .on("a", {
    element(el) {
      el.setAttribute("target", "_blank");
    },
  })
  .on("script", {
    element(el) {
      el.remove();
    },
  })
  .on("title", {
    text(text) {
      text.replace(text.text.toUpperCase());
    },
  });

const result = rewriter.transform(new Response("<html>...</html>"));
```

---

## Built-in Modules

### bun:ffi

Foreign Function Interface for calling native libraries.

```typescript
import { dlopen, FFIType, suffix } from "bun:ffi";

const lib = dlopen(`libfoo.${suffix}`, {
  add: {
    args: [FFIType.i32, FFIType.i32],
    returns: FFIType.i32,
  },
  greet: {
    args: [FFIType.cstring],
    returns: FFIType.cstring,
  },
});

const result = lib.symbols.add(2, 3);  // 5
const greeting = lib.symbols.greet("World");
```

### bun:jsc

JavaScriptCore internals (advanced).

```typescript
import { heapStats, serialize, deserialize } from "bun:jsc";

// Heap statistics
const stats = heapStats();

// Structured clone serialization
const buffer = serialize({ complex: "object" });
const restored = deserialize(buffer);
```

### bun:test

See Testing Guide for complete documentation.

```typescript
import {
  describe,
  test,
  expect,
  beforeAll,
  afterEach,
  mock,
  spyOn
} from "bun:test";
```

### Web APIs

Bun implements standard Web APIs:

- `fetch()`, `Request`, `Response`, `Headers`
- `URL`, `URLSearchParams`
- `Blob`, `File`, `FormData`
- `TextEncoder`, `TextDecoder`
- `ReadableStream`, `WritableStream`, `TransformStream`
- `WebSocket`
- `crypto.subtle`, `crypto.getRandomValues()`
- `atob()`, `btoa()`
- `setTimeout`, `setInterval`, `queueMicrotask`
- `console.*`
- `performance.now()`
- `navigator.userAgent`
