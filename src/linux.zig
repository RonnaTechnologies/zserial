const std = @import("std");
pub const port = @import("common.zig");

const allowedDevices = [_][]const u8{ "ttyS", "ttyUSB", "ttyXRUSB", "ttyACM", "ttyAMA", "rfcomm", "ttyAP", "ttyGS" };
const rootPath: []const u8 = "/sys/class/tty";

pub const Port = struct {
    file: ?std.Io.File = null,
    io: std.Io,

    pub fn init(io: std.Io) Port {
        return .{ .io = io };
    }

    pub fn open(
        self: *Port,
        portInfo: port.PortInfo,
    ) !void {
        self.file = try std.Io.Dir.openFileAbsolute(self.io, portInfo.device, .{ .mode = .read_write });
    }

    pub fn close(self: *Port) void {
        if (self.file) |f| {
            f.close(self.io);
        }
    }

    pub fn configure(self: *Port, _: port.Options) !void {
        var tty = try std.posix.tcgetattr(self.file.?.handle);

        const baudMask = std.posix.speed_t.B115200;

        tty.cflag = @bitCast(@intFromEnum(baudMask));

        tty.ispeed = baudMask;
        tty.ospeed = baudMask;

        tty.cflag.PARENB = false;
        tty.cflag.CSTOPB = false;
        tty.cflag.CSIZE = .CS8;
        tty.cflag.CRTSCTS = false;
        tty.cflag.CREAD = true;
        tty.cflag.CLOCAL = true;

        tty.cc[@intFromEnum(std.os.linux.V.MIN)] = 0;
        tty.cc[@intFromEnum(std.os.linux.V.TIME)] = 1;

        try std.posix.tcsetattr(self.file.?.handle, .NOW, tty);

        try self.file.?.writeStreamingAll(self.io, "hello");

        var buf: [256]u8 = undefined;
        var reader = self.file.?.reader(self.io, &buf);
        const n = try reader.interface.readSliceShort(&buf);
        std.log.info("Received data: \"{s}\"", .{buf[0..n]});
    }
};

pub fn listPorts(io: std.Io, allocator: std.mem.Allocator) !std.ArrayList(port.PortInfo) {
    const ports = try listSerialPorts(io, allocator, rootPath);

    var serialPorts = try std.ArrayList(port.PortInfo).initCapacity(allocator, 2);

    for (ports.items) |p| {
        const devicePath = try std.fmt.allocPrint(allocator, "{s}/{s}/device", .{ rootPath, p });

        const realPath = try std.Io.Dir.cwd().realPathFileAlloc(io, devicePath, allocator);
        const parentPath = std.fs.path.dirname(realPath) orelse "/";

        const vendorIdPath = try std.fmt.allocPrint(allocator, "{s}/idVendor", .{parentPath});
        const productIdPath = try std.fmt.allocPrint(allocator, "{s}/idProduct", .{parentPath});
        const hasVendor = fileExists(io, vendorIdPath);
        const hasProduct = fileExists(io, productIdPath);

        // std.debug.print("path = {s}, has vendor: {}\n", .{ parentPath, hasVendor });

        if (hasVendor and hasProduct) {
            const vendorStr = try readFile(io, allocator, vendorIdPath, 16);
            const vendorId = try std.fmt.parseInt(u16, vendorStr, 16);

            const productStr = try readFile(io, allocator, productIdPath, 16);
            const productId = try std.fmt.parseInt(u16, productStr, 16);

            const device = try std.fmt.allocPrint(allocator, "/dev/{s}", .{p});

            const manufacturerPath = try std.fmt.allocPrint(allocator, "{s}/manufacturer", .{parentPath});
            const manufacturer = if (fileExists(io, manufacturerPath)) readFile(io, allocator, manufacturerPath, 32) catch "" else "";

            const productPath = try std.fmt.allocPrint(allocator, "{s}/product", .{parentPath});
            const product = if (fileExists(io, productPath)) readFile(io, allocator, productPath, 32) catch "" else "";

            const serialPath = try std.fmt.allocPrint(allocator, "{s}/serial", .{parentPath});
            const serialNb = if (fileExists(io, serialPath)) readFile(io, allocator, serialPath, 32) catch "" else "";

            const portInfo = port.PortInfo{ .location = parentPath, .device = device, .pid = productId, .vid = vendorId, .manufacturer = manufacturer, .product = product, .serialNumber = serialNb };

            try serialPorts.append(allocator, portInfo);

            std.log.debug(
                \\found device: 
                \\       device = {s}
                \\       product = "{s}""
                \\       manufacturer = "{s}"
                \\       serial = "{s}"
                \\       vendor Id = 0x{x} 
                \\       product Id = 0x{x}
                \\       location = {s}
            , portInfo);
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

fn readFile(io: std.Io, allocator: std.mem.Allocator, path: []u8, comptime maxLen: usize) ![]u8 {
    var buffer: [maxLen]u8 = undefined;

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var reader = file.reader(io, &buffer);
    const n = try reader.interface.readSliceShort(&buffer);

    const trimmed = std.mem.trim(u8, buffer[0..n], " \t\r\n");

    return allocator.dupe(u8, trimmed);
}

test "valid port name" {
    const isValid = isValidPort(u8, "ttyACM0", &allowedDevices);
    try std.testing.expect(isValid);
}

test "invalid port name" {
    const isValid = isValidPort(u8, "ttyABC", &allowedDevices);
    try std.testing.expect(!isValid);
}
