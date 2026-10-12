const std = @import("std");
const Io = std.Io;
const process = std.process;
const debug = std.debug;
const linux = std.os.linux;
const posix = std.posix;
const mem = std.mem;

const builtin = @import("builtin");
const pty = @import("pty");

fn usage(arg0: []const u8) void {
    debug.print(
        \\Usage: {s} [options]
        \\Reads a sequence of lines from standard input and executes them in a pty.
        \\
    , .{arg0});
}

fn fatalUsage(arg0: []const u8) void {
    usage(arg0);
    process.exit(1);
}

fn fatal(comptime f: []const u8, args: anytype) void {
    debug.print(f, args);
    process.exit(1);
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
            fatalUsage(args[0]);
        }
    }
    const master_pt_fd = try posix.openat(std.posix.AT.FDCWD, "/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0);

    var unlock: c_int = 0;
    _ = posix.system.ioctl(
        master_pt_fd,
        posix.T.IOCSPTLCK,
        @intFromPtr(&unlock),
    );

    const pid_result: posix.pid_t = fork: {
        const rc = posix.system.fork();
        switch (posix.errno(rc)) {
            .SUCCESS => break :fork @intCast(rc),
            else => |errno| {
                fatal("errno: {d}\n", .{@intFromEnum(errno)});
                return;
            },
        }
    };

    if (pid_result == 0) {
        const slave_pt_fd = posix.system.ioctl(master_pt_fd, posix.T.IOCGPTPEER, @as(usize, 2));
        switch (posix.errno(slave_pt_fd)) {
            .SUCCESS => {},
            else => |errno| {
                fatal("errno: {d}\n", .{@intFromEnum(errno)});
                return;
            },
        }
        _ = posix.system.close(master_pt_fd);
        _ = posix.system.setsid();

        _ = posix.system.dup2(slave_pt_fd, posix.STDIN_FILENO);
        _ = posix.system.dup2(slave_pt_fd, posix.STDOUT_FILENO);
        _ = posix.system.dup2(slave_pt_fd, posix.STDERR_FILENO);

        _ = posix.system.execve("/bin/bash", &.{"bash"}, &.{});
        unreachable;
    }

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buf);
    while (stdin_reader.interface.takeDelimiterInclusive('\n')) |line| {
        _ = posix.system.write(master_pt_fd, line.ptr, line.len);
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    var child_stdout: [1024]u8 = undefined;
    while (true) {
        const bytes_read = posix.system.read(master_pt_fd, &child_stdout, child_stdout.len);
        switch (posix.errno(bytes_read)) {
            .SUCCESS => {
                _ = posix.system.write(posix.system.STDOUT_FILENO, &child_stdout, @intCast(bytes_read));
                continue;
            },
            else => break,
        }
    }

    _ = posix.system.close(master_pt_fd);
}
