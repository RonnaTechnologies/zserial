pub fn validate(comptime Impl: type) void {
    comptime {
        const ctx = @typeName(Impl);

        requireDecl(Impl, "baudRates", ctx ++ ": missing `baudRates`");
        requireDecl(Impl, "isValidBaudRate", ctx ++ ": missing `isValidBaudRate`");

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
    }
}

fn requireDecl(comptime T: type, comptime name: []const u8, comptime msg: []const u8) void {
    if (!@hasDecl(T, name)) @compileError(msg);
}
