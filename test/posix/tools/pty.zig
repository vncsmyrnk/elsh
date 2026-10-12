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

fn doNothingSignalHandler(_: posix.SIG, _: *const posix.siginfo_t, _: ?*anyopaque) callconv(.c) void {}

pub fn main(init: std.process.Init) !void {
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

    const master_pt_fd = posix.system.open("/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, @as(usize, 0));
    switch (posix.errno(master_pt_fd)) {
        .SUCCESS => {},
        else => |err| fatal("error: {d}", .{@intFromEnum(err)}),
    }

    var unlock: c_int = 0;
    _ = posix.system.ioctl(
        @intCast(master_pt_fd),
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
        const slave_pt_fd = posix.system.ioctl(@intCast(master_pt_fd), posix.T.IOCGPTPEER, @as(usize, 2));
        switch (posix.errno(slave_pt_fd)) {
            .SUCCESS => {},
            else => |errno| {
                fatal("errno: {d}\n", .{@intFromEnum(errno)});
                return;
            },
        }

        const slave_fd: posix.fd_t = @intCast(slave_pt_fd);
        _ = posix.system.setsid();

        var term = try std.posix.tcgetattr(slave_fd);
        term.lflag.ECHO = false;
        try std.posix.tcsetattr(slave_fd, .NOW, term);

        _ = posix.system.dup2(slave_fd, posix.STDIN_FILENO);
        _ = posix.system.dup2(slave_fd, posix.STDOUT_FILENO);
        _ = posix.system.dup2(slave_fd, posix.STDERR_FILENO);
        _ = posix.system.close(slave_fd);

        _ = posix.system.execve("/bin/bash", &.{"bash"}, &.{});
        unreachable;
    }

    const act: posix.Sigaction = .{
        .handler = .{ .sigaction = doNothingSignalHandler },
        .mask = posix.sigemptyset(),
        .flags = (posix.SA.SIGINFO | posix.SA.RESTART),
    };
    std.posix.sigaction(.INT, &act, null);

    const master_fd: posix.fd_t = @intCast(master_pt_fd);
    var fds = [_]std.posix.pollfd{
        .{
            .fd = std.posix.STDIN_FILENO,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = master_fd,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR,
            .revents = 0,
        },
    };
    var buf: [4096]u8 = undefined;

    while (true) {
        const poll_count = std.posix.poll(&fds, -1) catch |err| {
            if (err == error.Interrupted) continue;
            return err;
        };
        if (poll_count == 0) continue;

        if (fds[0].revents & std.posix.POLL.IN != 0) {
            const n = try std.posix.read(std.posix.STDIN_FILENO, &buf);
            if (n == 0) break;
            _ = std.posix.system.write(master_fd, &buf, n);
        }

        if (fds[1].revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) {
            const n = std.posix.read(master_fd, &buf) catch |err| switch (err) {
                error.InputOutput => {
                    break;
                },
                else => return err,
            };

            if (n == 0) break;
            _ = std.posix.system.write(std.posix.STDOUT_FILENO, &buf, n);
        }
    }

    _ = posix.system.close(master_fd);
}
