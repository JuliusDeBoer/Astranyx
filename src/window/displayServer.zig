const wds = @import("waylandDisplayServer.zig");

pub const DisplayServer = struct {
    const Self = @This();

    ptr: *anyopaque,
    connectFn: fn (*anyopaque) anyerror!void,

    pub fn init(ptr: anytype) Self {
        const Ptr = @TypeOf(ptr);
        const ptr_info = @typeInfo(Ptr);

        if (ptr_info != .Pointer) @compileError("Argument ptr must be a pointer");
        if (ptr_info.Pointer.size != .One) @compileError("Argument ptr must be a single item pointer");

        const gen = struct {
            pub fn connectImpl(pointer: *anyopaque) anyerror!void {
                const self: Ptr = @ptrCast(pointer);
                return @call(.always_inline, ptr_info.Pointer.child.connect, .{self});
            }
        };

        return .{ .ptr = ptr, .connectFn = gen.connectImpl };
    }
};

/// Get the display server for the current system
pub fn getDisplayServer() DisplayServer {
    // This works for now
    const server = wds.WaylandDisplayServer{};
    return @constCast(&server).displayServer();
}
