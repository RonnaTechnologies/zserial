const std = @import("std");
const builtin = @import("builtin");

pub const serial = switch (builtin.os.tag) {
    .macos => @import("macos.zig"),
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    else => @compileError("unsupported OS: " ++ @tagName(builtin.os.tag)),
};

test {
    std.testing.refAllDecls(serial);
}
