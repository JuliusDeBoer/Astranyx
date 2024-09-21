const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});
const util = @import("util.zig");
const std = @import("std");
const builtin = @import("builtin");

const logger = @import("../logging.zig").Logger.init(@This());

const validationLayers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const InstanceSettings = struct {
    enableValidationLayers: bool,
};

pub const VulkanRenderer = struct {
    const Self = @This();

    instance: c.VkInstance = undefined,

    fn createInstance(self: *Self, settings: InstanceSettings) !void {
        // TODO: Tweak these versions
        const app_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Astranyx",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "No Engine",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_0,
        };

        var create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pApplicationInfo = &app_info,
        };

        if (settings.enableValidationLayers) {
            create_info.enabledLayerCount = validationLayers.len;
            create_info.ppEnabledLayerNames = &validationLayers;
        } else {
            create_info.enabledLayerCount = 0;
        }

        switch (c.vkCreateInstance(&create_info, null, &self.instance)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not create Vulkan instance: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        var extension_count: u32 = 0;
        switch (c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get instance extension count: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        const extensions = try std.heap.c_allocator.alloc(c.VkExtensionProperties, extension_count);
        defer std.heap.c_allocator.free(extensions);

        switch (c.vkEnumerateInstanceExtensionProperties(null, &extension_count, extensions.ptr)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get instance extension properties: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        logger.info("Found {} extensions", .{extension_count});
    }

    fn validationLayersSupported() !bool {
        var layer_count: u32 = 0;
        switch (c.vkEnumerateInstanceLayerProperties(&layer_count, null)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get instance layer properties: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        const available_layers = try std.heap.c_allocator.alloc(c.VkLayerProperties, layer_count);
        defer std.heap.c_allocator.free(available_layers);

        // SIGSEGV HERE!
        switch (c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get instance layer properties: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        for (validationLayers) |layerName| {
            var found = false;

            for (available_layers) |layer| {
                if (std.mem.eql(
                    u8,
                    std.mem.span(@as([*:0]const u8, @ptrCast(layerName))),
                    &layer.layerName,
                )) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                logger.warn("Could not find layer: {s}", .{layerName});
                return false;
            }
        }

        return true;
    }

    fn registerValidationLayers(self: *Self) void {
        _ = self;
    }

    pub fn init() !Self {
        var self = Self{};
        var enableValidationLayers = false;

        if (builtin.mode == .Debug) {
            if (try validationLayersSupported()) {
                enableValidationLayers = true;
            } else {
                logger.warn("Cannot enable validation layers", .{});
            }
        }

        try createInstance(&self, .{ .enableValidationLayers = enableValidationLayers });

        if (enableValidationLayers) {
            registerValidationLayers(&self);
        }
        return self;
    }

    pub fn clean(self: Self) void {
        c.vkDestroyInstance(self.instance, null);
        logger.info("Cleand up", .{});
    }
};
