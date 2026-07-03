const std = @import("std");
const utils = @import("utils.zig");
const c = @import("c");
const windows = std.os.windows;

pub const port = @import("common.zig");

pub const baudRates: []const u32 = &.{
    110,
    300,
    600,
    1200,
    2400,
    4800,
    9600,
    14400,
    19200,
    38400,
    57600,
    115200,
    128000,
    256000,
};

pub fn isValidBaudRate(baudRate: u32) bool {
    return std.mem.indexOfScalar(u32, baudRates, baudRate) != null;
}

pub const Port = struct {
    handle: ?windows.HANDLE = null,
    iocpHandle: ?windows.HANDLE = null,
    writeEvent: ?c.HANDLE = null,
    readEvent: ?c.HANDLE = null,
    commEvent: ?c.HANDLE = null,
    io: std.Io,

    pub fn init(io: std.Io) Port {
        return .{ .io = io };
    }

    pub fn open(
        self: *@This(),
        portInfo: port.PortInfo,
    ) !void {
        var wideBuf: [260]u16 = undefined;
        const wideLen = try std.unicode.utf8ToUtf16Le(&wideBuf, portInfo.device);
        if (wideLen >= wideBuf.len) return error.PathTooLong;
        wideBuf[wideLen] = 0;
        const widePath: [*:0]const u16 = @ptrCast(&wideBuf);

        self.handle = c.CreateFileW(
            widePath,
            GENERIC_READ | GENERIC_WRITE,
            0,
            null,
            OPEN_EXISTING,
            FILE_FLAG_OVERLAPPED,
            null,
        );
        if (self.handle == windows.INVALID_HANDLE_VALUE) {
            const err: windows.Win32Error = @enumFromInt(c.GetLastError());
            return windows.unexpectedError(err);
        }

        self.writeEvent = c.CreateEventW(null, c.TRUE, c.FALSE, null) orelse {
            _ = c.CloseHandle(self.handle.?);
            self.handle = null;
            return windows.unexpectedError(@enumFromInt(c.GetLastError()));
        };

        self.readEvent = c.CreateEventW(null, c.TRUE, c.FALSE, null) orelse {
            return windows.unexpectedError(@enumFromInt(c.GetLastError()));
        };

        self.commEvent = c.CreateEventW(null, c.TRUE, c.FALSE, null) orelse {
            return windows.unexpectedError(@enumFromInt(c.GetLastError()));
        };

        if (c.SetCommMask(self.handle.?, EV_RXCHAR) == c.FALSE) {
            return windows.unexpectedError(@enumFromInt(c.GetLastError()));
        }
    }

    pub fn close(self: *@This()) void {
        if (self.writeEvent) |h| {
            _ = c.CloseHandle(h);
            self.writeEvent = null;
        }
        if (self.iocpHandle) |h| {
            _ = c.CloseHandle(h);
            self.iocpHandle = null;
        }
        if (self.handle) |h| {
            _ = c.CloseHandle(h);
            self.handle = null;
        }
    }

    pub fn configure(self: *@This(), options: port.Options) !void {
        if (self.handle == null) {
            return error.PortNotOpen;
        }

        var dcb = std.mem.zeroes(c.DCB);
        dcb.DCBlength = @sizeOf(c.DCB);

        if (c.GetCommState(self.handle.?, &dcb) == c.FALSE) {
            return windows.unexpectedError(@enumFromInt(c.GetLastError()));
        }

        dcb.BaudRate = options.baudRate;

        dcb.ByteSize = @intFromEnum(options.dataBits);

        dcb.StopBits = switch (options.stopBits) {
            .one => ONESTOPBIT,
            .two => TWOSTOPBITS,
        };

        dcb.Parity = switch (options.parity) {
            .none => NOPARITY,
            .odd => ODDPARITY,
            .even => EVENPARITY,
        };

        dcb.flags |= DCB_FBINARY;

        if (options.parity != .none) {
            dcb.flags |= DCB_FPARITY;
        } else {
            dcb.flags &= ~@as(c.DWORD, DCB_FPARITY);
        }

        // hardware control flow
        dcb.flags &= ~@as(c.DWORD, DCB_FOUTXCTSFLOW | DCB_FRTSCONTROL_MASK);
        if (options.hardwareFlowControl) {
            dcb.flags |= DCB_FOUTXCTSFLOW;
            dcb.flags |= DCB_FRTSCONTROL_HANDSHAKE;
        } else {
            dcb.flags |= DCB_FRTSCONTROL_ENABLE;
        }

        dcb.flags &= ~@as(c.DWORD, DCB_FOUTX | DCB_FINX);

        const DCB_FDTRCONTROL_MASK: c.DWORD = 3 << 4;
        const DCB_FDTRCONTROL_ENABLE: c.DWORD = 1 << 4;

        dcb.flags &= ~DCB_FDTRCONTROL_MASK;
        dcb.flags |= DCB_FDTRCONTROL_ENABLE;

        if (c.SetCommState(self.handle.?, &dcb) == c.FALSE) {
            return windows.unexpectedError(@enumFromInt(c.GetLastError()));
        }

        var timeouts = std.mem.zeroes(c.COMMTIMEOUTS);
        timeouts.ReadIntervalTimeout = MAXDWORD;
        timeouts.ReadTotalTimeoutMultiplier = 0;
        timeouts.ReadTotalTimeoutConstant = 0;
        timeouts.WriteTotalTimeoutMultiplier = 0;
        timeouts.WriteTotalTimeoutConstant = 0;

        if (c.SetCommTimeouts(self.handle.?, &timeouts) == c.FALSE) {
            return windows.unexpectedError(@enumFromInt(c.GetLastError()));
        }
    }

    pub fn write(self: *@This(), data: []const u8) !void {
        var overlapped = std.mem.zeroes(c.OVERLAPPED);

        if (self.writeEvent == null) {
            return error.PortNotOpen;
        }

        overlapped.hEvent = self.writeEvent.?;

        var written: c.DWORD = 0;
        if (c.WriteFile(self.handle.?, data.ptr, @intCast(data.len), &written, &overlapped) == c.FALSE) {
            const err = c.GetLastError();
            if (err != ERROR_IO_PENDING) {
                return windows.unexpectedError(@enumFromInt(err));
            }
            if (c.GetOverlappedResult(self.handle.?, &overlapped, &written, c.TRUE) == c.FALSE) {
                return windows.unexpectedError(@enumFromInt(c.GetLastError()));
            }
        }
    }

    pub fn read(self: *@This(), allocator: std.mem.Allocator, strategy: port.ReadStrategy) ![]u8 {
        var buffer: [4096]u8 = undefined;
        var bytesRead: usize = 0;

        switch (strategy) {
            .nonBlocking => {
                bytesRead = try self.readImpl(buffer[0..]);
            },
            .blockingAnyTimeout => |s| {
                if (try self.waitForData(s.timeout_ms)) {
                    bytesRead = try self.readImpl(buffer[0..]);
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

                    if (try self.waitForData(s.timeout_ms)) {
                        bytesRead += try self.readImpl(buffer[bytesRead..]);
                    } else {
                        return error.Timeout;
                    }
                }
            },
        }

        return allocator.dupe(u8, buffer[0..bytesRead]);
    }

    fn readImpl(self: *@This(), buffer: []u8) !usize {
        // TODO: c.ResetEvent(self.readEvent.?);
        var overlapped = std.mem.zeroes(c.OVERLAPPED);

        if (self.readEvent == null or self.handle == null) {
            return error.PortNotOpen;
        }

        overlapped.hEvent = self.readEvent.? orelse return 0;

        var n: c.DWORD = 0;
        if (c.ReadFile(self.handle.?, buffer.ptr, @intCast(buffer.len), &n, &overlapped) == c.FALSE) {
            const err = c.GetLastError();
            if (err == ERROR_IO_PENDING) {
                if (c.GetOverlappedResult(self.handle.?, &overlapped, &n, c.TRUE) == c.FALSE) {
                    return windows.unexpectedError(@enumFromInt(c.GetLastError()));
                }
            } else {
                return windows.unexpectedError(@enumFromInt(err));
            }
        }
        return @intCast(n);
    }

    fn waitForData(self: *@This(), timeout_ms: ?u32) !bool {
        var overlapped = std.mem.zeroes(c.OVERLAPPED);
        overlapped.hEvent = self.commEvent.? orelse return error.PortNotOpen;

        var evtMask: c.DWORD = 0;
        if (c.WaitCommEvent(self.handle.?, &evtMask, &overlapped) == c.FALSE) {
            const err = c.GetLastError();
            if (err != ERROR_IO_PENDING) {
                return windows.unexpectedError(@enumFromInt(err));
            }

            const timeout: c.DWORD = if (timeout_ms) |t| @intCast(t) else INFINITE;
            switch (c.WaitForSingleObject(self.commEvent.?, timeout)) {
                WAIT_OBJECT_0 => {
                    var unused: c.DWORD = 0;
                    if (c.GetOverlappedResult(self.handle.?, &overlapped, &unused, c.FALSE) == c.FALSE) {
                        return windows.unexpectedError(@enumFromInt(c.GetLastError()));
                    }
                },
                WAIT_TIMEOUT => {
                    _ = c.CancelIo(self.handle.?);
                    return false;
                },
                else => return windows.unexpectedError(@enumFromInt(c.GetLastError())),
            }
        }
        return (evtMask & EV_RXCHAR) != 0;
    }
};

pub fn listPorts(
    _: std.Io,
    allocator: std.mem.Allocator,
) !std.ArrayList(port.PortInfo) {
    var portsGuids: [8]c.GUID = undefined;
    var portsCount: c_ulong = 0;
    _ = c.SetupDiClassGuidsFromNameW(std.unicode.utf8ToUtf16LeStringLiteral("Ports"), &portsGuids, 8, &portsCount);

    var modemGuids: [8]c.GUID = undefined;
    var modemCount: c_ulong = 0;
    _ = c.SetupDiClassGuidsFromNameW(std.unicode.utf8ToUtf16LeStringLiteral("Modem"), &modemGuids, 8, &modemCount);

    var serialPorts = try std.ArrayList(port.PortInfo).initCapacity(allocator, 2);

    try enumGuids(allocator, &serialPorts, portsGuids[0..portsCount]);
    try enumGuids(allocator, &serialPorts, modemGuids[0..modemCount]);

    return serialPorts;
}

fn wideToUtf8(allocator: std.mem.Allocator, wide: []const u16) ![]u8 {
    const len = std.mem.indexOfScalar(u16, wide, 0) orelse wide.len;
    return std.unicode.utf16LeToUtf8Alloc(allocator, wide[0..len]);
}

fn enumGuids(
    allocator: std.mem.Allocator,
    ports: *std.ArrayList(port.PortInfo),
    guids: []c.GUID,
) !void {
    for (guids) |*guidPtr| {
        const hdi = c.SetupDiGetClassDevsW(
            guidPtr,
            null,
            null,
            DIGCF_PRESENT,
        );

        if (hdi == null or hdi == c.INVALID_HANDLE_VALUE) {
            continue;
        }
        defer _ = c.SetupDiDestroyDeviceInfoList(hdi);

        var di: c_ulong = 0;
        while (true) : (di += 1) {
            var devInfo = std.mem.zeroes(c.SP_DEVINFO_DATA);
            devInfo.cbSize = @sizeOf(c.SP_DEVINFO_DATA);

            if (c.SetupDiEnumDeviceInfo(hdi, di, &devInfo) == 0) {
                break;
            }

            const hkey = c.SetupDiOpenDevRegKey(
                hdi,
                &devInfo,
                DICS_FLAG_GLOBAL,
                0,
                DIREG_DEV,
                KEY_READ,
            );
            if (hkey == null or hkey == INVALID_HANDLE_VALUE) {
                continue;
            }

            var portBuf: [250]u16 = undefined;
            var portBytes: c_ulong = @sizeOf(@TypeOf(portBuf));
            _ = c.RegQueryValueExW(
                hkey,
                std.unicode.utf8ToUtf16LeStringLiteral("PortName"),
                null,
                null,
                @ptrCast(&portBuf),
                &portBytes,
            );
            _ = c.RegCloseKey(hkey);

            const portName = wideToUtf8(allocator, &portBuf) catch continue;
            defer allocator.free(portName);

            if (std.mem.startsWith(u8, portName, "LPT")) {
                continue;
            }

            var szHardwareId: [250]u16 = undefined;
            var szHardwareIdStr: []u8 = undefined;
            if (c.SetupDiGetDeviceInstanceIdW(
                hdi,
                &devInfo,
                @ptrCast(&szHardwareId),
                szHardwareId.len - 1,
                null,
            ) != 0) {
                if (c.SetupDiGetDeviceRegistryPropertyW(
                    hdi,
                    &devInfo,
                    SPDRP_HARDWAREID,
                    null,
                    @ptrCast(&szHardwareId),
                    @sizeOf(@TypeOf(szHardwareId)) - 2,
                    null,
                ) != 0) {
                    // ERROR
                }

                szHardwareIdStr = wideToUtf8(allocator, &szHardwareId) catch break;
                // defer allocator.free(szHardwareIdStr);
            }

            var info = port.PortInfo{
                .device = try allocator.dupe(u8, portName),
                .product = try allocator.dupe(u8, ""),
                .manufacturer = try allocator.dupe(u8, ""),
                .serialNumber = try allocator.dupe(u8, ""),
                .vid = 0,
                .pid = 0,
                .location = try allocator.dupe(u8, szHardwareIdStr),
            };
            errdefer info.deinit(allocator);

            if (std.mem.startsWith(u8, szHardwareIdStr, "USB")) {
                try utils.parseUsbHardwareInfo(allocator, szHardwareIdStr, &info);

                const serial = try getParentSerialNumber(allocator, devInfo.DevInst, null);

                info.serialNumber = try allocator.dupe(u8, serial.?);
            }

            var friendlyBuf: [250]u16 = undefined;
            if (c.SetupDiGetDeviceRegistryPropertyW(
                hdi,
                &devInfo,
                SPDRP_FRIENDLYNAME,
                null,
                @ptrCast(&friendlyBuf),
                @sizeOf(@TypeOf(friendlyBuf)) - 2,
                null,
            ) != 0) {
                allocator.free(info.product);
                info.product = try wideToUtf8(allocator, &friendlyBuf);
            }

            var manufacturerBuf: [250]u16 = undefined;
            if (c.SetupDiGetDeviceRegistryPropertyW(
                hdi,
                &devInfo,
                SPDRP_MFG,
                null,
                @ptrCast(&manufacturerBuf),
                @sizeOf(@TypeOf(manufacturerBuf)) - 2,
                null,
            ) != 0) {
                allocator.free(info.manufacturer);
                info.manufacturer = try wideToUtf8(allocator, &manufacturerBuf);
            }

            try ports.append(allocator, info);
        }
    }
}

fn getParentSerialNumber(
    allocator: std.mem.Allocator,
    childDevInst: c_ulong,
    lastSerial: ?[]const u8,
) !?[]const u8 {
    var devInst: c_ulong = undefined;

    const cr = c.CM_Get_Parent(&devInst, childDevInst, 0);

    if (cr != CR_SUCCESS) {
        return lastSerial;
    }

    var idBuf: [250]u16 = undefined;

    if (c.CM_Get_Device_IDW(devInst, @ptrCast(&idBuf), idBuf.len - 1, 0) != CR_SUCCESS) {
        return lastSerial;
    }
    const idStr = try wideToUtf8(allocator, &idBuf);
    defer allocator.free(idStr);

    var portInfo: port.PortInfo = undefined;

    try utils.parseUsbHardwareInfo(allocator, idStr, &portInfo);

    return portInfo.serialNumber;
}

const CR_SUCCESS: c_long = 0;
const DIGCF_PRESENT: c_ulong = 0x0002;
const DICS_FLAG_GLOBAL: c_ulong = 0x0001;
const DIREG_DEV: c_ulong = 0x0001;
const KEY_READ: c_ulong = 0x20019;
const SPDRP_HARDWAREID: c_ulong = 0x0001;
const SPDRP_FRIENDLYNAME: c_ulong = 0x000C;
const SPDRP_MFG: c_ulong = 0x000B;

// Sentinel values
const NULL: ?*anyopaque = null;
const TRUE: c.BOOL = 1;
const FALSE: c.BOOL = 0;
const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;

// CreateFileW access
const GENERIC_READ: c.DWORD = 0x80000000;
const GENERIC_WRITE: c.DWORD = 0x40000000;

// CreateFileW creation disposition
const OPEN_EXISTING: c.DWORD = 3;

// CreateFileW flags
const FILE_FLAG_OVERLAPPED: c.DWORD = 0x40000000;

// Error codes
const ERROR_IO_PENDING: c.DWORD = 997;

// MAXDWORD
const MAXDWORD: c.DWORD = 0xFFFFFFFF;

// DCB flag bits — the real SDK uses a bitfield here; we use a plain DWORD
// with named constants so the memory layout stays identical
const DCB_FBINARY: c.DWORD = 1 << 0;
const DCB_FPARITY: c.DWORD = 1 << 1;
const DCB_FOUTXCTSFLOW: c.DWORD = 1 << 2;
const DCB_FOUTX: c.DWORD = 1 << 8;
const DCB_FINX: c.DWORD = 1 << 9;
const DCB_FRTSCONTROL_MASK: c.DWORD = 3 << 12;
const DCB_FRTSCONTROL_ENABLE: c.DWORD = 1 << 12;
const DCB_FRTSCONTROL_HANDSHAKE: c.DWORD = 2 << 12;

// DCB stop bits
const ONESTOPBIT: c.BYTE = 0;
const TWOSTOPBITS: c.BYTE = 2;

// DCB parity
const NOPARITY: c.BYTE = 0;
const ODDPARITY: c.BYTE = 1;
const EVENPARITY: c.BYTE = 2;

// Event stuff
const EV_RXCHAR: c.DWORD = 0x0001; // character received event
const WAIT_OBJECT_0: c.DWORD = 0x00000000; // wait satisfied
const WAIT_TIMEOUT: c.DWORD = 0x00000102; // wait timed out
const WAIT_FAILED: c.DWORD = 0xFFFFFFFF;
const INFINITE: c.DWORD = 0xFFFFFFFF;
const ERROR_IO_INCOMPLETE: c.DWORD = 996; // overlapped I/O not yet complete
