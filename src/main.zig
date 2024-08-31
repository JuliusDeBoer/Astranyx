const std = @import("std");
const wl = @cImport({
    @cInclude("wayland-client.h");
});

pub fn main() !void {
    const display = wl.wl_display_connect(null);
    if (display == null) {
        std.debug.print("(wayland) Could not get display\n", .{});
        return;
    }
    std.debug.print("(wayland) Connection established!\n", .{});
    wl.wl_display_disconnect(display);
    return;
}