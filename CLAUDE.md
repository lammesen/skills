# Zig Project Configuration

## Project Type
This is a Zig project using Zig 0.15.2.

## Build Commands
- `zig build` - Build the project
- `zig build run` - Build and run
- `zig build test` - Run all tests
- `zig fmt src/` - Format all source files

## Code Quality
- zlint is configured for static analysis
- zig fmt enforces standard formatting
- All code must pass `zig build test` before commit

## Architecture Notes
[Add project-specific architecture notes here]

## Dependencies
See `build.zig.zon` for external dependencies.

## Cross-Compilation Targets
- Linux x86_64
- macOS aarch64
- Windows x86_64

Build for specific target: `zig build -Dtarget=<target>`

## Zig Expert Skill

This project includes a comprehensive Zig Expert Skill for Claude Code located in `.claude/skills/zig-expert/`. The skill provides:

### Main Skill
- **SKILL.md**: Core Zig 0.15.2 expertise including memory management, error handling, comptime, type system, build system, testing, and cross-compilation patterns

### Supporting Documentation
- **PATTERNS.md**: Extended design patterns (state machines, builders, pools, iterators, etc.)
- **BUILD_TEMPLATES.md**: Build system templates for various project types
- **ERROR_REFERENCE.md**: Common error diagnostics and solutions

### Specialized Agents
- **zig-tester**: Testing specialist for running tests, diagnosing failures, and ensuring code quality
- **zig-builder**: Build system expert for build.zig configuration, dependencies, and cross-compilation
- **zig-debugger**: Debugging specialist for runtime errors, memory issues, and performance analysis

### Hooks
- Automatic `zig fmt` formatting on file save
- Automatic `zlint` linting on file save (if installed)

## Installing zlint (Optional)
```bash
curl -fsSL https://raw.githubusercontent.com/DonIsaac/zlint/refs/heads/main/tasks/install.sh | bash
```

---

## Bun Expert Skill

This project also includes a comprehensive Bun Expert Skill for Claude Code located in `.claude/skills/bun-expert/`. The skill provides:

### Main Skill
- **SKILL.md**: Core Bun runtime expertise including HTTP servers, file I/O, package management, testing, bundling, TypeScript integration, and Node.js migration patterns

### Reference Documentation
- **api-reference.md**: Complete Bun API reference (Bun.serve, Bun.file, bun:sqlite, etc.)
- **migration-guide.md**: Node.js to Bun migration strategies and compatibility matrix
- **testing-guide.md**: Comprehensive bun:test documentation
- **bundler-guide.md**: Bun.build() configuration and optimization

### Specialized Agents
- **bun-tester**: Testing specialist for running tests, diagnosing failures, and ensuring code quality with bun:test
- **bun-bundler**: Build system expert for Bun.build() configuration, optimization, and single executable compilation
- **bun-migrator**: Migration specialist for converting Node.js projects to Bun
- **bun-debugger**: Debugging specialist for runtime errors, performance issues, and memory analysis

### Hooks
- Automatic Biome formatting on TypeScript/JavaScript file save (in Bun projects)
- Automatic test running with `bun test --bail` on session stop (in Bun projects)

### Bun Commands
```bash
bun install              # Install dependencies
bun run <script>         # Run package.json script
bun test                 # Run tests
bun build                # Bundle for production
bunx <package>           # Execute package without installing
```

### Installing Bun
```bash
curl -fsSL https://bun.sh/install | bash
```

---

## ElysiaJS Expert Skill

This project includes a comprehensive ElysiaJS Expert Skill for Claude Code located in `.claude/skills/elysiajs-expert/`. The skill provides:

### Main Skill
- **SKILL.md**: Core ElysiaJS expertise including routing, lifecycle hooks, TypeBox validation, Eden type-safe clients, authentication with JWT/Bearer, all official plugins, testing patterns, and production deployment

### Reference Documentation
- **core-api.md**: Complete Elysia core API reference (constructor, routes, context, state, plugins)
- **lifecycle-hooks.md**: All lifecycle hooks in detail (onRequest, onParse, derive, resolve, beforeHandle, etc.)
- **typebox-validation.md**: TypeBox schema patterns and validation
- **plugins.md**: All official plugins (OpenAPI, JWT, Bearer, CORS, Static, HTML, Cron, GraphQL, tRPC)
- **eden-client.md**: Eden Treaty type-safe client patterns

### Pattern Documentation
- **authentication.md**: JWT, Bearer, session, RBAC, OAuth patterns
- **api-design.md**: REST API design, project structure, error handling
- **websocket.md**: WebSocket implementation patterns
- **testing.md**: Testing strategies with bun:test and Eden

### Project Templates
- **basic-api.md**: Minimal API template
- **auth-api.md**: Authenticated API with JWT
- **fullstack.md**: Full-stack Elysia + Eden template

### Specialized Agents
- **elysia-router**: Route design expert for REST APIs, path parameters, groups, and guards
- **elysia-auth**: Authentication specialist for JWT, sessions, RBAC, and OAuth
- **elysia-api-designer**: API design specialist for schemas, OpenAPI, and conventions

### ElysiaJS Commands
```bash
# Create new Elysia project
bun create elysia my-app

# Install Elysia and plugins
bun add elysia @elysiajs/cors @elysiajs/jwt @elysiajs/openapi

# Run development server
bun --watch src/index.ts

# Build for production
bun build --compile --minify src/index.ts --outfile server
```

### Integration with Bun Expert Skill
The ElysiaJS skill assumes the Bun Expert Skill is active for Bun-specific patterns (file I/O, SQLite, testing runner, builds). Elysia projects benefit from existing Bun hooks for TypeScript formatting.
