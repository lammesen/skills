# Zig Build System Templates

## Minimal Executable
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    b.installArtifact(exe);
}
```

## Full-Featured Application
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the application").dependOn(&run_cmd.step);

    // Unit tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run unit tests").dependOn(&run_tests.step);

    // Documentation
    const docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("docs", "Generate documentation").dependOn(&docs.step);
}
```

## Library with Header Generation
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mylib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Generate C header
    lib.installHeader(b.path("include/mylib.h"), "mylib.h");
    b.installArtifact(lib);
}
```

## Shared Library (Dynamic)
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "mylib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });

    b.installArtifact(lib);
}
```

## Using Dependencies
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Fetch dependency
    const dep = b.dependency("some_package", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Import module from dependency
    exe.root_module.addImport("some_module", dep.module("some_module"));

    // Link library from dependency
    exe.linkLibrary(dep.artifact("some_lib"));

    b.installArtifact(exe);
}
```

## C/C++ Integration
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add C source files
    exe.addCSourceFiles(.{
        .files = &.{
            "src/c/helper.c",
            "src/c/utils.c",
        },
        .flags = &.{
            "-std=c99",
            "-O2",
            "-Wall",
            "-Wextra",
        },
    });

    // Add C++ source files
    exe.addCSourceFiles(.{
        .files = &.{"src/cpp/wrapper.cpp"},
        .flags = &.{
            "-std=c++17",
            "-O2",
        },
    });

    // Include paths
    exe.addIncludePath(b.path("include/"));
    exe.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });

    // Link system libraries
    exe.linkSystemLibrary("z");
    exe.linkSystemLibrary("pthread");
    exe.linkLibC();
    exe.linkLibCpp();

    b.installArtifact(exe);
}
```

## Multi-Target Cross-Compilation
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const targets = [_]std.Target.Query{
        .{}, // native
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
    };

    for (targets) |t| {
        const resolved = b.resolveTargetQuery(t);
        const exe = b.addExecutable(.{
            .name = b.fmt("myapp-{s}-{s}", .{
                @tagName(t.cpu_arch orelse .x86_64),
                @tagName(t.os_tag orelse .linux),
            }),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = resolved,
                .optimize = .ReleaseFast,
            }),
        });
        b.installArtifact(exe);
    }
}
```

## WebAssembly Build
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const wasm = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = optimize,
        }),
    });

    // Export functions for JavaScript
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    // Stack size for WASM
    wasm.stack_size = 14 * 1024 * 1024; // 14MB

    b.installArtifact(wasm);
}
```

## Embedded/Bare Metal Build
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "firmware",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .thumb,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
                .os_tag = .freestanding,
                .abi = .eabi,
            }),
            .optimize = optimize,
        }),
    });

    exe.setLinkerScript(b.path("linker.ld"));

    // Generate binary
    const bin = exe.addObjCopy(.{
        .format = .bin,
    });
    const install_bin = b.addInstallBinFile(bin.getOutput(), "firmware.bin");
    b.getInstallStep().dependOn(&install_bin.step);
}
```

## Custom Build Steps
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Code generation step
    const codegen = b.addSystemCommand(&.{ "python", "scripts/codegen.py" });
    const generated = codegen.addOutputFileArg("generated.zig");

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add generated file as anonymous import
    exe.root_module.addAnonymousImport("generated", .{
        .root_source_file = generated,
    });

    b.installArtifact(exe);

    // Custom clean step
    const clean = b.step("clean", "Clean build artifacts");
    clean.dependOn(&b.addRemoveDirTree(b.path("zig-out")).step);
    clean.dependOn(&b.addRemoveDirTree(b.path(".zig-cache")).step);
}
```

## Test with Coverage
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Enable code coverage
    tests.root_module.addRuntimeCoverage();

    const run_tests = b.addRunArtifact(tests);

    // Generate coverage report after tests
    const coverage = b.addSystemCommand(&.{
        "kcov",
        "--include-path=src",
        "coverage",
    });
    coverage.addArtifactArg(tests);
    coverage.step.dependOn(&run_tests.step);

    b.step("test", "Run tests").dependOn(&run_tests.step);
    b.step("coverage", "Run tests with coverage").dependOn(&coverage.step);
}
```

## build.zig.zon Template
```zig
.{
    .name = "my_project",
    .version = "0.1.0",
    .minimum_zig_version = "0.13.0",

    .dependencies = .{
        // Remote dependency with hash
        .zap = .{
            .url = "https://github.com/zigzap/zap/archive/refs/tags/v0.1.7.tar.gz",
            .hash = "1220002d24d73672fe8b1e39717c0671598acc8ec27b8af2e1caf623a4fd0ce0d1bd",
        },

        // Git dependency
        .ziglyph = .{
            .url = "git+https://github.com/kubkon/ziglyph.git#v0.4.0",
            .hash = "1220...",
        },

        // Local path dependency
        .local_lib = .{
            .path = "../lib",
        },
    },

    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "include",
        "LICENSE",
        "README.md",
    },
}
```
