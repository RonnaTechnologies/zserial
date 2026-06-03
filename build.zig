const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const osxcross_sdk = b.option(
        []const u8,
        "osxcross-sdk",
        "Path to osxcross SDK (e.g. /path/to/osxcross/target/SDK/MacOSX13.3.sdk)",
    );

    const exe = b.addExecutable(.{
        .name = "zserial",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });


    switch (target.query.os_tag orelse @import("builtin").os.tag) {
        .macos => {
            const sdk_path = osxcross_sdk orelse
                @panic("Pass -Dosxcross-sdk=/path/to/osxcross/target/SDK/MacOSX13.3.sdk");

            const sdk: std.Build.LazyPath = .{ .cwd_relative = sdk_path };

            exe.root_module.addSystemIncludePath(sdk.path(b, "usr/include"));
            exe.root_module.addSystemFrameworkPath(sdk.path(b, "System/Library/Frameworks"));
            exe.root_module.addLibraryPath(sdk.path(b, "usr/lib"));
            exe.root_module.linkSystemLibrary("objc", .{});
        },
        else => {},
    }

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Run the app").dependOn(&run.step);

    const emit_docs = b.addSystemCommand(&.{
        "zig",
        "build-obj",
        "-femit-docs=zig-out/docs",
        "-fno-emit-bin",
        "src/main.zig",
    });

    const docs_step = b.step("docs", "Generate docs");
    docs_step.dependOn(&emit_docs.step);
}
