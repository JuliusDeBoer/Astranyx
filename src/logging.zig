const std = @import("std");

pub const Logger = struct {
    const Self = @This();

    name: []const u8,
    // THIS WORKS. SHUT UP
    const stdout_writer = std.io.getStdOut().writer();
    const stderr_writer = std.io.getStdOut().writer();

    /// Create a new `Logger`
    ///
    /// ```zig
    /// Logger.init(@This());
    /// ```
    pub fn init(target: type) Self {
        return Self{ .name = @typeName(target) };
    }

    pub fn info(self: Self, comptime fmt: []const u8, args: anytype) void {
        _ = stdout_writer.print("({s}) INFO: ", .{self.name}) catch {};
        _ = stdout_writer.print(fmt, args) catch {};
        _ = stdout_writer.print("\n", .{}) catch {};
    }

    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype) void {
        _ = stdout_writer.print("({s}) WARN: ", .{self.name}) catch {};
        _ = stdout_writer.print(fmt, args) catch {};
        _ = stdout_writer.print("\n", .{}) catch {};
    }

    pub fn err(self: Self, comptime fmt: []const u8, args: anytype) void {
        _ = stderr_writer.print("({s}) ERR: ", .{self.name}) catch {};
        _ = stderr_writer.print(fmt, args) catch {};
        _ = stderr_writer.print("\n", .{}) catch {};
    }
};
