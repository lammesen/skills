# Bun Bundler Guide

Complete guide to bundling with `Bun.build()`.

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration Options](#configuration-options)
- [Targets & Formats](#targets--formats)
- [Code Splitting](#code-splitting)
- [Loaders](#loaders)
- [Plugins](#plugins)
- [Minification](#minification)
- [Source Maps](#source-maps)
- [Single Executable](#single-executable)
- [CLI Reference](#cli-reference)

---

## Quick Start

### JavaScript API

```typescript
const result = await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
});

if (!result.success) {
  console.error("Build failed:", result.logs);
  process.exit(1);
}

console.log("Built:", result.outputs.map(o => o.path));
```

### CLI

```bash
bun build ./src/index.ts --outdir ./dist
```

---

## Configuration Options

### Full Options Reference

```typescript
interface BuildConfig {
  // Entry points (required)
  entrypoints: string[];

  // Output directory
  outdir?: string;

  // Output format
  format?: "esm" | "cjs" | "iife";

  // Target environment
  target?: "browser" | "bun" | "node";

  // Minification
  minify?: boolean | {
    whitespace?: boolean;
    syntax?: boolean;
    identifiers?: boolean;
  };

  // Source maps
  sourcemap?: "none" | "inline" | "linked" | "external";

  // Code splitting
  splitting?: boolean;

  // External packages (not bundled)
  external?: string[];

  // Compile-time constants
  define?: Record<string, string>;

  // Drop function calls
  drop?: string[];

  // File loaders
  loader?: Record<string, Loader>;

  // Custom plugins
  plugins?: BunPlugin[];

  // Root directory for resolution
  root?: string;

  // Public path for assets
  publicPath?: string;

  // Output naming
  naming?: {
    entry?: string;
    chunk?: string;
    asset?: string;
  };

  // Experimental: compile to executable
  compile?: boolean;
}

type Loader =
  | "js" | "jsx" | "ts" | "tsx"
  | "json" | "toml" | "yaml"
  | "text" | "file" | "base64" | "dataurl" | "binary"
  | "css" | "napi";
```

---

## Targets & Formats

### Browser Target

```typescript
await Bun.build({
  entrypoints: ["./src/app.tsx"],
  outdir: "./dist",
  target: "browser",
  format: "esm",
  minify: true,
  splitting: true,
});
```

**Output:** ES modules for modern browsers with code splitting.

### Bun Target

```typescript
await Bun.build({
  entrypoints: ["./src/server.ts"],
  outdir: "./dist",
  target: "bun",
  format: "esm",
});
```

**Output:** Optimized for Bun runtime, uses Bun-specific APIs.

### Node Target

```typescript
await Bun.build({
  entrypoints: ["./src/cli.ts"],
  outdir: "./dist",
  target: "node",
  format: "cjs",
});
```

**Output:** CommonJS compatible with Node.js.

### IIFE Format (Script Tag)

```typescript
await Bun.build({
  entrypoints: ["./src/widget.ts"],
  outdir: "./dist",
  target: "browser",
  format: "iife",
  naming: {
    entry: "widget.min.js",
  },
});
```

**Output:** Immediately-invoked function expression for `<script>` tags.

---

## Code Splitting

### Enable Splitting

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
  splitting: true,
});
```

### Multiple Entry Points

```typescript
await Bun.build({
  entrypoints: [
    "./src/index.ts",
    "./src/admin.ts",
    "./src/worker.ts",
  ],
  outdir: "./dist",
  splitting: true,
});
```

Shared code is automatically extracted into separate chunks.

### Naming Chunks

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
  splitting: true,
  naming: {
    entry: "[dir]/[name].[ext]",
    chunk: "chunks/[name]-[hash].[ext]",
    asset: "assets/[name]-[hash].[ext]",
  },
});
```

**Placeholders:**
- `[name]` - Original file name
- `[hash]` - Content hash
- `[dir]` - Directory path
- `[ext]` - File extension

---

## Loaders

### Built-in Loaders

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
  loader: {
    // JavaScript/TypeScript (default for .js, .ts, .tsx, .jsx)
    ".mts": "ts",
    ".mjs": "js",

    // Data formats
    ".json": "json",
    ".toml": "toml",
    ".yaml": "json",  // Parse YAML as JSON

    // Text content
    ".txt": "text",
    ".md": "text",
    ".html": "text",
    ".sql": "text",
    ".graphql": "text",

    // Binary/assets
    ".png": "dataurl",    // Inline as data URL
    ".jpg": "file",       // Copy to outdir
    ".woff2": "file",
    ".wasm": "file",

    // Base64 encoding
    ".ico": "base64",

    // CSS (experimental)
    ".css": "css",

    // Native addons
    ".node": "napi",
  },
});
```

### Loader Behavior

| Loader | Output |
|--------|--------|
| `js`, `jsx`, `ts`, `tsx` | Bundled JavaScript |
| `json` | Parsed and inlined |
| `toml` | Parsed and inlined |
| `text` | String export |
| `file` | Copied, exports path |
| `dataurl` | Inline data: URL |
| `base64` | Base64 string |
| `binary` | Uint8Array |
| `css` | CSS bundled (experimental) |

### Usage in Code

```typescript
// With "text" loader
import query from "./query.sql";
console.log(query);  // SELECT * FROM users

// With "file" loader
import logo from "./logo.png";
console.log(logo);  // /assets/logo-abc123.png

// With "dataurl" loader
import icon from "./icon.svg";
console.log(icon);  // data:image/svg+xml,...

// With "json" loader
import config from "./config.json";
console.log(config.apiUrl);
```

---

## Plugins

### Plugin Structure

```typescript
interface BunPlugin {
  name: string;
  setup(build: PluginBuilder): void | Promise<void>;
}

interface PluginBuilder {
  onLoad(options: { filter: RegExp }, callback: OnLoadCallback): void;
  onResolve(options: { filter: RegExp }, callback: OnResolveCallback): void;
  config: BuildConfig;  // Access build config
}
```

### onLoad Plugin

Transform file contents before bundling.

```typescript
const yamlPlugin: BunPlugin = {
  name: "yaml-loader",
  setup(build) {
    build.onLoad({ filter: /\.ya?ml$/ }, async (args) => {
      const text = await Bun.file(args.path).text();
      const data = Bun.YAML.parse(text);
      return {
        contents: `export default ${JSON.stringify(data)}`,
        loader: "js",
      };
    });
  },
};

await Bun.build({
  entrypoints: ["./src/index.ts"],
  plugins: [yamlPlugin],
});
```

### onResolve Plugin

Control module resolution.

```typescript
const aliasPlugin: BunPlugin = {
  name: "alias",
  setup(build) {
    build.onResolve({ filter: /^@\// }, (args) => {
      return {
        path: args.path.replace(/^@\//, "./src/"),
      };
    });
  },
};
```

### Virtual Modules

```typescript
const envPlugin: BunPlugin = {
  name: "env",
  setup(build) {
    build.onResolve({ filter: /^virtual:env$/ }, () => {
      return {
        path: "virtual:env",
        namespace: "env",
      };
    });

    build.onLoad({ filter: /.*/, namespace: "env" }, () => {
      return {
        contents: `export const NODE_ENV = "${process.env.NODE_ENV}"`,
        loader: "js",
      };
    });
  },
};

// Usage: import { NODE_ENV } from "virtual:env"
```

### Common Plugins

```typescript
// SVG as React components
const svgPlugin: BunPlugin = {
  name: "svg-react",
  setup(build) {
    build.onLoad({ filter: /\.svg$/ }, async (args) => {
      const svg = await Bun.file(args.path).text();
      return {
        contents: `
          import React from "react";
          export default () => (${svg.replace(/<svg/, '<svg {...props}')});
        `,
        loader: "tsx",
      };
    });
  },
};

// Markdown with frontmatter
const markdownPlugin: BunPlugin = {
  name: "markdown",
  setup(build) {
    build.onLoad({ filter: /\.md$/ }, async (args) => {
      const content = await Bun.file(args.path).text();
      const [, frontmatter, body] = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/) || ["", "", content];
      return {
        contents: `
          export const meta = ${JSON.stringify(Bun.YAML.parse(frontmatter) || {})};
          export const content = ${JSON.stringify(body)};
        `,
        loader: "js",
      };
    });
  },
};
```

---

## Minification

### Enable Minification

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
  minify: true,
});
```

### Granular Control

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
  minify: {
    whitespace: true,    // Remove whitespace
    syntax: true,        // Shorten syntax
    identifiers: true,   // Mangle names
  },
});
```

### Define Constants

Replace identifiers at build time for dead code elimination.

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
  minify: true,
  define: {
    "process.env.NODE_ENV": '"production"',
    "__DEV__": "false",
    "API_URL": '"https://api.example.com"',
  },
});
```

### Drop Console/Debugger

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
  minify: true,
  drop: ["console", "debugger"],
});
```

---

## Source Maps

### Source Map Options

```typescript
// No source maps (default for production)
await Bun.build({
  entrypoints: ["./src/index.ts"],
  sourcemap: "none",
});

// External .map files
await Bun.build({
  entrypoints: ["./src/index.ts"],
  sourcemap: "external",
});

// Inline in bundle (larger file size)
await Bun.build({
  entrypoints: ["./src/index.ts"],
  sourcemap: "inline",
});

// Linked (external, referenced in bundle)
await Bun.build({
  entrypoints: ["./src/index.ts"],
  sourcemap: "linked",
});
```

---

## Single Executable

Compile your application into a standalone executable.

### Basic Compilation

```bash
bun build ./src/index.ts --compile --outfile myapp
```

### With Icon (Windows/macOS)

```bash
bun build ./src/index.ts --compile --outfile myapp --icon ./icon.ico
```

### Cross-Compilation

```bash
# From any platform to:
bun build ./src/index.ts --compile --target=bun-linux-x64 --outfile myapp-linux
bun build ./src/index.ts --compile --target=bun-darwin-arm64 --outfile myapp-mac
bun build ./src/index.ts --compile --target=bun-windows-x64 --outfile myapp.exe
```

### JavaScript API

```typescript
await Bun.build({
  entrypoints: ["./src/index.ts"],
  compile: true,
  outfile: "./myapp",
  minify: true,
});
```

---

## CLI Reference

### Basic Usage

```bash
bun build <entrypoints...> [options]
```

### Output Options

```bash
--outdir=<path>           # Output directory
--outfile=<path>          # Single output file
--format=esm|cjs|iife     # Output format
--target=browser|bun|node # Target environment
```

### Optimization

```bash
--minify                  # Enable all minification
--minify-whitespace       # Remove whitespace only
--minify-syntax           # Shorten syntax only
--minify-identifiers      # Mangle names only
--drop=console,debugger   # Remove calls
```

### Source Maps

```bash
--sourcemap=none|inline|external|linked
```

### Code Splitting

```bash
--splitting               # Enable code splitting
--public-path=<url>       # Public URL for assets
```

### Externals

```bash
--external=<pkg>          # Mark as external
--external:*              # Externalize all node_modules
```

### Define

```bash
--define:KEY=value        # Replace at build time
```

### Compile

```bash
--compile                 # Create executable
--target=bun-<os>-<arch>  # Cross-compile target
```

### Examples

```bash
# Production browser build
bun build ./src/index.tsx --outdir=dist --minify --splitting --sourcemap=external

# Node.js CLI tool
bun build ./src/cli.ts --outfile=dist/cli.js --target=node --format=cjs

# Single executable
bun build ./src/app.ts --compile --outfile=myapp --minify

# Cross-compile for Linux
bun build ./src/app.ts --compile --target=bun-linux-x64 --outfile=myapp-linux
```

---

## Build Outputs

### Result Object

```typescript
interface BuildOutput {
  success: boolean;
  outputs: BuildArtifact[];
  logs: BuildMessage[];
}

interface BuildArtifact {
  path: string;           // Output path
  kind: "entry-point" | "chunk" | "asset" | "sourcemap";
  hash: string;           // Content hash
  size: number;           // Bytes
  loader: Loader;
}

interface BuildMessage {
  level: "error" | "warning" | "info" | "debug" | "verbose";
  message: string;
  location?: {
    file: string;
    line: number;
    column: number;
  };
}
```

### Handling Results

```typescript
const result = await Bun.build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist",
});

if (!result.success) {
  for (const log of result.logs) {
    if (log.level === "error") {
      console.error(log.message);
      if (log.location) {
        console.error(`  at ${log.location.file}:${log.location.line}`);
      }
    }
  }
  process.exit(1);
}

console.log("Build successful!");
for (const output of result.outputs) {
  console.log(`  ${output.kind}: ${output.path} (${output.size} bytes)`);
}
```

---

## Best Practices

1. **Use Code Splitting** - Reduce initial load time
2. **Externalize Large Dependencies** - Consider CDN for React, etc.
3. **Enable Minification** - Always for production
4. **Use Define for Environment** - Dead code elimination
5. **Generate Source Maps** - External for production, inline for dev
6. **Hash Output Names** - Cache busting
7. **Drop Console in Production** - Smaller bundles
