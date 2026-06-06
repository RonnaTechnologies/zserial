const std = @import("std");
const builtin = @import("builtin");
const options = @import("buildOptions");

const serial = switch (builtin.os.tag) {
    .macos => @import("macos.zig"),
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    else => @compileError("unsupported OS: " ++ @tagName(builtin.os.tag)),
};

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

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // std.log.info("Name: {s}, version: {s}", .{ options.name, options.version });

    // std.log.info("ret = {d}", .{ret});

    // _ = try std.ArrayList(SerialPortInfo).initCapacity(init.arena.allocator(), 2);

    // Linux below

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    const serialPorts = try serial.listPorts(io, arenaAllocator);

    std.log.info("Serial ports found: ", .{});
    for (serialPorts.items) |portInfo| {
        std.log.info("{s}\n", .{portInfo.device});
    }
}
