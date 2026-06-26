const std = @import("std");
const port = @import("common.zig");

pub fn validate(comptime Impl: type) void {
    comptime {
        const ctx = @typeName(Impl);

        requireDecl(Impl, "baudRates", ctx ++ ": missing `baudRates`");
        requireDecl(Impl, "isValidBaudRate", ctx ++ ": missing `isValidBaudRate`");

        checkSignature(Impl.isValidBaudRate, .{u32}, bool, ctx ++ ".isValidBaudRate");

        requireDecl(Impl, "Port", ctx ++ ": missing `Port`");

        const Port = Impl.Port;
        if (@typeInfo(Port) != .@"struct") {
            @compileError(ctx ++ ": `Port` must be a struct");
        }

        requireDecl(Port, "init", ctx ++ ".Port: missing `init`");
        requireDecl(Port, "open", ctx ++ ".Port: missing `open`");
        requireDecl(Port, "close", ctx ++ ".Port: missing `close`");
        requireDecl(Port, "configure", ctx ++ ".Port: missing `configure`");
        requireDecl(Port, "write", ctx ++ ".Port: missing `write`");
        requireDecl(Port, "read", ctx ++ ".Port: missing `read`");

        checkSignature(Port.init, .{std.Io}, Port, ctx ++ ".Port." ++ "init");
        checkSignature(Port.open, .{ *Port, port.PortInfo }, anyerror!void, ctx ++ ".Port." ++ "open");
    }
}

fn requireDecl(comptime T: type, comptime name: []const u8, comptime msg: []const u8) void {
    if (!@hasDecl(T, name)) @compileError(msg);
}

fn checkSignature(comptime func: anytype, comptime expected: anytype, comptime expectedRet: anytype, comptime fName: []const u8) void {
    const fnInfo = @typeInfo(@TypeOf(func));
    if (fnInfo != .@"fn") {
        @compileError(fName ++ " is not a function");
    }

    const params = fnInfo.@"fn".params;
    const fields = @typeInfo(@TypeOf(expected)).@"struct".fields;

    if (params.len != fields.len) @compileError(std.fmt.comptimePrint(
        "{s}: expected {d} param(s), found {d}",
        .{ fName, fields.len, params.len },
    ));

    inline for (fields, 0..) |field, i| {
        const ExpectedField = @field(expected, field.name);

        const actualField = params[i].type orelse @compileError(std.fmt.comptimePrint(
            "{s}: param[{d}] is generic (anytype), expected `{s}`",
            .{ fName, i, @typeName(ExpectedField) },
        ));

        if (actualField != ExpectedField) {
            @compileError(std.fmt.comptimePrint(
                "{s}: param[{d}] => expected `{s}`, found `{s}`",
                .{ fName, i, @typeName(ExpectedField), @typeName(actualField) },
            ));
        }
    }

    const ret = fnInfo.@"fn".return_type orelse @compileError(fName ++ ": missing return type");

    if (@typeInfo(expectedRet) == .error_union) {
        const payload = @typeInfo(expectedRet).error_union.payload;
        const retInfo = @typeInfo(ret);
        if (retInfo != .error_union) {
            @compileError(
                fName ++ ": expected an error-union return type (!" ++ @typeName(payload) ++ "), found `" ++ @typeName(ret) ++ "`",
            );
        }
        if (retInfo.error_union.payload != payload) {
            @compileError(
                fName ++ ": error-union payload => expected `" ++ @typeName(payload) ++ "`, found `" ++ @typeName(retInfo.error_union.payload) ++ "`",
            );
        }
    } else {
        if (ret != expectedRet) {
            @compileError(
                fName ++ ": return type => expected `" ++ @typeName(expectedRet) ++ "`, found `" ++ @typeName(ret) ++ "`",
            );
        }
    }
}
