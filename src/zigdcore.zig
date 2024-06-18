const std = @import("std");
const utils = @import("utils.zig");

pub const PathBuf = [std.fs.MAX_PATH_BYTES]u8;

pub const TempByZigd = "tmp";
pub const CacheByZigd = "cached_master";
pub const VersionsByZigd = "versions";

/// Version cannot be master!
/// Returns a bool if it installed/reinstalled zig
pub fn install_zig(allocator: std.mem.Allocator, zigd_path: []const u8, download_url: []const u8, zig_version: ZigVersion) !bool {
    var final_dest_buf: PathBuf = undefined;
    const final_destination = utils.join_path(&final_dest_buf, &.{ zigd_path, VersionsByZigd, zig_version.as_string });

    if (try utils.isDirectory(final_destination)) {
        o: while (true) {
            std.log.warn("Version {} is already installed on your system! Re-install? (y/n)", .{zig_version});
            const byte = try std.io.getStdIn().reader().readByte();

            switch (byte) {
                'y' => {
                    try std.fs.deleteTreeAbsolute(final_destination);
                    break :o;
                },
                'n' => return false,
                else => continue :o,
            }
        }
    }

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

    if (req.response.status != .ok) {
        std.log.err(
            \\
            \\Fetching the version failed!
            \\Does the version still exist in zig builds?
            \\Is the version correct?
            \\Response Code: {s} {d}
        , .{ req.response.status.phrase() orelse "???", req.response.status });
        return error.ResponseWasNotOk;
    }

    var temp_dir_buf: PathBuf = undefined;
    const temp_dir_path = utils.join_path(&temp_dir_buf, &.{ zigd_path, "tmp" });

    try utils.createDirectoryIgnoreExist(temp_dir_path);

    var temp_dir = try std.fs.openDirAbsolute(temp_dir_path, .{});
    defer temp_dir.close();

    const temp_name = try std.fmt.allocPrint(allocator, "DO_NOT_MODIFY_zigd-{d}", .{std.time.nanoTimestamp()});
    defer allocator.free(temp_name);

    var temp_storage_closed: bool = false;
    var temporary_storage = try temp_dir.makeOpenPath(temp_name, .{
        .iterate = utils.os_tag == .windows,
    });
    errdefer if (!temp_storage_closed) temporary_storage.close();

    if (utils.os_tag == .windows) {
        // std.zip has no strip components :( so we have to do this mess...
        // TODO: It's kinda slow but it's std.zip's fault... yea, maybe we can do something to speed it up.
        const buf = try req.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(buf);

        var fbs = std.io.fixedBufferStream(buf);
        try std.zip.extract(temporary_storage, fbs.seekableStream(), .{});

        var tempstrg = temporary_storage.iterate();
        const w_path = try tempstrg.next() orelse return error.ZigInstallationWasLost__Oops;

        const w_path_duped = try allocator.dupe(u8, w_path.name);
        defer allocator.free(w_path_duped);

        if ((try tempstrg.next()) != null)
            return error.InstallationWasSabotaged;

        try temporary_storage.rename(w_path_duped, final_destination);
        temporary_storage.close();
        temp_storage_closed = true;
        try temp_dir.deleteTree(temp_name);
    } else {
        var xz_decompressor = try std.compress.xz.decompress(allocator, req.reader());
        defer xz_decompressor.deinit();

        try std.tar.pipeToFileSystem(temporary_storage, xz_decompressor.reader(), .{ .strip_components = 1 });
        try utils.createDirectoryIfNotExist(final_destination);
        temporary_storage.close();
        temp_storage_closed = true;
        try temp_dir.rename(temp_name, final_destination);
    }

    return true;
}

pub fn getCachePath(allocator: std.mem.Allocator, zigd_path: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ zigd_path, CacheByZigd });
}

pub fn getCacheFile(cache_path: []const u8) !std.fs.File {
    return try utils.existsOpenFile(cache_path, .{ .mode = .read_write }) orelse v: {
        break :v try std.fs.createFileAbsolute(cache_path, .{
            .read = true,
            .truncate = false,
            .exclusive = true,
        });
    };
}

// TODO: Add an command to re-cache or disable cache
// Caller frees the memory
pub fn fetchMaster(allocator: std.mem.Allocator, zigd_path: []const u8, allow_cache: bool) ![]u8 {
    const cache_path: ?[]const u8 = if (allow_cache)
        try getCachePath(allocator, zigd_path)
    else
        null;
    defer if (cache_path) |cp| allocator.free(cp);

    const cache_file: ?std.fs.File = if (allow_cache) try getCacheFile(cache_path orelse unreachable) else null;
    defer if (cache_file) |cf| cf.close();

    if (allow_cache) {
        const file_stat = try (cache_file orelse unreachable).stat();

        // If last modified less than 12 hours ago
        if (file_stat.mtime > std.time.nanoTimestamp() - (12 * std.time.ns_per_hour)) {
            const ver = try (cache_file orelse unreachable).readToEndAlloc(allocator, std.math.maxInt(usize));

            if (!std.meta.isError(std.SemanticVersion.parse(ver)))
                return ver;

            allocator.free(ver);
        }
    }

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

    if (resp.status != .ok) {
        std.log.err("Fetching the index failed\nResponse Code: {s} {d}", .{
            req.response.status.phrase() orelse "???",
            req.response.status,
        });
        return error.ResponseWasNotOk;
    }

    const body = try req.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(body);

    const json = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer json.deinit();

    const master = json.value.object.get("master") orelse return error.MasterNotFound;
    const version = master.object.get("version") orelse return error.VersionNotFound;

    if (version != .string) {
        return error.VersionNotString;
    }

    if (allow_cache)
        try (cache_file orelse unreachable).writer().writeAll(version.string);

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
        DotZigversion, // .zigversion file
        Zonver, // build.zig.zon, minimum_zig_version field
        WorkspaceVer, // config, path
        DefaultVer, // config, default
        Master: *Source,
    };

    // Handles the "master" case
    pub fn parse(allocator: std.mem.Allocator, str: []const u8, source: *Source, free_instant_if_zigver: bool, zigd_path: []const u8, allow_cache: bool) !@This() {
        var zig_version: @This() = .{
            .as_string = str,
            .source = source.*,
        };

        if (std.mem.eql(u8, zig_version.as_string, "master")) {
            if (free_instant_if_zigver and source.* == .DotZigversion)
                allocator.free(str);

            zig_version = .{
                .as_string = try fetchMaster(allocator, zigd_path, allow_cache),
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

    pub fn deinitIfMightBeAllocated(self: @This(), allocator: std.mem.Allocator) void {
        switch (self.source) {
            .Master, .DotZigversion, .Zonver => allocator.free(self.as_string),
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
        custom_zigd = false;

        if (utils.os_tag == .windows) {
            if (env_map.get("USERPROFILE")) |userprofile| {
                break :v try std.fs.path.join(allocator, &.{ userprofile, ".zigd" });
            }
        }

        if (env_map.get("HOME")) |home| {
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

// I'm bored, that's why im gonna do it the messy style
pub fn garbage_collect_tempdir(zigd_path: []const u8) !void {
    var buf: PathBuf = undefined;
    try std.fs.deleteTreeAbsolute(utils.join_path(&buf, &.{ zigd_path, "tmp" }));
}
