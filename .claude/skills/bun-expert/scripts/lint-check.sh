#!/bin/bash
# Bun linting and formatting hook for Claude Code
# Usage: Called by PostToolUse hook after file edits

set -e

# Read tool input from stdin
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.files[0].file_path // empty')

# Exit if no file path or not a JS/TS file
if [ -z "$file_path" ]; then
    exit 0
fi

# Check if it's a JavaScript/TypeScript file
if ! echo "$file_path" | grep -qE '\.(ts|tsx|js|jsx|mjs|mts|cjs|cts)$'; then
    exit 0
fi

# Check if file exists
if [ ! -f "$file_path" ]; then
    exit 0
fi

echo "Checking Bun/JS file: $file_path"

# Check if we're in a Bun project (has bunfig.toml, bun.lock, or bun.lockb)
project_dir=$(dirname "$file_path")
is_bun_project=false

while [ "$project_dir" != "/" ]; do
    if [ -f "$project_dir/bunfig.toml" ] || [ -f "$project_dir/bun.lock" ] || [ -f "$project_dir/bun.lockb" ]; then
        is_bun_project=true
        break
    fi
    project_dir=$(dirname "$project_dir")
done

if [ "$is_bun_project" = false ]; then
    # Not a Bun project, skip
    exit 0
fi

# Run Biome if available (preferred for Bun projects)
if command -v biome >/dev/null 2>&1; then
    echo "Formatting with Biome..."
    biome check --write "$file_path" 2>&1 || true
elif bunx biome --version >/dev/null 2>&1; then
    echo "Formatting with Biome (via bunx)..."
    bunx biome check --write "$file_path" 2>&1 || true
fi

# Run ESLint if available (fallback)
if [ ! -f "$project_dir/biome.json" ] && [ ! -f "$project_dir/biome.jsonc" ]; then
    if command -v eslint >/dev/null 2>&1; then
        echo "Linting with ESLint..."
        eslint --fix "$file_path" 2>&1 || true
    fi
fi

# Run Prettier if available and no Biome
if [ ! -f "$project_dir/biome.json" ] && [ ! -f "$project_dir/biome.jsonc" ]; then
    if command -v prettier >/dev/null 2>&1; then
        echo "Formatting with Prettier..."
        prettier --write "$file_path" 2>&1 || true
    fi
fi

echo "Bun/JS checks complete"
exit 0
