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
const math = @import("../math.zig");

const logger = @import("../logging.zig").Logger.init(@This());

const MAX_FRAMES_IN_FLIGHT = 2;
const VSYNC = true;

const validation_layers = [_][*c]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const QueueFamilyIndices = struct {
    graphics_family: u32,
    present_family: u32,
};

const instance_extenions = [_][*c]const u8{
    c.VK_KHR_SURFACE_EXTENSION_NAME,
    c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
};

const device_extensions = [_][*c]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const Vertex = struct {
    const Self = @This();

    pos: math.Vec2 = math.Vec2.empty(),
    color: math.Vec3 = math.Vec3.empty(),

    pub fn getBindingDescription() c.VkVertexInputBindingDescription {
        return c.VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Self),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn getAttributeDescriptions() []const c.VkVertexInputAttributeDescription {
        return &[_]c.VkVertexInputAttributeDescription{
            c.VkVertexInputAttributeDescription{
                .binding = 0,
                .location = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Self, "pos"),
            },
            c.VkVertexInputAttributeDescription{
                .binding = 0,
                .location = 1,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Self, "color"),
            },
        };
    }
};

const vertices: []const Vertex = &[_]Vertex{
    Vertex{ .pos = .{ .x = -0.5, .y = -0.5 }, .color = .{ .x = 1, .y = 0, .z = 0 } },
    Vertex{ .pos = .{ .x = 0.5, .y = 0.5 }, .color = .{ .x = 0, .y = 1, .z = 0 } },
    Vertex{ .pos = .{ .x = -0.5, .y = 0.5 }, .color = .{ .x = 0, .y = 0, .z = 1 } },

    Vertex{ .pos = .{ .x = -0.5, .y = -0.5 }, .color = .{ .x = 0, .y = 0, .z = 1 } },
    Vertex{ .pos = .{ .x = 0.5, .y = -0.5 }, .color = .{ .x = 0, .y = 1, .z = 0 } },
    Vertex{ .pos = .{ .x = 0.5, .y = 0.5 }, .color = .{ .x = 1, .y = 0, .z = 0 } },
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

/// Takes in a `VkResult `and prints an error message and returns an error if the result is not
/// `VK_SUCCES`
fn checkVulkanError(result: c.VkResult, msg: []const u8) !void {
    if (result != c.VK_SUCCESS) {
        logger.err("{s}: {s}", .{ msg, util.errorToString(result) });
        return error.VulkanError;
    }
}

pub const VulkanRenderer = struct {
    const Self = @This();

    instance: c.VkInstance = undefined,
    device: c.VkDevice = undefined,
    physical_device: c.VkPhysicalDevice = undefined,

    queue: c.VkQueue = undefined,
    present_queue: c.VkQueue = undefined,
    queue_family: QueueFamilyIndices = undefined,

    wlds: *wl.WaylandDisplayServer = undefined,
    surface: c.VkSurfaceKHR = undefined,

    swap_chain: c.VkSwapchainKHR = undefined,
    swap_chain_images: std.ArrayList(c.VkImage) = undefined,
    swap_chain_image_views: std.ArrayList(c.VkImageView) = undefined,
    swap_chain_image_format: c.VkSurfaceFormatKHR = undefined,
    swap_chain_extent: c.VkExtent2D = undefined,
    swap_chain_framebuffers: std.ArrayList(c.VkFramebuffer) = undefined,

    debug_messenger_handle: c.VkDebugUtilsMessengerEXT = undefined,

    shaders: std.AutoHashMap(usize, c.VkShaderModule) = undefined,
    shader_stages: std.ArrayList(c.VkPipelineShaderStageCreateInfo) = undefined,
    vert_shader: usize = undefined,
    frag_shader: usize = undefined,

    pipeline_layout: c.VkPipelineLayout = undefined,
    render_pass: c.VkRenderPass = undefined,
    graphics_pipeline: c.VkPipeline = undefined,
    command_pool: c.VkCommandPool = undefined,
    command_buffers: [MAX_FRAMES_IN_FLIGHT]c.VkCommandBuffer = undefined,

    image_available_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined,
    render_finished_semaphores: [MAX_FRAMES_IN_FLIGHT]c.VkSemaphore = undefined,
    in_flight_fences: [MAX_FRAMES_IN_FLIGHT]c.VkFence = undefined,

    vertex_buffer: c.VkBuffer = undefined,
    vertex_buffer_memory: c.VkDeviceMemory = undefined,

    current_frame: u32 = 0,
    initialized: bool = false,

    fn createInstance(self: *Self, settings: InstanceSettings) !void {
        // TODO(Julius): Tweak these versions
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

        try checkVulkanError(
            c.vkCreateInstance(&create_info, null, &self.instance),
            "Could not create Vulkan instance",
        );

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

        try checkVulkanError(
            c.vkEnumerateInstanceExtensionProperties(null, &extension_count, extensions.ptr),
            "Could not get instance extension properties",
        );

        logger.info("Found {} extensions", .{extension_count});
    }

    fn validationLayersSupported() !bool {
        var layer_count: u32 = 0;

        try checkVulkanError(
            c.vkEnumerateInstanceLayerProperties(&layer_count, null),
            "Could not get instance layer properties",
        );

        const available_layers = try std.heap.c_allocator.alloc(c.VkLayerProperties, layer_count);
        defer std.heap.c_allocator.free(available_layers);

        try checkVulkanError(
            c.vkEnumerateInstanceLayerProperties(&layer_count, available_layers.ptr),
            "Could not get instance layer properties",
        );

        for (validation_layers) |layer_name| {
            var found = false;

            for (available_layers) |layer| {
                // NOTE(Julius): Use strcmp here because I am not cutting off
                // the 200-ish null terminators. Thanks Vulkan!
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

        // NOTE(Julius): Device is null here
        c.vkGetPhysicalDeviceProperties(device.*, &properties);

        const extension_support = checkExtensionSupport(device);

        var swap_chain_adequate = false;
        if (extension_support) {
            const swap_chain_support = self.querySwapChainSupport(device.*) catch return false;
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

        try checkVulkanError(
            c.vkEnumeratePhysicalDevices(self.instance, &device_count, null),
            "Failed to get physical devices",
        );

        if (device_count == 0) {
            logger.err("Failed to find device with Vulkan support", .{});
            return error.VulkanError;
        }

        const devices = try std.heap.c_allocator.alloc(c.VkPhysicalDevice, device_count);
        defer std.heap.c_allocator.free(devices);

        try checkVulkanError(
            c.vkEnumeratePhysicalDevices(self.instance, &device_count, devices.ptr),
            "Failed to get physical devices",
        );

        var selected_device: ?c.VkPhysicalDevice = null;

        for (devices) |device| {
            // NOTE(Julius): Maybe score these to pick the best one. But who
            // cares about performance anyway
            if (self.isDeviceSuitable(@constCast(&device))) {
                selected_device = device;
            }
        }

        if (selected_device == null) {
            logger.err("Could not get suitable device", .{});
            return error.VulkanError;
        }

        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(selected_device.?, &properties);

        logger.info("Chosen a suitable GPU: {s}", .{properties.deviceName});

        self.physical_device = selected_device.?;
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
        c.vkGetPhysicalDeviceQueueFamilyProperties(
            self.physical_device,
            &family_count,
            families.ptr,
        );

        var i: u32 = 0;
        var success = false;
        for (families) |family| {
            var present_support: c.VkBool32 = undefined;
            switch (c.vkGetPhysicalDeviceSurfaceSupportKHR(
                self.physical_device,
                i,
                self.surface,
                &present_support,
            )) {
                c.VK_SUCCESS => {
                    indecies.present_family = i;
                },
                else => |e| {
                    logger.err(
                        "Could not get physical device support: {s}",
                        .{util.errorToString(e)},
                    );
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

        checkVulkanError(
            c.vkEnumerateDeviceExtensionProperties(device.*, null, &extension_count, null),
            "Could not get extension properties",
        ) catch return false;

        const available_extensions = std.heap.c_allocator.alloc(
            c.VkExtensionProperties,
            extension_count,
        ) catch |e| {
            logger.err("Could not allocate memory for array at {}: {}", .{ @This(), e });
            return false;
        };
        defer std.heap.c_allocator.free(available_extensions);

        checkVulkanError(
            c.vkEnumerateDeviceExtensionProperties(
                device.*,
                null,
                &extension_count,
                available_extensions.ptr,
            ),
            "Could not get extension properties",
        ) catch return false;

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

        try checkVulkanError(
            c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
                device,
                self.surface,
                &details.capabilities,
            ),
            "Could not get physical durface capabilities",
        );

        var format_count: u32 = undefined;

        try checkVulkanError(
            c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, self.surface, &format_count, null),
            "Could not get physical surface formats",
        );
        details.formats = try std.heap.c_allocator.alloc(c.VkSurfaceFormatKHR, format_count);

        // HACK(Julius): Not doing this causes a memory leak. Memory leaks are
        // bad. However. I dont care!

        // defer std.heap.c_allocator.free(details.formats);

        try checkVulkanError(
            c.vkGetPhysicalDeviceSurfaceFormatsKHR(
                device,
                self.surface,
                &format_count,
                details.formats.ptr,
            ),
            "Could not get physical surface formats",
        );

        var present_mode_count: u32 = undefined;

        try checkVulkanError(
            c.vkGetPhysicalDeviceSurfacePresentModesKHR(
                device,
                self.surface,
                &present_mode_count,
                null,
            ),
            "Could not get physical surface present modes",
        );

        details.present_modes = try std.heap.c_allocator.alloc(
            c.VkPresentModeKHR,
            present_mode_count,
        );
        // HACK(Julius): Same thing here
        // defer std.heap.c_allocator.free(details.present_modes);

        try checkVulkanError(
            c.vkGetPhysicalDeviceSurfacePresentModesKHR(
                device,
                self.surface,
                &present_mode_count,
                details.present_modes.ptr,
            ),
            "Could not get physical surface present modes",
        );

        return details;
    }

    fn createLogicalDevice(self: *Self, layers: std.ArrayList([*c]const u8)) !void {
        var unique_indices = std.AutoHashMap(u32, void).init(std.heap.c_allocator);
        defer unique_indices.deinit();

        try unique_indices.put(self.queue_family.graphics_family, {});
        try unique_indices.put(self.queue_family.present_family, {});

        var queue_create_infos = try std.heap.c_allocator.alloc(
            c.VkDeviceQueueCreateInfo,
            unique_indices.count(),
        );
        defer std.heap.c_allocator.free(queue_create_infos);

        var i: usize = 0;
        var it = unique_indices.keyIterator();
        while (it.next()) |queue| : (i += 1) {
            const queue_priority: f32 = 1;
            queue_create_infos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = queue.*,
                .queueCount = 1,
                .pQueuePriorities = &queue_priority,
            };
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

        try checkVulkanError(
            c.vkCreateDevice(self.physical_device, &device_info, null, &self.device),
            "Could not create device",
        );
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

        try checkVulkanError(
            c.vkCreateWaylandSurfaceKHR(self.instance, &create_info, null, &self.surface),
            "Could not create surface",
        );
    }

    fn chooseSwapChainSurfaceFormat(formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
        for (formats) |format| {
            if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
                format.colorSpace == c.VK_COLORSPACE_SRGB_NONLINEAR_KHR)
            {
                return format;
            }
        }
        // NOTE(Julius): Give up
        return formats[0];
    }

    fn chooseSwapChainPresentMode(present_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
        if (VSYNC) return c.VK_PRESENT_MODE_FIFO_KHR;

        for (present_modes) |present_mode| {
            if (present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                return present_mode;
            }
        }
        // NOTE(Julius): If we cant get the prefered mode. Just pick FIFO.
        // Since its always present
        return c.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn chooseSwapExtent(self: *Self, capabilities: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        if (capabilities.currentExtent.width != std.math.maxInt(u32)) {
            return capabilities.currentExtent;
        }

        return c.VkExtent2D{
            .width = std.math.clamp(
                self.wlds.width,
                capabilities.minImageExtent.width,
                capabilities.maxImageExtent.width,
            ),
            .height = std.math.clamp(
                self.wlds.height,
                capabilities.minImageExtent.height,
                capabilities.maxImageExtent.height,
            ),
        };
    }

    fn createSwapChain(self: *Self) !void {
        const support = try self.querySwapChainSupport(self.physical_device);
        const format: c.VkSurfaceFormatKHR = chooseSwapChainSurfaceFormat(support.formats);
        const present_mode = chooseSwapChainPresentMode(support.present_modes);
        const extent = self.chooseSwapExtent(support.capabilities);
        var image_count = support.capabilities.minImageCount + 1;

        if (support.capabilities.maxImageCount > 0 and
            image_count > support.capabilities.maxImageCount)
        {
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

        try checkVulkanError(
            c.vkCreateSwapchainKHR(self.device, &create_info, null, &self.swap_chain),
            "Could not create swapchain",
        );

        try checkVulkanError(
            c.vkGetSwapchainImagesKHR(self.device, self.swap_chain, &image_count, null),
            "Could not get swapchain image count",
        );

        try self.swap_chain_images.resize(image_count);

        try checkVulkanError(
            c.vkGetSwapchainImagesKHR(
                self.device,
                self.swap_chain,
                &image_count,
                self.swap_chain_images.items.ptr,
            ),
            "Could not get swapchain images",
        );

        self.swap_chain_image_format = format;
        self.swap_chain_extent = extent;
    }

    fn createImageViews(self: *Self) !void {
        try self.swap_chain_image_views.resize(self.swap_chain_images.items.len);

        var i: u32 = 0;
        for (self.swap_chain_images.items) |image| {
            const create_info = c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.swap_chain_image_format.format,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            try checkVulkanError(
                c.vkCreateImageView(
                    self.device,
                    &create_info,
                    null,
                    &self.swap_chain_image_views.items[i],
                ),
                "Could not create image view",
            );

            i += 1;
        }
    }

    /// Load in them shader
    fn loadThemShader(self: *Self, path: []const u8) !usize {
        logger.info("Loading shader: {s}", .{path});
        const code = try util.openRelativeFile(path);

        const create_info = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = @intCast(code.len),
            .pCode = @alignCast(@ptrCast(code.ptr)),
        };

        var module: c.VkShaderModule = undefined;

        try checkVulkanError(
            c.vkCreateShaderModule(self.device, &create_info, null, &module),
            "Could not create shader module",
        );

        const id = util.getUniqueId(
            self.shaders.keyIterator().items,
            self.shaders.keyIterator().len,
        );
        try self.shaders.put(id, module);

        return id;
    }

    fn createShaderStage(self: *Self) !void {
        const vert = self.shaders.get(self.vert_shader);
        if (vert == null) {
            logger.err("Missing vertex shader?", .{});
            return error.VulkanError;
        }
        const vert_create_info = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert.?,
            .pName = "main",
        };
        try self.shader_stages.append(vert_create_info);

        const frag = self.shaders.get(self.frag_shader);
        if (frag == null) {
            logger.err("Missing fragment shader?", .{});
            return error.VulkanError;
        }
        const frag_create_info = c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag.?,
            .pName = "main",
        };
        try self.shader_stages.append(frag_create_info);
    }

    fn createRenderPass(self: *Self) !void {
        const colout_attachment = c.VkAttachmentDescription{
            .format = self.swap_chain_image_format.format,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        const colour_attachment_ref = c.VkAttachmentReference{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const dependency = c.VkSubpassDependency{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        };

        const subpass = c.VkSubpassDescription{
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &colour_attachment_ref,
        };

        const render_pass_info = c.VkRenderPassCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = 1,
            .pAttachments = &colout_attachment,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &dependency,
        };

        try checkVulkanError(
            c.vkCreateRenderPass(self.device, &render_pass_info, null, &self.render_pass),
            "Could not create render pass",
        );
    }

    fn createGraphicsPipeline(self: *Self) !void {
        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swap_chain_extent.width),
            .height = @floatFromInt(self.swap_chain_extent.height),
            .minDepth = 0,
            .maxDepth = 1,
        };

        const scissor = c.VkRect2D{
            .offset = .{
                .x = 0,
                .y = 0,
            },
            .extent = self.swap_chain_extent,
        };

        const dynamic_states = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state = c.VkPipelineDynamicStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_states.len,
            .pDynamicStates = &dynamic_states,
        };

        const viewport_state = c.VkPipelineViewportStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .pViewports = &viewport,
            .scissorCount = 1,
            .pScissors = &scissor,
        };

        const attribute_descriptions = Vertex.getAttributeDescriptions();

        const vertex_input_info = c.VkPipelineVertexInputStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &Vertex.getBindingDescription(),
            .vertexAttributeDescriptionCount = @intCast(attribute_descriptions.len),
            .pVertexAttributeDescriptions = attribute_descriptions.ptr,
        };

        const input_assembly = c.VkPipelineInputAssemblyStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        };

        const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .lineWidth = 1,
            .cullMode = c.VK_CULL_MODE_BACK_BIT,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
            .depthBiasEnable = c.VK_FALSE,
        };

        const mutlisampling = c.VkPipelineMultisampleStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable = c.VK_FALSE,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        };

        const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
                c.VK_COLOR_COMPONENT_G_BIT |
                c.VK_COLOR_COMPONENT_B_BIT |
                c.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable = c.VK_FALSE,
        };

        const color_blending = c.VkPipelineColorBlendStateCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .attachmentCount = 1,
            .pAttachments = &color_blend_attachment,
        };

        const pipeline_layout_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        };

        try checkVulkanError(
            c.vkCreatePipelineLayout(
                self.device,
                &pipeline_layout_info,
                null,
                &self.pipeline_layout,
            ),
            "Could not create pipeline layout",
        );

        const pipeline_info = c.VkGraphicsPipelineCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .stageCount = @intCast(self.shader_stages.items.len),
            .pStages = self.shader_stages.items.ptr,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &input_assembly,
            .pViewportState = &viewport_state,
            .pRasterizationState = &rasterizer,
            .pMultisampleState = &mutlisampling,
            .pColorBlendState = &color_blending,
            .pDynamicState = &dynamic_state,
            .layout = self.pipeline_layout,
            .renderPass = self.render_pass,
            .subpass = 0,
        };

        try checkVulkanError(
            c.vkCreateGraphicsPipelines(
                self.device,
                null,
                1,
                &pipeline_info,
                null,
                &self.graphics_pipeline,
            ),
            "Could not create graphics pipeline",
        );
    }

    fn createFramebuffers(self: *Self) !void {
        try self.swap_chain_framebuffers.resize(self.swap_chain_image_views.items.len);

        for (self.swap_chain_image_views.items, 0..) |view, i| {
            const attachments = [_]c.VkImageView{view};

            const framebuffer_info = c.VkFramebufferCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = self.render_pass,
                .attachmentCount = attachments.len,
                .pAttachments = &attachments,
                .width = self.swap_chain_extent.width,
                .height = self.swap_chain_extent.height,
                .layers = 1,
            };

            try checkVulkanError(
                c.vkCreateFramebuffer(
                    self.device,
                    &framebuffer_info,
                    null,
                    &self.swap_chain_framebuffers.items[i],
                ),
                "Could not create framebuffer",
            );
        }
    }

    fn createCommandPool(self: *Self) !void {
        const pool_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = self.queue_family.graphics_family,
        };

        try checkVulkanError(
            c.vkCreateCommandPool(self.device, &pool_info, null, &self.command_pool),
            "Could not create command pool",
        );
    }

    fn createCommandBuffer(self: *Self) !void {
        const alloc_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = self.command_buffers.len,
        };

        try checkVulkanError(
            c.vkAllocateCommandBuffers(self.device, &alloc_info, &self.command_buffers),
            "Could not allocate command buffer",
        );
    }

    fn createSyncObjects(self: *Self) !void {
        const semaphore_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };
        const fence_info = c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            try checkVulkanError(
                c.vkCreateSemaphore(
                    self.device,
                    &semaphore_info,
                    null,
                    &self.image_available_semaphores[i],
                ),
                "Could not create semaphore",
            );
            try checkVulkanError(
                c.vkCreateSemaphore(
                    self.device,
                    &semaphore_info,
                    null,
                    &self.render_finished_semaphores[i],
                ),
                "Could not create semaphore",
            );
            try checkVulkanError(
                c.vkCreateFence(self.device, &fence_info, null, &self.in_flight_fences[i]),
                "Could not create fence",
            );
        }
    }

    fn findMemoryType(self: *Self, type_filter: u32, properties: c.VkMemoryPropertyFlags) !u32 {
        var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
        c.vkGetPhysicalDeviceMemoryProperties(self.physical_device, &memory_properties);

        for (0..memory_properties.memoryTypeCount) |i| {
            // NOTE(Juilus): Yes this isnt readable. Lets hope it does something good
            if ((type_filter & (@as(u32, 1) << @intCast(i)) != 0) and
                ((memory_properties.memoryTypes[i].propertyFlags & properties) != 0))
            {
                return @intCast(i);
            }
        }

        logger.err("Could not find suitable memory type", .{});
        return error.VulkanError;
    }

    fn createVertexBuffer(self: *Self) !void {
        const buffer_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = @sizeOf(Vertex) * vertices.len,
            .usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        };

        try checkVulkanError(
            c.vkCreateBuffer(self.device, &buffer_info, null, &self.vertex_buffer),
            "Could not create vertex buffer",
        );

        var memory_requirements = c.VkMemoryRequirements{};
        c.vkGetBufferMemoryRequirements(self.device, self.vertex_buffer, &memory_requirements);

        const alloc_info = c.VkMemoryAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = memory_requirements.size,
            .memoryTypeIndex = try self.findMemoryType(
                memory_requirements.memoryTypeBits,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            ),
        };

        try checkVulkanError(
            c.vkAllocateMemory(self.device, &alloc_info, null, &self.vertex_buffer_memory),
            "Could not allocate memory",
        );
        try checkVulkanError(
            c.vkBindBufferMemory(self.device, self.vertex_buffer, self.vertex_buffer_memory, 0),
            "Could not bind memory to buffer",
        );

        var data: ?*anyopaque = null;
        try checkVulkanError(
            c.vkMapMemory(self.device, self.vertex_buffer_memory, 0, buffer_info.size, 0, @ptrCast(&data)),
            "Could not map memory",
        );
        // TODO(Julius): I have no clue what this is
        @memcpy(
            @as([*]u8, @ptrCast(data.?))[0..buffer_info.size],
            @as([*]const u8, @ptrCast(vertices.ptr))[0..buffer_info.size],
        );
        c.vkUnmapMemory(self.device, self.vertex_buffer_memory);
    }

    pub fn init(wlds: *wl.WaylandDisplayServer) !Self {
        var self = Self{
            .wlds = wlds,
            .initialized = true,
        };

        var enableValidationLayers = false;

        self.swap_chain_images = std.ArrayList(c.VkImage).init(std.heap.c_allocator);
        self.swap_chain_image_views = std.ArrayList(c.VkImageView).init(std.heap.c_allocator);
        self.shaders = std.AutoHashMap(usize, c.VkShaderModule).init(std.heap.c_allocator);
        self.shader_stages =
            std.ArrayList(c.VkPipelineShaderStageCreateInfo).init(std.heap.c_allocator);
        self.swap_chain_framebuffers = std.ArrayList(c.VkFramebuffer).init(std.heap.c_allocator);

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

        logger.info("Creating surface", .{});
        try self.createSurface();
        logger.info("Getting physical device", .{});
        try self.pickPhysicalDevice();
        logger.info("Getting queue families", .{});
        try self.findQueueFamilies();
        logger.info("Creating logical device", .{});
        try self.createLogicalDevice(instance_extensions);
        self.getQueue();
        logger.info("Creating swapchain", .{});
        try self.createSwapChain();
        logger.info("Creating image views", .{});
        try self.createImageViews();

        logger.info("Loading required shaders", .{});
        self.vert_shader = try self.loadThemShader("shaders/basic.vert.spv");
        self.frag_shader = try self.loadThemShader("shaders/basic.frag.spv");

        logger.info("Creating shader stage", .{});
        try self.createShaderStage();
        logger.info("Creating render pass", .{});
        try self.createRenderPass();
        logger.info("Building pipeline", .{});
        try self.createGraphicsPipeline();
        logger.info("Creating framebuffers", .{});
        try self.createFramebuffers();
        logger.info("Creating command pool", .{});
        try self.createCommandPool();
        logger.info("Creating vertex buffer", .{});
        try self.createVertexBuffer();
        logger.info("Creating command buffer", .{});
        try self.createCommandBuffer();

        try self.createSyncObjects();

        return self;
    }

    pub fn clean(self: *Self) void {
        checkVulkanError(
            c.vkDeviceWaitIdle(self.device),
            "Could not wait for device to idle",
        ) catch {};

        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            c.vkDestroySemaphore(self.device, self.image_available_semaphores[i], null);
            c.vkDestroySemaphore(self.device, self.render_finished_semaphores[i], null);
            c.vkDestroyFence(self.device, self.in_flight_fences[i], null);
        }

        c.vkDestroyCommandPool(self.device, self.command_pool, null);

        c.vkDestroyBuffer(self.device, self.vertex_buffer, null);
        c.vkFreeMemory(self.device, self.vertex_buffer_memory, null);

        for (self.swap_chain_framebuffers.items) |framebuffer| {
            c.vkDestroyFramebuffer(self.device, framebuffer, null);
        }

        c.vkDestroyPipeline(self.device, self.graphics_pipeline, null);
        c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
        c.vkDestroyRenderPass(self.device, self.render_pass, null);

        var shaders = self.shaders.iterator();
        while (shaders.next()) |shader| {
            c.vkDestroyShaderModule(self.device, shader.value_ptr.*, null);
        }

        for (self.swap_chain_image_views.items) |view| {
            c.vkDestroyImageView(self.device, view, null);
        }
        c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyDevice(self.device, null);
        if (self.debug_messenger_handle != undefined) {
            const vkDestroyDebugUtilsMessengerEXT: c.PFN_vkDestroyDebugUtilsMessengerEXT =
                @ptrCast(
                c.vkGetInstanceProcAddr(self.instance, "vkDestroyDebugUtilsMessengerEXT"),
            );

            if (vkDestroyDebugUtilsMessengerEXT != null) {
                vkDestroyDebugUtilsMessengerEXT.?(
                    self.instance,
                    @constCast(self.debug_messenger_handle),
                    null,
                );
            } else {
                logger.warn("Could not destroy debug messenger", .{});
            }
        }
        c.vkDestroyInstance(self.instance, null);

        self.swap_chain_images.deinit();
        self.swap_chain_image_views.deinit();
        self.shaders.deinit();
        self.shader_stages.deinit();
        self.swap_chain_framebuffers.deinit();

        logger.info("Cleaned up", .{});
    }

    fn recordCommandBuffer(
        self: *Self,
        command_buffer: c.VkCommandBuffer,
        image_index: u32,
    ) !void {
        const begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        };

        try checkVulkanError(
            c.vkBeginCommandBuffer(command_buffer, &begin_info),
            "Failed to begin recoding the command buffer",
        );

        const clear_color = c.VkClearValue{ .color = .{ .float32 = .{ 0, 0, 0, 1 } } };
        const render_pass_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = self.render_pass,
            .framebuffer = self.swap_chain_framebuffers.items[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swap_chain_extent,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };

        const viewport = c.VkViewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swap_chain_extent.width),
            .height = @floatFromInt(self.swap_chain_extent.height),
            .minDepth = 0,
            .maxDepth = 1,
        };
        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swap_chain_extent,
        };

        var vertex_buffers = [_]c.VkBuffer{self.vertex_buffer};
        const offsets = [_]u64{0};

        c.vkCmdBeginRenderPass(command_buffer, &render_pass_info, c.VK_SUBPASS_CONTENTS_INLINE);
        c.vkCmdBindPipeline(
            command_buffer,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.graphics_pipeline,
        );
        c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);
        c.vkCmdSetScissor(command_buffer, 0, 1, &scissor);

        c.vkCmdBindPipeline(
            command_buffer,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.graphics_pipeline,
        );
        c.vkCmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);

        c.vkCmdDraw(command_buffer, vertices.len, 1, 0, 0);
        c.vkCmdEndRenderPass(command_buffer);

        try checkVulkanError(
            c.vkEndCommandBuffer(command_buffer),
            "Failed to record command buffer",
        );
    }

    pub fn draw(self: *Self) !void {
        if (!self.initialized) {
            logger.warn("Attempted to draw frame with uninitialized data", .{});
            return;
        }

        _ = c.vkWaitForFences(self.device, 1, &self.in_flight_fences[self.current_frame], c.VK_TRUE, std.math.maxInt(u32));
        _ = c.vkResetFences(self.device, 1, &self.in_flight_fences[self.current_frame]);

        var image_index: u32 = undefined;
        _ = c.vkAcquireNextImageKHR(
            self.device,
            self.swap_chain,
            std.math.maxInt(u32),
            self.image_available_semaphores[self.current_frame],
            null,
            &image_index,
        );

        _ = c.vkResetCommandBuffer(self.command_buffers[self.current_frame], 0);
        try self.recordCommandBuffer(self.command_buffers[self.current_frame], image_index);

        const wait_semaphores = [_]c.VkSemaphore{self.image_available_semaphores[self.current_frame]};
        const signal_semaphores = [_]c.VkSemaphore{self.render_finished_semaphores[self.current_frame]};
        const wait_stages =
            [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffers[self.current_frame],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        };

        try checkVulkanError(
            c.vkQueueSubmit(self.queue, 1, &submit_info, self.in_flight_fences[self.current_frame]),
            "Failed to submit draw command buffer",
        );

        const swap_chains = [_]c.VkSwapchainKHR{self.swap_chain};

        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = signal_semaphores.len,
            .pWaitSemaphores = &signal_semaphores,
            .swapchainCount = swap_chains.len,
            .pSwapchains = &swap_chains,
            .pImageIndices = &image_index,
        };

        _ = c.vkQueuePresentKHR(self.present_queue, &present_info);

        self.current_frame = (self.current_frame + 1) % MAX_FRAMES_IN_FLIGHT;
    }
};
