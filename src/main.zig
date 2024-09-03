const ds = @import("window/displayServer.zig");

pub fn main() !void {
    const displayServer = ds.getDisplayServer();
    try displayServer.connectFn(displayServer.ptr);
}
