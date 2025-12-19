#!/bin/bash
# Zig linting and formatting hook for Claude Code
# Usage: Called by PostToolUse hook after file edits

set -e

# Read tool input from stdin
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.files[0].file_path // empty')

# Exit if no file path or not a Zig file
if [ -z "$file_path" ] || ! echo "$file_path" | grep -qE '\.zig$'; then
    exit 0
fi

# Check if file exists
if [ ! -f "$file_path" ]; then
    exit 0
fi

echo "Checking Zig file: $file_path"

# Run zig fmt
if command -v zig >/dev/null 2>&1; then
    echo "Formatting with zig fmt..."
    zig fmt "$file_path" 2>&1 || true
fi

# Run zlint if available
if command -v zlint >/dev/null 2>&1; then
    echo "Linting with zlint..."
    zlint "$file_path" 2>&1 || true
fi

echo "Zig checks complete"
exit 0
