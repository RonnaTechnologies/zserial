pub fn validate(comptime Impl: type) void {
    comptime {
        const ctx = @typeName(Impl);

        requireDecl(Impl, "baudRates", ctx ++ ": missing `baudRates`");
        requireDecl(Impl, "isValidBaudRate", ctx ++ ": missing `isValidBaudRate`");

        requireDecl(Impl, "Port", ctx ++ ": missing `Port`");
    }
}

fn requireDecl(comptime T: type, comptime name: []const u8, comptime msg: []const u8) void {
    if (!@hasDecl(T, name)) @compileError(msg);
}
