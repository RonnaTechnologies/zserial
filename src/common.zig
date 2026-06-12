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

pub const Options = struct {
    // Baud rate
    baudRate: u32 = undefined,
    // Data bits
    dataBits: DataBits = .eight,
    // Stop bits
    stopBits: StopBits = .one,
    // Parity
    parity: Parity = .none,
    // Hardware flow control
    hardwareFlowControl: bool = false,
};

pub const DataBits = enum(u8) { five = 5, six = 6, seven = 7, eight = 8 };
pub const StopBits = enum { one, two };
pub const Parity = enum { none, odd, even };
