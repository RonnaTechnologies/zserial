# zserial

**zserial** is a cross-platform serial port library for [Zig](https://ziglang.org/) 0.16. It provides a native Zig API for opening, configuring, and communicating over serial ports, as well as a C shared library and a C++ wrapper.

## Features

- Cross-platform: Linux, macOS, and Windows.
- Native Zig module usable.
- C shared library (`libzserial`) with C++ wrapper.
- Platform-native backends (IOKit on macOS, Win32 APIs on Windows, POSIX on Linux).
- Build-time documentation generation.

## Platform Support

| Platform | Status |
|----------|--------|
| Linux    | ✅ Supported |
| macOS    | ✅ Supported (cross-compile via osxcross) |
| Windows  | ✅ Supported (cross-compile ready) |

## Requirements

- Zig **0.16.0** or later

## Installation (Zig)

Add `zserial` to your `build.zig.zon`:

```zig
.{
    .name = .my_project,
    .version = "0.0.1",
    .dependencies = .{
        .zserial = .{
            .url = "https://github.com/RonnaTechnologies/zserial/archive/refs/heads/main.tar.gz",
            .hash = "<run zig fetch to get the hash>",
        },
    },
}
```

Then import it in your `build.zig`:

```zig
const zserial = b.dependency("zserial", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zserial", zserial.module("zserial"));
```

## Zig Usage

```zig
const std = @import("std");
const serial = @import("zserial").serial;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const arenaAllocator = arena.allocator();

    const serialPorts = try serial.listPorts(io, arenaAllocator);

    // Valid baud rates are comptime
    const baudRates = comptime serial.baudRates;
    _ = baudRates;

    const baudRate: u32 = 115_200;

    if (!serial.isValidBaudRate(baudRate)) {
        return error.invalidBaudRate;
    }

    std.log.info("Serial ports found:", .{});

    for (serialPorts.items) |portInfo| {
        std.log.info("{s}\n", .{portInfo.device});

        var port: serial.Port = .init(io);
        try port.open(portInfo);
        defer port.close();

        const options = serial.port.Options{ .baudRate = baudRate, .dataBits = .eight, .parity = .none, .stopBits = .one };
        try port.configure(options);

        try port.write("test");
        const response = try port.read(arenaAllocator);

        std.log.info("Received: {s}", .{response});
    }
}

```

> **Note:** The example above reflects the general API shape. See the generated docs for the full API reference.

## Building

Clone the repository and build with:

```sh
git clone https://github.com/RonnaTechnologies/zserial.git
cd zserial
zig build
```

### Run the example program (Linux)

```sh
zig build run
```

### Run tests

```sh
zig build test
```

### Generate documentation

```sh
zig build docs
```

Documentation is emitted to `zig-out/docs/`.

## Cross-Compilation

### Windows

```sh
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows
```

### macOS (via osxcross)

```sh
zig build -Doptimize=ReleaseSmall \
    -Dtarget=x86_64-macos \
    -Dosxcross-sdk=/path/to/osxcross/target/SDK/MacOSX13.3.sdk
```

## C / C++ API

zserial also builds as a shared C library (`libzserial`), making it usable from any language with a C FFI.

### Build the shared library

```sh
zig build
```

This installs:

- `zig-out/lib/libzserial.so` (or `.dll` / `.dylib`)
- `zig-out/include/zserial.h`
- `zig-out/include/zserial.hpp`

### Compile a C++ program against libzserial

```sh
g++ -std=c++23 -o my_app -I./zig-out/include -L./zig-out/lib my_app.cpp -lzserial
```

## Build Options

| Option | Description |
|--------|-------------|
| `-Dtarget=<triple>` | Cross-compile target (e.g. `x86_64-windows`) |
| `-Doptimize=<mode>` | Optimization mode: `Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall` |
| `-Dosxcross-sdk=<path>` | Path to the macOS SDK (required for macOS cross-compilation) |

## License

MIT — see [LICENSE](LICENSE) for details.
