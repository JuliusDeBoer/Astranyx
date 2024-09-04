const std = @import("std");
const wl = @cImport({
    @cInclude("wayland-client.h");
});

pub const WaylandDisplayServer = struct {
    display: ?*wl.struct_wl_display = null,

    const Self = @This();

    pub fn init() anyerror!Self {
        const display = wl.wl_display_connect(null);
        if (display == null) {
            std.debug.print("(wayland) Could not get display\n", .{});
            return error.cringeError;
        }
        std.debug.print("(wayland) Connection established\n", .{});

        return Self{ .display = display };
    }

    pub fn close(self: Self) void {
        wl.wl_display_disconnect(self.display);
        std.debug.print("(wayland) Closed connection\n", .{});
    }
};
