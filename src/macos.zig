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

const IO_NAME_SIZE: usize = 128;

fn getIOServicesByType(
    allocator: std.mem.Allocator,
    service_type: [:0]const u8,
) !std.ArrayList(c.io_object_t) {
    var services = try std.ArrayList(c.io_object_t)
        .initCapacity(allocator, 8);

    const matching = c.IOServiceMatching(service_type.ptr);

    if (matching == null) {
        std.log.err("IOServiceMatching returned null", .{});
        return services;
    }

    var iterator: c.io_iterator_t = 0;

    const kr = c.IOServiceGetMatchingServices(
        c.kIOMainPortDefault,
        matching,
        &iterator,
    );

    std.log.info("IOServiceGetMatchingServices -> {}", .{kr});

    if (kr != c.KERN_SUCCESS)
        return services;

    defer _ = c.IOObjectRelease(iterator);

    while (true) {
        const service = c.IOIteratorNext(iterator);

        if (service == 0)
            break;

        try services.append(allocator, service);
    }

    return services;
}

fn dumpService(service: c.io_object_t) void {
    var name: [128]u8 = undefined;

    if (c.IORegistryEntryGetName(service, &name) == c.KERN_SUCCESS) {
        const len = std.mem.indexOfScalar(u8, &name, 0) orelse name.len;

        std.log.info(
            "service {d}: {s}",
            .{ service, name[0..len] },
        );
    } else {
        std.log.info(
            "service {d}: <no name>",
            .{service},
        );
    }
}

const IOObject = u32;
fn getStringProperty(
    allocator: std.mem.Allocator,
    entry: c.io_object_t,
    property: [:0]const u8,
) !?[]u8 {
    const key = c.CFStringCreateWithCString(
        null,
        property.ptr,
        c.kCFStringEncodingUTF8,
    );
    if (key == null) return null;
    defer c.CFRelease(key);

    const container_raw = c.IORegistryEntryCreateCFProperty(
        entry,
        key,
        null,
        0,
    );
    if (container_raw == null) return null;
    defer c.CFRelease(container_raw);

    const container: c.CFStringRef = @ptrCast(container_raw);

    if (c.CFStringGetCStringPtr(container, c.kCFStringEncodingUTF8)) |ptr| {
        return try allocator.dupe(u8, std.mem.sliceTo(ptr, 0));
    }

    var buf: [IO_NAME_SIZE]u8 = undefined;

    if (c.CFStringGetCString(
        container,
        &buf,
        IO_NAME_SIZE,
        c.kCFStringEncodingUTF8,
    ) != 0) {
        return try allocator.dupe(u8, std.mem.sliceTo(&buf, 0));
    }

    return null;
}

pub fn listPorts(
    _: std.Io,
    allocator: std.mem.Allocator,
) !std.ArrayList(port.PortInfo) {
    std.log.info("enumerating macOS serial ports", .{});

    const ports = try std.ArrayList(port.PortInfo).initCapacity(allocator, 4);

    const services = try getIOServicesByType(
        allocator,
        "IOSerialBSDClient",
    );

    defer {
        for (services.items) |service| {
            _ = c.IOObjectRelease(service);
        }
    }

    std.log.info(
        "found {} IOSerialBSDClient services",
        .{services.items.len},
    );

    for (services.items) |service| {
        const device_opt =
            try getStringProperty(allocator, service, "IOCalloutDevice");
        const device = device_opt orelse continue;

        std.log.info("Found device: {s}", .{device});
    }

    return ports;
}
