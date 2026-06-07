const std = @import("std");
pub const port = @import("common.zig");
const c = @import("c");

pub const Port = struct {
    file: ?std.Io.File = null,
    io: std.Io,

    pub fn init(io: std.Io) Port {
        return .{ .io = io };
    }

    pub fn open(
        _: *Port,
        _: port.PortInfo,
    ) !void {}

    pub fn close(_: *Port) void {}

    pub fn configure(_: *Port, _: port.Options) !void {}
};

const DIGCF_PRESENT: c_ulong = 0x0002;
const DICS_FLAG_GLOBAL: c_ulong = 0x0001;
const DIREG_DEV: c_ulong = 0x0001;
const KEY_READ: c_ulong = 0x20019;
const INVALID_HANDLE_VALUE = std.os.windows.INVALID_HANDLE_VALUE;

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

            const portInfo = port.PortInfo{ .device = portName, .location = "", .manufacturer = "", .pid = 0, .product = "", .serialNumber = "", .vid = 0 };

            try ports.append(allocator, portInfo);
        }
    }
}

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
