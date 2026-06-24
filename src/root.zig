const std = @import("std");
const builtin = @import("builtin");
const interface = @import("interface.zig");

pub const serial = switch (builtin.os.tag) {
    .macos => @import("macos.zig"),
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    else => @compileError("unsupported OS: " ++ @tagName(builtin.os.tag)),
};

comptime {
    interface.validate(serial);
}

test {
    std.testing.refAllDecls(serial);
}
