const std = @import("std");
const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell.h");
});

pub const RegistryItem = struct { name: u32, interface: []const u8, version: u32 };

// This is horrible! I hate it!
// It also might should maybe could be a mutex.
var registryItems: [64]RegistryItem = undefined;
// This one might even be worse
var registryItemsCount: u6 = 0;

/// Easily create a wayland window
pub const WaylandDisplayServer = struct {
    const Self = @This();

    display: *c.struct_wl_display = undefined,
    compositor: *c.struct_wl_compositor = undefined,
    registry: *c.wl_registry = undefined,
    xdg_shell: *c.struct_zxdg_shell_v6 = undefined,

    pub fn registry_handle_global(data: ?*anyopaque, registry: ?*c.struct_wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.C) void {
        _ = registry;
        _ = data;
        std.debug.print("(wayland) Found registry: interface: {s} version: {} name: {}\n", .{ interface, version, name });

        const interface_string = std.mem.span(@as([*:0]const u8, @ptrCast(interface)));
        const item = RegistryItem{ .name = name, .interface = interface_string, .version = version };
        registryItems[registryItemsCount] = item;
        registryItemsCount += 1;
    }

    pub fn registry_handle_global_remove(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32) callconv(.C) void {
        _ = registry;
        _ = data;
        _ = name;
        std.debug.print("(wayland) TODO: Handle removing from registry", .{});
    }

    pub fn init() anyerror!Self {
        var out = Self{ .compositor = undefined, .display = undefined };
        const display = c.wl_display_connect(null);

        {
            if (display == null) {
                std.debug.print("(wayland) Could not get display\n", .{});
                return error.WaylandError;
            }
            out.display = display.?;
        }

        out.registry = c.wl_display_get_registry(out.display).?;

        const registry_listener: c.wl_registry_listener = .{ .global = registry_handle_global, .global_remove = registry_handle_global_remove };
        _ = c.wl_registry_add_listener(out.registry, &registry_listener, null);

        if (c.wl_display_roundtrip(out.display) == -1) {
            std.debug.print("(wayland) wl_display_roundtrip failed. Cowardly exiting...\n", .{});
            return error.WaylandError;
        }

        for (&registryItems) |item| {
            if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.wl_compositor_interface.name))))) {
                const compositor_ptr = c.wl_registry_bind(out.registry, item.name, &c.wl_compositor_interface, item.version);
                out.compositor = @ptrCast(@alignCast(compositor_ptr));
            } else if (std.mem.eql(u8, item.interface, "zxdg_shell_v6")) {
                const xdg_shell_ptr = c.wl_registry_bind(out.registry, item.name, &c.zxdg_shell_v6_interface, item.version);
                out.xdg_shell = @ptrCast(@alignCast(xdg_shell_ptr));
            }
        }

        const surface = c.wl_compositor_create_surface(out.compositor);
        _ = surface;

        std.debug.print("(wayland) Initialized successfully\n", .{});
        return out;
    }

    pub fn close(self: Self) void {
        c.wl_display_disconnect(self.display);
        std.debug.print("(wayland) Closed connection\n", .{});
    }

    /// Event loop thingy
    pub fn dispatch(self: Self) bool {
        return c.wl_display_dispatch(self.display) != 0;
    }
};
