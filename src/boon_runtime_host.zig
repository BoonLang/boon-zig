const std = @import("std");
const diag = @import("diag.zig");
const headless = @import("headless.zig");
const parser = @import("parser.zig");

pub const ValueId = u32;
pub const LinkId = u64;

pub const SourceSpan = struct {
    start: usize,
    end: usize,
};

pub const Diagnostic = struct {
    severity: enum { info, warning, err },
    file_path: ?[]const u8 = null,
    span: ?SourceSpan = null,
    message: []const u8,
};

pub const ProjectFile = struct {
    path: []const u8,
    contents: []const u8,
    generated: bool = false,
};

pub const Project = struct {
    name: []const u8,
    entry_file: []const u8,
    files: []const ProjectFile,
    assets_root: ?[]const u8 = null,
};

pub const BuildSummary = struct {
    generated_files: []const []const u8 = &.{},
    logs: []const Diagnostic = &.{},
};

pub const BuildResult = union(enum) {
    not_present,
    ok: BuildSummary,
    diagnostics: []const Diagnostic,
};

pub const CompiledProject = struct {
    revision: u64,
};

pub const CompileResult = union(enum) {
    ok: CompiledProject,
    diagnostics: []const Diagnostic,
};

pub const VirtualClock = struct {
    now_ms: u64 = 0,

    pub fn advance(self: *VirtualClock, delta_ms: u64) void {
        self.now_ms +|= delta_ms;
    }
};

pub const TimeSource = union(enum) {
    real,
    virtual: *VirtualClock,
};

pub const RecordField = struct {
    name: []const u8,
    value: ValueId,
};

pub const ElementNode = struct {
    kind: []const u8,
    args: []const RecordField = &.{},
    stable_id: []const u8 = "",
};

pub const RuntimeValue = union(enum) {
    none,
    number: f64,
    bool: bool,
    text: []const u8,
    symbol: []const u8,
    list: []const ValueId,
    record: []const RecordField,
    element: ElementNode,
};

pub const ControlHandle = headless.ControlEventRef;

pub const EventBinding = struct {
    id: LinkId,
    source_value: ValueId,
    event_name: []const u8,
    handle: ?ControlHandle = null,
};

pub const SnapshotProfile = struct {
    calls: u64 = 0,
    render_ns: u64 = 0,
    semantic_root_ns: u64 = 0,
    snapshot_values_ns: u64 = 0,
    event_bindings_ns: u64 = 0,
    route_ns: u64 = 0,
};

pub const TimerBinding = struct {
    id: LinkId,
    interval_ms: u64,
};

pub const LightValue = struct {
    kind: []const u8,
    args: []const RecordField = &.{},
};

pub const DocumentSnapshot = struct {
    revision: u64,
    root: ValueId,
    values: []const RuntimeValue,
    events: []const EventBinding = &.{},
    timers: []const TimerBinding = &.{},
    route: []const u8 = "",
};

pub const SceneSnapshot = struct {
    revision: u64,
    root: ValueId,
    values: []const RuntimeValue,
    lights: []const LightValue = &.{},
    geometry: RuntimeValue = .none,
    events: []const EventBinding = &.{},
    timers: []const TimerBinding = &.{},
    route: []const u8 = "",
};

pub const RuntimeOutput = union(enum) {
    document: DocumentSnapshot,
    scene: SceneSnapshot,
    diagnostics: []const Diagnostic,
};

pub const Key = enum {
    unknown,
    enter,
    escape,
    tab,
    backspace,
    delete,
    arrow_left,
    arrow_right,
    arrow_up,
    arrow_down,
};

pub const PreviewEvent = union(enum) {
    press: LinkId,
    click: LinkId,
    click_ref: ControlHandle,
    click_text: []const u8,
    terminal_key: []const u8,
    double_click: LinkId,
    double_click_text: []const u8,
    hover: struct { link: LinkId, hovered: bool },
    hover_text: struct { text: []const u8, hovered: bool },
    change_text: struct { link: LinkId, text: []const u8 },
    key_down: struct { link: LinkId, key: Key, text: []const u8 },
    blur: LinkId,
    focus: LinkId,
    checkbox_change: struct { link: LinkId, checked: bool },
    checkbox_ref_change: struct { handle: ControlHandle, checked: bool },
    select_change: struct { link: LinkId, value: []const u8 },
    slider_change: struct { link: LinkId, value: f64 },
    svg_click: struct { link: LinkId, x: f32, y: f32 },
    svg_click_ref: struct { handle: ControlHandle, x: f32, y: f32 },
};

pub const TextInputHandle = headless.TextInputSessionRef;

pub const PersistStore = struct {
    ptr: *anyopaque,
    read: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8,
    write: *const fn (ptr: *anyopaque, key: []const u8, value: []const u8) anyerror!void,
    deletePrefix: *const fn (ptr: *anyopaque, prefix: []const u8) anyerror!void,
};

pub const RouteStore = struct {
    ptr: *anyopaque,
    current: *const fn (ptr: *anyopaque) []const u8,
    goTo: *const fn (ptr: *anyopaque, route: []const u8) anyerror!void,
};

pub const BoonRuntimeHost = struct {
    allocator: std.mem.Allocator,
    persist: *PersistStore,
    route: *RouteStore,
    time: *TimeSource,
    project_loaded: bool = false,
    has_build_file: bool = false,
    compiled_revision: u64 = 0,
    project_name: []u8 = &.{},
    entry_file: []u8 = &.{},
    files: []ProjectFile = &.{},
    compiled: ?headless.CompiledProgram = null,
    session: ?headless.Session = null,
    snapshot_values: []RuntimeValue = &.{},
    snapshot_events: []EventBinding = &.{},
    snapshot_timers: []TimerBinding = &.{},
    diagnostics: []Diagnostic = &.{},
    build_generated_files: [][]const u8 = &.{},
    build_logs: []Diagnostic = &.{},
    include_rendered_text: bool = true,
    include_control_visuals: bool = true,
    include_event_bindings: bool = true,
    persist_runtime_state: bool = true,
    profile_snapshots: bool = false,
    trace_runtime: bool = false,
    last_snapshot_profile: SnapshotProfile = .{},

    const ModuleInfo = struct {
        name: []const u8,
        path: []const u8,
        source: []const u8,
        functions: [][]const u8,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        persist: *PersistStore,
        route: *RouteStore,
        time: *TimeSource,
    ) !BoonRuntimeHost {
        return .{
            .allocator = allocator,
            .persist = persist,
            .route = route,
            .time = time,
        };
    }

    pub fn deinit(self: *BoonRuntimeHost) void {
        self.clearRuntime();
        self.clearProject();
        self.clearDiagnostics();
        self.clearBuildSummary();
    }

    pub fn loadProject(self: *BoonRuntimeHost, project: Project) !void {
        self.clearRuntime();
        self.clearProject();
        self.clearDiagnostics();
        self.clearBuildSummary();
        self.project_loaded = true;
        self.has_build_file = false;
        self.project_name = try self.allocator.dupe(u8, project.name);
        self.entry_file = try self.allocator.dupe(u8, project.entry_file);
        self.files = try self.allocator.alloc(ProjectFile, project.files.len);
        for (project.files, 0..) |file, index| {
            self.files[index] = .{
                .path = try self.allocator.dupe(u8, file.path),
                .contents = try self.allocator.dupe(u8, file.contents),
                .generated = file.generated,
            };
            if (std.mem.eql(u8, file.path, "BUILD.bn")) {
                self.has_build_file = true;
            }
        }
    }

    pub fn runBuildFile(self: *BoonRuntimeHost) !BuildResult {
        self.clearDiagnostics();
        self.clearBuildSummary();
        if (!self.project_loaded) return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.loadProject must be called before runBuildFile") };
        if (!self.has_build_file) return .not_present;
        const build_file = self.projectFileContents("BUILD.bn") orelse {
            return .{ .diagnostics = try self.unsupported("BoonRuntimeHost BUILD.bn was marked present but could not be read") };
        };

        const parsed = try parser.parseAlloc(self.allocator, build_file);
        switch (parsed) {
            .ok => |document| {
                var cleanup = document;
                cleanup.deinit();
            },
            .err => |failure| return .{ .diagnostics = try self.diagnosticFromHeadless(failure) },
        }

        var build_host = BuildHost.init(self, build_file);
        build_host.run() catch |err| switch (err) {
            error.UnsupportedBuildScript => return .{ .diagnostics = try self.unsupported(build_host.unsupported_message orelse "BoonRuntimeHost BUILD.bn host does not support this build script") },
            error.NoIconSvgFiles => return .{ .diagnostics = try self.unsupported("BoonRuntimeHost BUILD.bn Directory/entries(./assets/icons) found no SVG files") },
            error.GeneratedAssetsMismatch => return .{ .diagnostics = try self.unsupported("BoonRuntimeHost BUILD.bn generated ./Generated/Assets.bn, but it does not match the pinned checked-in file") },
            else => return err,
        };
        self.build_generated_files = try self.allocator.alloc([]const u8, 1);
        self.build_generated_files[0] = try self.allocator.dupe(u8, BuildHost.output_path);
        self.build_logs = try self.allocator.alloc(Diagnostic, 1);
        self.build_logs[0] = .{
            .severity = .info,
            .message = try std.fmt.allocPrint(self.allocator, "Included {d} icons", .{build_host.generated_icon_count}),
        };
        return .{ .ok = .{
            .generated_files = self.build_generated_files,
            .logs = self.build_logs,
        } };
    }

    pub fn compileEntry(self: *BoonRuntimeHost) !CompileResult {
        self.clearRuntime();
        self.clearDiagnostics();
        if (!self.project_loaded) return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.loadProject must be called before compileEntry") };
        const entry_source = self.entryContents() orelse {
            return .{ .diagnostics = try self.unsupported("BoonRuntimeHost project entry file was not found") };
        };
        const source = if (self.importableModuleCount() == 0)
            try self.allocator.dupe(u8, entry_source)
        else
            self.combinedModuleSourceAlloc(entry_source) catch |err| {
                if (self.diagnostics.len != 0) return .{ .diagnostics = self.diagnostics };
                return err;
            };
        defer self.allocator.free(source);
        const outcome = try headless.compileAlloc(self.allocator, source);
        switch (outcome) {
            .ok => |compiled| {
                self.compiled = compiled;
                self.compiled_revision +|= 1;
                return .{ .ok = .{ .revision = self.compiled_revision } };
            },
            .err => |failure| return .{ .diagnostics = try self.diagnosticFromHeadless(failure) },
        }
    }

    pub fn start(self: *BoonRuntimeHost) !RuntimeOutput {
        if (try self.startSession()) |diagnostics| return .{ .diagnostics = diagnostics };
        return try self.snapshotOutput();
    }

    pub fn startNoSnapshot(self: *BoonRuntimeHost) !void {
        if (try self.startSession()) |_| return error.RuntimeDiagnostic;
    }

    fn startSession(self: *BoonRuntimeHost) !?[]const Diagnostic {
        self.clearDiagnostics();
        if (self.compiled == null) {
            const compiled = try self.compileEntry();
            switch (compiled) {
                .ok => {},
                .diagnostics => |diagnostics| return diagnostics,
            }
        }
        if (self.session) |*old_session| old_session.deinit();
        self.session = null;
        const compiled = self.compiled orelse return try self.unsupported("BoonRuntimeHost compileEntry did not produce a compiled project");
        self.compiled = null;
        try ensureStateDir();
        const state_file_path = try self.stateFilePathAlloc(self.project_name);
        defer self.allocator.free(state_file_path);
        const outcome = try headless.runCompiledAlloc(self.allocator, compiled, .{
            .virtual_time_ms = self.currentVirtualTime(),
            .state_file_path = if (self.persist_runtime_state) state_file_path else null,
            .trace = self.trace_runtime,
        });
        switch (outcome) {
            .ok => |session| {
                self.session = session;
                return null;
            },
            .err => |failure| {
                return try self.diagnosticFromHeadless(failure);
            },
        }
    }

    pub fn dispatch(self: *BoonRuntimeHost, event: PreviewEvent) !RuntimeOutput {
        self.clearDiagnostics();
        const session = if (self.session) |*session| session else return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.start must be called before dispatch") };
        try self.dispatchIntoSession(session, event);
        return try self.snapshotOutput();
    }

    pub fn dispatchNoSnapshot(self: *BoonRuntimeHost, event: PreviewEvent) !void {
        self.clearDiagnostics();
        const session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        try self.dispatchIntoSession(session, event);
    }

    pub fn renderTextAlloc(self: *BoonRuntimeHost, allocator: std.mem.Allocator) ![]u8 {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.renderAlloc(allocator);
    }

    pub fn traceAlloc(self: *BoonRuntimeHost, allocator: std.mem.Allocator) ![]u8 {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.traceAlloc(allocator);
    }

    pub fn renderCompactGridTextAlloc(
        self: *BoonRuntimeHost,
        allocator: std.mem.Allocator,
        max_row_items: usize,
        max_column_head_items: usize,
    ) ![]u8 {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.renderCompactGridAlloc(allocator, max_row_items, max_column_head_items);
    }

    pub fn textInputHandle(self: *BoonRuntimeHost, index: usize) !TextInputHandle {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.textInputSessionRef(index);
    }

    pub fn checkboxHandle(self: *BoonRuntimeHost, index: usize) !ControlHandle {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.checkboxSessionRef(index);
    }

    pub fn buttonHandle(self: *BoonRuntimeHost, index: usize) !ControlHandle {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.buttonSessionRef(index);
    }

    pub fn checkboxChecked(self: *BoonRuntimeHost, handle: ControlHandle) !bool {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.controlBoolValue(handle);
    }

    pub fn checkboxCheckedMany(self: *BoonRuntimeHost, allocator: std.mem.Allocator, handles: []const ControlHandle) ![]bool {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        return try session.controlBoolValues(allocator, handles);
    }

    pub fn setTextInputValueWithHandle(self: *BoonRuntimeHost, handle: TextInputHandle, text: []const u8) !void {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        try session.setTextInputValueRef(handle.change, text);
    }

    pub fn pressTextInputKeyWithHandle(self: *BoonRuntimeHost, handle: TextInputHandle, key: Key, text: []const u8) !void {
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        try session.pressTextInputKeyRef(handle.key, handle.change, previewKeyName(key), text);
    }

    pub fn blurTextInputWithHandle(self: *BoonRuntimeHost, handle: TextInputHandle) !void {
        const event = handle.blur orelse return;
        var session = if (self.session) |*session| session else return error.RuntimeNotStarted;
        try session.blurTextInputRef(event);
    }

    fn dispatchIntoSession(self: *BoonRuntimeHost, session: *headless.Session, event: PreviewEvent) !void {
        switch (event) {
            .press, .click => |link| try session.clickButton(@intCast(link)),
            .click_ref => |handle| try session.clickButtonRef(handle),
            .click_text => |label| try session.clickButtonByLabel(self.allocator, label),
            .terminal_key => |key| try dispatchTerminalKey(session, key),
            .double_click => |link| try session.doubleClickLabel(@intCast(link)),
            .double_click_text => |label| try session.doubleClickLabelByText(self.allocator, label),
            .hover => |payload| try session.setHover(@intCast(payload.link), payload.hovered),
            .hover_text => |payload| try session.setHoverByLabel(self.allocator, payload.text, payload.hovered),
            .change_text => |payload| try session.setTextInputValue(@intCast(payload.link), payload.text),
            .key_down => |payload| try session.pressTextInputKeyWithText(@intCast(payload.link), previewKeyName(payload.key), payload.text),
            .blur => |link| try session.blurTextInput(@intCast(link)),
            .focus => |link| try session.focusTextInput(@intCast(link)),
            .checkbox_change => |payload| {
                _ = payload.checked;
                try session.clickCheckbox(@intCast(payload.link));
            },
            .checkbox_ref_change => |payload| {
                _ = payload.checked;
                try session.clickCheckboxRef(payload.handle);
            },
            .select_change => |payload| try session.setSelectValue(@intCast(payload.link), payload.value),
            .slider_change => |payload| try session.setSliderValue(@intCast(payload.link), payload.value),
            .svg_click => |payload| try session.triggerLinkAt(@intCast(payload.link), payload.x, payload.y),
            .svg_click_ref => |payload| try session.triggerLinkRefAt(payload.handle, payload.x, payload.y),
        }
    }

    pub fn tick(self: *BoonRuntimeHost, now_ms: u64) !RuntimeOutput {
        self.clearDiagnostics();
        var session = if (self.session) |*session| session else return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.start must be called before tick") };
        const delta = if (now_ms > session.current_time_ms) now_ms - session.current_time_ms else 0;
        if (delta != 0) try session.advanceTime(delta);
        return try self.snapshotOutput();
    }

    pub fn clearState(self: *BoonRuntimeHost, project_name: []const u8) !void {
        self.clearDiagnostics();
        try self.persist.deletePrefix(self.persist.ptr, project_name);
        const state_file_path = try self.stateFilePathAlloc(project_name);
        defer self.allocator.free(state_file_path);
        const state_file_path_z = try self.allocator.dupeZ(u8, state_file_path);
        defer self.allocator.free(state_file_path_z);
        _ = c_unlink(state_file_path_z.ptr);
    }

    pub fn snapshotProfile(self: *const BoonRuntimeHost) SnapshotProfile {
        return self.last_snapshot_profile;
    }

    fn unsupported(self: *BoonRuntimeHost, message: []const u8) ![]const Diagnostic {
        self.diagnostics = try self.allocator.dupe(Diagnostic, &.{
            .{
                .severity = .err,
                .message = message,
            },
        });
        return self.diagnostics;
    }

    fn clearDiagnostics(self: *BoonRuntimeHost) void {
        if (self.diagnostics.len != 0) {
            self.allocator.free(self.diagnostics);
            self.diagnostics = &.{};
        }
    }

    fn diagnosticFromHeadless(self: *BoonRuntimeHost, failure: diag.Diagnostic) ![]const Diagnostic {
        self.diagnostics = try self.allocator.dupe(Diagnostic, &.{
            .{
                .severity = .err,
                .message = failure.message,
            },
        });
        return self.diagnostics;
    }

    fn snapshotOutput(self: *BoonRuntimeHost) !RuntimeOutput {
        var session = if (self.session) |*session| session else return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.start must be called before snapshot") };
        self.last_snapshot_profile = .{};
        self.last_snapshot_profile.calls = 1;
        const previous_include_control_visuals = session.include_control_visuals;
        defer session.include_control_visuals = previous_include_control_visuals;
        session.include_control_visuals = self.include_control_visuals;
        const semantic_start = monotonicNanoseconds();
        const semantic_value = try session.semanticRootValue();
        self.last_snapshot_profile.semantic_root_ns = monotonicNanoseconds() - semantic_start;
        const render_start = monotonicNanoseconds();
        const rendered = if (self.include_rendered_text) switch (session.rootKind()) {
            .scene => try session.renderAlloc(self.allocator),
            else => try session.snapshotAlloc(self.allocator),
        } else try self.allocator.dupe(u8, "");
        self.last_snapshot_profile.render_ns = monotonicNanoseconds() - render_start;
        defer self.allocator.free(rendered);
        self.clearSnapshotValues();
        self.clearSnapshotEvents();

        var builder = SnapshotBuilder.init(self.allocator, session);
        defer builder.deinit();
        const values_start = monotonicNanoseconds();
        const semantic_root = try builder.appendValue(semantic_value);
        const rendered_text = try builder.appendValue(.{ .text = rendered });
        const root = try builder.appendElementIds("document", &.{
            .{ .name = "rendered_text", .value = rendered_text },
            .{ .name = "root", .value = semantic_root },
        });
        self.snapshot_values = try builder.finish();
        self.last_snapshot_profile.snapshot_values_ns = monotonicNanoseconds() - values_start;
        const events_start = monotonicNanoseconds();
        self.snapshot_events = if (self.include_event_bindings)
            try self.collectEventBindings(session)
        else
            &.{};
        self.last_snapshot_profile.event_bindings_ns = monotonicNanoseconds() - events_start;
        self.clearSnapshotTimers();
        self.snapshot_timers = try self.collectTimerBindings(session);
        const route_start = monotonicNanoseconds();
        const route = session.routeTextView() catch self.route.current(self.route.ptr);
        self.last_snapshot_profile.route_ns = monotonicNanoseconds() - route_start;
        if (self.profile_snapshots) {
            std.debug.print(
                "snapshot profile render={d:.3}ms semantic_root={d:.3}ms values={d:.3}ms events={d:.3}ms route={d:.3}ms\n",
                .{
                    nsToMs(self.last_snapshot_profile.render_ns),
                    nsToMs(self.last_snapshot_profile.semantic_root_ns),
                    nsToMs(self.last_snapshot_profile.snapshot_values_ns),
                    nsToMs(self.last_snapshot_profile.event_bindings_ns),
                    nsToMs(self.last_snapshot_profile.route_ns),
                },
            );
        }
        const document = DocumentSnapshot{
            .revision = self.compiled_revision,
            .root = root,
            .values = self.snapshot_values,
            .events = self.snapshot_events,
            .timers = self.snapshot_timers,
            .route = route,
        };
        return .{ .document = document };
    }

    fn collectTimerBindings(self: *BoonRuntimeHost, session: *headless.Session) ![]TimerBinding {
        const refs = try session.timerBindingsAlloc(self.allocator);
        defer self.allocator.free(refs);
        if (refs.len == 0) return &.{};
        const timers = try self.allocator.alloc(TimerBinding, refs.len);
        for (refs, 0..) |timer, index| {
            timers[index] = .{ .id = @intCast(timer.id), .interval_ms = timer.interval_ms };
        }
        return timers;
    }

    fn collectEventBindings(self: *BoonRuntimeHost, session: *headless.Session) ![]EventBinding {
        var events = std.ArrayList(EventBinding).empty;
        defer events.deinit(self.allocator);
        try appendControlEvents(self.allocator, &events, try session.clickControlRefs(), "click");
        try appendControlEvents(self.allocator, &events, try session.textInputChangeControlRefs(), "change_text");
        try appendControlEvents(self.allocator, &events, try session.textInputKeyControlRefs(), "key_down");
        try appendControlEvents(self.allocator, &events, try session.textInputBlurControlRefs(), "blur");
        try appendControlEvents(self.allocator, &events, try session.textInputFocusControlRefs(), "focus");
        const counts = try session.controlBindingCounts();
        try appendCountedEvents(self.allocator, &events, counts.double_click, "double_click");
        try appendCountedEvents(self.allocator, &events, counts.select, "select_change");
        try appendCountedEvents(self.allocator, &events, counts.hover, "hover");
        return try events.toOwnedSlice(self.allocator);
    }

    fn appendCountedEvents(
        allocator: std.mem.Allocator,
        events: *std.ArrayList(EventBinding),
        count: usize,
        event_name: []const u8,
    ) !void {
        for (0..count) |index| {
            try events.append(allocator, .{
                .id = @intCast(index),
                .source_value = 0,
                .event_name = event_name,
            });
        }
    }

    fn appendControlEvents(
        allocator: std.mem.Allocator,
        events: *std.ArrayList(EventBinding),
        controls: []const ControlHandle,
        event_name: []const u8,
    ) !void {
        for (controls) |control| {
            try events.append(allocator, .{
                .id = @intCast(control.link),
                .source_value = 0,
                .event_name = event_name,
                .handle = control,
            });
        }
    }

    fn appendSectionEvents(
        allocator: std.mem.Allocator,
        events: *std.ArrayList(EventBinding),
        controls: []const u8,
        section_name: []const u8,
        event_name: []const u8,
    ) !void {
        const header = try std.fmt.allocPrint(allocator, "{s} (", .{section_name});
        defer allocator.free(header);
        const section_start = std.mem.indexOf(u8, controls, header) orelse return;
        const after_header = controls[section_start + header.len ..];
        const count_end = std.mem.indexOfScalar(u8, after_header, ')') orelse return;
        const count = std.fmt.parseUnsigned(usize, after_header[0..count_end], 10) catch return;
        for (0..count) |index| {
            try events.append(allocator, .{
                .id = @intCast(index),
                .source_value = 0,
                .event_name = event_name,
            });
        }
    }

    fn dispatchTerminalKey(session: *headless.Session, key: []const u8) !void {
        const contract = (try session.terminalContractView()) orelse return error.NotTerminalRoot;
        for (contract.keyboard_bindings) |binding| {
            if (!binding.when) continue;
            for (binding.keys) |candidate| {
                if (std.mem.eql(u8, candidate, key)) {
                    try session.triggerLinkWithScope(binding.link, binding.scope);
                    return;
                }
            }
        }
        return error.UnknownTerminalKeyBinding;
    }

    fn entryContents(self: *const BoonRuntimeHost) ?[]const u8 {
        return self.projectFileContents(self.entry_file);
    }

    fn projectFileContents(self: *const BoonRuntimeHost, path: []const u8) ?[]const u8 {
        for (self.files) |file| {
            if (std.mem.eql(u8, file.path, path)) return file.contents;
        }
        return null;
    }

    fn projectFileIndex(self: *const BoonRuntimeHost, path: []const u8) ?usize {
        for (self.files, 0..) |file, index| {
            if (std.mem.eql(u8, file.path, path)) return index;
        }
        return null;
    }

    fn writeProjectFile(self: *BoonRuntimeHost, path: []const u8, contents: []const u8, generated: bool) !void {
        if (self.projectFileIndex(path)) |index| {
            self.allocator.free(self.files[index].contents);
            self.files[index].contents = try self.allocator.dupe(u8, contents);
            self.files[index].generated = generated;
            return;
        }

        const old_files = self.files;
        const next = try self.allocator.alloc(ProjectFile, old_files.len + 1);
        @memcpy(next[0..old_files.len], old_files);
        next[old_files.len] = .{
            .path = try self.allocator.dupe(u8, path),
            .contents = try self.allocator.dupe(u8, contents),
            .generated = generated,
        };
        self.allocator.free(old_files);
        self.files = next;
    }

    const BuildHost = struct {
        const icons_directory = "./assets/icons";
        const output_path = "Generated/Assets.bn";

        runtime: *BoonRuntimeHost,
        build_file: []const u8,
        generated_icon_count: usize = 0,
        unsupported_message: ?[]const u8 = null,

        const DirectoryEntry = struct {
            file_index: usize,
            path: []const u8,
            file_name: []const u8,
            file_stem: []const u8,
            extension: []const u8,
            is_file: bool = true,
            is_directory: bool = false,
        };

        fn init(runtime: *BoonRuntimeHost, build_file: []const u8) BuildHost {
            return .{ .runtime = runtime, .build_file = build_file };
        }

        fn run(self: *BuildHost) !void {
            try self.requireSupportedScript();

            var entries = try self.directoryEntries(icons_directory);
            defer entries.deinit(self.runtime.allocator);
            self.listRetainExtension(&entries, "svg");
            self.listSortByPath(entries.items);
            if (entries.items.len == 0) return error.NoIconSvgFiles;

            var icon_lines = std.ArrayList([]u8).empty;
            defer {
                for (icon_lines.items) |line| self.runtime.allocator.free(line);
                icon_lines.deinit(self.runtime.allocator);
            }

            for (entries.items) |entry| {
                try icon_lines.append(self.runtime.allocator, try self.iconCode(entry));
            }

            const joined = try self.textJoinLines(icon_lines.items);
            defer self.runtime.allocator.free(joined);
            const generated = try self.assetsModuleSource(joined);
            defer self.runtime.allocator.free(generated);

            if (self.runtime.projectFileContents(output_path)) |expected| {
                const normalized_generated = try normalizeLfAlloc(self.runtime.allocator, generated);
                defer self.runtime.allocator.free(normalized_generated);
                const normalized_expected = try normalizeLfAlloc(self.runtime.allocator, expected);
                defer self.runtime.allocator.free(normalized_expected);
                if (!std.mem.eql(u8, normalized_generated, normalized_expected)) return error.GeneratedAssetsMismatch;
            }

            try self.fileWriteText("./Generated/Assets.bn", generated);
            self.generated_icon_count = entries.items.len;
        }

        fn requireSupportedScript(self: *BuildHost) !void {
            const required = [_][]const u8{
                "Directory/entries",
                "File/read_text",
                "File/write_text",
                "Url/encode",
                "Text/join_lines",
                "List/retain",
                "List/sort_by",
                "List/map",
                "List/count",
                "Log/info",
                "Log/error",
                "Build/succeed",
                "Build/fail",
                "FLUSH",
                "FLUSHED",
            };
            for (required) |name| {
                if (std.mem.indexOf(u8, self.build_file, name) == null) {
                    self.unsupported_message = name;
                    return error.UnsupportedBuildScript;
                }
            }
        }

        fn directoryEntries(self: *BuildHost, path: []const u8) !std.ArrayList(DirectoryEntry) {
            const normalized = normalizeProjectPath(path) orelse {
                self.unsupported_message = "Directory/entries path escapes project VFS";
                return error.UnsupportedBuildScript;
            };
            if (!std.mem.eql(u8, normalized, "assets/icons")) {
                self.unsupported_message = "Directory/entries supports ./assets/icons for the v0 build host";
                return error.UnsupportedBuildScript;
            }

            var entries = std.ArrayList(DirectoryEntry).empty;
            errdefer entries.deinit(self.runtime.allocator);
            for (self.runtime.files, 0..) |file, index| {
                if (!isDirectIconSvg(file.path)) continue;
                const name = std.fs.path.basename(file.path);
                const dot = std.mem.lastIndexOfScalar(u8, name, '.');
                try entries.append(self.runtime.allocator, .{
                    .file_index = index,
                    .path = file.path,
                    .file_name = name,
                    .file_stem = if (dot) |offset| name[0..offset] else name,
                    .extension = if (dot) |offset| name[offset + 1 ..] else "",
                });
            }
            return entries;
        }

        fn listRetainExtension(_: *BuildHost, entries: *std.ArrayList(DirectoryEntry), extension: []const u8) void {
            var write_index: usize = 0;
            for (entries.items) |entry| {
                if (std.mem.eql(u8, entry.extension, extension)) {
                    entries.items[write_index] = entry;
                    write_index += 1;
                }
            }
            entries.shrinkRetainingCapacity(write_index);
        }

        fn listSortByPath(_: *BuildHost, entries: []DirectoryEntry) void {
            std.mem.sort(DirectoryEntry, entries, {}, directoryEntryPathLessThan);
        }

        fn iconCode(self: *BuildHost, entry: DirectoryEntry) ![]u8 {
            const source = try self.fileReadText(entry.path);
            const encoded = try self.urlEncode(std.mem.trimEnd(u8, source, "\r\n"));
            defer self.runtime.allocator.free(encoded);
            return try std.fmt.allocPrint(
                self.runtime.allocator,
                "{s}: data:image/svg+xml;utf8,{s}",
                .{ entry.file_stem, encoded },
            );
        }

        fn textJoinLines(self: *BuildHost, lines: []const []const u8) ![]u8 {
            var out = std.Io.Writer.Allocating.init(self.runtime.allocator);
            errdefer out.deinit();
            for (lines, 0..) |line, index| {
                if (index != 0) try out.writer.writeByte('\n');
                try out.writer.writeAll(line);
            }
            return try out.toOwnedSlice();
        }

        fn assetsModuleSource(self: *BuildHost, joined_icon_code: []const u8) ![]u8 {
            var out = std.Io.Writer.Allocating.init(self.runtime.allocator);
            errdefer out.deinit();
            const writer = &out.writer;
            try writer.writeAll(
                \\-- GENERATED CODE - DO NOT EDIT
                \\-- Generated by BUILD.bn from assets/icons/
                \\-- Generated at: 2025-01-01T00:00:00Z
                \\
                \\FUNCTION icon() {
                \\    [
                \\
            );
            var line_iter = std.mem.splitScalar(u8, joined_icon_code, '\n');
            var first = true;
            while (line_iter.next()) |line| {
                if (!first) try writer.writeByte('\n');
                first = false;
                const colon = std.mem.indexOfScalar(u8, line, ':') orelse {
                    self.unsupported_message = "List/map icon_code produced malformed output";
                    return error.UnsupportedBuildScript;
                };
                const stem = line[0..colon];
                const uri = std.mem.trim(u8, line[colon + 1 ..], " ");
                try writer.print(
                    \\        {s}: TEXT {{
                    \\            {s}
                    \\        }}
                    \\
                , .{ stem, uri });
            }
            try writer.writeAll(
                \\    ]
                \\}
                \\
            );
            return try out.toOwnedSlice();
        }

        fn fileReadText(self: *BuildHost, path: []const u8) ![]const u8 {
            const normalized = normalizeProjectPath(path) orelse {
                self.unsupported_message = "File/read_text path escapes project VFS";
                return error.UnsupportedBuildScript;
            };
            return self.runtime.projectFileContents(normalized) orelse {
                self.unsupported_message = "File/read_text path not found in project VFS";
                return error.UnsupportedBuildScript;
            };
        }

        fn fileWriteText(self: *BuildHost, path: []const u8, contents: []const u8) !void {
            const normalized = normalizeProjectPath(path) orelse {
                self.unsupported_message = "File/write_text path escapes project VFS";
                return error.UnsupportedBuildScript;
            };
            try self.runtime.writeProjectFile(normalized, contents, true);
        }

        fn urlEncode(self: *BuildHost, text: []const u8) ![]u8 {
            return percentEncode(self.runtime.allocator, text);
        }

        fn directoryEntryPathLessThan(_: void, lhs: DirectoryEntry, rhs: DirectoryEntry) bool {
            return std.mem.lessThan(u8, lhs.path, rhs.path);
        }

        fn normalizeProjectPath(path: []const u8) ?[]const u8 {
            var normalized = path;
            if (std.mem.startsWith(u8, normalized, "./")) normalized = normalized[2..];
            if (normalized.len == 0) return null;
            if (std.mem.startsWith(u8, normalized, "/")) return null;
            if (std.mem.indexOf(u8, normalized, "../") != null) return null;
            if (std.mem.endsWith(u8, normalized, "/..")) return null;
            return std.mem.trimEnd(u8, normalized, "/");
        }
    };

    fn isDirectIconSvg(path: []const u8) bool {
        const prefix = "assets/icons/";
        if (!std.mem.startsWith(u8, path, prefix)) return false;
        const rest = path[prefix.len..];
        if (rest.len == 0 or std.mem.indexOfScalar(u8, rest, '/') != null) return false;
        return std.mem.endsWith(u8, rest, ".svg");
    }

    fn percentEncode(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();
        const writer = &out.writer;
        const hex = "0123456789ABCDEF";
        for (text) |byte| {
            const allowed = (byte >= 'a' and byte <= 'z') or
                (byte >= 'A' and byte <= 'Z') or
                (byte >= '0' and byte <= '9') or
                byte == '-' or byte == '_' or byte == '.' or byte == '~' or
                byte == '/';
            if (allowed) {
                try writer.writeByte(byte);
            } else {
                try writer.writeByte('%');
                try writer.writeByte(hex[byte >> 4]);
                try writer.writeByte(hex[byte & 0x0f]);
            }
        }
        return try out.toOwnedSlice();
    }

    fn normalizeLfAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();
        const writer = &out.writer;
        var index: usize = 0;
        while (index < text.len) : (index += 1) {
            if (text[index] == '\r') {
                if (index + 1 < text.len and text[index + 1] == '\n') continue;
                try writer.writeByte('\n');
            } else {
                try writer.writeByte(text[index]);
            }
        }
        return try out.toOwnedSlice();
    }

    fn combinedModuleSourceAlloc(self: *BoonRuntimeHost, entry_source: []const u8) ![]u8 {
        var modules = std.ArrayList(ModuleInfo).empty;
        defer {
            for (modules.items) |module| self.allocator.free(module.functions);
            modules.deinit(self.allocator);
        }

        for (self.files) |file| {
            if (!isImportableModule(file, self.entry_file)) continue;
            const module_name = moduleNameFromPath(file.path);
            for (modules.items) |existing| {
                if (std.mem.eql(u8, existing.name, module_name)) {
                    const message = try std.fmt.allocPrint(
                        self.allocator,
                        "BoonRuntimeHost module basename collision for {s}: {s} and {s}",
                        .{ module_name, existing.path, file.path },
                    );
                    self.diagnostics = try self.allocator.dupe(Diagnostic, &.{
                        .{ .severity = .err, .file_path = file.path, .message = message },
                    });
                    return error.ModuleNameCollision;
                }
            }
            try modules.append(self.allocator, .{
                .name = module_name,
                .path = file.path,
                .source = file.contents,
                .functions = try collectFunctionNames(self.allocator, file.contents),
            });
            const parsed = try parser.parseAlloc(self.allocator, file.contents);
            switch (parsed) {
                .ok => |document| {
                    var cleanup = document;
                    cleanup.deinit();
                },
                .err => |failure| {
                    _ = try self.diagnosticFromHeadless(failure);
                    return error.ModuleParseFailed;
                },
            }
        }

        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();
        const writer = &out.writer;
        for (modules.items) |module| {
            if (!std.mem.eql(u8, module.name, "Assets")) continue;
            const rewritten = try rewriteModuleSourceAlloc(self.allocator, module.source, modules.items, module);
            defer self.allocator.free(rewritten);
            try writer.writeAll(rewritten);
            try writer.writeAll("\n\n");
        }
        const rewritten_entry = try rewriteEntrySourceAlloc(self.allocator, entry_source, modules.items);
        defer self.allocator.free(rewritten_entry);
        try writer.writeAll(rewritten_entry);
        return try out.toOwnedSlice();
    }

    fn isImportableModule(file: ProjectFile, entry_file: []const u8) bool {
        if (!std.mem.endsWith(u8, file.path, ".bn")) return false;
        if (std.mem.eql(u8, file.path, entry_file)) return false;
        if (std.mem.eql(u8, file.path, "BUILD.bn")) return false;
        return true;
    }

    fn moduleNameFromPath(path: []const u8) []const u8 {
        const name = std.fs.path.basename(path);
        return if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| name[0..dot] else name;
    }

    fn collectFunctionNames(allocator: std.mem.Allocator, source: []const u8) ![][]const u8 {
        var functions = std.ArrayList([]const u8).empty;
        errdefer functions.deinit(allocator);
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, source, cursor, "FUNCTION ")) |function_start| {
            const name_start = function_start + "FUNCTION ".len;
            var name_end = name_start;
            while (name_end < source.len and isIdent(source[name_end])) : (name_end += 1) {}
            if (name_end > name_start) try functions.append(allocator, source[name_start..name_end]);
            cursor = name_end;
        }
        return try functions.toOwnedSlice(allocator);
    }

    fn rewriteModuleSourceAlloc(
        allocator: std.mem.Allocator,
        source: []const u8,
        modules: []const ModuleInfo,
        current: ModuleInfo,
    ) ![]u8 {
        return rewriteSourceAlloc(allocator, source, modules, current);
    }

    fn rewriteEntrySourceAlloc(
        allocator: std.mem.Allocator,
        source: []const u8,
        modules: []const ModuleInfo,
    ) ![]u8 {
        return rewriteSourceAlloc(allocator, source, modules, null);
    }

    fn rewriteSourceAlloc(
        allocator: std.mem.Allocator,
        source: []const u8,
        modules: []const ModuleInfo,
        current: ?ModuleInfo,
    ) ![]u8 {
        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();
        const writer = &out.writer;
        var index: usize = 0;
        while (index < source.len) {
            if (try rewriteModulePathAt(writer, source, &index, modules)) continue;
            if (current) |module| {
                if (try rewriteLocalFunctionAt(writer, source, &index, module)) continue;
            }
            try writer.writeByte(source[index]);
            index += 1;
        }
        return try out.toOwnedSlice();
    }

    fn rewriteModulePathAt(
        writer: *std.Io.Writer,
        source: []const u8,
        index: *usize,
        modules: []const ModuleInfo,
    ) !bool {
        for (modules) |module| {
            if (std.mem.eql(u8, module.name, "Theme")) continue;
            if (!startsWithToken(source, index.*, module.name)) continue;
            var cursor = index.* + module.name.len;
            if (cursor >= source.len or source[cursor] != '/') continue;
            cursor += 1;
            for (module.functions) |function| {
                if (std.mem.eql(u8, module.name, "Theme") and
                    (std.mem.eql(u8, function, "geometry") or std.mem.eql(u8, function, "lights")))
                {
                    continue;
                }
                if (!startsWithToken(source, cursor, function)) continue;
                const end = cursor + function.len;
                if (end < source.len and isIdent(source[end])) continue;
                try writer.print("{s}__{s}", .{ module.name, function });
                index.* = end;
                return true;
            }
        }
        return false;
    }

    fn rewriteLocalFunctionAt(
        writer: *std.Io.Writer,
        source: []const u8,
        index: *usize,
        module: ModuleInfo,
    ) !bool {
        if (index.* != 0 and isIdent(source[index.* - 1])) return false;
        for (module.functions) |function| {
            if (!startsWithToken(source, index.*, function)) continue;
            const end = index.* + function.len;
            if (end >= source.len or source[end] != '(') continue;
            try writer.print("{s}__{s}", .{ module.name, function });
            index.* = end;
            return true;
        }
        return false;
    }

    fn startsWithToken(source: []const u8, index: usize, token: []const u8) bool {
        if (index + token.len > source.len) return false;
        if (!std.mem.eql(u8, source[index .. index + token.len], token)) return false;
        if (index != 0 and isIdent(source[index - 1])) return false;
        return true;
    }

    fn isIdent(byte: u8) bool {
        return (byte >= 'a' and byte <= 'z') or
            (byte >= 'A' and byte <= 'Z') or
            (byte >= '0' and byte <= '9') or
            byte == '_';
    }

    fn importableModuleCount(self: *const BoonRuntimeHost) usize {
        var count: usize = 0;
        for (self.files) |file| {
            if (!isImportableModule(file, self.entry_file)) continue;
            count += 1;
        }
        return count;
    }

    fn currentVirtualTime(self: *const BoonRuntimeHost) u64 {
        return switch (self.time.*) {
            .real => 0,
            .virtual => |clock| clock.now_ms,
        };
    }

    fn stateFilePathAlloc(self: *BoonRuntimeHost, project_name: []const u8) ![]u8 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(project_name);
        const digest = hasher.final();
        return try std.fmt.allocPrint(self.allocator, "zig-out/boon-runtime-state/{x}.json", .{digest});
    }

    fn clearRuntime(self: *BoonRuntimeHost) void {
        if (self.session) |*session| session.deinit();
        self.session = null;
        if (self.compiled) |*compiled| compiled.deinit();
        self.compiled = null;
        self.clearSnapshotValues();
        self.clearSnapshotEvents();
        self.clearSnapshotTimers();
    }

    fn clearProject(self: *BoonRuntimeHost) void {
        self.clearBuildSummary();
        for (self.files) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.contents);
        }
        self.allocator.free(self.files);
        self.files = &.{};
        self.allocator.free(self.project_name);
        self.project_name = &.{};
        self.allocator.free(self.entry_file);
        self.entry_file = &.{};
        self.project_loaded = false;
        self.has_build_file = false;
    }

    fn clearBuildSummary(self: *BoonRuntimeHost) void {
        for (self.build_generated_files) |path| self.allocator.free(path);
        self.allocator.free(self.build_generated_files);
        self.build_generated_files = &.{};
        for (self.build_logs) |log| self.allocator.free(log.message);
        self.allocator.free(self.build_logs);
        self.build_logs = &.{};
    }

    fn clearSnapshotValues(self: *BoonRuntimeHost) void {
        for (self.snapshot_values) |value| {
            self.freeRuntimeValue(value);
        }
        self.allocator.free(self.snapshot_values);
        self.snapshot_values = &.{};
    }

    fn freeRuntimeValue(self: *BoonRuntimeHost, value: RuntimeValue) void {
        switch (value) {
            .text => |text| self.allocator.free(text),
            .symbol => |symbol| self.allocator.free(symbol),
            .list => |items| self.allocator.free(items),
            .record => |fields| {
                for (fields) |field| self.allocator.free(field.name);
                self.allocator.free(fields);
            },
            .element => |element| {
                self.allocator.free(element.kind);
                for (element.args) |field| self.allocator.free(field.name);
                self.allocator.free(element.args);
                self.allocator.free(element.stable_id);
            },
            else => {},
        }
    }

    fn clearSnapshotEvents(self: *BoonRuntimeHost) void {
        self.allocator.free(self.snapshot_events);
        self.snapshot_events = &.{};
    }

    fn clearSnapshotTimers(self: *BoonRuntimeHost) void {
        self.allocator.free(self.snapshot_timers);
        self.snapshot_timers = &.{};
    }
};

fn previewKeyName(key: Key) []const u8 {
    return switch (key) {
        .unknown => "Unknown",
        .enter => "Enter",
        .escape => "Escape",
        .tab => "Tab",
        .backspace => "Backspace",
        .delete => "Delete",
        .arrow_left => "ArrowLeft",
        .arrow_right => "ArrowRight",
        .arrow_up => "ArrowUp",
        .arrow_down => "ArrowDown",
    };
}

const SnapshotBuilder = struct {
    const ScopedKey = struct {
        node_id: u32,
        scope_id: u64,
    };

    allocator: std.mem.Allocator,
    session: *headless.Session,
    values: std.ArrayList(RuntimeValue),
    scoped_values: std.AutoHashMapUnmanaged(ScopedKey, ValueId) = .empty,

    fn init(allocator: std.mem.Allocator, session: *headless.Session) SnapshotBuilder {
        return .{
            .allocator = allocator,
            .session = session,
            .values = std.ArrayList(RuntimeValue).empty,
        };
    }

    fn finish(self: *SnapshotBuilder) ![]RuntimeValue {
        return try self.values.toOwnedSlice(self.allocator);
    }

    fn deinit(self: *SnapshotBuilder) void {
        self.scoped_values.deinit(self.allocator);
    }

    fn appendValue(self: *SnapshotBuilder, value: headless.Value) anyerror!ValueId {
        if (value == .scoped_node) {
            const deferred = value.scoped_node;
            const key = ScopedKey{
                .node_id = deferred.node_id,
                .scope_id = self.session.semanticScopeIdentity(deferred.scope),
            };
            if (self.scoped_values.get(key)) |cached_id| return cached_id;
            const converted = try self.convertValue(try self.session.evalSemanticNode(deferred.node_id, deferred.scope));
            const id: ValueId = @intCast(self.values.items.len);
            try self.values.append(self.allocator, converted);
            try self.scoped_values.put(self.allocator, key, id);
            return id;
        }
        const converted = try self.convertValue(value);
        const id: ValueId = @intCast(self.values.items.len);
        try self.values.append(self.allocator, converted);
        return id;
    }

    fn convertValue(self: *SnapshotBuilder, value: headless.Value) anyerror!RuntimeValue {
        return switch (value) {
            .none => .none,
            .number => |number| .{ .number = number },
            .duration_ms => |duration_ms| .{ .number = @floatFromInt(duration_ms) },
            .text => |text| .{ .text = try self.allocator.dupe(u8, text) },
            .symbol => |symbol| if (std.mem.eql(u8, symbol, "True"))
                .{ .bool = true }
            else if (std.mem.eql(u8, symbol, "False"))
                .{ .bool = false }
            else
                .{ .symbol = try self.allocator.dupe(u8, symbol) },
            .list => |items| .{ .list = try self.appendValueList(items) },
            .record => |fields| .{ .record = try self.appendRecordFields(fields) },
            .binding_ref => |binding_id| try self.convertValue(try self.session.semanticBindingValue(binding_id)),
            .document => |document| try self.elementValue("document", &.{.{ .name = "root", .value = document.root }}),
            .terminal => |terminal| try self.elementValue("terminal", &.{.{ .name = "root", .value = terminal.root }}),
            .stripe => |stripe| blk: {
                const direction: headless.Value = .{ .text = switch (stripe.direction) {
                    .row => "row",
                    .column => "column",
                } };
                break :blk try self.elementValue("stripe", &.{
                    .{ .name = "items", .value = .{ .list = stripe.items } },
                    .{ .name = "direction", .value = direction },
                });
            },
            .label => |label| try self.elementValue("label", &.{.{ .name = "label", .value = label.label }}),
            .container => |container| try self.elementValue("container", &.{
                .{ .name = "child", .value = container.child },
                .{ .name = "click_link", .value = if (container.click_link) |link| .{ .number = @floatFromInt(link) } else .none },
                .{ .name = "width", .value = .{ .number = @floatFromInt(container.terminal_width) } },
                .{ .name = "height", .value = .{ .number = @floatFromInt(container.terminal_height) } },
            }),
            .checkbox => |checkbox| try self.elementValue("checkbox", &.{
                .{ .name = "icon", .value = checkbox.icon },
                .{ .name = "label", .value = checkbox.label },
                .{ .name = "checked", .value = checkbox.checked },
            }),
            .button => |button| try self.elementValue("button", &.{
                .{ .name = "label", .value = button.label },
                .{ .name = "disabled", .value = .{ .symbol = if (button.disabled) "True" else "False" } },
                .{ .name = "outlined", .value = .{ .symbol = if (button.outlined) "True" else "False" } },
                .{ .name = "press_link", .value = if (button.press_link) |link| .{ .number = @floatFromInt(link) } else .none },
            }),
            .text_input => |input| try self.elementValue("text_input", &.{
                .{ .name = "text", .value = input.text },
                .{ .name = "placeholder", .value = input.placeholder },
                .{ .name = "focused", .value = .{ .symbol = if (input.focused) "True" else "False" } },
                .{ .name = "disabled", .value = .{ .symbol = if (input.disabled) "True" else "False" } },
                .{ .name = "change_link", .value = if (input.change_link) |link| .{ .number = @floatFromInt(link) } else .none },
                .{ .name = "key_link", .value = if (input.key_link) |link| .{ .number = @floatFromInt(link) } else .none },
                .{ .name = "blur_link", .value = if (input.blur_link) |link| .{ .number = @floatFromInt(link) } else .none },
                .{ .name = "focus_link", .value = if (input.focus_link) |link| .{ .number = @floatFromInt(link) } else .none },
            }),
            .select => |select| try self.elementValue("select", &.{.{ .name = "selected", .value = select.selected }}),
            .slider => try self.elementValue("slider", &.{}),
            .scoped_node => unreachable,
            .link => |link| .{ .symbol = try std.fmt.allocPrint(self.allocator, "link:{d}", .{link}) },
            .scoped_link => |scoped| .{ .symbol = try std.fmt.allocPrint(
                self.allocator,
                "link:{d}@{d}",
                .{ scoped.link, if (scoped.scope) |scope| scope.id else @as(u64, 0) },
            ) },
        };
    }

    fn appendValueList(self: *SnapshotBuilder, items: []const headless.Value) ![]ValueId {
        const ids = try self.allocator.alloc(ValueId, items.len);
        for (items, 0..) |item, index| ids[index] = try self.appendValue(item);
        return ids;
    }

    fn appendRecordFields(self: *SnapshotBuilder, fields: []const headless.RecordField) ![]RecordField {
        const out = try self.allocator.alloc(RecordField, fields.len);
        for (fields, 0..) |field, index| {
            out[index] = .{
                .name = try self.allocator.dupe(u8, field.name),
                .value = try self.appendValue(field.value),
            };
        }
        return out;
    }

    fn elementValue(self: *SnapshotBuilder, kind: []const u8, fields: []const headless.RecordField) !RuntimeValue {
        return .{ .element = .{
            .kind = try self.allocator.dupe(u8, kind),
            .args = try self.appendRecordFields(fields),
            .stable_id = try self.allocator.dupe(u8, ""),
        } };
    }

    fn appendElementIds(self: *SnapshotBuilder, kind: []const u8, fields: []const RecordField) !ValueId {
        const id: ValueId = @intCast(self.values.items.len);
        const args = try self.allocator.alloc(RecordField, fields.len);
        for (fields, 0..) |field, index| {
            args[index] = .{
                .name = try self.allocator.dupe(u8, field.name),
                .value = field.value,
            };
        }
        try self.values.append(self.allocator, .{ .element = .{
            .kind = try self.allocator.dupe(u8, kind),
            .args = args,
            .stable_id = try self.allocator.dupe(u8, ""),
        } });
        return id;
    }
};

fn ensureStateDir() !void {
    _ = c_mkdir("zig-out", 0o777);
    _ = c_mkdir("zig-out/boon-runtime-state", 0o777);
}

fn monotonicNanoseconds() u64 {
    if (@import("builtin").os.tag == .linux) {
        const linux = std.os.linux;
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
    }
    return 0;
}

fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern fn unlink(path: [*:0]const u8) c_int;

const c_mkdir = mkdir;
const c_unlink = unlink;

test "BoonRuntimeHost bridge exposes explicit unsupported diagnostics" {
    const testing = std.testing;

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
    var persist = PersistStore{
        .ptr = &persist_ctx,
        .read = PersistCtx.read,
        .write = PersistCtx.write,
        .deletePrefix = PersistCtx.deletePrefix,
    };
    var route = RouteStore{
        .ptr = &route_ctx,
        .current = RouteCtx.current,
        .goTo = RouteCtx.goTo,
    };
    var clock = VirtualClock{};
    var time = TimeSource{ .virtual = &clock };
    var host = try BoonRuntimeHost.init(testing.allocator, &persist, &route, &time);
    defer host.deinit();

    const result = try host.compileEntry();
    switch (result) {
        .diagnostics => |diagnostics| {
            try testing.expectEqual(@as(usize, 1), diagnostics.len);
            try testing.expectEqual(.err, diagnostics[0].severity);
        },
        else => return error.ExpectedDiagnostics,
    }
}

test "BoonRuntimeHost dispatches visible click bindings after snapshot collection" {
    const testing = std.testing;
    const allocator = std.heap.smp_allocator;

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
    var persist = PersistStore{
        .ptr = &persist_ctx,
        .read = PersistCtx.read,
        .write = PersistCtx.write,
        .deletePrefix = PersistCtx.deletePrefix,
    };
    var route = RouteStore{
        .ptr = &route_ctx,
        .current = RouteCtx.current,
        .goTo = RouteCtx.goTo,
    };
    var clock = VirtualClock{};
    var time = TimeSource{ .virtual = &clock };
    var host = try BoonRuntimeHost.init(allocator, &persist, &route, &time);
    defer host.deinit();

    const upstream_source = try std.Io.Dir.cwd().readFileAlloc(testing.io, "examples/upstream/filter_checkbox_bug/filter_checkbox_bug.bn", allocator, .limited(1024 * 1024));
    defer allocator.free(upstream_source);
    const source = try std.mem.replaceOwned(u8, allocator, upstream_source, "SOURCE", "LINK");
    defer allocator.free(source);
    try host.loadProject(.{
        .name = "filter_checkbox_bug",
        .entry_file = "filter_checkbox_bug.bn",
        .files = &.{.{ .path = "filter_checkbox_bug.bn", .contents = source }},
    });
    try host.clearState("filter_checkbox_bug");

    _ = try host.start();
    const output = try host.dispatch(.{ .click = 1 });
    const rendered = renderedTextFromOutput(output) orelse return error.MissingRenderedText;
    try testing.expect(std.mem.indexOf(u8, rendered, "Filter:Active") != null);
}

test "BoonRuntimeHost dispatches SVG click payload by control ref" {
    const testing = std.testing;
    const allocator = std.heap.c_allocator;

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
    var persist = PersistStore{ .ptr = &persist_ctx, .read = PersistCtx.read, .write = PersistCtx.write, .deletePrefix = PersistCtx.deletePrefix };
    var route = RouteStore{ .ptr = &route_ctx, .current = RouteCtx.current, .goTo = RouteCtx.goTo };
    var clock = VirtualClock{};
    var time = TimeSource{ .virtual = &clock };
    var host = try BoonRuntimeHost.init(allocator, &persist, &route, &time);
    defer host.deinit();

    const source = try std.Io.Dir.cwd().readFileAlloc(testing.io, "../raybox-zig/examples/upstream/circle_drawer/circle_drawer.bn", allocator, .limited(1024 * 1024));
    defer allocator.free(source);
    try host.loadProject(.{
        .name = "circle_drawer",
        .entry_file = "circle_drawer.bn",
        .files = &.{.{ .path = "circle_drawer.bn", .contents = source }},
    });
    try host.clearState("circle_drawer");

    const initial = try host.start();
    const handle = try svgClickHandleFromOutput(initial);
    const updated = try host.dispatch(.{ .svg_click_ref = .{ .handle = handle, .x = 123, .y = 45 } });
    const rendered = renderedTextFromOutput(updated) orelse return error.MissingRenderedText;
    try testing.expect(std.mem.indexOf(u8, rendered, "Circles:1") != null);
}

fn svgClickHandleFromOutput(output: RuntimeOutput) !ControlHandle {
    const document = switch (output) {
        .document => |document| document,
        else => return error.MissingDocumentRoot,
    };
    for (document.values) |value| {
        const element = switch (value) {
            .element => |element| element,
            else => continue,
        };
        if (!std.mem.eql(u8, element.kind, "container")) continue;
        const link = elementNumberField(document.values, element, "click_link") orelse continue;
        const width = elementNumberField(document.values, element, "width") orelse 0;
        const height = elementNumberField(document.values, element, "height") orelse 0;
        if (width <= 0 or height <= 0) continue;
        const link_id: LinkId = @intFromFloat(link);
        for (document.events) |event| {
            if (event.id == link_id and event.handle != null) return event.handle.?;
        }
    }
    return error.MissingSvgClickHandle;
}

fn elementNumberField(values: []const RuntimeValue, element: ElementNode, name: []const u8) ?f64 {
    for (element.args) |field| {
        if (!std.mem.eql(u8, field.name, name)) continue;
        if (field.value >= values.len) return null;
        return switch (values[field.value]) {
            .number => |number| number,
            else => null,
        };
    }
    return null;
}

test "BoonRuntimeHost dispatches terminal key bindings through terminal contract" {
    const testing = std.testing;
    const allocator = std.heap.c_allocator;

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
    var persist = PersistStore{
        .ptr = &persist_ctx,
        .read = PersistCtx.read,
        .write = PersistCtx.write,
        .deletePrefix = PersistCtx.deletePrefix,
    };
    var route = RouteStore{
        .ptr = &route_ctx,
        .current = RouteCtx.current,
        .goTo = RouteCtx.goTo,
    };
    var clock = VirtualClock{};
    var time = TimeSource{ .virtual = &clock };
    var host = try BoonRuntimeHost.init(allocator, &persist, &route, &time);
    defer host.deinit();

    const source = @embedFile("../examples/terminal/pong/pong.bn");
    try host.loadProject(.{
        .name = "pong",
        .entry_file = "pong.bn",
        .files = &.{.{ .path = "pong.bn", .contents = source }},
    });
    try host.clearState("pong");

    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => return error.UnexpectedDiagnostics,
    }

    const initial = try host.start();
    const initial_rendered = renderedTextFromOutput(initial) orelse return error.MissingRenderedText;
    try testing.expect(std.mem.indexOf(u8, initial_rendered, "Press Enter") != null);

    const updated = try host.dispatch(.{ .terminal_key = "Enter" });
    const rendered = renderedTextFromOutput(updated) orelse return error.MissingRenderedText;
    try testing.expect(std.mem.indexOf(u8, rendered, "Rally") != null);
}

test "BoonRuntimeHost semantic snapshot reflects select-driven input disabled state" {
    const testing = std.testing;
    const allocator = std.heap.c_allocator;

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
    var persist = PersistStore{
        .ptr = &persist_ctx,
        .read = PersistCtx.read,
        .write = PersistCtx.write,
        .deletePrefix = PersistCtx.deletePrefix,
    };
    var route = RouteStore{
        .ptr = &route_ctx,
        .current = RouteCtx.current,
        .goTo = RouteCtx.goTo,
    };
    var clock = VirtualClock{};
    var time = TimeSource{ .virtual = &clock };
    var host = try BoonRuntimeHost.init(allocator, &persist, &route, &time);
    defer host.deinit();

    const upstream_source = try std.Io.Dir.cwd().readFileAlloc(testing.io, "examples/upstream/flight_booker/flight_booker.bn", allocator, .limited(1024 * 1024));
    defer allocator.free(upstream_source);
    const source = try std.mem.replaceOwned(u8, allocator, upstream_source, "SOURCE", "LINK");
    defer allocator.free(source);
    try host.loadProject(.{
        .name = "flight_booker",
        .entry_file = "flight_booker.bn",
        .files = &.{.{ .path = "flight_booker.bn", .contents = source }},
    });
    try host.clearState("flight_booker");

    switch (try host.runBuildFile()) {
        .not_present, .ok => {},
        .diagnostics => return error.UnexpectedDiagnostics,
    }
    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => return error.UnexpectedDiagnostics,
    }
    const initial = try host.start();
    try testing.expectEqual(true, nthTextInputDisabled(initial, 1) orelse return error.MissingTextInput);

    _ = try host.dispatch(.{ .click = 0 });
    const updated = try host.dispatch(.{ .select_change = .{ .link = 0, .value = "return" } });
    try testing.expectEqual(false, nthTextInputDisabled(updated, 1) orelse return error.MissingTextInput);
}

fn renderedTextFromOutput(output: RuntimeOutput) ?[]const u8 {
    const document = switch (output) {
        .document => |document| document,
        else => return null,
    };
    const root = document.values[document.root];
    const element = switch (root) {
        .element => |element| element,
        else => return null,
    };
    for (element.args) |field| {
        if (!std.mem.eql(u8, field.name, "rendered_text")) continue;
        return switch (document.values[field.value]) {
            .text => |text| text,
            else => null,
        };
    }
    return null;
}

fn nthTextInputDisabled(output: RuntimeOutput, wanted_index: usize) ?bool {
    const document = switch (output) {
        .document => |document| document,
        else => return null,
    };
    var index: usize = 0;
    return nthTextInputDisabledInValue(document.values, document.root, wanted_index, &index);
}

fn nthTextInputDisabledInValue(values: []const RuntimeValue, value_id: ValueId, wanted_index: usize, index: *usize) ?bool {
    if (value_id >= values.len) return null;
    switch (values[value_id]) {
        .list => |items| for (items) |item| {
            if (nthTextInputDisabledInValue(values, item, wanted_index, index)) |disabled| return disabled;
        },
        .record => |fields| for (fields) |field| {
            if (nthTextInputDisabledInValue(values, field.value, wanted_index, index)) |disabled| return disabled;
        },
        .element => |element| {
            if (std.mem.eql(u8, element.kind, "text_input")) {
                if (index.* == wanted_index) return elementBoolFieldForTest(values, element, "disabled");
                index.* += 1;
            }
            for (element.args) |field| {
                if (nthTextInputDisabledInValue(values, field.value, wanted_index, index)) |disabled| return disabled;
            }
        },
        else => {},
    }
    return null;
}

fn elementBoolFieldForTest(values: []const RuntimeValue, element: ElementNode, name: []const u8) bool {
    for (element.args) |field| {
        if (!std.mem.eql(u8, field.name, name) or field.value >= values.len) continue;
        return switch (values[field.value]) {
            .bool => |value| value,
            .symbol => |value| std.mem.eql(u8, value, "True") or std.mem.eql(u8, value, "true"),
            .text => |value| std.mem.eql(u8, value, "True") or std.mem.eql(u8, value, "true"),
            else => false,
        };
    }
    return false;
}
