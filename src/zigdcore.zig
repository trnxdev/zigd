const std = @import("std");
const tarC = @import("C/tar.zig");
const utils = @import("utils.zig");

/// Version cannot be master!
/// Returns the path to the zig binary
pub fn install_zig(allocator: std.mem.Allocator, download_url: []const u8, install_path: []const u8, version: []const u8) !void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const download_uri = try std.Uri.parse(download_url);

    var header_buffer: [4096]u8 = undefined;
    var req = try client.open(.GET, download_uri, .{
        .server_header_buffer = &header_buffer,
    });

    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok)
        return error.ResponseWasNotOk;

    const final_destination = try std.fs.path.join(allocator, &.{ install_path, "versions", version });
    defer allocator.free(final_destination);

    try utils.createDirectoryIfNotExist(final_destination);

    const data = try req.reader().readAllAlloc(allocator, 2 << 50);
    defer allocator.free(data);

    const friendly_cwd_name_ext = try std.mem.concat(allocator, u8, &.{ "zig-", utils.os, "-", utils.cpu_arch, "-", version, ".", utils.archive_ext });

    defer allocator.free(friendly_cwd_name_ext);

    const tarfile = try std.fs.cwd().createFile(friendly_cwd_name_ext, .{
        .truncate = true,
        .exclusive = false,
    });
    defer tarfile.close();
    try tarfile.writeAll(data);

    // Use std.tar.pipeToFileSystem() in the future, currently very slow
    // because it doesn't support GNU longnames or PAX headers.
    // https://imgur.com/9ZUhkHx
    _ = try tarC.extractTarXZ(friendly_cwd_name_ext);

    const the_extracted_path = try std.fs.cwd().realpathAlloc(allocator, friendly_cwd_name_ext[0 .. friendly_cwd_name_ext.len - (".".len + utils.archive_ext.len)]);
    defer allocator.free(the_extracted_path);

    if (!(try utils.isDirectory(the_extracted_path))) {
        return error.InstalledFileWasExtractedButLost___Oops;
    }

    // libarchive can't set dest path so it extracts to cwd
    // rename here moves the extracted folder to the correct path
    // (cwd)/zig-linux-x86_64-0.11.0 -> ~/.zigd/versions/0.11.0
    try std.fs.cwd().rename(the_extracted_path, final_destination);
    try std.fs.cwd().deleteFile(friendly_cwd_name_ext);
    return;
}

pub fn masterFromIndex(allocator: std.mem.Allocator) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(utils.index_url);
    var header_buffer: [4096]u8 = undefined;

    var req = try client.open(.GET, uri, .{
        .server_header_buffer = &header_buffer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
        },
    });
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    const resp = req.response;

    if (resp.status != .ok)
        return error.ResponseWasNotOk;

    const body = try req.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(body);

    const json = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer json.deinit();

    const master = json.value.object.get("master") orelse return error.MasterNotFound;
    const version = master.object.get("version") orelse return error.VersionNotFound;

    if (version != .string) {
        return error.VersionNotString;
    }

    return try allocator.dupe(u8, version.string);
}

// Caller frees the memory
pub fn downloadUrlFromVersion(allocator: std.mem.Allocator, version: []const u8, is_master: bool) ![]const u8 {
    return try if (is_master)
        std.fmt.allocPrint(allocator, utils.download_base_master_url ++ "/zig-{s}-{s}-{s}.{s}", .{ utils.os, utils.cpu_arch, version, utils.archive_ext })
    else
        std.fmt.allocPrint(allocator, utils.download_base_url ++ "/{s}/zig-{s}-{s}-{s}.{s}", .{ version, utils.os, utils.cpu_arch, version, utils.archive_ext });
}

pub const ZigVersion = struct {
    as_string: []const u8, // Never allowed to be "master"
    source: Source,

    pub const Source = union(enum) {
        UserArg, // Zigd Cli exclusive
        Zigver,
        WorkspaceVer,
        DefaultVer,
        Master: *Source,
    };

    // Handles the "master" case
    pub fn parse(allocator: std.mem.Allocator, str: []const u8, source: *Source, free_instant_if_zigver: bool) !@This() {
        var zig_version: @This() = .{
            .as_string = str,
            .source = source.*,
        };

        if (std.mem.eql(u8, zig_version.as_string, "master")) {
            if (free_instant_if_zigver and source.* == .Zigver)
                allocator.free(str);

            zig_version = .{
                .as_string = try masterFromIndex(allocator),
                .source = .{ .Master = source },
            };
        }

        return zig_version;
    }

    /// Writes with quotes!
    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) @TypeOf(writer).Error!void {
        switch (self.source) {
            .Master => {
                try writer.print("\"master\" ({s})", .{self.as_string});
            },
            else => {
                try writer.print("\"{s}\"", .{self.as_string});
            },
        }
    }

    pub fn deinitIfMasterOrZigver(self: @This(), allocator: std.mem.Allocator) void {
        switch (self.source) {
            .Master, .Zigver => allocator.free(self.as_string),
            else => {},
        }
    }
};

// Caller frees the memory
pub fn getZigdPath(allocator: std.mem.Allocator) ![]u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    var custom_zigd: bool = true;
    const zigd_directory = env_map.get(utils.custom_env_path_key_for_zigd) orelse v: {
        if (env_map.get("HOME")) |home| {
            custom_zigd = false;
            break :v try std.fs.path.join(allocator, &.{ home, ".zigd" });
        }

        std.log.err("A directory with the important zigd files could not have been found", .{});
        return error.DirNotFound;
    };
    defer if (!custom_zigd) allocator.free(zigd_directory);

    if (custom_zigd and !(try utils.isDirectory(zigd_directory))) {
        std.log.err("The zigd directory specified in the environment variable ({s}: \"{s}\") does not exist or is not a directory.", .{ utils.custom_env_path_key_for_zigd, zigd_directory });
        return error.DirNotFound;
    } else {
        try utils.createDirectoryIgnoreExist(zigd_directory);
    }

    return try allocator.dupe(u8, zigd_directory);
}
