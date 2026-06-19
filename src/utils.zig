const std = @import("std");
const port = @import("common.zig");

// Windows utils
pub fn parseUsbHardwareInfo(info: []const u8, portInfo: *port.PortInfo) !void {
    const vidStr = "VID_";
    const vidOffset = (std.mem.indexOf(u8, info, vidStr) orelse return error.ParseError) + vidStr.len;

    const vid = std.fmt.parseInt(u16, info[vidOffset .. vidOffset + 4], 16) catch return error.ParseError;

    const pidStr = "PID_";
    const pidOffset = (std.mem.indexOf(u8, info, pidStr) orelse return error.ParseError) + pidStr.len;

    const pid = std.fmt.parseInt(u16, info[pidOffset .. pidOffset + 4], 16) catch return error.ParseErrro;

    portInfo.vid = vid;
    portInfo.pid = pid;
}
