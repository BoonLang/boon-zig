const std = @import("std");
const diag = @import("diag.zig");
const headless = @import("headless.zig");

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

pub const EventBinding = struct {
    id: LinkId,
    source_value: ValueId,
    event_name: []const u8,
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
    double_click: LinkId,
    hover: struct { link: LinkId, hovered: bool },
    change_text: struct { link: LinkId, text: []const u8 },
    key_down: struct { link: LinkId, key: Key, text: []const u8 },
    blur: LinkId,
    focus: LinkId,
    checkbox_change: struct { link: LinkId, checked: bool },
    select_change: struct { link: LinkId, value: []const u8 },
    slider_change: struct { link: LinkId, value: f64 },
    svg_click: struct { link: LinkId, x: f32, y: f32 },
};

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
    diagnostics: []Diagnostic = &.{},

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
    }

    pub fn loadProject(self: *BoonRuntimeHost, project: Project) !void {
        self.clearRuntime();
        self.clearProject();
        self.clearDiagnostics();
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
        if (!self.project_loaded) return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.loadProject must be called before runBuildFile") };
        if (!self.has_build_file) return .not_present;
        return .{ .diagnostics = try self.unsupported("BoonRuntimeHost BUILD.bn execution is not implemented yet") };
    }

    pub fn compileEntry(self: *BoonRuntimeHost) !CompileResult {
        self.clearRuntime();
        self.clearDiagnostics();
        if (!self.project_loaded) return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.loadProject must be called before compileEntry") };
        if (self.importableModuleCount() != 0) {
            return .{ .diagnostics = try self.unsupported("BoonRuntimeHost public module-resolution bridge is not implemented yet") };
        }
        const entry = self.entryContents() orelse {
            return .{ .diagnostics = try self.unsupported("BoonRuntimeHost project entry file was not found") };
        };
        const outcome = try headless.compileAlloc(self.allocator, entry);
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
        self.clearDiagnostics();
        if (self.compiled == null) {
            const compiled = try self.compileEntry();
            switch (compiled) {
                .ok => {},
                .diagnostics => |diagnostics| return .{ .diagnostics = diagnostics },
            }
        }
        if (self.session) |*old_session| old_session.deinit();
        self.session = null;
        const compiled = self.compiled orelse return .{ .diagnostics = try self.unsupported("BoonRuntimeHost compileEntry did not produce a compiled project") };
        self.compiled = null;
        const outcome = try headless.runCompiledAlloc(self.allocator, compiled, .{
            .virtual_time_ms = self.currentVirtualTime(),
        });
        switch (outcome) {
            .ok => |session| {
                self.session = session;
                return try self.snapshotOutput();
            },
            .err => |failure| return .{ .diagnostics = try self.diagnosticFromHeadless(failure) },
        }
    }

    pub fn dispatch(self: *BoonRuntimeHost, event: PreviewEvent) !RuntimeOutput {
        self.clearDiagnostics();
        var session = if (self.session) |*session| session else return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.start must be called before dispatch") };
        switch (event) {
            .press, .click => |link| try session.triggerLink(@intCast(link)),
            .double_click => |link| try session.triggerLink(@intCast(link)),
            .hover => |payload| {
                _ = payload.hovered;
                try session.triggerLink(@intCast(payload.link));
            },
            .change_text => |payload| try session.triggerLink(@intCast(payload.link)),
            .key_down => |payload| try session.triggerLink(@intCast(payload.link)),
            .blur => |link| try session.triggerLink(@intCast(link)),
            .focus => |link| try session.triggerLink(@intCast(link)),
            .checkbox_change => |payload| {
                _ = payload.checked;
                try session.triggerLink(@intCast(payload.link));
            },
            .select_change => |payload| try session.triggerLink(@intCast(payload.link)),
            .slider_change => |payload| try session.triggerLink(@intCast(payload.link)),
            .svg_click => |payload| try session.triggerLink(@intCast(payload.link)),
        }
        return try self.snapshotOutput();
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
        const rendered = try session.snapshotAlloc(self.allocator);
        defer self.allocator.free(rendered);
        self.clearSnapshotValues();
        self.snapshot_values = try self.allocator.alloc(RuntimeValue, 1);
        self.snapshot_values[0] = .{ .text = try self.allocator.dupe(u8, rendered) };
        const document = DocumentSnapshot{
            .revision = self.compiled_revision,
            .root = 0,
            .values = self.snapshot_values,
            .route = self.route.current(self.route.ptr),
        };
        return .{ .document = document };
    }

    fn entryContents(self: *const BoonRuntimeHost) ?[]const u8 {
        for (self.files) |file| {
            if (std.mem.eql(u8, file.path, self.entry_file)) return file.contents;
        }
        return null;
    }

    fn importableModuleCount(self: *const BoonRuntimeHost) usize {
        var count: usize = 0;
        for (self.files) |file| {
            if (!std.mem.endsWith(u8, file.path, ".bn")) continue;
            if (std.mem.eql(u8, file.path, self.entry_file)) continue;
            if (std.mem.eql(u8, file.path, "BUILD.bn")) continue;
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

    fn clearRuntime(self: *BoonRuntimeHost) void {
        if (self.session) |*session| session.deinit();
        self.session = null;
        if (self.compiled) |*compiled| compiled.deinit();
        self.compiled = null;
        self.clearSnapshotValues();
    }

    fn clearProject(self: *BoonRuntimeHost) void {
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

    fn clearSnapshotValues(self: *BoonRuntimeHost) void {
        for (self.snapshot_values) |value| {
            switch (value) {
                .text => |text| self.allocator.free(text),
                else => {},
            }
        }
        self.allocator.free(self.snapshot_values);
        self.snapshot_values = &.{};
    }
};

test "BoonRuntimeHost bridge exposes explicit unsupported diagnostics" {
    const testing = std.testing;

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
