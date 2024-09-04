const wds = @import("window/waylandDisplayServer.zig");

pub fn main() !void {
    const displayServer = try wds.WaylandDisplayServer.init();
    displayServer.close();
}
