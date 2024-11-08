const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});
const logger = @import("../logging.zig").Logger.init(@This());
const vulkan = @import("VulkanRenderer.zig");
const util = @import("util.zig");

pub fn debugLogCallback(
    severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    _: c.VkDebugUtilsMessageTypeFlagsEXT,
    data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.C) c.VkBool32 {
    switch (severity) {
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => {
            logger.info("[Validation layer]: {s}", .{data.*.pMessage});
        },
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => {
            logger.warn("[Validation layer]: {s}", .{data.*.pMessage});
        },
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => {
            logger.err("[Validation layer]: {s}", .{data.*.pMessage});
        },
        else => {},
    }

    return c.VK_FALSE;
}

/// Register the debug logger for validation layers. There is no way to
/// tell if this function failed or not. So just hope it didnt
pub fn registerDebugLogger(self: *vulkan.VulkanRenderer) void {
    const debug_create_info = c.VkDebugUtilsMessengerCreateInfoEXT{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
        .pfnUserCallback = debugLogCallback,
    };

    var vkCreateDebugUtilsMessengerEXT: c.PFN_vkCreateDebugUtilsMessengerEXT = undefined;
    vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(
        @ptrCast(self.instance),
        "vkCreateDebugUtilsMessengerEXT",
    ));

    if (vkCreateDebugUtilsMessengerEXT == null) {
        logger.warn("Could not find vkCreateDebugUtilsMessengerEXT", .{});
        return;
    }

    switch (vkCreateDebugUtilsMessengerEXT.?(
        @ptrCast(self.instance),
        &debug_create_info,
        null,
        @ptrCast(&self.debug_messenger_handle),
    )) {
        c.VK_SUCCESS => {},
        else => |e| {
            logger.warn("Could not register debug messenger: {s}", .{util.errorToString(e)});
        },
    }
}

comptime {
    // Check if various vulkan macros are empty or not. If there is an error
    // it might just still work
    if (c.VKAPI_CALL.len != 0) {
        @compileError("VKAPI_CALL is not empty!");
    }
    if (c.VKAPI_ATTR.len != 0) {
        @compileError("VKAPI_ATTR is not empty!");
    }
}
