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

    // TODO(Julius): Make this its own error maybe
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

// NOTE(Julius): This is horrible! I hate it! It also might should maybe could
// be a mutex.
var registryItems: [64]RegistryItem = undefined;
// NOTE(Julius): This one might even be worse
var registryItemsCount: u6 = 0;

const WaylandDisplayServerArgs = struct { name: []const u8, width: i32, height: i32 };

/// Easily create a wayland window
pub const WaylandDisplayServer = struct {
    const Self = @This();
    const logger = l.Logger.init(Self);

    width: u32 = 0,
    height: u32 = 0,

    wl_display: *c.struct_wl_display = undefined,
    wl_compositor: *c.struct_wl_compositor = undefined,
    wl_registry: *c.wl_registry = undefined,
    wl_shm: *c.wl_shm = undefined,
    wl_surface: *c.struct_wl_surface = undefined,
    xdg_wm_base: *c.xdg_wm_base = undefined,
    xdg_surface: *c.xdg_surface = undefined,
    xdg_toplevel: *c.xdg_toplevel = undefined,

    pub fn registry_handle_global(
        data: ?*anyopaque,
        registry: ?*c.struct_wl_registry,
        name: u32,
        interface: [*c]const u8,
        version: u32,
    ) callconv(.C) void {
        _ = registry;
        _ = data;

        const interface_string = std.mem.span(@as([*:0]const u8, @ptrCast(interface)));
        const item = RegistryItem{ .name = name, .interface = interface_string, .version = version };
        registryItems[registryItemsCount] = item;
        registryItemsCount += 1;
    }

    pub fn registry_handle_global_remove(
        data: ?*anyopaque,
        registry: ?*c.wl_registry,
        name: u32,
    ) callconv(.C) void {
        _ = registry;
        _ = data;
        _ = name;
        logger.warn("TODO: Handle removing from registry", .{});
    }

    // NOTE(Julius): I dont know if this only handles ping or other things too.
    pub fn handle_ping(_: ?*anyopaque, base: ?*c.struct_xdg_wm_base, id: u32) callconv(.C) void {
        c.xdg_wm_base_pong(base, id);
    }

    pub fn init(args: WaylandDisplayServerArgs) !Self {
        var self = Self{
            .width = @intCast(args.width),
            .height = @intCast(args.height),
        };
        const display = c.wl_display_connect(null);

        {
            if (display == null) {
                logger.err("Could not get display", .{});
                return error.WaylandError;
            }
            self.wl_display = display.?;
        }

        self.wl_registry = c.wl_display_get_registry(self.wl_display).?;

        const registry_listener: c.wl_registry_listener = .{
            .global = registry_handle_global,
            .global_remove = registry_handle_global_remove,
        };
        _ = c.wl_registry_add_listener(self.wl_registry, &registry_listener, null);

        if (c.wl_display_roundtrip(self.wl_display) == -1) {
            logger.err("wl_display_roundtrip failed. Cowardly exiting...", .{});
            return error.WaylandError;
        }

        // This will cause a segvault when one or more do not get registered.
        // Time to not think about that.
        for (&registryItems) |item| {
            if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.wl_compositor_interface.name))))) {
                const compositor_ptr = c.wl_registry_bind(
                    self.wl_registry,
                    item.name,
                    &c.wl_compositor_interface,
                    item.version,
                );
                self.wl_compositor = @ptrCast(@alignCast(compositor_ptr));
                logger.info("Registered compositor", .{});
            } else if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.wl_shm_interface.name))))) {
                const shm_ptr = c.wl_registry_bind(
                    self.wl_registry,
                    item.name,
                    &c.wl_shm_interface,
                    item.version,
                );
                self.wl_shm = @ptrCast(@alignCast(shm_ptr));
                logger.info("Registered SHM", .{});
            } else if (std.mem.eql(u8, item.interface, std.mem.span(@as([*:0]const u8, @ptrCast(c.xdg_wm_base_interface.name))))) {
                const xdg_shell_ptr = c.wl_registry_bind(
                    self.wl_registry,
                    item.name,
                    &c.xdg_wm_base_interface,
                    item.version,
                );
                self.xdg_wm_base = @ptrCast(@alignCast(xdg_shell_ptr));
                logger.info("Registered XDG shell", .{});
            }
        }

        self.wl_surface = c.wl_compositor_create_surface(self.wl_compositor).?;
        _ = c.xdg_wm_base_add_listener(self.xdg_wm_base, &.{ .ping = handle_ping }, null);

        self.xdg_surface = c.xdg_wm_base_get_xdg_surface(self.xdg_wm_base, self.wl_surface).?;
        self.xdg_toplevel = c.xdg_surface_get_toplevel(self.xdg_surface).?;

        // NOTE(Julius) Haha. CNAME
        const c_name = std.mem.span(@as([*c]const u8, @ptrCast(args.name)));
        c.xdg_toplevel_set_title(self.xdg_toplevel, c_name);

        const stride = args.width * 4;
        const shm_pool_size: usize = @as(usize, @intCast(args.height * stride * 2));

        const fd = try allocateShmFile(@intCast(shm_pool_size));
        const pool_data = std.c.mmap(null, shm_pool_size, std.c.PROT.READ | std.c.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);
        const pool = c.wl_shm_create_pool(self.wl_shm, fd, @intCast(shm_pool_size)).?;

        const index = 0;
        const offset = args.height * stride * index;

        const buffer = c.wl_shm_pool_create_buffer(pool, offset, args.width, args.height, stride, c.WL_SHM_FORMAT_XRGB8888).?;

        _ = pool_data;

        c.wl_surface_attach(self.wl_surface, buffer, 0, 0);
        c.wl_surface_damage(self.wl_surface, 0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
        c.wl_surface_commit(self.wl_surface);

        logger.info("Initialized successfully", .{});
        return self;
    }

    pub fn close(self: Self) void {
        c.xdg_toplevel_destroy(self.xdg_toplevel);
        c.xdg_surface_destroy(self.xdg_surface);
        c.wl_surface_destroy(self.wl_surface);
        c.xdg_wm_base_destroy(self.xdg_wm_base);
        c.wl_compositor_destroy(self.wl_compositor);
        c.wl_registry_destroy(self.wl_registry);
        c.wl_display_disconnect(self.wl_display);

        logger.info("Closed connection", .{});
    }

    /// Event loop thingy
    pub fn dispatch(self: Self) bool {
        return c.wl_display_dispatch(self.wl_display) != -1;
    }
};

test "randName generates random name" {
    const seed: u64 = 42;
    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();

    const name1 = randName(random);
    const name2 = randName(random);

    try std.testing.expect(name1.len == 7);
    try std.testing.expect(name2.len == 7);
    try std.testing.expect(!std.mem.eql(u8, &name1, &name2));

    for (name1) |char| {
        try std.testing.expect(char >= 'a' and char <= 'z');
    }
    for (name2) |char| {
        try std.testing.expect(char >= 'a' and char <= 'z');
    }
}
