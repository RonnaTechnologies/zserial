const std = @import("std");
const serial = @import("root.zig").serial;
const common = @import("common.zig");

const PortList = struct {
    allocator: std.mem.Allocator,
    ports: []common.PortInfo,
};

export fn zserial_list_ports(len: *usize) ?*PortList {
    var ioThreaded: std.Io.Threaded = .init_single_threaded;
    const io = ioThreaded.io();

    const allocator = std.heap.c_allocator;
    const list = allocator.create(PortList) catch return null;
    errdefer allocator.destroy(list);

    var ports = serial.listPorts(io, allocator) catch return null;
    list.* = .{
        .allocator = allocator,
        .ports = ports.toOwnedSlice(allocator) catch return null,
    };
    len.* = list.ports.len;
    return list;
}

export fn zserial_port_name(ports: *PortList, index: usize) [*]const u8 {
    return ports.ports[index].device.ptr;
}

export fn zserial_free(ports: *PortList) void {
    ports.allocator.free(ports.ports);
    ports.allocator.destroy(ports);
}
