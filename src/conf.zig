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
        const fz = try findZigVersion(allocator) orelse @panic("Unable to find zig executable");
        const ck = try allocator.dupe(u8, "default");
        try cfgmap.put(ck, fz);
        try save(home, cfgmap);
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

pub fn save(home: []const u8, cfgmap: std.StringHashMap([]const u8)) !void {
    var homedir = try std.fs.openDirAbsolute(home, .{});
    defer homedir.close();

    var buf: [4096]u8 = undefined;
    var it = cfgmap.iterator();

    while (it.next()) |p| {
        _ = try std.fmt.bufPrint(&buf, "{s}={s}\n", .{ p.key_ptr.*, p.value_ptr.* });
    }

    try homedir.writeFile(".zigdconfig", &buf);
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

// https://github.com/zigtools/zls/blob/adcc6862f7680a2fd079d7feba51af6ddc57a35b/src/configuration.zig#L176
pub fn findZigVersion(allocator: std.mem.Allocator) !?[]const u8 {
    const env_path = try std.process.getEnvVarOwned(allocator, "PATH");
    defer allocator.free(env_path);

    var it = std.mem.tokenize(u8, env_path, &[_]u8{std.fs.path.delimiter});
    while (it.next()) |path| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, "zig" });
        defer allocator.free(full_path);

        if (!std.fs.path.isAbsolute(full_path)) continue;

        const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
        defer file.close();
        const stat = file.stat() catch continue;
        if (stat.kind == .directory) continue;
        const lastSlash = std.mem.lastIndexOfScalar(u8, path[0 .. path.len - 1], '/') orelse @panic("Unable to find slash");
        const version = path[lastSlash + 1 ..];
        return try allocator.dupe(u8, version);
    }
    return null;
}
