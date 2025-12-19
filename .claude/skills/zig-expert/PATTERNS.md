# Zig Design Patterns Reference

## State Machine Pattern (Labeled Switch)
```zig
const State = enum { start, processing, done, failed };

fn run(initial: State) !Result {
    return sw: switch (initial) {
        .start => continue :sw .processing,
        .processing => |data| {
            if (isComplete(data)) break :sw .{ .success = data };
            if (hasError(data)) continue :sw .failed;
            continue :sw .processing;
        },
        .done => break :sw .{ .success = {} },
        .failed => return error.ProcessingFailed,
    };
}
```

## Builder Pattern
```zig
const Config = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    timeout: u32 = 30,
    retries: u8 = 3,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn withHost(self: Self, host: []const u8) Self {
        var copy = self;
        copy.host = host;
        return copy;
    }

    pub fn withPort(self: Self, port: u16) Self {
        var copy = self;
        copy.port = port;
        return copy;
    }

    pub fn withTimeout(self: Self, timeout: u32) Self {
        var copy = self;
        copy.timeout = timeout;
        return copy;
    }
};

// Usage
const config = Config.init()
    .withHost("example.com")
    .withPort(443)
    .withTimeout(60);
```

## Resource Pool Pattern
```zig
fn Pool(comptime T: type, comptime size: usize) type {
    return struct {
        items: [size]T = undefined,
        available: [size]bool = [_]bool{true} ** size,
        mutex: std.Thread.Mutex = .{},

        const Self = @This();

        pub fn acquire(self: *Self) ?*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (&self.available, &self.items) |*avail, *item| {
                if (avail.*) {
                    avail.* = false;
                    return item;
                }
            }
            return null;
        }

        pub fn release(self: *Self, item: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const index = (@intFromPtr(item) - @intFromPtr(&self.items)) / @sizeOf(T);
            self.available[index] = true;
        }
    };
}
```

## Iterator Pattern
```zig
const Iterator = struct {
    data: []const u8,
    index: usize = 0,

    pub fn next(self: *Iterator) ?u8 {
        if (self.index >= self.data.len) return null;
        defer self.index += 1;
        return self.data[self.index];
    }

    pub fn peek(self: *const Iterator) ?u8 {
        if (self.index >= self.data.len) return null;
        return self.data[self.index];
    }

    pub fn reset(self: *Iterator) void {
        self.index = 0;
    }
};
```

## Reader/Writer Abstraction
```zig
fn processStream(reader: anytype, writer: anytype) !void {
    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;
        try writer.writeAll(buffer[0..bytes_read]);
    }
}
```

## Sentinel-Terminated Arrays for C Interop
```zig
// Null-terminated string for C
const c_string: [*:0]const u8 = "hello";

// Custom sentinel
const data: [4:255]u8 = .{ 1, 2, 3, 4 };

// Convert slice to sentinel-terminated
fn toSentinelSlice(slice: []const u8, allocator: Allocator) ![*:0]u8 {
    const result = try allocator.allocSentinel(u8, slice.len, 0);
    @memcpy(result, slice);
    return result;
}
```

## RAII Pattern (Resource Acquisition Is Initialization)
```zig
const ManagedFile = struct {
    file: std.fs.File,

    pub fn open(path: []const u8) !ManagedFile {
        return .{
            .file = try std.fs.cwd().openFile(path, .{}),
        };
    }

    pub fn deinit(self: *ManagedFile) void {
        self.file.close();
    }

    pub fn read(self: *ManagedFile, buffer: []u8) !usize {
        return self.file.read(buffer);
    }
};

// Usage with defer
var managed = try ManagedFile.open("data.txt");
defer managed.deinit();
```

## Callback/Closure Pattern
```zig
fn forEachFiltered(
    comptime T: type,
    items: []const T,
    context: anytype,
    predicate: fn (@TypeOf(context), T) bool,
    callback: fn (@TypeOf(context), T) void,
) void {
    for (items) |item| {
        if (predicate(context, item)) {
            callback(context, item);
        }
    }
}

// Usage
const Context = struct {
    threshold: i32,
    count: usize = 0,
};
var ctx = Context{ .threshold = 10 };
forEachFiltered(
    i32,
    &[_]i32{ 5, 15, 8, 20, 3 },
    &ctx,
    struct {
        fn pred(c: *Context, val: i32) bool {
            return val > c.threshold;
        }
    }.pred,
    struct {
        fn cb(c: *Context, _: i32) void {
            c.count += 1;
        }
    }.cb,
);
```

## Type-Safe Flags/Options Pattern
```zig
const Options = packed struct {
    verbose: bool = false,
    debug: bool = false,
    dry_run: bool = false,
    force: bool = false,
    _padding: u4 = 0,

    pub const verbose_flag: Options = .{ .verbose = true };
    pub const debug_flag: Options = .{ .debug = true };
    pub const dry_run_flag: Options = .{ .dry_run = true };

    pub fn combine(a: Options, b: Options) Options {
        const a_int: u8 = @bitCast(a);
        const b_int: u8 = @bitCast(b);
        return @bitCast(a_int | b_int);
    }

    pub fn has(self: Options, other: Options) bool {
        const self_int: u8 = @bitCast(self);
        const other_int: u8 = @bitCast(other);
        return (self_int & other_int) == other_int;
    }
};

// Usage
const opts = Options.verbose_flag.combine(Options.debug_flag);
if (opts.has(Options.verbose_flag)) {
    // verbose mode enabled
}
```

## Slice Window/Chunking Pattern
```zig
fn windows(comptime T: type, slice: []const T, size: usize) WindowIterator(T) {
    return .{ .slice = slice, .size = size };
}

fn WindowIterator(comptime T: type) type {
    return struct {
        slice: []const T,
        size: usize,
        index: usize = 0,

        pub fn next(self: *@This()) ?[]const T {
            if (self.index + self.size > self.slice.len) return null;
            defer self.index += 1;
            return self.slice[self.index..][0..self.size];
        }
    };
}

// Usage
var iter = windows(u8, "hello world", 3);
while (iter.next()) |window| {
    std.debug.print("{s}\n", .{window}); // "hel", "ell", "llo", ...
}
```

## Defer Stack Pattern for Complex Cleanup
```zig
fn complexOperation(allocator: Allocator) !Result {
    var cleanup_stack = std.ArrayList(*anyopaque).init(allocator);
    defer {
        // Cleanup in reverse order
        while (cleanup_stack.popOrNull()) |ptr| {
            // Cleanup logic
            _ = ptr;
        }
        cleanup_stack.deinit();
    }

    const resource1 = try acquireResource1();
    try cleanup_stack.append(@ptrCast(resource1));

    const resource2 = try acquireResource2();
    try cleanup_stack.append(@ptrCast(resource2));

    // Work with resources...
    return computeResult(resource1, resource2);
}
```

## Comptime Interface Validation
```zig
fn assertImplementsReader(comptime T: type) void {
    const has_read = @hasDecl(T, "read");
    const has_reader = @hasDecl(T, "reader");

    if (!has_read and !has_reader) {
        @compileError(@typeName(T) ++ " must implement read() or reader()");
    }
}

fn processReader(reader: anytype) !void {
    comptime assertImplementsReader(@TypeOf(reader));
    // Now safe to use reader
}
```

## Lazy Initialization Pattern
```zig
fn LazyInit(comptime T: type, comptime initFn: fn () T) type {
    return struct {
        value: ?T = null,

        pub fn get(self: *@This()) T {
            if (self.value) |v| return v;
            self.value = initFn();
            return self.value.?;
        }
    };
}

// Usage
var lazy_config = LazyInit(Config, loadConfig){};
const config = lazy_config.get(); // Only loads once
```
