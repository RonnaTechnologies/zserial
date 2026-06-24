const std = @import("std");
const port = @import("common.zig");

// Windows utils
pub fn parseUsbHardwareInfo(allocator: std.mem.Allocator, info: []const u8, portInfo: *port.PortInfo) !void {
    const vidStr = "VID_";
    const vidOffset = (std.mem.indexOf(u8, info, vidStr) orelse return error.ParseError) + vidStr.len;

    const vid = std.fmt.parseInt(u16, info[vidOffset .. vidOffset + 4], 16) catch return error.ParseError;

    const pidStr = "PID_";
    const pidOffset = (std.mem.indexOf(u8, info, pidStr) orelse return error.ParseError) + pidStr.len;

    const pid = std.fmt.parseInt(u16, info[pidOffset .. pidOffset + 4], 16) catch return error.ParseError;

    const serialOffset = std.mem.lastIndexOfScalar(u8, info, '\\') orelse return error.ParseError;
    const serial = info[serialOffset + 1 ..];

    portInfo.vid = vid;
    portInfo.pid = pid;
    portInfo.serialNumber = try allocator.dupe(u8, serial);
}

pub fn parseDecimal(comptime s: []const u8) u32 {
    var result: u32 = 0;
    for (s) |c| {
        result = result * 10 + (c - '0');
    }
    return result;
}

test "windows parse USB info" {
    const str: []const u8 = " USB\\VID_0483&PID_5740\\1234";
    var pi: port.PortInfo = undefined;

    var dba = std.heap.DebugAllocator(.{}){};
    const allocator = dba.allocator();

    try parseUsbHardwareInfo(allocator, str, &pi);

    try std.testing.expect(pi.vid == 0x0483);
    try std.testing.expect(pi.pid == 0x5740);
    try std.testing.expect(std.mem.eql(u8, pi.serialNumber, "1234"));

    allocator.free(pi.serialNumber);
}
