const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const benchmark = b.option(bool, "benchmark", "Run benchmarks?") orelse true;
    const options = b.addOptions();
    options.addOption(bool, "benchmark", benchmark);

    const logger = b.dependency("logger", .{
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("benchmark", .{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{.{ .name = "logger", .module = logger.module("logger") }},
    });

    // Lib
    const lib = b.addStaticLibrary(.{
        .name = "benchmark",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("logger", logger.module("logger"));
    b.installArtifact(lib);

    // Unit Testing
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("logger", logger.module("logger"));
    lib_unit_tests.root_module.addOptions("opts", options);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
