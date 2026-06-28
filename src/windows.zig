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
    }

    pub fn close(self: *@This()) void {
        if (self.iocpHandle) |h| {
            _ = c.CloseHandle(h);
            self.iocpHandle = null;
        }
        if (self.handle) |h| {
            _ = c.CloseHandle(h);
            self.handle = null;
        }
    }

    pub fn configure(_: *@This(), _: port.Options) !void {}

    pub fn write(self: *@This(), data: []const u8) !void {
        _ = self;
        _ = data;
    }

    pub fn read(self: *@This(), allocator: std.mem.Allocator, strategy: port.ReadStrategy) ![]u8 {
        _ = self;
        _ = allocator;
        _ = strategy;

        return error.TODO;
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
const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;
const SPDRP_HARDWAREID: c_ulong = 0x0001;
const SPDRP_FRIENDLYNAME: c_ulong = 0x000C;
const SPDRP_MFG: c_ulong = 0x000B;

const GENERIC_READ: windows.DWORD = 0x80000000;
const GENERIC_WRITE: windows.DWORD = 0x40000000;
const OPEN_EXISTING: windows.DWORD = 3;
const FILE_FLAG_OVERLAPPED: windows.DWORD = 0x40000000;
