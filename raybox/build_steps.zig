const std = @import("std");
const playground_layout = @import("src/app/playground_layout.zig");

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    io_backend: []const u8,
    selected_example: ?[]const u8,
    screenshot_example: []const u8,
    build_only: bool,
};

pub fn addRayboxSteps(b: *std.Build, options: Options) !void {
    const target = options.target;
    const optimize: std.builtin.OptimizeMode = if (isWebTarget(target.result) and options.optimize == .Debug)
        .ReleaseFast
    else if (!isWebTarget(target.result) and options.optimize == .Debug)
        .ReleaseFast
    else
        options.optimize;
    const selected_example = options.selected_example;
    const screenshot_example = options.screenshot_example;
    const build_only = options.build_only;

    const dep_emsdk = if (isWebTarget(target.result))
        b.dependency("emsdk", .{})
    else
        null;
    const dep_sdl = if (isWebTarget(target.result))
        b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            .preferred_linkage = .static,
            .system_include_path = dep_emsdk.?.path("upstream/emscripten/cache/sysroot/include"),
            .sanitize_c = .off,
        })
    else
        b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            .preferred_linkage = .static,
            .sanitize_c = .off,
        });
    const sdl_mod = createSdlModule(b, dep_sdl, target, optimize, dep_emsdk);
    const playground_sources_mod = try createPlaygroundSourcesOptions(b);
    const playground_layout_mod = createPlaygroundLayoutModule(b, target, optimize);

    const boon_mod = createBoonModule(b, "raybox_app", target, optimize, options.io_backend);

    const raybox_mod = b.createModule(.{
        .root_source_file = b.path("raybox/raybox_module.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "boon", .module = boon_mod },
            .{ .name = "playground_layout", .module = playground_layout_mod },
        },
    });
    const text_lib = buildTextCModule(b, "raybox_text_c_app", target, optimize, dep_emsdk);
    raybox_mod.linkLibrary(text_lib);
    raybox_mod.linkLibrary(buildClayCModule(b, "raybox_clay_c_app", target, optimize, dep_emsdk));
    raybox_mod.addIncludePath(b.path("raybox/src/clay"));

    const unit_tests = b.addTest(.{
        .root_module = raybox_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test-raybox", "Run Raybox unit and bridge preflight tests");
    test_step.dependOn(&run_unit_tests.step);

    addTextVerifiers(b, optimize, options.io_backend);
    try addExampleVerifiers(b, optimize, options.io_backend, selected_example, build_only);
    try addPhysicalVerifiers(b, optimize, options.io_backend, selected_example, build_only);
    addNativeBenchmark(b, optimize, options.io_backend);

    const app_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "boon", .module = boon_mod },
            .{ .name = "raybox", .module = raybox_mod },
            .{ .name = "sdl", .module = sdl_mod },
            .{ .name = "playground_sources", .module = playground_sources_mod },
            .{ .name = "playground_layout", .module = playground_layout_mod },
            .{ .name = "example_registry", .module = b.createModule(.{
                .root_source_file = b.path("raybox/src/playground/generated_example_registry.zig"),
                .target = target,
                .optimize = optimize,
            }) },
        },
    });

    const run_playground_step = b.step("run-raybox", "Run the Boon playground Raybox shell");
    const image_preflight_exe = b.addExecutable(.{
        .name = "raybox-image-preflight",
        .root_module = b.createModule(.{
            .root_source_file = b.path("raybox/src/tools/image_preflight.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const screenshot_artifacts_exe = b.addExecutable(.{
        .name = "raybox-screenshot-artifacts",
        .root_module = b.createModule(.{
            .root_source_file = b.path("raybox/src/tools/screenshot_artifacts.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const browser_screenshot_exe = b.addExecutable(.{
        .name = "raybox-browser-screenshot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("raybox/src/tools/browser_screenshot.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const image_preflight_run = b.addRunArtifact(image_preflight_exe);
    if (b.args) |args| image_preflight_run.addArgs(args);
    b.step("raybox-image-preflight", "Check local image dimensions/size before model upload").dependOn(&image_preflight_run.step);
    const screenshot_artifacts_run = b.addRunArtifact(screenshot_artifacts_exe);
    if (b.args) |args| screenshot_artifacts_run.addArgs(args);
    b.step("raybox-screenshot-artifacts", "Create bounded screenshot analysis previews from image artifacts").dependOn(&screenshot_artifacts_run.step);
    const browser_screenshot_run = b.addRunArtifact(browser_screenshot_exe);
    if (b.args) |args| browser_screenshot_run.addArgs(args);
    b.step("raybox-browser-screenshot", "Capture the browser canvas screenshot through Chrome without Node").dependOn(&browser_screenshot_run.step);

    const screenshot_native_step = b.step("screenshot-raybox-native", "Capture a native screenshot and write a bounded analysis preview");
    const screenshot_browser_step = b.step("screenshot-raybox-browser", "Capture a browser canvas screenshot and write a bounded analysis preview");
    const screenshot_terminal_step = b.step("screenshot-raybox-terminal", "Write bounded analysis previews for terminal screenshot artifacts");
    const screenshot_terminal_cmd = b.addRunArtifact(screenshot_artifacts_exe);
    screenshot_terminal_cmd.addArgs(&.{
        "terminal",
        "--delete-oversized",
    });
    screenshot_terminal_step.dependOn(&screenshot_terminal_cmd.step);

    if (isWebTarget(target.result)) {
        const web_emsdk = dep_emsdk.?;
        const playground_lib = b.addLibrary(.{
            .name = "boon-playground-raybox",
            .root_module = app_mod,
        });
        const link_step = try emLinkStep(b, .{
            .target = target,
            .optimize = optimize,
            .lib_main = playground_lib,
            .emsdk = web_emsdk,
            .extra_args = &.{
                "-sUSE_WEBGL2=1",
                "-sMALLOC='emmalloc'",
                "-sSTACK_SIZE=16MB",
                "-sALLOW_MEMORY_GROWTH=1",
                "-sINITIAL_MEMORY=512MB",
                "-sMAXIMUM_MEMORY=4GB",
                "-sABORTING_MALLOC=0",
            },
        });
        const browser_visual_report = "zig-out/reports/browser_canvas_visual.json";
        const browser_smoke_capture = b.addRunArtifact(browser_screenshot_exe);
        browser_smoke_capture.addArgs(&.{
            "zig-out/web",
            "zig-out/verification/browser_canvas/run_playground_web.png",
            browser_visual_report,
        });
        browser_smoke_capture.step.dependOn(&link_step.step);
        const browser_smoke = b.addSystemCommand(&.{
            "node",
            "raybox/tools/browser_canvas_smoke.js",
            "zig-out/web",
            "zig-out/verification/browser_canvas/run_playground_web.png",
            "zig-out/reports/browser_canvas_smoke.json",
            browser_visual_report,
        });
        browser_smoke.step.dependOn(&browser_smoke_capture.step);
        run_playground_step.dependOn(&browser_smoke.step);

        const screenshot_native_unavailable = b.addSystemCommand(&.{
            "sh",
            "-c",
            "echo 'screenshot-native requires a native target, not wasm32-emscripten' >&2; exit 1",
        });
        screenshot_native_step.dependOn(&screenshot_native_unavailable.step);

        const browser_screenshot_raw = "zig-out/screenshot-raw/browser/run_playground_web.png";
        const browser_screenshot_smoke = b.addRunArtifact(browser_screenshot_exe);
        browser_screenshot_smoke.addArgs(&.{
            "zig-out/web",
            browser_screenshot_raw,
            "zig-out/reports/screenshot_browser_smoke.json",
        });
        browser_screenshot_smoke.step.dependOn(&link_step.step);
        const browser_screenshot_pack = b.addRunArtifact(screenshot_artifacts_exe);
        browser_screenshot_pack.addArgs(&.{
            "browser",
            "--source",
            "zig-out/screenshot-raw/browser",
            "--out",
            "zig-out/screenshots/browser",
            "--manifest",
            "zig-out/reports/screenshot_browser.json",
            "--delete-oversized",
        });
        browser_screenshot_pack.step.dependOn(&browser_screenshot_smoke.step);
        screenshot_browser_step.dependOn(&browser_screenshot_pack.step);
    } else {
        const playground_exe = b.addExecutable(.{
            .name = "boon-playground-raybox",
            .root_module = app_mod,
        });
        b.installArtifact(playground_exe);
        const run_cmd = addCosmicBackgroundRunArtifact(b, playground_exe);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        run_playground_step.dependOn(&run_cmd.step);

        const screenshot_browser_unavailable = b.addSystemCommand(&.{
            "sh",
            "-c",
            "echo 'screenshot-browser requires -Dtarget=wasm32-emscripten' >&2; exit 1",
        });
        screenshot_browser_step.dependOn(&screenshot_browser_unavailable.step);

        const native_screenshot_raw = b.fmt("zig-out/screenshot-raw/native/{s}.png", .{screenshot_example});
        const native_screenshot_run = addCosmicBackgroundRunArtifact(b, playground_exe);
        native_screenshot_run.addArgs(&.{
            b.fmt("--example={s}", .{screenshot_example}),
            b.fmt("--capture-frame={s}", .{native_screenshot_raw}),
            b.fmt("--capture-size={d}x{d}", .{ playground_layout.window_width, playground_layout.window_height }),
            "--exit-after-frames=8",
        });
        const native_screenshot_pack = b.addRunArtifact(screenshot_artifacts_exe);
        native_screenshot_pack.addArgs(&.{
            "native",
            "--source",
            "zig-out/screenshot-raw/native",
            "--out",
            "zig-out/screenshots/native",
            "--manifest",
            "zig-out/reports/screenshot_native.json",
            "--delete-oversized",
        });
        native_screenshot_pack.step.dependOn(&native_screenshot_run.step);
        screenshot_native_step.dependOn(&native_screenshot_pack.step);

        const shell_layout_mod = b.createModule(.{
            .root_source_file = b.path("raybox/src/tools/verify_playground_shell_layout.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "playground_layout", .module = playground_layout_mod },
            },
        });
        const shell_layout_exe = b.addExecutable(.{
            .name = "verify-raybox-shell-layout",
            .root_module = shell_layout_mod,
        });
        const shell_layout_run = b.addRunArtifact(shell_layout_exe);
        b.step("verify-raybox-shell-layout", "Verify playground shell dimensions stay readable and hit-testable").dependOn(&shell_layout_run.step);

        const native_events_mod = b.createModule(.{
            .root_source_file = b.path("raybox/src/tools/verify_playground_native_events.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "playground_app", .module = b.createModule(.{
                    .root_source_file = b.path("raybox/src/app/app.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "boon", .module = boon_mod },
                        .{ .name = "raybox", .module = raybox_mod },
                        .{ .name = "sdl", .module = sdl_mod },
                        .{ .name = "playground_sources", .module = playground_sources_mod },
                        .{ .name = "playground_layout", .module = playground_layout_mod },
                        .{ .name = "example_registry", .module = b.createModule(.{
                            .root_source_file = b.path("raybox/src/playground/generated_example_registry.zig"),
                            .target = target,
                            .optimize = optimize,
                        }) },
                    },
                }) },
                .{ .name = "boon", .module = boon_mod },
                .{ .name = "raybox", .module = raybox_mod },
                .{ .name = "sdl", .module = sdl_mod },
                .{ .name = "playground_sources", .module = playground_sources_mod },
                .{ .name = "playground_layout", .module = playground_layout_mod },
                .{ .name = "example_registry", .module = b.createModule(.{
                    .root_source_file = b.path("raybox/src/playground/generated_example_registry.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        });
        const native_events_exe = b.addExecutable(.{
            .name = "verify-raybox-native-events",
            .root_module = native_events_mod,
        });
        const native_events_run = b.addRunArtifact(native_events_exe);
        b.step("verify-raybox-native-events", "Verify native playground clicks and text entry through projected controls").dependOn(&native_events_run.step);
    }
}

fn addCosmicBackgroundRunArtifact(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
) *std.Build.Step.Run {
    const launcher = b.addExecutable(.{
        .name = "cosmic-background-launch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/cosmic_background_launch_compat.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    const run = b.addRunArtifact(launcher);
    run.addArgs(&.{ "--workspace", "boon-zig", "--" });
    run.addArtifactArg(artifact);
    return run;
}

fn createPlaygroundSourcesOptions(b: *std.Build) !*std.Build.Module {
    const options = b.addOptions();
    inline for (playground_source_files) |entry| {
        const contents = try std.Io.Dir.cwd().readFileAlloc(b.graph.io, entry.path, b.allocator, .limited(4 * 1024 * 1024));
        options.addOption([]const u8, entry.option_name, contents);
    }
    return options.createModule();
}

fn createPlaygroundLayoutModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("raybox/src/app/playground_layout.zig"),
        .target = target,
        .optimize = optimize,
    });
}

const PlaygroundSourceFile = struct {
    option_name: []const u8,
    path: []const u8,
};

const playground_source_files = [_]PlaygroundSourceFile{
    .{ .option_name = "run_bn", .path = "examples/upstream/todo_mvc_physical/RUN.bn" },
    .{ .option_name = "build_bn", .path = "examples/upstream/todo_mvc_physical/BUILD.bn" },
    .{ .option_name = "generated_assets_bn", .path = "examples/upstream/todo_mvc_physical/Generated/Assets.bn" },
    .{ .option_name = "theme_bn", .path = "examples/upstream/todo_mvc_physical/Theme/Theme.bn" },
    .{ .option_name = "professional_bn", .path = "examples/upstream/todo_mvc_physical/Theme/Professional.bn" },
    .{ .option_name = "glassmorphism_bn", .path = "examples/upstream/todo_mvc_physical/Theme/Glassmorphism.bn" },
    .{ .option_name = "neobrutalism_bn", .path = "examples/upstream/todo_mvc_physical/Theme/Neobrutalism.bn" },
    .{ .option_name = "neumorphism_bn", .path = "examples/upstream/todo_mvc_physical/Theme/Neumorphism.bn" },
    .{ .option_name = "checkbox_active_svg", .path = "examples/upstream/todo_mvc_physical/assets/icons/checkbox_active.svg" },
    .{ .option_name = "checkbox_completed_svg", .path = "examples/upstream/todo_mvc_physical/assets/icons/checkbox_completed.svg" },
};

fn addUnsupportedVerifier(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    selected_example: ?[]const u8,
    build_only: bool,
) void {
    const cmd = b.addSystemCommand(&.{ "sh", "tools/unsupported_verifier.sh", name });
    if (selected_example) |example| {
        cmd.addArg(example);
    } else {
        cmd.addArg("-");
    }
    cmd.addArg(if (build_only) "true" else "false");
    b.step(name, description).dependOn(&cmd.step);
}

fn isWebTarget(target: std.Target) bool {
    return target.os.tag == .emscripten;
}

fn createSdlModule(
    b: *std.Build,
    dep_sdl: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dep_emsdk: ?*std.Build.Dependency,
) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/app/sdl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(dep_sdl.path("include"));
    if (dep_emsdk) |emsdk| {
        mod.addSystemIncludePath(emsdk.path("upstream/emscripten/cache/sysroot/include"));
    }
    mod.linkLibrary(dep_sdl.artifact("SDL3"));
    return mod;
}

const EmLinkOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_main: *std.Build.Step.Compile,
    emsdk: *std.Build.Dependency,
    extra_args: []const []const u8 = &.{},
};

fn emLinkStep(b: *std.Build, options: EmLinkOptions) !*std.Build.Step.InstallDir {
    const emcc = b.addSystemCommand(&.{emTool(b, options.emsdk, "emcc").getPath(b)});
    emcc.setName("emcc");
    if (options.optimize == .Debug) {
        emcc.addArgs(&.{ "-Og", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1" });
    } else {
        emcc.addArg("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            emcc.addArg("-Oz");
        } else {
            emcc.addArg("-O3");
        }
    }
    for (options.extra_args) |arg| emcc.addArg(arg);
    emcc.addArtifactArg(options.lib_main);
    for (options.lib_main.getCompileDependencies(false)) |item| {
        if (item.kind == .lib) emcc.addArtifactArg(item);
    }
    emcc.addArg("-o");
    const out_file = emcc.addOutputFileArg(b.fmt("{s}.html", .{options.lib_main.name}));
    const install = b.addInstallDirectory(.{
        .source_dir = out_file.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    install.step.dependOn(&emcc.step);
    return install;
}

fn emTool(b: *std.Build, emsdk: *std.Build.Dependency, tool: []const u8) std.Build.LazyPath {
    return emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", tool }));
}

fn buildTextCModule(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dep_emsdk: ?*std.Build.Dependency,
) *std.Build.Step.Compile {
    const c_mod = b.addModule(b.fmt("{s}_mod", .{name}), .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const lib = b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = c_mod,
    });
    c_mod.addCSourceFile(.{
        .file = b.path("raybox/src/text/fontstash_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined", "-Iraybox/src/text" },
    });
    if (dep_emsdk) |emsdk| {
        c_mod.addSystemIncludePath(emsdk.path("upstream/emscripten/cache/sysroot/include"));
    }
    if (target.result.os.tag == .linux) {
        c_mod.linkSystemLibrary("m", .{});
    }
    return lib;
}

fn buildClayCModule(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dep_emsdk: ?*std.Build.Dependency,
) *std.Build.Step.Compile {
    const c_mod = b.addModule(b.fmt("{s}_mod", .{name}), .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const lib = b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = c_mod,
    });
    c_mod.addCSourceFile(.{
        .file = b.path("raybox/src/clay/clay_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined", "-DCLAY_DISABLE_SIMD", "-Iraybox/src/clay" },
    });
    if (dep_emsdk) |emsdk| {
        c_mod.addSystemIncludePath(emsdk.path("upstream/emscripten/cache/sysroot/include"));
    }
    if (target.result.os.tag == .linux) {
        c_mod.linkSystemLibrary("m", .{});
    }
    return lib;
}

fn addTextVerifiers(b: *std.Build, optimize: std.builtin.OptimizeMode, io_backend: []const u8) void {
    const native_target = b.graph.host;
    const native_raybox_mod = buildRayboxModuleForTarget(b, "verify_text_native", native_target, optimize, io_backend, null);
    const native_text_c = buildTextCModule(b, "raybox_text_c_verify_native", native_target, optimize, null);
    native_raybox_mod.linkLibrary(native_text_c);
    const native_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/tools/verify_text_native.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "raybox", .module = native_raybox_mod },
        },
    });
    const native_exe = b.addExecutable(.{
        .name = "verify-raybox-text-native",
        .root_module = native_mod,
    });
    const native_run = b.addRunArtifact(native_exe);
    b.step("verify-raybox-text-native", "Verify FontStash text metrics and glyph atlas natively").dependOn(&native_run.step);

    const web_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .emscripten,
    });
    const web_emsdk = b.dependency("emsdk", .{});
    const web_raybox_mod = buildRayboxModuleForTarget(b, "verify_text_web", web_target, optimize, io_backend, web_emsdk);
    const web_text_c = buildTextCModule(b, "raybox_text_c_verify_web", web_target, optimize, web_emsdk);
    web_raybox_mod.linkLibrary(web_text_c);
    const web_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/tools/verify_text_web.zig"),
        .target = web_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "raybox", .module = web_raybox_mod },
        },
    });
    const web_lib = b.addLibrary(.{
        .name = "verify-raybox-text-web",
        .root_module = web_mod,
    });
    const emcc = b.addSystemCommand(&.{
        emTool(b, web_emsdk, "emcc").getPath(b),
        "-sENVIRONMENT=node",
        "-sEXIT_RUNTIME=1",
        "-sSINGLE_FILE=1",
    });
    emcc.addArtifactArg(web_lib);
    emcc.addArtifactArg(web_text_c);
    emcc.addArg("-o");
    const web_js = emcc.addOutputFileArg("verify-text-web.js");

    const node = b.addSystemCommand(&.{"node"});
    node.addFileArg(web_js);
    node.step.dependOn(&emcc.step);
    b.step("verify-raybox-text-web", "Verify FontStash text metrics and glyph atlas through wasm32-emscripten").dependOn(&node.step);
}

fn addExampleVerifiers(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    io_backend: []const u8,
    selected_example: ?[]const u8,
    build_only: bool,
) !void {
    const native_target = b.graph.host;
    const native_raybox_mod = buildRayboxModuleForTarget(b, "verify_examples_native", native_target, optimize, io_backend, null);
    const native_text_c = buildTextCModule(b, "raybox_text_c_verify_examples_native", native_target, optimize, null);
    native_raybox_mod.linkLibrary(native_text_c);
    const native_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/tools/verify_examples_native.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "raybox", .module = native_raybox_mod },
            .{ .name = "example_registry", .module = b.createModule(.{
                .root_source_file = b.path("raybox/src/playground/generated_example_registry.zig"),
                .target = native_target,
                .optimize = optimize,
            }) },
        },
    });
    const native_exe = b.addExecutable(.{
        .name = "verify-raybox-examples-native",
        .root_module = native_mod,
    });
    const native_run = b.addRunArtifact(native_exe);
    native_run.addArg(selected_example orelse "-");
    native_run.addArg(if (build_only) "true" else "false");
    b.step("verify-raybox-examples-native", "Verify imported examples through native BoonRuntimeHost").dependOn(&native_run.step);

    const web_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .emscripten,
    });
    const web_optimize: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseFast else optimize;
    const web_emsdk = b.dependency("emsdk", .{});
    const web_raybox_mod = buildRayboxModuleForTarget(b, "verify_examples_web", web_target, web_optimize, io_backend, web_emsdk);
    const web_text_c = buildTextCModule(b, "raybox_text_c_verify_examples_web", web_target, web_optimize, web_emsdk);
    web_raybox_mod.linkLibrary(web_text_c);
    const web_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/tools/verify_examples_web.zig"),
        .target = web_target,
        .optimize = web_optimize,
        .imports = &.{
            .{ .name = "raybox", .module = web_raybox_mod },
            .{ .name = "example_registry", .module = b.createModule(.{
                .root_source_file = b.path("raybox/src/playground/generated_example_registry.zig"),
                .target = web_target,
                .optimize = web_optimize,
            }) },
        },
    });
    const web_lib = b.addLibrary(.{
        .name = "verify-raybox-examples-web",
        .root_module = web_mod,
    });
    const emcc = b.addSystemCommand(&.{
        emTool(b, web_emsdk, "emcc").getPath(b),
        "-sENVIRONMENT=node",
        "-sEXIT_RUNTIME=0",
        "-sSINGLE_FILE=1",
        "-sFORCE_FILESYSTEM=1",
        "-sNODERAWFS=1",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sMAXIMUM_MEMORY=4GB",
        "-sABORTING_MALLOC=0",
        "-sINITIAL_MEMORY=512MB",
        "-sSTACK_SIZE=16MB",
        "-sSTACK_OVERFLOW_CHECK=0",
    });
    emcc.addArtifactArg(web_lib);
    emcc.addArtifactArg(web_text_c);
    emcc.addArg("-o");
    const web_js = emcc.addOutputFileArg("verify-examples-web.js");

    const node = b.addSystemCommand(&.{"node"});
    node.addFileArg(web_js);
    node.addArg(selected_example orelse "-");
    node.addArg(if (build_only) "true" else "false");
    node.step.dependOn(&emcc.step);
    const step = b.step("verify-raybox-examples-web", "Verify imported examples through wasm32-emscripten BoonRuntimeHost and browser canvas");
    if (build_only) {
        step.dependOn(&node.step);
    } else {
        const browser = b.addSystemCommand(&.{ "zig", "build", "run-raybox", "-Dtarget=wasm32-emscripten" });
        browser.step.dependOn(&node.step);
        step.dependOn(&browser.step);
    }
}

fn addPhysicalVerifiers(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    io_backend: []const u8,
    selected_example: ?[]const u8,
    build_only: bool,
) !void {
    const native_target = b.graph.host;
    const native_raybox_mod = buildRayboxModuleForTarget(b, "verify_physical_native", native_target, optimize, io_backend, null);
    native_raybox_mod.linkLibrary(buildTextCModule(b, "raybox_text_c_verify_physical_native", native_target, optimize, null));
    const native_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/tools/verify_physical_native.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "raybox", .module = native_raybox_mod },
            .{ .name = "example_registry", .module = b.createModule(.{
                .root_source_file = b.path("raybox/src/playground/generated_example_registry.zig"),
                .target = native_target,
                .optimize = optimize,
            }) },
        },
    });
    const native_exe = b.addExecutable(.{
        .name = "verify-raybox-physical-native",
        .root_module = native_mod,
    });
    const native_run = b.addRunArtifact(native_exe);
    native_run.addArg(selected_example orelse "-");
    native_run.addArg(if (build_only) "true" else "false");
    b.step("verify-raybox-physical-native", "Verify physical TodoMVC projection natively").dependOn(&native_run.step);

    const web_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .emscripten });
    const web_optimize: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseFast else optimize;
    const web_emsdk = b.dependency("emsdk", .{});
    const web_raybox_mod = buildRayboxModuleForTarget(b, "verify_physical_web", web_target, web_optimize, io_backend, web_emsdk);
    const web_text_c = buildTextCModule(b, "raybox_text_c_verify_physical_web", web_target, web_optimize, web_emsdk);
    web_raybox_mod.linkLibrary(web_text_c);
    const web_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/tools/verify_physical_web.zig"),
        .target = web_target,
        .optimize = web_optimize,
        .imports = &.{
            .{ .name = "raybox", .module = web_raybox_mod },
            .{ .name = "example_registry", .module = b.createModule(.{
                .root_source_file = b.path("raybox/src/playground/generated_example_registry.zig"),
                .target = web_target,
                .optimize = web_optimize,
            }) },
        },
    });
    const web_lib = b.addLibrary(.{
        .name = "verify-raybox-physical-web",
        .root_module = web_mod,
    });
    const emcc = b.addSystemCommand(&.{
        emTool(b, web_emsdk, "emcc").getPath(b),
        "-sENVIRONMENT=node",
        "-sEXIT_RUNTIME=0",
        "-sSINGLE_FILE=1",
        "-sFORCE_FILESYSTEM=1",
        "-sNODERAWFS=1",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sMAXIMUM_MEMORY=4GB",
        "-sABORTING_MALLOC=0",
        "-sINITIAL_MEMORY=512MB",
        "-sSTACK_SIZE=16MB",
        "-sSTACK_OVERFLOW_CHECK=0",
    });
    emcc.addArtifactArg(web_lib);
    emcc.addArtifactArg(web_text_c);
    emcc.addArg("-o");
    const web_js = emcc.addOutputFileArg("verify-physical-web.js");
    const node = b.addSystemCommand(&.{"node"});
    node.addFileArg(web_js);
    node.addArg(selected_example orelse "-");
    node.addArg(if (build_only) "true" else "false");
    node.step.dependOn(&emcc.step);
    const step = b.step("verify-raybox-physical-web", "Verify physical project projection through wasm32-emscripten and browser canvas");
    if (build_only) {
        step.dependOn(&node.step);
    } else {
        const browser = b.addSystemCommand(&.{ "zig", "build", "run-raybox", "-Dtarget=wasm32-emscripten" });
        browser.step.dependOn(&node.step);
        step.dependOn(&browser.step);
    }
}

fn addNativeBenchmark(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    io_backend: []const u8,
) void {
    const native_target = b.graph.host;
    const native_raybox_mod = buildRayboxModuleForTarget(b, "bench_playground_native", native_target, optimize, io_backend, null);
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("raybox/src/tools/bench_playground_native.zig"),
        .target = native_target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "raybox", .module = native_raybox_mod },
        },
    });
    const bench_exe = b.addExecutable(.{
        .name = "bench-raybox-native",
        .root_module = bench_mod,
    });
    const bench_run = b.addRunArtifact(bench_exe);
    b.step("bench-raybox-native", "Benchmark native TodoMVC runtime/projection interaction latency").dependOn(&bench_run.step);
}

fn buildRayboxModuleForTarget(
    b: *std.Build,
    suffix: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    io_backend: []const u8,
    dep_emsdk: ?*std.Build.Dependency,
) *std.Build.Module {
    const boon_mod = createBoonModule(b, suffix, target, optimize, io_backend);
    const mod = b.createModule(.{
        .root_source_file = b.path("raybox/raybox_module.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "boon", .module = boon_mod },
            .{ .name = "playground_layout", .module = createPlaygroundLayoutModule(b, target, optimize) },
        },
    });
    mod.addIncludePath(b.path("raybox/src/clay"));
    mod.linkLibrary(buildClayCModule(b, b.fmt("raybox_clay_c_{s}", .{suffix}), target, optimize, dep_emsdk));
    return mod;
}

fn createBoonModule(
    b: *std.Build,
    suffix: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    io_backend: []const u8,
) *std.Build.Module {
    const boon_build_options = b.addOptions();
    boon_build_options.addOption([]const u8, "io_backend", io_backend);
    return b.addModule(b.fmt("boon_raybox_{s}", .{suffix}), .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "boon_build_options", .module = boon_build_options.createModule() },
        },
    });
}
