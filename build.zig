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

    const test_posix_runner_exe = b.addExecutable(.{
        .name = "elsh-test-posix-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/posix/tools/runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });
    const test_posix_runner_run = b.addRunArtifact(test_posix_runner_exe);
    test_posix_runner_run.addArgs(&.{"dash"});
    const test_posix_runner_step = b.step("test-posix", "Run POSIX tests");
    test_posix_runner_step.dependOn(&test_posix_runner_run.step);

    const test_posix_pty_exe = b.addExecutable(.{
        .name = "elsh-test-posix-pty",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/posix/tools/pty.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    b.installArtifact(test_posix_pty_exe);

    const test_posix_pty_run = b.addRunArtifact(test_posix_pty_exe);
    const test_posix_pty_step = b.step("pty", "");
    test_posix_pty_step.dependOn(&test_posix_pty_run.step);

    if (b.args) |args| {
        test_posix_pty_run.addArgs(args);
    }

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
