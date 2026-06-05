const std = @import("std");
const pkg = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", pkg.version);
    options.addOption([]const u8, "name", @tagName(pkg.name));

    const osxcross_sdk = b.option(
        []const u8,
        "osxcross-sdk",
        "path to macOS SDK",
    );

    const exe = b.addExecutable(.{
        .name = "zserial",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const effective_os = target.query.os_tag orelse .linux;

    switch (effective_os) {
        .macos => {
            var sdk_path: ?[]const u8 = null;
            sdk_path = osxcross_sdk orelse
                @panic("missing -Dosxcross-sdk");

            if (b.sysroot == null)
                b.sysroot = sdk_path;
            const sdk = std.Build.LazyPath{
                .cwd_relative = sdk_path.?,
            };

            const translate_c = b.addTranslateC(.{
                .root_source_file = b.path("src/macos.h"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            translate_c.addIncludePath(sdk.path(b, "usr/include"));
            translate_c.addSystemFrameworkPath(
                sdk.path(b, "System/Library/Frameworks"),
            );
            const c_module = translate_c.createModule();
            exe.root_module.addImport("c", c_module);

            exe.root_module.addSystemFrameworkPath(
                sdk.path(b, "System/Library/Frameworks"),
            );

            exe.root_module.linkFramework("IOKit", .{});
            exe.root_module.linkFramework("CoreFoundation", .{});
        },
        .windows => {
            const translate_c = b.addTranslateC(.{
                .root_source_file = b.path("src/windows.h"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            const c_module = translate_c.createModule();
            exe.root_module.addImport("c", c_module);

            exe.root_module.linkSystemLibrary("setupapi", .{});
            exe.root_module.linkSystemLibrary("cfgmgr32", .{});
            exe.root_module.linkSystemLibrary("advapi32", .{});
        },
        else => {
            const run_cmd = b.addRunArtifact(exe);

            run_cmd.step.dependOn(b.getInstallStep());

            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            b.step("run", "Run the app").dependOn(&run_cmd.step);
        },
    }

    exe.root_module.addOptions("buildOptions", options);

    b.installArtifact(exe);

    // docs
    const emit_docs = b.addSystemCommand(&.{
        "zig",
        "build-obj",
        "-femit-docs=zig-out/docs",
        "-fno-emit-bin",
        "src/main.zig",
    });

    b.step("docs", "Generate docs").dependOn(&emit_docs.step);
}
