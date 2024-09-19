const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

// There is a function for this called `string_VkResult` inside
// `vulkan/vk_enum_string_helper.h`. But I cant find it. Sooo
pub fn errorToString(code: c.VkResult) []const u8 {
    const result = switch (code) {
        c.VK_SUCCESS => "Success?",
        c.VK_ERROR_OUT_OF_HOST_MEMORY => "Out of Host Memory",
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => "Out of Device Memory",
        c.VK_ERROR_INITIALIZATION_FAILED => "Initialization Failed",
        c.VK_ERROR_LAYER_NOT_PRESENT => "Layer Not Present",
        c.VK_ERROR_EXTENSION_NOT_PRESENT => "Extension Not Present",
        c.VK_ERROR_INCOMPATIBLE_DRIVER => "Incompatible Driver",
        else => "Unknown Error",
    };

    return result;
}
