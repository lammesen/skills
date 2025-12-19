#!/bin/bash
# Bun test runner for Claude Code
# Usage: Called by Stop hook or manually to run tests

set -e

# Get project directory from environment or use current directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Check if we're in a Bun project
is_bun_project=false

if [ -f "$PROJECT_DIR/bunfig.toml" ] || [ -f "$PROJECT_DIR/bun.lock" ] || [ -f "$PROJECT_DIR/bun.lockb" ]; then
    is_bun_project=true
fi

# Also check for bun in package.json scripts
if [ -f "$PROJECT_DIR/package.json" ]; then
    if grep -q '"bun' "$PROJECT_DIR/package.json" 2>/dev/null; then
        is_bun_project=true
    fi
fi

if [ "$is_bun_project" = false ]; then
    echo "Not a Bun project, skipping tests"
    exit 0
fi

# Check if bun is installed
if ! command -v bun >/dev/null 2>&1; then
    echo "Bun is not installed, skipping tests"
    exit 0
fi

echo "Running Bun tests..."
cd "$PROJECT_DIR"

# Check if there are test files
test_files=$(find . -name "*.test.ts" -o -name "*.test.tsx" -o -name "*.test.js" -o -name "*.test.jsx" -o -name "*.spec.ts" -o -name "*.spec.tsx" -o -name "*.spec.js" -o -name "*.spec.jsx" 2>/dev/null | head -5)

if [ -z "$test_files" ]; then
    echo "No test files found, skipping tests"
    exit 0
fi

# Run tests with bail (stop on first failure)
if bun test --bail 2>&1; then
    echo "All tests passed!"
    exit 0
else
    echo "Tests completed with failures"
    exit 1
fi
