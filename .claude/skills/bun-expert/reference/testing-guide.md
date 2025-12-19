# Bun Test Runner Guide

Complete guide to testing with `bun:test`.

## Table of Contents

- [Quick Start](#quick-start)
- [Test Structure](#test-structure)
- [Assertions & Matchers](#assertions--matchers)
- [Mocking](#mocking)
- [Async Testing](#async-testing)
- [Snapshots](#snapshots)
- [Test Lifecycle](#test-lifecycle)
- [Configuration](#configuration)
- [Coverage](#coverage)
- [CLI Reference](#cli-reference)

---

## Quick Start

```typescript
// math.test.ts
import { describe, test, expect } from "bun:test";
import { add } from "./math";

describe("math", () => {
  test("adds two numbers", () => {
    expect(add(1, 2)).toBe(3);
  });
});
```

```bash
bun test
```

---

## Test Structure

### Basic Test

```typescript
import { test, expect } from "bun:test";

test("basic assertion", () => {
  expect(2 + 2).toBe(4);
});
```

### Describe Blocks

```typescript
import { describe, test, expect } from "bun:test";

describe("Calculator", () => {
  describe("add", () => {
    test("adds positive numbers", () => {
      expect(add(1, 2)).toBe(3);
    });

    test("adds negative numbers", () => {
      expect(add(-1, -2)).toBe(-3);
    });
  });

  describe("multiply", () => {
    test("multiplies numbers", () => {
      expect(multiply(2, 3)).toBe(6);
    });
  });
});
```

### Test Modifiers

```typescript
import { test, describe } from "bun:test";

// Skip tests
test.skip("skipped test", () => {});
describe.skip("skipped suite", () => {});

// Run only specific tests (requires --only flag)
test.only("focused test", () => {});
describe.only("focused suite", () => {});

// Mark as todo
test.todo("not implemented yet");
describe.todo("suite not implemented");

// Conditional tests
test.if(process.platform === "linux")("linux only", () => {});
test.skipIf(process.platform === "win32")("skip on windows", () => {});

// Expected to fail
test.failing("known bug", () => {
  expect(buggyFunction()).toBe(correct);
});

// Retry failed tests
test.retry(3)("flaky test", async () => {
  await flakyOperation();
});

// Concurrent tests
test.concurrent("parallel 1", async () => {});
test.concurrent("parallel 2", async () => {});
```

### Parameterized Tests

```typescript
import { test, expect } from "bun:test";

// test.each with arrays
test.each([
  [1, 2, 3],
  [2, 3, 5],
  [5, 5, 10],
])("add(%i, %i) = %i", (a, b, expected) => {
  expect(add(a, b)).toBe(expected);
});

// test.each with objects
test.each([
  { input: "hello", expected: "HELLO" },
  { input: "world", expected: "WORLD" },
])("uppercase($input) = $expected", ({ input, expected }) => {
  expect(input.toUpperCase()).toBe(expected);
});

// describe.each
describe.each([
  { name: "Chrome", version: 100 },
  { name: "Firefox", version: 95 },
])("$name v$version", ({ name, version }) => {
  test("is supported", () => {
    expect(isSupported(name, version)).toBe(true);
  });
});
```

---

## Assertions & Matchers

### Equality

```typescript
// Strict equality (===)
expect(value).toBe(expected);

// Deep equality
expect(object).toEqual({ a: 1, b: { c: 2 } });

// Strict deep equality (same types)
expect(object).toStrictEqual(expected);
```

### Truthiness

```typescript
expect(value).toBeTruthy();
expect(value).toBeFalsy();
expect(value).toBeNull();
expect(value).toBeUndefined();
expect(value).toBeDefined();
expect(value).toBeNaN();
```

### Numbers

```typescript
expect(value).toBeGreaterThan(3);
expect(value).toBeGreaterThanOrEqual(3);
expect(value).toBeLessThan(5);
expect(value).toBeLessThanOrEqual(5);
expect(value).toBeCloseTo(3.14, 2);  // 2 decimal places
expect(value).toBeInteger();
expect(value).toBePositive();
expect(value).toBeNegative();
expect(value).toBeFinite();
```

### Strings

```typescript
expect(str).toMatch(/pattern/);
expect(str).toContain("substring");
expect(str).toStartWith("Hello");
expect(str).toEndWith("!");
expect(str).toHaveLength(5);
```

### Arrays

```typescript
expect(arr).toContain(item);
expect(arr).toContainEqual({ id: 1 });  // Deep equality
expect(arr).toHaveLength(3);
expect(arr).toBeEmpty();
expect(arr).toBeArrayOfSize(3);
```

### Objects

```typescript
expect(obj).toHaveProperty("key");
expect(obj).toHaveProperty("nested.key", "value");
expect(obj).toMatchObject({ subset: true });
expect(obj).toBeInstanceOf(MyClass);
expect(obj).toBeEmpty();
```

### Errors

```typescript
// Sync errors
expect(() => throwError()).toThrow();
expect(() => throwError()).toThrow("message");
expect(() => throwError()).toThrow(/pattern/);
expect(() => throwError()).toThrow(ErrorClass);

// Async errors
await expect(asyncThrow()).rejects.toThrow();
await expect(promise).rejects.toThrow("error");
```

### Promises

```typescript
await expect(promise).resolves.toBe(value);
await expect(promise).resolves.toEqual(expected);
await expect(promise).rejects.toThrow();
```

### Negation

```typescript
expect(value).not.toBe(other);
expect(arr).not.toContain(item);
expect(obj).not.toHaveProperty("key");
```

### Custom Matchers

```typescript
import { expect, extend } from "bun:test";

extend({
  toBeWithinRange(received, floor, ceiling) {
    const pass = received >= floor && received <= ceiling;
    return {
      pass,
      message: () => `Expected ${received} to be within range ${floor}-${ceiling}`,
    };
  },
});

test("custom matcher", () => {
  expect(50).toBeWithinRange(1, 100);
});
```

---

## Mocking

### Mock Functions

```typescript
import { mock, expect, test } from "bun:test";

test("mock function", () => {
  const fn = mock(() => 42);

  expect(fn()).toBe(42);
  expect(fn).toHaveBeenCalled();
  expect(fn).toHaveBeenCalledTimes(1);
});
```

### Mock Implementations

```typescript
const fn = mock(() => "default");

// Change implementation
fn.mockImplementation(() => "new");
fn.mockImplementationOnce(() => "once");

// Return values
fn.mockReturnValue("value");
fn.mockReturnValueOnce("once");

// Resolved values (async)
fn.mockResolvedValue({ data: true });
fn.mockResolvedValueOnce({ data: true });

// Rejected values
fn.mockRejectedValue(new Error("failed"));
fn.mockRejectedValueOnce(new Error("once"));

// Clear/reset
fn.mockClear();  // Clear call history
fn.mockReset();  // Clear history + implementation
fn.mockRestore();  // Restore original
```

### Mock Assertions

```typescript
expect(fn).toHaveBeenCalled();
expect(fn).toHaveBeenCalledTimes(2);
expect(fn).toHaveBeenCalledWith(arg1, arg2);
expect(fn).toHaveBeenLastCalledWith(arg);
expect(fn).toHaveBeenNthCalledWith(1, arg);
expect(fn).toHaveReturned();
expect(fn).toHaveReturnedWith(value);
expect(fn).toHaveLastReturnedWith(value);
```

### Spying

```typescript
import { spyOn, expect, test } from "bun:test";

const obj = {
  method: (x: number) => x * 2,
};

test("spy on method", () => {
  const spy = spyOn(obj, "method");

  obj.method(5);

  expect(spy).toHaveBeenCalledWith(5);
  expect(spy).toHaveReturnedWith(10);

  spy.mockImplementation((x) => x * 3);
  expect(obj.method(5)).toBe(15);

  spy.mockRestore();
  expect(obj.method(5)).toBe(10);
});
```

### Module Mocking

```typescript
import { mock, test } from "bun:test";

// Mock entire module
mock.module("./api", () => ({
  fetchUser: mock(() => ({ id: 1, name: "Test" })),
  fetchPosts: mock(() => []),
}));

// Now imports use mocked version
import { fetchUser } from "./api";

test("uses mocked module", async () => {
  const user = await fetchUser(1);
  expect(user.name).toBe("Test");
});
```

### Restore All Mocks

```typescript
import { afterEach, mock } from "bun:test";

afterEach(() => {
  mock.restore();  // Restore all mocks
});
```

---

## Async Testing

### Async/Await

```typescript
test("async operation", async () => {
  const result = await fetchData();
  expect(result).toEqual({ success: true });
});
```

### Promises

```typescript
test("returns promise", () => {
  return fetchData().then(result => {
    expect(result.success).toBe(true);
  });
});
```

### Callbacks (Done)

```typescript
test("callback style", (done) => {
  fetchData((error, result) => {
    expect(error).toBeNull();
    expect(result.success).toBe(true);
    done();
  });
});
```

### Timeouts

```typescript
// Per-test timeout
test("slow operation", async () => {
  await slowOperation();
}, { timeout: 10000 });  // 10 seconds

// Global timeout via CLI
// bun test --timeout=30000
```

---

## Snapshots

### Basic Snapshots

```typescript
test("snapshot", () => {
  const output = generateOutput();
  expect(output).toMatchSnapshot();
});
```

### Inline Snapshots

```typescript
test("inline snapshot", () => {
  const user = { name: "Alice", age: 30 };
  expect(user).toMatchInlineSnapshot(`
    {
      "age": 30,
      "name": "Alice",
    }
  `);
});
```

### Update Snapshots

```bash
bun test --update-snapshots
```

### Snapshot Serializers

```typescript
import { expect, addSnapshotSerializer } from "bun:test";

addSnapshotSerializer({
  test: (value) => value instanceof Date,
  serialize: (value) => `Date<${value.toISOString()}>`,
});

test("custom serializer", () => {
  expect(new Date("2024-01-01")).toMatchSnapshot();
  // Snapshot: Date<2024-01-01T00:00:00.000Z>
});
```

---

## Test Lifecycle

### Setup & Teardown

```typescript
import {
  beforeAll,
  afterAll,
  beforeEach,
  afterEach,
  describe,
  test
} from "bun:test";

describe("with lifecycle", () => {
  let db: Database;
  let user: User;

  // Run once before all tests in this describe
  beforeAll(async () => {
    db = await Database.connect();
  });

  // Run once after all tests in this describe
  afterAll(async () => {
    await db.close();
  });

  // Run before each test
  beforeEach(async () => {
    user = await db.createUser({ name: "Test" });
  });

  // Run after each test
  afterEach(async () => {
    await db.deleteUser(user.id);
  });

  test("user exists", () => {
    expect(user).toBeDefined();
  });
});
```

### Nested Lifecycle

```typescript
describe("outer", () => {
  beforeEach(() => console.log("outer before"));
  afterEach(() => console.log("outer after"));

  describe("inner", () => {
    beforeEach(() => console.log("inner before"));
    afterEach(() => console.log("inner after"));

    test("runs in order", () => {
      console.log("test");
    });
    // Order: outer before → inner before → test → inner after → outer after
  });
});
```

---

## Configuration

### bunfig.toml

```toml
[test]
# Preload scripts before tests
preload = ["./test/setup.ts"]

# Enable coverage
coverage = true

# Coverage thresholds
coverageThreshold = { lines = 80, functions = 80, branches = 70 }

# Test file patterns
include = ["**/*.test.ts", "**/*.spec.ts"]

# Exclude patterns
exclude = ["**/node_modules/**"]

# Default timeout (ms)
timeout = 5000

# Bail on first failure
bail = false

# Retry count for flaky tests
retry = 0
```

### Test Setup File

```typescript
// test/setup.ts
import { beforeAll, afterAll, mock } from "bun:test";

// Global setup
beforeAll(() => {
  // Set up test database, mocks, etc.
});

// Global teardown
afterAll(() => {
  // Clean up
});

// Global mock
mock.module("./config", () => ({
  apiUrl: "http://localhost:3000",
}));
```

---

## Coverage

### Enable Coverage

```bash
bun test --coverage
```

### Coverage Output

```
----------|---------|----------|---------|---------|
File      | % Stmts | % Branch | % Funcs | % Lines |
----------|---------|----------|---------|---------|
All files |   85.71 |    66.67 |     100 |   85.71 |
 math.ts  |   85.71 |    66.67 |     100 |   85.71 |
----------|---------|----------|---------|---------|
```

### Coverage Thresholds

```toml
# bunfig.toml
[test]
coverageThreshold = {
  lines = 80,
  functions = 80,
  branches = 70,
  statements = 80
}
```

### Ignore Coverage

```typescript
/* c8 ignore start */
function ignoredCode() {
  // Not included in coverage
}
/* c8 ignore stop */

function partiallyIgnored() {
  /* c8 ignore next */
  debugOnlyCode();
}
```

---

## CLI Reference

### Basic Commands

```bash
bun test                      # Run all tests
bun test path/to/test.ts      # Run specific file
bun test src/                 # Run tests in directory
```

### Filtering

```bash
bun test -t "pattern"         # Filter by test name
bun test --only               # Run only .only tests
bun test --todo               # Include .todo tests
```

### Watch Mode

```bash
bun test --watch              # Rerun on file changes
```

### Output

```bash
bun test --bail               # Stop on first failure
bun test --bail=5             # Stop after 5 failures
bun test --reporter=spec      # Use spec reporter
```

### Coverage

```bash
bun test --coverage           # Enable coverage
bun test --coverage-dir=cov   # Custom coverage directory
```

### Snapshots

```bash
bun test --update-snapshots   # Update snapshots
bun test -u                   # Short form
```

### Timing

```bash
bun test --timeout=10000      # 10 second timeout
```

### Environment

```bash
bun test --env-file=.env.test # Load specific env file
bun test --preload=./setup.ts # Preload script
```

---

## Best Practices

1. **One Assertion per Test** - Keep tests focused
2. **Descriptive Names** - `"returns user when ID exists"` not `"test user"`
3. **Arrange-Act-Assert** - Clear test structure
4. **Mock External Services** - Don't hit real APIs
5. **Use beforeEach for Setup** - Fresh state per test
6. **Clean Up in afterEach** - Prevent test pollution
7. **Avoid Test Dependencies** - Tests should run in any order
8. **Test Edge Cases** - Empty inputs, errors, boundaries
