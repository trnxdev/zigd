const std = @import("std");
const builtin = @import("builtin");
const run = @import("./utils.zig").run;
const fromHome = @import("./utils.zig").fromHome;

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

    if (req.response.status != .ok) {
        @panic("Response was not ok!");
    }

    var zigdir = try fromHome(home, "zig");

    const data = try req.reader().readAllAlloc(allocator, 2 << 50);
    defer allocator.free(data);

    var downloaddir = try fromHome(home, "Downloads");

    zigdir.makeDir(version) catch {
        std.debug.print("Zig version already exists, if you wish to reinstall it, remove the directory first\nIf that's not the case, well talk about it in Github Issues or smthn.", .{});
        return std.process.exit(0);
    };

    const zigstr = try zigdir.realpathAlloc(allocator, version);
    defer allocator.free(zigstr);

    const friendlyname = try std.mem.concat(allocator, u8, &.{ "zigd-", os, "-", arch, "-", version, ".", archive_ext });
    defer allocator.free(friendlyname);

    try downloaddir.writeFile(friendlyname, data);

    const fpstr = try downloaddir.realpathAlloc(allocator, friendlyname);
    defer allocator.free(fpstr);

    _ = try run(allocator, &[_][]const u8{ "tar", "xf", fpstr, "-C", zigstr, "--strip-components", "1" });

    var _binpath = try zigdir.openDir(version, .{});
    const binpath = try _binpath.realpathAlloc(allocator, "zig");
    _binpath.close();
    return binpath;
}
