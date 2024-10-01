const std = @import("std");
const wds = @import("window/wayland.zig");
const vulkan = @import("rendering/VulkanRenderer.zig");
const l = @import("logging.zig");
const builtin = @import("builtin");

const logger = l.Logger.init(@This());

// The state of the entire program. Maybe move this to another file. Maybe not.
const State = struct {
    const Self = @This();

    displayServer: *wds.WaylandDisplayServer,
    renderer: *vulkan.VulkanRenderer,

    pub fn clean(self: *Self) void {
        logger.info("Gracefully exiting...\n", .{});
        self.renderer.clean();
        self.displayServer.close();
        logger.info("Exited", .{});
    }
};

var state: State = .{
    .displayServer = undefined,
    .renderer = undefined,
};

pub fn cleanHandle(_: i32) callconv(.C) void {
    state.clean();
    std.posix.exit(0);
}

pub fn main() !void {
    // TODO: Show more info here
    logger.info("Running a {s} build", .{if (builtin.mode == .Debug) "debug" else "release"});
    logger.info("Zig version: {}", .{builtin.zig_version});

    logger.info("Initializing Wayland...", .{});
    const displayServer = try wds.WaylandDisplayServer.init(.{ .width = 640, .height = 480, .name = "Window maybe?" });
    state.displayServer = @constCast(&displayServer);

    logger.info("Initializing Vulkan...", .{});
    state.renderer = @constCast(&try vulkan.VulkanRenderer.init());

    // Handle SIGINT (ctrl+c)
    //
    // This does not work for windows since it doesnt actually uses signals for
    // handling ctrl+c. Too bad!
    const handler: std.posix.Sigaction = .{
        .handler = .{ .handler = cleanHandle },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &handler, null) catch {
        logger.warn("Cannot handle SIGINT", .{});
    };

    logger.info("Starting event loop", .{});
    while (state.displayServer.dispatch()) {}

    state.clean();
}

comptime {
    // This is dumb. Howver the testing gods have forced my hands
    _ = @import("window/wayland.zig");
    _ = @import("rendering/debug.zig");
}
