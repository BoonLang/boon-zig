const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Build optimize mode") orelse .Debug;
    const io_backend = b.option([]const u8, "io_backend", "Select std.Io backend: threaded or evented") orelse "threaded";

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "io_backend", io_backend);

    const boon_mod = b.addModule("boon", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "boon_build_options", .module = build_options.createModule() },
        },
    });

    const browser_assets_mod = b.addModule("browser_assets", .{
        .root_source_file = b.path("browser/assets.zig"),
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
                .{ .name = "browser_assets", .module = browser_assets_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const fast_exe = b.addExecutable(.{
        .name = "boon-zig-fast",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
                .{ .name = "browser_assets", .module = browser_assets_mod },
            },
        }),
    });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the Boon Zig CLI");
    run_step.dependOn(&run_cmd.step);

    const run_fast_cmd = b.addRunArtifact(fast_exe);
    if (b.args) |args| run_fast_cmd.addArgs(args);
    const run_fast_step = b.step("run-fast", "Run the Boon Zig CLI in ReleaseFast mode");
    run_fast_step.dependOn(&run_fast_cmd.step);

    const run_ex_cmd = b.addRunArtifact(exe);
    run_ex_cmd.step.dependOn(b.getInstallStep());
    run_ex_cmd.addArg("example");
    if (b.args) |args| run_ex_cmd.addArgs(args);
    const run_ex_step = b.step("run_ex", "Run a built-in example by short name in the default optimize mode");
    run_ex_step.dependOn(&run_ex_cmd.step);

    const run_ex_fast_cmd = b.addRunArtifact(fast_exe);
    run_ex_fast_cmd.addArg("example");
    if (b.args) |args| run_ex_fast_cmd.addArgs(args);
    const run_ex_fast_step = b.step("run_ex_fast", "Run a built-in example by short name in ReleaseFast mode");
    run_ex_fast_step.dependOn(&run_ex_fast_cmd.step);

    const parse_cmd = b.addRunArtifact(exe);
    parse_cmd.step.dependOn(b.getInstallStep());
    parse_cmd.addArg("parse");
    if (b.args) |args| parse_cmd.addArgs(args);

    const parse_step = b.step("parse", "Parse a Boon source file");
    parse_step.dependOn(&parse_cmd.step);

    const hir_cmd = b.addRunArtifact(exe);
    hir_cmd.step.dependOn(b.getInstallStep());
    hir_cmd.addArg("hir");
    if (b.args) |args| hir_cmd.addArgs(args);

    const hir_step = b.step("hir", "Lower a Boon source file into HIR");
    hir_step.dependOn(&hir_cmd.step);

    const flow_cmd = b.addRunArtifact(exe);
    flow_cmd.step.dependOn(b.getInstallStep());
    flow_cmd.addArg("flow");
    if (b.args) |args| flow_cmd.addArgs(args);

    const flow_step = b.step("flow", "Lower a Boon source file into Flow IR");
    flow_step.dependOn(&flow_cmd.step);

    const run_headless_cmd = b.addRunArtifact(exe);
    run_headless_cmd.step.dependOn(b.getInstallStep());
    run_headless_cmd.addArg("run-headless");
    if (b.args) |args| run_headless_cmd.addArgs(args);

    const run_headless_step = b.step("run-headless", "Run a Boon source file in the headless runtime");
    run_headless_step.dependOn(&run_headless_cmd.step);

    const snapshot_cmd = b.addRunArtifact(exe);
    snapshot_cmd.step.dependOn(b.getInstallStep());
    snapshot_cmd.addArg("snapshot");
    if (b.args) |args| snapshot_cmd.addArgs(args);

    const snapshot_step = b.step("snapshot", "Render a deterministic terminal-grid snapshot");
    snapshot_step.dependOn(&snapshot_cmd.step);

    const run_terminal_cmd = b.addRunArtifact(exe);
    run_terminal_cmd.step.dependOn(b.getInstallStep());
    run_terminal_cmd.addArg("run-terminal");
    if (b.args) |args| run_terminal_cmd.addArgs(args);

    const run_terminal_step = b.step("run-terminal", "Run the interactive terminal fallback backend");
    run_terminal_step.dependOn(&run_terminal_cmd.step);

    const sync_corpus_cmd = b.addRunArtifact(exe);
    sync_corpus_cmd.step.dependOn(b.getInstallStep());
    sync_corpus_cmd.addArg("sync-corpus");
    const sync_corpus_step = b.step("sync-corpus", "Sync the pinned upstream corpus examples into examples/upstream");
    sync_corpus_step.dependOn(&sync_corpus_cmd.step);

    const verify_corpus_cmd = b.addRunArtifact(exe);
    verify_corpus_cmd.step.dependOn(b.getInstallStep());
    verify_corpus_cmd.addArg("verify-corpus");
    if (b.args) |args| verify_corpus_cmd.addArgs(args);
    const verify_corpus_step = b.step("verify-corpus", "Verify imported upstream corpus tree and parser coverage");
    verify_corpus_step.dependOn(&verify_corpus_cmd.step);

    const verify_upstream_pin_cmd = b.addRunArtifact(exe);
    verify_upstream_pin_cmd.step.dependOn(b.getInstallStep());
    verify_upstream_pin_cmd.addArg("verify-upstream-pin");
    const verify_upstream_pin_step = b.step("verify-upstream-pin", "Verify tracked upstream pin metadata matches compiled constants");
    verify_upstream_pin_step.dependOn(&verify_upstream_pin_cmd.step);

    const verify_examples_cmd = b.addRunArtifact(exe);
    verify_examples_cmd.step.dependOn(b.getInstallStep());
    verify_examples_cmd.addArg("verify-examples");
    if (b.args) |args| verify_examples_cmd.addArgs(args);
    const verify_examples_step = b.step("verify-examples", "Verify example execution lanes and recorded blockers");
    verify_examples_step.dependOn(&verify_examples_cmd.step);

    const browser_out = b.getInstallPath(.prefix, "browser");
    const browser_cmd = b.addRunArtifact(exe);
    browser_cmd.step.dependOn(b.getInstallStep());
    browser_cmd.addArg("build-browser");
    browser_cmd.addArg("--out-dir");
    browser_cmd.addArg(browser_out);
    const browser_step = b.step("browser", "Build the browser host bundle");
    browser_step.dependOn(&browser_cmd.step);

    const verify_visual_cmd = b.addRunArtifact(exe);
    verify_visual_cmd.step.dependOn(b.getInstallStep());
    verify_visual_cmd.addArg("verify-visual");
    if (b.args) |args| verify_visual_cmd.addArgs(args);
    if (b.args == null) {
        verify_visual_cmd.addArg("--filter");
        verify_visual_cmd.addArg("todo_mvc");
    }
    const verify_visual_step = b.step("verify-visual", "Run browser visual comparison lanes");
    verify_visual_step.dependOn(&verify_visual_cmd.step);

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
