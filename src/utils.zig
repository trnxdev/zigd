const std = @import("std");

pub fn run(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var proc = std.ChildProcess.init(argv, allocator);
    try proc.spawn();
    _ = try proc.wait();
}

pub fn fromHome(home: []const u8, to: []const u8) !std.fs.Dir {
    var o1 = try std.fs.openDirAbsolute(home, .{});
    var o2 = try o1.makeOpenPath(to, .{});
    o1.close();
    return o2;
}
