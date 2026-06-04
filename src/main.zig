const std = @import("std");

const linuxSerialRoot: []const u8 = "/sys/class/tty";
const linuxAllowedDevices = [_][]const u8{ "ttyS", "ttyUSB", "ttyXRUSB", "ttyACM", "ttyAMA", "rfcomm", "ttyAP", "ttyGS" };

fn fileExists(io: std.Io, path: []const u8) bool {
    return !std.meta.isError(std.Io.Dir.cwd().access(io, path, .{}));
}

// fn FilterIterator(comptime T: type) type {
//     return struct {
//         items: []const T,
//         index: usize = 0,
//         predicate: *const fn (T) bool,

//         pub fn next(self: *@This()) ?T {
//             while (self.index < self.items.len) {
//                 const item = self.items[self.index];
//                 self.index += 1;
//                 if (self.predicate(item)) return item;
//             }
//             return null;
//         }
//     };
// }

fn linuxIsValidPort(comptime T: type, needle: []const T, haystack: anytype) bool {
    const Haystack = @TypeOf(haystack);
    switch (@typeInfo(Haystack)) {
        .pointer => {
            for (haystack) |value| {
                if (std.mem.startsWith(T, needle, value)) {
                    return true;
                }
            }
            return false;
        },
        else => {
            @compileError("Invalid container type.");
        },
    }
}

fn listSerialPorts(
    io: std.Io,
    allocator: std.mem.Allocator,
    comptime path: []const u8,
) !std.ArrayList([]u8) {
    var ports: std.ArrayList([]u8) = .empty;

    const dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    var dirIterator = dir.iterate();

    while (try dirIterator.next(io)) |dirContent| {
        const name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, dirContent.name });
        if (linuxIsValidPort(u8, dirContent.name, &linuxAllowedDevices)) {
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

    for (ports.items) |port| {
        const devicePath = try std.fmt.allocPrint(arenaAllocator, "{s}/device", .{port});

        const realPath = try std.Io.Dir.cwd().realPathFileAlloc(io, devicePath, arenaAllocator);
        const parentPath = std.fs.path.dirname(realPath) orelse "/";

        const vendorPath = try std.fmt.allocPrint(arenaAllocator, "{s}/idVendor", .{parentPath});
        const hasVendor = fileExists(io, vendorPath);

        // std.debug.print("path = {s}, has vendor: {}\n", .{ parentPath, hasVendor });

        if (hasVendor) {
            var buf: [16]u8 = undefined;

            const file = try std.Io.Dir.cwd().openFile(io, vendorPath, .{});
            defer file.close(io);

            var reader = file.reader(io, &buf);

            const n = try reader.interface.readSliceShort(&buf);

            const vendorStr = std.mem.trim(u8, buf[0..n], " \t\r\n");
            // std.log.info("vendor id = \"{s}\"", .{vendorStr});
            const vendor_id = try std.fmt.parseInt(u32, vendorStr, 16);

            std.log.info("path = {s}, vendor_id = 0x{x}", .{ parentPath, vendor_id });
        }
    }

    // for (ports.items) |name| {
    // std.debug.print("{s}\n", .{name});
    // }
}
