const std = @import("std");
const wds = @import("window/wayland.zig");

// The state of the entire program. Maybe move this to another file. Maybe not.
const State = struct {
    const Self = @This();

    displayServer: *wds.WaylandDisplayServer,

    pub fn clean(self: Self) void {
        std.debug.print("(global) Gracefully exiting...\n", .{});
        self.displayServer.close();
    }
};
var state: State = .{ .displayServer = undefined };

pub fn cleanHandle(_: i32) callconv(.C) void {
    std.debug.print("\n", .{});
    state.clean();
}

pub fn main() !void {
    const displayServer = try wds.WaylandDisplayServer.init();
    state.displayServer = @constCast(&displayServer);

    // Handle SIGINT (ctrl+c)
    //
    // This does not work for windows since it doesnt actually uses signals for
    // handling ctrl+c. Too bad!
    //
    // (Also this line is waaay to long)
    const handler: std.posix.Sigaction = .{ .handler = .{ .handler = cleanHandle }, .mask = std.posix.empty_sigset, .flags = 0 };
    try std.posix.sigaction(std.posix.SIG.INT, &handler, null);

    std.debug.print("(global) Starting event loop\n", .{});
    while (state.displayServer.dispatch()) {}

    state.clean();
}
