// Process that looks up the correct zig version using the zigd library and runs it with user arguments.

const std = @import("std");
const utils = @import("utils.zig");
const zigdcore = @import("zigdcore.zig");

pub fn main() !void {
    var gpa = if (utils.InDebug) std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = if (utils.InDebug) gpa.allocator() else std.heap.c_allocator;
    defer _ = if (utils.InDebug) gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const zigd_path = try zigdcore.getZigdPath(allocator);
    defer allocator.free(zigd_path);

    const config_path = try std.fs.path.join(allocator, &.{ zigd_path, "config" });
    defer allocator.free(config_path);

    var config = try Config.load_from(allocator, config_path);
    defer config.deinit();

    var zig_version: zigdcore.ZigVersion = v: {
        if (try utils.existsReadFileCwd(allocator, "zig.ver")) |zig_ver| {
            // Can't error so no need for errdefer in this scope
            break :v zigdcore.ZigVersion{
                .as_string = zig_ver,
                .source = .Zigver,
            };
        }

        if (try utils.existsReadFileCwdSentinel(allocator, "build.zig.zon")) |build_zig_zon| {
            defer allocator.free(build_zig_zon);

            if (try zon_minimum_version(allocator, build_zig_zon)) |zonver| {
                break :v zigdcore.ZigVersion{
                    .as_string = zonver,
                    .source = .Zonver,
                };
            }
        }

        const absolute_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(absolute_cwd);

        if (config.recursive_search_for_workspace_version(absolute_cwd)) |workspace_version| {
            break :v zigdcore.ZigVersion{
                .as_string = workspace_version,
                .source = .WorkspaceVer,
            };
        }

        if (config.default) |default_version| {
            break :v zigdcore.ZigVersion{
                .as_string = default_version,
                .source = .DefaultVer,
            };
        }

        std.log.err("No default, workspace, or zig.ver version was found.", .{});
        return;
    };

    zig_version = try zigdcore.ZigVersion.parse(allocator, zig_version.as_string, &zig_version.source, true);
    defer zig_version.deinitIfMasterOrZigverOrZonver(allocator);

    const zig_binary_path = try std.fs.path.join(allocator, &.{ zigd_path, "versions", zig_version.as_string, "zig" ++ utils.binary_ext });
    defer allocator.free(zig_binary_path);

    if (!(try utils.isFile(zig_binary_path))) o: {
        const zig_version_path = std.mem.lastIndexOfScalar(u8, zig_binary_path, std.fs.path.sep) orelse unreachable;

        if (!(try utils.isDirectory(zig_binary_path[0..zig_version_path]))) {
            // TODO: Add zigd specific config option to not auto install zig versions.
            std.log.warn("Zigd could not find zig version {} on your system, installing...", .{zig_version});

            const download_url = try zigdcore.downloadUrlFromVersion(allocator, zig_version.as_string, zig_version.source == .Master);
            defer allocator.free(download_url);

            if (!try zigdcore.install_zig(allocator, download_url, zigd_path, zig_version)) {
                std.log.err("Installation failed! Exiting...", .{});
                return;
            }

            break :o;
        }

        std.log.err("Zigd could find the directory for the zig version {} on your system, but not the executable... Try reinstalling it\n", .{zig_version});
        return;
    }

    const run_result = try utils.exec(allocator, zig_binary_path, args);
    std.posix.exit(run_result.Exited);
}

const Config = struct {
    // [Path]: [Zig Version]
    const WorkspaceVersionsMap = std.StringHashMap([]const u8);

    allocator: std.mem.Allocator = undefined,
    workspace_versions: WorkspaceVersionsMap = undefined,
    default: ?[]const u8 = null,
    loaded: bool = false,
    contents: []u8 = "",

    // Caller calls deinit
    pub inline fn load_from(allocator: std.mem.Allocator, path: []const u8) !@This() {
        // We do not free this because the WorkspaceVersionsMap relies on it, otherwise we'd have to dupe each key and value in the parse function.
        const cfgfile = std.fs.cwd().readFileAlloc(
            allocator,
            path,
            std.math.maxInt(usize),
        ) catch |e| switch (e) {
            std.fs.Dir.OpenError.FileNotFound => return .{},
            else => return e,
        };
        errdefer allocator.free(cfgfile);

        var cfgmap = WorkspaceVersionsMap.init(allocator);
        errdefer cfgmap.deinit();

        var self: @This() = .{
            .allocator = allocator,
            .workspace_versions = cfgmap,
            .loaded = true,
            .contents = cfgfile,
        };

        try self.parse();

        return self;
    }

    inline fn parse(self: *@This()) !void {
        var lines = std.mem.tokenizeScalar(u8, self.contents, '\n');

        o: while (lines.next()) |line| {
            if (line[0] == '#' or line.len == 0)
                continue :o;

            const index_of_equal_sign = std.mem.indexOf(u8, line, "=") orelse return error.LineDoesNotHaveAnEqualSign;

            if (index_of_equal_sign + 1 > line.len)
                return error.ValueInTheConfigIsEmpty;

            const key = std.mem.trim(u8, line[0..index_of_equal_sign], &std.ascii.whitespace);
            const value = std.mem.trim(u8, line[index_of_equal_sign + 1 ..], &std.ascii.whitespace);

            if (std.mem.eql(u8, key, "default")) {
                self.default = value;
                continue :o;
            }

            // putNoClobber asserts, that's why we use getOrPut here
            const gop = try self.workspace_versions.getOrPut(key);

            if (gop.found_existing)
                return error.VersionExistsTwiceInConfig;

            // key_ptr is automatically set by VersionsMap.getOrPut() ^
            gop.value_ptr.* = value;
        }
    }

    // if user is in /home/john/dummy/x and there is a entry for /home/john/dummy/ in the config file,
    // then return the version for /home/john/dummy/
    pub fn recursive_search_for_workspace_version(self: *Config, starter_directory: []const u8) ?[]const u8 {
        var starter = starter_directory;

        while (true) {
            if (self.workspace_versions.get(starter)) |workspace_version|
                return workspace_version;

            if (std.mem.lastIndexOfScalar(u8, starter, std.fs.path.sep)) |index_of_slash|
                starter = starter[0..index_of_slash]
            else
                return null;
        }
    }

    pub fn deinit(self: *Config) void {
        if (!self.loaded)
            return;

        self.default = null;
        self.loaded = false;
        self.workspace_versions.deinit();
        self.allocator.free(self.contents);
    }
};

// Caller frees the returned memory
fn zon_minimum_version(allocator: std.mem.Allocator, zon_contents: [:0]u8) !?[]const u8 {
    var ast = try std.zig.Ast.parse(allocator, zon_contents, .zon);
    defer ast.deinit(allocator);

    var ast_buf: [2]std.zig.Ast.Node.Index = undefined;
    const root = ast.fullStructInit(&ast_buf, ast.nodes.items(.data)[0].lhs) orelse return error.ZonParseError;

    for (root.ast.fields) |field_idx| {
        const field_name = try parseFieldName(allocator, ast, field_idx);
        defer allocator.free(field_name);

        if (std.mem.eql(u8, field_name, "minimum_zig_version")) {
            return try parseString(allocator, ast, field_idx);
        }
    }

    return null;
}

// Caller frees memory
fn parseString(allocator: std.mem.Allocator, ast: std.zig.Ast, idx: std.zig.Ast.Node.Index) ![]const u8 {
    const node_tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    if (node_tags[idx] != .string_literal) {
        return error.ExpectedStringLiteral;
    }
    const str_lit_token = main_tokens[idx];
    const token_bytes = ast.tokenSlice(str_lit_token);
    return try parseStrLit(allocator, token_bytes, 0);
}

// Caller frees memory
inline fn parseStrLit(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    offset: u32,
) ![]u8 {
    return try std.zig.string_literal.parseAlloc(allocator, bytes[offset..]);
}

fn parseFieldName(
    alloc: std.mem.Allocator,
    ast: std.zig.Ast,
    idx: std.zig.Ast.Node.Index,
) ![]const u8 {
    const name = ast.tokenSlice(ast.firstToken(idx) - 2);
    return if (name[0] == '@') // Escaping something, like @"hello bois"
        try std.zig.string_literal.parseAlloc(alloc, name[1..])
    else
        try alloc.dupe(u8, name);
}
