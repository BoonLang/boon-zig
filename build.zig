const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const boon_mod = b.addModule("boon", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "boon-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the Boon Zig CLI");
    run_step.dependOn(&run_cmd.step);

    const sync_corpus_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/corpus.py",
        "sync",
    });
    const sync_corpus_step = b.step("sync-corpus", "Import the pinned upstream corpus and regenerate fixtures");
    sync_corpus_step.dependOn(&sync_corpus_cmd.step);

    const verify_corpus_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/corpus.py",
        "verify",
    });
    const verify_corpus_step = b.step("verify-corpus", "Verify imported upstream corpus and generated fixtures");
    verify_corpus_step.dependOn(&verify_corpus_cmd.step);

    const lib_tests = b.addTest(.{
        .root_module = boon_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run project tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
