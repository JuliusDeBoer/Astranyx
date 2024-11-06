const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});
const logger = @import("../logging.zig").Logger.init(@This());
const std = @import("std");

// There is a function for this called `string_VkResult` inside
// `vulkan/vk_enum_string_helper.h`. But I cant find it. Sooo
pub fn errorToString(code: c.VkResult) []const u8 {
    logger.info("Code: {}", .{code});
    const result = switch (code) {
        c.VK_SUCCESS => "Success?",
        c.VK_ERROR_OUT_OF_HOST_MEMORY => "Out of Host Memory",
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => "Out of Device Memory",
        c.VK_ERROR_INITIALIZATION_FAILED => "Initialization Failed",
        c.VK_ERROR_LAYER_NOT_PRESENT => "Layer Not Present",
        c.VK_ERROR_EXTENSION_NOT_PRESENT => "Extension Not Present",
        c.VK_ERROR_INCOMPATIBLE_DRIVER => "Incompatible Driver",
        c.VK_ERROR_INVALID_SHADER_NV => "Invalid shader",
        c.VK_ERROR_UNKNOWN => "Unknown error",
        else => "Couldnt generate error message",
    };

    return result;
}

/// Opens a file relative to the exectuable directory
pub fn openRelativeFile(path: []const u8) ![]u8 {
    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const exe_dir_path = std.fs.selfExeDirPath(&path_buf) catch |err| {
        logger.err("Failed to get executable directory: {}", .{err});
        return err;
    };

    const full_path = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ exe_dir_path, path }) catch |err| {
        logger.err("Failed to join paths: {}", .{err});
        return err;
    };
    defer std.heap.page_allocator.free(full_path);

    const file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();

    const stats = try file.stat();

    const buffer = try std.heap.page_allocator.alloc(u8, @as(usize, stats.size));
    const bytes_read = try file.readAll(buffer);
    if (bytes_read != stats.size) {
        return error.UnexpectedEOF;
    }

    return buffer;
}

pub fn getUniqueId(keys: [*]usize, len: usize) usize {
    var i: usize = 0;
    var unique = true;
    while (true) {
        i += 1;
        unique = true;

        var j: usize = 0;
        while (j < len) {
            if (keys[j] == i) {
                i += 1;
                unique = false;
                break;
            }
            j += 1;
        }

        if (unique) {
            return i;
        }
    }
}
