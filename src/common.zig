const std = @import("std");

pub fn computeTimeoutMs(options: Options, nBytes: u32) u32 {
    const dataBits: u32 = @intFromEnum(options.dataBits);

    const stopBits: u32 = switch (options.stopBits) {
        .one => 1,
        .two => 2,
    };

    const parity: u32 = switch (options.parity) {
        .none => 0,
        .odd, .even => 1,
    };

    const bitsPerByte = 1 + dataBits + parity + stopBits;

    return (nBytes * bitsPerByte * 1_000) / options.baudRate;
}

pub const PortInfo = struct {
    /// Device path
    device: []const u8,
    /// Product name
    product: []const u8,
    /// Manufacturer
    manufacturer: []const u8,
    /// Serial number
    serialNumber: []const u8,
    /// Vendor id
    vid: u16,
    /// Product id
    pid: u16,
    /// Device system location
    location: []const u8,

    pub fn deinit(self: PortInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.device);
        allocator.free(self.product);
        allocator.free(self.manufacturer);
        allocator.free(self.serialNumber);
        allocator.free(self.location);
    }

    pub fn format(
        self: *const PortInfo,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print(
            \\PortInfo {{
            \\  device: "{s}",
            \\  product: "{s}",
            \\  manufacturer: "{s}",
            \\  serialNumber: "{s}",
            \\  vid: 0x{X:0>4},
            \\  pid: 0x{X:0>4},
            \\  location: "{s}"
            \\}}
        , .{
            self.device,
            self.product,
            self.manufacturer,
            self.serialNumber,
            self.vid,
            self.pid,
            self.location,
        });
    }
};

pub const Options = struct {
    /// Baud rate
    baudRate: u32 = undefined,
    /// Data bits
    dataBits: DataBits = .eight,
    /// Stop bits
    stopBits: StopBits = .one,
    /// Parity
    parity: Parity = .none,
    /// Hardware flow control
    hardwareFlowControl: bool = false,
};

pub const ReadStrategy = union(enum) {
    /// Block until at least 'nBbytes' arrive, or 'timeout_ms' elapses.
    /// If timeout_ms is null, blocks indefinitely.
    blockingMinTimeout: struct { nBytes: usize, timeout_ms: ?u32 },
    /// Block until at least one byte arrives, or 'timeout_ms' elapses.
    blockingAnyTimeout: struct { timeout_ms: u32 },
    /// Non-blocking read. Returns immediately with available data (0 or more bytes).
    nonBlocking,
};

pub const DataBits = enum(u8) { five = 5, six = 6, seven = 7, eight = 8 };
pub const StopBits = enum { one, two };
pub const Parity = enum { none, odd, even };
