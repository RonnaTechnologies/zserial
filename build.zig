const std = @import("std");
const builtin = @import("builtin");
const pkg = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // options
    const options = b.addOptions();
    options.addOption([]const u8, "version", pkg.version);
    options.addOption([]const u8, "name", @tagName(pkg.name));
    options.addOption(bool, "docs", false);

    // parse version
    var it = std.mem.splitScalar(u8, pkg.version, '.');
    const major = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidVersion, 10);
    const minor = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidVersion, 10);
    const patch = try std.fmt.parseInt(u32, it.next() orelse return error.InvalidVersion, 10);

    const osxcross_sdk = b.option([]const u8, "osxcross-sdk", "path to macOS SDK");

    // zig library
    const zserialLib = b.addModule("zserial", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zserialLib.addOptions("buildOptions", options);
    addPlatformImports(b, zserialLib, target, optimize, osxcross_sdk);

    // executable (example program -- linux only)
    const exe = b.addExecutable(.{
        .name = "zserial",
        .use_lld = if (getOS(target) == .linux) true else null,
        .use_llvm = if (getOS(target) == .linux) true else null,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addOptions("buildOptions", options);
    exe.root_module.addImport("zserial", zserialLib);
    b.installArtifact(exe);

    const runCmd = b.addRunArtifact(exe);
    runCmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| runCmd.addArgs(args);
    b.step("run", "Run the example").dependOn(&runCmd.step);

    // C shared library
    const clib = b.addLibrary(.{
        .name = "zserial",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .version = .{ .major = major, .minor = minor, .patch = patch },
    });
    clib.root_module.addOptions("buildOptions", options);
    addPlatformImports(b, clib.root_module, target, optimize, osxcross_sdk);

    b.installArtifact(clib);
    b.installFile("src/zserial.h", "include/zserial.h");

    b.step("clib", "Build the C shared library").dependOn(&clib.step);

    // tests
    const tests = b.addTest(.{
        .name = "zserial_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    tests.root_module.addOptions("buildOptions", options);
    addPlatformImports(b, tests.root_module, b.graph.host, optimize, null);

    const runTests = b.addRunArtifact(tests);
    b.step("test", "Run library tests").dependOn(&runTests.step);
    b.installArtifact(tests);

    // docs
    const docsOptions = b.addOptions();
    docsOptions.addOption([]const u8, "version", pkg.version);
    docsOptions.addOption([]const u8, "name", @tagName(pkg.name));
    docsOptions.addOption(bool, "docs", true);

    const docsFiles = b.addWriteFiles();
    const docsRoot = docsFiles.addCopyFile(b.path("src/docs.zig"), "root.zig");
    _ = docsFiles.addCopyFile(b.path("src/linux.zig"), "linux.zig");
    _ = docsFiles.addCopyFile(b.path("src/macos.zig"), "macos.zig");
    _ = docsFiles.addCopyFile(b.path("src/windows.zig"), "windows.zig");
    _ = docsFiles.addCopyFile(b.path("src/common.zig"), "common.zig"); // if exists

    const docsObj = b.addObject(.{
        .name = "zserial",
        .root_module = b.createModule(.{
            .root_source_file = docsRoot, // ← LazyPath returned by addCopyFile
            .target = b.graph.host,
            .optimize = .Debug,
            .link_libc = true,
        }),
    });
    docsObj.root_module.addOptions("buildOptions", docsOptions);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docsObj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("docs", "Generate docs").dependOn(&install_docs.step);
}

fn getOS(target: anytype) std.Target.Os.Tag {
    const effectiveOS = blk: {
        const tag = if (@TypeOf(target) == std.Build.ResolvedTarget)
            target.query.os_tag
        else
            target.query.os_tag;
        break :blk tag orelse builtin.os.tag;
    };

    return effectiveOS;
}

fn addPlatformImports(
    b: *std.Build,
    mod: *std.Build.Module,
    target: anytype,
    optimize: std.builtin.OptimizeMode,
    osxcross_sdk: ?[]const u8,
) void {
    const effectiveOS = getOS(target);

    switch (effectiveOS) {
        .macos => {
            const sdkPath = osxcross_sdk orelse @panic("missing -Dosxcross-sdk");
            if (b.sysroot == null) b.sysroot = sdkPath;
            const sdk = std.Build.LazyPath{ .cwd_relative = sdkPath };
            const translateC = b.addTranslateC(.{
                .root_source_file = b.path("src/macos.h"),
                .target = if (@TypeOf(target) == std.Build.ResolvedTarget) target else b.graph.host,
                .optimize = optimize,
                .link_libc = true,
            });
            translateC.addIncludePath(sdk.path(b, "usr/include"));
            translateC.addSystemFrameworkPath(sdk.path(b, "System/Library/Frameworks"));
            mod.addImport("c", translateC.createModule());
            mod.addSystemFrameworkPath(sdk.path(b, "System/Library/Frameworks"));
            mod.linkFramework("IOKit", .{});
            mod.linkFramework("CoreFoundation", .{});
        },
        .windows => {
            const translateC = b.addTranslateC(.{
                .root_source_file = b.path("src/windows.h"),
                .target = if (@TypeOf(target) == std.Build.ResolvedTarget) target else b.graph.host,
                .optimize = optimize,
                .link_libc = true,
            });
            mod.addImport("c", translateC.createModule());
            mod.linkSystemLibrary("setupapi", .{});
            mod.linkSystemLibrary("cfgmgr32", .{});
            mod.linkSystemLibrary("advapi32", .{});
        },
        else => {},
    }
}
