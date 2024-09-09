const std = @import("std");
const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell.h");
});

fn randName(random: std.rand.Random) [7]u8 {
    var out: [7]u8 = undefined;
    for (0..out.len) |i| {
        out[i] = random.intRangeAtMost(u8, 'a', 'z');
    }
    return out;
}

fn createShmFile() !c_int {
    var retries: u8 = 99;
    const seed: u64 = @intCast(std.time.milliTimestamp());
    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();

    while (retries > 0) {
        // var name = "/wl_shm-0000000";
        // std.mem.copyForwards(u8, @constCast(name[8..], &randName(random));
        const name = try std.fmt.allocPrint(std.heap.page_allocator, "/wl_shm-{s}", .{randName(random)});
        retries -= 1;
        const flags = std.posix.O{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
        };
        const fd = std.c.shm_open(@ptrCast(name), @bitCast(flags), 0o666);
        if (fd >= 0) {
            _ = std.c.shm_unlink(@ptrCast(name));
            return fd;
        }
    }

    // TODO: Make this its own error maybe
    return error.WaylandError;
}

fn allocateShmFile(size: i32) !c_int {
    const fd = try createShmFile();
    var ret: i32 = -1;

    while (ret < 0) {
        ret = std.c.ftruncate(fd, size);
    }

    if (ret < 0) {
        _ = std.c.close(fd);
        return error.WaylandError;
    }

    return fd;
}

pub const RegistryItem = struct { name: u32, interface: []const u8, version: u32 };

// This is horrible! I hate it!
// It also might should maybe could be a mutex.
var registryItems: [64]RegistryItem = undefined;
// This one might even be worse
var registryItemsCount: u6 = 0;

const WaylandDisplayServerArgs = struct { name: []const u8, width: i32, height: i32 };

/// Easily create a wayland window
pub const WaylandDisplayServer = struct {
    const Self = @This();

    display: *c.struct_wl_display = undefined,
    compositor: *c.struct_wl_compositor = undefined,
    registry: *c.wl_registry = undefined,
    shm: *c.wl_shm = undefined,
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

    pub fn init(args: WaylandDisplayServerArgs) anyerror!Self {
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
            // TODO: Use a switch statement
            if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.wl_compositor_interface.name))))) {
                const compositor_ptr = c.wl_registry_bind(out.registry, item.name, &c.wl_compositor_interface, item.version);
                out.compositor = @ptrCast(@alignCast(compositor_ptr));
            } else if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.wl_shm_interface.name))))) {
                const shm_ptr = c.wl_registry_bind(out.registry, item.name, &c.wl_shm_interface, item.version);
                out.shm = @ptrCast(@alignCast(shm_ptr));
            } else if (std.mem.eql(u8, item.interface, "zxdg_shell_v6")) {
                const xdg_shell_ptr = c.wl_registry_bind(out.registry, item.name, &c.zxdg_shell_v6_interface, item.version);
                out.xdg_shell = @ptrCast(@alignCast(xdg_shell_ptr));
            }
        }

        const surface = c.wl_compositor_create_surface(out.compositor);

        const stride = args.width * 4;
        const shm_pool_size: usize = @as(usize, @intCast(args.height * stride * 2));

        const fd = try allocateShmFile(@intCast(shm_pool_size));
        const pool_data = std.c.mmap(null, shm_pool_size, std.c.PROT.READ | std.c.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);
        const pool = c.wl_shm_create_pool(out.shm, fd, @intCast(shm_pool_size)).?;

        const index = 0;
        const offset = args.height * stride * index;

        const buffer = c.wl_shm_pool_create_buffer(pool, offset, args.width, args.height, stride, c.WL_SHM_FORMAT_XRGB8888).?;

        _ = pool_data;

        c.wl_surface_attach(surface, buffer, 0, 0);
        c.wl_surface_damage(surface, 0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
        c.wl_surface_commit(surface);

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
