//! # zserial
//!
//! Cross-platform serial port library for Zig.
//!
//! ## Platform modules
//! - `linux` — Linux implementation via termios
//! - `macos` — macOS implementation via IOKit
//! - `windows` — Windows implementation via Win32
//!
//! ## Usage
//! ```zig
//! const serial = @import("zserial").serial;
//! const ports = try serial.listPorts(allocator);
//! ```

pub const common = @import("common.zig");
pub const linux = @import("linux.zig");
pub const macos = @import("macos.zig");
pub const windows = @import("windows.zig");
