const std = @import("std");

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
        self.clearDiagnostics();
    }

    pub fn loadProject(self: *BoonRuntimeHost, project: Project) !void {
        self.clearDiagnostics();
        self.project_loaded = true;
        self.has_build_file = false;
        for (project.files) |file| {
            if (std.mem.eql(u8, file.path, "BUILD.bn")) {
                self.has_build_file = true;
                break;
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
        self.clearDiagnostics();
        if (!self.project_loaded) return .{ .diagnostics = try self.unsupported("BoonRuntimeHost.loadProject must be called before compileEntry") };
        return .{ .diagnostics = try self.unsupported("BoonRuntimeHost compileEntry is not implemented yet") };
    }

    pub fn start(self: *BoonRuntimeHost) !RuntimeOutput {
        self.clearDiagnostics();
        return .{ .diagnostics = try self.unsupported("BoonRuntimeHost start is not implemented yet") };
    }

    pub fn dispatch(self: *BoonRuntimeHost, event: PreviewEvent) !RuntimeOutput {
        _ = event;
        self.clearDiagnostics();
        return .{ .diagnostics = try self.unsupported("BoonRuntimeHost dispatch is not implemented yet") };
    }

    pub fn tick(self: *BoonRuntimeHost, now_ms: u64) !RuntimeOutput {
        _ = now_ms;
        self.clearDiagnostics();
        return .{ .diagnostics = try self.unsupported("BoonRuntimeHost tick is not implemented yet") };
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
