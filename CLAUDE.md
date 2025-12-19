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
