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

        var port: serial.Port = .init(io);
        try port.open(portInfo);
        defer port.close();

        const options = serial.port.Options{ .parity = .even };
        try port.configure(options);
    }
}
