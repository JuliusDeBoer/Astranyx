const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_wayland.h");
    @cInclude("string.h");
});
const util = @import("util.zig");
const std = @import("std");
const builtin = @import("builtin");
const debug = @import("debug.zig");
const wl = @import("../window/wayland.zig");

const logger = @import("../logging.zig").Logger.init(@This());

const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const QueueFamilyIndices = struct {
    graphics_family: u32,
    present_family: u32,
};

// Pure guesswork. Probably missing something
const instance_extenions = [_][*c]const u8{
    c.VK_KHR_SURFACE_EXTENSION_NAME,
    c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
};

const device_extensions = [_][*c]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const InstanceSettings = struct {
    debug: bool,
    extensions: [*c]const [*c]const u8,
    extension_count: u32,
};

const SwapChainDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,
};

pub const VulkanRenderer = struct {
    const Self = @This();

    wlds: *wl.WaylandDisplayServer = undefined,
    instance: c.VkInstance = undefined,
    debug_messenger_handle: c.VkDebugUtilsMessengerEXT = undefined,
    physical_device: c.VkPhysicalDevice = undefined,
    queue_family: QueueFamilyIndices = undefined,
    device: c.VkDevice = undefined,
    queue: c.VkQueue = undefined,
    surface: c.VkSurfaceKHR = undefined,
    present_queue: c.VkQueue = undefined,
    swap_chain: c.VkSwapchainKHR = undefined,

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

    fn isDeviceSuitable(self: *Self, device: *c.VkPhysicalDevice) bool {
        // var features: c.VkPhysicalDeviceFeatures = undefined;
        // c.vkGetPhysicalDeviceFeatures(device.*, &features);
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device.*, &properties);

        const extension_support = checkExtensionSupport(device);

        var swap_chain_adequate = false;
        if (extension_support) {
            const swap_chain_support: SwapChainDetails = self.querySwapChainSupport(device.*) catch return false;
            swap_chain_adequate = swap_chain_support.formats.len > 0 and
                swap_chain_support.present_modes.len > 0;
        }

        return (properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU or
            properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) and
            extension_support and
            swap_chain_adequate;
    }

    fn pickPhysicalDevice(self: *Self) !void {
        var device_count: u32 = 0;
        switch (c.vkEnumeratePhysicalDevices(self.instance, &device_count, null)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Failed to get physical devices: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        if (device_count == 0) {
            logger.err("Failed to find device with Vulkan support", .{});
            return error.VulkanError;
        }

        const devices = try std.heap.c_allocator.alloc(c.VkPhysicalDevice, device_count);
        defer std.heap.c_allocator.free(devices);

        switch (c.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Failed to get physical devices: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        var selected_device: c.VkPhysicalDevice = undefined;

        for (devices) |device| {
            // Maybe score these to pick the best one. But who cares about
            // performance anyway
            if (self.isDeviceSuitable(@constCast(&device))) {
                selected_device = device;
            }
        }

        if (selected_device == undefined) {
            logger.err("Could not get suitable device", .{});
            return error.VulkanError;
        }

        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(selected_device, &properties);

        logger.info("Chosen a suitable GPU: {s}", .{properties.deviceName});

        self.physical_device = selected_device;
    }

    fn findQueueFamilies(self: *Self) !void {
        var indecies: QueueFamilyIndices = .{
            .graphics_family = undefined,
            .present_family = undefined,
        };

        var family_count: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(self.physical_device, &family_count, null);
        const families = try std.heap.c_allocator.alloc(c.VkQueueFamilyProperties, family_count);
        defer std.heap.c_allocator.free(families);
        c.vkGetPhysicalDeviceQueueFamilyProperties(self.physical_device, &family_count, families.ptr);

        var i: u32 = 0;
        var success = false;
        for (families) |family| {
            var present_support: c.VkBool32 = undefined;
            switch (c.vkGetPhysicalDeviceSurfaceSupportKHR(self.physical_device, i, self.surface, &present_support)) {
                c.VK_SUCCESS => {
                    indecies.present_family = i;
                },
                else => |e| {
                    logger.err("Could not get physical device support: {s}", .{util.errorToString(e)});
                    return error.VulkanError;
                },
            }

            if ((family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0) {
                indecies.graphics_family = i;
                success = true;
            }
            i += 1;
        }

        if (!success) {
            logger.err("Could not get device queue family", .{});
            return error.VulkanError;
        }

        self.queue_family = indecies;
    }

    fn checkExtensionSupport(device: *c.VkPhysicalDevice) bool {
        var extension_count: u32 = undefined;

        switch (c.vkEnumerateDeviceExtensionProperties(device.*, null, &extension_count, null)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get extension properties: {s}", .{util.errorToString(e)});
                return false;
            },
        }

        const available_extensions = std.heap.c_allocator.alloc(c.VkExtensionProperties, extension_count) catch |e| {
            logger.err("Could not allocate memory for array at {}: {}", .{ @This(), e });
            return false;
        };
        defer std.heap.c_allocator.free(available_extensions);

        switch (c.vkEnumerateDeviceExtensionProperties(device.*, null, &extension_count, available_extensions.ptr)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get extension properties: {s}", .{util.errorToString(e)});
                return false;
            },
        }

        for (device_extensions) |required_ext| {
            var found = false;
            for (available_extensions) |available_ext| {
                if (c.strcmp(required_ext, &available_ext.extensionName) == 0) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    fn querySwapChainSupport(self: *Self, device: c.VkPhysicalDevice) !SwapChainDetails {
        var details = SwapChainDetails{
            .capabilities = undefined,
            .formats = undefined,
            .present_modes = undefined,
        };

        switch (c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, self.surface, &details.capabilities)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get physical durface capabilities: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        var format_count: u32 = undefined;
        switch (c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, null)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get physical surface formats: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }
        details.formats = try std.heap.c_allocator.alloc(c.VkSurfaceFormatKHR, format_count);

        // HACK(Julius): Not doing this causes a memory leak. Memory leaks are
        // bad. However. I dont care!

        // defer std.heap.c_allocator.free(details.formats);

        switch (c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, details.formats.ptr)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get physical surface formats: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        var present_mode_count: u32 = undefined;
        switch (c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, null)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get physical surface present modes: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }
        details.present_modes = try std.heap.c_allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        // HACK(Julius): Same thing here
        // defer std.heap.c_allocator.free(details.present_modes);
        switch (c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, self.surface, &present_mode_count, details.present_modes.ptr)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not get physical surface present modes: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }

        return details;
    }

    fn createLogicalDevice(self: *Self, layers: std.ArrayList([*c]const u8)) !void {
        var unique_indices = std.AutoHashMap(u32, void).init(std.heap.c_allocator);
        defer unique_indices.deinit();

        try unique_indices.put(self.queue_family.graphics_family, {});
        try unique_indices.put(self.queue_family.present_family, {});

        var queue_create_infos = try std.heap.c_allocator.alloc(c.VkDeviceQueueCreateInfo, unique_indices.count());
        defer std.heap.c_allocator.free(queue_create_infos);

        var i: usize = 0;
        var it = unique_indices.keyIterator();
        while (it.next()) |queue| {
            const queue_priority: f32 = 1;
            queue_create_infos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = queue.*,
                .queueCount = 1,
                .pQueuePriorities = &queue_priority,
            };
            i += 1;
        }

        const device_features: c.VkPhysicalDeviceFeatures = .{};

        var device_info: c.VkDeviceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = @intCast(queue_create_infos.len),
            .pQueueCreateInfos = queue_create_infos.ptr,
            .pEnabledFeatures = &device_features,
            .ppEnabledExtensionNames = &device_extensions,
            .enabledExtensionCount = device_extensions.len,
        };

        if (comptime false) {
            @compileLog("Supporting deprecated ppEnabledLayerNames in VkDeviceCreateInfo");
            logger.warn("Supporting deprecated ppEnabledLayerNames in VkDeviceCreateInfo");
            if (layers.items.len > 0) {
                logger.info("Adding {} layers to device initialization", .{layers.items.len});
                device_info.enabledLayerCount = @intCast(layers.items.len);
                device_info.ppEnabledLayerNames = layers.items.ptr;
            } else {
                device_info.ppEnabledLayerNames = 0;
            }
        }

        switch (c.vkCreateDevice(self.physical_device, &device_info, null, &self.device)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not create device: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }
    }

    fn getQueue(self: *Self) void {
        c.vkGetDeviceQueue(self.device, self.queue_family.graphics_family, 0, &self.queue);
        c.vkGetDeviceQueue(self.device, self.queue_family.present_family, 0, &self.present_queue);
    }

    fn createSurface(self: *Self) !void {
        const create_info: c.VkWaylandSurfaceCreateInfoKHR = .{
            .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
            .surface = @ptrCast(self.wlds.wl_surface),
            .display = @ptrCast(self.wlds.wl_display),
        };

        switch (c.vkCreateWaylandSurfaceKHR(self.instance, &create_info, null, &self.surface)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not create surface: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }
    }

    fn chooseSwapChainSurfaceFormat(formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
        for (formats) |format| {
            logger.info("Enumerating format {}", .{format});
            if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
                format.colorSpace == c.VK_COLORSPACE_SRGB_NONLINEAR_KHR)
            {
                return format;
            }
        }
        // Give up
        return formats[0];
    }

    fn chooseSwapChainPresentMode(present_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
        for (present_modes) |present_mode| {
            if (present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                return present_mode;
            }
        }
        // If we cant get the prefered mode. Just pick FIFO. Since its always
        // present
        return c.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn chooseSwapExtent(self: *Self, capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        return c.VkExtent2D{
            .width = std.math.clamp(self.wlds.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
            .height = std.math.clamp(self.wlds.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
        };
    }

    fn createSwapChain(self: *Self) !void {
        const support = try self.querySwapChainSupport(self.physical_device);
        const format: c.VkSurfaceFormatKHR = chooseSwapChainSurfaceFormat(support.formats);
        const present_mode = chooseSwapChainPresentMode(support.present_modes);
        const extent = self.chooseSwapExtent(support.capabilities);
        var image_count = support.capabilities.minImageCount + 1;

        if (support.capabilities.maxImageCount > 0 and image_count > support.capabilities.maxImageCount) {
            image_count = support.capabilities.maxImageCount;
        }

        const create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = self.surface,
            .minImageCount = image_count,
            .imageFormat = format.format,
            .imageColorSpace = format.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .preTransform = support.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = c.VK_TRUE,
        };

        switch (c.vkCreateSwapchainKHR(self.device, &create_info, null, &self.swap_chain)) {
            c.VK_SUCCESS => {},
            else => |e| {
                logger.err("Could not create swapchain: {s}", .{util.errorToString(e)});
                return error.VulkanError;
            },
        }
    }

    pub fn init(wlds: *wl.WaylandDisplayServer) !Self {
        var self = Self{ .wlds = wlds };
        var enableValidationLayers = false;

        var instance_extensions = std.ArrayList([*c]const u8).init(std.heap.c_allocator);
        defer instance_extensions.deinit();

        for (instance_extenions) |extension| {
            try instance_extensions.append(extension);
        }

        if (comptime builtin.mode == .Debug) {
            if (try validationLayersSupported()) {
                enableValidationLayers = true;
                try instance_extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
            } else {
                logger.err("Cannot enable validation layers", .{});
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

        try self.createSurface();
        try self.pickPhysicalDevice();
        try self.findQueueFamilies();
        try self.createLogicalDevice(instance_extensions);
        self.getQueue();
        try self.createSwapChain();

        return self;
    }

    pub fn clean(self: *Self) void {
        c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyDevice(self.device, null);
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
