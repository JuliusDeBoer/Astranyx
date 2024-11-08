const std = @import("std");

pub const Logger = struct {
    const Self = @This();

    name: []const u8,
    // THIS WORKS. SHUT UP
    const stdout_writer = std.io.getStdOut().writer();
    const stderr_writer = std.io.getStdOut().writer();

    const color = struct {
        pub const bold = "\x1b[1m";
        pub const cyan = bold ++ "\x1b[36m";
        pub const yellow = bold ++ "\x1b[33m";
        pub const red = bold ++ "\x1b[31m";
        pub const grey = "\x1b[90m";
        pub const reset = "\x1b[0m";
    };

    /// Create a new `Logger`
    ///
    /// ```zig
    /// Logger.init(@This());
    /// ```
    pub fn init(target: type) Self {
        return Self{ .name = @typeName(target) };
    }

    pub fn info(self: Self, comptime fmt: []const u8, args: anytype) void {
        _ = stdout_writer.print("{s}({s}){s} {s}INFO{s}: ", .{
            color.grey,
            self.name,
            color.reset,
            color.cyan,
            color.reset,
        }) catch {};
        _ = stdout_writer.print(fmt, args) catch {};
        _ = stdout_writer.print("\n", .{}) catch {};
    }

    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype) void {
        _ = stdout_writer.print("{s}({s}){s} {s}WARN{s}: ", .{
            color.grey,
            self.name,
            color.reset,
            color.yellow,
            color.reset,
        }) catch {};
        _ = stdout_writer.print(fmt, args) catch {};
        _ = stdout_writer.print("\n", .{}) catch {};
    }

    pub fn err(self: Self, comptime fmt: []const u8, args: anytype) void {
        _ = stderr_writer.print("{s}({s}){s} {s}ERR{s}: ", .{
            color.grey,
            self.name,
            color.reset,
            color.red,
            color.reset,
        }) catch {};
        _ = stderr_writer.print(fmt, args) catch {};
        _ = stderr_writer.print("\n", .{}) catch {};
    }
};
