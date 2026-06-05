# zserial

zserial is a cross platform Zig library for serial port communication.

## Cross Compile for Windows

```bash
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows
```

## Cross Compile for MacOS

```bash
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-macos -Dosxcross-sdk=/home/jeremy/Desktop/Prog/osxcross/target/SDK/MacOSX13.3.sdk
```
