const std = @import("std");
pub const port = @import("common.zig");

const allowedDevices = [_][]const u8{ "ttyS", "ttyUSB", "ttyXRUSB", "ttyACM", "ttyAMA", "rfcomm", "ttyAP", "ttyGS" };
const rootPath: []const u8 = "/sys/class/tty";

const CBAUD: u32 = 0x100F;

pub const baudRates: []const u32 = b: {
    const fieldNames = std.meta.fieldNames(std.posix.speed_t);
    var rates: [fieldNames.len]u32 = undefined;
    for (fieldNames, 0..) |name, i| {
        const trimmed = std.mem.trimStart(u8, name, "B");
        rates[i] = parseDecimal(trimmed);
    }
    const computed = rates;
    break :b &computed;
};

pub fn isValidBaudRate(baudRate: u32) bool {
    return std.mem.indexOfScalar(u32, baudRates, baudRate) != null;
}

pub const Port = struct {
    file: ?std.Io.File = null,
    io: std.Io,
    epollHandle: ?i32 = null,

    pub fn init(io: std.Io) Port {
        return .{ .io = io };
    }

    pub fn open(
        self: *@This(),
        portInfo: port.PortInfo,
    ) !void {
        self.file = try std.Io.Dir.openFileAbsolute(self.io, portInfo.device, .{ .mode = .read_write });
    }

    pub fn close(self: *Port) void {
        if (self.file) |f| {
            f.close(self.io);
        }
        if (self.epollHandle) |epollFd| {
            _ = std.os.linux.close(@intCast(epollFd));
        }
    }

    pub fn configure(self: *@This(), options: port.Options) !void {
        var tty = try std.posix.tcgetattr(self.file.?.handle);

        const allocator = std.heap.smp_allocator;
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        const arenaAllocator = arena.allocator();

        var baudRatesMap = try enumToMap(arenaAllocator, u32, std.posix.speed_t, struct {
            fn call(name: []const u8) !u32 {
                const trimmed = std.mem.trimStart(u8, name, "B");
                return std.fmt.parseInt(u32, trimmed, 10);
            }
        }.call);

        var dataBitsMap = try enumToMap(arenaAllocator, u8, std.posix.CSIZE, struct {
            fn call(name: []const u8) !u8 {
                const trimmed = std.mem.trimStart(u8, name, "CS");
                return std.fmt.parseInt(u8, trimmed, 10);
            }
        }.call);

        const baudRate: @TypeOf(tty.ispeed) = @enumFromInt(baudRatesMap.get(options.baudRate).?);
        const dataBits: std.posix.CSIZE = @enumFromInt(dataBitsMap.get(@intFromEnum(options.dataBits)).?);

        const baudRateInt = @intFromEnum(baudRate);

        var cflag_int: u32 = @bitCast(tty.cflag);

        // ospeed
        cflag_int &= ~CBAUD;
        cflag_int |= baudRateInt;
        tty.cflag = @bitCast(cflag_int);

        // ispeed
        cflag_int &= ~(CBAUD << 16);
        cflag_int |= (baudRateInt << 16);
        tty.cflag = @bitCast(cflag_int);

        // parity
        tty.cflag.PARENB = options.parity != .none;
        tty.cflag.PARODD = options.parity == .odd;

        // stop bit
        tty.cflag.CSTOPB = options.stopBits != .one;

        // data bits
        tty.cflag.CSIZE = dataBits;

        // modem-specific signal lines
        tty.cflag.CREAD = true;
        tty.cflag.CLOCAL = true;

        // Raw mode (cfmakeraw)
        tty.iflag.IGNBRK = false;
        tty.iflag.BRKINT = false;
        tty.iflag.PARMRK = false;
        tty.iflag.ISTRIP = false;
        tty.iflag.INLCR = false;
        tty.iflag.IGNCR = false;
        tty.iflag.ICRNL = false;

        tty.iflag.IXON = false;
        tty.iflag.IXOFF = false;
        tty.iflag.IXANY = false;

        tty.oflag.OPOST = false;

        tty.lflag.ECHO = false;
        tty.lflag.ECHONL = false;
        tty.lflag.ICANON = false;
        tty.lflag.ISIG = false;
        tty.lflag.IEXTEN = false;

        // Hardware flow control
        tty.cflag.CRTSCTS = options.hardwareFlowControl;

        tty.cc[@intFromEnum(std.os.linux.V.MIN)] = 0;
        tty.cc[@intFromEnum(std.os.linux.V.TIME)] = 0;

        try std.posix.tcsetattr(self.file.?.handle, .NOW, tty);
        // try std.os.linux.fcntl(fd: i32, cmd: i32, arg: usize)
    }

    pub fn write(self: *@This(), data: []const u8) !void {
        try self.file.?.writeStreamingAll(self.io, data);
    }

    pub fn read(self: *@This(), allocator: std.mem.Allocator, strategy: port.ReadStrategy) ![]u8 {
        const fd = self.file.?.handle;
        var buffer: [4096]u8 = undefined;
        var bytesRead: usize = 0;

        switch (strategy) {
            .nonBlocking => {
                const n = try std.posix.read(fd, buffer[bytesRead..]);
                if (n < 0) {
                    const err = std.posix.errno(n);
                    if (err == .AGAIN or err == .WOULDBLOCK) {
                        return allocator.dupe(u8, "");
                    } else {
                        return std.posix.unexpectedErrno(err);
                    }
                }

                bytesRead = n;
            },
            .blockingAnyTimeout => |s| {
                if (try self.poll(s.timeout_ms)) {
                    const n = try std.posix.read(fd, buffer[bytesRead..]);
                    if (n < 0) return std.posix.unexpectedErrno(std.posix.errno(n));
                    bytesRead = n;
                } else {
                    return error.Timeout;
                }
            },
            .blockingMinTimeout => |s| {
                const startTime = std.Io.Timestamp.now(self.io, .awake);

                while (bytesRead < s.nBytes) {
                    if (s.timeout_ms != null) {
                        const endTime = std.Io.Timestamp.addDuration(startTime, std.Io.Duration.fromMilliseconds(s.timeout_ms.?));

                        const remainingTime = endTime.nanoseconds - std.Io.Timestamp.now(self.io, .awake).nanoseconds;

                        if (remainingTime <= 0) {
                            return error.Timeout;
                        }
                    }

                    if (self.poll(s.timeout_ms)) |_| {
                        const n = try std.posix.read(fd, buffer[bytesRead..]);
                        if (n < 0) {
                            return std.posix.unexpectedErrno(std.posix.errno(n));
                        }
                        bytesRead += n;
                    } else |err| return err;

                    if (bytesRead < s.nBytes) {
                        if (bytesRead == 0) {
                            return error.Timeout;
                        }
                    }
                }
            },
        }

        return allocator.dupe(u8, buffer[0..bytesRead]);
    }

    fn poll(self: *@This(), timeout_ms: ?u32) !bool {
        var events: [1]std.os.linux.epoll_event = undefined;

        if (self.epollHandle == null) {
            const epfd = std.os.linux.epoll_create1(0);
            if (std.os.linux.errno(epfd) != .SUCCESS) {
                return error.EpollCreate;
            }

            self.epollHandle = @intCast(epfd);

            var ev: std.os.linux.epoll_event = .{
                .events = std.os.linux.EPOLL.IN,
                .data = .{ .fd = self.file.?.handle },
            };

            const ctl_rc = std.os.linux.epoll_ctl(
                self.epollHandle.?,
                std.os.linux.EPOLL.CTL_ADD,
                self.file.?.handle,
                &ev,
            );

            if (std.os.linux.errno(ctl_rc) != .SUCCESS) {
                return error.EpollCtl;
            }
        }

        const timeout: i32 = if (timeout_ms) |t| @intCast(t) else -1;

        const n = std.os.linux.epoll_wait(
            self.epollHandle.?,
            &events,
            1,
            timeout,
        );

        if (n == 0) {
            return false;
        }

        if (n < 0) {
            return error.EpollWait;
        }

        const ev = events[0].events;

        if ((ev & std.os.linux.EPOLL.IN) != 0) {
            return true;
        }

        if ((ev & std.os.linux.EPOLL.ERR) != 0 or
            (ev & std.os.linux.EPOLL.HUP) != 0)
        {
            return error.EpollWait;
        }

        return false;
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

fn parseDecimal(comptime s: []const u8) u32 {
    var result: u32 = 0;
    for (s) |c| {
        result = result * 10 + (c - '0');
    }
    return result;
}

fn enumToMap(allocator: std.mem.Allocator, comptime keyType: type, comptime enumType: type, comptime enumToKey: fn ([]const u8) anyerror!keyType) !std.hash_map.AutoHashMap(keyType, std.meta.Tag(enumType)) {
    var values = std.hash_map.AutoHashMap(keyType, std.meta.Tag(enumType)).init(allocator);
    errdefer values.deinit();

    inline for (std.meta.fields(enumType)) |field| {
        const key = try enumToKey(field.name);
        try values.put(key, field.value);
    }
    return values;
}

test "valid port name" {
    const isValid = isValidPort(u8, "ttyACM0", &allowedDevices);
    try std.testing.expect(isValid);
}

test "invalid port name" {
    const isValid = isValidPort(u8, "ttyABC", &allowedDevices);
    try std.testing.expect(!isValid);
}
