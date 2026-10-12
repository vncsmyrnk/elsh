const std = @import("std");
const Io = std.Io;
const process = std.process;
const mem = std.mem;
const fs = std.fs;
const debug = std.debug;
const fmt = std.fmt;
const testing = std.testing;

fn usage(arg0: []const u8) void {
    debug.print(
        \\Usage: {s} [shell]
        \\Executes each one of the defined use cases and asserts the results.
        \\
    , .{arg0});
}

fn fatalUsage(arg0: []const u8) void {
    usage(arg0);
    process.exit(1);
}

fn expectEqualFiles(io: Io, gpa: mem.Allocator, dir: Io.Dir, expected_sub_path: []const u8, actual_sub_path: []const u8) !void {
    const expected_content = try dir.readFileAlloc(io, expected_sub_path, gpa, .unlimited);
    const actual_content = try dir.readFileAlloc(io, actual_sub_path, gpa, .unlimited);
    return testing.expectEqualStrings(expected_content, actual_content);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const arg0 = args[0];
    if (args.len < 2) {
        fatalUsage(arg0);
    }

    var argv: [2][]const u8 = .{ args[1], "input" };

    var disabled_use_cases_names: std.ArrayList([]const u8) = try .initCapacity(arena, args.len);
    defer disabled_use_cases_names.deinit(arena);

    for (args) |arg| {
        if (mem.eql(u8, arg, "--help")) {
            usage(arg0);
            return;
        } else if (mem.startsWith(u8, arg, "--disable-")) {
            try disabled_use_cases_names.appendBounded(mem.cutPrefix(u8, arg, "--disable-").?);
        } else if (mem.startsWith(u8, arg, "-")) {
            fatalUsage(arg0);
        }
    }

    const cwd = Io.Dir.cwd();
    const use_cases_dir = try cwd.openDir(io, try fs.path.join(arena, &.{ "test", "posix", "use-cases" }), .{ .iterate = true });
    var iter = use_cases_dir.iterate();

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

        const stdout_file = try use_case_dir.createFile(io, "generated-stdout", .{ .truncate = true });
        const stderr_file = try use_case_dir.createFile(io, "generated-stderr", .{ .truncate = true });

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

        try use_case_dir.writeFile(io, .{ .sub_path = "generated-exit-code", .data = try fmt.allocPrint(arena, "{d}", .{term.exited}) });
    }

    iter = use_cases_dir.iterate();
    l: while (try iter.next(io)) |entry| {
        const use_case_name = entry.name;
        for (disabled_use_cases_names.items) |d| {
            if (mem.eql(u8, use_case_name, d)) {
                debug.print("SKIPPED {s}\n", .{use_case_name});
                continue :l;
            }
        }

        const use_case_dir = try iter.reader.dir.openDir(io, use_case_name, .{});
        try expectEqualFiles(io, arena, use_case_dir, "expected-stdout", "generated-stdout");
        try expectEqualFiles(io, arena, use_case_dir, "expected-stderr", "generated-stderr");
        try expectEqualFiles(io, arena, use_case_dir, "expected-exit-code", "generated-exit-code");

        debug.print("PASS {s}\n", .{use_case_name});
    }
}
