const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Standard target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const mach_objc_dep = b.dependency("mach-objc", .{ .target = target, .optimize = optimize });
    const sdl3_dep = b.dependency("sdl3", .{ .target = target, .optimize = optimize });
    const zalgebra_dep = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });

    // Expose our modules
    const core = b.addModule("core", .{ .root_source_file = .{ .path = "./lib/core.zig" } });
    core.addImport("zalgebra", zalgebra_dep.module("zalgebra"));

    const ecs = b.addModule("ecs", .{ .root_source_file = .{ .path = "./lib/ecs.zig" } });
    ecs.addImport("eltlib-core", core);

    const sdl = b.addModule("sdl", .{ .root_source_file = .{ .path = "./lib/sdl.zig" } });
    sdl.addImport("eltlib-core", core);
    sdl.addImport("eltlib-ecs", ecs);
    sdl.addImport("mach-objc", mach_objc_dep.module("mach-objc"));
    sdl.addCSourceFile(.{ .file = .{ .path = "./lib/sdl/details/mainwindow.m" }, .flags = &.{"-fobjc-arc"} });
    sdl.linkLibrary(sdl3_dep.artifact("libsdl3"));

    // Main executable. Dumb rotating cube app for now.
    const exe = b.addExecutable(.{ .name = "main", .target = target, .optimize = optimize, .root_source_file = .{ .path = "src/main.zig" } });
    exe.root_module.addImport("eltlib-core", core);
    exe.root_module.addImport("eltlib-ecs", ecs);
    exe.root_module.addImport("eltlib-sdl", sdl);
    exe.root_module.addImport("mach-objc", mach_objc_dep.module("mach-objc"));
    exe.root_module.addImport("zalgebra", zalgebra_dep.module("zalgebra"));
    _ = b.installArtifact(exe);

    // Runnables
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // forward command line arguments to the executable
    if (b.args) |args| run_cmd.addArgs(args);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Format
    const fmt_include_paths = &.{ "lib", "src", "build.zig", "build.zig.zon", "vendor/sdl3" };
    const fmt_exclude_paths = &.{};
    const do_fmt = b.addFmt(.{ .paths = fmt_include_paths, .exclude_paths = fmt_exclude_paths });
    b.step("fmt", "Modify source files in place to have conforming formatting")
        .dependOn(&do_fmt.step);

    // Format test
    const fmt_test = b.addFmt(.{ .paths = fmt_include_paths, .exclude_paths = fmt_exclude_paths, .check = true });
    b.step("test-fmt", "Check source files having conforming formatting").dependOn(&fmt_test.step);

    // Library and application unit tests
    const lib_unit_tests = b.addTest(.{ .name = "library tests", .root_source_file = .{ .path = "lib/lib.zig" }, .target = target, .optimize = optimize });
    lib_unit_tests.root_module.addImport("eltlib-core", core);
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{ .name = "main executable tests", .root_source_file = .{ .path = "src/main.zig" }, .target = target, .optimize = optimize });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
