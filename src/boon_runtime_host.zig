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
    snapshot_events: []EventBinding = &.{},
    diagnostics: []Diagnostic = &.{},
    build_generated_files: [][]const u8 = &.{},
    build_logs: []Diagnostic = &.{},

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

        if (std.mem.indexOf(u8, build_file, "Directory/entries") == null or
            std.mem.indexOf(u8, build_file, "File/write_text") == null or
            std.mem.indexOf(u8, build_file, "FUNCTION icon_code") == null)
        {
            return .{ .diagnostics = try self.unsupported("BoonRuntimeHost BUILD.bn host supports the pinned icon asset build script only") };
        }

        const generated = self.generateIconAssetsFile() catch |err| switch (err) {
            error.NoIconSvgFiles => return .{ .diagnostics = try self.unsupported("BoonRuntimeHost BUILD.bn found no SVG files under ./assets/icons") },
            else => return err,
        };
        defer self.allocator.free(generated);

        const output_path = "Generated/Assets.bn";
        if (self.projectFileContents(output_path)) |expected| {
            const normalized_generated = try normalizeLfAlloc(self.allocator, generated);
            defer self.allocator.free(normalized_generated);
            const normalized_expected = try normalizeLfAlloc(self.allocator, expected);
            defer self.allocator.free(normalized_expected);
            if (!std.mem.eql(u8, normalized_generated, normalized_expected)) {
                return .{ .diagnostics = try self.unsupported("BoonRuntimeHost BUILD.bn generated ./Generated/Assets.bn, but it does not match the pinned checked-in file") };
            }
        }

        try self.writeProjectFile(output_path, generated, true);
        self.build_generated_files = try self.allocator.alloc([]const u8, 1);
        self.build_generated_files[0] = try self.allocator.dupe(u8, output_path);
        self.build_logs = try self.allocator.alloc(Diagnostic, 1);
        self.build_logs[0] = .{
            .severity = .info,
            .message = try std.fmt.allocPrint(self.allocator, "Included {d} icons", .{self.iconSvgCount()}),
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
        try ensureStateDir();
        const state_file_path = try self.stateFilePathAlloc(self.project_name);
        defer self.allocator.free(state_file_path);
        const outcome = try headless.runCompiledAlloc(self.allocator, compiled, .{
            .virtual_time_ms = self.currentVirtualTime(),
            .state_file_path = state_file_path,
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
            .press, .click => |link| try session.clickButton(@intCast(link)),
            .double_click => |link| try session.doubleClickLabel(@intCast(link)),
            .hover => |payload| {
                _ = payload.hovered;
                try session.triggerLink(@intCast(payload.link));
            },
            .change_text => |payload| try session.setTextInputValue(@intCast(payload.link), payload.text),
            .key_down => |payload| try session.pressTextInputKey(@intCast(payload.link), @tagName(payload.key)),
            .blur => |link| try session.blurTextInput(@intCast(link)),
            .focus => |link| try session.focusTextInput(@intCast(link)),
            .checkbox_change => |payload| {
                _ = payload.checked;
                try session.triggerLink(@intCast(payload.link));
            },
            .select_change => |payload| try session.setSelectValue(@intCast(payload.link), payload.value),
            .slider_change => |payload| try session.setSliderValue(@intCast(payload.link), payload.value),
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
        const state_file_path = try self.stateFilePathAlloc(project_name);
        defer self.allocator.free(state_file_path);
        const state_file_path_z = try self.allocator.dupeZ(u8, state_file_path);
        defer self.allocator.free(state_file_path_z);
        _ = c_unlink(state_file_path_z.ptr);
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
        self.clearSnapshotEvents();
        self.snapshot_values = try self.allocator.alloc(RuntimeValue, 1);
        self.snapshot_values[0] = .{ .text = try self.allocator.dupe(u8, rendered) };
        self.snapshot_events = try self.collectEventBindings(session);
        const document = DocumentSnapshot{
            .revision = self.compiled_revision,
            .root = 0,
            .values = self.snapshot_values,
            .events = self.snapshot_events,
            .route = session.routeTextView() catch self.route.current(self.route.ptr),
        };
        return .{ .document = document };
    }

    fn collectEventBindings(self: *BoonRuntimeHost, session: *headless.Session) ![]EventBinding {
        const controls = try session.controlsAlloc(self.allocator);
        defer self.allocator.free(controls);

        var events = std.ArrayList(EventBinding).empty;
        defer events.deinit(self.allocator);
        try appendSectionEvents(self.allocator, &events, controls, "click", "click");
        try appendSectionEvents(self.allocator, &events, controls, "dblclick", "double_click");
        try appendSectionEvents(self.allocator, &events, controls, "text", "change_text");
        try appendSectionEvents(self.allocator, &events, controls, "select", "select_change");
        try appendSectionEvents(self.allocator, &events, controls, "hover", "hover");
        return try events.toOwnedSlice(self.allocator);
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

    fn generateIconAssetsFile(self: *BoonRuntimeHost) ![]u8 {
        var icons = std.ArrayList(ProjectFile).empty;
        defer icons.deinit(self.allocator);
        for (self.files) |file| {
            if (!isDirectIconSvg(file.path)) continue;
            try icons.append(self.allocator, file);
        }
        if (icons.items.len == 0) return error.NoIconSvgFiles;
        std.mem.sort(ProjectFile, icons.items, {}, iconPathLessThan);

        var out = std.Io.Writer.Allocating.init(self.allocator);
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
        for (icons.items, 0..) |icon, index| {
            const stem = iconStem(icon.path);
            const encoded = try percentEncode(self.allocator, std.mem.trimEnd(u8, icon.contents, "\r\n"));
            defer self.allocator.free(encoded);
            try writer.print(
                \\        {s}: TEXT {{
                \\            data:image/svg+xml;utf8,{s}
                \\        }}
                \\
            , .{ stem, encoded });
            if (index + 1 < icons.items.len) try writer.writeByte('\n');
        }
        try writer.writeAll(
            \\    ]
            \\}
            \\
        );
        return try out.toOwnedSlice();
    }

    fn iconSvgCount(self: *const BoonRuntimeHost) usize {
        var count: usize = 0;
        for (self.files) |file| {
            if (isDirectIconSvg(file.path)) count += 1;
        }
        return count;
    }

    fn isDirectIconSvg(path: []const u8) bool {
        const prefix = "assets/icons/";
        if (!std.mem.startsWith(u8, path, prefix)) return false;
        const rest = path[prefix.len..];
        if (rest.len == 0 or std.mem.indexOfScalar(u8, rest, '/') != null) return false;
        return std.mem.endsWith(u8, rest, ".svg");
    }

    fn iconPathLessThan(_: void, lhs: ProjectFile, rhs: ProjectFile) bool {
        return std.mem.lessThan(u8, lhs.path, rhs.path);
    }

    fn iconStem(path: []const u8) []const u8 {
        const name = std.fs.path.basename(path);
        return if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| name[0..dot] else name;
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
            switch (value) {
                .text => |text| self.allocator.free(text),
                else => {},
            }
        }
        self.allocator.free(self.snapshot_values);
        self.snapshot_values = &.{};
    }

    fn clearSnapshotEvents(self: *BoonRuntimeHost) void {
        self.allocator.free(self.snapshot_events);
        self.snapshot_events = &.{};
    }
};

fn ensureStateDir() !void {
    _ = c_mkdir("zig-out", 0o777);
    _ = c_mkdir("zig-out/boon-runtime-state", 0o777);
}

extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern fn unlink(path: [*:0]const u8) c_int;

const c_mkdir = mkdir;
const c_unlink = unlink;

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
