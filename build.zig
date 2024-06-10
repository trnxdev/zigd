const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigdcli = b.addExecutable(.{
        .name = "zigd",
        .root_source_file = b.path("src/zigdcli.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(zigdcli);

    const zigdemu = b.addExecutable(.{
        .name = "zigdemu",
        .root_source_file = b.path("src/zigdemu.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(zigdemu);

    if (optimize != .Debug) {
        zigdcli.linkLibC();
        zigdemu.linkLibC();
    }

    const run_cmd = b.addRunArtifact(zigdemu);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
