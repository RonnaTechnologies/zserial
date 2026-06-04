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

// fn longerThan3(s: []const u8) bool { return s.len > 3; }
// var it = FilterIterator([]const u8){
//     .items = list.items,
//     .predicate = longerThan3,
// };
// while (it.next()) |s| {
//     std.debug.print("{s}\n", .{s});
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

fn readFile(io: std.Io, path: []u8, buffer: []u8) ![]const u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var reader = file.reader(io, buffer);

    const n = try reader.interface.readSliceShort(buffer);

    const vendorStr = std.mem.trim(u8, buffer[0..n], " \t\r\n");

    return vendorStr;
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
        const productPath = try std.fmt.allocPrint(arenaAllocator, "{s}/idProduct", .{parentPath});
        const hasVendor = fileExists(io, vendorPath);
        const hasProduct = fileExists(io, productPath);

        // std.debug.print("path = {s}, has vendor: {}\n", .{ parentPath, hasVendor });

        if (hasVendor and hasProduct) {
            var buf: [16]u8 = undefined;

            const vendorStr = try readFile(io, vendorPath, &buf);
            const vendorId = try std.fmt.parseInt(u32, vendorStr, 16);

            const productStr = try readFile(io, productPath, &buf);
            const productId = try std.fmt.parseInt(u32, productStr, 16);

            std.log.info("path = {s}, vendor Id = 0x{x}, product Id = 0x{x}", .{ parentPath, vendorId, productId });
        }
    }

    // for (ports.items) |name| {
    // std.debug.print("{s}\n", .{name});
    // }
}
