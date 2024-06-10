const std = @import("std");
const zigdcore = @import("zigdcore.zig");
const utils = @import("utils.zig");

const stdout = std.io.getStdOut().writer();
const Command = enum {
    help,
    install,
    version,
    exists,
};

pub fn main() !void {
    var gpa = if (utils.InDebug) std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = if (utils.InDebug) gpa.allocator() else std.heap.c_allocator;
    defer _ = if (utils.InDebug) gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    std.debug.assert(args.len >= 1);

    if (args.len == 1)
        return try help_menu();

    if (std.meta.stringToEnum(Command, args[1])) |command| {
        return try switch (command) {
            .install => install(allocator, args),
            .exists => exists(allocator, args),
            .help => help_menu(),
            .version => version(),
        };
    }

    std.log.err("Unkown command entered!\n", .{});
    return try help_menu();
}

fn help_menu() !void {
    try stdout.print(
        \\> zigd ({s}) cli: Manage zigd stuff
        \\ 
        \\help - Outputs this help Menu
        \\version - Outputs zigd version
        \\install [version] - Install a zig version
        \\exists [version] - Check if a zig version is installed on the system
        \\
    , .{utils.zigd_version});
    return;
}

fn version() !void {
    try stdout.print("{s}\n", .{utils.zigd_version});
    return;
}

var user_arg: zigdcore.ZigVersion.Source = .UserArg;

fn install(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len <= 2) {
        std.log.err("Wrong Usage!\n", .{});
        try stdout.print(
            \\Usage: zigd install [version]
            \\For more help use zigd help
            \\
        , .{});
        return;
    }

    var zig_version = try zigdcore.ZigVersion.parse(allocator, args[2], &user_arg, false);
    defer zig_version.deinitIfMasterOrZigver(allocator);

    try stdout.print("Installing zig version {s}\n", .{zig_version});

    const download_url = try zigdcore.downloadUrlFromVersion(allocator, zig_version.as_string, zig_version.source == .Master);
    defer allocator.free(download_url);

    const zigd_path = try zigdcore.getZigdPath(allocator);
    defer allocator.free(zigd_path);

    try zigdcore.install_zig(allocator, download_url, zigd_path, zig_version.as_string);
}

fn exists(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len <= 2) {
        std.log.err("Wrong Usage!\n", .{});
        try stdout.print(
            \\Usage: zigd exists [version]
            \\For more help use zigd help
            \\
        , .{});
        return;
    }

    const zigd_path = try zigdcore.getZigdPath(allocator);
    defer allocator.free(zigd_path);

    var zig_version = try zigdcore.ZigVersion.parse(allocator, args[2], &user_arg, false);
    defer zig_version.deinitIfMasterOrZigver(allocator);

    const version_path = try std.fs.path.join(allocator, &.{ zigd_path, "versions", args[2] });
    defer allocator.free(version_path);

    if (try utils.isDirectory(version_path)) {
        try stdout.writeAll("Yes!\n");
    } else {
        try stdout.writeAll("No!\n");
    }
}
