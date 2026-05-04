const std = @import("std");
const boon = @import("boon");

const Sources = struct {
    source_counter: []const u8,
    single_document: []const u8,
    multi_run: []const u8,
    multi_widgets: []const u8,
    codegen_source: []const u8,
    cli_source: []const u8,
    host_source: []const u8,
    browser_source: []const u8,
    raybox_app_source: []const u8,
    raybox_adapter_source: []const u8,
    raybox_projection_source: []const u8,
    raybox_verify_examples_source: []const u8,
    raybox_playground_project_source: []const u8,
    raybox_clay_bridge_source: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const sources = Sources{
        .source_counter = try readFileAlloc(allocator, init.io, "fixtures/generic_apps/source_counter/app.bn"),
        .single_document = try readFileAlloc(allocator, init.io, "fixtures/generic_apps/single_document/app.bn"),
        .multi_run = try readFileAlloc(allocator, init.io, "fixtures/generic_apps/multi_module/RUN.bn"),
        .multi_widgets = try readFileAlloc(allocator, init.io, "fixtures/generic_apps/multi_module/Widgets.bn"),
        .codegen_source = try readFileAlloc(allocator, init.io, "src/codegen_zig.zig"),
        .cli_source = try readFileAlloc(allocator, init.io, "src/cli.zig"),
        .host_source = try readFileAlloc(allocator, init.io, "src/boon_runtime_host.zig"),
        .browser_source = try readFileAlloc(allocator, init.io, "browser/boon-browser.mjs"),
        .raybox_app_source = try readFileAlloc(allocator, init.io, "raybox/src/app/app.zig"),
        .raybox_adapter_source = try readFileAlloc(allocator, init.io, "raybox/src/boon_adapter/document_adapter.zig"),
        .raybox_projection_source = try readFileAlloc(allocator, init.io, "raybox/src/render/physical_projection.zig"),
        .raybox_verify_examples_source = try readFileAlloc(allocator, init.io, "raybox/src/tools/verify_examples.zig"),
        .raybox_playground_project_source = try readFileAlloc(allocator, init.io, "raybox/src/app/playground_project.zig"),
        .raybox_clay_bridge_source = try readFileAlloc(allocator, init.io, "raybox/src/clay/clay_bridge.zig"),
    };

    try verifyCompilerPipeline(allocator, sources.source_counter);
    try verifyDocumentRuntime(allocator, sources.single_document);
    try verifyPhysicalRuntime(allocator, sources.source_counter);
    try verifyGeneratedZig(allocator, sources.source_counter);
    try verifyRuntimeHost(allocator, sources);
    try verifyStructuralGenericity(sources);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    try stdout_writer.interface.writeAll("verify-genericity ok\n");
    try stdout_writer.interface.writeAll("fixtures: fixtures/generic_apps/source_counter/app.bn, fixtures/generic_apps/single_document/app.bn, fixtures/generic_apps/multi_module/RUN.bn\n");
    try stdout_writer.interface.flush();
}

fn verifyDocumentRuntime(allocator: std.mem.Allocator, source: []const u8) !void {
    var parsed = switch (try boon.parser.parseAlloc(allocator, source)) {
        .ok => |document| document,
        .err => |failure| return failDiagnostic("parse single_document", failure),
    };
    defer parsed.deinit();
    var lowered_hir = switch (try boon.hir.lowerAlloc(allocator, source)) {
        .ok => |document| document,
        .err => |failure| return failDiagnostic("hir single_document", failure),
    };
    defer lowered_hir.deinit();
    var lowered_flow = switch (try boon.flow_ir.lowerAlloc(allocator, source)) {
        .ok => |document| document,
        .err => |failure| return failDiagnostic("flow single_document", failure),
    };
    defer lowered_flow.deinit();

    const outcome = try boon.headless.runAlloc(allocator, source, .{});
    switch (outcome) {
        .ok => |session| {
            var runtime = session;
            defer runtime.deinit();
            const rendered = try runtime.renderAlloc(allocator);
            defer allocator.free(rendered);
            try requireContains(rendered, "Generic Browser Fixture", "generic single document render");
        },
        .err => |failure| return failDiagnostic("run single_document", failure),
    }
}

fn readFileAlloc(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
}

fn verifyCompilerPipeline(allocator: std.mem.Allocator, source_counter: []const u8) !void {
    var parsed = switch (try boon.parser.parseAlloc(allocator, source_counter)) {
        .ok => |document| document,
        .err => |failure| return failDiagnostic("parse source_counter", failure),
    };
    defer parsed.deinit();

    var lowered_hir = switch (try boon.hir.lowerAlloc(allocator, source_counter)) {
        .ok => |document| document,
        .err => |failure| return failDiagnostic("hir source_counter", failure),
    };
    defer lowered_hir.deinit();
    if (lowered_hir.definition_count == 0) return error.GenericFixtureMissingHirDefinitions;

    var lowered_flow = switch (try boon.flow_ir.lowerAlloc(allocator, source_counter)) {
        .ok => |document| document,
        .err => |failure| return failDiagnostic("flow source_counter", failure),
    };
    defer lowered_flow.deinit();
    if (lowered_flow.nodes.len == 0 or lowered_flow.stateful_count == 0) return error.GenericFixtureMissingFlowState;
}

fn verifyPhysicalRuntime(allocator: std.mem.Allocator, source_counter: []const u8) !void {
    var program = switch (try boon.physical_ir.lowerAlloc(allocator, source_counter)) {
        .ok => |program| program,
        .err => |failure| return failDiagnostic("physical source_counter", failure),
    };
    defer program.deinit();
    if (program.source_slots.len != 1 or program.state_slots.len != 1) return error.GenericFixtureUnexpectedPhysicalShape;

    var runtime = try boon.physical_runtime.Runtime.initAlloc(allocator, &program);
    defer runtime.deinit();
    try runtime.executeInitializers(&program);
    try runtime.plugSource(0, 1);
    const result = try runtime.dispatchEvent(.{
        .source_slot_id = 0,
        .binding_id_or_generation = 1,
        .scope_or_instance_id = 0,
        .payload = .pulse,
    });
    if (result != .queued) return error.GenericFixtureDispatchNotQueued;
    try runtime.processQueuedEvents(&program);

    const snapshot = try runtime.stateSnapshotAlloc(allocator);
    defer allocator.free(snapshot);
    if (std.mem.indexOf(u8, snapshot, "state[0]=number:1") == null) return error.GenericFixtureBadPhysicalState;
}

fn verifyGeneratedZig(allocator: std.mem.Allocator, source_counter: []const u8) !void {
    var program = switch (try boon.physical_ir.lowerAlloc(allocator, source_counter)) {
        .ok => |program| program,
        .err => |failure| return failDiagnostic("physical source_counter for codegen", failure),
    };
    defer program.deinit();

    const generated = try boon.codegen_zig.generateAlloc(allocator, &program, .{
        .demo_event = .{ .source_slot_id = 0 },
        .source_path = "fixtures/generic_apps/source_counter/app.bn",
    });
    defer allocator.free(generated);
    try requireContains(generated, "runGeneratedPhysicalRuntimeAdapter", "generated adapter entrypoint");
    try requireContains(generated, "runtime.dispatchEvent", "generic runtime dispatch");
    try requireContains(generated, "generated_physical_program", "embedded physical program");
    try requireContains(generated, "fixtures/generic_apps/source_counter/app.bn", "generic source path");
    try requireMissing(generated, "AppState", "example-shaped generated app state");
    try requireMissing(generated, "switch (source_slot_id)", "hard-coded source dispatch switch");
    try requireMissing(generated, "GeneratedRuntimeAdapterMismatch", "parallel handwritten adapter comparison");
}

fn verifyRuntimeHost(allocator: std.mem.Allocator, sources: Sources) !void {
    const PersistCtx = struct {
        fn read(ptr: *anyopaque, read_allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8 {
            _ = ptr;
            _ = read_allocator;
            _ = key;
            return null;
        }

        fn write(ptr: *anyopaque, key: []const u8, value: []const u8) anyerror!void {
            _ = ptr;
            _ = key;
            _ = value;
        }

        fn deletePrefix(ptr: *anyopaque, prefix: []const u8) anyerror!void {
            _ = ptr;
            _ = prefix;
        }
    };

    const RouteCtx = struct {
        fn current(ptr: *anyopaque) []const u8 {
            _ = ptr;
            return "/";
        }

        fn goTo(ptr: *anyopaque, route: []const u8) anyerror!void {
            _ = ptr;
            _ = route;
        }
    };

    var persist_ctx: u8 = 0;
    var route_ctx: u8 = 0;
    var persist = boon.boon_runtime_host.PersistStore{
        .ptr = &persist_ctx,
        .read = PersistCtx.read,
        .write = PersistCtx.write,
        .deletePrefix = PersistCtx.deletePrefix,
    };
    var route = boon.boon_runtime_host.RouteStore{
        .ptr = &route_ctx,
        .current = RouteCtx.current,
        .goTo = RouteCtx.goTo,
    };
    var clock = boon.boon_runtime_host.VirtualClock{};
    var time = boon.boon_runtime_host.TimeSource{ .virtual = &clock };
    var host = try boon.boon_runtime_host.BoonRuntimeHost.init(allocator, &persist, &route, &time);
    defer host.deinit();
    try host.loadProject(.{
        .name = "genericity_multi_module_fixture",
        .entry_file = "RUN.bn",
        .files = &.{
            .{ .path = "RUN.bn", .contents = sources.multi_run },
            .{ .path = "Widgets.bn", .contents = sources.multi_widgets },
        },
    });
    switch (try host.runBuildFile()) {
        .not_present => {},
        else => return error.GenericFixtureUnexpectedBuildFile,
    }
    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => return error.GenericFixtureHostCompileDiagnostics,
    }
    _ = try host.start();
    const rendered = try host.renderTextAlloc(allocator);
    defer allocator.free(rendered);
    try requireContains(rendered, "Generic Widgets Fixture", "generic multi-module rendered text");
}

fn verifyStructuralGenericity(sources: Sources) !void {
    try requireMissing(sources.codegen_source, "fn appSnapshotAlloc", "old generated AppState snapshot helper");
    try requireMissing(sources.codegen_source, "assertGeneratedRuntimeAdapterMatchesApp", "old generated AppState adapter comparison");
    try requireMissing(sources.codegen_source, "switch (source_slot_id)", "generated source-slot switch");
    try requireMissing(sources.cli_source, "unsupported physical example", "browser physical-state example restriction");
    try requireMissing(sources.host_source, "if (!std.mem.eql(u8, module.name, \"Assets\")) continue;", "Assets-only module emission");
    try requireMissing(sources.host_source, "std.mem.eql(u8, module.name, \"Theme\")", "Theme-specific module rewrite branch");
    try requireContains(sources.browser_source, "manifest?.served_source?.name", "served browser source default");
    try requireContains(sources.browser_source, "createFetchRenderedTextProvider", "generic browser served-source text provider");
    try requireContains(sources.cli_source, "/__boon/render-text", "generic browser render-text endpoint");
    try requireContains(sources.browser_source, "isPhysicalHost()", "generic browser physical target predicate");
    try requireMissing(sources.browser_source, "exampleName", "browser example-name host input");
    try requireMissing(sources.browser_source, "supported_examples", "browser bundled example registry");
    try requireMissing(sources.browser_source, "exampleName !== \"todo_mvc_physical\"", "browser physical-state example-name restriction");
    try requireMissing(sources.raybox_app_source, "return error.UnsupportedMultiFileExample", "Raybox native multi-file example-name branch");
    try requireMissing(sources.raybox_app_source, "\"example\":\"todo_mvc_physical\"", "Raybox hard-coded web state example");
    try requireMissing(sources.raybox_app_source, "todo_mvc", "Raybox app TodoMVC runtime branch");
    try requireMissing(sources.raybox_app_source, "cells", "Raybox app cells runtime branch");
    try requireMissing(sources.raybox_app_source, "pong", "Raybox app Pong runtime branch");
    try requireMissing(sources.raybox_adapter_source, "todo_mvc_physical", "Raybox adapter example-name branch");
    try requireMissing(sources.raybox_projection_source, "TodoMVC", "Raybox projection TodoMVC branch");
    try requireMissing(sources.raybox_projection_source, "usesPhysicalTodoLayout", "Raybox projection physical Todo layout detector");
    try requireMissing(sources.raybox_projection_source, "usesGenericTodoLayout", "Raybox projection generic Todo layout detector");
    try requireMissing(sources.raybox_projection_source, "itemsleft", "Raybox projection Todo footer text scraping");
    try requireMissing(sources.raybox_projection_source, "PONG", "Raybox projection Pong text detector");
    try requireMissing(sources.raybox_verify_examples_source, "isCellsExample", "Raybox verifier example-name render mode branch");
    try requireMissing(sources.raybox_verify_examples_source, "dblclick_cells_cell", "Raybox verifier cells-specific action");
    try requireMissing(sources.raybox_verify_examples_source, "assert_cells_cell_text", "Raybox verifier cells-specific assertion");
    try requireMissing(sources.raybox_verify_examples_source, "assert_cells_row_visible", "Raybox verifier cells-specific row assertion");
    try requireContains(sources.raybox_verify_examples_source, "expectedUsesCompactRender", "Raybox verifier data-driven compact render mode");
    try requireMissing(sources.raybox_playground_project_source, "todo_mvc_physical", "Raybox bundled project example-name identity");
    try requireMissing(sources.raybox_clay_bridge_source, "std.mem.eql(u8, example_name", "Raybox shell example-name hint branch");
    try requireMissing(sources.raybox_clay_bridge_source, "\"pong\"", "Raybox shell Pong hint branch");
    try requireMissing(sources.raybox_clay_bridge_source, "\"cells\"", "Raybox shell cells hint branch");
}

fn failDiagnostic(context: []const u8, failure: boon.diag.Diagnostic) error{GenericityDiagnostic} {
    std.debug.print("{s}: {s}\n", .{ context, failure.message });
    return error.GenericityDiagnostic;
}

fn requireContains(haystack: []const u8, needle: []const u8, label: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("missing {s}: {s}\n", .{ label, needle });
        return error.GenericityExpectedTextMissing;
    }
}

fn requireMissing(haystack: []const u8, needle: []const u8, label: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("forbidden {s}: {s}\n", .{ label, needle });
        return error.GenericityForbiddenTextPresent;
    }
}
