const std = @import("std");
const serial = @import("zserial").serial;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    const serialPorts = try serial.listPorts(io, arenaAllocator);

    std.log.info("Serial ports found:", .{});
    for (serialPorts.items) |portInfo| {
        std.log.info("{s}\n", .{portInfo.device});
    }
}
