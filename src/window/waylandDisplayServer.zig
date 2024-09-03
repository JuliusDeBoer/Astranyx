const std = @import("std");
const wl = @cImport({
    @cInclude("wayland-client.h");
});
const ds = @import("displayServer.zig");

pub const WaylandDisplayServer = struct {
    const Self = @This();

    pub fn connect(ptr: *anyopaque) anyerror!void {
        // Trust me bro
        const self: *Self = @ptrCast(@alignCast(ptr));
        _ = self;

        const display = wl.wl_display_connect(null);
        if (display == null) {
            std.debug.print("(wayland) Could not get display\n", .{});
            return;
        }
        std.debug.print("(wayland) Connection established!\n", .{});
        wl.wl_display_disconnect(display);
    }

    pub fn displayServer(self: *Self) ds.DisplayServer {
        return ds.DisplayServer.init(self);
    }
};
