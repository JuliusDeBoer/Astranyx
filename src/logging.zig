const std = @import("std");

pub const Logger = struct {
    const Self = @This();
    name: []const u8,
    // THIS WORKS. SHUT UP
    writer: @TypeOf(std.io.getStdOut().writer()),

    pub fn init(target: ?type) Self {
        if (target == null) {
            return Self{ .name = "global", .writer = std.io.getStdOut().writer() };
        } else {
            return Self{ .name = @typeName(target.?), .writer = std.io.getStdOut().writer() };
        }
    }

    pub fn info(self: Self, comptime fmt: []const u8, args: anytype) void {
        self.writer.print("({s}) INFO: ", .{self.name}) catch return;
        self.writer.print(fmt, args) catch return;
        self.writer.print("\n", .{}) catch return;
    }

    pub fn warn(self: Self, comptime fmt: []const u8, args: anytype) void {
        self.writer.print("({s}) WARN: ", .{self.name}) catch return;
        self.writer.print(fmt, args) catch return;
        self.writer.print("\n", .{}) catch return;
    }

    pub fn err(self: Self, comptime fmt: []const u8, args: anytype) void {
        self.writer.print("({s}) ERR: ", .{self.name}) catch return;
        self.writer.print(fmt, args) catch return;
        self.writer.print("\n", .{}) catch return;
    }
};
