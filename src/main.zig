const std = @import("std");
const wds = @import("window/wayland.zig");
const vulkan = @import("rendering/VulkanRenderer.zig");
const l = @import("logging.zig");

const logger = l.Logger.init(@This());

// The state of the entire program. Maybe move this to another file. Maybe not.
const State = struct {
    const Self = @This();

    displayServer: *wds.WaylandDisplayServer,

    pub fn clean(self: Self) void {
        logger.info("Gracefully exiting...\n", .{});
        self.displayServer.close();
    }
};
var state: State = .{ .displayServer = undefined };

pub fn cleanHandle(_: i32) callconv(.C) void {
    _ = std.io.getStdOut().write("\n") catch {};
    state.clean();
}

pub fn main() !void {
    logger.info("TODO: Show program version", .{});

    logger.info("Initializing Wayland...", .{});
    const displayServer = try wds.WaylandDisplayServer.init(.{ .width = 640, .height = 480, .name = "Window maybe?" });
    state.displayServer = @constCast(&displayServer);

    logger.info("Initializing Vulkan...", .{});
    _ = try vulkan.VulkanRenderer.init();

    // Handle SIGINT (ctrl+c)
    //
    // This does not work for windows since it doesnt actually uses signals for
    // handling ctrl+c. Too bad!
    const handler: std.posix.Sigaction = .{ .handler = .{ .handler = cleanHandle }, .mask = std.posix.empty_sigset, .flags = 0 };
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
    // _ = @import("logging.zig");
    // _ = @import("rendering/VulkanRenderer.zig");
}
