const std = @import("std");
const raybox = @import("raybox");

const host_mod = raybox.boon_adapter.host;
const bridge = host_mod.bridge;
const physical = raybox.render.physical_projection;
const geometry = raybox.render.geometry;

const report_path = "zig-out/reports/bench_playground_native.json";
const duplicate_title = "dupe";
const default_duplicate_todo_count = 100;
const hold_key_character_count = 64;
const single_toggle_budget_ms = 16.0;
const toggle_all_budget_ms = 16.0;
const text_input_single_budget_ms = 16.0;
const text_input_hold_max_budget_ms = 16.0;
const text_input_hold_average_budget_ms = 8.0;
const runtime_snapshot_budget_ms = 9.999;

const PhaseTiming = struct {
    dispatch_ms: f64 = 0,
    snapshot_ms: f64 = 0,
    snapshot_render_ms: f64 = 0,
    snapshot_semantic_root_ms: f64 = 0,
    snapshot_values_ms: f64 = 0,
    snapshot_events_ms: f64 = 0,
    snapshot_route_ms: f64 = 0,
    snapshot_profile_calls: u64 = 0,
    semantic_ms: f64 = 0,
    projection_ms: f64 = 0,
    geometry_ms: f64 = 0,
    total_ms: f64 = 0,
    command_count: usize = 0,
    vertex_count: usize = 0,
    index_count: usize = 0,
};

const BenchContext = struct {
    allocator: std.mem.Allocator,
    persist_ctx: host_mod.MemoryPersistStore,
    route_ctx: host_mod.MemoryRouteStore = .{},
    persist: bridge.PersistStore = undefined,
    route: bridge.RouteStore = undefined,
    virtual_clock: bridge.VirtualClock = .{},
    time_source: bridge.TimeSource = undefined,
    host: bridge.BoonRuntimeHost = undefined,
    batch: geometry.Batcher,

    pub fn init(allocator: std.mem.Allocator) !BenchContext {
        var persist_ctx = host_mod.MemoryPersistStore.init(allocator);
        errdefer persist_ctx.deinit();
        return .{
            .allocator = allocator,
            .persist_ctx = persist_ctx,
            .batch = geometry.Batcher.init(allocator),
        };
    }

    pub fn bindHost(self: *BenchContext) !void {
        self.persist = self.persist_ctx.store();
        self.route = self.route_ctx.store();
        self.time_source = .{ .virtual = &self.virtual_clock };
        self.host = try bridge.BoonRuntimeHost.init(self.allocator, &self.persist, &self.route, &self.time_source);
        self.host.include_rendered_text = false;
        self.host.include_control_visuals = false;
        self.host.include_event_bindings = false;
        self.host.persist_runtime_state = false;
    }

    pub fn deinit(self: *BenchContext) void {
        self.host.deinit();
        self.persist_ctx.deinit();
        self.batch.deinit();
    }
};

const Report = struct {
    add_100: PhaseTiming,
    text_input_single: PhaseTiming,
    text_input_hold: BurstTiming,
    single_toggle: PhaseTiming,
    toggle_all: PhaseTiming,
    single_runtime_snapshot_ms: f64,
    toggle_all_runtime_snapshot_ms: f64,
    text_input_single_runtime_snapshot_ms: f64,
    duplicate_total_after_single: usize,
    duplicate_checked_after_single: usize,
    todo_items_after_toggle_all: usize,
    checked_items_after_toggle_all: usize,
    text_input_hold_chars: usize,
    single_pass: bool,
    toggle_all_pass: bool,
    text_input_single_pass: bool,
    text_input_hold_pass: bool,
    duplicate_independent: bool,
    single_toggled_one: bool,
    toggle_all_correct: bool,
    pass: bool,
};

const BurstTiming = struct {
    iterations: usize = 0,
    total_ms: f64 = 0,
    average_ms: f64 = 0,
    max_ms: f64 = 0,
    max_dispatch_ms: f64 = 0,
    max_snapshot_ms: f64 = 0,
    max_semantic_ms: f64 = 0,
    max_projection_ms: f64 = 0,
    max_geometry_ms: f64 = 0,
};

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    try makePath("zig-out/reports");

    var ctx = try BenchContext.init(allocator);
    defer ctx.deinit();
    try ctx.bindHost();

    const source = try readFileAlloc(allocator, "examples/upstream/todo_mvc/todo_mvc.bn", 4 * 1024 * 1024);
    defer allocator.free(source);
    var files = [_]bridge.ProjectFile{.{
        .path = "todo_mvc.bn",
        .contents = source,
    }};
    try ctx.host.loadProject(.{
        .name = "todo_mvc_bench",
        .entry_file = "todo_mvc.bn",
        .files = &files,
    });
    try ctx.host.clearState("todo_mvc_bench");
    switch (try ctx.host.runBuildFile()) {
        .not_present, .ok => {},
        .diagnostics => |diagnostics| return failDiagnostics(diagnostics),
    }
    switch (try ctx.host.compileEntry()) {
        .ok => {},
        .diagnostics => |diagnostics| return failDiagnostics(diagnostics),
    }
    _ = try snapshotPipeline(&ctx, try ctx.host.start());
    if (ctx.host.session) |*session| session.limit_updates_to_active_control_states = true;
    const trace_enabled = envFlag("RAYBOX_BENCH_TRACE");
    const profile_enabled = envFlag("RAYBOX_BENCH_PROFILE");
    ctx.host.profile_snapshots = profile_enabled;
    if (trace_enabled) {
        if (ctx.host.session) |*session| session.trace_enabled = true;
    }
    const duplicate_todo_count = try configuredTodoCount(allocator);
    const input_handle = try ctx.host.textInputHandle(0);

    var add_timing = PhaseTiming{};
    const add_start = monotonicNanoseconds();
    for (0..duplicate_todo_count) |_| {
        const dispatch_start = monotonicNanoseconds();
        try ctx.host.setTextInputValueWithHandle(input_handle, duplicate_title);
        try ctx.host.pressTextInputKeyWithHandle(input_handle, .enter, duplicate_title);
        add_timing.dispatch_ms += nsToMs(monotonicNanoseconds() - dispatch_start);
    }
    const add_pipeline = try snapshotOnlyPipeline(&ctx);
    add_timing.snapshot_ms = add_pipeline.snapshot_ms;
    add_timing.semantic_ms = add_pipeline.semantic_ms;
    add_timing.projection_ms = add_pipeline.projection_ms;
    add_timing.geometry_ms = add_pipeline.geometry_ms;
    add_timing.command_count = add_pipeline.command_count;
    add_timing.vertex_count = add_pipeline.vertex_count;
    add_timing.index_count = add_pipeline.index_count;
    add_timing.total_ms = nsToMs(monotonicNanoseconds() - add_start);

    const text_input_single = try timedTextInputChange(&ctx, input_handle, "a");
    var hold_text = std.ArrayList(u8).empty;
    defer hold_text.deinit(allocator);
    const text_input_hold = try timedHeldTextInput(&ctx, input_handle, &hold_text, hold_key_character_count);

    var before_single = try snapshotSemantics(&ctx);
    defer before_single.deinit(allocator);
    const checkbox_handles = try checkboxHandles(&ctx, before_single.checkboxes.len);
    defer allocator.free(checkbox_handles);
    if (profile_enabled) {
        if (ctx.host.session) |*session| session.profile_enabled = true;
    }
    const middle_checkbox_index = 3 + duplicate_todo_count / 2;
    const middle_checkbox = checkbox_handles[middle_checkbox_index];
    const toggle_all_checkbox = checkbox_handles[0];
    const single_timing = try timedEventCompact(&ctx, .{ .checkbox_ref_change = .{ .handle = middle_checkbox, .checked = true } }, checkbox_handles);
    if (trace_enabled) try printTrace(&ctx, allocator, "after single");
    var after_single = try compactSemantics(&ctx, checkbox_handles);
    defer after_single.deinit(allocator);
    const duplicate_checked_after_single = checkedAppendedTodos(after_single);
    const duplicate_total_after_single = appendedTodos(after_single);
    const duplicate_independent = duplicate_total_after_single == duplicate_todo_count and duplicate_checked_after_single == 1;
    const before_single_checked = checkedTodoItems(before_single);
    const after_single_checked = checkedTodoItems(after_single);
    const single_toggled_one = after_single_checked == before_single_checked + 1;

    const toggle_all_timing = try timedEventCompact(&ctx, .{ .checkbox_ref_change = .{ .handle = toggle_all_checkbox, .checked = true } }, checkbox_handles);
    if (trace_enabled) try printTrace(&ctx, allocator, "after toggle-all");
    var after_toggle_all = try compactSemantics(&ctx, checkbox_handles);
    defer after_toggle_all.deinit(allocator);
    const todo_items = todoItemCheckboxes(after_toggle_all);
    const checked_items = checkedTodoItems(after_toggle_all);
    const toggle_all_correct = todo_items != 0 and checked_items == todo_items;

    const single_runtime_snapshot_ms = single_timing.dispatch_ms + single_timing.snapshot_ms;
    const toggle_all_runtime_snapshot_ms = toggle_all_timing.dispatch_ms + toggle_all_timing.snapshot_ms;
    const text_input_single_runtime_snapshot_ms = text_input_single.dispatch_ms + text_input_single.snapshot_ms;
    const single_pass = single_timing.total_ms <= single_toggle_budget_ms and single_runtime_snapshot_ms <= runtime_snapshot_budget_ms;
    const toggle_all_pass = toggle_all_timing.total_ms <= toggle_all_budget_ms and toggle_all_runtime_snapshot_ms <= runtime_snapshot_budget_ms;
    const text_input_single_pass = text_input_single.total_ms <= text_input_single_budget_ms and text_input_single_runtime_snapshot_ms <= runtime_snapshot_budget_ms;
    const text_input_hold_pass = text_input_hold.max_ms <= text_input_hold_max_budget_ms and text_input_hold.average_ms <= text_input_hold_average_budget_ms;
    const correctness_pass = duplicate_independent and single_toggled_one and toggle_all_correct;
    const pass = single_pass and toggle_all_pass and text_input_single_pass and text_input_hold_pass and correctness_pass;

    try writeReport(.{
        .add_100 = add_timing,
        .text_input_single = text_input_single,
        .text_input_hold = text_input_hold,
        .single_toggle = single_timing,
        .toggle_all = toggle_all_timing,
        .single_runtime_snapshot_ms = single_runtime_snapshot_ms,
        .toggle_all_runtime_snapshot_ms = toggle_all_runtime_snapshot_ms,
        .text_input_single_runtime_snapshot_ms = text_input_single_runtime_snapshot_ms,
        .duplicate_total_after_single = duplicate_total_after_single,
        .duplicate_checked_after_single = duplicate_checked_after_single,
        .todo_items_after_toggle_all = todo_items,
        .checked_items_after_toggle_all = checked_items,
        .text_input_hold_chars = hold_key_character_count,
        .single_pass = single_pass,
        .toggle_all_pass = toggle_all_pass,
        .text_input_single_pass = text_input_single_pass,
        .text_input_hold_pass = text_input_hold_pass,
        .duplicate_independent = duplicate_independent,
        .single_toggled_one = single_toggled_one,
        .toggle_all_correct = toggle_all_correct,
        .pass = pass,
    });

    std.debug.print(
        "bench-playground-native: type={d:.3}ms hold_avg={d:.3}ms hold_max={d:.3}ms single={d:.3}ms toggle_all={d:.3}ms duplicate_checked={d}/{d} all_checked={d}/{d} pass={}\n",
        .{
            text_input_single.total_ms,
            text_input_hold.average_ms,
            text_input_hold.max_ms,
            single_timing.total_ms,
            toggle_all_timing.total_ms,
            duplicate_checked_after_single,
            duplicate_total_after_single,
            checked_items,
            todo_items,
            pass,
        },
    );
    if (!pass) return error.BenchmarkGateFailed;
}

fn timedEvent(ctx: *BenchContext, event: bridge.PreviewEvent) !PhaseTiming {
    const total_start = monotonicNanoseconds();
    const dispatch_start = monotonicNanoseconds();
    try ctx.host.dispatchNoSnapshot(event);
    var timing = PhaseTiming{ .dispatch_ms = nsToMs(monotonicNanoseconds() - dispatch_start) };
    const pipeline = try snapshotOnlyPipeline(ctx);
    timing.snapshot_ms = pipeline.snapshot_ms;
    timing.semantic_ms = pipeline.semantic_ms;
    timing.projection_ms = pipeline.projection_ms;
    timing.geometry_ms = pipeline.geometry_ms;
    timing.command_count = pipeline.command_count;
    timing.vertex_count = pipeline.vertex_count;
    timing.index_count = pipeline.index_count;
    timing.total_ms = nsToMs(monotonicNanoseconds() - total_start);
    return timing;
}

fn timedTextInputChange(ctx: *BenchContext, handle: bridge.TextInputHandle, text: []const u8) !PhaseTiming {
    const total_start = monotonicNanoseconds();
    const dispatch_start = monotonicNanoseconds();
    try ctx.host.setTextInputValueWithHandle(handle, text);
    var timing = PhaseTiming{ .dispatch_ms = nsToMs(monotonicNanoseconds() - dispatch_start) };
    const pipeline = try snapshotOnlyPipeline(ctx);
    timing.snapshot_ms = pipeline.snapshot_ms;
    timing.semantic_ms = pipeline.semantic_ms;
    timing.projection_ms = pipeline.projection_ms;
    timing.geometry_ms = pipeline.geometry_ms;
    timing.command_count = pipeline.command_count;
    timing.vertex_count = pipeline.vertex_count;
    timing.index_count = pipeline.index_count;
    timing.total_ms = nsToMs(monotonicNanoseconds() - total_start);
    return timing;
}

fn timedHeldTextInput(
    ctx: *BenchContext,
    handle: bridge.TextInputHandle,
    text: *std.ArrayList(u8),
    count: usize,
) !BurstTiming {
    var burst = BurstTiming{ .iterations = count };
    for (0..count) |_| {
        try text.append(ctx.allocator, 'a');
        const timing = try timedTextInputChange(ctx, handle, text.items);
        burst.total_ms += timing.total_ms;
        burst.max_ms = @max(burst.max_ms, timing.total_ms);
        burst.max_dispatch_ms = @max(burst.max_dispatch_ms, timing.dispatch_ms);
        burst.max_snapshot_ms = @max(burst.max_snapshot_ms, timing.snapshot_ms);
        burst.max_semantic_ms = @max(burst.max_semantic_ms, timing.semantic_ms);
        burst.max_projection_ms = @max(burst.max_projection_ms, timing.projection_ms);
        burst.max_geometry_ms = @max(burst.max_geometry_ms, timing.geometry_ms);
    }
    if (count != 0) burst.average_ms = burst.total_ms / @as(f64, @floatFromInt(count));
    return burst;
}

fn timedEventCompact(ctx: *BenchContext, event: bridge.PreviewEvent, handles: []const bridge.ControlHandle) !PhaseTiming {
    const total_start = monotonicNanoseconds();
    const dispatch_start = monotonicNanoseconds();
    try ctx.host.dispatchNoSnapshot(event);
    var timing = PhaseTiming{ .dispatch_ms = nsToMs(monotonicNanoseconds() - dispatch_start) };

    const snapshot_start = monotonicNanoseconds();
    var semantic = try compactSemantics(ctx, handles);
    timing.snapshot_ms = nsToMs(monotonicNanoseconds() - snapshot_start);
    defer semantic.deinit(ctx.allocator);

    const projection_start = monotonicNanoseconds();
    var trace = try physical.RenderTrace.project(ctx.allocator, semantic, .{});
    defer trace.deinit(ctx.allocator);
    timing.projection_ms = nsToMs(monotonicNanoseconds() - projection_start);
    timing.command_count = trace.commands.len;

    const geometry_start = monotonicNanoseconds();
    ctx.batch.clearRetainingCapacity();
    try emitTraceGeometry(&ctx.batch, trace);
    timing.geometry_ms = nsToMs(monotonicNanoseconds() - geometry_start);
    timing.vertex_count = ctx.batch.vertices.items.len;
    timing.index_count = ctx.batch.indices.items.len;
    timing.total_ms = nsToMs(monotonicNanoseconds() - total_start);
    return timing;
}

fn configuredTodoCount(allocator: std.mem.Allocator) !usize {
    _ = allocator;
    const raw_ptr = std.c.getenv("RAYBOX_BENCH_TODO_COUNT") orelse return default_duplicate_todo_count;
    const raw = std.mem.sliceTo(raw_ptr, 0);
    return try std.fmt.parseUnsigned(usize, raw, 10);
}

fn envFlag(name: [*:0]const u8) bool {
    const raw_ptr = std.c.getenv(name) orelse return false;
    const raw = std.mem.sliceTo(raw_ptr, 0);
    return raw.len != 0 and !std.mem.eql(u8, raw, "0") and !std.mem.eql(u8, raw, "false");
}

fn printTrace(ctx: *BenchContext, allocator: std.mem.Allocator, label: []const u8) !void {
    if (ctx.host.session) |*session| {
        const trace = try session.traceAlloc(allocator);
        defer allocator.free(trace);
        std.debug.print("TRACE {s}\n{s}\n", .{ label, trace });
    }
}

fn snapshotOnlyPipeline(ctx: *BenchContext) !PhaseTiming {
    const snapshot_start = monotonicNanoseconds();
    const output = try ctx.host.tick(ctx.virtual_clock.now_ms);
    var timing = PhaseTiming{};
    applySnapshotProfile(ctx, &timing);
    const pipeline = try snapshotPipeline(ctx, output);
    timing.semantic_ms = pipeline.semantic_ms;
    timing.projection_ms = pipeline.projection_ms;
    timing.geometry_ms = pipeline.geometry_ms;
    timing.command_count = pipeline.command_count;
    timing.vertex_count = pipeline.vertex_count;
    timing.index_count = pipeline.index_count;
    timing.snapshot_ms = nsToMs(monotonicNanoseconds() - snapshot_start) - timing.semantic_ms - timing.projection_ms - timing.geometry_ms;
    if (timing.snapshot_ms < 0) timing.snapshot_ms = 0;
    return timing;
}

fn snapshotPipeline(ctx: *BenchContext, output: bridge.RuntimeOutput) !PhaseTiming {
    const allocator = ctx.allocator;
    var timing = PhaseTiming{};

    const semantic_start = monotonicNanoseconds();
    var semantic = switch (output) {
        .document => |document| try physical.SemanticTree.fromDocument(allocator, document),
        .scene => |scene| try physical.SemanticTree.fromScene(allocator, scene),
        .diagnostics => |diagnostics| return failDiagnostics(diagnostics),
    };
    defer semantic.deinit(allocator);
    timing.semantic_ms = nsToMs(monotonicNanoseconds() - semantic_start);

    const projection_start = monotonicNanoseconds();
    var trace = try physical.RenderTrace.project(allocator, semantic, .{});
    defer trace.deinit(allocator);
    timing.projection_ms = nsToMs(monotonicNanoseconds() - projection_start);
    timing.command_count = trace.commands.len;

    const geometry_start = monotonicNanoseconds();
    ctx.batch.clearRetainingCapacity();
    try emitTraceGeometry(&ctx.batch, trace);
    timing.geometry_ms = nsToMs(monotonicNanoseconds() - geometry_start);
    timing.vertex_count = ctx.batch.vertices.items.len;
    timing.index_count = ctx.batch.indices.items.len;
    return timing;
}

fn snapshotSemantics(ctx: *BenchContext) !physical.SemanticTree {
    const output = try ctx.host.tick(ctx.virtual_clock.now_ms);
    return switch (output) {
        .document => |document| try physical.SemanticTree.fromDocument(ctx.allocator, document),
        .scene => |scene| try physical.SemanticTree.fromScene(ctx.allocator, scene),
        .diagnostics => |diagnostics| return failDiagnostics(diagnostics),
    };
}

fn checkboxHandles(ctx: *BenchContext, count: usize) ![]bridge.ControlHandle {
    const handles = try ctx.allocator.alloc(bridge.ControlHandle, count);
    errdefer ctx.allocator.free(handles);
    for (handles, 0..) |*handle, index| {
        handle.* = try ctx.host.checkboxHandle(index);
    }
    return handles;
}

fn compactSemantics(ctx: *BenchContext, handles: []const bridge.ControlHandle) !physical.SemanticTree {
    const rendered_text = try ctx.allocator.dupe(u8, "");
    errdefer ctx.allocator.free(rendered_text);
    const checked_values = if (handles.len > 1)
        try ctx.host.checkboxCheckedMany(ctx.allocator, handles[1..])
    else
        try ctx.host.checkboxCheckedMany(ctx.allocator, handles);
    defer ctx.allocator.free(checked_values);
    const checkboxes = try ctx.allocator.alloc(physical.SemanticCheckbox, handles.len);
    errdefer ctx.allocator.free(checkboxes);
    if (handles.len != 0) {
        checkboxes[0] = .{
            .label = @constCast(&[_]u8{}),
            .checked = false,
        };
    }
    const offset: usize = if (handles.len > 1) 1 else 0;
    for (checked_values, 0..) |checked, index| {
        checkboxes[index + offset] = .{
            .label = @constCast(&[_]u8{}),
            .checked = checked,
        };
    }
    return .{
        .rendered_text = rendered_text,
        .inputs = @constCast(&[_]physical.SemanticInput{}),
        .buttons = @constCast(&[_]physical.SemanticButton{}),
        .checkboxes = checkboxes,
        .svg_clicks = @constCast(&[_]physical.SemanticSvgClick{}),
        .svg_circles = @constCast(&[_]physical.SemanticSvgCircle{}),
    };
}

fn emitTraceGeometry(batch: *geometry.Batcher, trace: physical.RenderTrace) !void {
    for (trace.commands) |command| {
        const base = command.base;
        switch (base.kind) {
            .shadow, .cutout_rounded_rect, .bevel, .glow, .outline, .caret, .selection => {
                try geometry.emitRoundedRect(batch, base.rect, base.radius, base.color);
            },
            .inner_shadow => {
                const spread = @max(1.0, base.spread);
                try geometry.emitBorder(batch, base.rect, base.radius, .{ .left = spread, .top = spread, .right = spread, .bottom = spread }, base.color);
            },
            .svg_circle => {
                const width = @max(1.0, if (base.outline_width > 0) base.outline_width else 2.0);
                try geometry.emitBorder(batch, base.rect, geometry.CornerRadius.uniform(base.rect.w * 0.5), .{ .left = width, .top = width, .right = width, .bottom = width }, base.color);
            },
            .svg_path => {
                const width = @max(2.0, if (base.outline_width > 0) base.outline_width else 3.0);
                const a = geometry.Vec2{ .x = base.rect.x + base.rect.w * 0.24, .y = base.rect.y + base.rect.h * 0.55 };
                const b = geometry.Vec2{ .x = base.rect.x + base.rect.w * 0.44, .y = base.rect.y + base.rect.h * 0.74 };
                const c = geometry.Vec2{ .x = base.rect.x + base.rect.w * 0.78, .y = base.rect.y + base.rect.h * 0.28 };
                try geometry.emitLine(batch, a, b, width, base.color);
                try geometry.emitLine(batch, b, c, width, base.color);
            },
        }
    }
}

fn todoItemCheckboxes(semantic: physical.SemanticTree) usize {
    return if (semantic.checkboxes.len == 0) 0 else semantic.checkboxes.len - 1;
}

fn checkedTodoItems(semantic: physical.SemanticTree) usize {
    var count: usize = 0;
    for (semantic.checkboxes, 0..) |checkbox, index| {
        if (index == 0) continue;
        if (checkbox.checked) count += 1;
    }
    return count;
}

fn appendedTodos(semantic: physical.SemanticTree) usize {
    return if (semantic.checkboxes.len > 3) semantic.checkboxes.len - 3 else 0;
}

fn checkedAppendedTodos(semantic: physical.SemanticTree) usize {
    var count: usize = 0;
    for (semantic.checkboxes, 0..) |checkbox, index| {
        if (index < 3) continue;
        if (checkbox.checked) count += 1;
    }
    return count;
}

fn writeReport(report: Report) !void {
    var out = std.Io.Writer.Allocating.init(std.heap.c_allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll("{\n");
    try writeTiming(w, "add_100", report.add_100, true);
    try writeTiming(w, "text_input_single", report.text_input_single, true);
    try writeBurstTiming(w, "text_input_hold", report.text_input_hold, true);
    try writeTiming(w, "single_toggle", report.single_toggle, true);
    try writeTiming(w, "toggle_all", report.toggle_all, true);
    try w.print("  \"text_input_single_runtime_snapshot_ms\": {d:.3},\n", .{report.text_input_single_runtime_snapshot_ms});
    try w.print("  \"single_runtime_snapshot_ms\": {d:.3},\n", .{report.single_runtime_snapshot_ms});
    try w.print("  \"toggle_all_runtime_snapshot_ms\": {d:.3},\n", .{report.toggle_all_runtime_snapshot_ms});
    try w.print("  \"duplicate_total_after_single\": {d},\n", .{report.duplicate_total_after_single});
    try w.print("  \"duplicate_checked_after_single\": {d},\n", .{report.duplicate_checked_after_single});
    try w.print("  \"todo_items_after_toggle_all\": {d},\n", .{report.todo_items_after_toggle_all});
    try w.print("  \"checked_items_after_toggle_all\": {d},\n", .{report.checked_items_after_toggle_all});
    try w.print("  \"text_input_hold_chars\": {d},\n", .{report.text_input_hold_chars});
    try w.print("  \"single_pass\": {},\n", .{report.single_pass});
    try w.print("  \"toggle_all_pass\": {},\n", .{report.toggle_all_pass});
    try w.print("  \"text_input_single_pass\": {},\n", .{report.text_input_single_pass});
    try w.print("  \"text_input_hold_pass\": {},\n", .{report.text_input_hold_pass});
    try w.print("  \"duplicate_independent\": {},\n", .{report.duplicate_independent});
    try w.print("  \"single_toggled_one\": {},\n", .{report.single_toggled_one});
    try w.print("  \"toggle_all_correct\": {},\n", .{report.toggle_all_correct});
    try w.print("  \"pass\": {}\n", .{report.pass});
    try w.writeAll("}\n");
    try writeFile(report_path, out.written());
}

fn writeBurstTiming(w: *std.Io.Writer, name: []const u8, timing: BurstTiming, comma: bool) !void {
    try w.print("  \"{s}\": {{\n", .{name});
    try w.print("    \"iterations\": {d},\n", .{timing.iterations});
    try w.print("    \"total_ms\": {d:.3},\n", .{timing.total_ms});
    try w.print("    \"average_ms\": {d:.3},\n", .{timing.average_ms});
    try w.print("    \"max_ms\": {d:.3},\n", .{timing.max_ms});
    try w.print("    \"max_dispatch_ms\": {d:.3},\n", .{timing.max_dispatch_ms});
    try w.print("    \"max_snapshot_ms\": {d:.3},\n", .{timing.max_snapshot_ms});
    try w.print("    \"max_semantic_ms\": {d:.3},\n", .{timing.max_semantic_ms});
    try w.print("    \"max_projection_ms\": {d:.3},\n", .{timing.max_projection_ms});
    try w.print("    \"max_geometry_ms\": {d:.3}\n", .{timing.max_geometry_ms});
    try w.print("  }}{s}\n", .{if (comma) "," else ""});
}

fn writeTiming(w: *std.Io.Writer, name: []const u8, timing: PhaseTiming, comma: bool) !void {
    try w.print("  \"{s}\": {{\n", .{name});
    try w.print("    \"dispatch_ms\": {d:.3},\n", .{timing.dispatch_ms});
    try w.print("    \"snapshot_ms\": {d:.3},\n", .{timing.snapshot_ms});
    try w.print("    \"snapshot_render_ms\": {d:.3},\n", .{timing.snapshot_render_ms});
    try w.print("    \"snapshot_semantic_root_ms\": {d:.3},\n", .{timing.snapshot_semantic_root_ms});
    try w.print("    \"snapshot_values_ms\": {d:.3},\n", .{timing.snapshot_values_ms});
    try w.print("    \"snapshot_events_ms\": {d:.3},\n", .{timing.snapshot_events_ms});
    try w.print("    \"snapshot_route_ms\": {d:.3},\n", .{timing.snapshot_route_ms});
    try w.print("    \"snapshot_profile_calls\": {d},\n", .{timing.snapshot_profile_calls});
    try w.print("    \"semantic_ms\": {d:.3},\n", .{timing.semantic_ms});
    try w.print("    \"projection_ms\": {d:.3},\n", .{timing.projection_ms});
    try w.print("    \"geometry_ms\": {d:.3},\n", .{timing.geometry_ms});
    try w.print("    \"total_ms\": {d:.3},\n", .{timing.total_ms});
    try w.print("    \"command_count\": {d},\n", .{timing.command_count});
    try w.print("    \"vertex_count\": {d},\n", .{timing.vertex_count});
    try w.print("    \"index_count\": {d}\n", .{timing.index_count});
    try w.print("  }}{s}\n", .{if (comma) "," else ""});
}

fn applySnapshotProfile(ctx: *BenchContext, timing: *PhaseTiming) void {
    const profile = ctx.host.snapshotProfile();
    timing.snapshot_render_ms = nsToMs(profile.render_ns);
    timing.snapshot_semantic_root_ms = nsToMs(profile.semantic_root_ns);
    timing.snapshot_values_ms = nsToMs(profile.snapshot_values_ns);
    timing.snapshot_events_ms = nsToMs(profile.event_bindings_ns);
    timing.snapshot_route_ms = nsToMs(profile.route_ns);
    timing.snapshot_profile_calls = profile.calls;
}

fn failDiagnostics(diagnostics: []const bridge.Diagnostic) anyerror {
    for (diagnostics) |diagnostic| {
        std.debug.print("diagnostic: {s}\n", .{diagnostic.message});
    }
    return error.RuntimeDiagnostic;
}

fn monotonicNanoseconds() u64 {
    const linux = std.os.linux;
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_size: usize) ![]u8 {
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
    if (c_fread(bytes.ptr, 1, size, file) != size) return error.FileReadFailed;
    return bytes;
}

fn makePath(path: []const u8) !void {
    var buf: [512:0]u8 = undefined;
    if (path.len >= buf.len) return error.PathTooLong;
    for (path, 0..) |byte, i| {
        buf[i] = byte;
        if (byte == '/' and i != 0) {
            buf[i] = 0;
            _ = c_mkdir(buf[0..i :0].ptr, 0o777);
            buf[i] = '/';
        }
    }
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = c_mkdir(buf[0..path.len :0].ptr, 0o777);
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    var path_buf: [512:0]u8 = undefined;
    if (path.len >= path_buf.len) return error.PathTooLong;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const file = c_fopen(path_buf[0..path.len :0].ptr, "wb") orelse return error.FileCreateFailed;
    defer _ = c_fclose(file);
    if (c_fwrite(bytes.ptr, 1, bytes.len, file) != bytes.len) return error.FileWriteFailed;
}

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(file: *anyopaque) c_int;
extern fn fseek(file: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(file: *anyopaque) c_long;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;

const c_fopen = fopen;
const c_fclose = fclose;
const c_fseek = fseek;
const c_ftell = ftell;
const c_fread = fread;
const c_fwrite = fwrite;
const c_mkdir = mkdir;
