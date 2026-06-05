const std = @import("std");
const serial = @import("common.zig");

pub const rootPath: []const u8 = "/sys/class/tty";

const allowedDevices = [_][]const u8{ "ttyS", "ttyUSB", "ttyXRUSB", "ttyACM", "ttyAMA", "rfcomm", "ttyAP", "ttyGS" };

pub fn listPorts(io: std.Io, allocator: std.mem.Allocator) !std.ArrayList(serial.PortInfo) {
    const ports = try listSerialPorts(io, allocator, rootPath);

    var serialPorts = try std.ArrayList(serial.PortInfo).initCapacity(allocator, 2);

    for (ports.items) |port| {
        const devicePath = try std.fmt.allocPrint(allocator, "{s}/{s}/device", .{ rootPath, port });

        const realPath = try std.Io.Dir.cwd().realPathFileAlloc(io, devicePath, allocator);
        const parentPath = std.fs.path.dirname(realPath) orelse "/";

        const vendorPath = try std.fmt.allocPrint(allocator, "{s}/idVendor", .{parentPath});
        const productPath = try std.fmt.allocPrint(allocator, "{s}/idProduct", .{parentPath});
        const hasVendor = fileExists(io, vendorPath);
        const hasProduct = fileExists(io, productPath);

        // std.debug.print("path = {s}, has vendor: {}\n", .{ parentPath, hasVendor });

        if (hasVendor and hasProduct) {
            var buf: [16]u8 = undefined;

            const vendorStr = try readFile(io, vendorPath, &buf);
            const vendorId = try std.fmt.parseInt(u16, vendorStr, 16);

            const productStr = try readFile(io, productPath, &buf);
            const productId = try std.fmt.parseInt(u16, productStr, 16);
            const portInfo = serial.PortInfo{ .location = parentPath, .device = port, .pid = productId, .vid = vendorId, .manufacturer = "", .product = "", .serialNumber = "" };

            try serialPorts.append(allocator, portInfo);

            std.log.info("port = /dev/{s}, path = {s}, vendor Id = 0x{x}, product Id = 0x{x}", .{ port, parentPath, vendorId, productId });
        }
    }

    return serialPorts;
}

fn fileExists(io: std.Io, path: []const u8) bool {
    return !std.meta.isError(std.Io.Dir.cwd().access(io, path, .{}));
}

fn isValidPort(comptime T: type, needle: []const T, haystack: anytype) bool {
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
        const name = try std.fmt.allocPrint(allocator, "{s}", .{dirContent.name});
        if (isValidPort(u8, dirContent.name, &allowedDevices)) {
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

test "valid port name" {
    const isValid = isValidPort(u8, "ttyACM0", &allowedDevices);
    try std.testing.expect(isValid);
}

test "invalid port name" {
    const isValid = isValidPort(u8, "ttyABC", &allowedDevices);
    try std.testing.expect(!isValid);
}
