const std = @import("std");
const builtin = @import("builtin");
const run = @import("./utils.zig").run;
const fromHome = @import("./utils.zig").fromHome;
const tarC = @import("./C/tar.zig");
const cfg = @import("./conf.zig");

const arch = switch (builtin.cpu.arch) {
    .x86_64 => "x86_64",
    .aarch64 => "aarch64",
    .riscv64 => "riscv64",
    else => @compileError("Unsupported CPU Architecture"),
};

const os = switch (builtin.os.tag) {
    .linux => "linux",
    .macos => "macos",
    else => @compileError("Unsupported OS"), // Windows too
};

const url_platform = os ++ "-" ++ arch;
const archive_ext = if (builtin.os.tag == .windows) "zip" else "tar.xz"; // Maybe Windows support in future?

/// Do not forget to free the returned value!
pub fn install(allocator: std.mem.Allocator, version: []const u8, home: []const u8) ![]const u8 {
    const url = try std.fmt.allocPrint(allocator, "https://ziglang.org/builds/zig-{s}-{s}.{s}", .{ url_platform, version, archive_ext });
    defer allocator.free(url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);

    var headers = std.http.Headers.init(allocator);
    defer headers.deinit();

    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();

    try req.start();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok)
        @panic("Response was not ok!");

    var zigdir = try fromHome(home, "zig");
    _ = zigdir;

    const data = try req.reader().readAllAlloc(allocator, 2 << 50);
    defer allocator.free(data);

    const friendlyname = try std.mem.concat(allocator, u8, &.{ "zigd-", os, "-", arch, "-", version, ".", archive_ext });
    defer allocator.free(friendlyname);

    var downloaddir = try fromHome(home, "Downloads");
    try downloaddir.writeFile(friendlyname, data);
    defer downloaddir.close();

    const fpstr = try downloaddir.realpathAlloc(allocator, friendlyname);
    defer allocator.free(fpstr);

    _ = try tarC.extractTarXZ(fpstr);

    const fx = try std.fmt.allocPrint(allocator, "zig-" ++ url_platform ++ "-" ++ "{s}", .{version});
    defer allocator.free(fx);

    const lastp = try std.fs.path.join(allocator, &.{ home, "zig", version });
    defer allocator.free(lastp);

    // zig-linux-x86_64-0.12.0-dev.126+387b0ac4f -> 0.12.0-dev.126+387b0ac4f
    try std.fs.cwd().rename(fx, lastp);

    var _binpath = try std.fs.path.join(allocator, &.{ lastp, "zig" });
    return _binpath;
}

pub fn setdefault(allocator: std.mem.Allocator, version: []const u8, home: []const u8) !void {
    var config = try cfg.load(allocator, home);
    defer cfg.deinit(allocator, &config) catch {};

    const d = try config.getOrPut("default");

    if (!d.found_existing) {
        d.key_ptr.* = try allocator.dupe(u8, "default");
    } else {
        allocator.free(d.value_ptr.*);
    }

    d.value_ptr.* = try allocator.dupe(u8, version);

    const path = try std.fs.path.join(allocator, &.{ home, "zig" });
    defer allocator.free(path);

    var zigdir = try std.fs.openDirAbsolute(path, .{});
    defer zigdir.close();

    var z = zigdir.openDir(version, .{}) catch b: {
        std.debug.print("Did not find zig binary in zigd cache, installing...\n", .{});
        const y = try install(allocator, version, home);
        allocator.free(y);
        break :b zigdir.openDir(version, .{}) catch unreachable;
    };
    z.close();

    try cfg.save(home, config);
}
