const std = @import("std");
const mode = @import("builtin").mode;
const zigd = @import("./zigd.zig");

const run = @import("./utils.zig").run;
const fromHome = @import("./utils.zig").fromHome;

const cmd = enum { install };

pub fn main() !void {
    var gpa = if (mode == .Debug) std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = if (mode == .Debug) gpa.deinit();
    const allocator = if (mode == .Debug) gpa.allocator() else std.heap.c_allocator;

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    var home = env.get("HOME") orelse unreachable;

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
        }
    }

    const zig_version = std.fs.cwd().readFileAlloc(allocator, "zigd.ver", 1 << 21) catch {
        std.debug.print("Did not find zigd.ver in current directory, exiting...\n", .{});
        return;
    };
    defer allocator.free(zig_version);

    const zig_binary = try try_get_bin: {
        var zig_binary_0 = try fromHome(home, "zig");
        var zig_binary_1 = zig_binary_0.openDir(zig_version, .{}) catch {
            std.debug.print("Did not find zig binary in zigd cache, installing...\n", .{});
            const bin = try zigd.install(allocator, zig_version, home);
            break :try_get_bin bin;
        };
        var zig_binary_a = zig_binary_1.realpathAlloc(allocator, "zig");
        zig_binary_1.close();
        zig_binary_0.close();
        break :try_get_bin zig_binary_a;
    };

    defer allocator.free(zig_binary);

    var nargs = std.ArrayList([]const u8).init(allocator);
    defer nargs.deinit();
    try nargs.append(zig_binary);

    var i: usize = 0;

    for (args) |arg| {
        i += 1;

        if (i == 1)
            continue;

        try nargs.append(arg);
    }

    var naargs = try nargs.toOwnedSlice();
    defer allocator.free(naargs);
    _ = try run(allocator, naargs);
}
