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
        stdout_writer.print("({s}) INFO: ", .{self.name}) catch return;
        stdout_writer.print(fmt, args) catch return;
        stdout_writer.print("\n", .{}) catch return;
    }

    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype) void {
        stdout_writer.print("({s}) WARN: ", .{self.name}) catch return;
        stdout_writer.print(fmt, args) catch return;
        stdout_writer.print("\n", .{}) catch return;
    }

    pub fn err(self: Self, comptime fmt: []const u8, args: anytype) void {
        stderr_writer.print("({s}) ERR: ", .{self.name}) catch return;
        stderr_writer.print(fmt, args) catch return;
        stderr_writer.print("\n", .{}) catch return;
    }
};
