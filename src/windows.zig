const std = @import("std");
const serial = @import("common.zig");
const c = @import("c");

const DIGCF_PRESENT: c_ulong = 0x0002;

fn enumGuids(
    _: std.mem.Allocator,
    // _: *std.ArrayList(serial.PortInfo),
    guids: []c.GUID,
    count: c_ulong,
) !void {
    var gi: c_ulong = 0;
    while (gi < count) : (gi += 1) {
        const hdi = c.SetupDiGetClassDevsW(
            &guids[gi],
            null,
            null,
            DIGCF_PRESENT,
        );

        if (hdi == null or hdi == c.INVALID_HANDLE_VALUE) continue;
        defer _ = c.SetupDiDestroyDeviceInfoList(hdi);
    }
}

pub fn listPorts(
    _: std.Io,
    allocator: std.mem.Allocator,
) !std.ArrayList(serial.PortInfo) {
    const serialPorts = try std.ArrayList(serial.PortInfo).initCapacity(allocator, 2);

    var ports_guids: [8]c.GUID = undefined;
    var ports_count: c_ulong = 0;
    _ = c.SetupDiClassGuidsFromNameW(std.unicode.utf8ToUtf16LeStringLiteral("Ports"), &ports_guids, 8, &ports_count);

    var modem_guids: [8]c.GUID = undefined;
    var modem_count: c_ulong = 0;
    _ = c.SetupDiClassGuidsFromNameW(std.unicode.utf8ToUtf16LeStringLiteral("Modem"), &modem_guids, 8, &modem_count);

    try enumGuids(allocator, ports_guids[0..ports_count], ports_count);
    try enumGuids(allocator, modem_guids[0..modem_count], modem_count);

    return serialPorts;
}
