const std = @import("std");
const boon = @import("boon");

pub const boon_adapter = struct {
    pub const boon_runtime_host = requireBoonRuntimeHostBridge();
    pub const host = @import("boon_adapter/boon_runtime_host.zig");
    pub const document_snapshot = @import("boon_adapter/document_snapshot.zig");
    pub const document_adapter = @import("boon_adapter/document_adapter.zig");
};

pub const render = struct {
    pub const colors = @import("render/colors.zig");
    pub const batcher = @import("render/batcher.zig");
    pub const geometry = @import("render/geometry.zig");
    pub const renderer = @import("render/renderer.zig");
    pub const physical_projection = @import("render/physical_projection.zig");
    pub const svg_minimal = @import("render/svg_minimal.zig");
};

pub const clay = struct {
    pub const bridge = @import("clay/clay_bridge.zig");
};

pub const text = struct {
    pub const fontstash_backend = @import("text/fontstash_backend.zig");
    pub const font_manager = @import("text/font_manager.zig");
    pub const text_measure = @import("text/text_measure.zig");
};

fn requireBoonRuntimeHostBridge() type {
    comptime {
        if (!@hasDecl(boon, "boon_runtime_host")) {
            @compileError("local boon-zig module must expose pub const boon_runtime_host");
        }

        const bridge = boon.boon_runtime_host;
        const required_types = .{
            "BoonRuntimeHost",
            "BuildResult",
            "CompileResult",
            "RuntimeOutput",
            "TimeSource",
            "VirtualClock",
            "DocumentSnapshot",
            "SceneSnapshot",
            "RuntimeValue",
            "EventBinding",
            "Diagnostic",
            "PersistStore",
            "RouteStore",
            "PreviewEvent",
            "TextInputHandle",
            "Project",
            "ProjectFile",
        };
        for (required_types) |name| {
            if (!@hasDecl(bridge, name)) {
                @compileError("boon-zig boon_runtime_host is missing required public type: " ++ name);
            }
        }

        const Host = bridge.BoonRuntimeHost;
        const required_methods = .{
            "init",
            "deinit",
            "loadProject",
            "runBuildFile",
            "compileEntry",
            "start",
            "startNoSnapshot",
            "dispatch",
            "dispatchNoSnapshot",
            "renderTextAlloc",
            "textInputHandle",
            "setTextInputValueWithHandle",
            "pressTextInputKeyWithHandle",
            "blurTextInputWithHandle",
            "tick",
            "clearState",
        };
        for (required_methods) |name| {
            if (!@hasDecl(Host, name)) {
                @compileError("boon-zig BoonRuntimeHost is missing required method: " ++ name);
            }
        }

        return bridge;
    }
}

test "Phase 0 bridge preflight exposes runtime host contract" {
    const bridge = boon_adapter.boon_runtime_host;

    const Host = bridge.BoonRuntimeHost;
    const project_file = bridge.ProjectFile{
        .path = "RUN.bn",
        .contents = "document: Document/new(root: TEXT { Hello Raybox })",
    };
    const project = bridge.Project{
        .name = "minimal",
        .entry_file = "RUN.bn",
        .files = @constCast(&[_]bridge.ProjectFile{project_file}),
    };

    const PersistCtx = struct {
        fn read(ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8 {
            _ = ptr;
            _ = allocator;
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
    var persist = bridge.PersistStore{
        .ptr = &persist_ctx,
        .read = PersistCtx.read,
        .write = PersistCtx.write,
        .deletePrefix = PersistCtx.deletePrefix,
    };
    var route = bridge.RouteStore{
        .ptr = &route_ctx,
        .current = RouteCtx.current,
        .goTo = RouteCtx.goTo,
    };
    var clock = bridge.VirtualClock{};
    var time = bridge.TimeSource{ .virtual = &clock };

    var host = try Host.init(std.testing.allocator, &persist, &route, &time);
    defer host.deinit();

    try host.loadProject(project);
    const build = try host.runBuildFile();
    try std.testing.expectEqual(@as(std.meta.Tag(bridge.BuildResult), .not_present), build);

    const compile = try host.compileEntry();
    switch (compile) {
        .ok => |compiled| {
            try std.testing.expect(compiled.revision > 0);
        },
        .diagnostics => return error.ExpectedCompileOk,
    }

    const output = try host.start();
    switch (output) {
        .document => |document| {
            try std.testing.expect(document.values.len > 0);
            try std.testing.expectEqual(@as(bridge.ValueId, 0), document.root);
            try std.testing.expectEqualStrings("/", document.route);
        },
        .scene => return error.ExpectedDocumentSnapshot,
        .diagnostics => return error.ExpectedRuntimeSnapshot,
    }
}

test "Raybox bridge loads arbitrary multi-module Boon projects" {
    const bridge = boon_adapter.boon_runtime_host;

    const run_source = @embedFile("../../fixtures/generic_apps/multi_module/RUN.bn");
    const widgets_source = @embedFile("../../fixtures/generic_apps/multi_module/Widgets.bn");
    const project = bridge.Project{
        .name = "raybox_generic_multi_module_fixture",
        .entry_file = "RUN.bn",
        .files = @constCast(&[_]bridge.ProjectFile{
            .{ .path = "RUN.bn", .contents = run_source },
            .{ .path = "Widgets.bn", .contents = widgets_source },
        }),
    };

    var persist_ctx = boon_adapter.host.MemoryPersistStore.init(std.testing.allocator);
    defer persist_ctx.deinit();
    var route_ctx = boon_adapter.host.MemoryRouteStore{};
    var persist = persist_ctx.store();
    var route = route_ctx.store();
    var clock = bridge.VirtualClock{};
    var time = bridge.TimeSource{ .virtual = &clock };
    var host = try bridge.BoonRuntimeHost.init(std.testing.allocator, &persist, &route, &time);
    defer host.deinit();

    try host.loadProject(project);
    switch (try host.runBuildFile()) {
        .not_present => {},
        else => return error.ExpectedNoBuildFile,
    }
    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => return error.ExpectedCompileOk,
    }

    const output = try host.start();
    switch (output) {
        .document => |document| {
            try std.testing.expect(document.values.len > 0);
            try std.testing.expect(document.events.len == 0);
        },
        .scene => return error.ExpectedDocumentSnapshot,
        .diagnostics => return error.ExpectedRuntimeSnapshot,
    }
}
