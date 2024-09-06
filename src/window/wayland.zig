const std = @import("std");
const wl = @cImport({
    @cInclude("wayland-client.h");
});

pub const WaylandDisplayServer = struct {
    display: *wl.struct_wl_display = undefined,
    compositor: *wl.struct_wl_compositor = undefined,
    registry: *wl.wl_registry = undefined,

    const Self = @This();

    pub fn registry_handle_global(data: ?*anyopaque, registry: ?*wl.struct_wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.C) void {
        _ = registry;
        _ = data;
        std.debug.print("(wayland) Found registry: interface: {s} version: {} name: {}\n", .{ interface, version, name });
    }
    pub fn registry_handle_global_remove(data: ?*anyopaque, registry: ?*wl.wl_registry, name: u32) callconv(.C) void {
        _ = registry;
        _ = data;
        std.debug.print("(wayland) Removed registry: name: {}\n", .{name});
    }

    pub fn init() anyerror!Self {
        var out = Self{ .compositor = undefined, .display = undefined };
        const display = wl.wl_display_connect(null);

        {
            if (display == null) {
                std.debug.print("(wayland) Could not get display\n", .{});
                return error.WaylandError;
            }
            out.display = display.?;
        }

        out.registry = wl.wl_display_get_registry(out.display).?;

        const registry_listener: wl.wl_registry_listener = .{ .global = registry_handle_global, .global_remove = registry_handle_global_remove };
        _ = wl.wl_registry_add_listener(out.registry, &registry_listener, null);

        if (wl.wl_display_roundtrip(out.display) == -1) {
            std.debug.print("(wayland) wl_display_roundtrip failed. Cowardly exiting...\n", .{});
            return error.WaylandError;
        }

        // TODO: Figure out what iterface means
        // https://wayland-book.com/surfaces/compositor.html
        // if (std.mem.eql(interface, wl.wl_compositor_interface.name)) {
        const compositorPtr = wl.wl_registry_bind(out.registry, 0, &wl.wl_compositor_interface, 4);
        out.compositor = @ptrCast(@alignCast(compositorPtr));
        // }

        const surface = wl.wl_compositor_create_surface(out.compositor);
        _ = surface;

        std.debug.print("(wayland) Initialized successfully\n", .{});
        return out;
    }

    pub fn close(self: Self) void {
        wl.wl_display_disconnect(self.display);
        std.debug.print("(wayland) Closed connection\n", .{});
    }

    /// Event loop thingy
    pub fn dispatch(self: Self) bool {
        return wl.wl_display_dispatch(self.display) != 0;
    }
};
