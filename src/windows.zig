const std = @import("std");
const serial = @import("common.zig");

pub fn listPorts(
    _: std.Io,
    allocator: std.mem.Allocator,
) !std.ArrayList(serial.PortInfo) {
    const serialPorts = try std.ArrayList(serial.PortInfo).initCapacity(allocator, 2);
    return serialPorts;
}
