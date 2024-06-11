const std = @import("std");
const zigdcore = @import("zigdcore.zig");
const utils = @import("utils.zig");

const Command = enum {
    install,
    setup,
    exists,
    @"recache-master",
    help,
    version,
};

pub fn main() !void {
    var gpa = if (utils.InDebug) std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = if (utils.InDebug) gpa.allocator() else std.heap.c_allocator;
    defer _ = if (utils.InDebug) gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const zigd_path = try zigdcore.getZigdPath(allocator);
    defer allocator.free(zigd_path);

    try zigdcore.garbage_collect_tempdir(zigd_path);

    std.debug.assert(args.len >= 1);

    if (args.len == 1)
        return try help_menu();

    if (std.meta.stringToEnum(Command, args[1])) |command| {
        return try switch (command) {
            .install => install(allocator, args, zigd_path),
            .setup => setup(allocator, args, zigd_path),
            .exists => exists(allocator, args, zigd_path),
            .@"recache-master" => recache_master(allocator, zigd_path),
            .help => help_menu(),
            .version => version(),
        };
    }

    std.log.err("Unkown command entered!\n", .{});
    return try help_menu();
}

fn help_menu() !void {
    try std.io.getStdOut().writer().print(
        \\> zigd ({s}) cli: Manage zigd stuff
        \\ 
        \\install [version] - Install a zig version
        \\setup [version] - First time setup (creates a config and installs the version)
        \\exists [version] - Check if a zig version is installed on the system
        \\recache-master - Re-cache the master version
        \\help - Outputs this help Menu
        \\version - Outputs zigd version
        \\
    , .{utils.zigd_version});
    return;
}

fn version() !void {
    try std.io.getStdOut().writer().print("{s}\n", .{utils.zigd_version});
    return;
}

var user_arg: zigdcore.ZigVersion.Source = .UserArg;

fn install(allocator: std.mem.Allocator, args: []const []const u8, zigd_path: []const u8) !void {
    if (args.len <= 2) {
        std.log.err("Wrong Usage!\n", .{});
        try std.io.getStdOut().writer().print(
            \\Usage: zigd install [version]
            \\For more help use zigd help
            \\
        , .{});
        return;
    }

    var zig_version = try zigdcore.ZigVersion.parse(allocator, args[2], &user_arg, false, zigd_path, true);
    defer zig_version.deinitIfMightBeAllocated(allocator);

    try std.io.getStdOut().writer().print("Installing zig version {s}\n", .{zig_version});

    const download_url = try zigdcore.downloadUrlFromVersion(allocator, zig_version.as_string, zig_version.source == .Master);
    defer allocator.free(download_url);

    if (!try zigdcore.install_zig(allocator, zigd_path, download_url, zig_version)) {
        std.log.err("Installation failed!", .{});
    }

    return;
}

fn setup(allocator: std.mem.Allocator, args: []const []const u8, zigd_path: []const u8) !void {
    if (args.len <= 2) {
        std.log.err("Wrong Usage!\n", .{});
        try std.io.getStdOut().writer().print(
            \\Usage: zigd setup [version]
            \\For more help use zigd help
            \\
        , .{});
        return;
    }

    const config_path = try std.fs.path.join(allocator, &.{ zigd_path, "config" });
    defer allocator.free(config_path);

    if (try utils.isFile(config_path)) {
        o: while (true) {
            std.log.warn("A config file already exists, overwrite (y/n?)", .{});
            const byte = try std.io.getStdIn().reader().readByte();

            switch (byte) {
                'y' => break :o,
                'n' => return,
                else => continue :o,
            }
        }
    }

    var zig_version = try zigdcore.ZigVersion.parse(allocator, args[2], &user_arg, false, zigd_path, true);
    defer zig_version.deinitIfMightBeAllocated(allocator);

    if (zig_version.source == .Master) {
        o: while (true) {
            std.log.warn("It is not recommended to setup with master, are you sure you want to set master as default in the config? (y/n)", .{});
            const byte = try std.io.getStdIn().reader().readByte();

            switch (byte) {
                'y' => break :o,
                'n' => return,
                else => continue :o,
            }
        }
    }

    const download_url = try zigdcore.downloadUrlFromVersion(allocator, zig_version.as_string, zig_version.source == .Master);
    defer allocator.free(download_url);

    try std.io.getStdOut().writer().print("Installing version {s}...\n", .{zig_version});
    _ = try zigdcore.install_zig(allocator, zigd_path, download_url, zig_version);

    try std.io.getStdOut().writer().print("Creating a config...\n", .{});
    const config_file = try std.fs.createFileAbsolute(config_path, .{
        .truncate = true,
    });
    defer config_file.close();

    try config_file.writer().writeAll("# Generated by `zigd setup`, btw :)\n");
    try config_file.writer().writeAll("default=");
    switch (zig_version.source) {
        .Master => try config_file.writeAll("master"),
        else => try config_file.writeAll(zig_version.as_string),
    }
    try config_file.writer().writeByte('\n');
}

fn exists(allocator: std.mem.Allocator, args: []const []const u8, zigd_path: []const u8) !void {
    if (args.len <= 2) {
        std.log.err("Wrong Usage!\n", .{});
        try std.io.getStdOut().writer().print(
            \\Usage: zigd exists [version]
            \\For more help use zigd help
            \\
        , .{});
        return;
    }

    var zig_version = try zigdcore.ZigVersion.parse(allocator, args[2], &user_arg, false, zigd_path, true);
    defer zig_version.deinitIfMightBeAllocated(allocator);

    const version_path = try std.fs.path.join(allocator, &.{ zigd_path, "versions", zig_version.as_string });
    defer allocator.free(version_path);

    if (try utils.isDirectory(version_path)) {
        try std.io.getStdOut().writer().writeAll("Yes!\n");
    } else {
        try std.io.getStdOut().writer().writeAll("No!\n");
    }
}

fn recache_master(allocator: std.mem.Allocator, zigd_path: []const u8) !void {
    const master = try zigdcore.fetchMaster(allocator, zigd_path, false);
    defer allocator.free(master);

    const cache_path = try zigdcore.getCachePath(allocator, zigd_path);
    defer allocator.free(cache_path);

    const cache_file = try zigdcore.getCacheFile(cache_path);
    defer cache_file.close();

    try cache_file.writer().writeAll(master);
}
