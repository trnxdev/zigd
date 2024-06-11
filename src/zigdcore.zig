const std = @import("std");
const utils = @import("utils.zig");

/// Version cannot be master!
/// Returns a bool if it installed/reinstalled zig
pub fn install_zig(allocator: std.mem.Allocator, download_url: []const u8, install_path: []const u8, zig_version: ZigVersion) !bool {
    const final_destination = try std.fs.path.join(allocator, &.{ install_path, "versions", zig_version.as_string });
    defer allocator.free(final_destination);

    if (try utils.isDirectory(final_destination)) {
        o: while (true) {
            const byte = try std.io.getStdIn().reader().readByte();
            std.log.warn("Version {} is already installed on your system! Re-install? (y/n)", .{zig_version});

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

    if (req.response.status != .ok)
        return error.ResponseWasNotOk;

    try utils.createDirectoryIgnoreExist(final_destination);

    if (utils.os_tag == .windows) {
        // std.zip has no strip components :( so we have to do this mess...
        // TODO: It's kinda slow but it's std.zip's fault... yea, maybe we can do something to speed it up.
        const temp_name = "DO_NOT_MODIFY_U_STINKY-zigd-install-temp";

        var temporary_storage = try std.fs.cwd().makeOpenPath(temp_name, .{
            .iterate = true,
        });

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
        try std.fs.cwd().deleteDir(temp_name);
    } else {
        var final_dest_dir = try std.fs.openDirAbsolute(final_destination, .{});
        defer final_dest_dir.close();

        var xz_decompressor = try std.compress.xz.decompress(allocator, req.reader());
        defer xz_decompressor.deinit();

        try std.tar.pipeToFileSystem(final_dest_dir, xz_decompressor.reader(), .{ .strip_components = 1 });
    }

    return true;
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
        Zigver, // zig.ver file
        Zonver, // build.zig.zon, minimum_zig_version field
        WorkspaceVer, // config, path
        DefaultVer, // config, default
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

    pub fn deinitIfMasterOrZigverOrZonver(self: @This(), allocator: std.mem.Allocator) void {
        switch (self.source) {
            .Master, .Zigver, .Zonver => allocator.free(self.as_string),
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
