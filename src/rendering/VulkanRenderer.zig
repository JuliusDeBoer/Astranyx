const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("string.h");
});
const util = @import("util.zig");
const std = @import("std");
const builtin = @import("builtin");
const debug = @import("debug.zig");

const logger = @import("../logging.zig").Logger.init(@This());

const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

// Pure guesswork. Probably missing something
const extenions = [_][*c]const u8{
    c.VK_KHR_SURFACE_EXTENSION_NAME,
    // TODO: Remove this one on release
    // c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
    "VK_KHR_wayland_surface",
};

const InstanceSettings = struct {
    debug: bool,
    extensions: [*c]const [*c]const u8,
    extension_count: u32,
};

pub const VulkanRenderer = struct {
    const Self = @This();

    instance: c.VkInstance = undefined,
    debug_messenger_handle: c.VkDebugUtilsMessengerEXT = undefined,

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
            .ppEnabledExtensionNames = @constCast(&settings.extensions).*,
            .enabledExtensionCount = settings.extension_count,
        };

        if (settings.debug) {
            create_info.enabledLayerCount = validation_layers.len;
            create_info.ppEnabledLayerNames = &validation_layers;
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

        switch (c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get instance layer properties: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        for (validation_layers) |layer_name| {
            var found = false;

            for (available_layers) |layer| {
                // NOTE: Use strcmp here because I am not cutting off the 200-ish
                // null terminators. Thanks Vulkan!
                if (c.strcmp(layer_name, &layer.layerName) == 0) {
                    logger.info("Found required layer: {s}", .{&layer.layerName});
                    found = true;
                    break;
                }
            }

            if (!found) {
                logger.warn("Could not find layer: {s}", .{layer_name});
                return false;
            }
        }

        return true;
    }

    pub fn init() !Self {
        var self = Self{};
        var enableValidationLayers = false;

        var instance_extensions = std.ArrayList([*c]const u8).init(std.heap.c_allocator);
        defer instance_extensions.deinit();
        if (builtin.mode == .Debug) {
            if (try validationLayersSupported()) {
                enableValidationLayers = true;
                try instance_extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
            } else {
                logger.warn("Cannot enable validation layers", .{});
            }
        }

        try self.createInstance(.{
            .debug = enableValidationLayers,
            .extensions = instance_extensions.items.ptr,
            .extension_count = @intCast(instance_extensions.items.len),
        });

        if (enableValidationLayers) {
            debug.registerDebugLogger(&self);
        }
        return self;
    }

    pub fn clean(self: *Self) void {
        if (self.debug_messenger_handle != undefined) {
            const vkDestroyDebugUtilsMessengerEXT: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(self.instance, "vkDestroyDebugUtilsMessengerEXT"));
            if (vkDestroyDebugUtilsMessengerEXT != null) {
                vkDestroyDebugUtilsMessengerEXT.?(self.instance, @constCast(self.debug_messenger_handle), null);
            }
        }
        c.vkDestroyInstance(self.instance, null);
        logger.info("Cleaned up", .{});
    }
};
