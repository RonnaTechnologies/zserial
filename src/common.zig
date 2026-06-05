const std = @import("std");

pub const PortInfo = struct {
    device: []const u8,
    product: []const u8,
    manufacturer: []const u8,
    serialNumber: []const u8,
    vid: u16,
    pid: u16,
    location: []const u8,
};
