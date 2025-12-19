# Zig Error Reference

## Common Compiler Errors

### error: expected ',' after argument
**Cause**: Missing comma in function call or array literal.
```zig
// Wrong
const arr = [_]i32{ 1 2 3 };
foo(a b);

// Correct
const arr = [_]i32{ 1, 2, 3 };
foo(a, b);
```

### error: unused local variable
**Cause**: Variable declared but never used.
```zig
// Wrong
const x = 5; // Never used

// Correct - if intentional
_ = x; // Explicitly discard
```

### error: expected type expression, found 'var'
**Cause**: Using `var` where a type is expected (common in function parameters).
```zig
// Wrong
fn foo(x: var) void {}

// Correct
fn foo(x: anytype) void {}
```

### error: cannot assign to constant
**Cause**: Trying to modify a `const` binding.
```zig
// Wrong
const x = 5;
x = 6;

// Correct
var x = 5;
x = 6;
```

### error: type 'T' is not indexable
**Cause**: Trying to index a non-indexable type.
```zig
// Wrong
const x: u32 = 5;
_ = x[0];

// Correct - use slice or array
const arr = [_]u32{ 5 };
_ = arr[0];
```

### error: cannot implicitly cast
**Cause**: Type mismatch without explicit conversion.
```zig
// Wrong
const x: u32 = -1;

// Correct
const x: i32 = -1;
// Or with cast (if intentional)
const y: u32 = @intCast(@as(i32, -1) + 2);
```

---

## Runtime Errors

### panic: index out of bounds
**Cause**: Accessing array/slice with invalid index.
```zig
const arr = [_]i32{ 1, 2, 3 };
_ = arr[5]; // Panic!

// Prevention
if (index < arr.len) {
    _ = arr[index];
}
```

### panic: integer overflow
**Cause**: Arithmetic operation exceeds type bounds (Debug mode).
```zig
const x: u8 = 255;
_ = x + 1; // Panic in Debug!

// Use wrapping operations if intended
_ = x +% 1; // Wraps to 0
_ = x +| 1; // Saturates to 255
```

### panic: attempt to unwrap null pointer
**Cause**: Dereferencing null optional pointer.
```zig
var ptr: ?*i32 = null;
_ = ptr.?; // Panic!

// Prevention
if (ptr) |p| {
    _ = p.*;
}
```

### panic: reached unreachable code
**Cause**: Execution reached an `unreachable` statement.
```zig
fn foo(x: u8) u8 {
    return switch (x) {
        0 => 1,
        1 => 2,
        else => unreachable, // Panic if x > 1!
    };
}
```

---

## Memory Errors

### error: OutOfMemory
**Cause**: Allocator failed to allocate memory.
```zig
// Handle explicitly
const slice = allocator.alloc(u8, size) catch |err| {
    std.log.err("Allocation failed: {}", .{err});
    return err;
};
```

### Memory leak detected (GPA)
**Cause**: Allocated memory not freed before allocator deinit.
```zig
// Wrong
const data = try allocator.alloc(u8, 100);
// Missing: allocator.free(data);

// Correct
const data = try allocator.alloc(u8, 100);
defer allocator.free(data);
```

### Use after free
**Cause**: Accessing memory after it was freed.
```zig
// Wrong
const data = try allocator.alloc(u8, 100);
allocator.free(data);
_ = data[0]; // Undefined behavior!

// Prevention: nullify after free
var data = try allocator.alloc(u8, 100);
defer {
    allocator.free(data);
    data = undefined;
}
```

### Double free
**Cause**: Freeing the same memory twice.
```zig
// Wrong
allocator.free(data);
allocator.free(data); // Undefined behavior!

// Prevention: use defer once
defer allocator.free(data);
```

---

## Build System Errors

### error: FileNotFound for build.zig.zon dependency
**Cause**: Dependency URL invalid or hash mismatch.
```bash
# Fetch and update hash
zig fetch --save <url>
```

### error: dependency loop detected
**Cause**: Circular module imports.
```zig
// a.zig imports b.zig
// b.zig imports a.zig -> Loop!

// Solution: Restructure to avoid cycle
// Or use @import at function level
```

### error: unable to find 'zig-cache'
**Cause**: Build cache corrupted.
```bash
rm -rf zig-cache .zig-cache zig-out
zig build
```

---

## Common Warnings

### warning: unused function parameter
```zig
// Wrong
fn foo(x: i32) void {
    // x not used
}

// Correct
fn foo(_: i32) void {
    // Explicitly unused
}
```

### warning: unreachable code
```zig
// Wrong
fn foo() void {
    return;
    const x = 5; // Never reached
}
```

---

## Error Handling Best Practices

### Define Specific Error Sets
```zig
// Prefer this
const FileError = error{
    NotFound,
    AccessDenied,
    IoError,
};

fn readFile() FileError![]u8 { ... }

// Over this
fn readFile() anyerror![]u8 { ... }
```

### Use errdefer for Cleanup
```zig
fn init(allocator: Allocator) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.data = try allocator.alloc(u8, 1024);
    errdefer allocator.free(self.data);

    try self.setup(); // If this fails, both errdefers run
    return self;
}
```

### Exhaustive Error Handling
```zig
const result = operation() catch |err| switch (err) {
    error.NotFound => handleNotFound(),
    error.AccessDenied => handleDenied(),
    error.IoError => handleIo(),
    // Compiler ensures all errors handled
};
```

---

## Debugging Tips

### Enable Stack Traces
```zig
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.debug.print("Panic: {s}\n", .{msg});
    if (trace) |t| {
        std.debug.dumpStackTrace(t.*);
    }
    std.process.abort();
}
```

### Use std.debug.print
```zig
std.debug.print("value: {}, type: {s}\n", .{ value, @typeName(@TypeOf(value)) });
```

### GPA with Stack Traces
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 10,
}){};
```

### Compile with Debug Info
```bash
zig build -Doptimize=Debug
```
