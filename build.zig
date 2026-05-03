const std = @import("std");
const raybox_build = @import("raybox/build_steps.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Build optimize mode") orelse .Debug;
    const io_backend = b.option([]const u8, "io_backend", "Select std.Io backend: threaded or evented") orelse "threaded";
    const raybox_selected_example = b.option([]const u8, "example", "Limit a Raybox verifier to one example");
    const raybox_screenshot_example = b.option([]const u8, "screenshot-example", "Raybox example to capture with screenshot-raybox-native") orelse "todo_mvc";
    const raybox_build_only = b.option(bool, "build-only", "Run Raybox verifier build-only mode") orelse false;

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

    try raybox_build.addRayboxSteps(b, .{
        .target = target,
        .optimize = optimize,
        .io_backend = io_backend,
        .selected_example = raybox_selected_example,
        .screenshot_example = raybox_screenshot_example,
        .build_only = raybox_build_only,
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

    const generated_counter_exe = b.addExecutable(.{
        .name = "generated-counter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/counter.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });

    const generated_todo_exe = b.addExecutable(.{
        .name = "generated-todo-mvc-headless",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/todo_mvc_headless.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });

    const generated_list_latest_exe = b.addExecutable(.{
        .name = "generated-list-latest-dynamic",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/list_latest_dynamic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });

    const generated_interval_exe = b.addExecutable(.{
        .name = "generated-interval",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/interval.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });

    const generated_cells_exe = b.addExecutable(.{
        .name = "generated-cells",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/cells.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });

    const generated_pong_exe = b.addExecutable(.{
        .name = "generated-pong",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/pong.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });

    const generated_arkanoid_exe = b.addExecutable(.{
        .name = "generated-arkanoid",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/arkanoid.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });

    const generated_structured_runtime_plan_exe = b.addExecutable(.{
        .name = "generated-structured-runtime-plan",
        .root_module = b.createModule(.{
            .root_source_file = b.path("generated_zig/structured_runtime_plan.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
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

    const run_play_cmd = b.addRunArtifact(exe);
    run_play_cmd.step.dependOn(b.getInstallStep());
    run_play_cmd.addArg("run-playground");
    if (b.args) |args| run_play_cmd.addArgs(args);
    const run_play_step = b.step("run_play", "Run the terminal playground multiplexer in the default optimize mode");
    run_play_step.dependOn(&run_play_cmd.step);

    const run_play_fast_cmd = b.addRunArtifact(fast_exe);
    run_play_fast_cmd.addArg("run-playground");
    if (b.args) |args| run_play_fast_cmd.addArgs(args);
    const run_play_fast_step = b.step("run_play_fast", "Run the terminal playground multiplexer in ReleaseFast mode");
    run_play_fast_step.dependOn(&run_play_fast_cmd.step);

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

    const verify_examples_headless_cmd = b.addRunArtifact(exe);
    verify_examples_headless_cmd.step.dependOn(b.getInstallStep());
    verify_examples_headless_cmd.addArgs(&.{ "verify-examples", "--headless", "--all" });
    const verify_examples_headless_step = b.step("verify-examples-headless", "Verify all mapped headless examples");
    verify_examples_headless_step.dependOn(&verify_examples_headless_cmd.step);

    const verify_examples_terminal_cmd = b.addRunArtifact(exe);
    verify_examples_terminal_cmd.step.dependOn(b.getInstallStep());
    verify_examples_terminal_cmd.addArgs(&.{ "verify-examples", "--terminal-grid", "--all" });
    const verify_examples_terminal_step = b.step("verify-examples-terminal", "Verify all mapped terminal-grid examples");
    verify_examples_terminal_step.dependOn(&verify_examples_terminal_cmd.step);

    const test_terminal_playground_cmd = b.addRunArtifact(exe);
    test_terminal_playground_cmd.step.dependOn(b.getInstallStep());
    test_terminal_playground_cmd.addArgs(&.{ "verify-examples", "--terminal-grid", "--filter", "playground" });
    const test_terminal_playground_step = b.step("test-terminal-playground", "Verify the Zig-host terminal playground multiplexer");
    test_terminal_playground_step.dependOn(&test_terminal_playground_cmd.step);

    const test_headless_counter_cmd = b.addRunArtifact(exe);
    test_headless_counter_cmd.step.dependOn(b.getInstallStep());
    test_headless_counter_cmd.addArgs(&.{ "verify-examples", "--headless", "--filter", "counter" });
    const test_headless_counter_step = b.step("test-headless-counter", "Verify counter headless behavior");
    test_headless_counter_step.dependOn(&test_headless_counter_cmd.step);

    const test_headless_while_cmd = b.addRunArtifact(exe);
    test_headless_while_cmd.step.dependOn(b.getInstallStep());
    test_headless_while_cmd.addArgs(&.{ "run-headless", "examples/upstream/while/while.bn", "--expect-text", "A + BA - B" });
    const test_headless_while_step = b.step("test-headless-while", "Verify current upstream WHILE headless behavior");
    test_headless_while_step.dependOn(&test_headless_while_cmd.step);

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

    const test_browser_smoke_counter_cmd = b.addSystemCommand(&.{ "node", "tools/browser_smoke.mjs", "counter" });
    test_browser_smoke_counter_cmd.step.dependOn(b.getInstallStep());
    const test_browser_smoke_interval_cmd = b.addSystemCommand(&.{ "node", "tools/browser_smoke.mjs", "interval" });
    test_browser_smoke_interval_cmd.step.dependOn(b.getInstallStep());
    const test_browser_smoke_todo_cmd = b.addSystemCommand(&.{ "node", "tools/browser_smoke.mjs", "todo_mvc" });
    test_browser_smoke_todo_cmd.step.dependOn(b.getInstallStep());
    const test_browser_smoke_cells_cmd = b.addSystemCommand(&.{ "node", "tools/browser_smoke.mjs", "cells" });
    test_browser_smoke_cells_cmd.step.dependOn(b.getInstallStep());
    const test_browser_smoke_wasm_host_cmd = b.addSystemCommand(&.{ "node", "tools/browser_smoke.mjs", "wasm_host_boundary" });
    test_browser_smoke_wasm_host_cmd.step.dependOn(b.getInstallStep());
    const test_browser_smoke_step = b.step("test-browser-smoke", "Run current browser smoke coverage");
    test_browser_smoke_step.dependOn(&test_browser_smoke_counter_cmd.step);
    test_browser_smoke_step.dependOn(&test_browser_smoke_interval_cmd.step);
    test_browser_smoke_step.dependOn(&test_browser_smoke_todo_cmd.step);
    test_browser_smoke_step.dependOn(&test_browser_smoke_cells_cmd.step);
    test_browser_smoke_step.dependOn(&test_browser_smoke_wasm_host_cmd.step);

    const test_browser_visual_cmd = b.addRunArtifact(exe);
    test_browser_visual_cmd.step.dependOn(b.getInstallStep());
    test_browser_visual_cmd.addArgs(&.{ "verify-visual", "--all-with-reference-assets" });
    const test_browser_visual_step = b.step("test-browser-visual", "Run browser visual reference checks");
    test_browser_visual_step.dependOn(&test_browser_visual_cmd.step);

    const test_playground_compile_cmd = b.addSystemCommand(&.{ "node", "tools/playground_smoke.mjs" });
    test_playground_compile_cmd.step.dependOn(b.getInstallStep());
    const test_playground_server_cmd = b.addSystemCommand(&.{ "node", "tools/playground_server_smoke.mjs" });
    test_playground_server_cmd.step.dependOn(b.getInstallStep());
    const test_playground_compile_step = b.step("test-playground-compile", "Run playground interpreter/codegen/local-Zig compile smoke coverage");
    test_playground_compile_step.dependOn(&test_playground_compile_cmd.step);
    test_playground_compile_step.dependOn(&test_playground_server_cmd.step);

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

    const physical_ir_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/physical_ir_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });
    const run_physical_ir_tests = b.addRunArtifact(physical_ir_tests);
    const test_physical_ir_step = b.step("test-physical-ir", "Run Physical IR lowering tests");
    test_physical_ir_step.dependOn(&run_physical_ir_tests.step);

    const test_runtime_step = b.step("test-runtime", "Run current runtime coverage until Physical IR runtime tests are split out");
    test_runtime_step.dependOn(test_step);

    const test_headless_list_keys_step = b.step("test-headless-list-keys", "Run current list-key runtime coverage until branch-specific tests are split out");
    test_headless_list_keys_step.dependOn(test_step);

    const test_physical_runtime_counter_cmd = b.addRunArtifact(exe);
    test_physical_runtime_counter_cmd.step.dependOn(b.getInstallStep());
    test_physical_runtime_counter_cmd.addArgs(&.{
        "physical-run",
        "fixtures/physical_runtime/counter.bn",
        "--event",
        "0:1",
        "--expect-state",
        "state[0]=number:1",
    });
    const test_physical_runtime_counter_step = b.step("test-physical-runtime-counter", "Verify canonical Physical Runtime counter fixture through the CLI");
    test_physical_runtime_counter_step.dependOn(&test_physical_runtime_counter_cmd.step);
    test_runtime_step.dependOn(test_physical_runtime_counter_step);

    const test_physical_runtime_payload_cmd = b.addRunArtifact(exe);
    test_physical_runtime_payload_cmd.step.dependOn(b.getInstallStep());
    test_physical_runtime_payload_cmd.addArgs(&.{
        "physical-run",
        "fixtures/physical_runtime/payload_hold.bn",
        "--event",
        "0:1:number:7",
        "--expect-state",
        "state[0]=number:7",
    });
    const test_physical_runtime_payload_step = b.step("test-physical-runtime-payload", "Verify typed Physical Runtime CLI event payloads");
    test_physical_runtime_payload_step.dependOn(&test_physical_runtime_payload_cmd.step);
    test_runtime_step.dependOn(test_physical_runtime_payload_step);

    const test_physical_runtime_virtual_time_cmd = b.addRunArtifact(exe);
    test_physical_runtime_virtual_time_cmd.step.dependOn(b.getInstallStep());
    test_physical_runtime_virtual_time_cmd.addArgs(&.{
        "physical-run",
        "fixtures/physical_runtime/counter.bn",
        "--interval",
        "0:1:100ms",
        "--virtual-time",
        "250ms",
        "--expect-state",
        "state[0]=number:2",
    });
    const test_physical_runtime_virtual_time_step = b.step("test-physical-runtime-virtual-time", "Verify deterministic Physical Runtime interval dispatch through the CLI");
    test_physical_runtime_virtual_time_step.dependOn(&test_physical_runtime_virtual_time_cmd.step);
    test_runtime_step.dependOn(test_physical_runtime_virtual_time_step);

    const test_physical_runtime_pass_cmd = b.addRunArtifact(exe);
    test_physical_runtime_pass_cmd.step.dependOn(b.getInstallStep());
    test_physical_runtime_pass_cmd.addArgs(&.{
        "physical-run",
        "fixtures/physical_runtime/pass_context_counter.bn",
        "--event",
        "0:1",
        "--expect-state",
        "state[0]=number:1",
    });
    const test_physical_runtime_pass_step = b.step("test-physical-runtime-pass", "Verify Physical Runtime PASS/PASSED normalization through a canonical fixture");
    test_physical_runtime_pass_step.dependOn(&test_physical_runtime_pass_cmd.step);
    test_runtime_step.dependOn(test_physical_runtime_pass_step);

    const test_physical_runtime_persist_first_cmd = b.addRunArtifact(exe);
    test_physical_runtime_persist_first_cmd.step.dependOn(b.getInstallStep());
    test_physical_runtime_persist_first_cmd.addArgs(&.{
        "physical-run",
        "fixtures/physical_runtime/counter.bn",
        "--state-dir",
        ".zig-cache/physical-runtime-counter-state",
        "--clear-state",
        "--event",
        "0:1",
        "--expect-state",
        "state[0]=number:1",
    });
    const test_physical_runtime_persist_second_cmd = b.addRunArtifact(exe);
    test_physical_runtime_persist_second_cmd.step.dependOn(&test_physical_runtime_persist_first_cmd.step);
    test_physical_runtime_persist_second_cmd.addArgs(&.{
        "physical-run",
        "fixtures/physical_runtime/counter.bn",
        "--state-dir",
        ".zig-cache/physical-runtime-counter-state",
        "--event",
        "0:1",
        "--expect-state",
        "state[0]=number:2",
    });
    const test_physical_runtime_persistence_step = b.step("test-physical-runtime-persistence", "Verify file-backed Physical Runtime state snapshots through the CLI");
    test_physical_runtime_persistence_step.dependOn(&test_physical_runtime_persist_second_cmd.step);
    test_runtime_step.dependOn(test_physical_runtime_persistence_step);

    const test_physical_example_counter_cmd = b.addRunArtifact(exe);
    test_physical_example_counter_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_counter_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/counter/counter.bn",
        "--event",
        "0:1",
        "--expect-state",
        "state[0]=number:1",
    });
    const test_physical_example_counter_step = b.step("test-physical-example-counter", "Verify canonical SOURCE counter example through Physical Runtime");
    test_physical_example_counter_step.dependOn(&test_physical_example_counter_cmd.step);
    test_runtime_step.dependOn(test_physical_example_counter_step);

    const test_physical_example_interval_cmd = b.addRunArtifact(exe);
    test_physical_example_interval_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_interval_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/interval/interval.bn",
        "--interval",
        "0:1:100ms",
        "--virtual-time",
        "350ms",
        "--expect-state",
        "state[0]=number:3",
    });
    const test_physical_example_interval_step = b.step("test-physical-example-interval", "Verify canonical SOURCE interval example through Physical Runtime virtual time");
    test_physical_example_interval_step.dependOn(&test_physical_example_interval_cmd.step);
    test_runtime_step.dependOn(test_physical_example_interval_step);

    const test_physical_example_list_latest_cmd = b.addRunArtifact(exe);
    test_physical_example_list_latest_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_list_latest_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/list_latest_regression/list_latest_regression.bn",
        "--expect-state",
        "state[0]=number:2",
    });
    const test_physical_example_list_latest_step = b.step("test-physical-example-list-latest", "Verify canonical non-UI List/latest regression through Physical Runtime");
    test_physical_example_list_latest_step.dependOn(&test_physical_example_list_latest_cmd.step);
    test_runtime_step.dependOn(test_physical_example_list_latest_step);

    const test_physical_example_cells_cmd = b.addRunArtifact(exe);
    test_physical_example_cells_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_cells_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/cells/cells.bn",
        "--event",
        "0:1:text:=add(A0,A1)",
        "--expect-state",
        "state[0]=text:=add(A0,A1)",
    });
    const test_physical_example_cells_step = b.step("test-physical-example-cells", "Verify canonical SOURCE cells state lane through Physical Runtime");
    test_physical_example_cells_step.dependOn(&test_physical_example_cells_cmd.step);
    test_runtime_step.dependOn(test_physical_example_cells_step);

    const test_physical_example_todo_cmd = b.addRunArtifact(exe);
    test_physical_example_todo_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_todo_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/todo_mvc/todo_mvc.bn",
        "--event",
        "0:1:text:Write tests",
        "--expect-state",
        "state[0]=text:Write tests",
    });
    const test_physical_example_todo_step = b.step("test-physical-example-todo-mvc", "Verify canonical SOURCE todo_mvc state lane through Physical Runtime");
    test_physical_example_todo_step.dependOn(&test_physical_example_todo_cmd.step);
    test_runtime_step.dependOn(test_physical_example_todo_step);

    const test_physical_example_todo_physical_store_cmd = b.addRunArtifact(exe);
    test_physical_example_todo_physical_store_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_todo_physical_store_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/todo_mvc_physical/todo_mvc_physical.bn",
        "--event",
        "9:1:text:Write docs",
        "--expect-state",
        "state[0]=text:Write docs",
    });
    const test_physical_example_todo_physical_item_cmd = b.addRunArtifact(exe);
    test_physical_example_todo_physical_item_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_todo_physical_item_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/todo_mvc_physical/todo_mvc_physical.bn",
        "--event",
        "12:1:text:Edited title",
        "--expect-state",
        "state[3]=text:Edited title",
    });
    const test_physical_example_todo_physical_remove_cmd = b.addRunArtifact(exe);
    test_physical_example_todo_physical_remove_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_todo_physical_remove_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/todo_mvc_physical/todo_mvc_physical.bn",
        "--event",
        "11:1",
        "--expect-state",
        "state[2]=number:1",
    });
    const test_physical_example_todo_physical_step = b.step("test-physical-example-todo-mvc-physical", "Verify canonical SOURCE physical TodoMVC source bags through Physical Runtime");
    test_physical_example_todo_physical_step.dependOn(&test_physical_example_todo_physical_store_cmd.step);
    test_physical_example_todo_physical_step.dependOn(&test_physical_example_todo_physical_item_cmd.step);
    test_physical_example_todo_physical_step.dependOn(&test_physical_example_todo_physical_remove_cmd.step);
    test_runtime_step.dependOn(test_physical_example_todo_physical_step);

    const test_physical_example_pong_cmd = b.addRunArtifact(exe);
    test_physical_example_pong_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_pong_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/pong/pong.bn",
        "--event",
        "0:1:text:Enter",
        "--expect-state",
        "state[0]=text:Enter",
    });
    const test_physical_example_pong_step = b.step("test-physical-example-pong", "Verify canonical SOURCE pong input lane through Physical Runtime");
    test_physical_example_pong_step.dependOn(&test_physical_example_pong_cmd.step);
    test_runtime_step.dependOn(test_physical_example_pong_step);

    const test_physical_example_arkanoid_cmd = b.addRunArtifact(exe);
    test_physical_example_arkanoid_cmd.step.dependOn(b.getInstallStep());
    test_physical_example_arkanoid_cmd.addArgs(&.{
        "physical-run",
        "examples/source_physical/arkanoid/arkanoid.bn",
        "--event",
        "0:1:text:Left",
        "--expect-state",
        "state[0]=text:Left",
    });
    const test_physical_example_arkanoid_step = b.step("test-physical-example-arkanoid", "Verify canonical SOURCE arkanoid input lane through Physical Runtime");
    test_physical_example_arkanoid_step.dependOn(&test_physical_example_arkanoid_cmd.step);
    test_runtime_step.dependOn(test_physical_example_arkanoid_step);

    const codegen_zig_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/codegen_zig_tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "boon", .module = boon_mod },
            },
        }),
    });
    const run_codegen_zig_tests = b.addRunArtifact(codegen_zig_tests);

    const run_generated_counter_cmd = b.addRunArtifact(generated_counter_exe);
    const run_generated_counter_step = b.step("run-generated-counter", "Run generated Zig counter executable");
    run_generated_counter_step.dependOn(&run_generated_counter_cmd.step);

    const run_generated_todo_cmd = b.addRunArtifact(generated_todo_exe);
    const run_generated_todo_step = b.step("run-generated-todo-mvc-headless", "Run generated Zig TodoMVC headless state-lane executable");
    run_generated_todo_step.dependOn(&run_generated_todo_cmd.step);

    const run_generated_list_latest_cmd = b.addRunArtifact(generated_list_latest_exe);
    const run_generated_list_latest_step = b.step("run-generated-list-latest-dynamic", "Run generated Zig dynamic List/latest executable self-tests");
    run_generated_list_latest_step.dependOn(&run_generated_list_latest_cmd.step);

    const run_generated_interval_cmd = b.addRunArtifact(generated_interval_exe);
    const run_generated_interval_step = b.step("run-generated-interval", "Run generated Zig interval executable");
    run_generated_interval_step.dependOn(&run_generated_interval_cmd.step);

    const run_generated_cells_cmd = b.addRunArtifact(generated_cells_exe);
    const run_generated_cells_step = b.step("run-generated-cells", "Run generated Zig cells executable");
    run_generated_cells_step.dependOn(&run_generated_cells_cmd.step);

    const run_generated_pong_cmd = b.addRunArtifact(generated_pong_exe);
    const run_generated_pong_step = b.step("run-generated-pong", "Run generated Zig pong executable");
    run_generated_pong_step.dependOn(&run_generated_pong_cmd.step);

    const run_generated_arkanoid_cmd = b.addRunArtifact(generated_arkanoid_exe);
    const run_generated_arkanoid_step = b.step("run-generated-arkanoid", "Run generated Zig arkanoid executable");
    run_generated_arkanoid_step.dependOn(&run_generated_arkanoid_cmd.step);

    const run_generated_structured_runtime_plan_cmd = b.addRunArtifact(generated_structured_runtime_plan_exe);
    const run_generated_structured_runtime_plan_step = b.step("run-generated-structured-runtime-plan", "Run generated Zig structured runtime plan executable self-validation");
    run_generated_structured_runtime_plan_step.dependOn(&run_generated_structured_runtime_plan_cmd.step);

    const test_codegen_zig_step = b.step("test-codegen-zig", "Run Physical IR to Zig codegen tests and generated executables");
    test_codegen_zig_step.dependOn(&run_codegen_zig_tests.step);
    test_codegen_zig_step.dependOn(run_generated_counter_step);
    test_codegen_zig_step.dependOn(run_generated_todo_step);
    test_codegen_zig_step.dependOn(run_generated_list_latest_step);
    test_codegen_zig_step.dependOn(run_generated_interval_step);
    test_codegen_zig_step.dependOn(run_generated_cells_step);
    test_codegen_zig_step.dependOn(run_generated_pong_step);
    test_codegen_zig_step.dependOn(run_generated_arkanoid_step);
    test_codegen_zig_step.dependOn(run_generated_structured_runtime_plan_step);
}
