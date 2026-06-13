const std = @import("std");
const serial = @import("zserial").serial;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    const serialPorts = try serial.listPorts(io, arenaAllocator);

    // Valid baud rates are comptime
    const baudRates = comptime serial.baudRates;
    _ = baudRates;

    const baudRate: u32 = 115_200;

    if (!serial.isValidBaudRate(baudRate)) {
        return error.invalidBaudRate;
    }

    std.log.info("Serial ports found:", .{});

    for (serialPorts.items) |portInfo| {
        std.log.info("{s}\n", .{portInfo.device});

        var port: serial.Port = .init(io);
        try port.open(portInfo);
        defer port.close();

        const options = serial.port.Options{ .baudRate = baudRate, .dataBits = .eight, .parity = .none, .stopBits = .one, .hardwareFlowControl = false };
        try port.configure(options);

        try port.write("test");

        // const readStrategy: serial.port.ReadStrategy = .{ .blockingMinTimeout = .{ .nBytes = 16, .timeout_ms = 1000 } };
        const readStrategy: serial.port.ReadStrategy = .nonBlocking;

        // try std.Io.sleep(io, .fromMilliseconds(1), .awake);

        if (port.read(arenaAllocator, readStrategy)) |data| {
            if (data.len > 0) {
                std.log.info("Received: {s} \n[{d}]", .{ data, data.len });
            }
        } else |err| {
            std.log.info("Error reading from serial device: {s}", .{@errorName(err)});
        }
    }
}
