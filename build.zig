const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "astranyx",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();

    exe.addCSourceFile(.{ .file = b.path("c/xdg-shell-protocol.c"), .flags = &.{} });
    exe.addIncludePath(.{ .src_path = .{ .sub_path = "c", .owner = b } });

    exe.linkSystemLibrary2("wayland-client", .{ .preferred_link_mode = .static });
    exe.linkSystemLibrary2("vulkan", .{ .preferred_link_mode = .static });

    const shaders = b.step("shaders", "Compile shaders");

    const shader_output_dir = "zig-out/bin/shaders";
    std.fs.cwd().makePath(shader_output_dir) catch {};

    // Get list of shader files
    var shader_dir = std.fs.cwd().openDir("shaders", .{ .iterate = true }) catch @panic("Failed to open shaders directory");
    defer shader_dir.close();

    var it = shader_dir.iterate();
    while (it.next() catch @panic("Failed to iterate shader directory")) |entry| {
        if (entry.kind != .file) continue;

        const shader_path = b.fmt("shaders/{s}", .{entry.name});
        const output_path = b.fmt("{s}/{s}.spv", .{ shader_output_dir, entry.name });

        const compile_step = b.addSystemCommand(&.{
            "glslc",
            shader_path,
            "-o",
            output_path,
        });

        shaders.dependOn(&compile_step.step);
    }

    exe.step.dependOn(shaders);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
