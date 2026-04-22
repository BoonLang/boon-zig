const std = @import("std");
const diag = @import("diag.zig");
const flow_ir = @import("flow_ir.zig");
const io_backend = @import("io_backend.zig");
const physical = @import("physical.zig");

pub const Options = struct {
    trace: bool = false,
    virtual_time_ms: u64 = 0,
    state_file_path: ?[]const u8 = null,
    clear_state: bool = false,
    terminal_columns: usize = 80,
    terminal_rows: usize = 24,
};

pub const Outcome = union(enum) {
    ok: Session,
    err: diag.Diagnostic,
};

const Pulse = struct {
    source: flow_ir.NodeId,
    payload: PulsePayload,
    scope: ?*const EvalScope = null,
};

const PulsePayload = union(enum) {
    node: flow_ir.NodeId,
    value: Value,
};

const RecordField = struct {
    name: []const u8,
    value: Value,
};

const ScopedNodeKey = struct {
    node_id: flow_ir.NodeId,
    scope_id: u64,
};

const CachedEvalEntry = struct {
    value: Value,
    deps: []ScopedNodeKey,
};

const EvalFrame = struct {
    parent: ?*EvalFrame,
    deps: std.ArrayListUnmanaged(ScopedNodeKey) = .empty,
};

const ScopedNodeValue = struct {
    node_id: flow_ir.NodeId,
    scope: ?*const EvalScope,
};

const DocumentValue = struct {
    root: Value,
};

const TerminalValue = struct {
    root: Value,
    loop: Value = .none,
};

const StripeDirection = enum {
    row,
    column,
};

const StripeValue = struct {
    items: []Value,
    direction: StripeDirection,
    gap: usize = 0,
    hovered_link: ?flow_ir.NodeId = null,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const LabelValue = struct {
    label: Value,
    click_link: ?flow_ir.NodeId = null,
    double_click_link: ?flow_ir.NodeId = null,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const ContainerValue = struct {
    child: Value,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const CheckboxValue = struct {
    icon: Value,
    label: Value = .none,
    checked: Value = .none,
    click_link: ?flow_ir.NodeId,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const ButtonValue = struct {
    label: Value,
    press_link: ?flow_ir.NodeId,
    hovered_link: ?flow_ir.NodeId = null,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const TextInputValue = struct {
    text: Value,
    change_link: ?flow_ir.NodeId,
    key_link: ?flow_ir.NodeId = null,
    blur_link: ?flow_ir.NodeId = null,
    focus_link: ?flow_ir.NodeId = null,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const SelectValue = struct {
    selected: Value,
    change_link: ?flow_ir.NodeId,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const SliderValue = struct {
    change_link: ?flow_ir.NodeId,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

const EvalScope = struct {
    bindings: []const RecordField,
    parent: ?*const EvalScope,
    passed: ?Value = null,
    id: u64 = 0,
    transparent_state_scope: bool = false,
};

const Value = union(enum) {
    number: f64,
    text: []const u8,
    symbol: []const u8,
    duration_ms: u64,
    list: []Value,
    record: []RecordField,
    binding_ref: flow_ir.BindingId,
    document: *DocumentValue,
    terminal: *TerminalValue,
    stripe: *StripeValue,
    label: *LabelValue,
    container: *ContainerValue,
    checkbox: *CheckboxValue,
    button: *ButtonValue,
    text_input: *TextInputValue,
    select: *SelectValue,
    slider: *SliderValue,
    scoped_node: *ScopedNodeValue,
    link: flow_ir.NodeId,
    none,
};

pub const PhysicalRenderTarget = union(enum) {
    ascii_strip: physical.AsciiStrip,
    cavity_panel: physical.CavityPanel,
    shaded_panel: physical.ShadedPanel,
    lit_panel: physical.LitPanel,

    pub fn textAlloc(self: PhysicalRenderTarget, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .ascii_strip => |ascii| ascii.textAlloc(allocator),
            .cavity_panel => |panel| panel.textAlloc(allocator),
            .shaded_panel => |panel| panel.textAlloc(allocator),
            .lit_panel => |panel| panel.textAlloc(allocator),
        };
    }

    pub fn kindLabel(self: PhysicalRenderTarget) []const u8 {
        return switch (self) {
            .ascii_strip => "ascii_strip",
            .cavity_panel => "cavity_panel",
            .shaded_panel => "shaded_panel",
            .lit_panel => "lit_panel",
        };
    }
};

pub const TerminalKeyBinding = struct {
    keys: [][]const u8,
    link: flow_ir.NodeId,
    scope: ?*const EvalScope = null,
    when: bool,
    label: ?[]const u8,
};

pub const TerminalLoopSpec = struct {
    pulse_link: flow_ir.NodeId,
    scope: ?*const EvalScope = null,
    while_active: bool,
    every_ms: u64,
};

pub const TerminalHitRegion = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    button_index: ?usize = null,
    label_double_click_index: ?usize = null,
    text_input_index: ?usize = null,
    hover_index: ?usize = null,

    pub fn contains(self: TerminalHitRegion, x: usize, y: usize) bool {
        return x >= self.x and x < self.x + self.width and y >= self.y and y < self.y + self.height;
    }
};

pub const TerminalContract = struct {
    keyboard_bindings: []TerminalKeyBinding,
    loop: ?TerminalLoopSpec,

    pub fn deinit(self: *TerminalContract, allocator: std.mem.Allocator) void {
        for (self.keyboard_bindings) |binding| {
            allocator.free(binding.keys);
            if (binding.label) |label| allocator.free(label);
            destroyCapturedScope(allocator, binding.scope);
        }
        allocator.free(self.keyboard_bindings);
        if (self.loop) |loop| destroyCapturedScope(allocator, loop.scope);
    }
};

fn cloneTerminalContract(allocator: std.mem.Allocator, contract: TerminalContract) !TerminalContract {
    const bindings = try allocator.alloc(TerminalKeyBinding, contract.keyboard_bindings.len);
    for (contract.keyboard_bindings, 0..) |binding, index| {
        const keys = try allocator.alloc([]const u8, binding.keys.len);
        for (binding.keys, 0..) |key, key_index| {
            keys[key_index] = try allocator.dupe(u8, key);
        }
        bindings[index] = .{
            .keys = keys,
            .link = binding.link,
            .scope = if (binding.scope) |scope| try captureScope(allocator, scope) else null,
            .when = binding.when,
            .label = if (binding.label) |label| try allocator.dupe(u8, label) else null,
        };
    }

    return .{
        .keyboard_bindings = bindings,
        .loop = if (contract.loop) |loop| .{
            .pulse_link = loop.pulse_link,
            .scope = if (loop.scope) |scope| try captureScope(allocator, scope) else null,
            .while_active = loop.while_active,
            .every_ms = loop.every_ms,
        } else null,
    };
}

const PersistedScalarKind = enum {
    none,
    number,
    text,
    symbol,
    duration_ms,
};

const PersistedScalar = struct {
    kind: PersistedScalarKind,
    number: ?f64 = null,
    text: ?[]const u8 = null,
    duration_ms: ?u64 = null,
};

const PersistedSumEntry = struct {
    stable_id: u64 = 0,
    node_id: ?flow_ir.NodeId = null,
    value: f64,
};

const PersistedHoldEntry = struct {
    stable_id: u64 = 0,
    node_id: ?flow_ir.NodeId = null,
    value: PersistedScalar,
};

const PersistedState = struct {
    version: u32 = 2,
    sums: []PersistedSumEntry,
    holds: []PersistedHoldEntry,
};

const PersistKind = enum {
    sum,
    hold,
};

const ControlEventRef = struct {
    link: flow_ir.NodeId,
    scope: ?*const EvalScope = null,
};

const CachedControlKind = enum {
    button,
    slider,
    text_input,
    text_input_key,
    text_input_blur,
    text_input_focus,
    label_double_click,
    hover,
    select,
};

const TerminalLayoutCounters = struct {
    button: usize = 0,
    label_double_click: usize = 0,
    text_input: usize = 0,
    hover: usize = 0,
};

const TerminalLayoutSize = struct {
    width: usize,
    height: usize,
};

const TerminalStyleSize = struct {
    width: usize = 0,
    height: usize = 0,
};

const GridBlock = struct {
    lines: []const []const u8,
    width: usize,
};

const ControlSummary = struct {
    clicks: std.ArrayList([]const u8) = .empty,
    double_clicks: std.ArrayList([]const u8) = .empty,
    text_inputs: std.ArrayList([]const u8) = .empty,
    selects: std.ArrayList([]const u8) = .empty,
    hovers: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *ControlSummary, allocator: std.mem.Allocator) void {
        self.clicks.deinit(allocator);
        self.double_clicks.deinit(allocator);
        self.text_inputs.deinit(allocator);
        self.selects.deinit(allocator);
        self.hovers.deinit(allocator);
    }
};

const control_summary_limit: usize = 16;

pub const Session = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    memo_arena: std.heap.ArenaAllocator,
    flow: flow_ir.Document,
    trace_enabled: bool,
    trace_lines: std.ArrayList([]const u8) = .empty,
    queue: std.ArrayList(Pulse) = .empty,
    subscribers: [][]flow_ir.NodeId = &.{},
    runtime_subscribers: []bool = &.{},
    latest_values: []?PulsePayload = &.{},
    scoped_latest_values: std.AutoHashMapUnmanaged(ScopedNodeKey, PulsePayload) = .empty,
    hold_values: []Value = &.{},
    hold_inited: []bool = &.{},
    scoped_hold_values: std.AutoHashMapUnmanaged(ScopedNodeKey, Value) = .empty,
    link_values: []Value = &.{},
    link_inited: []bool = &.{},
    scoped_link_values: std.AutoHashMapUnmanaged(ScopedNodeKey, Value) = .empty,
    link_key_values: []Value = &.{},
    link_key_inited: []bool = &.{},
    scoped_link_key_values: std.AutoHashMapUnmanaged(ScopedNodeKey, Value) = .empty,
    eval_cache: std.AutoHashMapUnmanaged(ScopedNodeKey, CachedEvalEntry) = .empty,
    cached_terminal_contract: ?*TerminalContract = null,
    cached_terminal_contract_deps: ?[]ScopedNodeKey = null,
    cached_terminal_hit_regions: ?[]TerminalHitRegion = null,
    cached_button_links: ?[]ControlEventRef = null,
    cached_slider_links: ?[]ControlEventRef = null,
    cached_text_input_links: ?[]ControlEventRef = null,
    cached_text_input_key_links: ?[]ControlEventRef = null,
    cached_text_input_blur_links: ?[]ControlEventRef = null,
    cached_text_input_focus_links: ?[]ControlEventRef = null,
    cached_label_double_click_links: ?[]ControlEventRef = null,
    cached_hover_links: ?[]ControlEventRef = null,
    cached_select_links: ?[]ControlEventRef = null,
    cached_text_inputs: ?[]*TextInputValue = null,
    current_eval_frame: ?*EvalFrame = null,
    terminal_columns: usize = 80,
    terminal_rows: usize = 24,
    list_values: []Value = &.{},
    list_inited: []bool = &.{},
    list_remove_tombstones: [][]Value = &.{},
    skip_values: []Value = &.{},
    skip_inited: []bool = &.{},
    skip_seen: []u64 = &.{},
    sum_values: []f64 = &.{},
    sum_inited: []bool = &.{},
    timer_period_ms: []u64 = &.{},
    timer_next_fire_ms: []u64 = &.{},
    scene_specs: []?physical.SceneSpec = &.{},
    geometry_plans: []?physical.GeometryPlan = &.{},
    geometry_results: []?physical.GeometryResult = &.{},
    geometry_primitives: []?physical.GeometryPrimitive = &.{},
    geometry_rasters: []?physical.GeometryRaster = &.{},
    geometry_displays: []?physical.GeometryDisplay = &.{},
    geometry_shaded_strips: []?physical.ShadedStrip = &.{},
    geometry_panels: []?physical.CavityPanel = &.{},
    geometry_shaded_panels: []?physical.ShadedPanel = &.{},
    geometry_lit_panels: []?physical.LitPanel = &.{},
    pending_physical_features: []?physical.PendingFeatureUse = &.{},
    persist_ids: []u64 = &.{},
    node_scope_state: []u8 = &.{},
    current_time_ms: u64 = 0,
    route_value: Value = .{ .text = "/" },
    state_file_path: ?[]const u8 = null,
    clear_state: bool = false,

    pub fn deinit(self: *Session) void {
        self.trace_lines.deinit(self.arena.allocator());
        self.queue.deinit(self.arena.allocator());
        self.scoped_latest_values.deinit(self.arena.allocator());
        self.scoped_hold_values.deinit(self.arena.allocator());
        self.scoped_link_values.deinit(self.arena.allocator());
        self.scoped_link_key_values.deinit(self.arena.allocator());
        self.clearEvalCache();
        self.eval_cache.deinit(self.backing_allocator);
        if (self.cached_terminal_contract_deps) |deps| self.backing_allocator.free(deps);
        self.memo_arena.deinit();
        self.flow.deinit();
        self.arena.deinit();
    }

    fn clearEvalCache(self: *Session) void {
        var iterator = self.eval_cache.iterator();
        while (iterator.next()) |entry| {
            self.backing_allocator.free(entry.value_ptr.deps);
        }
        self.eval_cache.clearRetainingCapacity();
    }

    fn invalidateEvalCache(self: *Session) void {
        self.clearEvalCache();
        if (self.cached_terminal_contract_deps) |deps| self.backing_allocator.free(deps);
        self.cached_terminal_contract = null;
        self.cached_terminal_contract_deps = null;
        self.cached_terminal_hit_regions = null;
        self.cached_button_links = null;
        self.cached_slider_links = null;
        self.cached_text_input_links = null;
        self.cached_text_input_key_links = null;
        self.cached_text_input_blur_links = null;
        self.cached_text_input_focus_links = null;
        self.cached_label_double_click_links = null;
        self.cached_hover_links = null;
        self.cached_select_links = null;
        self.cached_text_inputs = null;
    }

    fn flushPendingQueue(self: *Session) !void {
        if (self.queue.items.len != 0) try self.processQueue();
    }

    pub fn renderAlloc(self: *Session, allocator: std.mem.Allocator) anyerror![]u8 {
        try self.flushPendingQueue();
        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();

        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);

        const value = try self.evalNode(scratch.allocator(), self.flow.bindings[root_binding].node, null);
        try self.appendRenderedValue(&output, allocator, value);
        return try output.toOwnedSlice(allocator);
    }

    pub fn snapshotAlloc(self: *Session, allocator: std.mem.Allocator) anyerror![]u8 {
        try self.flushPendingQueue();
        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();

        const value = try self.evalNode(scratch.allocator(), self.flow.bindings[root_binding].node, null);
        if (try self.livePhysicalRenderTarget(scratch.allocator())) |target| {
            return try target.textAlloc(allocator);
        }
        if (self.hasPhysicalRenderTarget()) {
            return try self.cachedPhysicalSnapshotAlloc(allocator);
        }
        const block = try self.snapshotBlock(scratch.allocator(), value);

        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);
        for (block.lines, 0..) |line, index| {
            if (index != 0) try output.append(allocator, '\n');
            try output.appendSlice(allocator, line);
        }
        return try output.toOwnedSlice(allocator);
    }

    pub fn physicalRenderTarget(self: *Session, allocator: std.mem.Allocator) !?PhysicalRenderTarget {
        try self.flushPendingQueue();
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        return try self.livePhysicalRenderTarget(scratch.allocator());
    }

    fn hasPhysicalRenderTarget(self: *Session) bool {
        for (self.geometry_lit_panels) |maybe_panel| {
            if (maybe_panel != null) return true;
        }
        for (self.geometry_shaded_panels) |maybe_panel| {
            if (maybe_panel != null) return true;
        }
        for (self.geometry_panels) |maybe_panel| {
            if (maybe_panel != null) return true;
        }
        for (self.geometry_displays) |maybe_display| {
            if (maybe_display != null) return true;
        }
        return false;
    }

    fn cachedPhysicalSnapshotAlloc(self: *Session, allocator: std.mem.Allocator) ![]u8 {
        for (self.geometry_lit_panels) |maybe_panel| {
            if (maybe_panel) |panel| return panel.textAlloc(allocator);
        }
        for (self.geometry_shaded_panels) |maybe_panel| {
            if (maybe_panel) |panel| return panel.textAlloc(allocator);
        }
        for (self.geometry_panels) |maybe_panel| {
            if (maybe_panel) |panel| return panel.textAlloc(allocator);
        }
        for (self.geometry_displays) |maybe_display| {
            if (maybe_display) |display| switch (display) {
                .ascii_strip => |ascii| return ascii.textAlloc(allocator),
                else => {},
            };
        }
        return error.MissingPhysicalRenderTarget;
    }

    fn livePhysicalRenderTarget(
        self: *Session,
        scratch_allocator: std.mem.Allocator,
    ) !?PhysicalRenderTarget {
        for (self.scene_specs) |maybe_scene_spec| {
            const scene_spec = maybe_scene_spec orelse continue;
            if (!scene_spec.hasPhysicalInputs()) continue;
            if (try self.scenePhysicalRenderTarget(scratch_allocator, scene_spec)) |target| {
                return target;
            }
        }
        return null;
    }

    fn scenePhysicalRenderTarget(
        self: *Session,
        scratch_allocator: std.mem.Allocator,
        scene_spec: physical.SceneSpec,
    ) !?PhysicalRenderTarget {
        const geometry_node = scene_spec.geometry orelse return null;
        const plan = physical.geometryPlanFromNode(&self.flow, geometry_node);
        var primitive: ?physical.GeometryPrimitive = null;

        switch (try self.executeGeometryPlan(scratch_allocator, plan, null)) {
            .cut => |cut| primitive = physical.primitiveFromGeometryResult(.{ .cut = cut }),
            .none, .unresolved => {},
        }

        if (primitive == null) {
            const geometry_value = try self.evalNode(scratch_allocator, geometry_node, null);
            primitive = themeGeometryPrimitiveFromValue(geometry_value);
        }

        const resolved_primitive = primitive orelse return null;
        const raster = physical.rasterFromGeometryPrimitive(resolved_primitive);
        const display = physical.displayFromGeometryRaster(raster);

        if (physical.shadedStripFromGeometryRaster(raster)) |shaded| {
            const panel = physical.cavityPanelFromShadedStrip(shaded);
            const shaded_panel = physical.shadedPanelFromCavityPanel(panel);
            const lighting = if (scene_spec.lights) |lights_node|
                panelLightingFromValue(self, try self.evalNode(scratch_allocator, lights_node, null))
            else
                null;
            const material = panelMaterialFromValues(
                self,
                if (scene_spec.materials) |materials_node| try self.evalNode(scratch_allocator, materials_node, null) else null,
                if (scene_spec.colors) |colors_node| try self.evalNode(scratch_allocator, colors_node, null) else null,
            );
            if (lighting != null or material != null) {
                const lighting_summary = lighting orelse physical.PanelLighting{
                    .light_count = 0,
                    .ambient_intensity = 0,
                    .peak_intensity = 0,
                };
                const lit_panel = physical.litPanelFromShadedPanel(shaded_panel, lighting_summary, material);
                return .{ .lit_panel = lit_panel };
            }
            return .{ .shaded_panel = shaded_panel };
        }

        return switch (display) {
            .ascii_strip => |ascii| .{ .ascii_strip = ascii },
            else => null,
        };
    }

    pub fn controlsAlloc(self: *Session, allocator: std.mem.Allocator) anyerror![]u8 {
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();

        var summary: ControlSummary = .{};
        defer summary.deinit(scratch.allocator());
        try self.populateControlSummary(scratch.allocator(), &summary);

        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);
        try output.appendSlice(allocator, "controls\n");
        try appendControlSection(&output, allocator, "click", summary.clicks.items);
        try appendControlSection(&output, allocator, "dblclick", summary.double_clicks.items);
        try appendControlSection(&output, allocator, "text", summary.text_inputs.items);
        try appendControlSection(&output, allocator, "select", summary.selects.items);
        try appendControlSection(&output, allocator, "hover", summary.hovers.items);
        return try output.toOwnedSlice(allocator);
    }

    pub fn traceAlloc(self: *Session, allocator: std.mem.Allocator) ![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);

        for (self.trace_lines.items, 0..) |line, index| {
            if (index != 0) try output.append(allocator, '\n');
            try output.appendSlice(allocator, line);
        }
        return try output.toOwnedSlice(allocator);
    }

    pub fn rootKind(self: *Session) enum { document, scene, terminal, unknown } {
        const root_binding = self.flow.root_binding orelse return .unknown;
        const name = self.flow.bindings[root_binding].name;
        if (std.mem.eql(u8, name, "terminal")) return .terminal;
        if (std.mem.eql(u8, name, "scene")) return .scene;
        if (std.mem.eql(u8, name, "document")) return .document;
        return .unknown;
    }

    pub fn triggerLink(self: *Session, link: flow_ir.NodeId) !void {
        return self.triggerLinkWithScope(link, null);
    }

    pub fn triggerLinkWithScope(self: *Session, link: flow_ir.NodeId, scope: ?*const EvalScope) !void {
        try self.logf("external link n{d}", .{link});
        try self.enqueueExternalNodePulse(link, scope);
    }

    pub fn terminalContractView(self: *Session) !?*const TerminalContract {
        if (self.rootKind() != .terminal) return null;
        try self.flushPendingQueue();
        if (self.cached_terminal_contract) |contract| return contract;

        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const value = try self.evalNode(self.arena.allocator(), self.flow.bindings[root_binding].node, null);
        const terminal = switch (value) {
            .terminal => |terminal| terminal,
            else => return error.ExpectedTerminalRoot,
        };

        var frame = EvalFrame{ .parent = self.current_eval_frame };
        self.current_eval_frame = &frame;
        defer {
            self.current_eval_frame = frame.parent;
            frame.deps.deinit(self.backing_allocator);
        }

        const contract = try self.memo_arena.allocator().create(TerminalContract);
        contract.* = try terminalContractFromValue(self, self.memo_arena.allocator(), terminal);
        const deps = try self.backing_allocator.alloc(ScopedNodeKey, frame.deps.items.len);
        @memcpy(deps, frame.deps.items);
        if (self.cached_terminal_contract_deps) |old_deps| self.backing_allocator.free(old_deps);
        self.cached_terminal_contract_deps = deps;
        self.cached_terminal_contract = contract;
        return contract;
    }

    pub fn terminalContractAlloc(self: *Session, allocator: std.mem.Allocator) !?TerminalContract {
        const contract = (try self.terminalContractView()) orelse return null;
        return try cloneTerminalContract(allocator, contract.*);
    }

    pub fn terminalHitRegionsView(self: *Session) !?[]const TerminalHitRegion {
        if (self.rootKind() != .terminal) return null;
        try self.flushPendingQueue();
        if (self.cached_terminal_hit_regions) |regions| return regions;

        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const value = try self.evalNode(self.arena.allocator(), self.flow.bindings[root_binding].node, null);
        const terminal = switch (value) {
            .terminal => |terminal| terminal,
            else => return error.ExpectedTerminalRoot,
        };

        var regions: std.ArrayList(TerminalHitRegion) = .empty;
        defer regions.deinit(self.memo_arena.allocator());
        var counters = TerminalLayoutCounters{};
        _ = try self.collectTerminalHitRegions(self.memo_arena.allocator(), &regions, &counters, terminal.root, 0, 0);
        const owned = try regions.toOwnedSlice(self.memo_arena.allocator());
        self.cached_terminal_hit_regions = owned;
        return owned;
    }

    pub fn terminalHitRegionsAlloc(self: *Session, allocator: std.mem.Allocator) !?[]TerminalHitRegion {
        const regions = (try self.terminalHitRegionsView()) orelse return null;
        return try allocator.dupe(TerminalHitRegion, regions);
    }

    pub fn clickButtonByLabel(self: *Session, allocator: std.mem.Allocator, label: []const u8) !void {
        return self.clickButton(try self.controlIndexByLabel(allocator, .click, label));
    }

    pub fn doubleClickLabelByText(self: *Session, allocator: std.mem.Allocator, label: []const u8) !void {
        return self.doubleClickLabel(try self.controlIndexByLabel(allocator, .double_click, label));
    }

    pub fn setHoverByLabel(self: *Session, allocator: std.mem.Allocator, label: []const u8, hovered: bool) !void {
        return self.setHover(try self.controlIndexByLabel(allocator, .hover, label), hovered);
    }

    pub fn setFirstTextInputValue(self: *Session, allocator: std.mem.Allocator, text: []const u8) !void {
        return self.setTextInputValue(try self.firstControlIndex(allocator, .text_input), text);
    }

    pub fn pressFirstTextInputKey(self: *Session, allocator: std.mem.Allocator, key: []const u8) !void {
        return self.pressTextInputKey(try self.firstControlIndex(allocator, .text_input), key);
    }

    pub fn focusFirstTextInput(self: *Session, allocator: std.mem.Allocator) !void {
        return self.focusTextInput(try self.firstControlIndex(allocator, .text_input));
    }

    pub fn blurFirstTextInput(self: *Session, allocator: std.mem.Allocator) !void {
        return self.blurTextInput(try self.firstControlIndex(allocator, .text_input));
    }

    pub fn textInputCountAlloc(self: *Session, allocator: std.mem.Allocator) !usize {
        _ = allocator;
        return (try self.textInputValuesView()).len;
    }

    pub fn textInputTextAlloc(self: *Session, allocator: std.mem.Allocator, index: usize) ![]u8 {
        const value = try self.currentTextInputValue(index);
        return try allocator.dupe(u8, try valueAsText(value));
    }

    pub fn clickButton(self: *Session, index: usize) !void {
        const event = try self.buttonLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.logf("external click button[{d}] -> n{d}", .{ index, event.link });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn setSliderValue(self: *Session, index: usize, value: f64) !void {
        const event = try self.sliderLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, .{ .number = value });
        try self.logf("external slider[{d}] -> n{d} = {d}", .{ index, event.link, value });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn setTextInputValue(self: *Session, index: usize, text: []const u8) !void {
        const event = try self.textInputLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, .{ .text = try self.arena.allocator().dupe(u8, text) });
        try self.logf("external text_input[{d}] -> n{d} = {s}", .{ index, event.link, text });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn setSelectValue(self: *Session, index: usize, text: []const u8) !void {
        const event = try self.selectLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, .{ .text = try self.arena.allocator().dupe(u8, text) });
        try self.logf("external select[{d}] -> n{d} = {s}", .{ index, event.link, text });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn pressTextInputKey(self: *Session, index: usize, key: []const u8) !void {
        const event = try self.textInputKeyLinkAt(index);
        const change_event = try self.textInputLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        const change_scope = canonicalControlScope(change_event.scope);
        const current_text = self.getLinkValue(change_event.link, change_scope) orelse try self.currentTextInputValue(index);
        try self.setLinkValue(event.link, scope, current_text);
        try self.setLinkKeyValue(event.link, scope, .{ .symbol = try self.arena.allocator().dupe(u8, key) });
        try self.logf("external text_input_key[{d}] -> n{d} = {s}", .{ index, event.link, key });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn focusTextInput(self: *Session, index: usize) !void {
        const event = try self.textInputFocusLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.logf("external text_input_focus[{d}] -> n{d}", .{ index, event.link });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn blurTextInput(self: *Session, index: usize) !void {
        const event = try self.textInputBlurLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.logf("external text_input_blur[{d}] -> n{d}", .{ index, event.link });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn doubleClickLabel(self: *Session, index: usize) !void {
        const event = try self.labelDoubleClickLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        if (event.scope) |frame| {
            try self.logf(
                "external label_double_click[{d}] -> n{d} scope={d}:{s} parent={?d}:{?s} grand={?d}:{?s} canonical={?d}:{?s}",
                .{
                    index,
                    event.link,
                    frame.id,
                    if (frame.bindings.len != 0) frame.bindings[0].name else "",
                    if (frame.parent) |parent| parent.id else null,
                    if (frame.parent) |parent| if (parent.bindings.len != 0) parent.bindings[0].name else "" else null,
                    if (frame.parent) |parent| if (parent.parent) |grand| grand.id else null else null,
                    if (frame.parent) |parent| if (parent.parent) |grand| if (grand.bindings.len != 0) grand.bindings[0].name else "" else null else null,
                    if (scope) |canonical| canonical.id else null,
                    if (scope) |canonical| if (canonical.bindings.len != 0) canonical.bindings[0].name else "" else null,
                },
            );
        } else {
            try self.logf("external label_double_click[{d}] -> n{d}", .{ index, event.link });
        }
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn setHover(self: *Session, index: usize, hovered: bool) !void {
        const event = try self.hoverLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, booleanValue(hovered));
        try self.logf("external hover[{d}] -> n{d} = {s}", .{ index, event.link, if (hovered) "True" else "False" });
        try self.enqueueExternalNodePulse(event.link, scope);
    }

    pub fn advanceTime(self: *Session, delta_ms: u64) !void {
        const target_time = self.current_time_ms + delta_ms;
        while (true) {
            var next_fire: ?u64 = null;
            for (self.timer_next_fire_ms, self.timer_period_ms) |fire_at, period| {
                if (period == 0 or fire_at == 0 or fire_at > target_time) continue;
                if (next_fire == null or fire_at < next_fire.?) next_fire = fire_at;
            }
            const firing_time = next_fire orelse break;
            self.current_time_ms = firing_time;
            for (self.timer_next_fire_ms, self.timer_period_ms, 0..) |*fire_at, period, index_usize| {
                if (period == 0 or fire_at.* != firing_time) continue;
                const node_id: flow_ir.NodeId = @intCast(index_usize);
                try self.logf("timer n{d} fired at {d}ms", .{ node_id, firing_time });
                try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
                fire_at.* += period;
            }
            try self.processQueue();
        }
        self.current_time_ms = target_time;
    }

    fn enqueueExternalNodePulse(self: *Session, source: flow_ir.NodeId, scope: ?*const EvalScope) !void {
        try self.queue.append(self.arena.allocator(), .{
            .source = source,
            .payload = .{ .node = source },
            .scope = scope,
        });
        try self.processQueue();
    }

    fn init(self: *Session) !void {
        const allocator = self.arena.allocator();
        const node_count = self.flow.nodes.len;

        self.latest_values = try allocator.alloc(?PulsePayload, node_count);
        for (self.latest_values) |*slot| slot.* = null;

        self.runtime_subscribers = try allocator.alloc(bool, node_count);
        @memset(self.runtime_subscribers, false);

        self.hold_values = try allocator.alloc(Value, node_count);
        for (self.hold_values) |*slot| slot.* = .none;

        self.hold_inited = try allocator.alloc(bool, node_count);
        @memset(self.hold_inited, false);

        self.link_values = try allocator.alloc(Value, node_count);
        for (self.link_values) |*slot| slot.* = .none;

        self.link_inited = try allocator.alloc(bool, node_count);
        @memset(self.link_inited, false);

        self.link_key_values = try allocator.alloc(Value, node_count);
        for (self.link_key_values) |*slot| slot.* = .none;

        self.link_key_inited = try allocator.alloc(bool, node_count);
        @memset(self.link_key_inited, false);

        self.list_values = try allocator.alloc(Value, node_count);
        for (self.list_values) |*slot| slot.* = .none;

        self.list_inited = try allocator.alloc(bool, node_count);
        @memset(self.list_inited, false);

        self.list_remove_tombstones = try allocator.alloc([]Value, node_count);
        for (self.list_remove_tombstones) |*slot| slot.* = &.{};

        self.skip_values = try allocator.alloc(Value, node_count);
        for (self.skip_values) |*slot| slot.* = .none;

        self.skip_inited = try allocator.alloc(bool, node_count);
        @memset(self.skip_inited, false);

        self.skip_seen = try allocator.alloc(u64, node_count);
        @memset(self.skip_seen, 0);

        self.sum_values = try allocator.alloc(f64, node_count);
        @memset(self.sum_values, 0);

        self.sum_inited = try allocator.alloc(bool, node_count);
        @memset(self.sum_inited, false);

        self.timer_period_ms = try allocator.alloc(u64, node_count);
        @memset(self.timer_period_ms, 0);

        self.timer_next_fire_ms = try allocator.alloc(u64, node_count);
        @memset(self.timer_next_fire_ms, 0);

        self.scene_specs = try allocator.alloc(?physical.SceneSpec, node_count);
        for (self.scene_specs) |*slot| slot.* = null;

        self.geometry_plans = try allocator.alloc(?physical.GeometryPlan, node_count);
        for (self.geometry_plans) |*slot| slot.* = null;

        self.geometry_results = try allocator.alloc(?physical.GeometryResult, node_count);
        for (self.geometry_results) |*slot| slot.* = null;

        self.geometry_primitives = try allocator.alloc(?physical.GeometryPrimitive, node_count);
        for (self.geometry_primitives) |*slot| slot.* = null;

        self.geometry_rasters = try allocator.alloc(?physical.GeometryRaster, node_count);
        for (self.geometry_rasters) |*slot| slot.* = null;

        self.geometry_displays = try allocator.alloc(?physical.GeometryDisplay, node_count);
        for (self.geometry_displays) |*slot| slot.* = null;

        self.geometry_shaded_strips = try allocator.alloc(?physical.ShadedStrip, node_count);
        for (self.geometry_shaded_strips) |*slot| slot.* = null;

        self.geometry_panels = try allocator.alloc(?physical.CavityPanel, node_count);
        for (self.geometry_panels) |*slot| slot.* = null;

        self.geometry_shaded_panels = try allocator.alloc(?physical.ShadedPanel, node_count);
        for (self.geometry_shaded_panels) |*slot| slot.* = null;

        self.geometry_lit_panels = try allocator.alloc(?physical.LitPanel, node_count);
        for (self.geometry_lit_panels) |*slot| slot.* = null;

        self.pending_physical_features = try allocator.alloc(?physical.PendingFeatureUse, node_count);
        for (self.pending_physical_features) |*slot| slot.* = null;

        self.persist_ids = try allocator.alloc(u64, node_count);
        @memset(self.persist_ids, 0);

        self.node_scope_state = try allocator.alloc(u8, node_count);
        @memset(self.node_scope_state, 0);

        try self.computePersistIds();
        try self.loadPersistedState();

        try self.buildSubscribers();

        for (self.flow.nodes, 0..) |node, index_usize| {
            const index: flow_ir.NodeId = @intCast(index_usize);
            switch (node.kind) {
                .latest => |latest| {
                    const initial_node = latest.initial orelse self.latestImplicitInitialSource(latest);
                    self.latest_values[index] = if (initial_node) |initial| .{ .node = initial } else null;
                    if (initial_node) |initial| {
                        try self.logf("init latest n{d} <- n{d}", .{ index, initial });
                    } else {
                        try self.logf("init latest n{d} <- <none>", .{index});
                    }
                },
                .hold => |hold| {
                    if (!self.nodeNeedsScope(index) and !self.hold_inited[index]) {
                        self.hold_values[index] = try self.evalNode(allocator, hold.initial, null);
                        self.hold_inited[index] = true;
                        try self.logf("init hold n{d}", .{index});
                    } else if (self.hold_inited[index]) {
                        try self.logf("restore hold n{d}", .{index});
                    }
                },
                .builtin_call => |call| {
                    if (physical.sceneSpecFromBuiltin(index, call)) |scene_spec| {
                        self.scene_specs[index] = scene_spec;
                        if (scene_spec.hasPhysicalInputs()) {
                            try self.logf("physical scene n{d} root=n{d}", .{ index, scene_spec.root });
                        }
                        if (scene_spec.geometry) |geometry_node| {
                            const plan = physical.geometryPlanFromNode(&self.flow, geometry_node);
                            self.geometry_plans[index] = plan;
                            switch (plan) {
                                .model_cut => |cut| {
                                    try self.logf(
                                        "physical geometry n{d} cut from=n{d} remove=n{d}",
                                        .{ index, cut.from, cut.remove },
                                    );
                                    const result = try self.executeGeometryPlan(allocator, plan, null);
                                    self.geometry_results[index] = result;
                                    switch (result) {
                                        .cut => |cut_result| {
                                            const summary = try cut_result.formatAlloc(allocator);
                                            defer allocator.free(summary);
                                            try self.logf("physical result n{d} {s}", .{ index, summary });
                                        },
                                        else => try self.logf("physical result n{d} {s}", .{ index, result.label() }),
                                    }
                                    const primitive = physical.primitiveFromGeometryResult(result);
                                    self.geometry_primitives[index] = primitive;
                                    switch (primitive) {
                                        .cavity_rect => |cavity| {
                                            const summary = try cavity.formatAlloc(allocator);
                                            defer allocator.free(summary);
                                            try self.logf("physical primitive n{d} {s}", .{ index, summary });
                                        },
                                        else => try self.logf("physical primitive n{d} {s}", .{ index, primitive.label() }),
                                    }
                                    const raster = physical.rasterFromGeometryPrimitive(primitive);
                                    self.geometry_rasters[index] = raster;
                                    switch (raster) {
                                        .depth_strip => |strip| {
                                            const summary = try strip.formatAlloc(allocator);
                                            defer allocator.free(summary);
                                            try self.logf("physical raster n{d} {s}", .{ index, summary });
                                        },
                                        else => try self.logf("physical raster n{d} {s}", .{ index, raster.label() }),
                                    }
                                    const display = physical.displayFromGeometryRaster(raster);
                                    self.geometry_displays[index] = display;
                                    switch (display) {
                                        .ascii_strip => |ascii| {
                                            const summary = try ascii.formatAlloc(allocator);
                                            defer allocator.free(summary);
                                            try self.logf("physical display n{d} {s}", .{ index, summary });
                                        },
                                        else => try self.logf("physical display n{d} {s}", .{ index, display.label() }),
                                    }
                                    if (physical.shadedStripFromGeometryRaster(raster)) |shaded| {
                                        self.geometry_shaded_strips[index] = shaded;
                                        const summary = try shaded.formatAlloc(allocator);
                                        defer allocator.free(summary);
                                        try self.logf("physical shaded n{d} {s}", .{ index, summary });
                                        const panel = physical.cavityPanelFromShadedStrip(shaded);
                                        self.geometry_panels[index] = panel;
                                        const panel_summary = try panel.formatAlloc(allocator);
                                        defer allocator.free(panel_summary);
                                        try self.logf("physical panel n{d} {s}", .{ index, panel_summary });
                                        const shaded_panel = physical.shadedPanelFromCavityPanel(panel);
                                        self.geometry_shaded_panels[index] = shaded_panel;
                                        const shaded_panel_summary = try shaded_panel.formatAlloc(allocator);
                                        defer allocator.free(shaded_panel_summary);
                                        try self.logf("physical shaded_panel n{d} {s}", .{ index, shaded_panel_summary });
                                        const lighting = if (scene_spec.lights) |lights_node|
                                            panelLightingFromValue(self, try self.evalNode(allocator, lights_node, null))
                                        else
                                            null;
                                        const material = panelMaterialFromValues(
                                            self,
                                            if (scene_spec.materials) |materials_node| try self.evalNode(allocator, materials_node, null) else null,
                                            if (scene_spec.colors) |colors_node| try self.evalNode(allocator, colors_node, null) else null,
                                        );
                                        if (lighting != null or material != null) {
                                            const lighting_summary = lighting orelse physical.PanelLighting{
                                                .light_count = 0,
                                                .ambient_intensity = 0,
                                                .peak_intensity = 0,
                                            };
                                            const lit_panel = physical.litPanelFromShadedPanel(shaded_panel, lighting_summary, material);
                                            self.geometry_lit_panels[index] = lit_panel;
                                            const lit_panel_summary = try lit_panel.formatAlloc(allocator);
                                            defer allocator.free(lit_panel_summary);
                                            try self.logf(
                                                "physical lit_panel n{d} lights={d} ambient={d} peak={d} gloss={d} metal={d} glow={d} tone={s}\n{s}",
                                                .{
                                                    index,
                                                    lighting_summary.light_count,
                                                    lighting_summary.ambient_intensity,
                                                    lighting_summary.peak_intensity,
                                                    if (material) |surface| surface.gloss else 0,
                                                    if (material) |surface| surface.metal else 0,
                                                    if (material) |surface| surface.glow_intensity else 0,
                                                    if (material) |surface| surface.tone.label() else physical.PanelTone.neutral.label(),
                                                    lit_panel_summary,
                                                },
                                            );
                                        }
                                    }
                                },
                                else => try self.logf("physical geometry n{d} {s}", .{ index, plan.label() }),
                            }
                            if (self.geometry_primitives[index] == null) {
                                const geometry_value = try self.evalNode(allocator, geometry_node, null);
                                if (themeGeometryPrimitiveFromValue(geometry_value)) |primitive| {
                                    self.geometry_primitives[index] = primitive;
                                    switch (primitive) {
                                        .cavity_rect => |cavity| {
                                            const summary = try cavity.formatAlloc(allocator);
                                            defer allocator.free(summary);
                                            try self.logf("physical primitive n{d} {s}", .{ index, summary });
                                        },
                                        else => try self.logf("physical primitive n{d} {s}", .{ index, primitive.label() }),
                                    }
                                    const raster = physical.rasterFromGeometryPrimitive(primitive);
                                    self.geometry_rasters[index] = raster;
                                    switch (raster) {
                                        .depth_strip => |strip| {
                                            const summary = try strip.formatAlloc(allocator);
                                            defer allocator.free(summary);
                                            try self.logf("physical raster n{d} {s}", .{ index, summary });
                                        },
                                        else => try self.logf("physical raster n{d} {s}", .{ index, raster.label() }),
                                    }
                                    const display = physical.displayFromGeometryRaster(raster);
                                    self.geometry_displays[index] = display;
                                    switch (display) {
                                        .ascii_strip => |ascii| {
                                            const summary = try ascii.formatAlloc(allocator);
                                            defer allocator.free(summary);
                                            try self.logf("physical display n{d} {s}", .{ index, summary });
                                        },
                                        else => try self.logf("physical display n{d} {s}", .{ index, display.label() }),
                                    }
                                    if (physical.shadedStripFromGeometryRaster(raster)) |shaded| {
                                        self.geometry_shaded_strips[index] = shaded;
                                        const summary = try shaded.formatAlloc(allocator);
                                        defer allocator.free(summary);
                                        try self.logf("physical shaded n{d} {s}", .{ index, summary });
                                        const panel = physical.cavityPanelFromShadedStrip(shaded);
                                        self.geometry_panels[index] = panel;
                                        const panel_summary = try panel.formatAlloc(allocator);
                                        defer allocator.free(panel_summary);
                                        try self.logf("physical panel n{d} {s}", .{ index, panel_summary });
                                        const shaded_panel = physical.shadedPanelFromCavityPanel(panel);
                                        self.geometry_shaded_panels[index] = shaded_panel;
                                        const shaded_panel_summary = try shaded_panel.formatAlloc(allocator);
                                        defer allocator.free(shaded_panel_summary);
                                        try self.logf("physical shaded_panel n{d} {s}", .{ index, shaded_panel_summary });
                                        const lighting = if (scene_spec.lights) |lights_node|
                                            panelLightingFromValue(self, try self.evalNode(allocator, lights_node, null))
                                        else
                                            null;
                                        const material = panelMaterialFromValues(
                                            self,
                                            if (scene_spec.materials) |materials_node| try self.evalNode(allocator, materials_node, null) else null,
                                            if (scene_spec.colors) |colors_node| try self.evalNode(allocator, colors_node, null) else null,
                                        );
                                        if (lighting != null or material != null) {
                                            const lighting_summary = lighting orelse physical.PanelLighting{
                                                .light_count = 0,
                                                .ambient_intensity = 0,
                                                .peak_intensity = 0,
                                            };
                                            const lit_panel = physical.litPanelFromShadedPanel(shaded_panel, lighting_summary, material);
                                            self.geometry_lit_panels[index] = lit_panel;
                                            const lit_panel_summary = try lit_panel.formatAlloc(allocator);
                                            defer allocator.free(lit_panel_summary);
                                            try self.logf(
                                                "physical lit_panel n{d} lights={d} ambient={d} peak={d} gloss={d} metal={d} glow={d} tone={s}\n{s}",
                                                .{
                                                    index,
                                                    lighting_summary.light_count,
                                                    lighting_summary.ambient_intensity,
                                                    lighting_summary.peak_intensity,
                                                    if (material) |surface| surface.gloss else 0,
                                                    if (material) |surface| surface.metal else 0,
                                                    if (material) |surface| surface.glow_intensity else 0,
                                                    if (material) |surface| surface.tone.label() else physical.PanelTone.neutral.label(),
                                                    lit_panel_summary,
                                                },
                                            );
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (physical.pendingFeatureFromBuiltin(index, call)) |feature| {
                        self.pending_physical_features[index] = feature;
                        try self.logf("physical pending n{d} {s}", .{ index, feature.feature.label() });
                    }
                    if (std.mem.eql(u8, call.path, "Stream/pulses")) {
                        if (!self.nodeNeedsScope(index)) {
                            try self.emitPulses(index, call, null);
                        } else {
                            try self.logf("defer scoped pulses n{d}", .{index});
                        }
                    }
                    if (std.mem.eql(u8, call.path, "Stream/skip")) {
                        if (!self.nodeNeedsScope(index)) {
                            try self.initSkipNode(allocator, index, call, null);
                        } else {
                            try self.logf("defer scoped skip n{d}", .{index});
                        }
                    }
                    if (std.mem.eql(u8, call.path, "List/append")) {
                        if (!self.nodeNeedsScope(index)) try self.initListAppendNode(allocator, index, call);
                    }
                    if (std.mem.eql(u8, call.path, "List/clear")) {
                        if (!self.nodeNeedsScope(index)) try self.initListClearNode(allocator, index, call);
                    }
                    if (std.mem.eql(u8, call.path, "List/remove")) {
                        try self.initListRemoveNode(allocator, index, call);
                    }
                    if (std.mem.eql(u8, call.path, "List/remove_last")) {
                        try self.initListRemoveLastNode(allocator, index, call);
                    }
                    if (std.mem.eql(u8, call.path, "Timer/interval")) {
                        if (!self.nodeNeedsScope(index)) {
                            const period_ms = try self.durationMsFromCall(call, null);
                            self.timer_period_ms[index] = period_ms;
                            self.timer_next_fire_ms[index] = period_ms;
                            try self.logf("init timer n{d} every {d}ms", .{ index, period_ms });
                        } else {
                            try self.logf("defer scoped timer n{d}", .{index});
                        }
                    }
                    if (std.mem.eql(u8, call.path, "Math/sum") and call.positional.len != 0) {
                        if (self.sum_inited[index]) {
                            try self.logf("restore sum n{d} = {d}", .{ index, self.sum_values[index] });
                        } else if (try self.initialNumericValue(call.positional[0])) |value| {
                            self.sum_values[index] = value;
                            self.sum_inited[index] = true;
                            self.invalidateEvalCacheForDependency(.{ .node_id = index, .scope_id = 0 });
                            try self.logf("init sum n{d} = {d}", .{ index, value });
                        } else {
                            try self.logf("init sum n{d} = <empty>", .{index});
                        }
                    }
                    if (std.mem.eql(u8, call.path, "Router/go_to")) {
                        try self.logf("init router route={s}", .{try valueAsText(self.route_value)});
                    }
                },
                else => {},
            }
        }

        if (self.queue.items.len != 0) try self.processQueue();
        try self.savePersistedState();
    }

    fn executeGeometryPlan(
        self: *Session,
        allocator: std.mem.Allocator,
        plan: physical.GeometryPlan,
        scope: ?*const EvalScope,
    ) anyerror!physical.GeometryResult {
        return switch (plan) {
            .none => .none,
            .unresolved_builtin => |label| .{ .unresolved = label },
            .unresolved_user_call => |label| .{ .unresolved = label },
            .unresolved_node_kind => |label| .{ .unresolved = label },
            .model_cut => |cut| .{ .cut = physical.cutResultFromOperands(
                try self.geometryOperandSummary(allocator, try self.evalNode(allocator, cut.from, scope)),
                try self.geometryOperandSummary(allocator, try self.evalNode(allocator, cut.remove, scope)),
            ) },
        };
    }

    fn geometryOperandSummary(
        self: *Session,
        allocator: std.mem.Allocator,
        value: Value,
    ) anyerror!physical.OperandSummary {
        _ = self;
        return switch (value) {
            .record => |fields| .{
                .kind = "record",
                .shape = try duplicateOptionalRecordText(allocator, findRecordValue(fields, "shape")),
                .depth = optionalRecordNumber(findRecordValue(fields, "depth")),
                .wall = optionalRecordNumber(findRecordValue(fields, "wall")),
            },
            .symbol => |symbol| .{ .kind = try allocator.dupe(u8, symbol) },
            .text => |text| .{ .kind = try allocator.dupe(u8, text) },
            .number => |number| .{ .kind = try std.fmt.allocPrint(allocator, "number({d})", .{number}) },
            else => .{ .kind = @tagName(value) },
        };
    }

    fn buildSubscribers(self: *Session) !void {
        const allocator = self.arena.allocator();
        const node_count = self.flow.nodes.len;
        const counts = try allocator.alloc(usize, node_count);
        @memset(counts, 0);

        for (self.flow.nodes, 0..) |node, index_usize| {
            const subscriber: flow_ir.NodeId = @intCast(index_usize);
            switch (node.kind) {
                .then_value => |then_value| {
                    if (self.nodeNeedsScope(then_value.source)) {
                        self.runtime_subscribers[subscriber] = true;
                        continue;
                    }
                    const source = self.eventDependencySource(then_value.source) catch |err| switch (err) {
                        error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                        else => return err,
                    };
                    counts[source] += 1;
                },
                .latest => |latest| {
                    for (latest.sources) |source_node| {
                        if (self.nodeNeedsScope(source_node)) {
                            self.runtime_subscribers[subscriber] = true;
                            continue;
                        }
                        const source = self.eventDependencySource(source_node) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                            else => return err,
                        };
                        counts[source] += 1;
                    }
                },
                .hold => |hold| {
                    for (hold.updates) |update| {
                        if (self.nodeNeedsScope(update)) {
                            self.runtime_subscribers[subscriber] = true;
                            continue;
                        }
                        const source = self.holdTriggerSource(update) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                            else => return err,
                        };
                        counts[source] += 1;
                    }
                },
                .linked_value => |linked| {
                    if (self.nodeNeedsScope(linked.value)) {
                        self.runtime_subscribers[subscriber] = true;
                        continue;
                    }
                    const source = self.linkedValueTriggerSource(linked.value) catch |err| switch (err) {
                        error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                        else => return err,
                    };
                    counts[source] += 1;
                },
                .builtin_call => |call| {
                    if (std.mem.eql(u8, call.path, "Stream/pulses") and call.positional.len != 0) {
                        if (self.nodeNeedsScope(call.positional[0])) {
                            self.runtime_subscribers[subscriber] = true;
                        } else {
                            const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                                error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                                else => return err,
                            };
                            counts[source] += 1;
                        }
                    }
                    if (std.mem.eql(u8, call.path, "Stream/skip") and call.positional.len != 0) {
                        if (self.nodeNeedsScope(call.positional[0])) {
                            self.runtime_subscribers[subscriber] = true;
                        } else {
                            const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                                error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                                else => return err,
                            };
                            counts[source] += 1;
                        }
                    }
                    if (std.mem.eql(u8, call.path, "Math/sum") and call.positional.len != 0) {
                        if (self.nodeNeedsScope(call.positional[0])) {
                            self.runtime_subscribers[subscriber] = true;
                        } else {
                            const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                                error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                                else => return err,
                            };
                            counts[source] += 1;
                        }
                    }
                    if (std.mem.eql(u8, call.path, "List/append") and !self.nodeNeedsScope(subscriber)) {
                        if (call.positional.len != 0) counts[try self.listSourceDependency(call.positional[0])] += 1;
                        if (findNamed(call.named, "item")) |item_node| {
                            if (self.nodeNeedsScope(item_node)) {
                                self.runtime_subscribers[subscriber] = true;
                            } else {
                                counts[try self.valueTriggerSource(item_node)] += 1;
                            }
                        } else if (findNamed(call.named, "on")) |on_node| {
                            if (self.nodeNeedsScope(on_node)) {
                                self.runtime_subscribers[subscriber] = true;
                            } else {
                                counts[try self.valueTriggerSource(on_node)] += 1;
                            }
                        } else {
                            return error.MissingArgument;
                        }
                    }
                    if (std.mem.eql(u8, call.path, "List/clear") and !self.nodeNeedsScope(subscriber)) {
                        if (call.positional.len != 0) counts[try self.listSourceDependency(call.positional[0])] += 1;
                        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                        if (self.nodeNeedsScope(on_node)) {
                            self.runtime_subscribers[subscriber] = true;
                        } else {
                            counts[try self.valueTriggerSource(on_node)] += 1;
                        }
                    }
                    if (std.mem.eql(u8, call.path, "List/remove_last")) {
                        if (call.positional.len != 0) counts[try self.listSourceDependency(call.positional[0])] += 1;
                        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                        if (self.nodeNeedsScope(on_node)) {
                            self.runtime_subscribers[subscriber] = true;
                        } else {
                            counts[try self.valueTriggerSource(on_node)] += 1;
                        }
                    }
                    if (std.mem.eql(u8, call.path, "Router/go_to") and call.positional.len != 0) {
                        if (self.nodeNeedsScope(call.positional[0])) {
                            self.runtime_subscribers[subscriber] = true;
                        } else {
                            counts[try self.eventDependencySource(call.positional[0])] += 1;
                        }
                    }
                },
                else => {},
            }
        }

        self.subscribers = try allocator.alloc([]flow_ir.NodeId, node_count);
        for (counts, 0..) |count, index| {
            self.subscribers[index] = try allocator.alloc(flow_ir.NodeId, count);
        }

        const filled = try allocator.alloc(usize, node_count);
        @memset(filled, 0);

        for (self.flow.nodes, 0..) |node, index_usize| {
            const subscriber: flow_ir.NodeId = @intCast(index_usize);
            switch (node.kind) {
                .then_value => |then_value| {
                    if (self.nodeNeedsScope(then_value.source)) continue;
                    const source = self.eventDependencySource(then_value.source) catch |err| switch (err) {
                        error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                        else => return err,
                    };
                    try self.addSubscriber(source, subscriber, filled);
                },
                .latest => |latest| {
                    for (latest.sources) |source_node| {
                        if (self.nodeNeedsScope(source_node)) continue;
                        const source = self.eventDependencySource(source_node) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                            else => return err,
                        };
                        try self.addSubscriber(source, subscriber, filled);
                    }
                },
                .hold => |hold| {
                    for (hold.updates) |update| {
                        if (self.nodeNeedsScope(update)) continue;
                        const source = self.holdTriggerSource(update) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                            else => return err,
                        };
                        try self.addSubscriber(source, subscriber, filled);
                    }
                },
                .linked_value => |linked| {
                    if (self.nodeNeedsScope(linked.value)) continue;
                    const source = self.linkedValueTriggerSource(linked.value) catch |err| switch (err) {
                        error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                        else => return err,
                    };
                    try self.addSubscriber(source, subscriber, filled);
                },
                .builtin_call => |call| {
                    if (std.mem.eql(u8, call.path, "Stream/pulses") and call.positional.len != 0) {
                        if (self.nodeNeedsScope(call.positional[0])) continue;
                        const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                            else => return err,
                        };
                        try self.addSubscriber(source, subscriber, filled);
                    }
                    if (std.mem.eql(u8, call.path, "Stream/skip") and call.positional.len != 0) {
                        if (self.nodeNeedsScope(call.positional[0])) continue;
                        const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                            else => return err,
                        };
                        try self.addSubscriber(source, subscriber, filled);
                    }
                    if (std.mem.eql(u8, call.path, "Math/sum") and call.positional.len != 0) {
                        if (self.nodeNeedsScope(call.positional[0])) continue;
                        const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                            else => return err,
                        };
                        try self.addSubscriber(source, subscriber, filled);
                    }
                    if (std.mem.eql(u8, call.path, "List/append") and !self.nodeNeedsScope(subscriber)) {
                        if (call.positional.len != 0) try self.addSubscriber(try self.listSourceDependency(call.positional[0]), subscriber, filled);
                        if (findNamed(call.named, "item")) |item_node| {
                            if (!self.nodeNeedsScope(item_node)) {
                                try self.addSubscriber(try self.valueTriggerSource(item_node), subscriber, filled);
                            }
                        } else if (findNamed(call.named, "on")) |on_node| {
                            if (!self.nodeNeedsScope(on_node)) {
                                try self.addSubscriber(try self.valueTriggerSource(on_node), subscriber, filled);
                            }
                        } else {
                            return error.MissingArgument;
                        }
                    }
                    if (std.mem.eql(u8, call.path, "List/clear") and !self.nodeNeedsScope(subscriber)) {
                        if (call.positional.len != 0) try self.addSubscriber(try self.listSourceDependency(call.positional[0]), subscriber, filled);
                        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                        if (!self.nodeNeedsScope(on_node)) {
                            try self.addSubscriber(try self.valueTriggerSource(on_node), subscriber, filled);
                        }
                    }
                    if (std.mem.eql(u8, call.path, "List/remove_last")) {
                        if (call.positional.len != 0) try self.addSubscriber(try self.listSourceDependency(call.positional[0]), subscriber, filled);
                        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                        if (!self.nodeNeedsScope(on_node)) {
                            try self.addSubscriber(try self.valueTriggerSource(on_node), subscriber, filled);
                        }
                    }
                    if (std.mem.eql(u8, call.path, "Router/go_to") and call.positional.len != 0) {
                        if (!self.nodeNeedsScope(call.positional[0])) {
                            try self.addSubscriber(try self.eventDependencySource(call.positional[0]), subscriber, filled);
                        }
                    }
                },
                else => {},
            }
        }
    }

    fn addSubscriber(self: *Session, source: flow_ir.NodeId, subscriber: flow_ir.NodeId, filled: []usize) !void {
        const offset = filled[source];
        self.subscribers[source][offset] = subscriber;
        filled[source] += 1;
    }

    const BoundLocalFrame = struct {
        name: []const u8,
        parent: ?*const BoundLocalFrame,
    };

    fn isBoundLocal(frame: ?*const BoundLocalFrame, name: []const u8) bool {
        var current = frame;
        while (current) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return true;
            current = entry.parent;
        }
        return false;
    }

    fn nodeNeedsOuterScope(self: *Session, node_id: flow_ir.NodeId, bound: ?*const BoundLocalFrame) bool {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .number, .atom, .symbol, .link_port => false,
            .binding_ref => false,
            .local_ref => |name| !isBoundLocal(bound, name),
            .special => |special| switch (special) {
                .pass_ref, .passed_ref => true,
                else => false,
            },
            .access => |access| self.nodeNeedsOuterScope(access.target, bound),
            .binary => |binary| self.nodeNeedsOuterScope(binary.lhs, bound) or self.nodeNeedsOuterScope(binary.rhs, bound),
            .text => |parts| blk: {
                for (parts) |part| if (self.nodeNeedsOuterScope(part, bound)) break :blk true;
                break :blk false;
            },
            .list => |list| blk: {
                for (list.items) |item| if (self.nodeNeedsOuterScope(item, bound)) break :blk true;
                break :blk false;
            },
            .record => |fields| blk: {
                for (fields) |field| if (self.nodeNeedsOuterScope(field.value, bound)) break :blk true;
                break :blk false;
            },
            .block => |block| self.blockNeedsOuterScope(block, bound),
            .when => |when| blk: {
                if (self.nodeNeedsOuterScope(when.input, bound)) break :blk true;
                for (when.arms) |arm| {
                    if (self.nodeNeedsOuterScope(arm.pattern, bound) or self.nodeNeedsOuterScope(arm.result, bound)) break :blk true;
                }
                break :blk false;
            },
            .latest => |latest| blk: {
                if (latest.initial) |initial| if (self.nodeNeedsOuterScope(initial, bound)) break :blk true;
                for (latest.sources) |source| if (self.nodeNeedsOuterScope(source, bound)) break :blk true;
                break :blk false;
            },
            .then_value => |then_value| self.nodeNeedsOuterScope(then_value.source, bound) or self.nodeNeedsOuterScope(then_value.value, bound),
            .hold => |hold| self.holdNeedsOuterScope(hold, bound),
            .linked_value => |linked| self.nodeNeedsOuterScope(linked.value, bound) or self.nodeNeedsOuterScope(linked.target, bound),
            .builtin_call => |call| blk: {
                for (call.positional) |arg| if (self.nodeNeedsOuterScope(arg, bound)) break :blk true;
                for (call.named) |arg| if (self.nodeNeedsOuterScope(arg.value, bound)) break :blk true;
                break :blk false;
            },
            .user_call => |call| blk: {
                for (call.positional) |arg| if (self.nodeNeedsOuterScope(arg, bound)) break :blk true;
                for (call.named) |arg| if (self.nodeNeedsOuterScope(arg.value, bound)) break :blk true;
                if (call.pass_context) |pass_context| break :blk self.nodeNeedsOuterScope(pass_context, bound);
                break :blk false;
            },
        };
    }

    fn blockNeedsOuterScope(self: *Session, block: flow_ir.Block, bound: ?*const BoundLocalFrame) bool {
        return self.blockBindingsNeedOuterScope(block, 0, bound);
    }

    fn blockBindingsNeedOuterScope(self: *Session, block: flow_ir.Block, index: usize, bound: ?*const BoundLocalFrame) bool {
        if (index >= block.bindings.len) return self.nodeNeedsOuterScope(block.result, bound);
        const binding = block.bindings[index];
        if (self.nodeNeedsOuterScope(binding.value, bound)) return true;
        const next_bound = BoundLocalFrame{
            .name = binding.name,
            .parent = bound,
        };
        return self.blockBindingsNeedOuterScope(block, index + 1, &next_bound);
    }

    fn holdNeedsOuterScope(self: *Session, hold: flow_ir.Hold, bound: ?*const BoundLocalFrame) bool {
        if (self.nodeNeedsOuterScope(hold.initial, bound)) return true;
        const state_bound = BoundLocalFrame{
            .name = hold.state_name,
            .parent = bound,
        };
        for (hold.updates) |update| {
            if (self.nodeNeedsOuterScope(update, &state_bound)) return true;
        }
        return false;
    }

    fn holdNeedsRuntimeScope(self: *Session, node_id: flow_ir.NodeId, hold: flow_ir.Hold) bool {
        if (self.isTopLevelBindingNode(node_id)) return false;
        return self.holdNeedsOuterScope(hold, null);
    }

    fn nodeNeedsScope(self: *Session, node_id: flow_ir.NodeId) bool {
        switch (self.node_scope_state[node_id]) {
            1 => return false,
            2 => return false,
            3 => return true,
            else => {},
        }

        self.node_scope_state[node_id] = 1;
        const node = self.flow.nodes[node_id];
        const needs_scope = switch (node.kind) {
            .binding_ref => |binding_id| self.nodeNeedsScope(self.flow.bindings[binding_id].node),
            .local_ref => true,
            .special => |special| switch (special) {
                .pass_ref, .passed_ref => true,
                else => false,
            },
            .access => |access| self.nodeNeedsScope(access.target),
            .binary => |binary| self.nodeNeedsScope(binary.lhs) or self.nodeNeedsScope(binary.rhs),
            .text => |parts| blk: {
                for (parts) |part| if (self.nodeNeedsScope(part)) break :blk true;
                break :blk false;
            },
            .list => |list| blk: {
                for (list.items) |item| if (self.nodeNeedsScope(item)) break :blk true;
                break :blk false;
            },
            .record => |fields| blk: {
                for (fields) |field| if (self.nodeNeedsScope(field.value)) break :blk true;
                break :blk false;
            },
            .block => |block| blk: {
                for (block.bindings) |binding| if (self.nodeNeedsScope(binding.value)) break :blk true;
                break :blk self.nodeNeedsScope(block.result);
            },
            .when => |when| blk: {
                if (self.nodeNeedsScope(when.input)) break :blk true;
                for (when.arms) |arm| {
                    if (self.nodeNeedsScope(arm.pattern) or self.nodeNeedsScope(arm.result)) break :blk true;
                }
                break :blk false;
            },
            .latest => |latest| blk: {
                if (latest.initial) |initial| if (self.nodeNeedsScope(initial)) break :blk true;
                for (latest.sources) |source| if (self.nodeNeedsScope(source)) break :blk true;
                break :blk false;
            },
            .then_value => |then_value| self.nodeNeedsScope(then_value.source) or self.nodeNeedsScope(then_value.value),
            .hold => |hold| blk: {
                if (self.nodeNeedsScope(hold.initial)) break :blk true;
                for (hold.updates) |update| if (self.nodeNeedsScope(update)) break :blk true;
                break :blk false;
            },
            .linked_value => |linked| self.nodeNeedsScope(linked.value) or self.nodeNeedsScope(linked.target),
            .builtin_call => |call| blk: {
                for (call.positional) |arg| if (self.nodeNeedsScope(arg)) break :blk true;
                for (call.named) |arg| if (self.nodeNeedsScope(arg.value)) break :blk true;
                break :blk false;
            },
            .user_call => |call| blk: {
                for (call.positional) |arg| if (self.nodeNeedsScope(arg)) break :blk true;
                for (call.named) |arg| if (self.nodeNeedsScope(arg.value)) break :blk true;
                if (call.pass_context) |pass_context| break :blk self.nodeNeedsScope(pass_context);
                break :blk false;
            },
            else => false,
        };

        self.node_scope_state[node_id] = if (needs_scope) 3 else 2;
        return needs_scope;
    }

    fn nodeNeedsDeferredField(self: *Session, node_id: flow_ir.NodeId) bool {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| self.nodeNeedsDeferredField(self.flow.bindings[binding_id].node),
            .latest, .hold, .then_value, .linked_value => true,
            .builtin_call => |call| std.mem.eql(u8, call.path, "Math/sum") or
                std.mem.eql(u8, call.path, "Stream/pulses") or
                std.mem.eql(u8, call.path, "Stream/skip") or
                std.mem.eql(u8, call.path, "List/append") or
                std.mem.eql(u8, call.path, "List/clear") or
                std.mem.eql(u8, call.path, "List/remove") or
                std.mem.eql(u8, call.path, "List/remove_last"),
            else => false,
        };
    }

    fn eventDependencySource(self: *Session, node_id: flow_ir.NodeId) !flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.eventDependencySource(self.flow.bindings[binding_id].node),
            .access => |access| try self.resolveAccessEventSource(node_id, access),
            else => node_id,
        };
    }

    fn resolveAccessEventSource(self: *Session, node_id: flow_ir.NodeId, access: flow_ir.Access) !flow_ir.NodeId {
        if (std.mem.eql(u8, access.field, "press")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "press", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "change")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "change", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "click", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "double_click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "double_click", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "key_down")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "key_down", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "blur")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "blur", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "focus")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "focus", null)) |link| return link;
            }
        }
        if (try self.resolveStaticLinkNode(node_id)) |link| return link;
        if (try self.resolveStaticLinkNode(access.target)) |link| return link;
        if (std.mem.eql(u8, access.field, "value")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveElementEventLink(event_target.kind.access.target, "change", null)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "text")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveElementEventLink(event_target.kind.access.target, "change", null)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "key")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "key_down")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveElementEventLink(event_target.kind.access.target, "key_down", null)) |link| return link;
                }
            }
        }
        return node_id;
    }

    fn scopedEventDependencySource(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.scopedEventDependencySource(self.flow.bindings[binding_id].node, scope),
            .then_value => |then_value| try self.scopedEventDependencySource(then_value.source, scope),
            .when => |when| try self.scopedEventDependencySource(when.input, scope),
            .block => |block| try self.scopedEventDependencySource(block.result, scope),
            .access => |access| try self.resolveScopedAccessEventSource(node_id, access, scope),
            else => node_id,
        };
    }

    fn resolveScopedAccessEventSource(self: *Session, node_id: flow_ir.NodeId, access: flow_ir.Access, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        if (std.mem.eql(u8, access.field, "press")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "press", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "change")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "change", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "click", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "double_click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "double_click", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "key_down")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "key_down", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "blur")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "blur", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "focus")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveElementEventLink(target.kind.access.target, "focus", scope)) |link| return link;
            }
        }
        if (try self.resolveScopedLinkNode(node_id, scope)) |link| return link;
        if (try self.resolveScopedLinkNode(access.target, scope)) |link| return link;
        if (std.mem.eql(u8, access.field, "value")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveElementEventLink(event_target.kind.access.target, "change", scope)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "text")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveElementEventLink(event_target.kind.access.target, "change", scope)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "key")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "key_down")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveElementEventLink(event_target.kind.access.target, "key_down", scope)) |link| return link;
                }
            }
        }
        return node_id;
    }

    fn resolveElementEventLink(self: *Session, node_id: flow_ir.NodeId, event_name: []const u8, scope: ?*const EvalScope) anyerror!?flow_ir.NodeId {
        const value = try self.evalNode(self.arena.allocator(), node_id, scope);
        return try self.eventLinkFromResolvedValue(self.arena.allocator(), value, event_name);
    }

    fn eventLinkFromResolvedValue(self: *Session, allocator: std.mem.Allocator, value: Value, event_name: []const u8) anyerror!?flow_ir.NodeId {
        return switch (value) {
            .record => |fields| blk: {
                if (std.mem.eql(u8, event_name, "hovered")) {
                    if (findRecordValue(fields, "hovered")) |hovered| {
                        break :blk try self.representativeLinkFromResolvedValue(allocator, hovered);
                    }
                }
                if (findRecordValue(fields, "event")) |event_value| {
                    if (try self.eventLinkFromResolvedValue(allocator, event_value, event_name)) |link| {
                        break :blk link;
                    }
                }
                const field_value = findRecordValue(fields, event_name) orelse break :blk null;
                break :blk try self.representativeLinkFromResolvedValue(allocator, field_value);
            },
            .button => |button| if (std.mem.eql(u8, event_name, "press"))
                button.press_link
            else if (std.mem.eql(u8, event_name, "hovered"))
                button.hovered_link
            else
                null,
            .checkbox => |checkbox| if (std.mem.eql(u8, event_name, "click")) checkbox.click_link else null,
            .label => |label| if (std.mem.eql(u8, event_name, "click"))
                label.click_link
            else if (std.mem.eql(u8, event_name, "double_click"))
                label.double_click_link
            else
                null,
            .stripe => |stripe| if (std.mem.eql(u8, event_name, "hovered")) stripe.hovered_link else null,
            .text_input => |input| if (std.mem.eql(u8, event_name, "change"))
                input.change_link
            else if (std.mem.eql(u8, event_name, "key_down"))
                input.key_link orelse input.change_link
            else if (std.mem.eql(u8, event_name, "blur"))
                input.blur_link orelse input.change_link
            else if (std.mem.eql(u8, event_name, "focus"))
                input.focus_link orelse input.change_link
            else
                null,
            .select => |select| if (std.mem.eql(u8, event_name, "change")) select.change_link else null,
            .slider => |slider| if (std.mem.eql(u8, event_name, "change")) slider.change_link else null,
            .scoped_node => |deferred| try self.eventLinkFromResolvedValue(
                allocator,
                try self.evalNode(allocator, deferred.node_id, deferred.scope),
                event_name,
            ),
            .binding_ref => |binding_id| try self.eventLinkFromResolvedValue(
                allocator,
                try self.evalNode(allocator, self.flow.bindings[binding_id].node, null),
                event_name,
            ),
            else => null,
        };
    }

    fn representativeLinkFromResolvedValue(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror!?flow_ir.NodeId {
        return switch (value) {
            .link => |link| link,
            .record => |fields| blk: {
                for (fields) |field| {
                    if (try self.representativeLinkFromResolvedValue(allocator, field.value)) |link| break :blk link;
                }
                break :blk null;
            },
            .scoped_node => |deferred| try self.representativeLinkFromResolvedValue(
                allocator,
                try self.evalNode(allocator, deferred.node_id, deferred.scope),
            ),
            .binding_ref => |binding_id| try self.representativeLinkFromResolvedValue(
                allocator,
                try self.evalNode(allocator, self.flow.bindings[binding_id].node, null),
            ),
            else => null,
        };
    }

    fn listSourceDependency(self: *Session, node_id: flow_ir.NodeId) !flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.listSourceDependency(self.flow.bindings[binding_id].node),
            .builtin_call => |call| if (std.mem.eql(u8, call.path, "List/append") or std.mem.eql(u8, call.path, "List/clear") or std.mem.eql(u8, call.path, "List/remove") or std.mem.eql(u8, call.path, "List/remove_last")) node_id else try self.eventDependencySource(node_id),
            else => try self.eventDependencySource(node_id),
        };
    }

    fn valueTriggerSource(self: *Session, node_id: flow_ir.NodeId) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.valueTriggerSource(self.flow.bindings[binding_id].node),
            .then_value => |then_value| try self.valueTriggerSource(then_value.source),
            .when => |when| try self.valueTriggerSource(when.input),
            .block => |block| try self.valueTriggerSource(block.result),
            .binary => |binary| blk: {
                const lhs = try self.valueTriggerSource(binary.lhs);
                if (lhs != binary.lhs or self.flow.nodes[lhs].kind == .link_port) break :blk lhs;
                break :blk try self.valueTriggerSource(binary.rhs);
            },
            .text => |parts| blk: {
                for (parts) |part| {
                    const source = try self.valueTriggerSource(part);
                    if (source != part or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .record => |fields| blk: {
                for (fields) |field| {
                    const source = try self.valueTriggerSource(field.value);
                    if (source != field.value or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .list => |list| blk: {
                for (list.items) |item| {
                    const source = try self.valueTriggerSource(item);
                    if (source != item or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .user_call => |call| blk: {
                for (call.positional) |arg| {
                    const source = try self.valueTriggerSource(arg);
                    if (source != arg or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                for (call.named) |arg| {
                    const source = try self.valueTriggerSource(arg.value);
                    if (source != arg.value or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                if (call.pass_context) |pass_context| {
                    const source = try self.valueTriggerSource(pass_context);
                    if (source != pass_context or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .builtin_call => |call| blk: {
                for (call.positional) |arg| {
                    const source = try self.valueTriggerSource(arg);
                    if (source != arg or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                for (call.named) |arg| {
                    const source = try self.valueTriggerSource(arg.value);
                    if (source != arg.value or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk try self.eventDependencySource(node_id);
            },
            else => try self.eventDependencySource(node_id),
        };
    }

    fn valueTriggerSourceScoped(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.valueTriggerSourceScoped(self.flow.bindings[binding_id].node, scope),
            .then_value => |then_value| try self.valueTriggerSourceScoped(then_value.source, scope),
            .when => |when| try self.valueTriggerSourceScoped(when.input, scope),
            .block => |block| try self.valueTriggerSourceScoped(block.result, scope),
            .binary => |binary| blk: {
                const lhs = try self.valueTriggerSourceScoped(binary.lhs, scope);
                if (lhs != binary.lhs or self.flow.nodes[lhs].kind == .link_port) break :blk lhs;
                break :blk try self.valueTriggerSourceScoped(binary.rhs, scope);
            },
            .text => |parts| blk: {
                for (parts) |part| {
                    const source = try self.valueTriggerSourceScoped(part, scope);
                    if (source != part or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .record => |fields| blk: {
                for (fields) |field| {
                    const source = try self.valueTriggerSourceScoped(field.value, scope);
                    if (source != field.value or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .list => |list| blk: {
                for (list.items) |item| {
                    const source = try self.valueTriggerSourceScoped(item, scope);
                    if (source != item or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .user_call => |call| blk: {
                for (call.positional) |arg| {
                    const source = try self.valueTriggerSourceScoped(arg, scope);
                    if (source != arg or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                for (call.named) |arg| {
                    const source = try self.valueTriggerSourceScoped(arg.value, scope);
                    if (source != arg.value or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                if (call.pass_context) |pass_context| {
                    const source = try self.valueTriggerSourceScoped(pass_context, scope);
                    if (source != pass_context or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk node_id;
            },
            .builtin_call => |call| blk: {
                for (call.positional) |arg| {
                    const source = try self.valueTriggerSourceScoped(arg, scope);
                    if (source != arg or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                for (call.named) |arg| {
                    const source = try self.valueTriggerSourceScoped(arg.value, scope);
                    if (source != arg.value or self.flow.nodes[source].kind == .link_port) break :blk source;
                }
                break :blk try self.scopedEventDependencySource(node_id, scope);
            },
            else => try self.scopedEventDependencySource(node_id, scope),
        };
    }

    fn buttonPressLink(self: *Session, node_id: flow_ir.NodeId) !flow_ir.NodeId {
        return try self.resolveElementEventLink(node_id, "press", null) orelse error.UnsupportedEventSource;
    }

    fn resolveStaticLinkNode(self: *Session, node_id: flow_ir.NodeId) !?flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .link_port => node_id,
            .binding_ref => |binding_id| try self.resolveStaticLinkNode(self.flow.bindings[binding_id].node),
            .linked_value => |linked| try self.resolveStaticLinkNode(linked.target),
            .access => |access| blk: {
                if (std.mem.eql(u8, access.field, "event")) {
                    if (try self.resolveStaticLinkNode(access.target)) |link| break :blk link;
                }
                if (std.mem.eql(u8, access.field, "press")) {
                    const target = self.flow.nodes[access.target];
                    if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                        break :blk try self.resolveStaticLinkNode(target.kind.access.target);
                    }
                }

                const field_node = try self.resolveStaticFieldNode(access.target, access.field) orelse break :blk null;
                break :blk try self.resolveStaticLinkNode(field_node);
            },
            else => null,
        };
    }

    fn resolveStaticFieldNode(self: *Session, node_id: flow_ir.NodeId, field_name: []const u8) !?flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.resolveStaticFieldNode(self.flow.bindings[binding_id].node, field_name),
            .record => |fields| findField(fields, field_name),
            .access => |access| blk: {
                const inner = try self.resolveStaticFieldNode(access.target, access.field) orelse break :blk null;
                break :blk try self.resolveStaticFieldNode(inner, field_name);
            },
            else => null,
        };
    }

    fn recordLinkField(self: *Session, node_id: flow_ir.NodeId, outer_name: []const u8, inner_name: []const u8) !flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        const fields = switch (node.kind) {
            .binding_ref => |binding_id| return try self.recordLinkField(self.flow.bindings[binding_id].node, outer_name, inner_name),
            .record => |fields| fields,
            else => return error.ExpectedRecordNode,
        };
        const outer = findField(fields, outer_name) orelse return error.MissingRecordField;
        const inner_node = self.flow.nodes[outer];
        const inner_fields = switch (inner_node.kind) {
            .record => |inner_fields| inner_fields,
            else => return error.ExpectedRecordNode,
        };
        const link_node = findField(inner_fields, inner_name) orelse return error.MissingRecordField;
        const link_value = self.flow.nodes[link_node];
        return switch (link_value.kind) {
            .link_port => link_node,
            .binding_ref => |binding_id| self.flow.bindings[binding_id].node,
            else => error.ExpectedLinkNode,
        };
    }

    fn resolveScopedLinkNode(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!?flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .link_port => node_id,
            .binding_ref => |binding_id| try self.resolveScopedLinkNode(self.flow.bindings[binding_id].node, scope),
            .local_ref => |name| if (lookupLocal(scope, name)) |value|
                try self.resolveLinkValue(value, scope)
            else
                null,
            .linked_value => |linked| try self.resolveScopedLinkNode(linked.target, scope),
            .access => |access| blk: {
                if (try self.resolveStaticLinkNode(node_id)) |link| break :blk link;
                const target_value = if (try self.resolveScopedLinkNode(access.target, scope)) |link|
                    Value{ .link = link }
                else switch (self.flow.nodes[access.target].kind) {
                    .symbol => |text| lookupLocal(scope, text) orelse try self.evalNode(self.arena.allocator(), access.target, scope),
                    else => try self.evalNode(self.arena.allocator(), access.target, scope),
                };
                break :blk try self.resolveLinkFieldFromValue(target_value, access.field, scope);
            },
            else => null,
        };
    }

    fn resolveLinkFieldFromValue(self: *Session, value: Value, field_name: []const u8, scope: ?*const EvalScope) anyerror!?flow_ir.NodeId {
        return switch (value) {
            .record => |fields| if (findRecordValue(fields, field_name)) |field_value|
                try self.resolveLinkValue(field_value, scope)
            else
                null,
            .binding_ref => |binding_id| blk: {
                const field_node = try self.resolveStaticFieldNode(self.flow.bindings[binding_id].node, field_name) orelse break :blk null;
                break :blk try self.resolveScopedLinkNode(field_node, scope);
            },
            else => null,
        };
    }

    fn resolveLinkValue(self: *Session, value: Value, scope: ?*const EvalScope) anyerror!?flow_ir.NodeId {
        return switch (value) {
            .link => |link| link,
            .binding_ref => |binding_id| try self.resolveScopedLinkNode(self.flow.bindings[binding_id].node, scope),
            else => null,
        };
    }

    fn linkedValueTriggerSource(self: *Session, node_id: flow_ir.NodeId) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.linkedValueTriggerSource(self.flow.bindings[binding_id].node),
            .when => |when| try self.eventDependencySource(when.input),
            .block => |block| try self.linkedValueTriggerSource(block.result),
            else => try self.eventDependencySource(node_id),
        };
    }

    fn linkedValueTriggerSourceScoped(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.linkedValueTriggerSourceScoped(self.flow.bindings[binding_id].node, scope),
            .when => |when| try self.scopedEventDependencySource(when.input, scope),
            .block => |block| try self.linkedValueTriggerSourceScoped(block.result, scope),
            else => try self.scopedEventDependencySource(node_id, scope),
        };
    }

    fn processQueue(self: *Session) !void {
        var index: usize = 0;
        var had_pulses = false;
        while (index < self.queue.items.len) : (index += 1) {
            had_pulses = true;
            const pulse = self.queue.items[index];
            switch (pulse.payload) {
                .node => |node| try self.logf("pulse n{d} payload=n{d}", .{ pulse.source, node }),
                .value => try self.logf("pulse n{d} payload=<value>", .{pulse.source}),
            }
            for (self.subscribers[pulse.source]) |subscriber| {
                try self.dispatchPulseToSubscriber(subscriber, pulse);
            }
            try self.dispatchRuntimeScopedSubscribers(pulse);
            for (self.flow.nodes, 0..) |node, subscriber_usize| {
                if (node.kind != .builtin_call) continue;
                const call = node.kind.builtin_call;
                if (std.mem.eql(u8, call.path, "List/remove")) {
                    try self.processListRemovePulse(@intCast(subscriber_usize), call, pulse.source);
                    continue;
                }
                if (std.mem.eql(u8, call.path, "List/remove_last")) {
                    try self.processListRemoveLastPulse(@intCast(subscriber_usize), call, pulse.source);
                }
            }
        }
        self.queue.clearRetainingCapacity();
        if (had_pulses) try self.savePersistedState();
    }

    fn dispatchPulseToSubscriber(self: *Session, subscriber: flow_ir.NodeId, pulse: Pulse) !void {
        if (self.nodeNeedsScope(subscriber) and pulse.scope == null) return;
        const node = self.flow.nodes[subscriber];
        switch (node.kind) {
            .then_value => |then_value| {
                try self.logf("then n{d} -> n{d}", .{ subscriber, then_value.value });
                try self.queue.append(self.arena.allocator(), .{
                    .source = subscriber,
                    .payload = .{ .node = subscriber },
                    .scope = pulse.scope,
                });
            },
            .latest => {
                try self.setLatestPayload(subscriber, pulse.scope, pulse.payload);
                switch (pulse.payload) {
                    .node => |payload_node| try self.logf("latest n{d} <- n{d}", .{ subscriber, payload_node }),
                    .value => try self.logf("latest n{d} <- <value>", .{subscriber}),
                }
                try self.queue.append(self.arena.allocator(), .{
                    .source = subscriber,
                    .payload = pulse.payload,
                    .scope = pulse.scope,
                });
            },
            .hold => |hold| {
                try self.processHoldPulse(subscriber, hold, pulse.source, pulse.scope);
            },
            .linked_value => |linked| {
                const value = switch (self.flow.nodes[linked.value].kind) {
                    .when, .block, .then_value => try self.evalNode(self.arena.allocator(), linked.value, pulse.scope),
                    else => try valueFromPulsePayload(self, self.arena.allocator(), pulse.payload, pulse.scope),
                };
                if (value == .none) return;
                const link = if (try self.resolveStaticLinkNode(linked.target)) |static_link|
                    static_link
                else if (try self.resolveScopedLinkNode(linked.target, pulse.scope)) |scoped_link|
                    scoped_link
                else blk: {
                    const target = try self.evalNode(self.arena.allocator(), linked.target, pulse.scope);
                    break :blk switch (target) {
                        .link => |resolved_link| resolved_link,
                        else => return error.ExpectedLinkValue,
                    };
                };
                try self.setLinkValue(link, pulse.scope, value);
                try self.logf("linked n{d} -> n{d}", .{ subscriber, link });
                try self.queue.append(self.arena.allocator(), .{
                    .source = link,
                    .payload = .{ .value = value },
                    .scope = pulse.scope,
                });
            },
            .builtin_call => |call| {
                if (std.mem.eql(u8, call.path, "Stream/pulses")) {
                    try self.emitPulses(subscriber, call, pulse.scope);
                }
                if (std.mem.eql(u8, call.path, "Stream/skip")) {
                    try self.processSkipPulse(subscriber, call, pulse.payload, pulse.scope);
                }
                if (std.mem.eql(u8, call.path, "Math/sum")) {
                    const value = try valueAsNumber(try valueFromPulsePayload(self, self.arena.allocator(), pulse.payload, pulse.scope));
                    self.sum_values[subscriber] += value;
                    self.sum_inited[subscriber] = true;
                    self.invalidateEvalCacheForDependency(.{ .node_id = subscriber, .scope_id = 0 });
                    try self.logf("sum n{d} += {d} -> {d}", .{
                        subscriber,
                        value,
                        self.sum_values[subscriber],
                    });
                    try self.queue.append(self.arena.allocator(), .{ .source = subscriber, .payload = .{ .node = subscriber } });
                }
                if (std.mem.eql(u8, call.path, "List/append")) {
                    try self.processListAppendPulse(subscriber, call, pulse.source);
                }
                if (std.mem.eql(u8, call.path, "List/clear")) {
                    try self.processListClearPulse(subscriber, call, pulse.source);
                }
                if (std.mem.eql(u8, call.path, "Router/go_to") and call.positional.len != 0) {
                    const route = try self.evalNode(self.arena.allocator(), call.positional[0], null);
                    if (route != .none) {
                        self.route_value = route;
                        self.invalidateEvalCacheForDependency(.{ .node_id = subscriber, .scope_id = 0 });
                        try self.logf("router_go_to n{d} -> {s}", .{ subscriber, try valueAsText(route) });
                        try self.queue.append(self.arena.allocator(), .{ .source = subscriber, .payload = .{ .node = subscriber } });
                    }
                }
            },
            else => {},
        }
    }

    fn dispatchRuntimeScopedSubscribers(self: *Session, pulse: Pulse) !void {
        const scope = pulse.scope orelse return;
        for (self.runtime_subscribers, 0..) |enabled, subscriber_usize| {
            if (!enabled) continue;
            const subscriber: flow_ir.NodeId = @intCast(subscriber_usize);
            if (!try self.runtimeSubscriberMatchesPulse(subscriber, pulse.source, scope)) continue;
            try self.dispatchPulseToSubscriber(subscriber, pulse);
        }
    }

    fn runtimeSubscriberMatchesPulse(self: *Session, subscriber: flow_ir.NodeId, pulse_source: flow_ir.NodeId, scope: *const EvalScope) anyerror!bool {
        const node = self.flow.nodes[subscriber];
        return switch (node.kind) {
            .then_value => |then_value| self.nodeNeedsScope(then_value.source) and try self.safeScopedEventSourceEquals(then_value.source, scope, pulse_source),
            .latest => |latest| blk: {
                for (latest.sources) |source_node| {
                    if (!self.nodeNeedsScope(source_node)) continue;
                    if (try self.safeScopedEventSourceEquals(source_node, scope, pulse_source)) break :blk true;
                }
                break :blk false;
            },
            .hold => |hold| blk: {
                for (hold.updates) |update| {
                    if (!self.nodeNeedsScope(update)) continue;
                    if (try self.safeScopedHoldTriggerEquals(update, scope, pulse_source)) break :blk true;
                }
                break :blk false;
            },
            .linked_value => |linked| self.nodeNeedsScope(linked.value) and try self.safeScopedLinkedTriggerEquals(linked.value, scope, pulse_source),
            .builtin_call => |call| try self.runtimeBuiltinCallMatchesPulse(call, pulse_source, scope),
            else => false,
        };
    }

    fn runtimeBuiltinCallMatchesPulse(self: *Session, call: flow_ir.BuiltinCall, pulse_source: flow_ir.NodeId, scope: *const EvalScope) anyerror!bool {
        if ((std.mem.eql(u8, call.path, "Stream/pulses") or
            std.mem.eql(u8, call.path, "Stream/skip") or
            std.mem.eql(u8, call.path, "Math/sum")) and call.positional.len != 0)
        {
            return self.nodeNeedsScope(call.positional[0]) and try self.safeScopedEventSourceEquals(call.positional[0], scope, pulse_source);
        }
        if (std.mem.eql(u8, call.path, "List/append")) {
            if (call.positional.len != 0 and self.nodeNeedsScope(call.positional[0]) and try self.safeScopedListSourceEquals(call.positional[0], scope, pulse_source)) return true;
            if (findNamed(call.named, "item")) |item_node| {
                return self.nodeNeedsScope(item_node) and try self.safeScopedValueSourceEquals(item_node, scope, pulse_source);
            }
            if (findNamed(call.named, "on")) |on_node| {
                return self.nodeNeedsScope(on_node) and try self.safeScopedValueSourceEquals(on_node, scope, pulse_source);
            }
        }
        if (std.mem.eql(u8, call.path, "List/clear") or std.mem.eql(u8, call.path, "List/remove_last")) {
            if (call.positional.len != 0 and self.nodeNeedsScope(call.positional[0]) and try self.safeScopedListSourceEquals(call.positional[0], scope, pulse_source)) return true;
            const on_node = findNamed(call.named, "on") orelse return false;
            return self.nodeNeedsScope(on_node) and try self.safeScopedValueSourceEquals(on_node, scope, pulse_source);
        }
        if (std.mem.eql(u8, call.path, "Router/go_to") and call.positional.len != 0) {
            return self.nodeNeedsScope(call.positional[0]) and try self.safeScopedEventSourceEquals(call.positional[0], scope, pulse_source);
        }
        return false;
    }

    fn safeScopedEventSourceEquals(self: *Session, node_id: flow_ir.NodeId, scope: *const EvalScope, pulse_source: flow_ir.NodeId) anyerror!bool {
        const source = self.scopedEventDependencySource(node_id, scope) catch |err| switch (err) {
            error.MissingLocalBinding,
            error.MissingRecordField,
            error.ExpectedRecordNode,
            error.ExpectedLinkNode,
            error.ExpectedLinkValue,
            error.UnsupportedFieldAccess,
            error.UnsupportedEventSource,
            => return false,
            else => return err,
        };
        return source == pulse_source;
    }

    fn safeScopedHoldTriggerEquals(self: *Session, node_id: flow_ir.NodeId, scope: *const EvalScope, pulse_source: flow_ir.NodeId) anyerror!bool {
        const source = self.holdTriggerSourceScoped(node_id, scope) catch |err| switch (err) {
            error.MissingLocalBinding,
            error.MissingRecordField,
            error.ExpectedRecordNode,
            error.ExpectedLinkNode,
            error.ExpectedLinkValue,
            error.UnsupportedFieldAccess,
            error.UnsupportedEventSource,
            => return false,
            else => return err,
        };
        return source == pulse_source;
    }

    fn safeScopedLinkedTriggerEquals(self: *Session, node_id: flow_ir.NodeId, scope: *const EvalScope, pulse_source: flow_ir.NodeId) anyerror!bool {
        const source = self.linkedValueTriggerSourceScoped(node_id, scope) catch |err| switch (err) {
            error.MissingLocalBinding,
            error.MissingRecordField,
            error.ExpectedRecordNode,
            error.ExpectedLinkNode,
            error.ExpectedLinkValue,
            error.UnsupportedFieldAccess,
            error.UnsupportedEventSource,
            => return false,
            else => return err,
        };
        return source == pulse_source;
    }

    fn safeScopedListSourceEquals(self: *Session, node_id: flow_ir.NodeId, scope: *const EvalScope, pulse_source: flow_ir.NodeId) anyerror!bool {
        const source = self.listSourceDependencyScoped(node_id, scope) catch |err| switch (err) {
            error.MissingLocalBinding,
            error.MissingRecordField,
            error.ExpectedRecordNode,
            error.ExpectedLinkNode,
            error.ExpectedLinkValue,
            error.UnsupportedFieldAccess,
            error.UnsupportedEventSource,
            => return false,
            else => return err,
        };
        return source == pulse_source;
    }

    fn safeScopedValueSourceEquals(self: *Session, node_id: flow_ir.NodeId, scope: *const EvalScope, pulse_source: flow_ir.NodeId) anyerror!bool {
        const source = self.valueTriggerSourceScoped(node_id, scope) catch |err| switch (err) {
            error.MissingLocalBinding,
            error.MissingRecordField,
            error.ExpectedRecordNode,
            error.ExpectedLinkNode,
            error.ExpectedLinkValue,
            error.UnsupportedFieldAccess,
            error.UnsupportedEventSource,
            => return false,
            else => return err,
        };
        return source == pulse_source;
    }

    fn listSourceDependencyScoped(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.listSourceDependencyScoped(self.flow.bindings[binding_id].node, scope),
            .builtin_call => |call| if (std.mem.eql(u8, call.path, "List/append") or std.mem.eql(u8, call.path, "List/clear") or std.mem.eql(u8, call.path, "List/remove") or std.mem.eql(u8, call.path, "List/remove_last")) node_id else try self.scopedEventDependencySource(node_id, scope),
            else => try self.scopedEventDependencySource(node_id, scope),
        };
    }

    fn numberFromNode(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!f64 {
        var scratch = std.heap.ArenaAllocator.init(self.arena.allocator());
        defer scratch.deinit();
        const value = try self.evalNode(scratch.allocator(), node_id, scope);
        return try valueAsNumber(value);
    }

    fn initialNumericValue(self: *Session, node_id: flow_ir.NodeId) anyerror!?f64 {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.initialNumericValue(self.flow.bindings[binding_id].node),
            .number => |number| number.value,
            .latest => blk: {
                var scratch = std.heap.ArenaAllocator.init(self.arena.allocator());
                defer scratch.deinit();
                const value = self.evalNode(scratch.allocator(), node_id, null) catch |err| switch (err) {
                    error.ExpectedNumericValue, error.ExpectedTextValue, error.ExpectedDurationValue => break :blk null,
                    else => return err,
                };
                break :blk switch (value) {
                    .number => |number| number,
                    else => null,
                };
            },
            .link_port => if (self.getLinkValue(node_id, null)) |value| try valueAsNumber(value) else null,
            .builtin_call => |call| blk: {
                if (std.mem.eql(u8, call.path, "Math/sum") and self.sum_inited[node_id]) {
                    break :blk self.sum_values[node_id];
                }
                break :blk null;
            },
            else => null,
        };
    }

    fn cachedControlRefs(self: *Session, kind: CachedControlKind) anyerror![]const ControlEventRef {
        switch (kind) {
            .button => if (self.cached_button_links) |links| return links,
            .slider => if (self.cached_slider_links) |links| return links,
            .text_input => if (self.cached_text_input_links) |links| return links,
            .text_input_key => if (self.cached_text_input_key_links) |links| return links,
            .text_input_blur => if (self.cached_text_input_blur_links) |links| return links,
            .text_input_focus => if (self.cached_text_input_focus_links) |links| return links,
            .label_double_click => if (self.cached_label_double_click_links) |links| return links,
            .hover => if (self.cached_hover_links) |links| return links,
            .select => if (self.cached_select_links) |links| return links,
        }

        const value = try self.interactionRootValue();
        var links: std.ArrayList(ControlEventRef) = .empty;
        defer links.deinit(self.memo_arena.allocator());
        switch (kind) {
            .button => try collectButtonLinks(self, &links, self.memo_arena.allocator(), value),
            .slider => try collectSliderLinks(self, &links, self.memo_arena.allocator(), value),
            .text_input => try collectTextInputLinks(self, &links, self.memo_arena.allocator(), value),
            .text_input_key => try collectTextInputKeyLinks(self, &links, self.memo_arena.allocator(), value),
            .text_input_blur => try collectTextInputBlurLinks(self, &links, self.memo_arena.allocator(), value),
            .text_input_focus => try collectTextInputFocusLinks(self, &links, self.memo_arena.allocator(), value),
            .label_double_click => try collectLabelDoubleClickLinks(self, &links, self.memo_arena.allocator(), value),
            .hover => try collectHoverLinks(self, &links, self.memo_arena.allocator(), value),
            .select => try collectSelectLinks(self, &links, self.memo_arena.allocator(), value),
        }
        const owned = try links.toOwnedSlice(self.memo_arena.allocator());
        switch (kind) {
            .button => self.cached_button_links = owned,
            .slider => self.cached_slider_links = owned,
            .text_input => self.cached_text_input_links = owned,
            .text_input_key => self.cached_text_input_key_links = owned,
            .text_input_blur => self.cached_text_input_blur_links = owned,
            .text_input_focus => self.cached_text_input_focus_links = owned,
            .label_double_click => self.cached_label_double_click_links = owned,
            .hover => self.cached_hover_links = owned,
            .select => self.cached_select_links = owned,
        }
        return owned;
    }

    fn buttonLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.button);
        if (index >= links.len) return error.InvalidButtonIndex;
        return links[index];
    }

    fn sliderLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.slider);
        if (index >= links.len) return error.InvalidSliderIndex;
        return links[index];
    }

    fn textInputLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.text_input);
        if (index >= links.len) return error.InvalidTextInputIndex;
        return links[index];
    }

    fn textInputKeyLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.text_input_key);
        if (index >= links.len) return error.InvalidTextInputIndex;
        return links[index];
    }

    fn textInputBlurLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.text_input_blur);
        if (index >= links.len) return error.InvalidTextInputIndex;
        return links[index];
    }

    fn textInputFocusLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.text_input_focus);
        if (index >= links.len) return error.InvalidTextInputIndex;
        return links[index];
    }

    fn labelDoubleClickLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.label_double_click);
        if (index >= links.len) return error.InvalidButtonIndex;
        return links[index];
    }

    fn hoverLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.hover);
        if (index >= links.len) return error.InvalidButtonIndex;
        return links[index];
    }

    fn selectLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.select);
        if (index >= links.len) return error.InvalidSelectIndex;
        return links[index];
    }

    fn interactionRootValue(self: *Session) anyerror!Value {
        try self.flushPendingQueue();
        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        return try self.evalNode(self.arena.allocator(), self.flow.bindings[root_binding].node, null);
    }

    fn scopedNodeKey(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?ScopedNodeKey {
        _ = self;
        const normalized_scope = canonicalControlScope(normalizedStateScope(scope)) orelse return null;
        return .{
            .node_id = node_id,
            .scope_id = normalized_scope.id,
        };
    }

    fn evalCacheKey(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ScopedNodeKey {
        _ = self;
        return .{
            .node_id = node_id,
            .scope_id = if (scope) |resolved| resolved.id else 0,
        };
    }

    fn addFrameDependency(self: *Session, frame: *EvalFrame, dep: ScopedNodeKey) !void {
        for (frame.deps.items) |existing| {
            if (existing.node_id == dep.node_id and existing.scope_id == dep.scope_id) return;
        }
        try frame.deps.append(self.backing_allocator, dep);
    }

    fn mergeCachedDependencies(self: *Session, deps: []const ScopedNodeKey) !void {
        const frame = self.current_eval_frame orelse return;
        for (deps) |dep| try self.addFrameDependency(frame, dep);
    }

    fn recordStateDependency(self: *Session, dep: ScopedNodeKey) !void {
        const frame = self.current_eval_frame orelse return;
        try self.addFrameDependency(frame, dep);
    }

    fn scopedStateKey(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ScopedNodeKey {
        if (self.scopedNodeKey(node_id, scope)) |key| return key;
        return .{ .node_id = node_id, .scope_id = 0 };
    }

    fn recordLinkDependencies(self: *Session, link: flow_ir.NodeId, scope: ?*const EvalScope, include_key: bool) !void {
        try self.recordStateDependency(self.scopedStateKey(link, scope));
        if (include_key) try self.recordStateDependency(self.scopedStateKey(link, scope));
    }

    fn invalidateEvalCacheForDependency(self: *Session, dep: ScopedNodeKey) void {
        if (self.cached_terminal_contract_deps) |deps| {
            for (deps) |cached_dep| {
                if (cached_dep.node_id == dep.node_id and cached_dep.scope_id == dep.scope_id) {
                    self.backing_allocator.free(deps);
                    self.cached_terminal_contract_deps = null;
                    self.cached_terminal_contract = null;
                    break;
                }
            }
        }
        self.cached_terminal_hit_regions = null;
        self.cached_button_links = null;
        self.cached_slider_links = null;
        self.cached_text_input_links = null;
        self.cached_text_input_key_links = null;
        self.cached_text_input_blur_links = null;
        self.cached_text_input_focus_links = null;
        self.cached_label_double_click_links = null;
        self.cached_hover_links = null;
        self.cached_select_links = null;
        self.cached_text_inputs = null;

        var keys: std.ArrayList(ScopedNodeKey) = .empty;
        defer keys.deinit(self.backing_allocator);

        var iterator = self.eval_cache.iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            const cached = entry.value_ptr.*;
            if (key.node_id == dep.node_id and key.scope_id == dep.scope_id) {
                keys.append(self.backing_allocator, key) catch {
                    self.invalidateEvalCache();
                    return;
                };
                continue;
            }
            for (cached.deps) |cached_dep| {
                if (cached_dep.node_id == dep.node_id and cached_dep.scope_id == dep.scope_id) {
                    keys.append(self.backing_allocator, key) catch {
                        self.invalidateEvalCache();
                        return;
                    };
                    break;
                }
            }
        }

        for (keys.items) |key| {
            if (self.eval_cache.fetchRemove(key)) |removed| {
                self.backing_allocator.free(removed.value.deps);
            }
        }
    }

    fn isTopLevelBindingNode(self: *Session, node_id: flow_ir.NodeId) bool {
        for (self.flow.bindings) |binding| {
            if (binding.node == node_id) return true;
        }
        return false;
    }

    fn holdStorageScope(self: *Session, node_id: flow_ir.NodeId, hold: flow_ir.Hold, scope: ?*const EvalScope) ?*const EvalScope {
        if (!self.holdNeedsRuntimeScope(node_id, hold)) return null;
        return normalizedStateScope(scope);
    }

    fn canonicalControlScope(scope: ?*const EvalScope) ?*const EvalScope {
        var current = scope orelse return null;
        var candidate: ?*const EvalScope = null;
        while (true) {
            if (current.bindings.len == 1 and std.mem.eql(u8, current.bindings[0].name, "element") and current.parent != null) {
                current = current.parent.?;
                continue;
            }
            if (current.bindings.len == 0 and current.parent != null) {
                current = current.parent.?;
                continue;
            }
            candidate = current;
            current = current.parent orelse break;
        }
        return candidate;
    }

    fn getLinkValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?Value {
        if (self.scopedNodeKey(node_id, scope)) |key| return self.scoped_link_values.get(key);
        return if (self.link_inited[node_id]) self.link_values[node_id] else null;
    }

    fn setLinkValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope, value: Value) !void {
        self.invalidateEvalCacheForDependency(self.scopedStateKey(node_id, scope));
        if (self.scopedNodeKey(node_id, scope)) |key| {
            try self.scoped_link_values.put(self.arena.allocator(), key, value);
            return;
        }
        self.link_values[node_id] = value;
        self.link_inited[node_id] = true;
    }

    fn getLinkKeyValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?Value {
        if (self.scopedNodeKey(node_id, scope)) |key| return self.scoped_link_key_values.get(key);
        return if (self.link_key_inited[node_id]) self.link_key_values[node_id] else null;
    }

    fn setLinkKeyValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope, value: Value) !void {
        self.invalidateEvalCacheForDependency(self.scopedStateKey(node_id, scope));
        if (self.scopedNodeKey(node_id, scope)) |key| {
            try self.scoped_link_key_values.put(self.arena.allocator(), key, value);
            return;
        }
        self.link_key_values[node_id] = value;
        self.link_key_inited[node_id] = true;
    }

    fn getLatestPayload(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?PulsePayload {
        if (self.scopedNodeKey(node_id, scope)) |key| return self.scoped_latest_values.get(key);
        return self.latest_values[node_id];
    }

    fn setLatestPayload(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope, payload: PulsePayload) !void {
        self.invalidateEvalCacheForDependency(self.scopedStateKey(node_id, scope));
        if (self.scopedNodeKey(node_id, scope)) |key| {
            try self.scoped_latest_values.put(self.arena.allocator(), key, payload);
            return;
        }
        self.latest_values[node_id] = payload;
    }

    fn getHoldValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?Value {
        if (self.scopedNodeKey(node_id, scope)) |key| return self.scoped_hold_values.get(key);
        return if (self.hold_inited[node_id]) self.hold_values[node_id] else null;
    }

    fn setHoldValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope, value: Value) !void {
        self.invalidateEvalCacheForDependency(self.scopedStateKey(node_id, scope));
        if (self.scopedNodeKey(node_id, scope)) |key| {
            try self.scoped_hold_values.put(self.arena.allocator(), key, value);
            return;
        }
        self.hold_values[node_id] = value;
        self.hold_inited[node_id] = true;
    }

    fn currentTextInputValue(self: *Session, index: usize) anyerror!Value {
        const inputs = try self.textInputValuesView();
        if (index >= inputs.len) return error.InvalidTextInputIndex;
        return inputs[index].text;
    }

    fn textInputValuesView(self: *Session) anyerror![]*TextInputValue {
        try self.flushPendingQueue();
        if (self.cached_text_inputs) |inputs| return inputs;

        const value = try self.interactionRootValue();
        var inputs: std.ArrayList(*TextInputValue) = .empty;
        defer inputs.deinit(self.memo_arena.allocator());
        try collectTextInputValues(self, &inputs, self.memo_arena.allocator(), value);
        const owned = try inputs.toOwnedSlice(self.memo_arena.allocator());
        self.cached_text_inputs = owned;
        return owned;
    }

    fn evalNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!Value {
        const cache_key = self.evalCacheKey(node_id, scope);
        if (self.eval_cache.get(cache_key)) |cached| {
            try self.mergeCachedDependencies(cached.deps);
            return cached.value;
        }

        var frame = EvalFrame{ .parent = self.current_eval_frame };
        self.current_eval_frame = &frame;
        defer {
            self.current_eval_frame = frame.parent;
            frame.deps.deinit(self.backing_allocator);
        }

        const value = try self.evalNodeUncached(allocator, node_id, scope);
        const deps = try self.backing_allocator.alloc(ScopedNodeKey, frame.deps.items.len);
        @memcpy(deps, frame.deps.items);
        if (frame.parent) |parent| {
            for (frame.deps.items) |dep| try self.addFrameDependency(parent, dep);
        }
        try self.eval_cache.put(self.backing_allocator, cache_key, .{
            .value = value,
            .deps = deps,
        });
        return value;
    }

    fn evalNodeUncached(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!Value {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .number => |number| .{ .number = number.value },
            .atom => |text| .{ .text = text },
            .symbol => |text| .{ .symbol = text },
            .local_ref => |name| lookupLocal(scope, name) orelse error.MissingLocalBinding,
            .special => |special| switch (special) {
                .pass_ref, .passed_ref => if (scope) |frame| frame.passed orelse .none else .none,
                else => .none,
            },
            .link_port => blk: {
                try self.recordStateDependency(self.scopedStateKey(node_id, scope));
                break :blk self.getLinkValue(node_id, scope) orelse .{ .link = node_id };
            },
            .binding_ref => |binding_id| try self.evalNode(allocator, self.flow.bindings[binding_id].node, null),
            .text => |parts| try self.evalText(allocator, parts, scope),
            .list => |list| try self.evalList(allocator, list.items, scope),
            .record => |fields| try self.evalRecord(allocator, fields, scope),
            .access => |access| try self.evalAccess(allocator, access, scope),
            .block => |block| try self.evalBlock(allocator, block, scope),
            .when => |when| try self.evalWhen(allocator, when, scope),
            .binary => |binary| try self.evalBinary(allocator, binary, scope),
            .latest => |latest| blk: {
                const latest_scope = if (self.nodeNeedsScope(node_id)) scope else null;
                try self.recordStateDependency(self.scopedStateKey(node_id, latest_scope));
                if (self.getLatestPayload(node_id, latest_scope)) |current| break :blk switch (current) {
                    .node => |current_node| try self.evalNode(allocator, current_node, scope),
                    .value => |current_value| current_value,
                };
                if (latest.initial) |initial| break :blk try self.evalNode(allocator, initial, latest_scope);
                break :blk .none;
            },
            .then_value => |then_value| try self.evalNode(allocator, then_value.value, scope),
            .hold => |hold| blk: {
                const hold_scope = self.holdStorageScope(node_id, hold, scope);
                try self.recordStateDependency(self.scopedStateKey(node_id, hold_scope));
                if (self.getHoldValue(node_id, hold_scope)) |value| break :blk value;
                break :blk try self.evalNode(allocator, hold.initial, hold_scope);
            },
            .linked_value => |linked| try self.evalLinkedValue(allocator, linked, scope),
            .builtin_call => |call| try self.evalBuiltin(allocator, node_id, call, scope),
            .user_call => |call| try self.evalUserCall(allocator, call, scope),
        };
    }

    fn evalText(self: *Session, allocator: std.mem.Allocator, parts: []flow_ir.NodeId, scope: ?*const EvalScope) anyerror!Value {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);

        for (parts) |part| {
            try self.appendRenderedValue(&output, allocator, try self.evalNode(allocator, part, scope));
        }
        return .{ .text = try output.toOwnedSlice(allocator) };
    }

    fn evalList(self: *Session, allocator: std.mem.Allocator, items: []flow_ir.NodeId, scope: ?*const EvalScope) anyerror!Value {
        var values = try allocator.alloc(Value, items.len);
        for (items, 0..) |item, index| values[index] = try self.evalNode(allocator, item, scope);
        return .{ .list = values };
    }

    fn evalRecord(self: *Session, allocator: std.mem.Allocator, fields: []flow_ir.Field, scope: ?*const EvalScope) anyerror!Value {
        var values: std.ArrayList(RecordField) = .empty;
        defer values.deinit(allocator);

        var record_scope = EvalScope{
            .bindings = &.{},
            .parent = scope,
            .passed = if (scope) |parent| parent.passed else null,
            .id = deriveRecordScopeId(scope, &.{}, if (scope) |parent| parent.passed else null),
        };

        for (fields) |field| {
            if (field.name.len == 0) {
                const spread_value = try self.evalNode(allocator, field.value, &record_scope);
                const spread_fields = switch (spread_value) {
                    .record => |spread_fields| spread_fields,
                    .binding_ref => |binding_id| blk: {
                        const resolved = try self.evalNode(allocator, self.flow.bindings[binding_id].node, &record_scope);
                        break :blk switch (resolved) {
                            .record => |resolved_fields| resolved_fields,
                            else => return error.ExpectedRecordValue,
                        };
                    },
                    else => return error.ExpectedRecordValue,
                };
                for (spread_fields) |spread_field| {
                    try values.append(allocator, spread_field);
                    record_scope.bindings = values.items;
                    record_scope.id = deriveRecordScopeId(record_scope.parent, record_scope.bindings, record_scope.passed);
                }
                continue;
            }

            const field_value = if (self.nodeNeedsScope(field.value) or self.nodeNeedsDeferredField(field.value)) blk: {
                const deferred_scope = if (self.nodeNeedsScope(field.value)) &record_scope else canonicalControlScope(&record_scope);
                const deferred = try allocator.create(ScopedNodeValue);
                deferred.* = .{
                    .node_id = field.value,
                    .scope = try captureScope(allocator, deferred_scope),
                };
                break :blk Value{ .scoped_node = deferred };
            } else switch (self.flow.nodes[field.value].kind) {
                .binding_ref => |binding_id| Value{ .binding_ref = binding_id },
                .link_port => Value{ .link = field.value },
                else => try self.evalNode(allocator, field.value, scope),
            };
            try values.append(allocator, .{
                .name = field.name,
                .value = field_value,
            });
            record_scope.bindings = values.items;
            record_scope.id = deriveRecordScopeId(record_scope.parent, record_scope.bindings, record_scope.passed);
        }
        return .{ .record = try values.toOwnedSlice(allocator) };
    }

    fn materializeValue(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror!Value {
        return switch (value) {
            .scoped_node => |deferred| blk: {
                if (self.trace_enabled) {
                    try self.logf("materialize scoped_node n{d} scope={?d}", .{
                        deferred.node_id,
                        if (deferred.scope) |scope| scope.id else null,
                    });
                }
                break :blk try self.evalNode(allocator, deferred.node_id, deferred.scope);
            },
            else => value,
        };
    }

    fn evalAccess(self: *Session, allocator: std.mem.Allocator, access: flow_ir.Access, scope: ?*const EvalScope) anyerror!Value {
        if (try self.resolveStaticFieldNode(access.target, access.field)) |field_node| {
            if (!self.nodeNeedsScope(field_node) and !self.nodeNeedsDeferredField(field_node)) {
                return try self.evalNode(allocator, field_node, scope);
            }
        }
        const target = if (try self.resolveStaticLinkNode(access.target)) |link|
            switch (access.field[0]) {
                else => blk: {
                    if (std.mem.eql(u8, access.field, "text") or
                        std.mem.eql(u8, access.field, "value") or
                        std.mem.eql(u8, access.field, "key") or
                        std.mem.eql(u8, access.field, "event"))
                    {
                        break :blk Value{ .link = link };
                    }
                    break :blk switch (self.flow.nodes[access.target].kind) {
                        .symbol => |text| lookupLocal(scope, text) orelse try self.evalNode(allocator, access.target, scope),
                        else => try self.evalNode(allocator, access.target, scope),
                    };
                },
            }
        else switch (self.flow.nodes[access.target].kind) {
            .symbol => |text| lookupLocal(scope, text) orelse try self.evalNode(allocator, access.target, scope),
            else => try self.evalNode(allocator, access.target, scope),
        };
        const result: anyerror!Value = switch (target) {
            .record => |fields| blk: {
                const field_value = findRecordValue(fields, access.field) orelse return error.MissingRecordField;
                break :blk switch (field_value) {
                    .link => |link| .{ .link = link },
                    .scoped_node => |deferred| if (!self.nodeNeedsScope(deferred.node_id) and self.nodeNeedsDeferredField(deferred.node_id)) blk2: {
                        const resolved = try self.evalNode(allocator, deferred.node_id, canonicalControlScope(deferred.scope));
                        break :blk2 switch (resolved) {
                            .link => |link| link_blk: {
                                try self.recordLinkDependencies(link, scope, false);
                                break :link_blk self.getLinkValue(link, scope) orelse resolved;
                            },
                            else => resolved,
                        };
                    } else blk2: {
                        const resolved = try self.materializeValue(allocator, field_value);
                        break :blk2 switch (resolved) {
                            .link => |link| link_blk: {
                                try self.recordLinkDependencies(link, scope, false);
                                break :link_blk self.getLinkValue(link, scope) orelse resolved;
                            },
                            else => resolved,
                        };
                    },
                    else => blk2: {
                        const resolved = try self.materializeValue(allocator, field_value);
                        break :blk2 switch (resolved) {
                            .link => |link| link_blk: {
                                try self.recordLinkDependencies(link, scope, false);
                                break :link_blk self.getLinkValue(link, scope) orelse resolved;
                            },
                            else => resolved,
                        };
                    },
                };
            },
            .binding_ref => |binding_id| blk: {
                const field_node = try self.resolveStaticFieldNode(self.flow.bindings[binding_id].node, access.field) orelse return error.MissingRecordField;
                break :blk try self.evalNode(allocator, field_node, scope);
            },
            .stripe => |stripe| blk: {
                if (std.mem.eql(u8, access.field, "hovered")) {
                    break :blk if (stripe.hovered_link) |link|
                        hovered_blk: {
                            try self.recordLinkDependencies(link, stripe.event_scope orelse scope, false);
                            break :hovered_blk self.getLinkValue(link, stripe.event_scope orelse scope) orelse .{ .link = link };
                        }
                    else
                        .none;
                }
                break :blk error.UnsupportedFieldAccess;
            },
            .label, .checkbox, .button, .text_input, .select, .slider => blk: {
                if (std.mem.eql(u8, access.field, "event")) {
                    break :blk try controlEventValue(allocator, target);
                }
                if (std.mem.eql(u8, access.field, "hovered")) {
                    break :blk switch (target) {
                        .button => |button| if (button.hovered_link) |link|
                            hovered_blk: {
                                try self.recordLinkDependencies(link, button.event_scope orelse scope, false);
                                break :hovered_blk self.getLinkValue(link, button.event_scope orelse scope) orelse .{ .link = link };
                            }
                        else
                            .none,
                        else => error.UnsupportedFieldAccess,
                    };
                }
                break :blk error.UnsupportedFieldAccess;
            },
            .link => |link| blk: {
                if (std.mem.eql(u8, access.field, "text")) {
                    try self.recordLinkDependencies(link, scope, false);
                    if (self.getLinkValue(link, scope)) |link_value| {
                        if (recordFieldFromValue(link_value, "text")) |field_value| break :blk field_value;
                    }
                    break :blk self.getLinkValue(link, scope) orelse .{ .text = "" };
                }
                if (std.mem.eql(u8, access.field, "value")) {
                    try self.recordLinkDependencies(link, scope, false);
                    if (self.getLinkValue(link, scope)) |link_value| {
                        if (recordFieldFromValue(link_value, "value")) |field_value| break :blk field_value;
                    }
                    break :blk self.getLinkValue(link, scope) orelse .none;
                }
                if (std.mem.eql(u8, access.field, "key")) {
                    try self.recordLinkDependencies(link, scope, true);
                    if (self.getLinkValue(link, scope)) |link_value| {
                        if (recordFieldFromValue(link_value, "key")) |field_value| break :blk field_value;
                    }
                    break :blk self.getLinkKeyValue(link, scope) orelse .none;
                }
                if (std.mem.eql(u8, access.field, "event")) {
                    try self.recordLinkDependencies(link, scope, true);
                    const link_value = self.getLinkValue(link, scope);
                    const key_value = self.getLinkKeyValue(link, scope);
                    const change_fields = try allocator.alloc(RecordField, 2);
                    change_fields[0] = .{
                        .name = "value",
                        .value = link_value orelse .none,
                    };
                    change_fields[1] = .{
                        .name = "text",
                        .value = link_value orelse .none,
                    };
                    const key_fields = try allocator.alloc(RecordField, 2);
                    key_fields[0] = .{
                        .name = "key",
                        .value = key_value orelse .none,
                    };
                    key_fields[1] = .{
                        .name = "text",
                        .value = link_value orelse .none,
                    };
                    const fields = try allocator.alloc(RecordField, 3);
                    fields[0] = .{
                        .name = "press",
                        .value = .{ .link = link },
                    };
                    fields[1] = .{
                        .name = "change",
                        .value = .{ .record = change_fields },
                    };
                    fields[2] = .{
                        .name = "key_down",
                        .value = .{ .record = key_fields },
                    };
                    break :blk .{ .record = fields };
                }
                try self.recordLinkDependencies(link, scope, false);
                if (self.getLinkValue(link, scope)) |link_value| {
                    if (recordFieldFromValue(link_value, access.field)) |field_value| break :blk field_value;
                }
                break :blk error.UnsupportedFieldAccess;
            },
            else => error.UnsupportedFieldAccess,
        };
        return result catch |err| {
            if (err == error.UnsupportedFieldAccess) {
                return err;
            }
            return err;
        };
    }

    fn evalBlock(self: *Session, allocator: std.mem.Allocator, block: flow_ir.Block, parent_scope: ?*const EvalScope) anyerror!Value {
        var bindings: std.ArrayList(RecordField) = .empty;
        defer bindings.deinit(allocator);

        var scope = EvalScope{
            .bindings = &.{},
            .parent = parent_scope,
            .passed = if (parent_scope) |parent| parent.passed else null,
            .id = deriveScopeId(parent_scope, &.{}, if (parent_scope) |parent| parent.passed else null),
        };

        for (block.bindings) |binding| {
            const value = try self.evalNode(allocator, binding.value, &scope);
            try bindings.append(allocator, .{
                .name = binding.name,
                .value = value,
            });
            scope.bindings = bindings.items;
            scope.id = deriveScopeId(scope.parent, scope.bindings, scope.passed);
        }

        return try self.evalNode(allocator, block.result, &scope);
    }

    fn evalWhen(self: *Session, allocator: std.mem.Allocator, when: flow_ir.When, scope: ?*const EvalScope) anyerror!Value {
        const input = try self.evalNode(allocator, when.input, scope);
        for (when.arms) |arm| {
            const pattern = try self.evalNode(allocator, arm.pattern, scope);
            const capture = try patternBinding(allocator, self.flow, arm.pattern, input, pattern);
            if (!matchesPattern(input, pattern) and capture == null) continue;
            const bindings: []const RecordField = if (capture) |binding| blk: {
                const buffer = try allocator.alloc(RecordField, 1);
                buffer[0] = binding;
                break :blk buffer;
            } else &.{};
            const arm_scope = EvalScope{
                .bindings = bindings,
                .parent = scope,
                .passed = if (scope) |parent| parent.passed else null,
                .id = deriveScopeId(scope, bindings, if (scope) |parent| parent.passed else null),
            };
            return try self.evalNode(allocator, arm.result, &arm_scope);
        }
        return .none;
    }

    fn evalLinkedValue(self: *Session, allocator: std.mem.Allocator, linked: flow_ir.LinkedValue, scope: ?*const EvalScope) anyerror!Value {
        const value = try self.evalNode(allocator, linked.value, scope);
        const link = if (try self.resolveStaticLinkNode(linked.target)) |static_link|
            static_link
        else blk: {
            const target = try self.evalNode(allocator, linked.target, scope);
            break :blk switch (target) {
                .link => |target_link| target_link,
                else => return error.ExpectedLinkValue,
            };
        };
        return switch (value) {
            .stripe => |stripe| blk: {
                const rebound = try allocator.create(StripeValue);
                rebound.* = stripe.*;
                rebound.hovered_link = link;
                break :blk .{ .stripe = rebound };
            },
            .label => |label| blk: {
                const rebound = try allocator.create(LabelValue);
                rebound.* = label.*;
                rebound.double_click_link = link;
                break :blk .{ .label = rebound };
            },
            .checkbox => |checkbox| blk: {
                const rebound = try allocator.create(CheckboxValue);
                rebound.* = checkbox.*;
                rebound.click_link = link;
                break :blk .{ .checkbox = rebound };
            },
            .button => |button| blk: {
                const rebound = try allocator.create(ButtonValue);
                rebound.* = button.*;
                rebound.press_link = link;
                break :blk .{ .button = rebound };
            },
            .text_input => |input| blk: {
                const rebound = try allocator.create(TextInputValue);
                rebound.* = input.*;
                rebound.change_link = link;
                rebound.key_link = link;
                rebound.blur_link = link;
                rebound.focus_link = link;
                break :blk .{ .text_input = rebound };
            },
            .select => |select| blk: {
                const rebound = try allocator.create(SelectValue);
                rebound.* = select.*;
                rebound.change_link = link;
                break :blk .{ .select = rebound };
            },
            .slider => |slider| blk: {
                const rebound = try allocator.create(SliderValue);
                rebound.* = slider.*;
                rebound.change_link = link;
                break :blk .{ .slider = rebound };
            },
            else => value,
        };
    }

    fn evalUserCall(self: *Session, allocator: std.mem.Allocator, call: flow_ir.UserCall, scope: ?*const EvalScope) anyerror!Value {
        const function = self.flow.functions[call.function];
        var bindings = try allocator.alloc(RecordField, function.params.len);
        var filled = try allocator.alloc(bool, function.params.len);
        @memset(filled, false);

        var positional_index: usize = 0;
        for (call.positional) |argument| {
            if (positional_index >= function.params.len) return error.TooManyArguments;
            bindings[positional_index] = .{
                .name = function.params[positional_index],
                .value = try self.evalNode(allocator, argument, scope),
            };
            if (bindings[positional_index].value == .none) return .none;
            filled[positional_index] = true;
            positional_index += 1;
        }

        for (call.named) |argument| {
            const param_index = findParamIndex(function.params, argument.name) orelse return error.UnknownFunctionArgument;
            bindings[param_index] = .{
                .name = function.params[param_index],
                .value = try self.evalNode(allocator, argument.value, scope),
            };
            if (bindings[param_index].value == .none) return .none;
            filled[param_index] = true;
        }

        for (filled, 0..) |is_filled, index| {
            if (!is_filled) return error.MissingFunctionArgument;
            _ = index;
        }

        const passed = if (call.pass_context) |pass_context|
            try self.evalNode(allocator, pass_context, scope)
        else if (scope) |parent|
            parent.passed
        else
            null;

        const function_scope = EvalScope{
            .bindings = bindings,
            .parent = null,
            .passed = passed,
            .id = deriveScopeId(null, bindings, passed),
        };
        return try self.evalNode(allocator, function.body, &function_scope);
    }

    fn evalBinary(self: *Session, allocator: std.mem.Allocator, binary: flow_ir.Binary, scope: ?*const EvalScope) anyerror!Value {
        const lhs = try self.evalNode(allocator, binary.lhs, scope);
        const rhs = try self.evalNode(allocator, binary.rhs, scope);
        const order = compareValues(lhs, rhs) catch null;
        return switch (binary.operator) {
            .add => .{ .number = try valueAsNumber(lhs) + try valueAsNumber(rhs) },
            .subtract => .{ .number = try valueAsNumber(lhs) - try valueAsNumber(rhs) },
            .multiply => .{ .number = try valueAsNumber(lhs) * try valueAsNumber(rhs) },
            .divide => .{ .number = try valueAsNumber(lhs) / try valueAsNumber(rhs) },
            .equal => booleanValue(valuesEqual(lhs, rhs)),
            .not_equal => booleanValue(!valuesEqual(lhs, rhs)),
            .greater => .{ .symbol = if ((order orelse return error.UnsupportedBinaryOperator) == .gt) "True" else "False" },
            .greater_equal => .{ .symbol = if ((order orelse return error.UnsupportedBinaryOperator) != .lt) "True" else "False" },
            .less => .{ .symbol = if ((order orelse return error.UnsupportedBinaryOperator) == .lt) "True" else "False" },
            .less_equal => .{ .symbol = if ((order orelse return error.UnsupportedBinaryOperator) != .gt) "True" else "False" },
            else => error.UnsupportedBinaryOperator,
        };
    }

    fn evalBuiltin(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, scope: ?*const EvalScope) anyerror!Value {
        if (std.mem.eql(u8, call.path, "Document/new") or std.mem.eql(u8, call.path, "Scene/new")) {
            const root_node = findNamed(call.named, "root") orelse if (call.positional.len != 0) call.positional[0] else return error.MissingRootArg;
            const document = try allocator.create(DocumentValue);
            document.* = .{ .root = try self.evalNode(allocator, root_node, scope) };
            return .{ .document = document };
        }
        if (std.mem.eql(u8, call.path, "Terminal/new")) {
            const root_node = findNamed(call.named, "root") orelse if (call.positional.len != 0) call.positional[0] else return error.MissingRootArg;
            const loop_node = findNamed(call.named, "loop") orelse return error.MissingArgument;
            const terminal = try allocator.create(TerminalValue);
            terminal.* = .{
                .root = try self.evalNode(allocator, root_node, scope),
                .loop = try self.evalNode(allocator, loop_node, scope),
            };
            return .{ .terminal = terminal };
        }
        if (std.mem.eql(u8, call.path, "Element/svg")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const children_node = findNamed(call.named, "children") orelse return error.MissingItemsArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, children_node, &element_scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (std.mem.eql(u8, call.path, "Element/svg_circle")) {
            const container = try allocator.create(ContainerValue);
            container.* = .{ .child = .none };
            return .{ .container = container };
        }
        if (std.mem.eql(u8, call.path, "Element/stack")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const layers_node = findNamed(call.named, "layers") orelse return error.MissingItemsArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const layers_value = try self.evalNode(allocator, layers_node, &element_scope);
            const layers = switch (layers_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            const stripe = try allocator.create(StripeValue);
            stripe.* = .{
                .items = layers,
                .direction = .column,
                .hovered_link = extractHoverLink(element_value),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .stripe = stripe };
        }
        if (std.mem.eql(u8, call.path, "Duration")) {
            if (findNamed(call.named, "seconds")) |seconds_node| {
                const seconds = try self.numberFromNode(seconds_node, scope);
                return .{ .duration_ms = @intFromFloat(seconds * 1000.0) };
            }
            if (findNamed(call.named, "milliseconds")) |milliseconds_node| {
                const milliseconds = try self.numberFromNode(milliseconds_node, scope);
                return .{ .duration_ms = @intFromFloat(milliseconds) };
            }
            return error.MissingDurationArg;
        }
        if (std.mem.eql(u8, call.path, "Terminal/columns")) {
            return .{ .number = @floatFromInt(self.terminal_columns) };
        }
        if (std.mem.eql(u8, call.path, "Terminal/rows")) {
            return .{ .number = @floatFromInt(self.terminal_rows) };
        }
        if (std.mem.eql(u8, call.path, "Router/route")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            return self.route_value;
        }
        if (std.mem.eql(u8, call.path, "Router/go_to")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            return self.route_value;
        }
        if (std.mem.eql(u8, call.path, "Theme/geometry")) {
            return try themeGeometryValueForScope(self, allocator, scope);
        }
        if (std.mem.eql(u8, call.path, "Theme/lights")) {
            return try themeLightsValueForScope(self, allocator, scope);
        }
        if (std.mem.startsWith(u8, call.path, "Light/")) {
            const fields = try allocator.alloc(RecordField, call.named.len + 1);
            fields[0] = .{ .name = "kind", .value = .{ .text = try allocator.dupe(u8, call.path) } };
            for (call.named, 0..) |field, index| {
                fields[index + 1] = .{
                    .name = field.name,
                    .value = try self.evalNode(allocator, field.value, scope),
                };
            }
            return .{ .record = fields };
        }
        if (std.mem.eql(u8, call.path, "Element/stripe") or std.mem.eql(u8, call.path, "Scene/Element/stripe")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const items_node = findNamed(call.named, "items") orelse return error.MissingItemsArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const items_value = try self.evalNode(allocator, items_node, &element_scope);
            const items = switch (items_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            const stripe = try allocator.create(StripeValue);
            stripe.* = .{
                .items = items,
                .direction = stripeDirectionFromValue(if (findNamed(call.named, "direction")) |direction_node|
                    try self.evalNode(allocator, direction_node, scope)
                else
                    .{ .symbol = "Column" }),
                .gap = if (findNamed(call.named, "gap")) |gap_node|
                    try valueAsIndex(try self.evalNode(allocator, gap_node, scope))
                else
                    0,
                .hovered_link = try self.resolveElementEventLink(element_node, "hovered", scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .stripe = stripe };
        }
        if (std.mem.eql(u8, call.path, "Element/label") or std.mem.eql(u8, call.path, "Scene/Element/label")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const label_node = findNamed(call.named, "label") orelse return error.MissingLabelArg;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const label = try allocator.create(LabelValue);
            label.* = .{
                .label = try self.evalNode(allocator, label_node, &element_scope),
                .click_link = try self.resolveElementEventLink(element_node, "click", scope),
                .double_click_link = try self.resolveElementEventLink(element_node, "double_click", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .label = label };
        }
        if (std.mem.eql(u8, call.path, "Element/container")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const child_node = findNamed(call.named, "child") orelse return error.MissingArgument;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, child_node, &element_scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (std.mem.eql(u8, call.path, "Scene/Element/block")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const child_node = findNamed(call.named, "child") orelse return error.MissingArgument;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, child_node, &element_scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (std.mem.eql(u8, call.path, "Element/paragraph") or std.mem.eql(u8, call.path, "Scene/Element/paragraph")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const contents_node = findNamed(call.named, "contents") orelse return error.MissingArgument;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, contents_node, &element_scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (std.mem.eql(u8, call.path, "Element/checkbox") or std.mem.eql(u8, call.path, "Scene/Element/checkbox")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const icon_node = findNamed(call.named, "icon") orelse return error.MissingArgument;
            const label_node = findNamed(call.named, "label");
            const checked_node = findNamed(call.named, "checked");
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const checkbox = try allocator.create(CheckboxValue);
            checkbox.* = .{
                .icon = try self.evalNode(allocator, icon_node, &element_scope),
                .label = if (label_node) |node| try self.evalNode(allocator, node, &element_scope) else .none,
                .checked = if (checked_node) |node| try self.evalNode(allocator, node, &element_scope) else .none,
                .click_link = try self.resolveElementEventLink(element_node, "click", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .checkbox = checkbox };
        }
        if (std.mem.eql(u8, call.path, "Scene/Element/text")) {
            const element_node = findNamed(call.named, "element");
            const text_node = findNamed(call.named, "text") orelse return error.MissingLabelArg;
            const element_value: Value = if (element_node) |node|
                try self.evalNode(allocator, node, scope)
            else
                .{ .record = &.{} };
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const label = try allocator.create(LabelValue);
            label.* = .{
                .label = try self.evalNode(allocator, text_node, &element_scope),
                .click_link = if (element_node) |node|
                    try self.resolveElementEventLink(node, "click", scope)
                else
                    null,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .label = label };
        }
        if (std.mem.eql(u8, call.path, "Text/empty")) {
            return .{ .text = "" };
        }
        if (std.mem.eql(u8, call.path, "Text/space")) {
            return .{ .text = " " };
        }
        if (std.mem.eql(u8, call.path, "Text/to_number")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| .{ .number = std.fmt.parseFloat(f64, text) catch std.math.nan(f64) },
                .symbol => |text| .{ .number = std.fmt.parseFloat(f64, text) catch std.math.nan(f64) },
                .number => value,
                else => .{ .number = std.math.nan(f64) },
            };
        }
        if (std.mem.eql(u8, call.path, "Text/trim")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| .{ .text = try allocator.dupe(u8, std.mem.trim(u8, text, " \n\r\t")) },
                .symbol => |text| .{ .text = try allocator.dupe(u8, std.mem.trim(u8, text, " \n\r\t")) },
                else => .{ .text = "" },
            };
        }
        if (std.mem.eql(u8, call.path, "Text/is_not_empty")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| booleanValue(text.len != 0),
                .symbol => |text| booleanValue(text.len != 0),
                else => booleanValue(false),
            };
        }
        if (std.mem.eql(u8, call.path, "Text/is_empty")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| booleanValue(text.len == 0),
                .symbol => |text| booleanValue(text.len == 0),
                else => booleanValue(true),
            };
        }
        if (std.mem.eql(u8, call.path, "Text/length")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
            return .{ .number = @floatFromInt(text.len) };
        }
        if (std.mem.eql(u8, call.path, "Text/find")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const search_node = findNamed(call.named, "search") orelse return error.MissingArgument;
            const haystack = try valueAsText(try self.evalNode(allocator, value_node, scope));
            const needle = try valueAsText(try self.evalNode(allocator, search_node, scope));
            return .{ .number = if (std.mem.indexOf(u8, haystack, needle)) |index| @floatFromInt(index) else -1 };
        }
        if (std.mem.eql(u8, call.path, "Text/substring")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const start_node = findNamed(call.named, "start") orelse return error.MissingArgument;
            const length_node = findNamed(call.named, "length") orelse return error.MissingArgument;
            const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
            const start = try valueAsIndex(try self.evalNode(allocator, start_node, scope));
            const length = try valueAsIndex(try self.evalNode(allocator, length_node, scope));
            const bounded_start = @min(start, text.len);
            const bounded_end = @min(bounded_start + length, text.len);
            return .{ .text = try allocator.dupe(u8, text[bounded_start..bounded_end]) };
        }
        if (std.mem.eql(u8, call.path, "Text/repeat")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const times_node = findNamed(call.named, "times") orelse return error.MissingArgument;
            const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
            const times_number = try valueAsNumber(try self.evalNode(allocator, times_node, scope));
            const times = @max(@as(i64, 0), @as(i64, @intFromFloat(times_number)));

            var output: std.ArrayList(u8) = .empty;
            defer output.deinit(allocator);
            try output.ensureTotalCapacity(allocator, text.len * @as(usize, @intCast(times)));
            var index: i64 = 0;
            while (index < times) : (index += 1) {
                try output.appendSlice(allocator, text);
            }
            return .{ .text = try output.toOwnedSlice(allocator) };
        }
        if (std.mem.eql(u8, call.path, "Text/join")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const items = try listItemsFromValue(try self.evalNode(allocator, value_node, scope));

            var output: std.ArrayList(u8) = .empty;
            defer output.deinit(allocator);

            for (items) |item| {
                try output.appendSlice(allocator, try valueAsText(item));
            }
            return .{ .text = try output.toOwnedSlice(allocator) };
        }
        if (std.mem.eql(u8, call.path, "Text/starts_with")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const prefix_node = findNamed(call.named, "prefix") orelse return error.MissingArgument;
            const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
            const prefix = try valueAsText(try self.evalNode(allocator, prefix_node, scope));
            return booleanValue(std.mem.startsWith(u8, text, prefix));
        }
        if (std.mem.eql(u8, call.path, "Bool/not")) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            return booleanValue(!try valueAsBool(try self.evalNode(allocator, value_node, scope)));
        }
        if (std.mem.eql(u8, call.path, "Bool/or")) {
            const lhs_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const rhs_node = findNamed(call.named, "that") orelse return error.MissingArgument;
            const lhs = try valueAsBool(try self.evalNode(allocator, lhs_node, scope));
            const rhs = try valueAsBool(try self.evalNode(allocator, rhs_node, scope));
            return booleanValue(lhs or rhs);
        }
        if (std.mem.eql(u8, call.path, "Bool/and")) {
            const lhs_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const rhs_node = findNamed(call.named, "that") orelse return error.MissingArgument;
            const lhs = try valueAsBool(try self.evalNode(allocator, lhs_node, scope));
            const rhs = try valueAsBool(try self.evalNode(allocator, rhs_node, scope));
            return booleanValue(lhs and rhs);
        }
        if (std.mem.eql(u8, call.path, "Element/button") or std.mem.eql(u8, call.path, "Scene/Element/button")) {
            const label_node = findNamed(call.named, "label") orelse return error.MissingLabelArg;
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const button = try allocator.create(ButtonValue);
            button.* = .{
                .label = try self.evalNode(allocator, label_node, &element_scope),
                .press_link = try self.resolveElementEventLink(element_node, "press", scope),
                .hovered_link = try self.resolveElementEventLink(element_node, "hovered", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .button = button };
        }
        if (std.mem.eql(u8, call.path, "Element/text_input") or std.mem.eql(u8, call.path, "Scene/Element/text_input")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const text_node = findNamed(call.named, "text") orelse return error.MissingArgument;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const input = try allocator.create(TextInputValue);
            input.* = .{
                .text = try self.evalNode(allocator, text_node, &element_scope),
                .change_link = try self.resolveElementEventLink(element_node, "change", scope),
                .key_link = try self.resolveElementEventLink(element_node, "key_down", scope),
                .blur_link = try self.resolveElementEventLink(element_node, "blur", scope),
                .focus_link = try self.resolveElementEventLink(element_node, "focus", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .text_input = input };
        }
        if (std.mem.eql(u8, call.path, "Element/select")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const selected_node = findNamed(call.named, "selected") orelse return error.MissingArgument;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const select = try allocator.create(SelectValue);
            select.* = .{
                .selected = try self.evalNode(allocator, selected_node, &element_scope),
                .change_link = try self.resolveElementEventLink(element_node, "change", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .select = select };
        }
        if (std.mem.eql(u8, call.path, "Element/link") or std.mem.eql(u8, call.path, "Scene/Element/link")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const label_node = findNamed(call.named, "label") orelse return error.MissingLabelArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const label = try allocator.create(LabelValue);
            label.* = .{ .label = try self.evalNode(allocator, label_node, &element_scope) };
            label.terminal_bindings = extractTerminalMetadata(element_value);
            label.event_scope = try captureScope(allocator, &element_scope);
            return .{ .label = label };
        }
        if (std.mem.eql(u8, call.path, "Assets/icon")) {
            const icons = try allocator.alloc(RecordField, 2);
            icons[0] = .{ .name = "checkbox_completed", .value = .{ .text = "X" } };
            icons[1] = .{ .name = "checkbox_active", .value = .{ .text = "O" } };
            return .{ .record = icons };
        }
        if (std.mem.eql(u8, call.path, "Element/slider")) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const slider = try allocator.create(SliderValue);
            slider.* = .{
                .change_link = try self.resolveElementEventLink(element_node, "change", scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureScope(allocator, &element_scope),
            };
            return .{ .slider = slider };
        }
        if (std.mem.eql(u8, call.path, "Math/sum")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.sum_inited[node_id]) return .none;
            return .{ .number = self.sum_values[node_id] };
        }
        if (std.mem.eql(u8, call.path, "Math/min")) {
            const lhs = if (call.positional.len != 0) try self.numberFromNode(call.positional[0], scope) else return error.MissingArgument;
            const rhs_node = findNamed(call.named, "b") orelse return error.MissingArgument;
            const rhs = try self.numberFromNode(rhs_node, scope);
            return .{ .number = @min(lhs, rhs) };
        }
        if (std.mem.eql(u8, call.path, "Math/round")) {
            const value = if (call.positional.len != 0) try self.numberFromNode(call.positional[0], scope) else return error.MissingArgument;
            return .{ .number = @round(value) };
        }
        if (std.mem.eql(u8, call.path, "Ulid/generate")) {
            const key = if (self.persist_ids.len != 0 and node_id < self.persist_ids.len and self.persist_ids[node_id] != 0)
                self.persist_ids[node_id]
            else
                @as(u64, node_id);
            return .{ .text = try std.fmt.allocPrint(allocator, "ulid-{x}", .{key}) };
        }
        if (std.mem.eql(u8, call.path, "Log/info") or std.mem.eql(u8, call.path, "Log/error")) {
            if (call.positional.len == 0) return .none;
            return try self.evalNode(allocator, call.positional[0], scope);
        }
        if (std.mem.eql(u8, call.path, "List/append")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.list_inited[node_id]) {
                const base_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                const base_value = try self.evalNode(allocator, base_node, scope);
                const current = try listItemsFromValue(base_value);
                if (findNamed(call.named, "on") != null) return .{ .list = current };
                const item = if (findNamed(call.named, "item")) |item_node|
                    try self.evalNode(allocator, item_node, scope)
                else if (findNamed(call.named, "on")) |on_node|
                    try self.evalNode(allocator, on_node, scope)
                else
                    return error.MissingArgument;
                if (item == .none) return .{ .list = current };
                const next = try allocator.alloc(Value, current.len + 1);
                @memcpy(next[0..current.len], current);
                next[current.len] = item;
                return .{ .list = next };
            }
            return self.list_values[node_id];
        }
        if (std.mem.eql(u8, call.path, "List/clear")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.list_inited[node_id]) {
                const base_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                return try self.evalNode(allocator, base_node, scope);
            }
            return self.list_values[node_id];
        }
        if (std.mem.eql(u8, call.path, "List/remove")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.list_inited[node_id]) {
                const base_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                const base_value = try self.evalNode(allocator, base_node, scope);
                return try self.filterRemovedItems(self.arena.allocator(), base_value, self.list_remove_tombstones[node_id]);
            }
            return self.list_values[node_id];
        }
        if (std.mem.eql(u8, call.path, "List/remove_last")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.list_inited[node_id]) {
                const base_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                return try self.evalNode(allocator, base_node, scope);
            }
            return self.list_values[node_id];
        }
        if (std.mem.eql(u8, call.path, "List/count")) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            return switch (list_value) {
                .list => |items| .{ .number = @floatFromInt(items.len) },
                else => error.ExpectedListValue,
            };
        }
        if (std.mem.eql(u8, call.path, "List/is_empty")) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            return switch (list_value) {
                .list => |items| booleanValue(items.len == 0),
                else => error.ExpectedListValue,
            };
        }
        if (std.mem.eql(u8, call.path, "List/is_not_empty")) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            return switch (list_value) {
                .list => |items| booleanValue(items.len != 0),
                else => error.ExpectedListValue,
            };
        }
        if (std.mem.eql(u8, call.path, "List/get")) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const index_node = findNamed(call.named, "index") orelse return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            const items = switch (list_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            const index = try valueAsIndex(try self.evalNode(allocator, index_node, scope));
            if (index == 0 or index > items.len) return .none;
            return items[index - 1];
        }
        if (std.mem.eql(u8, call.path, "List/range")) {
            const from_node = findNamed(call.named, "from") orelse return error.MissingArgument;
            const to_node = findNamed(call.named, "to") orelse return error.MissingArgument;
            const from_value = try valueAsIndex(try self.evalNode(allocator, from_node, scope));
            const to_value = try valueAsIndex(try self.evalNode(allocator, to_node, scope));
            if (to_value < from_value) return .{ .list = &.{} };
            const count = to_value - from_value + 1;
            const items = try allocator.alloc(Value, count);
            for (items, 0..) |*item, offset| {
                item.* = .{ .number = @floatFromInt(from_value + offset) };
            }
            return .{ .list = items };
        }
        if (std.mem.eql(u8, call.path, "List/map")) {
            if (call.positional.len < 2) return error.MissingArgument;
            const list_value = try self.evalNode(allocator, call.positional[0], scope);
            const items = switch (list_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            const item_name = switch (self.flow.nodes[call.positional[1]].kind) {
                .symbol => |text| text,
                else => return error.MissingLocalBinding,
            };
            const mapper = findNamed(call.named, "new") orelse return error.MissingArgument;
            var mapped = try allocator.alloc(Value, items.len);
            for (items, 0..) |item, index| {
                const bindings = try allocator.alloc(RecordField, 1);
                bindings[0] = .{ .name = item_name, .value = item };
                const map_scope = EvalScope{
                    .bindings = bindings,
                    .parent = scope,
                    .passed = if (scope) |parent| parent.passed else null,
                    .id = deriveScopeId(scope, bindings, if (scope) |parent| parent.passed else null),
                };
                mapped[index] = try self.evalNode(allocator, mapper, &map_scope);
            }
            return .{ .list = mapped };
        }
        if (std.mem.eql(u8, call.path, "List/retain")) {
            if (call.positional.len < 2) return error.MissingArgument;
            const list_value = try self.evalNode(allocator, call.positional[0], scope);
            const items = switch (list_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            const item_name = switch (self.flow.nodes[call.positional[1]].kind) {
                .symbol => |text| text,
                else => return error.MissingLocalBinding,
            };
            const predicate = findNamed(call.named, "if") orelse return error.MissingArgument;
            var retained: std.ArrayList(Value) = .empty;
            defer retained.deinit(allocator);
            for (items) |item| {
                const bindings = try allocator.alloc(RecordField, 1);
                bindings[0] = .{ .name = item_name, .value = item };
                const retain_scope = EvalScope{
                    .bindings = bindings,
                    .parent = scope,
                    .passed = if (scope) |parent| parent.passed else null,
                    .id = deriveScopeId(scope, bindings, if (scope) |parent| parent.passed else null),
                };
                if (!try valueAsBool(try self.evalNode(allocator, predicate, &retain_scope))) continue;
                try retained.append(allocator, item);
            }
            return .{ .list = try retained.toOwnedSlice(allocator) };
        }
        if (std.mem.eql(u8, call.path, "List/any") or std.mem.eql(u8, call.path, "List/every")) {
            if (call.positional.len < 2) return error.MissingArgument;
            const list_value = try self.evalNode(allocator, call.positional[0], scope);
            const items = switch (list_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            const item_name = switch (self.flow.nodes[call.positional[1]].kind) {
                .symbol => |text| text,
                else => return error.MissingLocalBinding,
            };
            const predicate = findNamed(call.named, "if") orelse return error.MissingArgument;
            const want_all = std.mem.eql(u8, call.path, "List/every");
            if (items.len == 0) return booleanValue(want_all);
            for (items) |item| {
                const bindings = try allocator.alloc(RecordField, 1);
                bindings[0] = .{ .name = item_name, .value = item };
                const predicate_scope = EvalScope{
                    .bindings = bindings,
                    .parent = scope,
                    .passed = if (scope) |parent| parent.passed else null,
                    .id = deriveScopeId(scope, bindings, if (scope) |parent| parent.passed else null),
                };
                const matched = try valueAsBool(try self.evalNode(allocator, predicate, &predicate_scope));
                if (!want_all and matched) return booleanValue(true);
                if (want_all and !matched) return booleanValue(false);
            }
            return booleanValue(want_all);
        }
        if (std.mem.eql(u8, call.path, "List/sum")) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            const items = switch (list_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            var sum: f64 = 0;
            for (items) |item| sum += try valueAsNumber(item);
            return .{ .number = sum };
        }
        if (std.mem.eql(u8, call.path, "Stream/pulses")) return .none;
        if (std.mem.eql(u8, call.path, "Stream/skip")) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.skip_inited[node_id] and scope != null) {
                try self.initSkipNode(allocator, node_id, call, scope);
                if (call.positional.len != 0) {
                    try self.primeScopedStream(call.positional[0], scope);
                    try self.processQueue();
                }
            }
            if (!self.skip_inited[node_id]) return .none;
            return self.skip_values[node_id];
        }
        if (std.mem.eql(u8, call.path, "Timer/interval")) return .none;
        if (std.mem.indexOfScalar(u8, call.path, '/')) |_| {} else {
            var fields = try allocator.alloc(RecordField, call.named.len);
            for (call.named, 0..) |field, index| {
                fields[index] = .{
                    .name = field.name,
                    .value = try self.evalNode(allocator, field.value, scope),
                };
            }
            return .{ .record = fields };
        }
        if (self.trace_enabled) {
            std.debug.print("unsupported builtin {s}\n", .{call.path});
        }
        return error.UnsupportedBuiltinCall;
    }

    fn latestImplicitInitialSource(self: *Session, latest: flow_ir.Latest) ?flow_ir.NodeId {
        for (latest.sources) |source| {
            if (self.nodeCanSeedLatest(source)) return source;
        }
        return null;
    }

    fn nodeCanSeedLatest(self: *Session, node_id: flow_ir.NodeId) bool {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| self.nodeCanSeedLatest(self.flow.bindings[binding_id].node),
            .then_value, .latest, .hold, .link_port => false,
            .builtin_call => |call| !std.mem.eql(u8, call.path, "Stream/skip") and !std.mem.eql(u8, call.path, "Stream/pulses") and !std.mem.eql(u8, call.path, "Timer/interval"),
            else => true,
        };
    }

    fn renderValue(self: *Session, writer: std.Io.Writer, value: Value) !void {
        switch (value) {
            .number => |number| {
                if (std.math.isFinite(number) and @round(number) == number) {
                    try writer.print("{d}", .{@as(i64, @intFromFloat(number))});
                } else {
                    try writer.print("{d}", .{number});
                }
            },
            .text => |text| try writer.writeAll(text),
            .symbol => |text| try writer.writeAll(text),
            .duration_ms => |duration_ms| try writer.print("{d}ms", .{duration_ms}),
            .list => |items| for (items) |item| try self.renderValue(writer, item),
            .record => {},
            .binding_ref => {},
            .document => |document| try self.renderValue(writer, document.root),
            .terminal => |terminal| try self.renderValue(writer, terminal.root),
            .stripe => |stripe| for (stripe.items) |item| try self.renderValue(writer, item),
            .label => |label| try self.renderValue(writer, label.label),
            .container => |container| try self.renderValue(writer, container.child),
            .checkbox => |checkbox| try self.renderValue(writer, checkbox.icon),
            .button => |button| try self.renderValue(writer, button.label),
            .text_input => |input| try self.renderValue(writer, input.text),
            .select => |select| try self.renderValue(writer, select.selected),
            .scoped_node => |deferred| try self.renderValue(writer, try self.evalNode(self.arena.allocator(), deferred.node_id, deferred.scope)),
            .slider, .link, .none => {},
        }
    }

    fn appendRenderedValue(self: *Session, output: *std.ArrayList(u8), allocator: std.mem.Allocator, value: Value) anyerror!void {
        switch (value) {
            .number => |number| {
                var buffer: [64]u8 = undefined;
                const text = if (std.math.isFinite(number) and @round(number) == number)
                    try std.fmt.bufPrint(&buffer, "{d}", .{@as(i64, @intFromFloat(number))})
                else
                    try std.fmt.bufPrint(&buffer, "{d}", .{number});
                try output.appendSlice(allocator, text);
            },
            .text => |text| try output.appendSlice(allocator, text),
            .symbol => |text| try output.appendSlice(allocator, text),
            .duration_ms => |duration_ms| {
                var buffer: [64]u8 = undefined;
                const text = try std.fmt.bufPrint(&buffer, "{d}ms", .{duration_ms});
                try output.appendSlice(allocator, text);
            },
            .list => |items| for (items) |item| try self.appendRenderedValue(output, allocator, item),
            .record => {},
            .binding_ref => {},
            .document => |document| try self.appendRenderedValue(output, allocator, document.root),
            .terminal => |terminal| try self.appendRenderedValue(output, allocator, terminal.root),
            .stripe => |stripe| for (stripe.items) |item| try self.appendRenderedValue(output, allocator, item),
            .label => |label| try self.appendRenderedValue(output, allocator, label.label),
            .container => |container| try self.appendRenderedValue(output, allocator, container.child),
            .checkbox => |checkbox| try self.appendRenderedValue(output, allocator, checkbox.icon),
            .button => |button| try self.appendRenderedValue(output, allocator, button.label),
            .text_input => |input| try self.appendRenderedValue(output, allocator, input.text),
            .select => |select| try self.appendRenderedValue(output, allocator, select.selected),
            .scoped_node => |deferred| try self.appendRenderedValue(output, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
            .slider, .link, .none => {},
        }
    }

    fn snapshotBlock(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror!GridBlock {
        return switch (value) {
            .document => |document| try self.snapshotBlock(allocator, document.root),
            .terminal => |terminal| try self.snapshotBlock(allocator, terminal.root),
            .stripe => |stripe| switch (stripe.direction) {
                .row => try self.snapshotRowBlock(allocator, stripe.items, stripe.gap),
                .column => try self.snapshotColumnBlock(allocator, stripe.items),
            },
            .label => |label| try self.snapshotSizedBlock(
                allocator,
                try self.snapshotBlock(allocator, label.label),
                label.terminal_width,
                label.terminal_height,
            ),
            .container => |container| try self.snapshotBlock(allocator, container.child),
            .checkbox => |checkbox| try self.snapshotSizedBlock(
                allocator,
                try self.snapshotCheckboxBlock(allocator, checkbox),
                checkbox.terminal_width,
                checkbox.terminal_height,
            ),
            .button => |button| try self.snapshotSizedBlock(
                allocator,
                try self.snapshotWrappedBlock(allocator, button.label, "[", "]"),
                button.terminal_width,
                button.terminal_height,
            ),
            .text_input => |input| try self.snapshotSizedBlock(
                allocator,
                try self.snapshotWrappedBlock(allocator, input.text, "<", ">"),
                input.terminal_width,
                input.terminal_height,
            ),
            .select => |select| try self.snapshotSizedBlock(
                allocator,
                try self.snapshotWrappedBlock(allocator, select.selected, "<", ">"),
                select.terminal_width,
                select.terminal_height,
            ),
            .scoped_node => |deferred| try self.snapshotBlock(allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
            .slider => try self.snapshotLiteralBlock(allocator, "<slider>"),
            else => try self.snapshotInlineBlock(allocator, value),
        };
    }

    fn snapshotRowBlock(self: *Session, allocator: std.mem.Allocator, items: []Value, gap: usize) anyerror!GridBlock {
        if (items.len == 0) return try self.snapshotLiteralBlock(allocator, "");

        const child_blocks = try allocator.alloc(GridBlock, items.len);
        var total_width: usize = 0;
        var height: usize = 0;
        for (items, 0..) |item, index| {
            const block = try self.snapshotBlock(allocator, item);
            child_blocks[index] = block;
            total_width += block.width;
            if (index != 0) total_width += gap;
            height = @max(height, block.lines.len);
        }
        if (height == 0) height = 1;

        const lines = try allocator.alloc([]const u8, height);
        for (0..height) |row_index| {
            var line: std.ArrayList(u8) = .empty;
            defer line.deinit(allocator);

            for (child_blocks, 0..) |block, block_index| {
                if (block_index != 0 and gap != 0) try line.appendNTimes(allocator, ' ', gap);
                const segment = if (row_index < block.lines.len) block.lines[row_index] else "";
                try line.appendSlice(allocator, segment);
                if (segment.len < block.width) {
                    try line.appendNTimes(allocator, ' ', block.width - segment.len);
                }
            }
            lines[row_index] = try line.toOwnedSlice(allocator);
        }

        return .{ .lines = lines, .width = total_width };
    }

    fn snapshotColumnBlock(self: *Session, allocator: std.mem.Allocator, items: []Value) anyerror!GridBlock {
        if (items.len == 0) return try self.snapshotLiteralBlock(allocator, "");

        const child_blocks = try allocator.alloc(GridBlock, items.len);
        var total_lines: usize = 0;
        var width: usize = 0;
        for (items, 0..) |item, index| {
            const block = try self.snapshotBlock(allocator, item);
            child_blocks[index] = block;
            total_lines += @max(block.lines.len, 1);
            width = @max(width, block.width);
        }

        const lines = try allocator.alloc([]const u8, total_lines);
        var cursor: usize = 0;
        for (child_blocks) |block| {
            if (block.lines.len == 0) {
                lines[cursor] = "";
                cursor += 1;
                continue;
            }
            for (block.lines) |line| {
                lines[cursor] = line;
                cursor += 1;
            }
        }
        return .{ .lines = lines, .width = width };
    }

    fn snapshotWrappedBlock(self: *Session, allocator: std.mem.Allocator, value: Value, prefix: []const u8, suffix: []const u8) anyerror!GridBlock {
        const inner = try self.inlineRenderedValueAlloc(allocator, value);
        return try self.snapshotLiteralBlock(allocator, try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, inner, suffix }));
    }

    fn snapshotCheckboxBlock(self: *Session, allocator: std.mem.Allocator, checkbox: *CheckboxValue) anyerror!GridBlock {
        const display = try self.checkboxDisplayAlloc(allocator, checkbox);
        return try self.snapshotLiteralBlock(allocator, display);
    }

    fn snapshotSizedBlock(
        self: *Session,
        allocator: std.mem.Allocator,
        block: GridBlock,
        min_width: usize,
        min_height: usize,
    ) anyerror!GridBlock {
        _ = self;

        const target_width = @max(block.width, min_width);
        const target_height = @max(@max(block.lines.len, 1), if (min_height == 0) @as(usize, 1) else min_height);

        if (target_width == block.width and target_height == @max(block.lines.len, 1)) return block;

        const lines = try allocator.alloc([]const u8, target_height);
        var row_index: usize = 0;
        while (row_index < target_height) : (row_index += 1) {
            if (row_index < block.lines.len) {
                const line = block.lines[row_index];
                if (line.len >= target_width) {
                    lines[row_index] = line;
                } else {
                    var padded: std.ArrayList(u8) = .empty;
                    defer padded.deinit(allocator);
                    try padded.appendSlice(allocator, line);
                    try padded.appendNTimes(allocator, ' ', target_width - line.len);
                    lines[row_index] = try padded.toOwnedSlice(allocator);
                }
            } else {
                lines[row_index] = try allocator.alloc(u8, target_width);
                @memset(@constCast(lines[row_index]), ' ');
            }
        }

        return .{ .lines = lines, .width = target_width };
    }

    fn snapshotInlineBlock(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror!GridBlock {
        return try self.snapshotLiteralBlock(allocator, try self.inlineRenderedValueAlloc(allocator, value));
    }

    fn snapshotLiteralBlock(self: *Session, allocator: std.mem.Allocator, text: []const u8) anyerror!GridBlock {
        _ = self;
        const lines = try allocator.alloc([]const u8, 1);
        lines[0] = text;
        return .{ .lines = lines, .width = text.len };
    }

    fn collectControlSummary(self: *Session, allocator: std.mem.Allocator, summary: *ControlSummary, value: Value) anyerror!void {
        switch (value) {
            .list => |items| for (items) |item| try self.collectControlSummary(allocator, summary, item),
            .document => |document| try self.collectControlSummary(allocator, summary, document.root),
            .terminal => |terminal| try self.collectControlSummary(allocator, summary, terminal.root),
            .stripe => |stripe| {
                if (stripe.hovered_link != null) try summary.hovers.append(allocator, try self.hoverDisplayAlloc(allocator, .{ .stripe = stripe }));
                for (stripe.items) |item| try self.collectControlSummary(allocator, summary, item);
            },
            .label => |label| {
                if (label.click_link != null) {
                    try summary.clicks.append(allocator, try self.inlineRenderedValueAlloc(allocator, label.label));
                }
                if (label.double_click_link != null) {
                    try summary.double_clicks.append(allocator, try self.inlineRenderedValueAlloc(allocator, label.label));
                }
            },
            .container => |container| try self.collectControlSummary(allocator, summary, container.child),
            .checkbox => |checkbox| {
                if (checkbox.click_link != null) {
                    try summary.clicks.append(allocator, try self.checkboxControlLabelAlloc(allocator, checkbox));
                }
            },
            .button => |button| {
                if (button.press_link != null) {
                    try summary.clicks.append(allocator, try self.inlineRenderedValueAlloc(allocator, button.label));
                }
                if (button.hovered_link != null) {
                    try summary.hovers.append(allocator, try self.inlineRenderedValueAlloc(allocator, button.label));
                }
            },
            .text_input => |input| {
                if (input.change_link != null or input.key_link != null or input.blur_link != null or input.focus_link != null) {
                    try summary.text_inputs.append(allocator, try self.inlineRenderedValueAlloc(allocator, input.text));
                }
            },
            .select => |select| {
                if (select.change_link != null) {
                    try summary.selects.append(allocator, try self.inlineRenderedValueAlloc(allocator, select.selected));
                }
            },
            .scoped_node => |deferred| try self.collectControlSummary(allocator, summary, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
            else => {},
        }
    }

    fn collectTerminalHitRegions(
        self: *Session,
        allocator: std.mem.Allocator,
        regions: *std.ArrayList(TerminalHitRegion),
        counters: *TerminalLayoutCounters,
        value: Value,
        x: usize,
        y: usize,
    ) anyerror!TerminalLayoutSize {
        return switch (value) {
            .document => |document| try self.collectTerminalHitRegions(allocator, regions, counters, document.root, x, y),
            .terminal => |terminal| try self.collectTerminalHitRegions(allocator, regions, counters, terminal.root, x, y),
            .list => |items| try self.collectTerminalHitRow(allocator, regions, counters, items, x, y, 0),
            .stripe => |stripe| switch (stripe.direction) {
                .row => blk: {
                    const hover_index = if (stripe.hovered_link != null) blk_hover: {
                        const index = counters.hover;
                        counters.hover += 1;
                        break :blk_hover index;
                    } else null;
                    const size = try self.collectTerminalHitRow(allocator, regions, counters, stripe.items, x, y, stripe.gap);
                    if (hover_index) |index| {
                        try regions.append(allocator, .{
                            .x = x,
                            .y = y,
                            .width = size.width,
                            .height = size.height,
                            .hover_index = index,
                        });
                    }
                    break :blk size;
                },
                .column => blk: {
                    const hover_index = if (stripe.hovered_link != null) blk_hover: {
                        const index = counters.hover;
                        counters.hover += 1;
                        break :blk_hover index;
                    } else null;

                    var cursor_y = y;
                    var width: usize = 0;
                    for (stripe.items) |item| {
                        const child_size = try self.collectTerminalHitRegions(allocator, regions, counters, item, x, cursor_y);
                        cursor_y += child_size.height;
                        width = @max(width, child_size.width);
                    }
                    const size = TerminalLayoutSize{
                        .width = width,
                        .height = cursor_y - y,
                    };
                    if (hover_index) |index| {
                        try regions.append(allocator, .{
                            .x = x,
                            .y = y,
                            .width = size.width,
                            .height = size.height,
                            .hover_index = index,
                        });
                    }
                    break :blk size;
                },
            },
            .label => |label| blk: {
                const click_index = if (label.click_link != null) blk_click: {
                    const index = counters.button;
                    counters.button += 1;
                    break :blk_click index;
                } else null;
                const double_click_index = if (label.double_click_link != null) blk_double: {
                    const index = counters.label_double_click;
                    counters.label_double_click += 1;
                    break :blk_double index;
                } else null;
                const child_size = try self.collectTerminalHitRegions(allocator, regions, counters, label.label, x, y);
                const size = TerminalLayoutSize{
                    .width = @max(child_size.width, label.terminal_width),
                    .height = @max(child_size.height, if (label.terminal_height == 0) @as(usize, 1) else label.terminal_height),
                };
                if (click_index != null or double_click_index != null) {
                    try regions.append(allocator, .{
                        .x = x,
                        .y = y,
                        .width = size.width,
                        .height = size.height,
                        .button_index = click_index,
                        .label_double_click_index = double_click_index,
                    });
                }
                break :blk size;
            },
            .container => |container| try self.collectTerminalHitRegions(allocator, regions, counters, container.child, x, y),
            .checkbox => |checkbox| blk: {
                const index = if (checkbox.click_link != null) blk_click: {
                    const next = counters.button;
                    counters.button += 1;
                    break :blk_click next;
                } else null;
                const block = try self.snapshotCheckboxBlock(allocator, checkbox);
                const width = @max(block.width, checkbox.terminal_width);
                const height = @max(@max(block.lines.len, 1), if (checkbox.terminal_height == 0) @as(usize, 1) else checkbox.terminal_height);
                if (index) |click_index| {
                    try regions.append(allocator, .{
                        .x = x,
                        .y = y,
                        .width = width,
                        .height = height,
                        .button_index = click_index,
                    });
                }
                break :blk .{ .width = width, .height = height };
            },
            .button => |button| blk: {
                const button_index = if (button.press_link != null) blk_click: {
                    const next = counters.button;
                    counters.button += 1;
                    break :blk_click next;
                } else null;
                const hover_index = if (button.hovered_link != null) blk_hover: {
                    const next = counters.hover;
                    counters.hover += 1;
                    break :blk_hover next;
                } else null;
                const block = try self.snapshotWrappedBlock(allocator, button.label, "[", "]");
                const width = @max(block.width, button.terminal_width);
                const height = @max(@max(block.lines.len, 1), if (button.terminal_height == 0) @as(usize, 1) else button.terminal_height);
                if (button_index != null or hover_index != null) {
                    try regions.append(allocator, .{
                        .x = x,
                        .y = y,
                        .width = width,
                        .height = height,
                        .button_index = button_index,
                        .hover_index = hover_index,
                    });
                }
                break :blk .{ .width = width, .height = height };
            },
            .text_input => |input| blk: {
                const text_input_index = if (input.change_link != null) blk_input: {
                    const next = counters.text_input;
                    counters.text_input += 1;
                    break :blk_input next;
                } else null;
                const block = try self.snapshotWrappedBlock(allocator, input.text, "<", ">");
                const width = @max(block.width, input.terminal_width);
                const height = @max(@max(block.lines.len, 1), if (input.terminal_height == 0) @as(usize, 1) else input.terminal_height);
                if (text_input_index) |index| {
                    try regions.append(allocator, .{
                        .x = x,
                        .y = y,
                        .width = width,
                        .height = height,
                        .text_input_index = index,
                    });
                }
                break :blk .{ .width = width, .height = height };
            },
            .select => |select| blk: {
                const block = try self.snapshotWrappedBlock(allocator, select.selected, "<", ">");
                break :blk .{
                    .width = @max(block.width, select.terminal_width),
                    .height = @max(@max(block.lines.len, 1), if (select.terminal_height == 0) @as(usize, 1) else select.terminal_height),
                };
            },
            .slider => blk: {
                const block = try self.snapshotLiteralBlock(allocator, "<slider>");
                break :blk .{ .width = block.width, .height = @max(block.lines.len, 1) };
            },
            .scoped_node => |deferred| try self.collectTerminalHitRegions(allocator, regions, counters, try self.evalNode(allocator, deferred.node_id, deferred.scope), x, y),
            else => blk: {
                const block = try self.snapshotInlineBlock(allocator, value);
                break :blk .{ .width = block.width, .height = @max(block.lines.len, 1) };
            },
        };
    }

    fn collectTerminalHitRow(
        self: *Session,
        allocator: std.mem.Allocator,
        regions: *std.ArrayList(TerminalHitRegion),
        counters: *TerminalLayoutCounters,
        items: []Value,
        x: usize,
        y: usize,
        gap: usize,
    ) anyerror!TerminalLayoutSize {
        var cursor_x = x;
        var height: usize = if (items.len == 0) 1 else 0;
        for (items, 0..) |item, index| {
            if (index != 0) cursor_x += gap;
            const child_size = try self.collectTerminalHitRegions(allocator, regions, counters, item, cursor_x, y);
            cursor_x += child_size.width;
            height = @max(height, child_size.height);
        }
        return .{
            .width = cursor_x - x,
            .height = height,
        };
    }

    fn checkboxDisplayAlloc(self: *Session, allocator: std.mem.Allocator, checkbox: *CheckboxValue) anyerror![]u8 {
        const icon = try self.inlineRenderedValueAlloc(allocator, checkbox.icon);
        const trimmed = std.mem.trim(u8, icon, " ");
        if (trimmed.len != 0 and !std.mem.eql(u8, trimmed, "NoElement")) return icon;
        return try allocator.dupe(u8, if (valueAsBoolLoose(checkbox.checked)) "☑" else "☐");
    }

    fn checkboxControlLabelAlloc(self: *Session, allocator: std.mem.Allocator, checkbox: *CheckboxValue) anyerror![]u8 {
        const display = try self.checkboxDisplayAlloc(allocator, checkbox);
        const label = self.inlineRenderedValueAlloc(allocator, checkbox.label) catch return display;
        const trimmed = std.mem.trim(u8, label, " ");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "NoElement")) return display;
        if (std.mem.eql(u8, trimmed, display)) return label;
        return try std.fmt.allocPrint(allocator, "{s} {s}", .{ display, trimmed });
    }

    fn hoverDisplayAlloc(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror![]u8 {
        const rendered = try self.inlineRenderedValueAlloc(allocator, value);
        const trimmed = std.mem.trim(u8, rendered, " ");
        if (trimmed.len != 0 and !std.mem.eql(u8, trimmed, "NoElement")) return rendered;
        return try allocator.dupe(u8, "hover");
    }

    fn populateControlSummary(self: *Session, allocator: std.mem.Allocator, summary: *ControlSummary) anyerror!void {
        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const value = try self.evalNode(allocator, self.flow.bindings[root_binding].node, null);
        try self.collectControlSummary(allocator, summary, value);
    }

    const ControlKind = enum {
        click,
        double_click,
        text_input,
        hover,
    };

    fn firstControlIndex(self: *Session, allocator: std.mem.Allocator, kind: ControlKind) !usize {
        return self.controlIndexByOrdinal(allocator, kind, 0);
    }

    fn controlIndexByOrdinal(self: *Session, allocator: std.mem.Allocator, kind: ControlKind, ordinal: usize) !usize {
        try self.flushPendingQueue();
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();

        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const value = try self.evalNode(scratch.allocator(), self.flow.bindings[root_binding].node, null);
        return switch (kind) {
            .click => blk: {
                var links: std.ArrayList(ControlEventRef) = .empty;
                defer links.deinit(scratch.allocator());
                try collectButtonLinks(self, &links, scratch.allocator(), value);
                if (ordinal >= links.items.len) return error.MissingVisibleControl;
                break :blk ordinal;
            },
            .double_click => blk: {
                var links: std.ArrayList(ControlEventRef) = .empty;
                defer links.deinit(scratch.allocator());
                try collectLabelDoubleClickLinks(self, &links, scratch.allocator(), value);
                if (ordinal >= links.items.len) return error.MissingVisibleControl;
                break :blk ordinal;
            },
            .text_input => blk: {
                var links: std.ArrayList(ControlEventRef) = .empty;
                defer links.deinit(scratch.allocator());
                try collectTextInputLinks(self, &links, scratch.allocator(), value);
                if (ordinal >= links.items.len) return error.MissingVisibleControl;
                break :blk ordinal;
            },
            .hover => blk: {
                var links: std.ArrayList(ControlEventRef) = .empty;
                defer links.deinit(scratch.allocator());
                try collectHoverLinks(self, &links, scratch.allocator(), value);
                if (ordinal >= links.items.len) return error.MissingVisibleControl;
                break :blk ordinal;
            },
        };
    }

    fn controlIndexByLabel(self: *Session, allocator: std.mem.Allocator, kind: ControlKind, label: []const u8) !usize {
        try self.flushPendingQueue();
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();

        var summary: ControlSummary = .{};
        defer summary.deinit(scratch.allocator());
        try self.populateControlSummary(scratch.allocator(), &summary);

        const items = switch (kind) {
            .click => summary.clicks.items,
            .double_click => summary.double_clicks.items,
            .text_input => summary.text_inputs.items,
            .hover => summary.hovers.items,
        };
        for (items, 0..) |item, index| {
            if (std.mem.eql(u8, item, label)) return index;
        }
        return error.UnknownControlLabel;
    }

    fn inlineRenderedValueAlloc(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror![]u8 {
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(allocator);
        try self.appendRenderedValue(&output, allocator, value);
        return try output.toOwnedSlice(allocator);
    }

    fn logf(self: *Session, comptime fmt: []const u8, args: anytype) !void {
        if (!self.trace_enabled) return;
        const line = try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
        try self.trace_lines.append(self.arena.allocator(), line);
    }

    fn durationMsFromCall(self: *Session, call: flow_ir.BuiltinCall, scope: ?*const EvalScope) anyerror!u64 {
        if (call.positional.len == 0) return error.MissingDurationArg;
        var scratch = std.heap.ArenaAllocator.init(self.arena.allocator());
        defer scratch.deinit();
        const value = try self.evalNode(scratch.allocator(), call.positional[0], scope);
        return switch (value) {
            .duration_ms => |duration_ms| duration_ms,
            .number => |number| @intFromFloat(number),
            else => error.ExpectedDurationValue,
        };
    }

    fn emitPulses(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, scope: ?*const EvalScope) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const count = @max(@as(i64, 0), @as(i64, @intFromFloat(try self.numberFromNode(call.positional[0], scope))));
        if (count == 0) return;
        for (1..@as(u64, @intCast(count)) + 1) |pulse_index| {
            try self.logf("pulses n{d} -> {d}", .{ node_id, pulse_index });
            try self.queue.append(self.arena.allocator(), .{
                .source = node_id,
                .payload = .{ .value = .{ .number = @floatFromInt(pulse_index) } },
                .scope = scope,
            });
        }
    }

    fn primeScopedStream(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!void {
        const node = self.flow.nodes[node_id];
        switch (node.kind) {
            .binding_ref => |binding_id| try self.primeScopedStream(self.flow.bindings[binding_id].node, scope),
            .hold => |hold| {
                const hold_scope = self.holdStorageScope(node_id, hold, scope);
                if (self.getHoldValue(node_id, hold_scope) == null) {
                    try self.setHoldValue(node_id, hold_scope, try self.evalNode(self.arena.allocator(), hold.initial, hold_scope));
                    try self.logf("init scoped hold n{d}", .{node_id});
                }
                for (hold.updates) |update| {
                    try self.primeScopedEventSource(try self.holdTriggerSource(update), scope);
                }
            },
            .builtin_call => |call| {
                if (std.mem.eql(u8, call.path, "Stream/skip") and !self.skip_inited[node_id]) {
                    try self.initSkipNode(self.arena.allocator(), node_id, call, scope);
                    if (call.positional.len != 0) try self.primeScopedStream(call.positional[0], scope);
                }
            },
            else => {},
        }
    }

    fn primeScopedEventSource(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!void {
        const node = self.flow.nodes[node_id];
        switch (node.kind) {
            .binding_ref => |binding_id| try self.primeScopedEventSource(self.flow.bindings[binding_id].node, scope),
            .builtin_call => |call| {
                if (std.mem.eql(u8, call.path, "Stream/pulses")) {
                    try self.emitPulses(node_id, call, scope);
                } else if (std.mem.eql(u8, call.path, "Stream/skip")) {
                    try self.primeScopedStream(node_id, scope);
                }
            },
            else => {},
        }
    }

    fn initSkipNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, scope: ?*const EvalScope) anyerror!void {
        const source = call.positional[0];
        const limit = try self.skipLimit(call, scope);
        if (try self.initialStreamValue(allocator, source, scope)) |value| {
            if (limit == 0) {
                self.skip_values[node_id] = value;
                self.skip_inited[node_id] = true;
                self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
            } else {
                self.skip_seen[node_id] = 1;
            }
        }
        try self.logf("init skip n{d} seen={d} limit={d}", .{ node_id, self.skip_seen[node_id], limit });
    }

    fn processSkipPulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, payload: PulsePayload, scope: ?*const EvalScope) anyerror!void {
        const limit = try self.skipLimit(call, scope);
        if (self.skip_seen[node_id] < limit) {
            self.skip_seen[node_id] += 1;
            try self.logf("skip n{d} ignored pulse {d}/{d}", .{ node_id, self.skip_seen[node_id], limit });
            return;
        }

        self.skip_values[node_id] = try valueFromPulsePayload(self, self.arena.allocator(), payload, scope);
        self.skip_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("skip n{d} emitted", .{node_id});
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn initListAppendNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("init list_append n{d}", .{node_id});
    }

    fn initListClearNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("init list_clear n{d}", .{node_id});
    }

    fn initListRemoveNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try self.filterRemovedItems(self.arena.allocator(), base, self.list_remove_tombstones[node_id]);
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("init list_remove n{d}", .{node_id});
    }

    fn initListRemoveLastNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("init list_remove_last n{d}", .{node_id});
    }

    fn processListAppendPulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, source: flow_ir.NodeId) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const base_source = try self.listSourceDependency(call.positional[0]);
        if (source == base_source) {
            const base = try self.evalNode(self.arena.allocator(), call.positional[0], null);
            self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
            self.list_inited[node_id] = true;
            self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
            try self.logf("list_append n{d} mirror", .{node_id});
            try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
            return;
        }

        const item = if (findNamed(call.named, "item")) |item_node| blk: {
            if (try self.valueTriggerSource(item_node) != source) return;
            break :blk try self.evalNode(self.arena.allocator(), item_node, null);
        } else if (findNamed(call.named, "on")) |on_node| blk: {
            if (try self.valueTriggerSource(on_node) != source) return;
            break :blk try self.evalNode(self.arena.allocator(), on_node, null);
        } else return error.MissingArgument;
        if (item == .none) return;
        const current = try listItemsFromValue(self.list_values[node_id]);
        const next = try self.arena.allocator().alloc(Value, current.len + 1);
        @memcpy(next[0..current.len], current);
        next[current.len] = item;
        self.list_values[node_id] = .{ .list = next };
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("list_append n{d} len={d}", .{ node_id, next.len });
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn processListClearPulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, source: flow_ir.NodeId) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const source_dep = try self.listSourceDependency(call.positional[0]);
        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
        if (source == source_dep) {
            const base = try self.evalNode(self.arena.allocator(), call.positional[0], null);
            self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
            self.list_inited[node_id] = true;
            self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
            try self.logf("list_clear n{d} mirror", .{node_id});
            try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
            return;
        }
        if (try self.valueTriggerSource(on_node) != source) return;
        self.list_values[node_id] = .{ .list = &.{} };
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("list_clear n{d} cleared", .{node_id});
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn processListRemovePulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, source: flow_ir.NodeId) anyerror!void {
        if (call.positional.len < 2) return error.MissingArgument;
        const base_node = call.positional[0];
        const item_name = switch (self.flow.nodes[call.positional[1]].kind) {
            .symbol => |text| text,
            else => return error.MissingLocalBinding,
        };
        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
        const base_source = try self.listSourceDependency(base_node);

        if (source == base_source) {
            const base = try self.evalNode(self.arena.allocator(), base_node, null);
            self.list_values[node_id] = try self.filterRemovedItems(self.arena.allocator(), base, self.list_remove_tombstones[node_id]);
            self.list_inited[node_id] = true;
            self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
            try self.logf("list_remove n{d} mirror len={d}", .{ node_id, (try listItemsFromValue(self.list_values[node_id])).len });
            try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
            return;
        }

        const current = if (self.list_inited[node_id])
            try listItemsFromValue(self.list_values[node_id])
        else blk: {
            const base = try self.evalNode(self.arena.allocator(), base_node, null);
            self.list_values[node_id] = try self.filterRemovedItems(self.arena.allocator(), base, self.list_remove_tombstones[node_id]);
            self.list_inited[node_id] = true;
            self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
            break :blk try listItemsFromValue(self.list_values[node_id]);
        };

        var kept: std.ArrayList(Value) = .empty;
        defer kept.deinit(self.arena.allocator());
        var removed: std.ArrayList(Value) = .empty;
        defer removed.deinit(self.arena.allocator());

        for (current) |item| {
            if (try self.listRemoveMatchesPulse(on_node, item_name, item, source)) {
                try removed.append(self.arena.allocator(), item);
            } else {
                try kept.append(self.arena.allocator(), item);
            }
        }

        if (removed.items.len == 0) return;

        self.list_remove_tombstones[node_id] = try self.appendUniqueValues(
            self.arena.allocator(),
            self.list_remove_tombstones[node_id],
            removed.items,
        );
        self.list_values[node_id] = .{ .list = try kept.toOwnedSlice(self.arena.allocator()) };
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("list_remove n{d} removed={d} len={d}", .{ node_id, removed.items.len, kept.items.len });
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn processListRemoveLastPulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, source: flow_ir.NodeId) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        const base_node = call.positional[0];
        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
        const base_source = try self.listSourceDependency(base_node);

        if (source == base_source) {
            const base = try self.evalNode(self.arena.allocator(), base_node, null);
            self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
            self.list_inited[node_id] = true;
            self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
            try self.logf("list_remove_last n{d} mirror", .{node_id});
            try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
            return;
        }
        if (try self.valueTriggerSource(on_node) != source) return;

        const current = if (self.list_inited[node_id])
            try listItemsFromValue(self.list_values[node_id])
        else blk: {
            const base = try self.evalNode(self.arena.allocator(), base_node, null);
            self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
            self.list_inited[node_id] = true;
            self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
            break :blk try listItemsFromValue(self.list_values[node_id]);
        };

        if (current.len == 0) return;

        const next = try self.arena.allocator().alloc(Value, current.len - 1);
        @memcpy(next, current[0 .. current.len - 1]);
        self.list_values[node_id] = .{ .list = next };
        self.list_inited[node_id] = true;
        self.invalidateEvalCacheForDependency(.{ .node_id = node_id, .scope_id = 0 });
        try self.logf("list_remove_last n{d} len={d}", .{ node_id, next.len });
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn skipLimit(self: *Session, call: flow_ir.BuiltinCall, scope: ?*const EvalScope) anyerror!u64 {
        const count_node = findNamed(call.named, "count") orelse return error.MissingCountArg;
        var scratch = std.heap.ArenaAllocator.init(self.arena.allocator());
        defer scratch.deinit();
        const value = try self.evalNode(scratch.allocator(), count_node, scope);
        return @intFromFloat(try valueAsNumber(value));
    }

    fn initialStreamValue(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!?Value {
        const value = try self.evalNode(allocator, node_id, scope);
        return switch (value) {
            .none => null,
            else => value,
        };
    }

    fn holdTriggerSource(self: *Session, node_id: flow_ir.NodeId) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .then_value => |then_value| try self.eventDependencySource(then_value.source),
            .latest, .hold => node_id,
            .builtin_call => |call| if (std.mem.eql(u8, call.path, "Stream/skip") or std.mem.eql(u8, call.path, "Stream/pulses")) node_id else try self.eventDependencySource(node_id),
            else => try self.eventDependencySource(node_id),
        };
    }

    fn holdTriggerSourceScoped(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .then_value => |then_value| try self.scopedEventDependencySource(then_value.source, scope),
            .latest, .hold => node_id,
            .builtin_call => |call| if (std.mem.eql(u8, call.path, "Stream/skip") or std.mem.eql(u8, call.path, "Stream/pulses")) node_id else try self.scopedEventDependencySource(node_id, scope),
            else => try self.scopedEventDependencySource(node_id, scope),
        };
    }

    fn processHoldPulse(self: *Session, node_id: flow_ir.NodeId, hold: flow_ir.Hold, source: flow_ir.NodeId, outer_scope: ?*const EvalScope) anyerror!void {
        const hold_scope = self.holdStorageScope(node_id, hold, outer_scope);
        const current = self.getHoldValue(node_id, hold_scope) orelse try self.evalNode(self.arena.allocator(), hold.initial, hold_scope);
        for (hold.updates) |update| {
            const update_source = if (outer_scope != null and self.nodeNeedsScope(update))
                try self.holdTriggerSourceScoped(update, outer_scope)
            else
                try self.holdTriggerSource(update);
            if (update_source != source) continue;
            const bindings = try self.arena.allocator().alloc(RecordField, 1);
            bindings[0] = .{
                .name = hold.state_name,
                .value = current,
            };
            const scope = EvalScope{
                .bindings = bindings,
                .parent = outer_scope,
                .passed = null,
                .id = deriveScopeId(outer_scope, bindings, null),
                .transparent_state_scope = true,
            };
            const next_value = try self.evalNode(self.arena.allocator(), update, &scope);
            const next_value_brief = try briefValueAlloc(self.arena.allocator(), next_value);
            try self.setHoldValue(node_id, hold_scope, next_value);
            if (hold_scope) |frame| {
                try self.logf("hold n{d} updated={s} scope={d}", .{ node_id, next_value_brief, frame.id });
            } else {
                try self.logf("hold n{d} updated={s}", .{ node_id, next_value_brief });
            }
            try self.queue.append(self.arena.allocator(), .{
                .source = node_id,
                .payload = .{ .node = node_id },
                .scope = hold_scope,
            });
            break;
        }
    }

    fn listRemoveMatchesPulse(self: *Session, on_node: flow_ir.NodeId, item_name: []const u8, item: Value, source: flow_ir.NodeId) anyerror!bool {
        const bindings = try self.arena.allocator().alloc(RecordField, 1);
        bindings[0] = .{
            .name = item_name,
            .value = item,
        };
        const scope = EvalScope{
            .bindings = bindings,
            .parent = null,
            .passed = null,
            .id = deriveScopeId(null, bindings, null),
        };
        const on_value = try self.evalNode(self.arena.allocator(), on_node, &scope);
        return switch (on_value) {
            .none => false,
            .link => |link| link == source,
            else => blk: {
                const trigger_source = try self.listRemoveTriggerSource(on_node);
                break :blk trigger_source != null and trigger_source.? == source;
            },
        };
    }

    fn listRemoveTriggerSource(self: *Session, node_id: flow_ir.NodeId) anyerror!?flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.listRemoveTriggerSource(self.flow.bindings[binding_id].node),
            .then_value => |then_value| try self.eventDependencySource(then_value.source),
            .latest => |latest| if (latest.sources.len == 1) try self.eventDependencySource(latest.sources[0]) else null,
            else => null,
        };
    }

    fn filterRemovedItems(self: *Session, allocator: std.mem.Allocator, base_value: Value, tombstones: []Value) anyerror!Value {
        _ = self;
        const base_items = try listItemsFromValue(base_value);
        var kept: std.ArrayList(Value) = .empty;
        defer kept.deinit(allocator);

        for (base_items) |item| {
            var is_removed = false;
            for (tombstones) |removed| {
                if (valuesEqual(item, removed)) {
                    is_removed = true;
                    break;
                }
            }
            if (!is_removed) try kept.append(allocator, item);
        }

        return .{ .list = try kept.toOwnedSlice(allocator) };
    }

    fn appendUniqueValues(self: *Session, allocator: std.mem.Allocator, existing: []Value, added: []Value) anyerror![]Value {
        _ = self;
        var items: std.ArrayList(Value) = .empty;
        defer items.deinit(allocator);

        for (existing) |value| try items.append(allocator, value);
        for (added) |value| {
            var found = false;
            for (items.items) |present| {
                if (valuesEqual(present, value)) {
                    found = true;
                    break;
                }
            }
            if (!found) try items.append(allocator, value);
        }
        return try items.toOwnedSlice(allocator);
    }

    fn loadPersistedState(self: *Session) !void {
        if (comptime io_backend.selected == .evented) return;
        const path = self.state_file_path orelse return;
        var io_instance = try io_backend.init();
        defer io_instance.deinit();
        const io = io_instance.io();
        const cwd = std.Io.Dir.cwd();
        if (std.fs.path.dirname(path)) |dir_name| {
            try cwd.createDirPath(io, dir_name);
        }
        if (self.clear_state) return;
        const data = cwd.readFileAlloc(io, path, self.arena.allocator(), .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => return,
            else => |e| return e,
        };
        const parsed = try std.json.parseFromSlice(PersistedState, self.arena.allocator(), data, .{
            .ignore_unknown_fields = true,
        });
        const state = parsed.value;
        if (state.version != 1 and state.version != 2) return;

        for (state.sums) |entry| {
            const node_id = self.resolvePersistedNode(entry.stable_id, entry.node_id, .sum) orelse continue;
            self.sum_values[node_id] = entry.value;
            self.sum_inited[node_id] = true;
            try self.logf("persist read sum n{d} key={x} = {d}", .{ node_id, self.persist_ids[node_id], entry.value });
        }

        for (state.holds) |entry| {
            const node_id = self.resolvePersistedNode(entry.stable_id, entry.node_id, .hold) orelse continue;
            self.hold_values[node_id] = try persistedScalarToValue(self.arena.allocator(), entry.value);
            self.hold_inited[node_id] = true;
            try self.logf("persist read hold n{d} key={x}", .{ node_id, self.persist_ids[node_id] });
        }
    }

    fn savePersistedState(self: *Session) !void {
        if (comptime io_backend.selected == .evented) return;
        const path = self.state_file_path orelse return;
        var io_instance = try io_backend.init();
        defer io_instance.deinit();
        const io = io_instance.io();
        const cwd = std.Io.Dir.cwd();
        if (std.fs.path.dirname(path)) |dir_name| {
            try cwd.createDirPath(io, dir_name);
        }

        const allocator = self.arena.allocator();
        var sums: std.ArrayList(PersistedSumEntry) = .empty;
        defer sums.deinit(allocator);
        for (self.sum_inited, self.sum_values, 0..) |inited, value, index| {
            if (!inited) continue;
            const node_id: flow_ir.NodeId = @intCast(index);
            try sums.append(allocator, .{
                .stable_id = self.persist_ids[index],
                .node_id = node_id,
                .value = value,
            });
            try self.logf("persist write sum n{d} key={x} = {d}", .{ node_id, self.persist_ids[index], value });
        }

        var holds: std.ArrayList(PersistedHoldEntry) = .empty;
        defer holds.deinit(allocator);
        for (self.hold_inited, self.hold_values, 0..) |inited, value, index| {
            if (!inited) continue;
            const persisted = valueToPersistedScalar(allocator, value) catch continue;
            const node_id: flow_ir.NodeId = @intCast(index);
            try holds.append(allocator, .{
                .stable_id = self.persist_ids[index],
                .node_id = node_id,
                .value = persisted,
            });
            try self.logf("persist write hold n{d} key={x}", .{ node_id, self.persist_ids[index] });
        }

        const state = PersistedState{
            .version = 2,
            .sums = try sums.toOwnedSlice(allocator),
            .holds = try holds.toOwnedSlice(allocator),
        };
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try std.json.Stringify.value(state, .{ .whitespace = .indent_2 }, &out.writer);
        try cwd.writeFile(io, .{
            .sub_path = path,
            .data = out.written(),
        });
    }

    fn computePersistIds(self: *Session) !void {
        const allocator = self.arena.allocator();
        for (self.flow.bindings) |binding| {
            const root_path = try std.fmt.allocPrint(allocator, "binding:{s}", .{binding.name});
            try self.assignPersistIdsFromPath(binding.node, root_path);
        }
        for (self.flow.functions) |function| {
            const root_path = try std.fmt.allocPrint(allocator, "function:{s}", .{function.name});
            try self.assignPersistIdsFromPath(function.body, root_path);
        }
    }

    fn assignPersistIdsFromPath(self: *Session, node_id: flow_ir.NodeId, path: []const u8) !void {
        const allocator = self.arena.allocator();
        const node = self.flow.nodes[node_id];
        if (self.persist_ids[node_id] == 0) {
            if (persistKindLabel(node.kind)) |label| {
                self.persist_ids[node_id] = persistStableId(path, label);
            }
        }

        switch (node.kind) {
            .access => |access| {
                const child_path = try std.fmt.allocPrint(allocator, "{s}/access:{s}", .{ path, access.field });
                try self.assignPersistIdsFromPath(access.target, child_path);
            },
            .binary => |binary| {
                try self.assignPersistIdsFromPath(binary.lhs, try std.fmt.allocPrint(allocator, "{s}/lhs", .{path}));
                try self.assignPersistIdsFromPath(binary.rhs, try std.fmt.allocPrint(allocator, "{s}/rhs", .{path}));
            },
            .text => |parts| {
                for (parts, 0..) |part, index| {
                    try self.assignPersistIdsFromPath(part, try std.fmt.allocPrint(allocator, "{s}/text[{d}]", .{ path, index }));
                }
            },
            .list => |list| {
                for (list.items, 0..) |item, index| {
                    try self.assignPersistIdsFromPath(item, try std.fmt.allocPrint(allocator, "{s}/list[{d}]", .{ path, index }));
                }
            },
            .record => |fields| {
                for (fields) |field| {
                    try self.assignPersistIdsFromPath(field.value, try std.fmt.allocPrint(allocator, "{s}/field:{s}", .{ path, field.name }));
                }
            },
            .block => |block| {
                for (block.bindings) |binding| {
                    try self.assignPersistIdsFromPath(binding.value, try std.fmt.allocPrint(allocator, "{s}/block:{s}", .{ path, binding.name }));
                }
                try self.assignPersistIdsFromPath(block.result, try std.fmt.allocPrint(allocator, "{s}/block:result", .{path}));
            },
            .when => |when| {
                try self.assignPersistIdsFromPath(when.input, try std.fmt.allocPrint(allocator, "{s}/when:input", .{path}));
                for (when.arms, 0..) |arm, index| {
                    try self.assignPersistIdsFromPath(arm.pattern, try std.fmt.allocPrint(allocator, "{s}/when:arm[{d}]:pattern", .{ path, index }));
                    try self.assignPersistIdsFromPath(arm.result, try std.fmt.allocPrint(allocator, "{s}/when:arm[{d}]:result", .{ path, index }));
                }
            },
            .latest => |latest| {
                if (latest.initial) |initial| {
                    try self.assignPersistIdsFromPath(initial, try std.fmt.allocPrint(allocator, "{s}/latest:init", .{path}));
                }
                for (latest.sources, 0..) |source, index| {
                    try self.assignPersistIdsFromPath(source, try std.fmt.allocPrint(allocator, "{s}/latest:source[{d}]", .{ path, index }));
                }
            },
            .then_value => |then_value| {
                try self.assignPersistIdsFromPath(then_value.source, try std.fmt.allocPrint(allocator, "{s}/then:source", .{path}));
                try self.assignPersistIdsFromPath(then_value.value, try std.fmt.allocPrint(allocator, "{s}/then:value", .{path}));
            },
            .hold => |hold| {
                try self.assignPersistIdsFromPath(hold.initial, try std.fmt.allocPrint(allocator, "{s}/hold:init:{s}", .{ path, hold.state_name }));
                for (hold.updates, 0..) |update, index| {
                    try self.assignPersistIdsFromPath(update, try std.fmt.allocPrint(allocator, "{s}/hold:update[{d}]:{s}", .{ path, index, hold.state_name }));
                }
            },
            .linked_value => |linked| {
                try self.assignPersistIdsFromPath(linked.value, try std.fmt.allocPrint(allocator, "{s}/linked:value", .{path}));
                try self.assignPersistIdsFromPath(linked.target, try std.fmt.allocPrint(allocator, "{s}/linked:target", .{path}));
            },
            .builtin_call => |call| {
                for (call.positional, 0..) |arg, index| {
                    try self.assignPersistIdsFromPath(arg, try std.fmt.allocPrint(allocator, "{s}/call:{s}:pos[{d}]", .{ path, call.path, index }));
                }
                for (call.named) |arg| {
                    try self.assignPersistIdsFromPath(arg.value, try std.fmt.allocPrint(allocator, "{s}/call:{s}:named:{s}", .{ path, call.path, arg.name }));
                }
            },
            .user_call => |call| {
                const function_name = self.flow.functions[call.function].name;
                for (call.positional, 0..) |arg, index| {
                    try self.assignPersistIdsFromPath(arg, try std.fmt.allocPrint(allocator, "{s}/user:{s}:pos[{d}]", .{ path, function_name, index }));
                }
                for (call.named) |arg| {
                    try self.assignPersistIdsFromPath(arg.value, try std.fmt.allocPrint(allocator, "{s}/user:{s}:named:{s}", .{ path, function_name, arg.name }));
                }
                if (call.pass_context) |pass_context| {
                    try self.assignPersistIdsFromPath(pass_context, try std.fmt.allocPrint(allocator, "{s}/user:{s}:pass", .{ path, function_name }));
                }
            },
            else => {},
        }
    }

    fn resolvePersistedNode(self: *Session, stable_id: u64, legacy_node_id: ?flow_ir.NodeId, kind: PersistKind) ?flow_ir.NodeId {
        if (stable_id != 0) {
            for (self.persist_ids, 0..) |persist_id, index| {
                if (persist_id != stable_id) continue;
                if (!self.nodeMatchesPersistKind(@intCast(index), kind)) continue;
                return @intCast(index);
            }
        }
        if (legacy_node_id) |node_id| {
            if (node_id < self.flow.nodes.len and self.nodeMatchesPersistKind(node_id, kind)) return node_id;
        }
        return null;
    }

    fn nodeMatchesPersistKind(self: *Session, node_id: flow_ir.NodeId, kind: PersistKind) bool {
        const node = self.flow.nodes[node_id];
        return switch (kind) {
            .sum => node.kind == .builtin_call and std.mem.eql(u8, node.kind.builtin_call.path, "Math/sum"),
            .hold => node.kind == .hold,
        };
    }
};

pub fn runAlloc(allocator: std.mem.Allocator, source: []const u8, options: Options) !Outcome {
    const lowered_flow = try flow_ir.lowerAlloc(allocator, source);
    const document = switch (lowered_flow) {
        .ok => |document| document,
        .err => |failure| return .{ .err = failure },
    };
    errdefer {
        var cleanup = document;
        cleanup.deinit();
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    var memo_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer memo_arena.deinit();

    var session = Session{
        .backing_allocator = allocator,
        .arena = arena,
        .memo_arena = memo_arena,
        .flow = document,
        .trace_enabled = options.trace,
        .state_file_path = if (options.state_file_path) |path| try arena.allocator().dupe(u8, path) else null,
        .clear_state = options.clear_state,
        .terminal_columns = options.terminal_columns,
        .terminal_rows = options.terminal_rows,
    };
    try session.init();
    if (options.virtual_time_ms != 0) try session.advanceTime(options.virtual_time_ms);
    return .{ .ok = session };
}

fn controlEventValue(allocator: std.mem.Allocator, value: Value) anyerror!Value {
    return switch (value) {
        .button => |button| blk: {
            var fields = [_]RecordField{
                .{ .name = "press", .value = optionalLinkValue(button.press_link) },
            };
            break :blk try allocRecordValue(allocator, &fields);
        },
        .checkbox => |checkbox| blk: {
            var fields = [_]RecordField{
                .{ .name = "click", .value = optionalLinkValue(checkbox.click_link) },
            };
            break :blk try allocRecordValue(allocator, &fields);
        },
        .label => |label| blk: {
            var fields = [_]RecordField{
                .{ .name = "click", .value = optionalLinkValue(label.click_link) },
                .{ .name = "double_click", .value = optionalLinkValue(label.double_click_link) },
            };
            break :blk try allocRecordValue(allocator, &fields);
        },
        .text_input => |input| blk: {
            const change_link = input.change_link;
            const key_link = input.key_link orelse input.change_link;
            const blur_link = input.blur_link;
            const focus_link = input.focus_link;
            var change_fields = [_]RecordField{
                .{ .name = "value", .value = optionalLinkValue(change_link) },
                .{ .name = "text", .value = optionalLinkValue(change_link) },
            };
            var key_fields = [_]RecordField{
                .{ .name = "key", .value = optionalLinkValue(key_link) },
                .{ .name = "text", .value = optionalLinkValue(key_link) },
            };
            var fields = [_]RecordField{
                .{ .name = "change", .value = try allocRecordValue(allocator, &change_fields) },
                .{ .name = "key_down", .value = try allocRecordValue(allocator, &key_fields) },
                .{ .name = "blur", .value = optionalLinkValue(blur_link) },
                .{ .name = "focus", .value = optionalLinkValue(focus_link) },
            };
            break :blk try allocRecordValue(allocator, &fields);
        },
        .select => |select| blk: {
            var change_fields = [_]RecordField{
                .{ .name = "value", .value = optionalLinkValue(select.change_link) },
            };
            var fields = [_]RecordField{
                .{ .name = "change", .value = try allocRecordValue(allocator, &change_fields) },
            };
            break :blk try allocRecordValue(allocator, &fields);
        },
        .slider => |slider| blk: {
            var change_fields = [_]RecordField{
                .{ .name = "value", .value = optionalLinkValue(slider.change_link) },
            };
            var fields = [_]RecordField{
                .{ .name = "change", .value = try allocRecordValue(allocator, &change_fields) },
            };
            break :blk try allocRecordValue(allocator, &fields);
        },
        else => error.UnsupportedFieldAccess,
    };
}

fn findNamed(named: []const flow_ir.NamedArg, name: []const u8) ?flow_ir.NodeId {
    for (named) |arg| {
        if (std.mem.eql(u8, arg.name, name)) return arg.value;
    }
    return null;
}

fn findField(fields: []const flow_ir.Field, name: []const u8) ?flow_ir.NodeId {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.value;
    }
    return null;
}

fn findRecordValue(fields: []const RecordField, name: []const u8) ?Value {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.value;
    }
    return null;
}

fn recordFieldFromValue(value: Value, name: []const u8) ?Value {
    return switch (value) {
        .record => |fields| findRecordValue(fields, name),
        else => null,
    };
}

fn terminalStyleSizeFromValue(value: Value) TerminalStyleSize {
    const width_value = recordFieldFromValue(value, "width");
    const height_value = recordFieldFromValue(value, "height");
    const width_px = if (width_value) |resolved| valueAsNumber(resolved) catch 0 else 0;
    const height_px = if (height_value) |resolved| valueAsNumber(resolved) catch 0 else 0;
    return .{
        .width = terminalStyleSpan(width_px, 8),
        .height = terminalStyleSpan(height_px, 26),
    };
}

fn terminalStyleSpan(size: f64, divisor: f64) usize {
    if (size <= 0) return 0;
    return @max(@as(usize, 1), @as(usize, @intFromFloat(@ceil(size / divisor))));
}

fn persistKindLabel(kind: flow_ir.Node.Kind) ?[]const u8 {
    return switch (kind) {
        .hold => "hold",
        .builtin_call => |call| if (std.mem.eql(u8, call.path, "Math/sum")) "sum" else null,
        else => null,
    };
}

fn persistStableId(path: []const u8, label: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(label);
    hasher.update("|");
    hasher.update(path);
    return hasher.final();
}

fn valueToPersistedScalar(allocator: std.mem.Allocator, value: Value) !PersistedScalar {
    return switch (value) {
        .none => .{ .kind = .none },
        .number => |number| .{
            .kind = .number,
            .number = number,
        },
        .text => |text| .{
            .kind = .text,
            .text = try allocator.dupe(u8, text),
        },
        .symbol => |text| .{
            .kind = .symbol,
            .text = try allocator.dupe(u8, text),
        },
        .duration_ms => |duration_ms| .{
            .kind = .duration_ms,
            .duration_ms = duration_ms,
        },
        else => error.UnsupportedPersistedValue,
    };
}

fn persistedScalarToValue(allocator: std.mem.Allocator, persisted: PersistedScalar) !Value {
    _ = allocator;
    return switch (persisted.kind) {
        .none => .none,
        .number => .{ .number = persisted.number orelse return error.InvalidPersistedValue },
        .text => .{ .text = persisted.text orelse return error.InvalidPersistedValue },
        .symbol => .{ .symbol = persisted.text orelse return error.InvalidPersistedValue },
        .duration_ms => .{ .duration_ms = persisted.duration_ms orelse return error.InvalidPersistedValue },
    };
}

fn findParamIndex(params: [][]const u8, name: []const u8) ?usize {
    for (params, 0..) |param, index| {
        if (std.mem.eql(u8, param, name)) return index;
    }
    return null;
}

fn withLocalBinding(allocator: std.mem.Allocator, parent: ?*const EvalScope, name: []const u8, value: Value) !EvalScope {
    const bindings = try allocator.alloc(RecordField, 1);
    bindings[0] = .{
        .name = name,
        .value = value,
    };
    return .{
        .bindings = bindings,
        .parent = parent,
        .passed = if (parent) |frame| frame.passed else null,
        .id = deriveScopeId(parent, bindings, if (parent) |frame| frame.passed else null),
    };
}

fn cloneCapturedValue(allocator: std.mem.Allocator, value: Value) anyerror!Value {
    return switch (value) {
        .text => |text| .{ .text = try allocator.dupe(u8, text) },
        .symbol => |text| .{ .symbol = try allocator.dupe(u8, text) },
        .list => |items| blk: {
            const copy = try allocator.alloc(Value, items.len);
            for (items, 0..) |item, index| copy[index] = try cloneCapturedValue(allocator, item);
            break :blk .{ .list = copy };
        },
        .record => |fields| blk: {
            const copy = try allocator.alloc(RecordField, fields.len);
            for (fields, 0..) |field, index| {
                copy[index] = .{
                    .name = try allocator.dupe(u8, field.name),
                    .value = try cloneCapturedValue(allocator, field.value),
                };
            }
            break :blk .{ .record = copy };
        },
        else => value,
    };
}

fn captureScope(allocator: std.mem.Allocator, scope: ?*const EvalScope) !?*const EvalScope {
    const frame = scope orelse return null;
    const copy = try allocator.create(EvalScope);
    const bindings = try allocator.alloc(RecordField, frame.bindings.len);
    for (frame.bindings, 0..) |binding, index| {
        bindings[index] = .{
            .name = try allocator.dupe(u8, binding.name),
            .value = try cloneCapturedValue(allocator, binding.value),
        };
    }
    copy.* = .{
        .bindings = bindings,
        .parent = try captureScope(allocator, frame.parent),
        .passed = if (frame.passed) |passed| try cloneCapturedValue(allocator, passed) else null,
        .id = frame.id,
        .transparent_state_scope = frame.transparent_state_scope,
    };
    return copy;
}

fn destroyCapturedValue(allocator: std.mem.Allocator, value: Value) void {
    switch (value) {
        .text => |text| allocator.free(text),
        .symbol => |text| allocator.free(text),
        .list => |items| {
            for (items) |item| destroyCapturedValue(allocator, item);
            allocator.free(items);
        },
        .record => |fields| {
            for (fields) |field| {
                allocator.free(field.name);
                destroyCapturedValue(allocator, field.value);
            }
            allocator.free(fields);
        },
        else => {},
    }
}

fn destroyCapturedScope(allocator: std.mem.Allocator, scope: ?*const EvalScope) void {
    const frame = scope orelse return;
    destroyCapturedScope(allocator, frame.parent);
    for (frame.bindings) |binding| {
        allocator.free(binding.name);
        destroyCapturedValue(allocator, binding.value);
    }
    allocator.free(frame.bindings);
    if (frame.passed) |passed| destroyCapturedValue(allocator, passed);
    allocator.destroy(frame);
}

fn normalizedStateScope(scope: ?*const EvalScope) ?*const EvalScope {
    var current = scope;
    while (current) |frame| {
        if (frame.transparent_state_scope) {
            current = frame.parent;
            continue;
        }
        if (frame.bindings.len == 1 and std.mem.eql(u8, frame.bindings[0].name, "element")) {
            current = frame.parent;
            continue;
        }
        if (frame.bindings.len == 0) {
            current = frame.parent;
            continue;
        }
        return frame;
    }
    return null;
}

fn deriveScopeId(parent: ?*const EvalScope, bindings: []const RecordField, passed: ?Value) u64 {
    var hasher = std.hash.Wyhash.init(if (parent) |frame| frame.id else 0);
    for (bindings) |binding| {
        hasher.update(binding.name);
        hashValueIdentity(&hasher, binding.value);
    }
    if (passed) |value| {
        hasher.update("passed");
        hashValueIdentity(&hasher, value);
    }
    return hasher.final();
}

fn deriveRecordScopeId(parent: ?*const EvalScope, bindings: []const RecordField, passed: ?Value) u64 {
    var hasher = std.hash.Wyhash.init(if (parent) |frame| frame.id else 0);
    for (bindings) |binding| {
        hasher.update(binding.name);
        hashRecordScopeValueIdentity(&hasher, binding.value);
    }
    if (passed) |value| {
        hasher.update("passed");
        hashRecordScopeValueIdentity(&hasher, value);
    }
    return hasher.final();
}

fn hashValueIdentity(hasher: *std.hash.Wyhash, value: Value) void {
    const tag = std.meta.activeTag(value);
    hasher.update(@tagName(tag));
    switch (value) {
        .number => |number| hasher.update(std.mem.asBytes(&number)),
        .text => |text| {
            hasher.update(text);
            const len = text.len;
            hasher.update(std.mem.asBytes(&len));
        },
        .symbol => |text| {
            hasher.update(text);
            const len = text.len;
            hasher.update(std.mem.asBytes(&len));
        },
        .duration_ms => |duration_ms| hasher.update(std.mem.asBytes(&duration_ms)),
        .list => |items| {
            const len = items.len;
            hasher.update(std.mem.asBytes(&len));
            for (items) |item| hashValueIdentity(hasher, item);
        },
        .record => |fields| {
            const len = fields.len;
            hasher.update(std.mem.asBytes(&len));
            for (fields) |field| {
                hasher.update(field.name);
                const name_len = field.name.len;
                hasher.update(std.mem.asBytes(&name_len));
                hashValueIdentity(hasher, field.value);
            }
        },
        .binding_ref => |binding_id| hasher.update(std.mem.asBytes(&binding_id)),
        .terminal => |terminal| {
            const ptr_value: usize = @intFromPtr(terminal);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .document => |document| {
            const ptr_value: usize = @intFromPtr(document);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .stripe => |stripe| {
            const ptr_value: usize = @intFromPtr(stripe);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .label => |label| {
            const ptr_value: usize = @intFromPtr(label);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .container => |container| {
            const ptr_value: usize = @intFromPtr(container);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .checkbox => |checkbox| {
            const ptr_value: usize = @intFromPtr(checkbox);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .button => |button| {
            const ptr_value: usize = @intFromPtr(button);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .text_input => |input| {
            const ptr_value: usize = @intFromPtr(input);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .select => |select| {
            const ptr_value: usize = @intFromPtr(select);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .slider => |slider| {
            const ptr_value: usize = @intFromPtr(slider);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .scoped_node => |deferred| {
            hasher.update(std.mem.asBytes(&deferred.node_id));
            const scope_id = if (deferred.scope) |scope| scope.id else @as(u64, 0);
            hasher.update(std.mem.asBytes(&scope_id));
        },
        .link => |link| hasher.update(std.mem.asBytes(&link)),
        .none => {},
    }
}

fn hashRecordScopeValueIdentity(hasher: *std.hash.Wyhash, value: Value) void {
    const tag = std.meta.activeTag(value);
    hasher.update(@tagName(tag));
    switch (value) {
        .number => |number| hasher.update(std.mem.asBytes(&number)),
        .text => |text| {
            hasher.update(text);
            const len = text.len;
            hasher.update(std.mem.asBytes(&len));
        },
        .symbol => |text| {
            hasher.update(text);
            const len = text.len;
            hasher.update(std.mem.asBytes(&len));
        },
        .duration_ms => |duration_ms| hasher.update(std.mem.asBytes(&duration_ms)),
        .list => |items| {
            const len = items.len;
            hasher.update(std.mem.asBytes(&len));
            for (items) |item| hashRecordScopeValueIdentity(hasher, item);
        },
        .record => |fields| {
            const len = fields.len;
            hasher.update(std.mem.asBytes(&len));
            for (fields) |field| {
                hasher.update(field.name);
                const name_len = field.name.len;
                hasher.update(std.mem.asBytes(&name_len));
                hashRecordScopeValueIdentity(hasher, field.value);
            }
        },
        .binding_ref => |binding_id| hasher.update(std.mem.asBytes(&binding_id)),
        .terminal => |terminal| {
            const ptr_value: usize = @intFromPtr(terminal);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .document => |document| {
            const ptr_value: usize = @intFromPtr(document);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .stripe => |stripe| {
            const ptr_value: usize = @intFromPtr(stripe);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .label => |label| {
            const ptr_value: usize = @intFromPtr(label);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .container => |container| {
            const ptr_value: usize = @intFromPtr(container);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .checkbox => |checkbox| {
            const ptr_value: usize = @intFromPtr(checkbox);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .button => |button| {
            const ptr_value: usize = @intFromPtr(button);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .text_input => |input| {
            const ptr_value: usize = @intFromPtr(input);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .select => |select| {
            const ptr_value: usize = @intFromPtr(select);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .slider => |slider| {
            const ptr_value: usize = @intFromPtr(slider);
            hasher.update(std.mem.asBytes(&ptr_value));
        },
        .scoped_node => |deferred| hasher.update(std.mem.asBytes(&deferred.node_id)),
        .link => |link| hasher.update(std.mem.asBytes(&link)),
        .none => {},
    }
}

fn valueFromPulsePayload(self: *Session, allocator: std.mem.Allocator, payload: PulsePayload, scope: ?*const EvalScope) anyerror!Value {
    return switch (payload) {
        .node => |node| try self.evalNode(allocator, node, scope),
        .value => |value| value,
    };
}

fn lookupLocal(scope: ?*const EvalScope, name: []const u8) ?Value {
    var current = scope;
    while (current) |frame| {
        for (frame.bindings) |binding| {
            if (std.mem.eql(u8, binding.name, name)) return binding.value;
        }
        current = frame.parent;
    }
    return null;
}

fn briefValueAlloc(allocator: std.mem.Allocator, value: Value) ![]const u8 {
    return switch (value) {
        .number => |number| std.fmt.allocPrint(allocator, "{d}", .{number}),
        .text => |text| std.fmt.allocPrint(allocator, "\"{s}\"", .{text}),
        .symbol => |text| allocator.dupe(u8, text),
        .link => |link| std.fmt.allocPrint(allocator, "link(n{d})", .{link}),
        .duration_ms => |duration_ms| std.fmt.allocPrint(allocator, "{d}ms", .{duration_ms}),
        .none => allocator.dupe(u8, "none"),
        .list => allocator.dupe(u8, "<list>"),
        .record => allocator.dupe(u8, "<record>"),
        .binding_ref => |binding_id| std.fmt.allocPrint(allocator, "binding({d})", .{binding_id}),
        .terminal => allocator.dupe(u8, "<terminal>"),
        .document => allocator.dupe(u8, "<document>"),
        .stripe => allocator.dupe(u8, "<stripe>"),
        .label => allocator.dupe(u8, "<label>"),
        .container => allocator.dupe(u8, "<container>"),
        .checkbox => allocator.dupe(u8, "<checkbox>"),
        .button => allocator.dupe(u8, "<button>"),
        .text_input => allocator.dupe(u8, "<text_input>"),
        .select => allocator.dupe(u8, "<select>"),
        .slider => allocator.dupe(u8, "<slider>"),
        .scoped_node => |deferred| std.fmt.allocPrint(
            allocator,
            "scoped(n{d}@{?d})",
            .{ deferred.node_id, if (deferred.scope) |scope| scope.id else null },
        ),
    };
}

fn valueAsNumber(value: Value) anyerror!f64 {
    return switch (value) {
        .number => |number| number,
        .text => |text| try std.fmt.parseFloat(f64, text),
        .duration_ms => |duration_ms| @floatFromInt(duration_ms),
        else => error.ExpectedNumericValue,
    };
}

fn valueAsText(value: Value) anyerror![]const u8 {
    return switch (value) {
        .text => |text| text,
        .symbol => |text| text,
        else => error.ExpectedTextValue,
    };
}

fn valueAsIndex(value: Value) anyerror!usize {
    const number = try valueAsNumber(value);
    if (std.math.isNan(number)) return 0;
    if (number <= 0) return 0;
    return @intFromFloat(@floor(number));
}

fn valueAsBool(value: Value) anyerror!bool {
    return switch (value) {
        .symbol => |text| blk: {
            if (std.mem.eql(u8, text, "True")) break :blk true;
            if (std.mem.eql(u8, text, "False")) break :blk false;
            return error.ExpectedBooleanValue;
        },
        .text => |text| blk: {
            if (std.mem.eql(u8, text, "True")) break :blk true;
            if (std.mem.eql(u8, text, "False")) break :blk false;
            return error.ExpectedBooleanValue;
        },
        .number => |number| number != 0,
        .none => false,
        else => error.ExpectedBooleanValue,
    };
}

fn cloneListValue(allocator: std.mem.Allocator, value: Value) anyerror!Value {
    return switch (value) {
        .list => |items| blk: {
            const clone = try allocator.alloc(Value, items.len);
            @memcpy(clone, items);
            break :blk .{ .list = clone };
        },
        else => error.ExpectedListValue,
    };
}

fn listItemsFromValue(value: Value) anyerror![]Value {
    return switch (value) {
        .list => |items| items,
        else => error.ExpectedListValue,
    };
}

fn compareValues(lhs: Value, rhs: Value) anyerror!std.math.Order {
    return switch (lhs) {
        .number => |number| try compareNumbers(number, try valueAsNumber(rhs)),
        .duration_ms => |duration_ms| try compareNumbers(@as(f64, @floatFromInt(duration_ms)), try valueAsNumber(rhs)),
        .text => |text| switch (rhs) {
            .text => |other| std.mem.order(u8, text, other),
            .symbol => |other| std.mem.order(u8, text, other),
            else => error.ExpectedComparableValue,
        },
        .symbol => |text| switch (rhs) {
            .text => |other| std.mem.order(u8, text, other),
            .symbol => |other| std.mem.order(u8, text, other),
            else => error.ExpectedComparableValue,
        },
        else => error.ExpectedComparableValue,
    };
}

fn compareNumbers(lhs: f64, rhs: f64) anyerror!std.math.Order {
    if (std.math.isNan(lhs) or std.math.isNan(rhs)) return error.ExpectedComparableValue;
    return std.math.order(lhs, rhs);
}

fn booleanValue(value: bool) Value {
    return .{ .symbol = if (value) "True" else "False" };
}

fn valueAsBoolLoose(value: Value) bool {
    return switch (value) {
        .symbol => |text| std.mem.eql(u8, text, "True"),
        .text => |text| std.mem.eql(u8, text, "True"),
        .number => |number| number != 0,
        else => false,
    };
}

fn duplicateOptionalRecordText(allocator: std.mem.Allocator, value: ?Value) anyerror!?[]const u8 {
    const item = value orelse return null;
    return try allocator.dupe(u8, try valueAsText(item));
}

fn optionalRecordNumber(value: ?Value) ?f64 {
    const item = value orelse return null;
    return switch (item) {
        .number => |number| number,
        .duration_ms => |duration_ms| @floatFromInt(duration_ms),
        else => null,
    };
}

fn panelLightingFromValue(_: *Session, value: Value) ?physical.PanelLighting {
    const items = switch (value) {
        .list => |items| items,
        else => return null,
    };

    var summary = physical.PanelLighting{
        .light_count = 0,
        .ambient_intensity = 0,
        .peak_intensity = 0,
    };

    for (items) |item| {
        const fields = switch (item) {
            .record => |fields| fields,
            else => continue,
        };
        const kind = switch (findRecordValue(fields, "kind") orelse continue) {
            .text => |text| text,
            .symbol => |text| text,
            else => continue,
        };
        const intensity = optionalRecordNumber(findRecordValue(fields, "intensity")) orelse 0;
        summary.light_count += 1;
        summary.peak_intensity = @max(summary.peak_intensity, intensity);
        if (std.mem.eql(u8, kind, "Light/ambient")) {
            summary.ambient_intensity += intensity;
        }
    }

    return if (summary.light_count == 0) null else summary;
}

fn themeGeometryValueForScope(self: *Session, allocator: std.mem.Allocator, scope: ?*const EvalScope) !Value {
    const theme_name = try currentThemeNameForScope(self, allocator, scope);
    const edge_radius: f64 = switch (theme_name) {
        .professional, .glassmorphism => 2,
        .neobrutalism => 0,
        .neumorphism => 3,
    };
    const bevel_angle: f64 = switch (theme_name) {
        .professional, .glassmorphism => 45,
        .neobrutalism => 30,
        .neumorphism => 50,
    };

    const fields = try allocator.alloc(RecordField, 2);
    fields[0] = .{ .name = "edge_radius", .value = .{ .number = edge_radius } };
    fields[1] = .{ .name = "bevel_angle", .value = .{ .number = bevel_angle } };
    return .{ .record = fields };
}

fn themeLightsValueForScope(self: *Session, allocator: std.mem.Allocator, scope: ?*const EvalScope) !Value {
    const theme_name = try currentThemeNameForScope(self, allocator, scope);
    const directional: f64 = switch (theme_name) {
        .professional => 1.2,
        .glassmorphism => 1.1,
        .neobrutalism => 1.5,
        .neumorphism => 1.15,
    };
    const ambient: f64 = switch (theme_name) {
        .professional => 0.4,
        .glassmorphism => 0.45,
        .neobrutalism => 0.3,
        .neumorphism => 0.42,
    };
    const spot: f64 = switch (theme_name) {
        .professional => 0.3,
        .glassmorphism => 0.35,
        .neobrutalism => 0.5,
        .neumorphism => 0.25,
    };

    const items = try allocator.alloc(Value, 3);
    items[0] = try lightRecord(allocator, "Light/directional", directional);
    items[1] = try lightRecord(allocator, "Light/ambient", ambient);
    items[2] = try lightRecord(allocator, "Light/spot", spot);
    return .{ .list = items };
}

const ThemeName = enum {
    professional,
    glassmorphism,
    neobrutalism,
    neumorphism,
};

fn currentThemeNameFromPassed(value: Value) ThemeName {
    const theme_options = recordFieldFromValue(value, "theme_options") orelse return .professional;
    const name_value = recordFieldFromValue(theme_options, "name") orelse return .professional;
    const name = switch (name_value) {
        .symbol => |text| text,
        .text => |text| text,
        else => return .professional,
    };
    if (std.mem.eql(u8, name, "Glassmorphism")) return .glassmorphism;
    if (std.mem.eql(u8, name, "Neobrutalism")) return .neobrutalism;
    if (std.mem.eql(u8, name, "Neumorphism")) return .neumorphism;
    return .professional;
}

fn currentThemeNameForScope(self: *Session, allocator: std.mem.Allocator, scope: ?*const EvalScope) !ThemeName {
    if (scope) |passed| {
        if (passed.passed) |root| return currentThemeNameFromPassed(root);
    }
    const theme_binding = for (self.flow.bindings, 0..) |binding, index| {
        if (std.mem.eql(u8, binding.name, "theme_options")) break @as(flow_ir.BindingId, @intCast(index));
    } else return .professional;
    const theme_value = try self.evalNode(allocator, self.flow.bindings[theme_binding].node, null);
    const passed = Value{ .record = try allocator.dupe(RecordField, &.{
        .{ .name = "theme_options", .value = theme_value },
    }) };
    return currentThemeNameFromPassed(passed);
}

fn currentThemeName(scope: ?*const EvalScope) ThemeName {
    const passed = scope orelse return .professional;
    const root = passed.passed orelse return .professional;
    const theme_options = recordFieldFromValue(root, "theme_options") orelse return .professional;
    const name_value = recordFieldFromValue(theme_options, "name") orelse return .professional;
    const name = switch (name_value) {
        .symbol => |text| text,
        .text => |text| text,
        else => return .professional,
    };
    if (std.mem.eql(u8, name, "Glassmorphism")) return .glassmorphism;
    if (std.mem.eql(u8, name, "Neobrutalism")) return .neobrutalism;
    if (std.mem.eql(u8, name, "Neumorphism")) return .neumorphism;
    return .professional;
}

fn lightRecord(allocator: std.mem.Allocator, kind: []const u8, intensity: f64) !Value {
    const fields = try allocator.alloc(RecordField, 2);
    fields[0] = .{ .name = "kind", .value = .{ .text = try allocator.dupe(u8, kind) } };
    fields[1] = .{ .name = "intensity", .value = .{ .number = intensity } };
    return .{ .record = fields };
}

fn themeGeometryPrimitiveFromValue(value: Value) ?physical.GeometryPrimitive {
    const fields = switch (value) {
        .record => |fields| fields,
        else => return null,
    };

    const edge_radius = optionalRecordNumber(findRecordValue(fields, "edge_radius")) orelse return null;
    const bevel_angle = optionalRecordNumber(findRecordValue(fields, "bevel_angle")) orelse return null;

    const wall_thickness = std.math.clamp(edge_radius, 1.0, 4.0);
    const rim_depth = @max(2.0, bevel_angle / 15.0);
    const cavity_floor_depth = @max(0.0, rim_depth - wall_thickness);

    return .{ .cavity_rect = .{
        .outer_shape = "ThemeGeometry",
        .inner_shape = "ThemeInset",
        .rim_depth = rim_depth,
        .cavity_floor_depth = cavity_floor_depth,
        .wall_thickness = wall_thickness,
    } };
}

fn panelMaterialFromValues(_: *Session, materials: ?Value, colors: ?Value) ?physical.PanelMaterial {
    var summary = physical.PanelMaterial{};
    var saw_any = false;
    if (materials) |value| accumulatePanelMaterial(value, null, &summary, &saw_any);
    if (colors) |value| accumulatePanelMaterial(value, null, &summary, &saw_any);
    return if (saw_any) summary else null;
}

fn accumulatePanelMaterial(
    value: Value,
    name_hint: ?[]const u8,
    summary: *physical.PanelMaterial,
    saw_any: *bool,
) void {
    if (name_hint) |hint| {
        if (panelToneFromText(hint)) |tone| {
            mergePanelTone(summary, tone);
            saw_any.* = true;
        }
    }

    switch (value) {
        .record => |fields| {
            for (fields) |field| {
                if (std.mem.eql(u8, field.name, "gloss")) {
                    if (optionalRecordNumber(field.value)) |number| {
                        summary.gloss = @max(summary.gloss, number);
                        saw_any.* = true;
                    }
                    continue;
                }
                if (std.mem.eql(u8, field.name, "metal")) {
                    if (optionalRecordNumber(field.value)) |number| {
                        summary.metal = @max(summary.metal, number);
                        saw_any.* = true;
                    }
                    continue;
                }
                if (std.mem.eql(u8, field.name, "glow")) {
                    if (recordFieldFromValue(field.value, "intensity")) |glow_intensity| {
                        if (optionalRecordNumber(glow_intensity)) |number| {
                            summary.glow_intensity = @max(summary.glow_intensity, number);
                            saw_any.* = true;
                        }
                    }
                }
                accumulatePanelMaterial(field.value, field.name, summary, saw_any);
            }
        },
        .list => |items| for (items) |item| accumulatePanelMaterial(item, name_hint, summary, saw_any),
        .text => |text| {
            if (panelToneFromText(text)) |tone| {
                mergePanelTone(summary, tone);
                saw_any.* = true;
            }
        },
        .symbol => |text| {
            if (panelToneFromText(text)) |tone| {
                mergePanelTone(summary, tone);
                saw_any.* = true;
            }
        },
        else => {},
    }
}

fn mergePanelTone(summary: *physical.PanelMaterial, tone: physical.PanelTone) void {
    if (panelTonePriority(tone) > panelTonePriority(summary.tone)) summary.tone = tone;
}

fn panelTonePriority(tone: physical.PanelTone) u8 {
    return switch (tone) {
        .neutral => 0,
        .cool, .warm => 1,
        .danger => 2,
    };
}

fn panelToneFromText(text: []const u8) ?physical.PanelTone {
    if (std.ascii.indexOfIgnoreCase(text, "danger") != null or std.ascii.indexOfIgnoreCase(text, "error") != null) {
        return .danger;
    }
    if (std.ascii.indexOfIgnoreCase(text, "primary") != null or
        std.ascii.indexOfIgnoreCase(text, "blue") != null or
        std.ascii.indexOfIgnoreCase(text, "cool") != null)
    {
        return .cool;
    }
    if (std.ascii.indexOfIgnoreCase(text, "warning") != null or
        std.ascii.indexOfIgnoreCase(text, "warm") != null or
        std.ascii.indexOfIgnoreCase(text, "amber") != null or
        std.ascii.indexOfIgnoreCase(text, "orange") != null)
    {
        return .warm;
    }
    return null;
}

fn stripeDirectionFromValue(value: Value) StripeDirection {
    return switch (value) {
        .symbol => |text| if (std.mem.eql(u8, text, "Row")) .row else .column,
        .text => |text| if (std.mem.eql(u8, text, "Row")) .row else .column,
        else => .column,
    };
}

fn appendControlSection(output: *std.ArrayList(u8), allocator: std.mem.Allocator, label: []const u8, items: []const []const u8) !void {
    if (items.len == 0) return;
    const header = try std.fmt.allocPrint(allocator, "{s} ({d}):\n", .{ label, items.len });
    try output.appendSlice(allocator, header);
    const visible_len = @min(items.len, control_summary_limit);
    for (items[0..visible_len], 0..) |item, index| {
        const line = try std.fmt.allocPrint(allocator, "  {d} {s}\n", .{ index, item });
        try output.appendSlice(allocator, line);
    }
    if (visible_len < items.len) {
        const rest = try std.fmt.allocPrint(allocator, "  ... {d} more\n", .{items.len - visible_len});
        try output.appendSlice(allocator, rest);
    }
}

fn valuesEqual(lhs: Value, rhs: Value) bool {
    return switch (lhs) {
        .number => |number| switch (rhs) {
            .number => |other| if (std.math.isNan(number) and std.math.isNan(other)) true else number == other,
            else => false,
        },
        .text => |text| switch (rhs) {
            .text => |other| std.mem.eql(u8, text, other),
            .symbol => |other| std.mem.eql(u8, text, other),
            else => false,
        },
        .symbol => |text| switch (rhs) {
            .text => |other| std.mem.eql(u8, text, other),
            .symbol => |other| std.mem.eql(u8, text, other),
            else => false,
        },
        .duration_ms => |duration_ms| switch (rhs) {
            .duration_ms => |other| duration_ms == other,
            else => false,
        },
        .list => |items| switch (rhs) {
            .list => |other| blk: {
                if (items.len != other.len) break :blk false;
                for (items, other) |item, other_item| {
                    if (!valuesEqual(item, other_item)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        .record => |fields| switch (rhs) {
            .record => |other| blk: {
                if (fields.len != other.len) break :blk false;
                for (fields, other) |field, other_field| {
                    if (!std.mem.eql(u8, field.name, other_field.name)) break :blk false;
                    if (!valuesEqual(field.value, other_field.value)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        .link => |link| switch (rhs) {
            .link => |other| link == other,
            else => false,
        },
        .scoped_node => |deferred| switch (rhs) {
            .scoped_node => |other| deferred.node_id == other.node_id and deferred.scope == other.scope,
            else => false,
        },
        .none => rhs == .none,
        else => false,
    };
}

fn matchesPattern(input: Value, pattern: Value) bool {
    return switch (pattern) {
        .text => |text| if (std.mem.eql(u8, text, "__")) true else switch (input) {
            .text => |other| std.mem.eql(u8, text, other),
            .symbol => |other| std.mem.eql(u8, text, other),
            else => false,
        },
        .symbol => |text| if (std.mem.eql(u8, text, "__")) true else switch (input) {
            .text => |other| std.mem.eql(u8, text, other),
            .symbol => |other| std.mem.eql(u8, text, other),
            else => false,
        },
        .number => |number| switch (input) {
            .number => |other| if (std.math.isNan(number) and std.math.isNan(other)) true else number == other,
            else => false,
        },
        .none => input == .none,
        else => false,
    };
}

fn patternBinding(allocator: std.mem.Allocator, flow: flow_ir.Document, pattern_id: flow_ir.NodeId, input: Value, pattern: Value) anyerror!?RecordField {
    if (matchesPattern(input, pattern)) return null;

    const node = flow.nodes[pattern_id];
    return switch (node.kind) {
        .symbol => |text| if (isCaptureName(text)) .{
            .name = try allocator.dupe(u8, text),
            .value = input,
        } else null,
        else => null,
    };
}

fn isCaptureName(text: []const u8) bool {
    if (text.len == 0) return false;
    if (std.mem.eql(u8, text, "__")) return false;
    return switch (text[0]) {
        'a'...'z', '_' => true,
        else => false,
    };
}

fn extractPressLink(value: Value) ?flow_ir.NodeId {
    return extractEventLink(value, "press");
}

fn extractChangeLink(value: Value) ?flow_ir.NodeId {
    return extractEventLink(value, "change");
}

fn extractClickLink(value: Value) ?flow_ir.NodeId {
    return extractEventLink(value, "click");
}

fn extractKeyLink(value: Value) ?flow_ir.NodeId {
    return extractEventLink(value, "key_down");
}

fn extractBlurLink(value: Value) ?flow_ir.NodeId {
    return extractEventLink(value, "blur");
}

fn extractFocusLink(value: Value) ?flow_ir.NodeId {
    return extractEventLink(value, "focus");
}

fn extractDoubleClickLink(value: Value) ?flow_ir.NodeId {
    return extractEventLink(value, "double_click");
}

fn extractHoverLink(value: Value) ?flow_ir.NodeId {
    return switch (value) {
        .record => |fields| blk: {
            const hovered = findRecordValue(fields, "hovered") orelse break :blk null;
            break :blk switch (hovered) {
                .link => |link| link,
                else => null,
            };
        },
        else => null,
    };
}

fn eventLinkFromValue(value: Value, event_name: []const u8) ?flow_ir.NodeId {
    return switch (value) {
        .record => |fields| blk: {
            if (std.mem.eql(u8, event_name, "hovered")) {
                break :blk extractHoverLink(value);
            }
            if (findRecordValue(fields, "event")) |event_value| {
                if (eventLinkFromValue(event_value, event_name)) |link| break :blk link;
            }
            const field_value = findRecordValue(fields, event_name) orelse break :blk null;
            break :blk nestedRepresentativeLink(field_value);
        },
        .button => |button| if (std.mem.eql(u8, event_name, "press"))
            button.press_link
        else if (std.mem.eql(u8, event_name, "hovered"))
            button.hovered_link
        else
            null,
        .checkbox => |checkbox| if (std.mem.eql(u8, event_name, "click")) checkbox.click_link else null,
        .label => |label| if (std.mem.eql(u8, event_name, "click"))
            label.click_link
        else if (std.mem.eql(u8, event_name, "double_click"))
            label.double_click_link
        else
            null,
        .stripe => |stripe| if (std.mem.eql(u8, event_name, "hovered")) stripe.hovered_link else null,
        .text_input => |input| if (std.mem.eql(u8, event_name, "change"))
            input.change_link
        else if (std.mem.eql(u8, event_name, "key_down"))
            input.key_link orelse input.change_link
        else if (std.mem.eql(u8, event_name, "blur"))
            input.blur_link orelse input.change_link
        else if (std.mem.eql(u8, event_name, "focus"))
            input.focus_link orelse input.change_link
        else
            null,
        .select => |select| if (std.mem.eql(u8, event_name, "change")) select.change_link else null,
        .slider => |slider| if (std.mem.eql(u8, event_name, "change")) slider.change_link else null,
        else => null,
    };
}

fn nestedRepresentativeLink(value: Value) ?flow_ir.NodeId {
    return switch (value) {
        .link => |link| link,
        .record => |fields| {
            for (fields) |field| {
                if (nestedRepresentativeLink(field.value)) |link| return link;
            }
            return null;
        },
        else => null,
    };
}

fn extractEventLink(value: Value, event_name: []const u8) ?flow_ir.NodeId {
    return switch (value) {
        .record => |fields| blk: {
            const event = findRecordValue(fields, "event") orelse break :blk null;
            const event_fields = switch (event) {
                .record => |event_fields| event_fields,
                else => break :blk null,
            };
            const link_value = findRecordValue(event_fields, event_name) orelse break :blk null;
            break :blk switch (link_value) {
                .link => |link| link,
                else => null,
            };
        },
        else => null,
    };
}

fn extractTerminalMetadata(value: Value) Value {
    return switch (value) {
        .record => |fields| findRecordValue(fields, "terminal") orelse .none,
        else => .none,
    };
}

fn optionalLinkValue(link: ?flow_ir.NodeId) Value {
    return if (link) |resolved| .{ .link = resolved } else .none;
}

fn allocRecordValue(allocator: std.mem.Allocator, fields: []const RecordField) !Value {
    const copy = try allocator.alloc(RecordField, fields.len);
    @memcpy(copy, fields);
    return .{ .record = copy };
}

fn terminalContractFromValue(self: *Session, allocator: std.mem.Allocator, terminal: *TerminalValue) !TerminalContract {
    return .{
        .keyboard_bindings = try collectTerminalBindingsAlloc(self, allocator, terminal.root),
        .loop = try terminalLoopSpecFromValue(self, allocator, terminal.loop),
    };
}

fn materializeTerminalContractValue(self: *Session, allocator: std.mem.Allocator, value: Value) !Value {
    const materialized = try self.materializeValue(allocator, value);
    return switch (materialized) {
        .binding_ref => |binding_id| try materializeTerminalContractValue(
            self,
            allocator,
            try self.evalNode(allocator, self.flow.bindings[binding_id].node, null),
        ),
        .list => |items| blk: {
            const resolved = try allocator.alloc(Value, items.len);
            for (items, 0..) |item, index| {
                resolved[index] = try materializeTerminalContractValue(self, allocator, item);
            }
            break :blk .{ .list = resolved };
        },
        .record => |fields| blk: {
            const resolved = try allocator.alloc(RecordField, fields.len);
            for (fields, 0..) |field, index| {
                resolved[index] = .{
                    .name = field.name,
                    .value = try materializeTerminalContractValue(self, allocator, field.value),
                };
            }
            break :blk .{ .record = resolved };
        },
        else => materialized,
    };
}

fn terminalPreferredScopeAlloc(self: *Session, allocator: std.mem.Allocator, value: Value) !?*const EvalScope {
    return switch (value) {
        .scoped_node => |deferred| try captureScope(allocator, Session.canonicalControlScope(deferred.scope) orelse deferred.scope),
        .binding_ref => |binding_id| try terminalPreferredScopeAlloc(
            self,
            allocator,
            try self.evalNode(allocator, self.flow.bindings[binding_id].node, null),
        ),
        .record => |fields| blk: {
            for (fields) |field| {
                if (try terminalPreferredScopeAlloc(self, allocator, field.value)) |scope| break :blk scope;
            }
            break :blk null;
        },
        .list => |items| blk: {
            for (items) |item| {
                if (try terminalPreferredScopeAlloc(self, allocator, item)) |scope| break :blk scope;
            }
            break :blk null;
        },
        else => null,
    };
}

fn appendTerminalBindingsFromValue(
    self: *Session,
    allocator: std.mem.Allocator,
    bindings: *std.ArrayList(TerminalKeyBinding),
    bindings_value: Value,
    scope: ?*const EvalScope,
) !void {
    if (bindings_value == .none) return;
    const resolved_terminal = try materializeTerminalContractValue(self, allocator, bindings_value);
    const resolved_bindings = switch (resolved_terminal) {
        .record => |fields| findRecordValue(fields, "bindings") orelse return,
        .list => resolved_terminal,
        .none => return,
        else => return error.ExpectedRecordValue,
    };
    const items = try listItemsFromValue(resolved_bindings);
    const canonical_scope = Session.canonicalControlScope(scope) orelse scope;
    for (items) |item| {
        const fields = switch (item) {
            .record => |fields| fields,
            else => return error.ExpectedRecordValue,
        };
        const keys_value = findRecordValue(fields, "keys") orelse return error.MissingRecordField;
        const keys_list = try listItemsFromValue(keys_value);
        const keys = try allocator.alloc([]const u8, keys_list.len);
        for (keys_list, 0..) |key_value, key_index| {
            keys[key_index] = try allocator.dupe(u8, try valueAsText(key_value));
        }
        errdefer allocator.free(keys);

        const link_value = findRecordValue(fields, "link") orelse return error.MissingRecordField;
        const link = switch (link_value) {
            .link => |link| link,
            else => return error.ExpectedLinkValue,
        };
        const when = if (findRecordValue(fields, "when")) |when_value| try valueAsBool(when_value) else true;
        const label = if (findRecordValue(fields, "label")) |label_value| try allocator.dupe(u8, try valueAsText(label_value)) else null;
        try bindings.append(allocator, .{
            .keys = keys,
            .link = link,
            .scope = if (canonical_scope) |resolved_scope| try captureScope(allocator, resolved_scope) else null,
            .when = when,
            .label = label,
        });
    }
}

fn collectTerminalBindingsAlloc(self: *Session, allocator: std.mem.Allocator, value: Value) ![]TerminalKeyBinding {
    var bindings: std.ArrayList(TerminalKeyBinding) = .empty;
    defer bindings.deinit(allocator);
    try collectTerminalBindings(self, &bindings, allocator, value);
    return try bindings.toOwnedSlice(allocator);
}

fn terminalLoopSpecFromValue(self: *Session, allocator: std.mem.Allocator, loop_value: Value) !?TerminalLoopSpec {
    if (loop_value == .none) return null;
    const resolved_loop = try materializeTerminalContractValue(self, allocator, loop_value);
    switch (resolved_loop) {
        .none => return null,
        .symbol => |symbol| if (std.mem.eql(u8, symbol, "None")) return null,
        else => {},
    }
    const loop_scope = try terminalPreferredScopeAlloc(self, allocator, resolved_loop);
    errdefer destroyCapturedScope(allocator, loop_scope);
    const pulse_value = recordFieldFromValue(resolved_loop, "pulse") orelse return error.MissingRecordField;
    const pulse_link = switch (pulse_value) {
        .link => |link| link,
        else => return error.ExpectedLinkValue,
    };
    const while_value = recordFieldFromValue(resolved_loop, "while") orelse return error.MissingRecordField;
    const every_value = recordFieldFromValue(resolved_loop, "every") orelse return error.MissingRecordField;
    return .{
        .pulse_link = pulse_link,
        .scope = loop_scope,
        .while_active = try valueAsBool(while_value),
        .every_ms = switch (every_value) {
            .duration_ms => |ms| ms,
            else => return error.ExpectedDurationValue,
        },
    };
}

fn collectButtonLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectButtonLinks(self, list, allocator, item),
        .document => |document| try collectButtonLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectButtonLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectButtonLinks(self, list, allocator, item),
        .container => |container| try collectButtonLinks(self, list, allocator, container.child),
        .label => |label| if (label.click_link) |link| try list.append(allocator, .{ .link = link, .scope = label.event_scope }),
        .checkbox => |checkbox| if (checkbox.click_link) |link| try list.append(allocator, .{ .link = link, .scope = checkbox.event_scope }),
        .button => |button| if (button.press_link) |link| try list.append(allocator, .{ .link = link, .scope = button.event_scope }),
        .scoped_node => |deferred| try collectButtonLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectTerminalBindings(self: *Session, list: *std.ArrayList(TerminalKeyBinding), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectTerminalBindings(self, list, allocator, item),
        .document => |document| try collectTerminalBindings(self, list, allocator, document.root),
        .terminal => |terminal| try collectTerminalBindings(self, list, allocator, terminal.root),
        .stripe => |stripe| {
            try appendTerminalBindingsFromValue(self, allocator, list, stripe.terminal_bindings, stripe.event_scope);
            for (stripe.items) |item| try collectTerminalBindings(self, list, allocator, item);
        },
        .label => |label| try appendTerminalBindingsFromValue(self, allocator, list, label.terminal_bindings, label.event_scope),
        .container => |container| {
            try appendTerminalBindingsFromValue(self, allocator, list, container.terminal_bindings, container.event_scope);
            try collectTerminalBindings(self, list, allocator, container.child);
        },
        .checkbox => |checkbox| try appendTerminalBindingsFromValue(self, allocator, list, checkbox.terminal_bindings, checkbox.event_scope),
        .button => |button| try appendTerminalBindingsFromValue(self, allocator, list, button.terminal_bindings, button.event_scope),
        .text_input => |input| try appendTerminalBindingsFromValue(self, allocator, list, input.terminal_bindings, input.event_scope),
        .select => |select| try appendTerminalBindingsFromValue(self, allocator, list, select.terminal_bindings, select.event_scope),
        .slider => |slider| try appendTerminalBindingsFromValue(self, allocator, list, slider.terminal_bindings, slider.event_scope),
        .scoped_node => |deferred| try collectTerminalBindings(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectLabelDoubleClickLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectLabelDoubleClickLinks(self, list, allocator, item),
        .document => |document| try collectLabelDoubleClickLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectLabelDoubleClickLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectLabelDoubleClickLinks(self, list, allocator, item),
        .container => |container| try collectLabelDoubleClickLinks(self, list, allocator, container.child),
        .label => |label| if (label.double_click_link) |link| try list.append(allocator, .{ .link = link, .scope = label.event_scope }),
        .scoped_node => |deferred| try collectLabelDoubleClickLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectHoverLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectHoverLinks(self, list, allocator, item),
        .document => |document| try collectHoverLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectHoverLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| {
            if (stripe.hovered_link) |link| try list.append(allocator, .{ .link = link, .scope = stripe.event_scope });
            for (stripe.items) |item| try collectHoverLinks(self, list, allocator, item);
        },
        .container => |container| try collectHoverLinks(self, list, allocator, container.child),
        .button => |button| if (button.hovered_link) |link| try list.append(allocator, .{ .link = link, .scope = button.event_scope }),
        .scoped_node => |deferred| try collectHoverLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectSliderLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectSliderLinks(self, list, allocator, item),
        .document => |document| try collectSliderLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectSliderLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectSliderLinks(self, list, allocator, item),
        .container => |container| try collectSliderLinks(self, list, allocator, container.child),
        .slider => |slider| if (slider.change_link) |link| try list.append(allocator, .{ .link = link, .scope = slider.event_scope }),
        .scoped_node => |deferred| try collectSliderLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectTextInputLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectTextInputLinks(self, list, allocator, item),
        .document => |document| try collectTextInputLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectTextInputLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectTextInputLinks(self, list, allocator, item),
        .container => |container| try collectTextInputLinks(self, list, allocator, container.child),
        .text_input => |input| if (input.change_link) |link| try list.append(allocator, .{ .link = link, .scope = input.event_scope }),
        .scoped_node => |deferred| try collectTextInputLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectTextInputValues(self: *Session, list: *std.ArrayList(*TextInputValue), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectTextInputValues(self, list, allocator, item),
        .document => |document| try collectTextInputValues(self, list, allocator, document.root),
        .terminal => |terminal| try collectTextInputValues(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectTextInputValues(self, list, allocator, item),
        .container => |container| try collectTextInputValues(self, list, allocator, container.child),
        .text_input => |input| try list.append(allocator, input),
        .scoped_node => |deferred| try collectTextInputValues(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectTextInputKeyLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectTextInputKeyLinks(self, list, allocator, item),
        .document => |document| try collectTextInputKeyLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectTextInputKeyLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectTextInputKeyLinks(self, list, allocator, item),
        .container => |container| try collectTextInputKeyLinks(self, list, allocator, container.child),
        .text_input => |input| if (input.key_link orelse input.change_link) |link| try list.append(allocator, .{ .link = link, .scope = input.event_scope }),
        .scoped_node => |deferred| try collectTextInputKeyLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectTextInputBlurLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectTextInputBlurLinks(self, list, allocator, item),
        .document => |document| try collectTextInputBlurLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectTextInputBlurLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectTextInputBlurLinks(self, list, allocator, item),
        .container => |container| try collectTextInputBlurLinks(self, list, allocator, container.child),
        .text_input => |input| if (input.blur_link) |link| try list.append(allocator, .{ .link = link, .scope = input.event_scope }),
        .scoped_node => |deferred| try collectTextInputBlurLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectTextInputFocusLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectTextInputFocusLinks(self, list, allocator, item),
        .document => |document| try collectTextInputFocusLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectTextInputFocusLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectTextInputFocusLinks(self, list, allocator, item),
        .container => |container| try collectTextInputFocusLinks(self, list, allocator, container.child),
        .text_input => |input| if (input.focus_link) |link| try list.append(allocator, .{ .link = link, .scope = input.event_scope }),
        .scoped_node => |deferred| try collectTextInputFocusLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectSelectLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectSelectLinks(self, list, allocator, item),
        .document => |document| try collectSelectLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectSelectLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectSelectLinks(self, list, allocator, item),
        .container => |container| try collectSelectLinks(self, list, allocator, container.child),
        .select => |select| if (select.change_link) |link| try list.append(allocator, .{ .link = link, .scope = select.event_scope }),
        .scoped_node => |deferred| try collectSelectLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

test "counter headless session renders and clicks deterministically" {
    const source = @embedFile("../examples/upstream/counter/counter.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected headless failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("0+", initial);

    try session.clickButton(0);
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expectEqualStrings("1+", after_one);

    try session.clickButton(0);
    try session.clickButton(0);
    try session.clickButton(0);
    try session.clickButton(0);
    const after_five = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_five);
    try std.testing.expectEqualStrings("5+", after_five);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external click button[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "sum n") != null);
}

test "counter headless session persists and clears state deterministically" {
    const source = @embedFile("../examples/upstream/counter/counter.bn");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const state_file_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/counter-state.json", .{tmp_path});
    defer std.testing.allocator.free(state_file_path);

    {
        const outcome = try runAlloc(std.testing.allocator, source, .{
            .state_file_path = state_file_path,
            .clear_state = true,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter persistence failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        try session.clickButton(0);
        try session.clickButton(0);
        try session.clickButton(0);
        try session.clickButton(0);
        try session.clickButton(0);

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings("5+", rendered);
    }

    {
        const outcome = try runAlloc(std.testing.allocator, source, .{
            .state_file_path = state_file_path,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter persistence reload failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings("5+", rendered);
    }

    {
        const outcome = try runAlloc(std.testing.allocator, source, .{
            .state_file_path = state_file_path,
            .clear_state = true,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter clear-state failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings("0+", rendered);
    }
}

test "interval headless session advances with virtual time" {
    const source = @embedFile("../examples/upstream/interval/interval.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected interval headless failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("", initial);

    try session.advanceTime(1100);
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expectEqualStrings("1", after_one);

    try session.advanceTime(1000);
    const after_two = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_two);
    try std.testing.expectEqualStrings("2", after_two);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init timer") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "timer n") != null);
}

test "block and when evaluate in headless runtime" {
    const source =
        \\document: Document/new(root: BLOCK {
        \\    value: 2
        \\    value |> WHEN {
        \\        1 => TEXT { no }
        \\        2 => TEXT { yes }
        \\        __ => TEXT { fallback }
        \\    }
        \\})
        \\
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected block/when failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("yes", rendered);
}

test "scene root renders through headless runtime" {
    const source =
        \\scene: Scene/new(root: TEXT { Hello })
        \\
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected scene-root headless failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello", rendered);
}

test "Text/join concatenates mapped text ranges through headless runtime" {
    const source =
        \\joined:
        \\    List/range(from: 0, to: 4)
        \\    |> List/map(column, new:
        \\        column == 2 |> WHEN {
        \\            True => TEXT { o }
        \\            False => TEXT { . }
        \\        }
        \\    )
        \\    |> Text/join()
        \\
        \\document: Document/new(root: Element/label(
        \\    element: []
        \\    style: []
        \\    label: joined
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected Text/join failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("..o..", rendered);
}

test "scene root records physical scene inputs in trace" {
    const source =
        \\scene: Scene/new(
        \\    root: TEXT { Hello }
        \\    lights: [ambient: 0.5]
        \\    materials: [surface: [gloss: 0.2]]
        \\)
        \\
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected physical scene trace failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical scene") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical pending") != null);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello", rendered);
}

test "scene geometry executes model cut result in trace" {
    const source =
        \\scene: Scene/new(
        \\    root: TEXT { Hello }
        \\    geometry: Model/cut(
        \\        from: [shape: Outer depth: 8]
        \\        remove: [shape: Inner depth: 5 wall: 2]
        \\    )
        \\)
        \\
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected model cut trace failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical geometry") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "cavity_depth=5") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "remaining_depth=3") != null);

    var saw_cut_result = false;
    var saw_cavity_primitive = false;
    var saw_depth_raster = false;
    var saw_ascii_display = false;
    var saw_shaded_display = false;
    var saw_panel_display = false;
    var saw_shaded_panel = false;
    var saw_lit_panel = false;
    for (session.geometry_results) |maybe_result| {
        if (maybe_result) |result| switch (result) {
            .cut => |cut_result| {
                try std.testing.expectEqual(@as(?f64, 5), cut_result.cavity_depth);
                try std.testing.expectEqual(@as(?f64, 3), cut_result.remaining_depth);
                try std.testing.expectEqual(@as(?f64, 2), cut_result.wall_thickness);
                const height_field = cut_result.height_field orelse return error.MissingHeightField;
                try std.testing.expectEqual(@as(f64, 3), height_field.heightAt(0));
                try std.testing.expectEqual(@as(f64, 8), height_field.heightAt(1));
                saw_cut_result = true;
            },
            else => {},
        };
    }
    try std.testing.expect(saw_cut_result);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical primitive") != null);
    for (session.geometry_primitives) |maybe_primitive| {
        if (maybe_primitive) |primitive| switch (primitive) {
            .cavity_rect => |cavity| {
                try std.testing.expectEqualStrings("Outer", cavity.outer_shape.?);
                try std.testing.expectEqualStrings("Inner", cavity.inner_shape.?);
                try std.testing.expectEqual(@as(f64, 3), cavity.sampleHeight(0));
                try std.testing.expectEqual(@as(f64, 8), cavity.sampleHeight(1));
                saw_cavity_primitive = true;
            },
            else => {},
        };
    }
    try std.testing.expect(saw_cavity_primitive);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical raster") != null);
    for (session.geometry_rasters) |maybe_raster| {
        if (maybe_raster) |raster| switch (raster) {
            .depth_strip => |strip| {
                try std.testing.expectEqualStrings("Outer", strip.outer_shape.?);
                try std.testing.expectEqualStrings("Inner", strip.inner_shape.?);
                try std.testing.expectEqual(@as(f64, 8), strip.samples[0]);
                try std.testing.expectEqual(@as(f64, 3), strip.samples[4]);
                try std.testing.expectEqual(@as(f64, 8), strip.samples[8]);
                saw_depth_raster = true;
            },
            else => {},
        };
    }
    try std.testing.expect(saw_depth_raster);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical display") != null);
    for (session.geometry_displays) |maybe_display| {
        if (maybe_display) |display| switch (display) {
            .ascii_strip => |ascii| {
                try std.testing.expectEqualStrings("Outer", ascii.outer_shape.?);
                try std.testing.expectEqualStrings("Inner", ascii.inner_shape.?);
                const text = try ascii.textAlloc(std.testing.allocator);
                defer std.testing.allocator.free(text);
                try std.testing.expectEqualStrings("##.....##", text);
                saw_ascii_display = true;
            },
            else => {},
        };
    }
    try std.testing.expect(saw_ascii_display);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical shaded") != null);
    for (session.geometry_shaded_strips) |maybe_shaded| {
        if (maybe_shaded) |shaded| {
            try std.testing.expectEqualStrings("Outer", shaded.outer_shape.?);
            try std.testing.expectEqualStrings("Inner", shaded.inner_shape.?);
            const text = try shaded.textAlloc(std.testing.allocator);
            defer std.testing.allocator.free(text);
            try std.testing.expectEqualStrings("#\\...../#", text);
            saw_shaded_display = true;
        }
    }
    try std.testing.expect(saw_shaded_display);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical panel") != null);
    for (session.geometry_panels) |maybe_panel| {
        if (maybe_panel) |panel| {
            try std.testing.expectEqualStrings("Outer", panel.outer_shape.?);
            try std.testing.expectEqualStrings("Inner", panel.inner_shape.?);
            const text = try panel.textAlloc(std.testing.allocator);
            defer std.testing.allocator.free(text);
            try std.testing.expectEqualStrings(
                "  #####  \n#\\...../#\n||.....||\n||.....||\n  \\\\\\\\\\  ",
                text,
            );
            saw_panel_display = true;
        }
    }
    try std.testing.expect(saw_panel_display);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical shaded_panel") != null);
    for (session.geometry_shaded_panels) |maybe_panel| {
        if (maybe_panel) |panel| {
            try std.testing.expectEqualStrings("Outer", panel.outer_shape.?);
            try std.testing.expectEqualStrings("Inner", panel.inner_shape.?);
            const text = try panel.textAlloc(std.testing.allocator);
            defer std.testing.allocator.free(text);
            try std.testing.expectEqualStrings(
                "  @@@@@  \n@v:::::/@\n##:::::##\n##:::::##\n  vvvvv  ",
                text,
            );
            saw_shaded_panel = true;
        }
    }
    try std.testing.expect(saw_shaded_panel);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical lit_panel") != null);
    for (session.geometry_lit_panels) |maybe_panel| {
        if (maybe_panel) |panel| {
            try std.testing.expectEqualStrings("Outer", panel.outer_shape.?);
            try std.testing.expectEqualStrings("Inner", panel.inner_shape.?);
            const text = try panel.textAlloc(std.testing.allocator);
            defer std.testing.allocator.free(text);
            try std.testing.expectEqualStrings(
                "  *****  \n*V...../*\n##.....##\n##.....##\n  VVVVV  ",
                text,
            );
            saw_lit_panel = true;
        }
    }
    try std.testing.expect(saw_lit_panel);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello", rendered);
}

test "scene geometry propagates materials and colors into lit panel" {
    const source =
        \\scene: Scene/new(
        \\    root: TEXT { Hello }
        \\    lights: LIST {
        \\        Light/ambient(intensity: 0.4)
        \\        Light/key(intensity: 1.2)
        \\        Light/fill(intensity: 0.8)
        \\    }
        \\    geometry: Model/cut(
        \\        from: [shape: Outer depth: 8]
        \\        remove: [shape: Inner depth: 5 wall: 2]
        \\    )
        \\    materials: [
        \\        surface: [
        \\            gloss: 0.7
        \\            metal: 0.4
        \\            glow: [intensity: 0.1]
        \\        ]
        \\    ]
        \\    colors: [
        \\        danger: [hex: TEXT { #f00 }]
        \\    ]
        \\)
        \\
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected material/color lit panel failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical lit_panel") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "gloss=0.7") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "metal=0.4") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "tone=danger") != null);

    var saw_lit_panel = false;
    for (session.geometry_lit_panels) |maybe_panel| {
        if (maybe_panel) |panel| {
            const material = panel.material orelse continue;
            try std.testing.expectEqual(@as(f64, 0.7), material.gloss);
            try std.testing.expectEqual(@as(f64, 0.4), material.metal);
            try std.testing.expectEqual(@as(f64, 0.1), material.glow_intensity);
            try std.testing.expectEqual(physical.PanelTone.danger, material.tone);
            const text = try panel.textAlloc(std.testing.allocator);
            defer std.testing.allocator.free(text);
            try std.testing.expectEqualStrings(
                "  =====  \n=V!!!!!/=\nMM!!!!!MM\nMM!!!!!MM\n  VVVVV  ",
                text,
            );
            saw_lit_panel = true;
        }
    }
    try std.testing.expect(saw_lit_panel);

    const snapshot = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expectEqualStrings(
        "  =====  \n=V!!!!!/=\nMM!!!!!MM\nMM!!!!!MM\n  VVVVV  ",
        snapshot,
    );

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello", rendered);
}

test "scene theme geometry record reaches physical snapshot target" {
    const source =
        \\scene: Scene/new(
        \\    root: TEXT { Hello }
        \\    lights: LIST {
        \\        Light/ambient(intensity: 0.4)
        \\        Light/key(intensity: 1.2)
        \\        Light/fill(intensity: 0.8)
        \\    }
        \\    geometry: [
        \\        edge_radius: 2
        \\        bevel_angle: 45
        \\    ]
        \\)
        \\
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected theme geometry snapshot failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "physical primitive") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "ThemeGeometry") != null);

    const snapshot = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expectEqualStrings(
        "  *****  \n*V...../*\n##.....##\n##.....##\n  VVVVV  ",
        snapshot,
    );

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("Hello", rendered);
}

test "todo_mvc_physical snapshot follows live theme state" {
    const source = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "examples/upstream/todo_mvc_physical/RUN.bn",
        std.math.maxInt(usize),
    );
    defer std.testing.allocator.free(source);

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected todo_mvc_physical failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial_snapshot = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial_snapshot);
    try std.testing.expectEqualStrings(
        "  *****  \nV......./\n##.....##\n##.....##\n  VVVVV  ",
        initial_snapshot,
    );

    try session.clickButton(2);

    const updated_snapshot = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(updated_snapshot);
    try std.testing.expectEqualStrings(
        "  *****  \nV,,,,,,,/\n##,,,,,##\n##,,,,,##\n  VVVVV  ",
        updated_snapshot,
    );
}

test "scene element aliases render through headless runtime" {
    const source =
        \\scene: Scene/new(root: Scene/Element/block(
        \\    element: []
        \\    child: Scene/Element/stripe(
        \\        element: []
        \\        direction: Column
        \\        items: LIST {
        \\            Scene/Element/text(element: [], text: TEXT { Hello })
        \\            Scene/Element/button(
        \\                element: [event: [press: LINK]]
        \\                label: Scene/Element/text(element: [], text: TEXT { World })
        \\            )
        \\        }
        \\    )
        \\))
        \\
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected scene element headless failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("HelloWorld", rendered);
}

test "counter_hold headless session stores state deterministically" {
    const source = @embedFile("../examples/upstream/counter_hold/counter_hold.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected counter_hold failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("0+", initial);

    try session.clickButton(0);
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expectEqualStrings("1+", after_one);

    try session.clickButton(0);
    const after_two = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_two);
    try std.testing.expectEqualStrings("2+", after_two);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init hold") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "hold n") != null);
}

test "counter_hold headless session persists and clears hold state deterministically" {
    const source = @embedFile("../examples/upstream/counter_hold/counter_hold.bn");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const state_file_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/counter-hold-state.json", .{tmp_path});
    defer std.testing.allocator.free(state_file_path);

    {
        const outcome = try runAlloc(std.testing.allocator, source, .{
            .state_file_path = state_file_path,
            .clear_state = true,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter_hold persistence failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        try session.clickButton(0);
        try session.clickButton(0);

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings("2+", rendered);
    }

    {
        const outcome = try runAlloc(std.testing.allocator, source, .{
            .trace = true,
            .state_file_path = state_file_path,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter_hold persistence reload failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings("2+", rendered);

        const trace = try session.traceAlloc(std.testing.allocator);
        defer std.testing.allocator.free(trace);
        try std.testing.expect(std.mem.indexOf(u8, trace, "restore hold") != null);
    }

    {
        const outcome = try runAlloc(std.testing.allocator, source, .{
            .state_file_path = state_file_path,
            .clear_state = true,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter_hold clear-state failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings("0+", rendered);
    }
}

test "counter_hold persistence survives node id shifts via stable ids" {
    const source_v1 =
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Column
        \\    gap: 0
        \\    style: []
        \\
        \\    items: LIST {
        \\        counter
        \\        increment_button
        \\    }
        \\))
        \\
        \\counter: 0 |> HOLD counter {
        \\    increment_button.event.press |> THEN { counter + 1 }
        \\}
        \\
        \\increment_button: Element/button(
        \\    element: [event: [press: LINK]]
        \\    style: []
        \\    label: TEXT { + }
        \\)
    ;
    const source_v2 =
        \\noise: 10 |> Math/sum()
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Column
        \\    gap: 0
        \\    style: []
        \\
        \\    items: LIST {
        \\        counter
        \\        increment_button
        \\    }
        \\))
        \\
        \\counter: 0 |> HOLD counter {
        \\    increment_button.event.press |> THEN { counter + 1 }
        \\}
        \\
        \\increment_button: Element/button(
        \\    element: [event: [press: LINK]]
        \\    style: []
        \\    label: TEXT { + }
        \\)
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const state_file_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/counter-hold-migrate.json", .{tmp_path});
    defer std.testing.allocator.free(state_file_path);

    {
        const outcome = try runAlloc(std.testing.allocator, source_v1, .{
            .state_file_path = state_file_path,
            .clear_state = true,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter_hold v1 persistence failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        try session.clickButton(0);
        try session.clickButton(0);
    }

    {
        const outcome = try runAlloc(std.testing.allocator, source_v2, .{
            .trace = true,
            .state_file_path = state_file_path,
        });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected counter_hold v2 persistence reload failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings("2+", rendered);

        const trace = try session.traceAlloc(std.testing.allocator);
        defer std.testing.allocator.free(trace);
        try std.testing.expect(std.mem.indexOf(u8, trace, "persist read hold") != null);
        try std.testing.expect(std.mem.indexOf(u8, trace, "restore hold") != null);
    }
}

test "stored button element in record exposes press events through headless runtime" {
    const source =
        \\store: [
        \\    elements: [
        \\        increment: Element/button(
        \\            element: [event: [press: LINK]]
        \\            style: []
        \\            label: TEXT { + }
        \\        )
        \\    ]
        \\]
        \\
        \\counter: 0 |> HOLD counter {
        \\    store.elements.increment.event.press |> THEN { counter + 1 }
        \\}
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Column
        \\    gap: 0
        \\    style: []
        \\    items: LIST { counter, store.elements.increment }
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected stored button failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("0+", initial);

    try session.clickButton(0);

    const updated = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("1+", updated);
}

test "stored text input element in record exposes change and key events through headless runtime" {
    const source =
        \\store: [
        \\    elements: [
        \\        input: Element/text_input(
        \\            element: [event: [change: LINK, key_down: LINK]]
        \\            style: []
        \\            label: Hidden[text: TEXT { Input }]
        \\            text: draft
        \\            placeholder: []
        \\            focus: False
        \\        )
        \\    ]
        \\]
        \\
        \\draft: TEXT {} |> HOLD draft {
        \\    store.elements.input.event.change |> THEN { store.elements.input.event.change.text }
        \\}
        \\
        \\committed: TEXT { idle } |> HOLD committed {
        \\    store.elements.input.event.key_down.key |> WHEN {
        \\        Enter => store.elements.input.event.key_down.text
        \\        __ => SKIP
        \\    }
        \\}
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Column
        \\    gap: 0
        \\    style: []
        \\    items: LIST { store.elements.input, committed }
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected stored text input failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.setTextInputValue(0, "Milk");
    const after_change = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_change);
    try std.testing.expectEqualStrings("Milkidle", after_change);

    try session.pressTextInputKey(0, "Enter");
    const after_key = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_key);
    try std.testing.expectEqualStrings("MilkMilk", after_key);
}

test "custom record event links preserve key_down.text access after key press" {
    const source =
        \\event_ports: [
        \\    edit_text_event: LINK
        \\    edit_committed: LINK
        \\]
        \\
        \\draft: TEXT {} |> HOLD draft {
        \\    event_ports.edit_text_event
        \\}
        \\
        \\committed: TEXT { idle } |> HOLD committed {
        \\    event_ports.edit_committed
        \\}
        \\
        \\input: BLOCK {
        \\    editing_element: [event: [change: LINK, key_down: LINK]]
        \\
        \\    edit_changed_link:
        \\        editing_element.event.change
        \\        |> THEN { editing_element.event.change.text }
        \\        |> LINK { event_ports.edit_text_event }
        \\
        \\    edit_committed_link:
        \\        editing_element.event.key_down.key
        \\        |> WHEN {
        \\            Enter => editing_element.event.key_down.text
        \\            __ => SKIP
        \\        }
        \\        |> LINK { event_ports.edit_committed }
        \\
        \\    Element/text_input(
        \\        element: editing_element
        \\        style: []
        \\        label: Hidden[text: TEXT { Input }]
        \\        text: draft
        \\        placeholder: []
        \\        focus: False
        \\    )
        \\}
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Column
        \\    gap: 0
        \\    style: []
        \\    items: LIST { input, committed }
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected custom event link failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.setTextInputValue(0, "Milk");
    try session.pressTextInputKey(0, "Enter");

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("MilkMilk", rendered);
}

test "terminal root exposes element-owned terminal binding and scoped link pulses" {
    const source =
        \\store: [
        \\    elements: [launch: LINK]
        \\    count: 0 |> HOLD count {
        \\        store.elements.launch.event.press |> THEN { count + 1 }
        \\    }
        \\]
        \\
        \\terminal: Terminal/new(
        \\    root: Element/label(
        \\        element: [
        \\            terminal: [
        \\                bindings: LIST {
        \\                    [keys: LIST { TEXT { Enter } } link: store.elements.launch label: TEXT { launch }]
        \\                }
        \\            ]
        \\        ]
        \\        style: []
        \\        label: store.count
        \\    )
        \\    loop: None
        \\)
    ;
    const outcome = try runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal root failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try std.testing.expect(session.rootKind() == .terminal);

    var contract = (try session.terminalContractAlloc(std.testing.allocator)).?;
    defer contract.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), contract.keyboard_bindings.len);
    try std.testing.expectEqualStrings("Enter", contract.keyboard_bindings[0].keys[0]);
    try std.testing.expect(contract.keyboard_bindings[0].scope != null);

    try session.triggerLinkWithScope(contract.keyboard_bindings[0].link, contract.keyboard_bindings[0].scope);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("1", rendered);
}

test "pong terminal root exposes root element bindings" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected pong terminal failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    var contract = (try session.terminalContractAlloc(std.testing.allocator)).?;
    defer contract.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), contract.keyboard_bindings.len);
    try std.testing.expectEqualStrings("Up", contract.keyboard_bindings[0].keys[0]);
    try std.testing.expectEqualStrings("Enter", contract.keyboard_bindings[2].keys[0]);

    try session.triggerLinkWithScope(contract.keyboard_bindings[2].link, contract.keyboard_bindings[2].scope);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Rally") != null);
}

test "terminal dimension builtins reflect configured viewport" {
    const source =
        \\terminal: Terminal/new(
        \\    root: Element/label(
        \\        element: []
        \\        style: []
        \\        label: TEXT { {Terminal/columns()}x{Terminal/rows()} }
        \\    )
        \\    loop: None
        \\)
    ;
    const outcome = try runAlloc(std.testing.allocator, source, .{
        .terminal_columns = 91,
        .terminal_rows = 33,
    });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal dimension failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const snapshot = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(snapshot);
    try std.testing.expectEqualStrings("91x33", snapshot);
}

test "nested store hold field exposes sibling derived value through headless runtime" {
    const source =
        \\store: [
        \\    elements: [
        \\        increment: Element/button(
        \\            element: [event: [press: LINK]]
        \\            style: []
        \\            label: TEXT { + }
        \\        )
        \\    ]
        \\
        \\    game: [
        \\        counter: 0 |> HOLD counter {
        \\            store.elements.increment.event.press |> THEN { counter + 1 }
        \\        }
        \\
        \\        doubled: counter * 2
        \\    ]
        \\]
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Column
        \\    gap: 0
        \\    style: []
        \\    items: LIST { store.game.doubled, store.elements.increment }
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected nested store hold failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("0+", initial);

    try session.clickButton(0);

    const updated = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("2+", updated);
}

test "deeply nested store hold field remains interactive through headless runtime" {
    const source =
        \\store: [
        \\    ui: [
        \\        controls: [
        \\            increment: Element/button(
        \\                element: [event: [press: LINK]]
        \\                style: []
        \\                label: TEXT { + }
        \\            )
        \\        ]
        \\    ]
        \\
        \\    game: [
        \\        stats: [
        \\            counter: 0 |> HOLD counter {
        \\                store.ui.controls.increment.event.press |> THEN { counter + 1 }
        \\            }
        \\            doubled: counter * 2
        \\        ]
        \\    ]
        \\]
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Column
        \\    gap: 0
        \\    style: []
        \\    items: LIST { store.game.stats.doubled, store.ui.controls.increment }
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected deeply nested store hold failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("0+", initial);

    try session.clickButton(0);

    const updated = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(updated);
    try std.testing.expectEqualStrings("2+", updated);
}

test "nested store hold field can read sibling hold value on unscoped tick" {
    const source =
        \\store: [
        \\    elements: [ serve: LINK tick: LINK ]
        \\    x: -1 |> HOLD x {
        \\        store.elements.serve.event.press |> THEN { 8 }
        \\        store.elements.tick.event.press |> THEN { store.y }
        \\    }
        \\    y: -1 |> HOLD y {
        \\        store.elements.serve.event.press |> THEN { 3 }
        \\        store.elements.tick.event.press |> THEN { y }
        \\    }
        \\]
        \\
        \\FUNCTION serve_button() {
        \\    Element/button(
        \\        element: [event: [press: store.elements.serve]]
        \\        style: []
        \\        label: TEXT { S }
        \\    )
        \\}
        \\
        \\FUNCTION tick_button() {
        \\    Element/button(
        \\        element: [event: [press: store.elements.tick]]
        \\        style: []
        \\        label: TEXT { T }
        \\    )
        \\}
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Row
        \\    gap: 0
        \\    style: []
        \\    items: LIST { store.x, TEXT { , }, store.y, serve_button(), tick_button() }
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected sibling hold read failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.clickButton(0);
    try session.clickButton(1);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("3,3ST", rendered);
}

test "nested store hold field can read sibling hold value inside block on unscoped tick" {
    const source =
        \\FUNCTION idle_ball(x, y) {
        \\    x == -1 |> Bool/or(that: y == -1)
        \\}
        \\
        \\store: [
        \\    elements: [ serve: LINK tick: LINK ]
        \\    x: -1 |> HOLD x {
        \\        store.elements.serve.event.press |> THEN { 8 }
        \\        store.elements.tick.event.press |> THEN {
        \\            BLOCK {
        \\                y_now: store.y
        \\                idle_ball(x: x, y: y_now) |> WHEN {
        \\                    True => -1
        \\                    False => x + 1
        \\                }
        \\            }
        \\        }
        \\    }
        \\    y: -1 |> HOLD y {
        \\        store.elements.serve.event.press |> THEN { 3 }
        \\        store.elements.tick.event.press |> THEN {
        \\            BLOCK {
        \\                x_now: store.x
        \\                idle_ball(x: x_now, y: y) |> WHEN {
        \\                    True => -1
        \\                    False => y
        \\                }
        \\            }
        \\        }
        \\    }
        \\]
        \\
        \\FUNCTION serve_button() {
        \\    Element/button(
        \\        element: [event: [press: store.elements.serve]]
        \\        style: []
        \\        label: TEXT { S }
        \\    )
        \\}
        \\
        \\FUNCTION tick_button() {
        \\    Element/button(
        \\        element: [event: [press: store.elements.tick]]
        \\        style: []
        \\        label: TEXT { T }
        \\    )
        \\}
        \\
        \\document: Document/new(root: Element/stripe(
        \\    element: []
        \\    direction: Row
        \\    gap: 0
        \\    style: []
        \\    items: LIST { store.x, TEXT { , }, store.y, serve_button(), tick_button() }
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected sibling block hold read failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.clickButton(0);
    try session.clickButton(1);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("9,3ST", rendered);
}

test "interval_hold headless session skips the initial hold value" {
    const source = @embedFile("../examples/upstream/interval_hold/interval_hold.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected interval_hold failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("", initial);

    try session.advanceTime(1100);
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expectEqualStrings("1", after_one);

    try session.advanceTime(1000);
    const after_two = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_two);
    try std.testing.expectEqualStrings("2", after_two);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init skip") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "skip n") != null);
}

test "complex_counter headless session runs through user functions and pass context" {
    const source = @embedFile("../examples/upstream/complex_counter/complex_counter.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected complex_counter failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expectEqualStrings("-0+", initial);

    try session.clickButton(1);
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expectEqualStrings("-1+", after_one);

    try session.clickButton(1);
    const after_two = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_two);
    try std.testing.expectEqualStrings("-2+", after_two);

    try session.clickButton(0);
    const after_three = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_three);
    try std.testing.expectEqualStrings("-1+", after_three);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "latest n") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "hold n") != null);
}

test "timer headless session handles elapsed time, reset, and slider changes" {
    const source = @embedFile("../examples/upstream/timer/timer.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected timer failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Timer") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Elapsed Time:") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Duration:") != null);

    try session.advanceTime(1000);
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expect(std.mem.indexOf(u8, after_one, "1s") != null);

    try session.clickButton(0);
    const after_reset = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_reset);
    try std.testing.expect(std.mem.indexOf(u8, after_reset, "0s") != null);

    try session.setSliderValue(0, 2);
    const after_slider = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_slider);
    try std.testing.expect(std.mem.indexOf(u8, after_slider, "2s") != null);

    try session.advanceTime(3000);
    const after_three = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_three);
    try std.testing.expect(std.mem.indexOf(u8, after_three, "100%") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external slider[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external click button[0]") != null);
}

test "flight_booker headless session handles while branches and input events" {
    const source = @embedFile("../examples/upstream/flight_booker/flight_booker.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected flight_booker failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "FlightBooker") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "one-way") != null);

    try session.setSelectValue(0, "return");
    try session.setTextInputValue(0, "2026-03-03");
    try session.setTextInputValue(1, "2026-03-05");
    try session.clickButton(0);

    const booked = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(booked);
    try std.testing.expect(std.mem.indexOf(u8, booked, "return") != null);
    try std.testing.expect(std.mem.indexOf(u8, booked, "Bookedreturnflight:2026-03-03to2026-03-05") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external select[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external click button[0]") != null);
}

test "then when while headless sessions boot with deferred scoped timers" {
    const cases = [_]struct {
        source: []const u8,
        expected: []const u8,
    }{
        .{ .source = @embedFile("../examples/upstream/then/then.bn"), .expected = "A:0B:0A + B0" },
        .{ .source = @embedFile("../examples/upstream/when/when.bn"), .expected = "A:0B:0A + BA - B" },
        .{ .source = @embedFile("../examples/upstream/while/while.bn"), .expected = "A + BA - B" },
    };

    for (cases) |case| {
        const outcome = try runAlloc(std.testing.allocator, case.source, .{ .trace = true });
        const session_value = switch (outcome) {
            .ok => |session| session,
            .err => |failure| {
                std.debug.print("unexpected scoped timer boot failure: {s}\n", .{failure.message});
                return error.UnexpectedHeadlessFailure;
            },
        };
        var session = session_value;
        defer session.deinit();

        const rendered = try session.renderAlloc(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expect(std.mem.indexOf(u8, rendered, case.expected) != null);

        const trace = try session.traceAlloc(std.testing.allocator);
        defer std.testing.allocator.free(trace);
        try std.testing.expect(std.mem.indexOf(u8, trace, "defer scoped timer") != null);
    }
}

test "latest headless session seeds from the first static source and updates on clicks" {
    const source = @embedFile("../examples/upstream/latest/latest.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected latest failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Send 1Send 23Sum: 3") != null);

    try session.clickButton(0);
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expect(std.mem.indexOf(u8, after_one, "Send 1Send 21Sum: 1") != null);

    try session.clickButton(1);
    const after_two = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_two);
    try std.testing.expect(std.mem.indexOf(u8, after_two, "Send 1Send 22Sum: 2") != null);
}

test "layers headless session renders stacked card labels" {
    const source = @embedFile("../examples/upstream/layers/layers.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected layers failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Red CardGreen CardBlue Card") != null);
}

test "circle_drawer headless session boots and renders initial count" {
    const source = @embedFile("../examples/upstream/circle_drawer/circle_drawer.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected circle_drawer failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Circle DrawerUndoCircles:0") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init list_remove_last") != null);
}

test "fibonacci headless session renders final computed value" {
    const source = @embedFile("../examples/upstream/fibonacci/fibonacci.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected fibonacci failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "10. Fibonacci number is 55") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "pulses n") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "hold n") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "skip n") != null);
}

test "temperature_converter headless session converts edited temperatures" {
    const source = @embedFile("../examples/upstream/temperature_converter/temperature_converter.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected temperature_converter failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "TemperatureConverter") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Celsius") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Fahrenheit") != null);

    try session.setTextInputValue(0, "100");
    const after_celsius = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_celsius);
    try std.testing.expect(std.mem.indexOf(u8, after_celsius, "100") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_celsius, "212") != null);

    try session.setTextInputValue(1, "32");
    const after_fahrenheit = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_fahrenheit);
    try std.testing.expect(std.mem.indexOf(u8, after_fahrenheit, "0") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_fahrenheit, "32") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input[1]") != null);
}

test "shopping_list headless session adds and clears items" {
    const source = @embedFile("../examples/upstream/shopping_list/shopping_list.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected shopping_list failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "0items") != null);

    try session.setTextInputValue(0, "Milk");
    try session.pressTextInputKey(0, "Enter");
    const after_one = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_one);
    try std.testing.expect(std.mem.indexOf(u8, after_one, "1items") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_one, "Milk") != null);

    try session.setTextInputValue(0, "Bread");
    try session.pressTextInputKey(0, "Enter");
    const after_two = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_two);
    try std.testing.expect(std.mem.indexOf(u8, after_two, "2items") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_two, "Bread") != null);

    try session.clickButton(0);
    const after_clear = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_clear);
    try std.testing.expect(std.mem.indexOf(u8, after_clear, "0items") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input_key[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "list_append n") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "list_clear n") != null);
}

test "list_retain_reactive headless session toggles filtered items" {
    const source = @embedFile("../examples/upstream/list_retain_reactive/list_retain_reactive.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected list_retain_reactive failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Toggle filter (show_even: False)") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Filtered count: 6") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "123456") != null);

    try session.clickButton(0);
    const filtered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(filtered);
    try std.testing.expect(std.mem.indexOf(u8, filtered, "Toggle filter (show_even: True)") != null);
    try std.testing.expect(std.mem.indexOf(u8, filtered, "Filtered count: 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, filtered, "246") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external click button[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "hold n") != null);
}

test "list_retain_count headless session updates derived counts after enter" {
    const source = @embedFile("../examples/upstream/list_retain_count/list_retain_count.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected list_retain_count failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "All count: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Retain count: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Initial") != null);

    try session.setTextInputValue(0, "Milk");
    try session.pressTextInputKey(0, "Enter");
    const after_enter = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_enter);
    try std.testing.expect(std.mem.indexOf(u8, after_enter, "All count: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_enter, "Retain count: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_enter, "Milk") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input_key[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "list_append n") != null);
}

test "crud headless session boots and renders initial people list" {
    const source = @embedFile("../examples/upstream/crud/crud.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected crud failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "CRUD") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Emil,Hans") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Mustermann,Max") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Tansen,Roman") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "CreateUpdateDelete") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init list_remove") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init latest") != null);
}

test "cells headless session renders initial spreadsheet grid" {
    const source = @embedFile("../examples/upstream/cells/cells.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected cells failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Cells") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "number") == null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "5") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "10") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "15") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "1 5 15 30") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init hold n") != null);
}

test "cells headless session recomputes dependent cells after edit commit" {
    const source = @embedFile("../examples/upstream/cells/cells.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected cells edit failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.doubleClickLabelByText(std.testing.allocator, "5");
    try session.setFirstTextInputValue(std.testing.allocator, "7");
    try session.pressFirstTextInputKey(std.testing.allocator, "Enter");

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "1 7 17 32") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external label_double_click") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input_key") != null);
}

test "cells_dynamic headless session renders initial spreadsheet grid" {
    const source = @embedFile("../examples/upstream/cells_dynamic/cells_dynamic.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected cells_dynamic failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Cells Dynamic") != null or std.mem.indexOf(u8, initial, "CellsDynamic") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "number") == null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "5") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "10") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "15") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "init hold n") != null);
}

test "cells_dynamic headless session recomputes dependent cells after edit commit" {
    const source = @embedFile("../examples/upstream/cells_dynamic/cells_dynamic.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected cells_dynamic edit failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.doubleClickLabelByText(std.testing.allocator, "5");
    try session.setFirstTextInputValue(std.testing.allocator, "7");
    try session.pressFirstTextInputKey(std.testing.allocator, "Enter");

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "1 7 17 32") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external label_double_click") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input_key") != null);
}

test "terminal cells headless session recomputes dependent cells after edit commit" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells edit failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.doubleClickLabelByText(std.testing.allocator, "5");
    try session.setFirstTextInputValue(std.testing.allocator, "7");
    try session.pressFirstTextInputKey(std.testing.allocator, "Enter");

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "1 7 17 32") != null);
}

test "terminal cells commit still works after snapshot renders between edit steps" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells snapshot-step failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.doubleClickLabelByText(std.testing.allocator, "5");
    const after_open = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_open);
    try std.testing.expect(std.mem.indexOf(u8, after_open, "<5>") != null);

    try session.setFirstTextInputValue(std.testing.allocator, "7");
    const after_change = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_change);
    try std.testing.expect(std.mem.indexOf(u8, after_change, "<7>") != null);

    try session.pressFirstTextInputKey(std.testing.allocator, "Enter");
    const rendered = try session.snapshotAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "1 7 17 32") != null);
}

test "terminal cells invalid formula commit degrades safely instead of crashing" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells invalid-formula failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.doubleClickLabelByText(std.testing.allocator, "15");
    try session.setFirstTextInputValue(std.testing.allocator, "=add(A1, A2)7");
    try session.pressFirstTextInputKey(std.testing.allocator, "Enter");

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "1 5 0 30") != null);
}

test "terminal cells_dynamic headless session recomputes dependent cells after edit commit" {
    const source = @embedFile("../examples/terminal/cells_dynamic/cells_dynamic.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected terminal cells_dynamic edit failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try session.doubleClickLabelByText(std.testing.allocator, "5");
    try session.setFirstTextInputValue(std.testing.allocator, "7");
    try session.pressFirstTextInputKey(std.testing.allocator, "Enter");

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "1 7 17 32") != null);
}

test "todo_mvc headless session adds, toggles, clears, and filters todos" {
    const source = @embedFile("../examples/upstream/todo_mvc/todo_mvc.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected todo_mvc failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Buygroceries") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Cleanroom") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "2itemsleft") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "3itemsleft") == null);

    try session.doubleClickLabel(0);
    try session.focusTextInput(1);
    try session.setTextInputValue(1, "Buy milk");
    try session.blurTextInput(1);
    const after_edit = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_edit);
    try std.testing.expect(std.mem.indexOf(u8, after_edit, "Buymilk") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_edit, "Buygroceries") == null);
    try std.testing.expect(std.mem.indexOf(u8, after_edit, "2itemsleft") != null);

    try session.setTextInputValue(0, "Write tests");
    try session.pressTextInputKey(0, "Enter");
    const after_add = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_add);
    try std.testing.expect(std.mem.indexOf(u8, after_add, "Writetests") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_add, "3itemsleft") != null);

    // Current headless button order:
    // 0 toggle-all checkbox, 1/2/3 todo checkboxes, 4/5/6 filter buttons, 7 clear completed.
    try session.clickButton(1);
    const after_toggle = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_toggle);
    try std.testing.expect(std.mem.indexOf(u8, after_toggle, "2itemsleft") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_toggle, "Clearcompleted") != null);

    try session.clickButton(7);
    const after_clear = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_clear);
    try std.testing.expect(std.mem.indexOf(u8, after_clear, "Buygroceries") == null);
    try std.testing.expect(std.mem.indexOf(u8, after_clear, "Cleanroom") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_clear, "Writetests") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_clear, "2itemsleft") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_clear, "Clearcompleted") == null);

    try session.clickButton(5);
    const completed_only = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(completed_only);
    try std.testing.expect(std.mem.indexOf(u8, completed_only, "Cleanroom") == null);
    try std.testing.expect(std.mem.indexOf(u8, completed_only, "Writetests") == null);
    try std.testing.expect(std.mem.indexOf(u8, completed_only, "2itemsleft") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external label_double_click[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input_focus[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input_blur[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external text_input_key[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "list_remove n") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "router_go_to") != null);
}

test "todo_mvc controls expose edit input after double click" {
    const source = @embedFile("../examples/upstream/todo_mvc/todo_mvc.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected todo_mvc controls failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial_controls = try session.controlsAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial_controls);
    try std.testing.expect(std.mem.indexOf(u8, initial_controls, "text (1):") != null);

    try session.doubleClickLabel(0);

    const controls = try session.controlsAlloc(std.testing.allocator);
    defer std.testing.allocator.free(controls);
    try std.testing.expect(std.mem.indexOf(u8, controls, "text (2):") != null);
    try std.testing.expect(std.mem.indexOf(u8, controls, "  1 Buygroceries") != null);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "<Buygroceries>") != null);
}

test "todo_mvc headless session removes a todo through hover-gated button" {
    const source = @embedFile("../examples/upstream/todo_mvc/todo_mvc.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected todo_mvc remove-button failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const initial = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(initial);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Buygroceries") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "×") == null);

    // Current hover order starts with the first todo row.
    try session.setHover(0, true);
    const hovered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(hovered);
    try std.testing.expect(std.mem.indexOf(u8, hovered, "×") != null);

    // Current button order after first-row hover:
    // 0 toggle-all, 1 first todo checkbox, 2 first-row remove button, then remaining controls.
    try session.clickButton(2);
    const after_remove = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_remove);
    try std.testing.expect(std.mem.indexOf(u8, after_remove, "Buygroceries") == null);
    try std.testing.expect(std.mem.indexOf(u8, after_remove, "Cleanroom") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_remove, "1itemsleft") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external hover[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external click button[2]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "list_remove n") != null);
}
