const std = @import("std");

pub fn run(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.Term {
    var proc = std.process.Child.init(argv, allocator);
    return proc.spawnAndWait();
}

pub fn fromHome(home: []const u8, to: []const u8) !std.fs.Dir {
    var o1 = try std.fs.openDirAbsolute(home, .{});
    const o2 = try o1.makeOpenPath(to, .{});
    o1.close();
    return o2;
}
