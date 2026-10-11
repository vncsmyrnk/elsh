const std = @import("std");
const Io = std.Io;
const process = std.process;
const mem = std.mem;
const fs = std.fs;
const debug = std.debug;
const fmt = std.fmt;
const defaultShell = "dash";

fn usage(arg0: []const u8) void {
    debug.print(
        \\Usage: {s} [shell]
        \\Executes each one of the defined use cases using a trusted POSIX compliant shell.
        \\
        \\Default shell: {s}
        \\
    , .{ arg0, defaultShell });
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "--help")) {
            usage(args[0]);
            return;
        } else if (mem.startsWith(u8, args[i], "-")) {
            usage(args[0]);
            std.process.exit(1);
        }
    }

    var argv: [2][]const u8 = .{ defaultShell, "input" };
    if (args.len > 1) {
        argv[0] = args[1];
    }

    const cwd = Io.Dir.cwd();
    const use_cases_dir = try cwd.openDir(io, try fs.path.join(arena, &.{ "test", "posix", "use-cases" }), .{ .iterate = true });
    var iter = use_cases_dir.iterateAssumeFirstIteration();

    while (try iter.next(io)) |entry| {
        const use_case_name = entry.name;
        const use_case_dir = try iter.reader.dir.openDir(io, use_case_name, .{});

        const use_case_output_path = try fs.path.join(arena, &.{ ".test-out", use_case_name });
        try cwd.deleteTree(io, use_case_output_path);

        const use_case_wd = try cwd.createDirPathOpen(io, use_case_output_path, .{});
        use_case_dir.copyFile("input", use_case_wd, "input", io, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    debug.print("{s}: an input file is required.\n", .{use_case_name});
                },
                else => {
                    debug.print("{s}: failed to read input file: {s}\n", .{ use_case_name, @errorName(err) });
                },
            }
            process.exit(1);
        };

        const stdout_file = try use_case_dir.createFile(io, "expected-stdout", .{ .truncate = true });
        const stderr_file = try use_case_dir.createFile(io, "expected-stderr", .{ .truncate = true });

        const spawn_options: process.SpawnOptions = .{ .argv = &argv, .cwd = .{ .dir = use_case_wd }, .stdin = .ignore, .stdout = .{ .file = stdout_file }, .stderr = .{ .file = stderr_file } };
        var child = try process.spawn(io, spawn_options);
        defer child.kill(io);

        const term = try child.wait(io);
        switch (term) {
            .exited => {},
            else => |t| {
                debug.print("{s} failed with {c}", .{ argv[0], @as(u8, @truncate(@intFromEnum(t))) });
                std.process.exit(1);
            },
        }

        try use_case_dir.writeFile(io, .{ .sub_path = "expected-exit-code", .data = try fmt.allocPrint(arena, "{d}", .{term.exited}) });
    }
}
