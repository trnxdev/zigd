const std = @import("std");
const builtin = @import("builtin");

const s = struct { default: []const u8 };

pub fn load(allocator: std.mem.Allocator, home: []const u8) !std.StringHashMap([]const u8) {
    var homedir = try std.fs.openDirAbsolute(home, .{});
    defer homedir.close();

    var existed = true;

    var cfgfile = homedir.readFileAlloc(allocator, ".zigdconfig", 1 << 21) catch |err| blk: {
        switch (err) {
            error.FileNotFound => {
                existed = false;
                break :blk "";
            },
            else => return err,
        }
    };

    if (cfgfile.len <= 3) {
        existed = false;
    }

    var cfgmap = std.StringHashMap([]const u8).init(allocator);

    if (existed) {
        try parse(allocator, cfgfile, &cfgmap);
        defer allocator.free(cfgfile);
    } else {
        var fz = try findZigVersion(allocator) orelse @panic("Unable to find zig executable");
        var fzz = try allocator.dupe(u8, fz);
        try cfgmap.put("default", fzz);
        try save(allocator, home, &cfgmap);
    }

    return cfgmap;
}

pub fn deinit(allocator: std.mem.Allocator, cfgmap: *std.StringHashMap([]const u8)) !void {
    var it = cfgmap.iterator();

    while (it.next()) |d| {
        allocator.free(d.key_ptr.*);
        allocator.free(d.value_ptr.*);
    }

    cfgmap.deinit();
}

pub fn save(allocator: std.mem.Allocator, home: []const u8, cfgmap: *std.StringHashMap([]const u8)) !void {
    var homedir = try std.fs.openDirAbsolute(home, .{});
    defer homedir.close();

    var out: []const u8 = "";
    var it = cfgmap.keyIterator();

    while (it.next()) |key_| {
        var key = key_.*;
        var value = cfgmap.get(key) orelse continue;
        var line = try std.fmt.allocPrint(allocator, "{s}={s}\n", .{ key, value });
        out = try std.mem.concat(allocator, u8, &.{ out, line });
    }

    try homedir.writeFile(".zigdconfig", out);
    return;
}

pub fn parse(allocator: std.mem.Allocator, file: []const u8, cfgmap: *std.StringHashMap([]const u8)) !void {
    var lines = std.mem.tokenize(u8, file, &[_]u8{'\n'});

    while (lines.next()) |line| {
        var indexofs = std.mem.indexOf(u8, line, "=") orelse continue;

        var key = std.mem.trim(u8, line[0..indexofs], &std.ascii.whitespace);
        var value = std.mem.trim(u8, line[indexofs + 1 ..], &std.ascii.whitespace);

        if (key[0] == '#') continue;

        var dupedkey = try allocator.dupe(u8, key);
        var dupedvalue = try allocator.dupe(u8, value);

        try cfgmap.put(dupedkey, dupedvalue);
    }
}

pub fn findZigVersion(allocator: std.mem.Allocator) !?[]const u8 {
    const env_path = std.process.getEnvVarOwned(allocator, "PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            return null;
        },
        else => return err,
    };
    defer allocator.free(env_path);

    const exe_extension = builtin.target.exeFileExt();
    const zig_exe = try std.fmt.allocPrint(allocator, "zig{s}", .{exe_extension});
    defer allocator.free(zig_exe);

    var it = std.mem.tokenize(u8, env_path, &[_]u8{std.fs.path.delimiter});
    while (it.next()) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, zig_exe });
        defer allocator.free(full_path);

        if (!std.fs.path.isAbsolute(full_path)) continue;

        const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
        defer file.close();
        const stat = file.stat() catch continue;
        if (stat.kind == .directory) continue;

        const lastSlash = std.mem.lastIndexOf(u8, path[0 .. path.len - 2], "/") orelse return null;
        const version = path[lastSlash + 1 .. path.len - 1];
        return try allocator.dupe(u8, version);
    }
    return null;
}
