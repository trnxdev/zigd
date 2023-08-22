const std = @import("std");
const mode = @import("builtin").mode;
const zigd = @import("./zigd.zig");
const config = @import("./conf.zig");
const run = @import("./utils.zig").run;
const fromHome = @import("./utils.zig").fromHome;

const cmd = enum { install, @"set-default" };

fn if_free(allocator: std.mem.Allocator, needtofree: bool, ptr: []const u8) void {
    if (needtofree) {
        allocator.free(ptr);
    }
}

pub fn main() !void {
    var gpa = if (mode == .Debug) std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = if (mode == .Debug) gpa.deinit();
    const allocator = if (mode == .Debug) gpa.allocator() else std.heap.c_allocator;

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    var home = env.get("HOME") orelse return error.NoEnv;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // if it's a command for zigd & not zig, handle it here
    if (args.len > 1 and std.mem.startsWith(u8, args[1], "d-")) {
        const dcmd = std.meta.stringToEnum(cmd, args[1][2..]) orelse return error.UnrecognizedCommand;

        switch (dcmd) {
            .install => {
                if (args.len < 3) {
                    std.log.err("`zigd d-install` requires 1 argument (<Version>)", .{});
                    return error.MissingArguments;
                }
                const d = try zigd.install(allocator, args[2], home);
                allocator.free(d);
                std.debug.print("Zigd has successfully installed zig version {s}!\n", .{args[2]});
                return;
            },
            .@"set-default" => {
                if (args.len < 3) {
                    std.log.err("`zigd d-set-default` requires 1 argument (<Version>)", .{});
                    return error.MissingArguments;
                }
                try zigd.setdefault(allocator, args[2], home);
                std.debug.print("Zigd has successfully changed the default zig version {s}!\n", .{args[2]});
                return;
            },
        }
    }

    var cfg = try config.load(allocator, home);
    defer config.deinit(allocator, &cfg) catch {};

    var needtofree_ = true;

    const zig_version = std.fs.cwd().readFileAlloc(allocator, "zigd.ver", 1 << 21) catch blk: {
        needtofree_ = false;

        var absolutecwd = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(absolutecwd);

        if (cfg.contains(absolutecwd)) {
            break :blk cfg.get(absolutecwd) orelse unreachable;
        }

        if (try recursiveW(absolutecwd, &cfg)) |u| {
            break :blk u;
        }

        if (cfg.contains("default")) {
            break :blk cfg.get("default") orelse unreachable;
        }

        @panic("No default/workspace version set in config file, and no zigd.ver file found in current directory.");
    };

    defer if_free(allocator, needtofree_, zig_version);

    const zig_binary = try try_get_bin: {
        var zig_binary_0 = try std.fs.path.join(allocator, &.{ home, ".zigd", "versions", zig_version });
        defer allocator.free(zig_binary_0);
        var zig_binary_1 = std.fs.openDirAbsolute(zig_binary_0, .{}) catch {
            std.debug.print("Did not find zig binary in zigd cache, installing...\n", .{});
            const bin = try zigd.install(allocator, zig_version, home);
            break :try_get_bin bin;
        };
        var zig_binary_a = zig_binary_1.realpathAlloc(allocator, "zig");
        zig_binary_1.close();
        break :try_get_bin zig_binary_a;
    };

    defer allocator.free(zig_binary);

    const term = try exec(allocator, zig_binary, args);
    std.os.exit(term.Exited);
}

fn exec(allocator: std.mem.Allocator, zig_binary: []const u8, args: [][:0]u8) !std.ChildProcess.Term {
    var nargs = std.ArrayList([]const u8).init(allocator);
    defer nargs.deinit();
    try nargs.append(zig_binary);

    for (args[1..]) |arg| {
        try nargs.append(arg);
    }

    var naargs = try nargs.toOwnedSlice();
    defer allocator.free(naargs);
    return try run(allocator, naargs);
}

// if user is in /home/john/dummy/x and there is a entry for /home/john/dummy/ in the config file,
// then return the version for /home/john/dummy/
fn recursiveW(absolute_: []const u8, cfg: *std.StringHashMap([]const u8)) !?[]const u8 {
    var absolute = absolute_;
    var cfg_ = cfg;

    while (true) {
        if (cfg_.contains(absolute)) {
            return cfg_.get(absolute) orelse unreachable;
        }

        var last_slash = std.mem.lastIndexOf(u8, absolute, "/");

        if (last_slash == null)
            return null;

        absolute = absolute[0..last_slash.?];
    }
}
