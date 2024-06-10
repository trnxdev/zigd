const std = @import("std");
const builtin = @import("builtin");
const tarC = @import("./C/tar.zig");

pub const cpu_arch: []const u8 = switch (builtin.cpu.arch) {
    .x86, .powerpc64le, .x86_64, .aarch64, .riscv64 => |e| @tagName(e),
    else => @compileError("Unsupported CPU Architecture"),
};
pub const os: []const u8 = switch (builtin.os.tag) {
    .linux, .macos => |e| @tagName(e),
    else => @compileError("Unsupported OS"), // Windows too
};
pub const url_platform = os ++ "-" ++ cpu_arch;
pub const archive_ext = if (builtin.os.tag == .windows) "zip" else "tar.xz"; // Maybe Windows support in future?
pub const index_url: []const u8 = "https://ziglang.org/download/index.json";
pub const download_base_url: []const u8 = "https://ziglang.org/download";
pub const download_base_master_url: []const u8 = "https://ziglang.org/builds"; // Master builds have another url for some unknown reason
pub const zigd_version = @embedFile("zigd.version");
pub const custom_env_path_key_for_zigd = "ZIGD_DIRECTORY";
pub const InDebug = builtin.mode == .Debug;

// == File System Stuff
// Note: fs.cwd().openDir is the same as fs.openDirAbsolute(), no need to check if it's absolute

pub fn isDirectory(path: []const u8) std.fs.Dir.OpenError!bool {
    const DefaultOpenFlags = std.fs.Dir.OpenDirOptions{};

    var dir = std.fs.cwd().openDir(path, DefaultOpenFlags) catch |e| switch (e) {
        std.fs.Dir.OpenError.FileNotFound, std.fs.Dir.OpenError.NotDir => {
            return false;
        },
        else => return e,
    };
    defer dir.close();

    return true;
}

pub fn isFile(path: []const u8) std.fs.File.OpenError!bool {
    const DefaultOpenFlags = std.fs.File.OpenFlags{};

    var dir = std.fs.cwd().openFile(path, DefaultOpenFlags) catch |e| switch (e) {
        std.fs.Dir.OpenError.FileNotFound, std.fs.Dir.OpenError.NotDir => {
            return false;
        },
        else => return e,
    };
    defer dir.close();

    return true;
}

pub inline fn createDirectoryIgnoreExist(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |e| switch (e) {
        std.fs.Dir.MakeError.PathAlreadyExists => return,
        else => return e,
    };
}

pub inline fn createDirectoryIfNotExist(path: []const u8) !void {
    try std.fs.cwd().makePath(path);
}

pub fn exec(allocator: std.mem.Allocator, zig_binary: []const u8, args: [][:0]u8) !std.process.Child.Term {
    var args_cleaned_up = std.ArrayList([]const u8).init(allocator);
    defer args_cleaned_up.deinit();

    try args_cleaned_up.append(zig_binary);

    for (args[1..]) |arg| {
        try args_cleaned_up.append(arg);
    }

    const argv = try args_cleaned_up.toOwnedSlice();
    defer allocator.free(argv);

    var proc = std.process.Child.init(argv, allocator);
    return try proc.spawnAndWait();
}
