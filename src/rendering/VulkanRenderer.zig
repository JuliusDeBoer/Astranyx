const l = @import("../logging.zig");
const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});
const logger = l.Logger.init(@This());

pub const VulkanRenderer = struct {
    const Self = @This();

    pub fn init() Self {
        // TODO: Tweak these versions
        const app_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Astranyx",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "No Engine",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_0,
        };

        const create_info = c.VkInstanceCreateInfo{ .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app_info };

        _ = create_info;

        return Self{};
    }
};
