const std = @import("std");

const linuxSerialRoot: []const u8 = "/sys/class/tty";
const linuxAllowedDevices = [_][]const u8{ "ttyS", "ttyUSB", "ttyXRUSB", "ttyACM", "ttyAMA", "rfcomm", "ttyAP", "ttyGS" };

fn arrayContains(comptime T: type, needle: []const T, haystack: anytype) bool {
    for (haystack) |value| {
        if (std.mem.startsWith(T, needle, value)) return true;
    }
    return false;
}

pub fn listSerialPorts(
    io: std.Io,
    allocator: std.mem.Allocator,
    comptime path: []const u8,
) !std.ArrayList([]u8) {
    var ports: std.ArrayList([]u8) = .empty;

    const dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    var dirIterator = dir.iterate();

    while (try dirIterator.next(io)) |dirContent| {
        const name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, dirContent.name });
        if (arrayContains(u8, dirContent.name, &linuxAllowedDevices)) {
            try ports.append(allocator, name);
        }
    }

    return ports;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    const ports = try listSerialPorts(io, arenaAllocator, linuxSerialRoot);

    for (ports.items) |name| {
        std.debug.print("{s}\n", .{name});
    }
}
