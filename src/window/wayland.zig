const std = @import("std");
const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell-protocol.h");
});
const l = @import("../logging.zig");

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
    const logger = l.Logger.init(Self);

    display: *c.struct_wl_display = undefined,
    compositor: *c.struct_wl_compositor = undefined,
    registry: *c.wl_registry = undefined,
    shm: *c.wl_shm = undefined,
    xdg_wm_base: *c.xdg_wm_base = undefined,
    xdg_surface: *c.xdg_surface = undefined,
    xdg_toplevel: *c.xdg_toplevel = undefined,

    pub fn registry_handle_global(data: ?*anyopaque, registry: ?*c.struct_wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.C) void {
        _ = registry;
        _ = data;
        logger.info("Found registry: interface: {s} version: {} name: {}", .{ interface, version, name });

        const interface_string = std.mem.span(@as([*:0]const u8, @ptrCast(interface)));
        const item = RegistryItem{ .name = name, .interface = interface_string, .version = version };
        registryItems[registryItemsCount] = item;
        registryItemsCount += 1;
    }

    pub fn registry_handle_global_remove(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32) callconv(.C) void {
        _ = registry;
        _ = data;
        _ = name;
        logger.info("TODO: Handle removing from registry", .{});
    }

    // I dont know if this only handles ping or other things too.
    pub fn handle_ping(_: ?*anyopaque, base: ?*c.struct_xdg_wm_base, id: u32) callconv(.C) void {
        c.xdg_wm_base_pong(base, id);
    }

    pub fn init(args: WaylandDisplayServerArgs) anyerror!Self {
        var out = Self{ .compositor = undefined, .display = undefined };
        const display = c.wl_display_connect(null);

        {
            if (display == null) {
                logger.err("Could not get display", .{});
                return error.WaylandError;
            }
            out.display = display.?;
        }

        out.registry = c.wl_display_get_registry(out.display).?;

        const registry_listener: c.wl_registry_listener = .{ .global = registry_handle_global, .global_remove = registry_handle_global_remove };
        _ = c.wl_registry_add_listener(out.registry, &registry_listener, null);

        if (c.wl_display_roundtrip(out.display) == -1) {
            logger.err("wl_display_roundtrip failed. Cowardly exiting...", .{});
            return error.WaylandError;
        }

        // This will cause a segvault when one or more do not get registered.
        // Time to not think about that.
        for (&registryItems) |item| {
            if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.wl_compositor_interface.name))))) {
                const compositor_ptr = c.wl_registry_bind(out.registry, item.name, &c.wl_compositor_interface, item.version);
                out.compositor = @ptrCast(@alignCast(compositor_ptr));
                logger.info("Registered compositor", .{});
            } else if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.wl_shm_interface.name))))) {
                const shm_ptr = c.wl_registry_bind(out.registry, item.name, &c.wl_shm_interface, item.version);
                out.shm = @ptrCast(@alignCast(shm_ptr));
                logger.info("Registered SHM", .{});
            } else if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.xdg_wm_base_interface.name))))) {
                const xdg_shell_ptr = c.wl_registry_bind(out.registry, item.name, &c.xdg_wm_base_interface, item.version);
                out.xdg_wm_base = @ptrCast(@alignCast(xdg_shell_ptr));
                logger.info("Registered XDG shell", .{});
            }
        }

        const surface = c.wl_compositor_create_surface(out.compositor);
        _ = c.xdg_wm_base_add_listener(out.xdg_wm_base, &.{ .ping = handle_ping }, null);

        out.xdg_surface = c.xdg_wm_base_get_xdg_surface(out.xdg_wm_base, surface).?;
        out.xdg_toplevel = c.xdg_surface_get_toplevel(out.xdg_surface).?;

        // Haha. CNAME
        const c_name = std.mem.span(@as([*c]const u8, @ptrCast(args.name)));
        c.xdg_toplevel_set_title(out.xdg_toplevel, c_name);

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

        logger.info("Initialized successfully", .{});
        return out;
    }

    pub fn close(self: Self) void {
        c.xdg_surface_destroy(self.xdg_surface);
        c.xdg_toplevel_destroy(self.xdg_toplevel);
        c.xdg_wm_base_destroy(self.xdg_wm_base);

        c.wl_display_disconnect(self.display);
        logger.info("Closed connection", .{});
    }

    /// Event loop thingy
    pub fn dispatch(self: Self) bool {
        return c.wl_display_dispatch(self.display) != 0;
    }
};

// Tests
const testing = std.testing;

test "randName generates valid names" {
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    const name = randName(random);
    try testing.expectEqual(name.len, 7);
    for (name) |char| {
        try testing.expect(char >= 'a' and char <= 'z');
    }
}

test "createShmFile returns a valid file descriptor" {
    const fd = try createShmFile();
    defer std.os.close(fd);
    try testing.expect(fd >= 0);
}

test "allocateShmFile creates a file of the correct size" {
    const size: i32 = 1024;
    const fd = try allocateShmFile(size);
    defer std.os.close(fd);

    var stat: std.os.Stat = undefined;
    try std.os.fstat(fd, &stat);
    try testing.expectEqual(stat.size, size);
}

test "WaylandDisplayServer initialization and closing" {
    const args = WaylandDisplayServerArgs{
        .name = "Test Window",
        .width = 800,
        .height = 600,
    };

    var server = WaylandDisplayServer.init(args) catch |err| {
        std.debug.print("Failed to initialize WaylandDisplayServer: {}\n", .{err});
        return;
    };
    defer server.close();

    // Verify that essential fields are initialized
    try testing.expect(server.display != null);
    try testing.expect(server.compositor != null);
    try testing.expect(server.registry != null);
    try testing.expect(server.shm != null);
    try testing.expect(server.xdg_wm_base != null);
    try testing.expect(server.xdg_surface != null);
    try testing.expect(server.xdg_toplevel != null);
}
