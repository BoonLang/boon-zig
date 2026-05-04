const std = @import("std");
const builtin = @import("builtin");
const raybox = @import("raybox");
const registry = @import("example_registry");
const sdl = @import("sdl");

const frame_stats = @import("frame_stats.zig");
const frame_capture = @import("frame_capture.zig");
const input_mod = @import("input.zig");
const local_examples = @import("local_examples.zig");
const playground_layout = @import("playground_layout");
const playground_project = @import("playground_project.zig");
const sdl_trace_renderer = @import("sdl_trace_renderer.zig");
const time_mod = @import("time.zig");

const c = sdl.c;

const bridge = raybox.boon_adapter.host.bridge;
const clay_bridge = raybox.clay.bridge;
const host_mod = raybox.boon_adapter.host;
const physical = raybox.render.physical_projection;
const font_manager = raybox.text.font_manager;

const default_example_index = if (builtin.os.tag == .emscripten)
    firstMultiFileExampleIndex() orelse 0
else
    0;

const CaptureSize = struct {
    width: i32,
    height: i32,
};

const example_names = blk: {
    var names: [registry.examples.len + local_examples.examples.len][]const u8 = undefined;
    for (registry.examples, 0..) |example, index| {
        names[index] = example.name;
    }
    for (local_examples.examples, 0..) |example, index| {
        names[registry.examples.len + index] = example.name;
    }
    break :blk names;
};

pub const PlaygroundApp = struct {
    initialized: bool = false,
    input: input_mod.InputState = .{},
    clock: time_mod.AppClock = .{},
    stats: frame_stats.FrameStats = .{},
    allocator: std.mem.Allocator = std.heap.c_allocator,
    renderer: ?sdl_trace_renderer.TraceRenderer = null,
    shell_renderer: ?sdl_trace_renderer.TraceRenderer = null,
    sdl_window: ?*c.SDL_Window = null,
    sdl_renderer: ?*c.SDL_Renderer = null,
    framebuffer_width: f32 = @floatFromInt(playground_layout.window_width),
    framebuffer_height: f32 = @floatFromInt(playground_layout.window_height),
    fonts: ?font_manager.FontManager = null,
    clay: ?clay_bridge.ClayBridge = null,
    persist_ctx: host_mod.MemoryPersistStore = undefined,
    persist_ctx_initialized: bool = false,
    route_ctx: host_mod.MemoryRouteStore = .{},
    persist: bridge.PersistStore = undefined,
    route: bridge.RouteStore = undefined,
    virtual_clock: bridge.VirtualClock = .{},
    ui_time_ms: u64 = 0,
    runtime_has_timers: bool = false,
    runtime_tick_remainder_ms: f64 = 0,
    time_source: bridge.TimeSource = undefined,
    host: ?bridge.BoonRuntimeHost = null,
    semantic: ?physical.SemanticTree = null,
    trace: ?physical.RenderTrace = null,
    web_input_text: std.ArrayListUnmanaged(u8) = .empty,
    web_focused_input: u64 = 0,
    web_focused_handle: ?bridge.TextInputHandle = null,
    current_example_index: usize = default_example_index,
    current_example_name: []const u8 = registry.examples[default_example_index].name,
    native_input_text: std.ArrayListUnmanaged(u8) = .empty,
    native_focused_input: u64 = 0,
    native_focused_valid: bool = false,
    native_focused_handle: ?bridge.TextInputHandle = null,
    native_input_dirty: bool = false,
    native_text_change_pending: bool = false,
    caret_blink_epoch_ms: u64 = 0,
    caret_visible_current: bool = true,
    last_svg_click_dispatched_for_test: bool = false,
    last_error: ?[]const u8 = null,
    capture_path: ?[]const u8 = null,
    capture_size: ?CaptureSize = null,
    capture_texture: ?*c.SDL_Texture = null,
    capture_texture_width: i32 = 0,
    capture_texture_height: i32 = 0,
    capture_after_frame: u64 = 3,
    capture_written: bool = false,
    source_title: ?[]u8 = null,
    source_preview: ?[]u8 = null,
    source_scroll_line: usize = 0,

    pub fn setInitialExample(self: *PlaygroundApp, name: []const u8) bool {
        const index = exampleIndex(name) orelse return false;
        self.current_example_index = index;
        self.current_example_name = exampleNameAt(index);
        return true;
    }

    pub fn setCapturePath(self: *PlaygroundApp, path: []const u8) void {
        self.capture_path = path;
        self.capture_written = false;
    }

    pub fn setCaptureSize(self: *PlaygroundApp, width: i32, height: i32) void {
        self.capture_size = .{
            .width = @max(1, width),
            .height = @max(1, height),
        };
    }

    pub fn initForNativeEventTest(self: *PlaygroundApp, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        try self.initRuntime();
        self.initialized = true;
    }

    pub fn deinitForNativeEventTest(self: *PlaygroundApp) void {
        if (self.host) |*host| {
            host.clearState(self.current_example_name) catch {};
        }
        self.deinitRuntimeResources();
    }

    pub fn clickInputForTest(self: *PlaygroundApp, index: usize) !void {
        self.handleProjectionPointerClick(try self.controlCenterForTest("text_input", index));
    }

    pub fn clickCheckboxForTest(self: *PlaygroundApp, index: usize) !void {
        const point = self.controlCenterForTest("checkbox", index) catch |err| switch (err) {
            error.ControlNotFound => {
                try self.dispatchCheckboxBySemanticIndex(index);
                return;
            },
            else => return err,
        };
        self.handleProjectionPointerClick(point);
    }

    pub fn clickButtonForTest(self: *PlaygroundApp, index: usize) !void {
        const point = self.controlCenterForTest("button", index) catch |err| switch (err) {
            error.ControlNotFound => {
                try self.dispatchButtonBySemanticIndex(index);
                return;
            },
            else => return err,
        };
        self.handleProjectionPointerClick(point);
    }

    pub fn clickButtonByLabelForTest(self: *PlaygroundApp, label: []const u8) !void {
        const semantic = self.semantic orelse return error.ProjectionNotReady;
        for (semantic.buttons, 0..) |button, index| {
            if (physical.containsVisible(button.label, label)) return self.clickButtonForTest(index);
        }
        return error.ControlNotFound;
    }

    pub fn clickCanvasForTest(self: *PlaygroundApp) !void {
        self.handleProjectionPointerClick(try self.controlCenterForTest("svg_canvas", 0));
    }

    fn dispatchCheckboxBySemanticIndex(self: *PlaygroundApp, index: usize) !void {
        const semantic = self.semantic orelse return error.ProjectionNotReady;
        if (index >= semantic.checkboxes.len) return error.ControlNotFound;
        const checkbox = semantic.checkboxes[index];
        self.dispatchEvent(.{ .checkbox_change = .{ .link = @intCast(index), .checked = !checkbox.checked } });
    }

    fn dispatchButtonBySemanticIndex(self: *PlaygroundApp, index: usize) !void {
        const semantic = self.semantic orelse return error.ProjectionNotReady;
        if (index >= semantic.buttons.len) return error.ControlNotFound;
        const button = semantic.buttons[index];
        if (button.handle) |handle| {
            self.dispatchEvent(.{ .click_ref = handle });
        } else if (button.label.len != 0) {
            self.dispatchEvent(.{ .click_text = button.label });
        } else if (button.link) |link| {
            self.dispatchEvent(.{ .click = link });
        } else {
            return error.ControlNotFound;
        }
    }

    pub fn typeAsciiForTest(self: *PlaygroundApp, text: []const u8) !void {
        for (text) |byte| {
            if (byte < 32 or byte >= 127) return error.UnsupportedTestInput;
            try self.native_input_text.append(self.allocator, byte);
            self.dispatchFocusedText();
        }
        self.flushPendingNativeTextChange();
    }

    pub fn pressEnterForTest(self: *PlaygroundApp) void {
        self.dispatchFocusedKey(.enter);
    }

    pub fn typeAsciiViaSdlEventsForTest(self: *PlaygroundApp, text: []const u8) !void {
        try self.dispatchTextInputForTest(text);
    }

    pub fn pressEnterViaSdlEventForTest(self: *PlaygroundApp) void {
        self.dispatchKeyDownForTest(c.SDLK_RETURN, false);
    }

    pub fn clickInputViaSdlEventForTest(self: *PlaygroundApp, index: usize) !void {
        try self.dispatchMouseButtonUpForControl("text_input", index);
    }

    pub fn pressBackspaceForTest(self: *PlaygroundApp) void {
        if (self.native_input_text.items.len != 0) _ = self.native_input_text.pop();
        self.dispatchFocusedKey(.backspace);
    }

    pub fn advanceUiTimeForTest(self: *PlaygroundApp, milliseconds: u64) !void {
        self.ui_time_ms +|= milliseconds;
        try self.refreshCaretBlink();
    }

    pub fn textInputCaretVisibleForTest(self: PlaygroundApp) bool {
        const trace = self.trace orelse return false;
        for (trace.commands) |command| {
            if (command.base.kind == .bevel and std.mem.eql(u8, command.role, "text_input") and command.caret_visible) return true;
        }
        return false;
    }

    pub fn advanceTimeForTest(self: *PlaygroundApp, milliseconds: u64) !void {
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;
        self.virtual_clock.advance(milliseconds);
        self.ui_time_ms +|= milliseconds;
        try self.updateProjection(try host.tick(self.virtual_clock.now_ms));
    }

    pub fn advanceFrameTimeForTest(self: *PlaygroundApp, milliseconds: u64) !void {
        self.clock.delta_seconds = @as(f64, @floatFromInt(milliseconds)) / 1000.0;
        self.advanceUiClock();
        self.flushPendingNativeTextChange();
        self.advanceRuntimeTimers();
        try self.refreshCaretBlink();
    }

    pub fn renderedTextForTest(self: PlaygroundApp) []const u8 {
        return if (self.semantic) |semantic| semantic.rendered_text else "";
    }

    pub fn inputTextForTest(self: PlaygroundApp, index: usize) ?[]const u8 {
        const semantic = self.semantic orelse return null;
        if (index >= semantic.inputs.len) return null;
        return semantic.inputs[index].text;
    }

    pub fn nativeInputDraftForTest(self: PlaygroundApp) []const u8 {
        return self.native_input_text.items;
    }

    pub fn currentExampleNameForTest(self: PlaygroundApp) []const u8 {
        return self.current_example_name;
    }

    pub fn clickExampleTabForTest(self: *PlaygroundApp, name: []const u8) !void {
        const index = exampleIndex(name) orelse return error.UnknownExample;
        const rect = exampleTabRect(index);
        if (exampleTabIndexAt(.{ .x = rect.x + rect.w * 0.5, .y = rect.y + rect.h * 0.5 }) != index) return error.ExampleTabHitTestFailed;
        self.current_example_index = index;
        try self.loadCurrentExample();
    }

    pub fn checkboxCheckedForTest(self: PlaygroundApp, index: usize) ?bool {
        const semantic = self.semantic orelse return null;
        if (index >= semantic.checkboxes.len) return null;
        return semantic.checkboxes[index].checked;
    }

    pub fn checkboxCountForTest(self: PlaygroundApp) usize {
        const semantic = self.semantic orelse return 0;
        return semantic.checkboxes.len;
    }

    pub fn svgClickHasHandleForTest(self: PlaygroundApp, index: usize) bool {
        const semantic = self.semantic orelse return false;
        if (index >= semantic.svg_clicks.len) return false;
        return semantic.svg_clicks[index].handle != null;
    }

    pub fn svgCircleCountForTest(self: PlaygroundApp) usize {
        const semantic = self.semantic orelse return 0;
        return semantic.svg_circles.len;
    }

    pub fn lastSvgClickDispatchedForTest(self: PlaygroundApp) bool {
        return self.last_svg_click_dispatched_for_test;
    }

    pub fn lastErrorForTest(self: PlaygroundApp) ?[]const u8 {
        return self.last_error;
    }

    pub fn buttonOutlinedForTest(self: PlaygroundApp, label: []const u8) ?bool {
        const semantic = self.semantic orelse return null;
        for (semantic.buttons) |button| {
            if (physical.containsVisible(button.label, label)) return button.outlined;
        }
        return null;
    }

    pub fn runNativeSmokeScript(self: *PlaygroundApp, script: []const u8) !void {
        var parts = std.mem.tokenizeAny(u8, script, ",;");
        while (parts.next()) |raw_part| {
            const part = std.mem.trim(u8, raw_part, " \t\r\n");
            if (part.len == 0) continue;
            if (std.mem.eql(u8, part, "enter")) {
                self.pressEnterForTest();
            } else if (std.mem.eql(u8, part, "sdl-enter")) {
                self.pressEnterViaSdlEventForTest();
            } else if (std.mem.startsWith(u8, part, "click-input=")) {
                try self.clickInputForTest(try parseSmokeIndex(part["click-input=".len..]));
            } else if (std.mem.startsWith(u8, part, "sdl-click-input=")) {
                try self.clickInputViaSdlEventForTest(try parseSmokeIndex(part["sdl-click-input=".len..]));
            } else if (std.mem.startsWith(u8, part, "click-button=")) {
                try self.clickButtonForTest(try parseSmokeIndex(part["click-button=".len..]));
            } else if (std.mem.startsWith(u8, part, "sdl-click-button=")) {
                try self.dispatchMouseButtonUpForControl("button", try parseSmokeIndex(part["sdl-click-button=".len..]));
            } else if (std.mem.startsWith(u8, part, "type=")) {
                try self.typeAsciiForTest(part["type=".len..]);
            } else if (std.mem.startsWith(u8, part, "sdl-type=")) {
                try self.typeAsciiViaSdlEventsForTest(part["sdl-type=".len..]);
            } else {
                return error.UnknownNativeSmokeScriptCommand;
            }
        }
    }

    pub fn init(self: *PlaygroundApp, window: *c.SDL_Window, renderer: *c.SDL_Renderer) void {
        self.sdl_window = window;
        self.sdl_renderer = renderer;
        self.updateFramebufferSize();
        self.fonts = font_manager.FontManager.init(self.allocator) catch |err| failed: {
            self.last_error = @errorName(err);
            std.log.err("failed to initialize font manager: {s}", .{@errorName(err)});
            break :failed null;
        };
        self.renderer = sdl_trace_renderer.TraceRenderer.init(self.allocator, renderer, if (self.fonts) |*fonts| fonts else null);
        self.shell_renderer = sdl_trace_renderer.TraceRenderer.init(self.allocator, renderer, if (self.fonts) |*fonts| fonts else null);
        if (self.fonts) |*fonts| {
            self.clay = clay_bridge.ClayBridge.init(self.allocator, fonts, self.framebuffer_width, self.framebuffer_height) catch |err| failed: {
                self.last_error = @errorName(err);
                std.log.err("failed to initialize Clay bridge: {s}", .{@errorName(err)});
                break :failed null;
            };
        }
        self.initRuntime() catch |err| {
            self.last_error = @errorName(err);
            std.log.err("failed to initialize Boon playground runtime: {s}", .{@errorName(err)});
        };
        self.initialized = true;
        self.clock.reset();
    }

    pub fn frame(self: *PlaygroundApp) void {
        if (!self.initialized) return;
        const sdl_renderer_ptr = self.sdl_renderer orelse return;

        self.clock.tick();
        self.updateFramebufferSize();
        self.advanceUiClock();
        self.stats.beginFrame(self.clock.delta_seconds);
        self.processWebBridgeQueue();
        self.flushPendingNativeTextChange();
        self.advanceRuntimeTimers();
        self.refreshCaretBlink() catch |err| self.recordRuntimeError(err);
        self.updateSdlTextInputArea();

        const capture_texture = self.beginCaptureRenderTarget(sdl_renderer_ptr);
        _ = c.SDL_SetRenderDrawBlendMode(sdl_renderer_ptr, c.SDL_BLENDMODE_BLEND_PREMULTIPLIED);
        _ = c.SDL_SetRenderDrawColorFloat(sdl_renderer_ptr, 0.945, 0.933, 0.910, 1.0);
        _ = c.SDL_RenderClear(sdl_renderer_ptr);
        const framebuffer_width = self.framebuffer_width;
        const framebuffer_height = self.framebuffer_height;
        const preview_rect = previewViewport(framebuffer_width, framebuffer_height);
        if (self.renderer) |*renderer| {
            if (self.clay) |*clay| {
                const dt: f32 = @floatCast(@max(1.0 / 240.0, self.clock.delta_seconds));
                clay.beginFrame(.{
                    .pointer_x = self.input.pointer_x,
                    .pointer_y = self.input.pointer_y,
                    .pointer_down = self.input.pointer_down,
                }, framebuffer_width, framebuffer_height, dt);
                clay_bridge.declarePlaygroundShell(.{
                    .example_name = self.current_example_name,
                    .example_names = example_names[0..],
                    .selected_example_index = self.current_example_index,
                    .source_title = self.source_title orelse "",
                    .source_preview = self.source_preview orelse "",
                    .source_scroll_line = self.source_scroll_line,
                    .frame_index = self.stats.frame_index,
                    .command_count = 0,
                    .trace_count = if (self.trace) |trace| trace.commands.len else 0,
                });
                const commands = clay.endFrame(dt);
                self.stats.draw_batches +|= 1;
                self.stats.vertices = @intCast(renderer.batch.vertices.items.len);
                self.stats.indices = @intCast(renderer.batch.indices.items.len);
                if (self.shell_renderer) |*shell_renderer| {
                    if (self.fonts) |*fonts| {
                        shell_renderer.renderClay(commands, fonts, framebuffer_width, framebuffer_height) catch |err| {
                            self.last_error = @errorName(err);
                            std.log.err("failed to render Clay shell: {s}", .{@errorName(err)});
                        };
                    }
                }
            }
            if (self.trace) |trace| {
                renderer.renderInRect(trace, if (self.fonts) |*fonts| fonts else null, preview_rect, framebuffer_width, framebuffer_height) catch |err| {
                    self.last_error = @errorName(err);
                    std.log.err("failed to render trace: {s}", .{@errorName(err)});
                };
            }
        }
        self.captureFrameIfRequested(framebuffer_width, framebuffer_height);
        if (capture_texture) |texture| {
            _ = c.SDL_SetRenderTarget(sdl_renderer_ptr, null);
            _ = c.SDL_SetRenderDrawBlendMode(sdl_renderer_ptr, c.SDL_BLENDMODE_BLEND_PREMULTIPLIED);
            _ = c.SDL_SetRenderDrawColorFloat(sdl_renderer_ptr, 0.945, 0.933, 0.910, 1.0);
            _ = c.SDL_RenderClear(sdl_renderer_ptr);
            _ = c.SDL_RenderTexture(sdl_renderer_ptr, texture, null, null);
        }
        _ = c.SDL_RenderPresent(sdl_renderer_ptr);

        self.stats.endFrame();
        self.input.endFrame();
        self.updateWebTestBridge();
    }

    pub fn event(self: *PlaygroundApp, ev: *const c.SDL_Event) void {
        var render_event = ev.*;
        self.convertPointerEventToRenderCoordinates(&render_event);
        self.input.record(&render_event);
        if (!self.initialized) return;
        switch (render_event.type) {
            c.SDL_EVENT_KEY_DOWN => self.handleKeyDown(&render_event),
            c.SDL_EVENT_TEXT_INPUT => self.handleTextInput(&render_event),
            c.SDL_EVENT_MOUSE_BUTTON_UP => self.handlePointerClick(render_event.button.x, render_event.button.y),
            else => {},
        }
    }

    pub fn deinit(self: *PlaygroundApp) void {
        if (!self.initialized) return;
        self.deinitRuntimeResources();
        self.initialized = false;
    }

    fn deinitRuntimeResources(self: *PlaygroundApp) void {
        self.clearProjection();
        if (self.host) |*host| {
            host.deinit();
            self.host = null;
        }
        self.web_input_text.deinit(self.allocator);
        self.web_focused_input = 0;
        self.web_focused_handle = null;
        self.native_input_text.deinit(self.allocator);
        self.native_focused_valid = false;
        self.native_focused_handle = null;
        self.native_text_change_pending = false;
        self.clearSourcePreview();
        if (self.persist_ctx_initialized) {
            self.persist_ctx.deinit();
            self.persist_ctx_initialized = false;
        }
        if (self.clay) |*clay| {
            clay.deinit();
            self.clay = null;
        }
        if (self.fonts) |*fonts| {
            fonts.deinit();
            self.fonts = null;
        }
        if (self.renderer) |*renderer| {
            renderer.deinit();
            self.renderer = null;
        }
        if (self.shell_renderer) |*shell_renderer| {
            shell_renderer.deinit();
            self.shell_renderer = null;
        }
        if (self.capture_texture) |texture| {
            c.SDL_DestroyTexture(texture);
            self.capture_texture = null;
        }
    }

    fn initRuntime(self: *PlaygroundApp) !void {
        self.persist_ctx = host_mod.MemoryPersistStore.init(self.allocator);
        self.persist_ctx_initialized = true;
        self.route_ctx = .{};
        self.persist = self.persist_ctx.store();
        self.route = self.route_ctx.store();
        self.virtual_clock = .{};
        self.time_source = .{ .virtual = &self.virtual_clock };

        self.host = try bridge.BoonRuntimeHost.init(self.allocator, &self.persist, &self.route, &self.time_source);
        try self.loadCurrentExample();
    }

    fn captureFrameIfRequested(self: *PlaygroundApp, framebuffer_width: f32, framebuffer_height: f32) void {
        const path = self.capture_path orelse return;
        if (self.capture_written) return;
        if (self.stats.frame_index < self.capture_after_frame) return;
        const renderer = self.sdl_renderer orelse return;
        frame_capture.writeFramebufferPng(
            self.allocator,
            renderer,
            path,
            @intFromFloat(@max(1.0, framebuffer_width)),
            @intFromFloat(@max(1.0, framebuffer_height)),
        ) catch |err| {
            if (err == error.BlankFramebuffer) return;
            self.last_error = @errorName(err);
            std.log.err("failed to capture framebuffer to {s}: {s}", .{ path, @errorName(err) });
            self.capture_written = true;
            return;
        };
        std.log.info("captured framebuffer to {s}", .{path});
        self.capture_written = true;
    }

    fn loadCurrentExample(self: *PlaygroundApp) !void {
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;
        self.current_example_name = exampleNameAt(self.current_example_index);
        self.last_error = null;
        self.virtual_clock.now_ms = 0;
        self.ui_time_ms = 0;
        self.runtime_has_timers = false;
        self.runtime_tick_remainder_ms = 0;
        self.web_input_text.clearRetainingCapacity();
        self.web_focused_input = 0;
        self.web_focused_handle = null;
        self.native_input_text.clearRetainingCapacity();
        self.native_focused_input = 0;
        self.native_focused_valid = false;
        self.native_focused_handle = null;
        self.native_input_dirty = false;
        self.native_text_change_pending = false;
        self.resetCaretBlinkPhaseOnly();
        const project = try self.loadSelectedProject();
        defer if (!self.selectedProjectIsStatic()) freeNativeProject(self.allocator, project);
        try self.updateSourcePreview(project);

        try host.loadProject(project);
        try host.clearState(self.current_example_name);
        switch (try host.runBuildFile()) {
            .not_present, .ok => {},
            .diagnostics => |diagnostics| return reportDiagnostics(diagnostics, error.BuildDiagnostic),
        }
        switch (try host.compileEntry()) {
            .ok => {},
            .diagnostics => |diagnostics| return reportDiagnostics(diagnostics, error.CompileDiagnostic),
        }
        const output = host.start() catch |err| switch (err) {
            error.OutOfMemory => {
                switch (try host.compileEntry()) {
                    .ok => {},
                    .diagnostics => |diagnostics| return reportDiagnostics(diagnostics, error.CompileDiagnostic),
                }
                try host.startNoSnapshot();
                const text = try host.renderCompactGridTextAlloc(self.allocator, 12, 6);
                defer self.allocator.free(text);
                try self.updateProjectionFromRenderedText(text);
                return;
            },
            else => return err,
        };
        try self.updateProjection(output);
    }

    fn loadSelectedProject(self: *PlaygroundApp) !bridge.Project {
        if (self.current_example_index < registry.examples.len) {
            const example = registry.examples[self.current_example_index];
            if (builtin.os.tag == .emscripten and self.selectedProjectIsStatic()) return playground_project.project();
            return try loadNativeProject(self.allocator, example);
        }
        const local_index = self.current_example_index - registry.examples.len;
        if (local_index >= local_examples.examples.len) return error.InvalidExampleIndex;
        return try loadNativeLocalProject(self.allocator, local_examples.examples[local_index]);
    }

    fn selectedProjectIsStatic(self: PlaygroundApp) bool {
        if (builtin.os.tag != .emscripten) return false;
        if (self.current_example_index >= registry.examples.len) return false;
        return registry.examples[self.current_example_index].kind == .multi_file;
    }

    fn updateSourcePreview(self: *PlaygroundApp, project: bridge.Project) !void {
        self.clearSourcePreview();
        self.source_title = try self.allocator.dupe(u8, project.entry_file);
        self.source_scroll_line = 0;
        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();
        if (project.files.len > 1) {
            try out.writer.writeAll("project files: ");
            for (project.files, 0..) |file, index| {
                if (index != 0) try out.writer.writeAll(", ");
                try out.writer.writeAll(file.path);
            }
            try out.writer.writeAll("\n\n");
        }
        const source = projectFileForPreview(project);
        try out.writer.writeAll("-- ");
        try out.writer.writeAll(source.path);
        try out.writer.writeByte('\n');
        try appendSourceLines(&out.writer, source.contents, 500, playground_layout.source_preview_columns);
        self.source_preview = try out.toOwnedSlice();
    }

    fn clearSourcePreview(self: *PlaygroundApp) void {
        if (self.source_title) |title| {
            self.allocator.free(title);
            self.source_title = null;
        }
        if (self.source_preview) |preview| {
            self.allocator.free(preview);
            self.source_preview = null;
        }
    }

    fn restartRuntime(self: *PlaygroundApp) !void {
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;
        self.virtual_clock.now_ms = 0;
        self.ui_time_ms = 0;
        self.web_input_text.clearRetainingCapacity();
        self.web_focused_input = 0;
        self.web_focused_handle = null;
        self.native_focused_valid = false;
        self.native_focused_handle = null;
        self.native_input_dirty = false;
        self.native_text_change_pending = false;
        self.resetCaretBlinkPhaseOnly();
        try host.clearState(self.current_example_name);
        switch (try host.compileEntry()) {
            .ok => {},
            .diagnostics => |diagnostics| return reportDiagnostics(diagnostics, error.CompileDiagnostic),
        }
        try self.updateProjection(try host.start());
    }

    fn updateProjection(self: *PlaygroundApp, output: bridge.RuntimeOutput) !void {
        var semantic = switch (output) {
            .document => |document| try physical.SemanticTree.fromDocument(self.allocator, document),
            .scene => |scene| try physical.SemanticTree.fromScene(self.allocator, scene),
            .diagnostics => |diagnostics| return reportDiagnostics(diagnostics, error.RuntimeDiagnostic),
        };
        self.runtime_has_timers = outputTimerCount(output) != 0;
        errdefer semantic.deinit(self.allocator);
        try self.syncNativeFocusFromIncomingSemantic(&semantic);
        try self.applyNativeDraftToSemantic(&semantic);
        self.applyCaretBlinkToSemantic(&semantic);

        var trace = try physical.RenderTrace.project(self.allocator, semantic, .{});
        errdefer trace.deinit(self.allocator);

        self.clearProjection();
        self.semantic = semantic;
        self.trace = trace;
    }

    fn updateProjectionFromRenderedText(self: *PlaygroundApp, text: []const u8) !void {
        var semantic = try physical.SemanticTree.fromRenderedText(self.allocator, text);
        errdefer semantic.deinit(self.allocator);
        var trace = try physical.RenderTrace.project(self.allocator, semantic, .{});
        errdefer trace.deinit(self.allocator);

        self.clearProjection();
        self.semantic = semantic;
        self.trace = trace;
    }

    fn clearProjection(self: *PlaygroundApp) void {
        if (self.trace) |*trace| {
            trace.deinit(self.allocator);
            self.trace = null;
        }
        if (self.semantic) |*semantic| {
            semantic.deinit(self.allocator);
            self.semantic = null;
        }
    }

    fn handleKeyDown(self: *PlaygroundApp, ev: *const c.SDL_Event) void {
        const key_code = ev.key.key;
        if (self.handleTerminalKey(key_code)) return;
        if (ev.key.repeat and (key_code == c.SDLK_LEFT or key_code == c.SDLK_RIGHT or key_code == c.SDLK_UP or key_code == c.SDLK_DOWN)) return;
        switch (key_code) {
            c.SDLK_LEFT, c.SDLK_UP => self.switchExample(-1),
            c.SDLK_RIGHT, c.SDLK_DOWN => self.switchExample(1),
            c.SDLK_PAGEUP => self.scrollSource(-10),
            c.SDLK_PAGEDOWN => self.scrollSource(10),
            c.SDLK_HOME => self.source_scroll_line = 0,
            c.SDLK_F5 => self.loadCurrentExample() catch |err| self.recordRuntimeError(err),
            c.SDLK_RETURN, c.SDLK_KP_ENTER => self.dispatchFocusedKey(.enter),
            c.SDLK_BACKSPACE => {
                if (self.native_input_text.items.len != 0) _ = self.native_input_text.pop();
                self.dispatchFocusedKey(.backspace);
            },
            c.SDLK_ESCAPE => self.dispatchFocusedKey(.escape),
            else => {},
        }
    }

    fn handleTextInput(self: *PlaygroundApp, ev: *const c.SDL_Event) void {
        if (!self.native_focused_valid) return;
        const bytes = std.mem.span(ev.text.text);
        if (bytes.len == 0) return;
        self.native_input_text.appendSlice(self.allocator, bytes) catch |err| {
            self.recordRuntimeError(err);
            return;
        };
        self.dispatchFocusedText();
    }

    fn handlePointerClick(self: *PlaygroundApp, x: f32, y: f32) void {
        if (self.handleShellClick(x, y)) return;
        const point = self.screenToProjection(x, y) orelse return;
        self.handleProjectionPointerClick(point);
    }

    fn scrollSource(self: *PlaygroundApp, delta: i32) void {
        if (delta < 0) {
            const amount: usize = @intCast(-delta);
            self.source_scroll_line = if (amount > self.source_scroll_line) 0 else self.source_scroll_line - amount;
        } else {
            self.source_scroll_line +|= @intCast(delta);
        }
    }

    fn handleProjectionPointerClick(self: *PlaygroundApp, point: Point) void {
        if (self.semantic) |semantic| {
            if (self.traceControlIndexAt(point, "text_input")) |index| {
                if (index >= semantic.inputs.len) return;
                const already_focused = self.native_focused_valid and self.native_focused_input == index;
                self.native_focused_input = @intCast(index);
                self.native_focused_valid = true;
                self.native_focused_handle = semantic.inputs[index].handle;
                if (self.native_focused_handle == null) self.cacheNativeFocusedInputHandle() catch |err| self.recordRuntimeError(err);
                self.resetCaretBlink();
                if (!already_focused or !self.native_input_dirty) {
                    self.syncNativeInputBuffer(@intCast(index)) catch |err| self.recordRuntimeError(err);
                    self.native_input_dirty = false;
                }
                self.startSdlTextInput();
                if (already_focused) return;
                self.dispatchEvent(.{ .focus = @intCast(index) });
                return;
            }
            if (self.traceControlIndexAt(point, "svg_canvas")) |index| {
                if (index >= semantic.svg_clicks.len) return;
                const svg_click = semantic.svg_clicks[index];
                const rect = self.traceControlRect("svg_canvas", index) orelse return;
                const local_point = Point{ .x = point.x - rect.x, .y = point.y - rect.y };
                self.last_svg_click_dispatched_for_test = true;
                if (svg_click.handle) |handle| {
                    self.dispatchEvent(.{ .svg_click_ref = .{ .handle = handle, .x = local_point.x, .y = local_point.y } });
                } else {
                    self.dispatchEvent(.{ .svg_click = .{ .link = svg_click.link, .x = local_point.x, .y = local_point.y } });
                }
                return;
            }
            if (self.traceControlIndexAt(point, "checkbox")) |index| {
                if (index >= semantic.checkboxes.len) return;
                const checkbox = semantic.checkboxes[index];
                self.dispatchEvent(.{ .checkbox_change = .{ .link = @intCast(index), .checked = !checkbox.checked } });
                return;
            }
            if (self.handleTerminalControlPointer(point)) return;
            if (self.traceControlIndexAt(point, "button")) |index| {
                if (index >= semantic.buttons.len) return;
                const button = semantic.buttons[index];
                if (button.handle) |handle| {
                    self.dispatchEvent(.{ .click_ref = handle });
                } else if (button.label.len != 0) {
                    const label = button.label;
                    self.dispatchEvent(.{ .click_text = label });
                } else {
                    self.dispatchEvent(.{ .click = @intCast(index) });
                }
                return;
            }
        }
    }

    fn switchExample(self: *PlaygroundApp, delta: i32) void {
        const count = exampleCount();
        if (count == 0) return;
        const len: i32 = @intCast(count);
        var next: i32 = @intCast(self.current_example_index);
        next = @mod(next + delta, len);
        self.current_example_index = @intCast(next);
        self.loadCurrentExample() catch |err| self.recordRuntimeError(err);
    }

    fn handleShellClick(self: *PlaygroundApp, x: f32, y: f32) bool {
        const framebuffer_width = self.framebuffer_width;
        if (shellButtonRect(framebuffer_width, 0).contains(.{ .x = x, .y = y })) {
            self.switchExample(-1);
            return true;
        }
        if (shellButtonRect(framebuffer_width, 1).contains(.{ .x = x, .y = y })) {
            self.switchExample(1);
            return true;
        }
        if (shellButtonRect(framebuffer_width, 2).contains(.{ .x = x, .y = y })) {
            self.loadCurrentExample() catch |err| self.recordRuntimeError(err);
            return true;
        }
        if (exampleTabIndexAt(.{ .x = x, .y = y })) |index| {
            if (index < exampleCount() and index != self.current_example_index) {
                self.current_example_index = index;
                self.loadCurrentExample() catch |err| self.recordRuntimeError(err);
            }
            return true;
        }
        return false;
    }

    fn handleTerminalKey(self: *PlaygroundApp, key_code: c.SDL_Keycode) bool {
        const key: []const u8 = switch (key_code) {
            c.SDLK_UP => "Up",
            c.SDLK_DOWN => "Down",
            c.SDLK_RETURN, c.SDLK_KP_ENTER => "Enter",
            c.SDLK_SPACE => "Space",
            c.SDLK_R => "r",
            else => return false,
        };
        return self.dispatchTerminalKeyIfAccepted(key);
    }

    fn handleTerminalControlPointer(self: *PlaygroundApp, point: Point) bool {
        for (terminal_control_labels, 0..) |_, index| {
            const rect = terminalControlRect(index);
            if (rect.contains(point)) {
                return self.dispatchTerminalKeyIfAccepted(terminal_control_keys[index]);
            }
        }
        return false;
    }

    fn traceControlIndexAt(self: PlaygroundApp, point: Point, role: []const u8) ?usize {
        const trace = self.trace orelse return null;
        var index: usize = 0;
        for (trace.commands) |command| {
            if (!std.mem.eql(u8, command.role, role)) continue;
            const wanted_kind: raybox.render.renderer.CustomKind = if (std.mem.eql(u8, role, "checkbox")) .svg_circle else .bevel;
            if (command.base.kind != wanted_kind) continue;
            var rect = physicalRect(.{
                .x = command.base.rect.x,
                .y = command.base.rect.y,
                .w = command.base.rect.w,
                .h = command.base.rect.h,
            });
            if (std.mem.eql(u8, role, "checkbox")) {
                rect = .{ .x = rect.x - 8, .y = rect.y - 8, .w = @max(rect.w + 180, 44), .h = @max(rect.h + 16, 38) };
            }
            if (rect.contains(point)) return index;
            index += 1;
        }
        return null;
    }

    fn controlCenterForTest(self: PlaygroundApp, role: []const u8, wanted_index: usize) !Point {
        const trace = self.trace orelse return error.ProjectionNotReady;
        var index: usize = 0;
        for (trace.commands) |command| {
            if (!std.mem.eql(u8, command.role, role)) continue;
            const wanted_kind: raybox.render.renderer.CustomKind = if (std.mem.eql(u8, role, "checkbox")) .svg_circle else .bevel;
            if (command.base.kind != wanted_kind) continue;
            if (index == wanted_index) {
                return .{
                    .x = command.base.rect.x + command.base.rect.w * 0.5,
                    .y = command.base.rect.y + command.base.rect.h * 0.5,
                };
            }
            index += 1;
        }
        return error.ControlNotFound;
    }

    fn dispatchMouseButtonUpForControl(self: *PlaygroundApp, role: []const u8, wanted_index: usize) !void {
        const projection_point = try self.controlCenterForTest(role, wanted_index);
        var screen_point = self.projectionToScreen(projection_point) orelse return error.ProjectionNotReady;
        if (self.sdl_renderer) |renderer| {
            var window_x: f32 = 0;
            var window_y: f32 = 0;
            if (c.SDL_RenderCoordinatesToWindow(renderer, screen_point.x, screen_point.y, &window_x, &window_y)) {
                screen_point = .{ .x = window_x, .y = window_y };
            }
        }
        var click_event: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
        click_event.type = c.SDL_EVENT_MOUSE_BUTTON_UP;
        click_event.button.button = c.SDL_BUTTON_LEFT;
        click_event.button.x = screen_point.x;
        click_event.button.y = screen_point.y;
        self.event(&click_event);
    }

    fn dispatchTextInputForTest(self: *PlaygroundApp, text: []const u8) !void {
        if (text.len >= 256) return error.TestInputTooLong;
        var text_buffer: [256:0]u8 = [_:0]u8{0} ** 256;
        @memcpy(text_buffer[0..text.len], text);
        var text_event: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
        text_event.text.type = c.SDL_EVENT_TEXT_INPUT;
        text_event.text.text = @ptrCast(&text_buffer[0]);
        self.event(&text_event);
    }

    fn dispatchKeyDownForTest(self: *PlaygroundApp, key: c.SDL_Keycode, repeat: bool) void {
        var key_event: c.SDL_Event = std.mem.zeroes(c.SDL_Event);
        key_event.type = c.SDL_EVENT_KEY_DOWN;
        key_event.key.key = key;
        key_event.key.repeat = repeat;
        self.event(&key_event);
    }

    fn convertPointerEventToRenderCoordinates(self: *PlaygroundApp, ev: *c.SDL_Event) void {
        switch (ev.type) {
            c.SDL_EVENT_MOUSE_MOTION => {
                const point = self.windowToRenderPoint(ev.motion.x, ev.motion.y);
                ev.motion.x = point.x;
                ev.motion.y = point.y;
            },
            c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
                const point = self.windowToRenderPoint(ev.button.x, ev.button.y);
                ev.button.x = point.x;
                ev.button.y = point.y;
            },
            else => {},
        }
    }

    fn windowToRenderPoint(self: *PlaygroundApp, x: f32, y: f32) Point {
        if (self.sdl_renderer) |renderer| {
            var render_x: f32 = 0;
            var render_y: f32 = 0;
            if (c.SDL_RenderCoordinatesFromWindow(renderer, x, y, &render_x, &render_y)) {
                return .{ .x = render_x, .y = render_y };
            }
        }
        if (self.sdl_window) |window| {
            var window_w: c_int = 0;
            var window_h: c_int = 0;
            if (c.SDL_GetWindowSize(window, &window_w, &window_h) and window_w > 0 and window_h > 0) {
                return .{
                    .x = x * self.framebuffer_width / @as(f32, @floatFromInt(window_w)),
                    .y = y * self.framebuffer_height / @as(f32, @floatFromInt(window_h)),
                };
            }
        }
        return .{ .x = x, .y = y };
    }

    fn traceControlRect(self: PlaygroundApp, role: []const u8, wanted_index: usize) ?HitRect {
        const trace = self.trace orelse return null;
        var index: usize = 0;
        for (trace.commands) |command| {
            if (!std.mem.eql(u8, command.role, role)) continue;
            const wanted_kind: raybox.render.renderer.CustomKind = if (std.mem.eql(u8, role, "checkbox")) .svg_circle else .bevel;
            if (command.base.kind != wanted_kind) continue;
            if (index == wanted_index) {
                return physicalRect(.{
                    .x = command.base.rect.x,
                    .y = command.base.rect.y,
                    .w = command.base.rect.w,
                    .h = command.base.rect.h,
                });
            }
            index += 1;
        }
        return null;
    }

    fn dispatchFocusedKey(self: *PlaygroundApp, key: bridge.Key) void {
        if (!self.native_focused_valid) return;
        self.resetCaretBlinkPhaseOnly();
        self.native_text_change_pending = false;
        if (key == .enter) self.native_input_dirty = false;
        if (self.native_focused_handle) |handle| {
            const host = if (self.host) |*host| host else return;
            host.pressTextInputKeyWithHandle(handle, key, self.native_input_text.items) catch |err| {
                self.recordRuntimeError(err);
                return;
            };
            self.updateProjection(host.tick(self.virtual_clock.now_ms) catch |err| {
                self.recordRuntimeError(err);
                return;
            }) catch |err| self.recordRuntimeError(err);
        } else {
            self.dispatchEvent(.{ .key_down = .{ .link = self.native_focused_input, .key = key, .text = self.native_input_text.items } });
        }
        if (key == .enter or key == .escape) {
            self.native_input_text.clearRetainingCapacity();
            self.clearFocusedInputProjection();
        }
        if (key == .escape) {
            self.native_input_dirty = false;
            self.native_focused_valid = false;
            self.native_focused_handle = null;
            self.native_text_change_pending = false;
            self.stopSdlTextInput();
        }
    }

    fn dispatchFocusedText(self: *PlaygroundApp) void {
        self.native_input_dirty = true;
        self.native_text_change_pending = true;
        self.resetCaretBlinkPhaseOnly();
        self.refreshNativeDraftProjection();
        self.updateSdlTextInputArea();
    }

    fn flushPendingNativeTextChange(self: *PlaygroundApp) void {
        if (!self.native_text_change_pending) return;
        self.native_text_change_pending = false;
        if (!self.native_focused_valid) return;
        if (self.native_focused_handle) |handle| {
            const host = if (self.host) |*host| host else return;
            host.setTextInputValueWithHandle(handle, self.native_input_text.items) catch |err| {
                self.recordRuntimeError(err);
                return;
            };
            self.updateProjection(host.tick(self.virtual_clock.now_ms) catch |err| {
                self.recordRuntimeError(err);
                return;
            }) catch |err| self.recordRuntimeError(err);
        } else {
            self.dispatchEvent(.{ .change_text = .{ .link = self.native_focused_input, .text = self.native_input_text.items } });
        }
    }

    fn refreshNativeDraftProjection(self: *PlaygroundApp) void {
        if (self.semantic) |*semantic| {
            self.applyNativeDraftToSemantic(semantic) catch |err| {
                self.recordRuntimeError(err);
                return;
            };
            self.applyCaretBlinkToSemantic(semantic);
            const trace = physical.RenderTrace.project(self.allocator, semantic.*, .{}) catch |err| {
                self.recordRuntimeError(err);
                return;
            };
            if (self.trace) |*old_trace| old_trace.deinit(self.allocator);
            self.trace = trace;
        }
    }

    fn cacheNativeFocusedInputHandle(self: *PlaygroundApp) !void {
        self.native_focused_handle = null;
        if (!self.native_focused_valid) return;
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;
        self.native_focused_handle = try host.textInputHandle(@intCast(self.native_focused_input));
    }

    fn clearFocusedInputProjection(self: *PlaygroundApp) void {
        if (!self.native_focused_valid) return;
        if (self.semantic) |*semantic| {
            if (self.native_focused_input >= semantic.inputs.len) return;
            const index: usize = @intCast(self.native_focused_input);
            self.allocator.free(semantic.inputs[index].text);
            semantic.inputs[index].text = self.allocator.dupe(u8, "") catch return;
        }
    }

    fn advanceRuntimeTimers(self: *PlaygroundApp) void {
        if (!self.runtime_has_timers) return;
        const host = if (self.host) |*host| host else return;
        const capped_delta_seconds = @min(self.clock.delta_seconds, 0.25);
        const total_ms = self.runtime_tick_remainder_ms + capped_delta_seconds * 1000.0;
        if (total_ms < 33.0) {
            self.runtime_tick_remainder_ms = total_ms;
            return;
        }
        const delta_ms: u64 = @intFromFloat(@floor(total_ms));
        self.runtime_tick_remainder_ms = total_ms - @as(f64, @floatFromInt(delta_ms));
        self.virtual_clock.advance(delta_ms);
        const output = host.tick(self.virtual_clock.now_ms) catch |err| {
            self.recordRuntimeError(err);
            return;
        };
        self.updateProjection(output) catch |err| self.recordRuntimeError(err);
    }

    fn advanceUiClock(self: *PlaygroundApp) void {
        const capped_delta_seconds = @min(self.clock.delta_seconds, 1.0);
        const delta_ms: u64 = @intFromFloat(@floor(capped_delta_seconds * 1000.0));
        self.ui_time_ms +|= delta_ms;
    }

    fn resetCaretBlinkPhaseOnly(self: *PlaygroundApp) void {
        self.caret_blink_epoch_ms = self.ui_time_ms;
        self.caret_visible_current = true;
    }

    fn resetCaretBlink(self: *PlaygroundApp) void {
        const was_visible = self.caret_visible_current;
        self.resetCaretBlinkPhaseOnly();
        if (!was_visible) self.reprojectCurrentSemanticForCaret() catch |err| self.recordRuntimeError(err);
    }

    fn refreshCaretBlink(self: *PlaygroundApp) !void {
        if (!self.native_focused_valid) return;
        const elapsed = self.ui_time_ms -| self.caret_blink_epoch_ms;
        const visible = (elapsed % 1000) < 500;
        if (visible == self.caret_visible_current) return;
        self.caret_visible_current = visible;
        try self.reprojectCurrentSemanticForCaret();
    }

    fn reprojectCurrentSemanticForCaret(self: *PlaygroundApp) !void {
        if (self.semantic) |*semantic| {
            self.applyCaretBlinkToSemantic(semantic);
            var trace = try physical.RenderTrace.project(self.allocator, semantic.*, .{});
            errdefer trace.deinit(self.allocator);
            if (self.trace) |*old_trace| old_trace.deinit(self.allocator);
            self.trace = trace;
        }
    }

    fn applyCaretBlinkToSemantic(self: PlaygroundApp, semantic: *physical.SemanticTree) void {
        for (semantic.inputs, 0..) |*input, index| {
            if (!input.focused) {
                input.caret_visible = true;
                continue;
            }
            if (self.native_focused_valid and index == self.native_focused_input) {
                input.caret_visible = self.caret_visible_current;
            } else {
                input.caret_visible = true;
            }
        }
    }

    fn dispatchEvent(self: *PlaygroundApp, preview_event: bridge.PreviewEvent) void {
        const host = if (self.host) |*host| host else return;
        const output = host.dispatch(preview_event) catch |err| {
            self.recordRuntimeError(err);
            return;
        };
        self.updateProjection(output) catch |err| self.recordRuntimeError(err);
    }

    fn dispatchTerminalKeyIfAccepted(self: *PlaygroundApp, key: []const u8) bool {
        const host = if (self.host) |*host| host else return false;
        const output = host.dispatch(.{ .terminal_key = key }) catch |err| switch (err) {
            error.NotTerminalRoot, error.UnknownTerminalKeyBinding, error.RuntimeNotStarted => return false,
            else => {
                self.recordRuntimeError(err);
                return true;
            },
        };
        self.updateProjection(output) catch |err| self.recordRuntimeError(err);
        return true;
    }

    fn syncNativeInputBuffer(self: *PlaygroundApp, index: u64) !void {
        self.native_input_text.clearRetainingCapacity();
        if (self.semantic) |semantic| {
            if (index < semantic.inputs.len) {
                try self.native_input_text.appendSlice(self.allocator, semantic.inputs[@intCast(index)].text);
            }
        }
    }

    fn syncNativeFocusFromIncomingSemantic(self: *PlaygroundApp, semantic: *const physical.SemanticTree) !void {
        if (self.native_focused_valid and self.native_focused_input < semantic.inputs.len) {
            if (semantic.inputs[@intCast(self.native_focused_input)].handle) |handle| {
                self.native_focused_handle = handle;
            }
            if (!self.native_input_dirty) try self.syncNativeInputBufferFromSemantic(semantic, self.native_focused_input);
            if (semantic.inputs[@intCast(self.native_focused_input)].focused) {
                if (self.native_focused_handle == null) try self.cacheNativeFocusedInputHandle();
                return;
            }
            return;
        }
        for (semantic.inputs, 0..) |input, index| {
            if (!input.focused) continue;
            self.native_focused_input = @intCast(index);
            self.native_focused_valid = true;
            self.native_focused_handle = input.handle;
            if (self.native_focused_handle == null) try self.cacheNativeFocusedInputHandle();
            self.native_input_dirty = false;
            self.native_text_change_pending = false;
            try self.syncNativeInputBufferFromSemantic(semantic, @intCast(index));
            return;
        }
        self.native_focused_valid = false;
        self.native_focused_handle = null;
        self.native_input_dirty = false;
        self.native_text_change_pending = false;
        self.native_input_text.clearRetainingCapacity();
    }

    fn syncNativeInputBufferFromSemantic(self: *PlaygroundApp, semantic: *const physical.SemanticTree, index: u64) !void {
        self.native_input_text.clearRetainingCapacity();
        if (index < semantic.inputs.len) {
            try self.native_input_text.appendSlice(self.allocator, semantic.inputs[@intCast(index)].text);
        }
    }

    fn applyNativeDraftToSemantic(self: *PlaygroundApp, semantic: *physical.SemanticTree) !void {
        if (!self.native_input_dirty or !self.native_focused_valid) return;
        if (self.native_focused_input >= semantic.inputs.len) return;
        const index: usize = @intCast(self.native_focused_input);
        self.allocator.free(semantic.inputs[index].text);
        semantic.inputs[index].text = try self.allocator.dupe(u8, self.native_input_text.items);
    }

    fn screenToProjection(self: *PlaygroundApp, x: f32, y: f32) ?Point {
        const framebuffer_width = self.framebuffer_width;
        const framebuffer_height = self.framebuffer_height;
        const target = previewViewport(framebuffer_width, framebuffer_height);
        const trace = self.trace orelse return null;
        const source_w = @as(f32, @floatFromInt(trace.viewport.width));
        const source_h = @as(f32, @floatFromInt(trace.viewport.height));
        const scale = @min(target.w / source_w, target.h / source_h);
        const origin_x = target.x + (target.w - source_w * scale) * 0.5;
        const origin_y = target.y + (target.h - source_h * scale) * 0.5;
        return .{ .x = (x - origin_x) / scale, .y = (y - origin_y) / scale };
    }

    fn projectionToScreen(self: *PlaygroundApp, point: Point) ?Point {
        const target = previewViewport(self.framebuffer_width, self.framebuffer_height);
        const trace = self.trace orelse return null;
        const source_w = @as(f32, @floatFromInt(trace.viewport.width));
        const source_h = @as(f32, @floatFromInt(trace.viewport.height));
        const scale = @min(target.w / source_w, target.h / source_h);
        const origin_x = target.x + (target.w - source_w * scale) * 0.5;
        const origin_y = target.y + (target.h - source_h * scale) * 0.5;
        return .{
            .x = origin_x + point.x * scale,
            .y = origin_y + point.y * scale,
        };
    }

    fn updateFramebufferSize(self: *PlaygroundApp) void {
        if (self.capture_size) |size| {
            self.framebuffer_width = @floatFromInt(size.width);
            self.framebuffer_height = @floatFromInt(size.height);
            return;
        }
        const window = self.sdl_window orelse return;
        var w: c_int = 0;
        var h: c_int = 0;
        if (c.SDL_GetWindowSizeInPixels(window, &w, &h)) {
            self.framebuffer_width = @floatFromInt(@max(1, w));
            self.framebuffer_height = @floatFromInt(@max(1, h));
        }
    }

    fn beginCaptureRenderTarget(self: *PlaygroundApp, renderer: *c.SDL_Renderer) ?*c.SDL_Texture {
        const size = self.capture_size orelse return null;
        if (self.capture_written) return null;
        const needs_texture = self.capture_texture == null or
            self.capture_texture_width != size.width or
            self.capture_texture_height != size.height;
        if (needs_texture) {
            if (self.capture_texture) |texture| c.SDL_DestroyTexture(texture);
            const texture = c.SDL_CreateTexture(
                renderer,
                c.SDL_PIXELFORMAT_RGBA32,
                c.SDL_TEXTUREACCESS_TARGET,
                size.width,
                size.height,
            ) orelse {
                self.last_error = "CaptureTextureCreateFailed";
                std.log.err("failed to create capture render target", .{});
                self.capture_texture = null;
                return null;
            };
            _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND_PREMULTIPLIED);
            _ = c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_LINEAR);
            self.capture_texture = texture;
            self.capture_texture_width = size.width;
            self.capture_texture_height = size.height;
        }
        const texture = self.capture_texture orelse return null;
        if (!c.SDL_SetRenderTarget(renderer, texture)) {
            self.last_error = "CaptureRenderTargetFailed";
            std.log.err("failed to select capture render target", .{});
            return null;
        }
        return texture;
    }

    fn startSdlTextInput(self: *PlaygroundApp) void {
        const window = self.sdl_window orelse return;
        _ = c.SDL_StartTextInput(window);
        self.updateSdlTextInputArea();
    }

    fn stopSdlTextInput(self: *PlaygroundApp) void {
        const window = self.sdl_window orelse return;
        _ = c.SDL_StopTextInput(window);
    }

    fn updateSdlTextInputArea(self: *PlaygroundApp) void {
        const window = self.sdl_window orelse return;
        const rect = self.focusedTextInputScreenRect() orelse return;
        var sdl_rect = c.SDL_Rect{
            .x = @intFromFloat(@round(rect.x)),
            .y = @intFromFloat(@round(rect.y)),
            .w = @intFromFloat(@round(@max(1, rect.w))),
            .h = @intFromFloat(@round(@max(1, rect.h))),
        };
        _ = c.SDL_SetTextInputArea(window, &sdl_rect, sdl_rect.w);
    }

    fn focusedTextInputScreenRect(self: *PlaygroundApp) ?HitRect {
        if (!self.native_focused_valid) return null;
        const local = self.traceControlRect("text_input", @intCast(self.native_focused_input)) orelse return null;
        const trace = self.trace orelse return null;
        const target = previewViewport(self.framebuffer_width, self.framebuffer_height);
        const source_w = @as(f32, @floatFromInt(trace.viewport.width));
        const source_h = @as(f32, @floatFromInt(trace.viewport.height));
        const scale = @min(target.w / source_w, target.h / source_h);
        const origin_x = target.x + (target.w - source_w * scale) * 0.5;
        const origin_y = target.y + (target.h - source_h * scale) * 0.5;
        return .{
            .x = origin_x + local.x * scale,
            .y = origin_y + local.y * scale,
            .w = local.w * scale,
            .h = local.h * scale,
        };
    }

    fn recordRuntimeError(self: *PlaygroundApp, err: anyerror) void {
        self.last_error = @errorName(err);
        std.log.err("playground interaction failed: {s}", .{@errorName(err)});
    }

    fn processWebBridgeQueue(self: *PlaygroundApp) void {
        if (builtin.os.tag != .emscripten) return;
        var processed: usize = 0;
        while (processed < 32) : (processed += 1) {
            const pending = emscripten_run_script_string(
                \\(()=>{const q=window.__rayboxBridgeQueue;if(!q||q.length===0)return "";return q.shift();})()
            ) orelse return;
            const action_json = std.mem.span(pending);
            if (action_json.len == 0) return;
            self.handleWebBridgeAction(action_json) catch |err| {
                self.last_error = @errorName(err);
                std.log.err("browser bridge action failed: {s}", .{@errorName(err)});
            };
        }
    }

    fn handleWebBridgeAction(self: *PlaygroundApp, action_json: []const u8) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, action_json, .{});
        defer parsed.deinit();
        const action_type = jsonStringField(parsed.value, "type") orelse return error.InvalidBridgeAction;
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;

        if (std.mem.eql(u8, action_type, "noop")) return;
        if (std.mem.eql(u8, action_type, "clear_state") or std.mem.eql(u8, action_type, "clear_states")) {
            try self.restartRuntime();
            return;
        }
        if (std.mem.eql(u8, action_type, "run")) {
            switch (try host.compileEntry()) {
                .ok => {},
                .diagnostics => |diagnostics| return reportDiagnostics(diagnostics, error.CompileDiagnostic),
            }
            try self.updateProjection(try host.start());
            return;
        }
        if (std.mem.eql(u8, action_type, "wait")) {
            const delta = jsonU64Field(parsed.value, "ms") orelse jsonU64Field(parsed.value, "delta") orelse 0;
            self.virtual_clock.advance(delta);
            try self.updateProjection(try host.tick(self.virtual_clock.now_ms));
            return;
        }
        if (std.mem.eql(u8, action_type, "focus_input")) {
            self.web_focused_input = jsonU64Field(parsed.value, "index") orelse 0;
            try self.syncWebInputBuffer(self.web_focused_input);
            try self.cacheWebFocusedInputHandle();
            try self.updateProjection(try host.dispatch(.{ .focus = self.web_focused_input }));
            return;
        }
        if (std.mem.eql(u8, action_type, "set_input_value")) {
            self.web_focused_input = jsonU64Field(parsed.value, "index") orelse self.web_focused_input;
            const text = jsonStringField(parsed.value, "text") orelse "";
            self.web_input_text.clearRetainingCapacity();
            try self.web_input_text.appendSlice(self.allocator, text);
            try self.cacheWebFocusedInputHandle();
            try self.dispatchWebTextInputChange();
            return;
        }
        if (std.mem.eql(u8, action_type, "type")) {
            const text = jsonStringField(parsed.value, "text") orelse "";
            try self.ensureWebInputBuffer();
            try self.web_input_text.appendSlice(self.allocator, text);
            try self.dispatchWebTextInputChange();
            return;
        }
        if (std.mem.eql(u8, action_type, "key")) {
            const key_name = jsonStringField(parsed.value, "key") orelse "";
            const key = parseBridgeKey(key_name);
            try self.ensureWebInputBuffer();
            if (key == .backspace and self.web_input_text.items.len != 0) _ = self.web_input_text.pop();
            try self.dispatchWebTextInputKey(key);
            if (key == .enter or key == .escape) {
                self.web_input_text.clearRetainingCapacity();
            }
            return;
        }
        if (std.mem.eql(u8, action_type, "click_checkbox")) {
            const index = jsonU64Field(parsed.value, "index") orelse 0;
            const checked = jsonBoolField(parsed.value, "checked") orelse true;
            try self.updateProjection(try host.dispatch(.{ .checkbox_change = .{ .link = index, .checked = checked } }));
            return;
        }
        if (std.mem.eql(u8, action_type, "click_button")) {
            const index = jsonU64Field(parsed.value, "index") orelse 0;
            try self.updateProjection(try host.dispatch(.{ .click = index }));
            return;
        }
        if (std.mem.eql(u8, action_type, "click_text")) {
            const text = jsonStringField(parsed.value, "text") orelse return error.InvalidBridgeAction;
            try self.updateProjection(try host.dispatch(.{ .click_text = text }));
            return;
        }
        if (std.mem.eql(u8, action_type, "hover_text")) {
            const text = jsonStringField(parsed.value, "text") orelse return error.InvalidBridgeAction;
            try self.updateProjection(try host.dispatch(.{ .hover_text = .{ .text = text, .hovered = true } }));
            return;
        }
        return error.UnsupportedBridgeAction;
    }

    fn ensureWebInputBuffer(self: *PlaygroundApp) !void {
        if (self.web_input_text.items.len != 0) return;
        try self.syncWebInputBuffer(self.web_focused_input);
        if (self.web_focused_handle == null) try self.cacheWebFocusedInputHandle();
    }

    fn cacheWebFocusedInputHandle(self: *PlaygroundApp) !void {
        self.web_focused_handle = null;
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;
        self.web_focused_handle = try host.textInputHandle(@intCast(self.web_focused_input));
    }

    fn dispatchWebTextInputChange(self: *PlaygroundApp) !void {
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;
        if (self.web_focused_handle) |handle| {
            try host.setTextInputValueWithHandle(handle, self.web_input_text.items);
            try self.updateProjection(try host.tick(self.virtual_clock.now_ms));
        } else {
            try self.updateProjection(try host.dispatch(.{ .change_text = .{ .link = self.web_focused_input, .text = self.web_input_text.items } }));
        }
    }

    fn dispatchWebTextInputKey(self: *PlaygroundApp, key: bridge.Key) !void {
        const host = if (self.host) |*host| host else return error.RuntimeNotInitialized;
        if (self.web_focused_handle) |handle| {
            try host.pressTextInputKeyWithHandle(handle, key, self.web_input_text.items);
            try self.updateProjection(try host.tick(self.virtual_clock.now_ms));
        } else {
            try self.updateProjection(try host.dispatch(.{ .key_down = .{ .link = self.web_focused_input, .key = key, .text = self.web_input_text.items } }));
        }
    }

    fn syncWebInputBuffer(self: *PlaygroundApp, index: u64) !void {
        self.web_input_text.clearRetainingCapacity();
        if (self.semantic) |semantic| {
            if (index < semantic.inputs.len) {
                try self.web_input_text.appendSlice(self.allocator, semantic.inputs[@intCast(index)].text);
            }
        }
    }

    fn updateWebTestBridge(self: *PlaygroundApp) void {
        if (builtin.os.tag != .emscripten) return;
        const state_json = self.webStateJsonAlloc() catch return;
        defer self.allocator.free(state_json);
        const script_bytes = std.fmt.allocPrint(
            self.allocator,
            \\(()=>{{const root=document.documentElement;const clone=(value)=>JSON.parse(JSON.stringify(value));const shot=()=>{{const canvas=document.querySelector("canvas");return canvas?canvas.toDataURL("image/png"):null;}};const state={s};window.__rayboxState=state;if(!window.__rayboxBridgeQueue)window.__rayboxBridgeQueue=[];const snapshot=()=>clone(window.__rayboxState);root.setAttribute("data-raybox-ready",state.ready?"1":"0");root.setAttribute("data-raybox-diagnostics",String(state.diagnostics.length));root.setAttribute("data-raybox-trace-commands",String(state.renderTrace.commands.length));root.setAttribute("data-raybox-semantic-inputs",String(state.semanticTree.inputs.length));root.setAttribute("data-raybox-semantic-buttons",String(state.semanticTree.buttons.length));root.setAttribute("data-raybox-semantic-checkboxes",String(state.semanticTree.checkboxes.length));root.setAttribute("data-raybox-bridge-methods","runExample,clearState,dispatch,semanticTree,renderTrace,frameStats,screenshotPng");window.__rayboxTest={{runExample:(name)=>{{if(name!==state.example)throw new Error("unsupported example: "+name);return snapshot();}},clearState:(name)=>{{if(name!==state.example)throw new Error("unsupported example: "+name);window.__rayboxBridgeQueue.push(JSON.stringify({{type:"clear_state",name}}));return true;}},dispatch:(action)=>{{window.__rayboxBridgeQueue.push(JSON.stringify(action||{{type:"noop"}}));return true;}},semanticTree:()=>clone(window.__rayboxState.semanticTree),renderTrace:()=>clone(window.__rayboxState.renderTrace),frameStats:()=>clone(window.__rayboxState.frameStats),screenshotPng:()=>shot(),ready:()=>window.__rayboxState.ready,diagnostics:()=>window.__rayboxState.diagnostics.slice(),route:()=>window.__rayboxState.route,screenshot:()=>shot(),snapshot}};}})();
        ,
            .{state_json},
        ) catch return;
        defer self.allocator.free(script_bytes);
        const script = self.allocator.dupeZ(u8, script_bytes) catch return;
        defer self.allocator.free(script);
        emscripten_run_script(script.ptr);
    }

    fn webStateJsonAlloc(self: *PlaygroundApp) ![]u8 {
        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();
        const writer = &out.writer;
        try writer.writeAll("{\"ready\":");
        try writer.writeAll(if (self.initialized and self.last_error == null and self.trace != null and self.semantic != null) "true" else "false");
        try writer.writeAll(",\"diagnostics\":[");
        if (self.last_error) |err| try writeJsonString(writer, err);
        try writer.writeAll("],\"semanticTree\":");
        try self.writeSemanticJson(writer);
        try writer.writeAll(",\"renderTrace\":");
        try self.writeTraceJson(writer);
        try writer.print(",\"frameStats\":{{\"frames\":{d},\"traceCommands\":{d}}}", .{
            self.stats.frame_index,
            if (self.trace) |trace| trace.commands.len else 0,
        });
        try writer.writeAll(",\"route\":\"/\",\"example\":");
        try writeJsonString(writer, self.current_example_name);
        try writer.writeByte('}');
        return try out.toOwnedSlice();
    }

    fn writeSemanticJson(self: *PlaygroundApp, writer: *std.Io.Writer) !void {
        if (self.semantic) |semantic| {
            try writer.writeAll("{\"renderedText\":");
            try writeJsonString(writer, semantic.rendered_text);
            try writer.writeAll(",\"inputs\":[");
            for (semantic.inputs, 0..) |input, index| {
                if (index != 0) try writer.writeByte(',');
                try writer.writeAll("{\"text\":");
                try writeJsonString(writer, input.text);
                try writer.writeAll(",\"placeholder\":");
                try writeJsonString(writer, input.placeholder);
                try writer.writeAll(",\"focused\":");
                try writer.writeAll(if (input.focused) "true" else "false");
                try writer.writeAll(",\"disabled\":");
                try writer.writeAll(if (input.disabled) "true" else "false");
                try writer.writeByte('}');
            }
            try writer.writeAll("],\"buttons\":[");
            for (semantic.buttons, 0..) |button, index| {
                if (index != 0) try writer.writeByte(',');
                try writer.writeAll("{\"label\":");
                try writeJsonString(writer, button.label);
                try writer.writeAll(",\"disabled\":");
                try writer.writeAll(if (button.disabled) "true" else "false");
                try writer.writeAll(",\"outlined\":");
                try writer.writeAll(if (button.outlined) "true" else "false");
                try writer.writeByte('}');
            }
            try writer.writeAll("],\"checkboxes\":[");
            for (semantic.checkboxes, 0..) |checkbox, index| {
                if (index != 0) try writer.writeByte(',');
                try writer.writeAll("{\"label\":");
                try writeJsonString(writer, checkbox.label);
                try writer.writeAll(",\"checked\":");
                try writer.writeAll(if (checkbox.checked) "true" else "false");
                try writer.writeByte('}');
            }
            try writer.writeAll("]}");
        } else {
            try writer.writeAll("{\"renderedText\":\"\",\"inputs\":[],\"buttons\":[],\"checkboxes\":[]}");
        }
    }

    fn writeTraceJson(self: *PlaygroundApp, writer: *std.Io.Writer) !void {
        if (self.trace) |trace| {
            try writer.writeAll("{\"theme\":");
            try writeJsonString(writer, trace.theme.name());
            try writer.writeAll(",\"mode\":");
            try writeJsonString(writer, @tagName(trace.mode));
            try writer.writeAll(",\"viewport\":{");
            try writer.print("\"width\":{d},\"height\":{d},\"scale\":{d}", .{ trace.viewport.width, trace.viewport.height, trace.viewport.scale });
            try writer.writeAll("},\"commands\":[");
            for (trace.commands, 0..) |command, index| {
                if (index != 0) try writer.writeByte(',');
                try writer.writeAll("{\"kind\":");
                try writeJsonString(writer, @tagName(command.base.kind));
                try writer.writeAll(",\"role\":");
                try writeJsonString(writer, command.role);
                try writer.writeAll(",\"label\":");
                try writeJsonString(writer, command.label);
                try writer.print(
                    ",\"rect\":{{\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d}}},\"z\":{d},\"alpha\":{d}",
                    .{ command.base.rect.x, command.base.rect.y, command.base.rect.w, command.base.rect.h, command.base.z, command.base.alpha },
                );
                try writer.writeByte('}');
            }
            try writer.writeAll("]}");
        } else {
            try writer.writeAll("{\"theme\":\"professional\",\"mode\":\"light\",\"viewport\":{\"width\":0,\"height\":0,\"scale\":1},\"commands\":[]}");
        }
    }
};

fn exampleIndex(name: []const u8) ?usize {
    for (registry.examples, 0..) |example, index| {
        if (std.mem.eql(u8, example.name, name)) return index;
    }
    for (local_examples.examples, 0..) |example, index| {
        if (std.mem.eql(u8, example.name, name)) return registry.examples.len + index;
    }
    return null;
}

fn firstMultiFileExampleIndex() ?usize {
    for (registry.examples, 0..) |example, index| {
        if (example.kind == .multi_file) return index;
    }
    return null;
}

fn parseSmokeIndex(text: []const u8) !usize {
    return try std.fmt.parseInt(usize, text, 10);
}

fn exampleNameAt(index: usize) []const u8 {
    if (index < registry.examples.len) return registry.examples[index].name;
    const local_index = index - registry.examples.len;
    if (local_index < local_examples.examples.len) return local_examples.examples[local_index].name;
    return "unknown";
}

fn outputTimerCount(output: bridge.RuntimeOutput) usize {
    return switch (output) {
        .document => |document| document.timers.len,
        .scene => |scene| scene.timers.len,
        .diagnostics => 0,
    };
}

fn exampleCount() usize {
    return registry.examples.len + local_examples.examples.len;
}

const Point = struct {
    x: f32,
    y: f32,
};

const HitRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn contains(self: HitRect, point: Point) bool {
        return point.x >= self.x and point.x <= self.x + self.w and point.y >= self.y and point.y <= self.y + self.h;
    }
};

fn physicalRect(rect: HitRect) HitRect {
    return rect;
}

fn previewViewport(width: f32, height: f32) raybox.render.geometry.Rect {
    const left: f32 = playground_layout.preview_left;
    const top: f32 = playground_layout.top_bar_height + playground_layout.outer_padding;
    const margin: f32 = playground_layout.outer_padding;
    return .{
        .x = left,
        .y = top,
        .w = @max(320, width - left - margin),
        .h = @max(320, height - top - margin),
    };
}

fn shellButtonRect(framebuffer_width: f32, index: usize) HitRect {
    const button_width: f32 = 150;
    const button_height: f32 = 52;
    const gap: f32 = 18;
    const right_padding: f32 = 28;
    const top: f32 = 18;
    const total_width = button_width * 3 + gap * 2;
    return .{
        .x = framebuffer_width - right_padding - total_width + @as(f32, @floatFromInt(index)) * (button_width + gap),
        .y = top,
        .w = button_width,
        .h = button_height,
    };
}

fn exampleTabRect(index: usize) HitRect {
    const col = index % playground_layout.tab_columns;
    const row = index / playground_layout.tab_columns;
    return .{
        .x = playground_layout.tab_start_x + @as(f32, @floatFromInt(col)) * (playground_layout.tab_width + playground_layout.tab_gap),
        .y = playground_layout.tab_start_y + @as(f32, @floatFromInt(row)) * (playground_layout.tab_height + playground_layout.tab_gap),
        .w = playground_layout.tab_width,
        .h = playground_layout.tab_height,
    };
}

fn exampleTabIndexAt(point: Point) ?usize {
    for (0..exampleCount()) |index| {
        if (exampleTabRect(index).contains(point)) return index;
    }
    return null;
}

const terminal_control_labels = [_][]const u8{ "up", "down", "enter", "space", "r" };
const terminal_control_keys = [_][]const u8{ "Up", "Down", "Enter", "Space", "r" };

fn terminalControlRect(index: usize) HitRect {
    return .{
        .x = 150 + @as(f32, @floatFromInt(index)) * 140,
        .y = 760,
        .w = 122,
        .h = 48,
    };
}

fn loadNativeProject(allocator: std.mem.Allocator, example: registry.Example) !bridge.Project {
    return switch (example.kind) {
        .single_file => loadNativeSingleFileProject(allocator, example),
        .multi_file => loadNativeMultiFileProject(allocator, example),
    };
}

fn loadNativeSingleFileProject(allocator: std.mem.Allocator, example: registry.Example) !bridge.Project {
    const path = try std.fs.path.join(allocator, &.{ example.root_path, example.entry_file });
    defer allocator.free(path);
    const contents = try readNativeFileAlloc(allocator, path, 4 * 1024 * 1024);
    errdefer allocator.free(contents);
    const files = try allocator.alloc(bridge.ProjectFile, 1);
    errdefer allocator.free(files);
    files[0] = .{
        .path = try allocator.dupe(u8, example.entry_file),
        .contents = contents,
    };
    return .{
        .name = example.name,
        .entry_file = example.entry_file,
        .files = files,
    };
}

fn loadNativeLocalProject(allocator: std.mem.Allocator, example: local_examples.Example) !bridge.Project {
    const path = try std.fs.path.join(allocator, &.{ example.root_path, example.entry_file });
    defer allocator.free(path);
    const contents = try readNativeFileAlloc(allocator, path, 4 * 1024 * 1024);
    errdefer allocator.free(contents);
    const files = try allocator.alloc(bridge.ProjectFile, 1);
    errdefer allocator.free(files);
    files[0] = .{
        .path = try allocator.dupe(u8, example.entry_file),
        .contents = contents,
    };
    return .{
        .name = example.name,
        .entry_file = example.entry_file,
        .files = files,
    };
}

fn loadNativeMultiFileProject(allocator: std.mem.Allocator, example: registry.Example) !bridge.Project {
    var files_list: std.ArrayList(bridge.ProjectFile) = .empty;
    errdefer freeNativeProjectFiles(allocator, files_list.items);
    try collectNativeProjectFiles(allocator, example.root_path, "", &files_list);
    std.mem.sort(bridge.ProjectFile, files_list.items, {}, projectFilePathLessThan);
    if (!projectContainsFile(files_list.items, example.entry_file)) return error.EntryFileNotFound;
    const files = try files_list.toOwnedSlice(allocator);
    return .{
        .name = example.name,
        .entry_file = example.entry_file,
        .files = files,
    };
}

fn collectNativeProjectFiles(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    relative_dir: []const u8,
    files: *std.ArrayList(bridge.ProjectFile),
) !void {
    const dir_path = if (relative_dir.len == 0)
        try allocator.dupe(u8, root_path)
    else
        try std.fs.path.join(allocator, &.{ root_path, relative_dir });
    defer allocator.free(dir_path);

    const dir_path_z = try allocator.dupeZ(u8, dir_path);
    defer allocator.free(dir_path_z);
    const dir = c_opendir(dir_path_z.ptr) orelse return error.DirectoryOpenFailed;
    defer _ = c_closedir(dir);

    while (c_readdir(dir)) |entry| {
        const name = direntName(entry);
        if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        const relative = if (relative_dir.len == 0)
            try allocator.dupe(u8, name)
        else
            try std.fs.path.join(allocator, &.{ relative_dir, name });
        errdefer allocator.free(relative);

        if (entry.d_type == dirent_type_directory) {
            try collectNativeProjectFiles(allocator, root_path, relative, files);
            allocator.free(relative);
            continue;
        }
        if (entry.d_type != dirent_type_file and entry.d_type != dirent_type_unknown) {
            allocator.free(relative);
            continue;
        }

        const full_path = try std.fs.path.join(allocator, &.{ root_path, relative });
        defer allocator.free(full_path);
        const contents = readNativeFileAlloc(allocator, full_path, 4 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound, error.FileReadFailed => {
                allocator.free(relative);
                continue;
            },
            else => return err,
        };
        errdefer allocator.free(contents);
        try files.append(allocator, .{
            .path = relative,
            .contents = contents,
            .generated = std.mem.startsWith(u8, relative, "Generated/"),
        });
    }
}

fn direntName(entry: *const Dirent) []const u8 {
    var len: usize = 0;
    while (len < entry.d_name.len and entry.d_name[len] != 0) : (len += 1) {}
    return entry.d_name[0..len];
}

fn projectContainsFile(files: []const bridge.ProjectFile, path: []const u8) bool {
    for (files) |file| {
        if (std.mem.eql(u8, file.path, path)) return true;
    }
    return false;
}

fn projectFilePathLessThan(_: void, lhs: bridge.ProjectFile, rhs: bridge.ProjectFile) bool {
    return std.mem.lessThan(u8, lhs.path, rhs.path);
}

fn projectFileForPreview(project: bridge.Project) bridge.ProjectFile {
    for (project.files) |file| {
        if (std.mem.eql(u8, file.path, project.entry_file)) return file;
    }
    return project.files[0];
}

fn appendSourceLines(writer: *std.Io.Writer, contents: []const u8, max_lines: usize, max_columns: usize) !void {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    var emitted: usize = 0;
    while (emitted < max_lines) {
        const line = lines.next() orelse return;
        const trimmed = std.mem.trim(u8, line, "\r");
        if (trimmed.len == 0) {
            try writer.writeByte('\n');
            emitted += 1;
            continue;
        }
        var offset: usize = 0;
        while (offset < trimmed.len and emitted < max_lines) {
            const continuation = offset != 0;
            if (continuation) try writer.writeAll("  ");
            const available_columns = if (continuation and max_columns > 2) max_columns - 2 else max_columns;
            const end = @min(trimmed.len, offset + available_columns);
            try writer.writeAll(trimmed[offset..end]);
            try writer.writeByte('\n');
            offset = end;
            emitted += 1;
        }
    }
    if (lines.next() != null) {
        try writer.writeAll("...\n");
    }
}

fn freeNativeProject(allocator: std.mem.Allocator, project: bridge.Project) void {
    freeNativeProjectFiles(allocator, project.files);
    allocator.free(project.files);
}

fn freeNativeProjectFiles(allocator: std.mem.Allocator, files: []const bridge.ProjectFile) void {
    for (files) |file| {
        allocator.free(file.path);
        allocator.free(file.contents);
    }
}

fn readNativeFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_size: usize) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const file = c_fopen(path_z.ptr, "rb") orelse return error.FileNotFound;
    defer _ = c_fclose(file);
    if (c_fseek(file, 0, 2) != 0) return error.FileSeekFailed;
    const end = c_ftell(file);
    if (end < 0) return error.FileTellFailed;
    const size: usize = @intCast(end);
    if (size > max_size) return error.FileTooLarge;
    if (c_fseek(file, 0, 0) != 0) return error.FileSeekFailed;
    const bytes = try allocator.alloc(u8, size);
    errdefer allocator.free(bytes);
    const read = c_fread(bytes.ptr, 1, size, file);
    if (read != size) return error.FileReadFailed;
    return bytes;
}

fn reportDiagnostics(diagnostics: []const bridge.Diagnostic, fallback: anyerror) anyerror {
    for (diagnostics) |diagnostic| {
        std.log.err("boon diagnostic: {s}", .{diagnostic.message});
    }
    return fallback;
}

extern fn emscripten_run_script(script: [*:0]const u8) void;
extern fn emscripten_run_script_string(script: [*:0]const u8) ?[*:0]u8;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(file: *anyopaque) c_int;
extern fn fseek(file: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(file: *anyopaque) c_long;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, file: *anyopaque) usize;
const Dir = opaque {};
const Dirent = extern struct {
    d_ino: c_ulong,
    d_off: c_long,
    d_reclen: c_ushort,
    d_type: u8,
    d_name: [256]u8,
};
extern fn opendir(path: [*:0]const u8) ?*Dir;
extern fn readdir(dir: *Dir) ?*Dirent;
extern fn closedir(dir: *Dir) c_int;

const c_fopen = fopen;
const c_fclose = fclose;
const c_fseek = fseek;
const c_ftell = ftell;
const c_fread = fread;
const c_opendir = opendir;
const c_readdir = readdir;
const c_closedir = closedir;
const dirent_type_unknown: u8 = 0;
const dirent_type_directory: u8 = 4;
const dirent_type_file: u8 = 8;

fn parseBridgeKey(key_text: []const u8) bridge.Key {
    if (std.mem.eql(u8, key_text, "Enter")) return .enter;
    if (std.mem.eql(u8, key_text, "Escape")) return .escape;
    if (std.mem.eql(u8, key_text, "Backspace")) return .backspace;
    if (std.mem.eql(u8, key_text, "Tab")) return .tab;
    return .unknown;
}

fn jsonStringField(value: std.json.Value, name: []const u8) ?[]const u8 {
    const field = jsonField(value, name) orelse return null;
    return switch (field) {
        .string => |text| text,
        else => null,
    };
}

fn jsonBoolField(value: std.json.Value, name: []const u8) ?bool {
    const field = jsonField(value, name) orelse return null;
    return switch (field) {
        .bool => |boolean| boolean,
        else => null,
    };
}

fn jsonU64Field(value: std.json.Value, name: []const u8) ?u64 {
    const field = jsonField(value, name) orelse return null;
    return switch (field) {
        .integer => |integer| if (integer >= 0) @intCast(integer) else null,
        .float => |float| if (float >= 0) @intFromFloat(float) else null,
        else => null,
    };
}

fn jsonField(value: std.json.Value, name: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(name),
        else => null,
    };
}

fn writeJsonString(writer: *std.Io.Writer, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...8, 11, 12, 14...0x1f => try writer.print("\\u{x:0>4}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}
