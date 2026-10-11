const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("elsh", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "elsh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "elsh", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_posix_output_generator_exe = b.addExecutable(.{
        .name = "elsh-test-posix-output-generator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/posix/tools/expected_output_generator.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });
    const test_posix_output_generator_run = b.addRunArtifact(test_posix_output_generator_exe);
    const test_posix_output_generator_step = b.step("posix-output-generator", "Generate standard output reference for POSIX test use cases");
    test_posix_output_generator_step.dependOn(&test_posix_output_generator_run.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
