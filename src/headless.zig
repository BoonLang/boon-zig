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

const BuiltinOp = enum(u8) {
    unknown,
    document_new,
    scene_new,
    terminal_new,
    element_svg,
    element_svg_circle,
    element_stack,
    duration,
    terminal_columns,
    terminal_rows,
    router_route,
    router_go_to,
    theme_geometry,
    theme_lights,
    theme_material,
    theme_font,
    theme_text,
    theme_number,
    theme_spring_range,
    light_prefixed,
    element_stripe,
    scene_element_stripe,
    element_label,
    scene_element_label,
    element_container,
    scene_element_block,
    element_paragraph,
    scene_element_paragraph,
    element_checkbox,
    scene_element_checkbox,
    scene_element_text,
    text_empty,
    text_space,
    text_to_number,
    text_trim,
    text_is_not_empty,
    text_is_empty,
    text_length,
    text_find,
    text_substring,
    text_repeat,
    text_join,
    text_starts_with,
    bool_not,
    bool_or,
    bool_and,
    bool_toggle,
    element_button,
    scene_element_button,
    element_text_input,
    scene_element_text_input,
    element_select,
    element_link,
    scene_element_link,
    reference,
    assets_icon,
    element_slider,
    math_sum,
    math_min,
    math_round,
    ulid_generate,
    log_info,
    log_error,
    list_append,
    list_clear,
    list_remove,
    list_remove_last,
    list_count,
    list_is_empty,
    list_is_not_empty,
    list_get,
    list_range,
    list_map,
    list_retain,
    list_any,
    list_every,
    list_sum,
    list_latest,
    stream_pulses,
    stream_skip,
    timer_interval,
};

pub const CompiledProgram = struct {
    metadata_arena: std.heap.ArenaAllocator,
    flow: flow_ir.Document,
    builtin_ops: []BuiltinOp,
    node_needs_scope: []bool,
    node_needs_deferred_field: []bool,
    list_remove_nodes: []flow_ir.NodeId,
    list_remove_last_nodes: []flow_ir.NodeId,

    pub fn deinit(self: *CompiledProgram) void {
        self.flow.deinit();
        self.metadata_arena.deinit();
    }
};

pub const CompileOutcome = union(enum) {
    ok: CompiledProgram,
    err: diag.Diagnostic,
};

const compiled_cache_magic = "BNCP";
// Serialized builtin op metadata uses enum ordinals; bump this when layout changes.
const compiled_cache_version: u32 = 2;

const Pulse = struct {
    source: flow_ir.NodeId,
    payload: PulsePayload,
    scope: ?*const EvalScope = null,
    event_name: ?[]const u8 = null,
};

const PulsePayload = union(enum) {
    node: flow_ir.NodeId,
    value: Value,
};

pub const RecordField = struct {
    name: []const u8,
    value: Value,
};

const ScopedNodeKey = struct {
    node_id: flow_ir.NodeId,
    scope_id: u64,
};

const CachedEvalEntry = struct {
    value: Value,
    deps: []CachedDependency,
};

const CachedDependency = struct {
    key: ScopedNodeKey,
    version: u32,
};

const EvalFrame = struct {
    parent: ?*EvalFrame,
    deps: std.ArrayListUnmanaged(ScopedNodeKey) = .empty,
};

pub const ScopedNodeValue = struct {
    node_id: flow_ir.NodeId,
    scope: ?*const EvalScope,
};

pub const ScopedLinkValue = struct {
    link: flow_ir.NodeId,
    scope: ?*const EvalScope,
};

pub const DocumentValue = struct {
    root: Value,
};

pub const TerminalValue = struct {
    root: Value,
    loop: Value = .none,
};

pub const StripeDirection = enum {
    row,
    column,
};

pub const StripeValue = struct {
    items: []Value,
    direction: StripeDirection,
    gap: usize = 0,
    hovered_link: ?flow_ir.NodeId = null,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const LabelValue = struct {
    label: Value,
    click_link: ?flow_ir.NodeId = null,
    double_click_link: ?flow_ir.NodeId = null,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const ContainerValue = struct {
    child: Value,
    click_link: ?flow_ir.NodeId = null,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const CheckboxValue = struct {
    icon: Value,
    label: Value = .none,
    checked: Value = .none,
    click_link: ?flow_ir.NodeId,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const ButtonValue = struct {
    label: Value,
    press_link: ?flow_ir.NodeId,
    hovered_link: ?flow_ir.NodeId = null,
    disabled: bool = false,
    outlined: bool = false,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const TextInputValue = struct {
    text: Value,
    placeholder: Value = .none,
    change_link: ?flow_ir.NodeId,
    key_link: ?flow_ir.NodeId = null,
    blur_link: ?flow_ir.NodeId = null,
    focus_link: ?flow_ir.NodeId = null,
    focused: bool = false,
    disabled: bool = false,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const SelectValue = struct {
    selected: Value,
    change_link: ?flow_ir.NodeId,
    terminal_width: usize = 0,
    terminal_height: usize = 0,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const SliderValue = struct {
    change_link: ?flow_ir.NodeId,
    terminal_bindings: Value = .none,
    event_scope: ?*const EvalScope = null,
};

pub const EvalScope = struct {
    bindings: []const RecordField,
    parent: ?*const EvalScope,
    passed: ?Value = null,
    id: u64 = 0,
    transparent_state_scope: bool = false,
};

pub const Value = union(enum) {
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
    scoped_link: ScopedLinkValue,
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
    button_coordinate_payload: bool = false,
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
    list,
    record,
    link,
};

const PersistedScalar = struct {
    kind: PersistedScalarKind,
    number: ?f64 = null,
    text: ?[]const u8 = null,
    duration_ms: ?u64 = null,
    node_id: ?flow_ir.NodeId = null,
    list: ?[]PersistedScalar = null,
    record: ?[]PersistedRecordField = null,
};

const PersistedRecordField = struct {
    name: []const u8,
    value: PersistedScalar,
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

const PersistedListEntry = struct {
    stable_id: u64 = 0,
    node_id: ?flow_ir.NodeId = null,
    value: PersistedScalar,
};

const PersistedState = struct {
    version: u32 = 3,
    sums: []PersistedSumEntry = &.{},
    holds: []PersistedHoldEntry = &.{},
    lists: []PersistedListEntry = &.{},
};

const PersistKind = enum {
    sum,
    hold,
    list,
};

pub const ControlEventRef = struct {
    link: flow_ir.NodeId,
    scope: ?*const EvalScope = null,
};

pub const TextInputSessionRef = struct {
    change: ControlEventRef,
    key: ControlEventRef,
    blur: ?ControlEventRef = null,
    focus: ?ControlEventRef = null,
};

fn cloneControlEventRefForCache(allocator: std.mem.Allocator, event: ControlEventRef) !ControlEventRef {
    return .{
        .link = event.link,
        .scope = try captureControlScope(allocator, event.scope),
    };
}

fn cloneTextInputValueForCache(allocator: std.mem.Allocator, input: *const TextInputValue) !*TextInputValue {
    const copy = try allocator.create(TextInputValue);
    copy.* = .{
        .text = try cloneCapturedValue(allocator, input.text),
        .placeholder = try cloneCapturedValue(allocator, input.placeholder),
        .change_link = input.change_link,
        .key_link = input.key_link,
        .blur_link = input.blur_link,
        .focus_link = input.focus_link,
        .focused = input.focused,
        .disabled = input.disabled,
        .terminal_width = input.terminal_width,
        .terminal_height = input.terminal_height,
        .terminal_bindings = try cloneCapturedValue(allocator, input.terminal_bindings),
        .event_scope = try captureControlScope(allocator, input.event_scope),
    };
    return copy;
}

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

fn builtinOpFromPath(path: []const u8) BuiltinOp {
    if (std.mem.eql(u8, path, "Document/new")) return .document_new;
    if (std.mem.eql(u8, path, "Scene/new")) return .scene_new;
    if (std.mem.eql(u8, path, "Terminal/new")) return .terminal_new;
    if (std.mem.eql(u8, path, "Element/svg")) return .element_svg;
    if (std.mem.eql(u8, path, "Element/svg_circle")) return .element_svg_circle;
    if (std.mem.eql(u8, path, "Element/stack")) return .element_stack;
    if (std.mem.eql(u8, path, "Duration")) return .duration;
    if (std.mem.eql(u8, path, "Terminal/columns")) return .terminal_columns;
    if (std.mem.eql(u8, path, "Terminal/rows")) return .terminal_rows;
    if (std.mem.eql(u8, path, "Router/route")) return .router_route;
    if (std.mem.eql(u8, path, "Router/go_to")) return .router_go_to;
    if (std.mem.eql(u8, path, "Theme/geometry")) return .theme_geometry;
    if (std.mem.eql(u8, path, "Theme/lights")) return .theme_lights;
    if (std.mem.eql(u8, path, "Theme/material")) return .theme_material;
    if (std.mem.eql(u8, path, "Theme/font")) return .theme_font;
    if (std.mem.eql(u8, path, "Theme/text")) return .theme_text;
    if (std.mem.eql(u8, path, "Theme/depth") or
        std.mem.eql(u8, path, "Theme/elevation") or
        std.mem.eql(u8, path, "Theme/corners") or
        std.mem.eql(u8, path, "Theme/sizing") or
        std.mem.eql(u8, path, "Theme/spacing"))
        return .theme_number;
    if (std.mem.eql(u8, path, "Theme/spring_range")) return .theme_spring_range;
    if (std.mem.startsWith(u8, path, "Light/")) return .light_prefixed;
    if (std.mem.eql(u8, path, "Element/stripe")) return .element_stripe;
    if (std.mem.eql(u8, path, "Scene/Element/stripe")) return .scene_element_stripe;
    if (std.mem.eql(u8, path, "Element/label")) return .element_label;
    if (std.mem.eql(u8, path, "Scene/Element/label")) return .scene_element_label;
    if (std.mem.eql(u8, path, "Element/container")) return .element_container;
    if (std.mem.eql(u8, path, "Scene/Element/block")) return .scene_element_block;
    if (std.mem.eql(u8, path, "Element/paragraph")) return .element_paragraph;
    if (std.mem.eql(u8, path, "Scene/Element/paragraph")) return .scene_element_paragraph;
    if (std.mem.eql(u8, path, "Element/checkbox")) return .element_checkbox;
    if (std.mem.eql(u8, path, "Scene/Element/checkbox")) return .scene_element_checkbox;
    if (std.mem.eql(u8, path, "Scene/Element/text")) return .scene_element_text;
    if (std.mem.eql(u8, path, "Text/empty")) return .text_empty;
    if (std.mem.eql(u8, path, "Text/space")) return .text_space;
    if (std.mem.eql(u8, path, "Text/to_number")) return .text_to_number;
    if (std.mem.eql(u8, path, "Text/trim")) return .text_trim;
    if (std.mem.eql(u8, path, "Text/is_not_empty")) return .text_is_not_empty;
    if (std.mem.eql(u8, path, "Text/is_empty")) return .text_is_empty;
    if (std.mem.eql(u8, path, "Text/length")) return .text_length;
    if (std.mem.eql(u8, path, "Text/find")) return .text_find;
    if (std.mem.eql(u8, path, "Text/substring")) return .text_substring;
    if (std.mem.eql(u8, path, "Text/repeat")) return .text_repeat;
    if (std.mem.eql(u8, path, "Text/join")) return .text_join;
    if (std.mem.eql(u8, path, "Text/starts_with")) return .text_starts_with;
    if (std.mem.eql(u8, path, "Bool/not")) return .bool_not;
    if (std.mem.eql(u8, path, "Bool/or")) return .bool_or;
    if (std.mem.eql(u8, path, "Bool/and")) return .bool_and;
    if (std.mem.eql(u8, path, "Bool/toggle")) return .bool_toggle;
    if (std.mem.eql(u8, path, "Element/button")) return .element_button;
    if (std.mem.eql(u8, path, "Scene/Element/button")) return .scene_element_button;
    if (std.mem.eql(u8, path, "Element/text_input")) return .element_text_input;
    if (std.mem.eql(u8, path, "Scene/Element/text_input")) return .scene_element_text_input;
    if (std.mem.eql(u8, path, "Element/select")) return .element_select;
    if (std.mem.eql(u8, path, "Element/link")) return .element_link;
    if (std.mem.eql(u8, path, "Scene/Element/link")) return .scene_element_link;
    if (std.mem.eql(u8, path, "Reference")) return .reference;
    if (std.mem.eql(u8, path, "Assets/icon")) return .assets_icon;
    if (std.mem.eql(u8, path, "Element/slider")) return .element_slider;
    if (std.mem.eql(u8, path, "Math/sum")) return .math_sum;
    if (std.mem.eql(u8, path, "Math/min")) return .math_min;
    if (std.mem.eql(u8, path, "Math/round")) return .math_round;
    if (std.mem.eql(u8, path, "Ulid/generate")) return .ulid_generate;
    if (std.mem.eql(u8, path, "Log/info")) return .log_info;
    if (std.mem.eql(u8, path, "Log/error")) return .log_error;
    if (std.mem.eql(u8, path, "List/append")) return .list_append;
    if (std.mem.eql(u8, path, "List/clear")) return .list_clear;
    if (std.mem.eql(u8, path, "List/remove")) return .list_remove;
    if (std.mem.eql(u8, path, "List/remove_last")) return .list_remove_last;
    if (std.mem.eql(u8, path, "List/count")) return .list_count;
    if (std.mem.eql(u8, path, "List/is_empty")) return .list_is_empty;
    if (std.mem.eql(u8, path, "List/is_not_empty")) return .list_is_not_empty;
    if (std.mem.eql(u8, path, "List/get")) return .list_get;
    if (std.mem.eql(u8, path, "List/range")) return .list_range;
    if (std.mem.eql(u8, path, "List/map")) return .list_map;
    if (std.mem.eql(u8, path, "List/retain")) return .list_retain;
    if (std.mem.eql(u8, path, "List/any")) return .list_any;
    if (std.mem.eql(u8, path, "List/every")) return .list_every;
    if (std.mem.eql(u8, path, "List/sum")) return .list_sum;
    if (std.mem.eql(u8, path, "List/latest")) return .list_latest;
    if (std.mem.eql(u8, path, "Stream/pulses")) return .stream_pulses;
    if (std.mem.eql(u8, path, "Stream/skip")) return .stream_skip;
    if (std.mem.eql(u8, path, "Timer/interval")) return .timer_interval;
    return .unknown;
}

fn builtinNeedsDeferredField(op: BuiltinOp) bool {
    return switch (op) {
        .math_sum, .stream_pulses, .stream_skip, .list_append, .list_clear, .list_remove, .list_remove_last => true,
        else => false,
    };
}

pub const Session = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    memo_arena: std.heap.ArenaAllocator,
    metadata_arena: std.heap.ArenaAllocator,
    scratch_arena: std.heap.ArenaAllocator,
    flow: flow_ir.Document,
    builtin_ops: []BuiltinOp = &.{},
    node_needs_scope: []bool = &.{},
    node_needs_deferred_field: []bool = &.{},
    top_level_owned_nodes: []bool = &.{},
    list_remove_nodes: []flow_ir.NodeId = &.{},
    list_remove_last_nodes: []flow_ir.NodeId = &.{},
    trace_enabled: bool,
    trace_lines: std.ArrayList([]const u8) = .empty,
    queue: std.ArrayList(Pulse) = .empty,
    subscribers: [][]flow_ir.NodeId = &.{},
    runtime_subscribers: []bool = &.{},
    runtime_subscriber_nodes: []flow_ir.NodeId = &.{},
    runtime_scopes: std.AutoHashMapUnmanaged(u64, *const EvalScope) = .empty,
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
    top_level_eval_values: []Value = &.{},
    top_level_eval_inited: []bool = &.{},
    top_level_eval_deps: [][]CachedDependency = &.{},
    eval_cache: std.AutoHashMapUnmanaged(ScopedNodeKey, CachedEvalEntry) = .empty,
    cached_terminal_contract: ?*TerminalContract = null,
    cached_terminal_contract_deps: ?[]ScopedNodeKey = null,
    cached_terminal_contract_versions: ?[]u32 = null,
    cached_terminal_hit_regions: ?[]TerminalHitRegion = null,
    cached_button_links: ?[]ControlEventRef = null,
    cached_button_links_deps: ?[]ScopedNodeKey = null,
    cached_button_links_versions: ?[]u32 = null,
    cached_slider_links: ?[]ControlEventRef = null,
    cached_slider_links_deps: ?[]ScopedNodeKey = null,
    cached_slider_links_versions: ?[]u32 = null,
    cached_text_input_links: ?[]ControlEventRef = null,
    cached_text_input_links_deps: ?[]ScopedNodeKey = null,
    cached_text_input_links_versions: ?[]u32 = null,
    cached_text_input_key_links: ?[]ControlEventRef = null,
    cached_text_input_key_links_deps: ?[]ScopedNodeKey = null,
    cached_text_input_key_links_versions: ?[]u32 = null,
    cached_text_input_blur_links: ?[]ControlEventRef = null,
    cached_text_input_blur_links_deps: ?[]ScopedNodeKey = null,
    cached_text_input_blur_links_versions: ?[]u32 = null,
    cached_text_input_focus_links: ?[]ControlEventRef = null,
    cached_text_input_focus_links_deps: ?[]ScopedNodeKey = null,
    cached_text_input_focus_links_versions: ?[]u32 = null,
    cached_label_double_click_links: ?[]ControlEventRef = null,
    cached_label_double_click_links_deps: ?[]ScopedNodeKey = null,
    cached_label_double_click_links_versions: ?[]u32 = null,
    cached_hover_links: ?[]ControlEventRef = null,
    cached_hover_links_deps: ?[]ScopedNodeKey = null,
    cached_hover_links_versions: ?[]u32 = null,
    cached_select_links: ?[]ControlEventRef = null,
    cached_select_links_deps: ?[]ScopedNodeKey = null,
    cached_select_links_versions: ?[]u32 = null,
    cached_text_inputs: ?[]*TextInputValue = null,
    cached_text_inputs_deps: ?[]ScopedNodeKey = null,
    cached_text_inputs_versions: ?[]u32 = null,
    current_eval_frame: ?*EvalFrame = null,
    terminal_columns: usize = 80,
    terminal_rows: usize = 24,
    list_values: []Value = &.{},
    list_inited: []bool = &.{},
    list_remove_tombstones: [][]Value = &.{},
    skip_values: []Value = &.{},
    skip_inited: []bool = &.{},
    skip_seen: []u64 = &.{},
    skip_limits: []u64 = &.{},
    skip_limit_inited: []bool = &.{},
    sum_values: []f64 = &.{},
    sum_inited: []bool = &.{},
    timer_period_ms: []u64 = &.{},
    timer_next_fire_ms: []u64 = &.{},
    state_versions: []u32 = &.{},
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
        self.memo_arena.deinit();
        self.scratch_arena.deinit();
        self.flow.deinit();
        self.metadata_arena.deinit();
        self.arena.deinit();
    }

    fn resetScratchArena(self: *Session) std.mem.Allocator {
        _ = self.scratch_arena.reset(.retain_capacity);
        return self.scratch_arena.allocator();
    }

    fn builtinOp(self: *const Session, node_id: flow_ir.NodeId) BuiltinOp {
        return self.builtin_ops[node_id];
    }

    fn clearEvalCache(self: *Session) void {
        if (self.top_level_eval_inited.len != 0) @memset(self.top_level_eval_inited, false);
        self.eval_cache.clearRetainingCapacity();
    }

    fn invalidateEvalCache(self: *Session) void {
        self.clearEvalCache();
        self.cached_terminal_contract = null;
        self.cached_terminal_contract_deps = null;
        self.cached_terminal_contract_versions = null;
        self.cached_terminal_hit_regions = null;
        self.dropCachedControlRefs(.button);
        self.dropCachedControlRefs(.slider);
        self.dropCachedControlRefs(.text_input);
        self.dropCachedControlRefs(.text_input_key);
        self.dropCachedControlRefs(.text_input_blur);
        self.dropCachedControlRefs(.text_input_focus);
        self.dropCachedControlRefs(.label_double_click);
        self.dropCachedControlRefs(.hover);
        self.dropCachedControlRefs(.select);
        self.dropCachedTextInputs();
    }

    fn flushPendingQueue(self: *Session) !void {
        if (self.queue.items.len != 0) try self.processQueue();
    }

    pub fn renderAlloc(self: *Session, allocator: std.mem.Allocator) anyerror![]u8 {
        try self.flushPendingQueue();
        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const scratch = self.resetScratchArena();

        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(scratch);

        try self.appendRenderedNode(&output, scratch, self.flow.bindings[root_binding].node, null);
        return try allocator.dupe(u8, output.items);
    }

    pub fn snapshotAlloc(self: *Session, allocator: std.mem.Allocator) anyerror![]u8 {
        try self.flushPendingQueue();
        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const scratch = self.resetScratchArena();

        const value = try self.evalNode(self.arena.allocator(), self.flow.bindings[root_binding].node, null);
        if (try self.livePhysicalRenderTarget(scratch)) |target| {
            return try target.textAlloc(allocator);
        }
        if (self.hasPhysicalRenderTarget()) {
            return try self.cachedPhysicalSnapshotAlloc(allocator);
        }
        const block = try self.snapshotBlock(scratch, value);

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
        _ = allocator;
        return try self.livePhysicalRenderTarget(self.resetScratchArena());
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
        const scratch = self.resetScratchArena();

        var summary: ControlSummary = .{};
        defer summary.deinit(scratch);
        try self.populateControlSummary(scratch, &summary);

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

    pub fn routeTextView(self: *Session) ![]const u8 {
        return try valueAsText(self.route_value);
    }

    pub fn triggerLink(self: *Session, link: flow_ir.NodeId) !void {
        return self.triggerLinkWithScope(link, null);
    }

    pub fn triggerLinkWithScope(self: *Session, link: flow_ir.NodeId, scope: ?*const EvalScope) !void {
        try self.logf("external link n{d}", .{link});
        try self.enqueueExternalNodePulse(link, scope, null);
    }

    pub fn terminalContractView(self: *Session) !?*const TerminalContract {
        if (self.rootKind() != .terminal) return null;
        try self.flushPendingQueue();
        if (self.cached_terminal_contract) |contract| {
            if (self.cachedTerminalContractIsFresh()) return contract;
            self.resetMemoDerivedCaches();
        }

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
            frame.deps.deinit(self.arena.allocator());
        }

        const contract = try self.memo_arena.allocator().create(TerminalContract);
        contract.* = try terminalContractFromValue(self, self.memo_arena.allocator(), terminal);
        const deps = try self.arena.allocator().alloc(ScopedNodeKey, frame.deps.items.len);
        const versions = try self.arena.allocator().alloc(u32, frame.deps.items.len);
        @memcpy(deps, frame.deps.items);
        for (frame.deps.items, 0..) |dep, index| versions[index] = self.stateVersion(dep);
        self.dropCachedTerminalContract();
        self.cached_terminal_contract_deps = deps;
        self.cached_terminal_contract_versions = versions;
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
        const event = try self.controlRefByLabel(allocator, .click, label);
        const scope = canonicalControlScope(event.scope);
        try self.logf("external click label {s} -> n{d}", .{ label, event.link });
        try self.enqueueExternalNodePulse(event.link, scope, "press");
    }

    pub fn doubleClickLabelByText(self: *Session, allocator: std.mem.Allocator, label: []const u8) !void {
        return self.doubleClickLabel(try self.controlIndexByLabel(allocator, .double_click, label));
    }

    pub fn setHoverByLabel(self: *Session, allocator: std.mem.Allocator, label: []const u8, hovered: bool) !void {
        const event = try self.controlRefByLabel(allocator, .hover, label);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, booleanValue(hovered));
        try self.logf("external hover label {s} -> n{d} = {s}", .{ label, event.link, if (hovered) "True" else "False" });
        try self.enqueueExternalNodePulse(event.link, scope, "hovered");
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
        return (try self.cachedControlRefs(.text_input)).len;
    }

    pub fn textInputTextAlloc(self: *Session, allocator: std.mem.Allocator, index: usize) ![]u8 {
        const value = try self.currentTextInputValue(index);
        return try allocator.dupe(u8, try valueAsText(value));
    }

    pub fn textInputTextView(self: *Session, index: usize) ![]const u8 {
        const value = try self.currentTextInputValue(index);
        return try valueAsText(value);
    }

    pub fn clickButton(self: *Session, index: usize) !void {
        const event = try self.buttonLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.logf("external click button[{d}] -> n{d}", .{ index, event.link });
        try self.enqueueExternalNodePulse(event.link, scope, null);
    }

    pub fn clickCheckbox(self: *Session, index: usize) !void {
        const event = try self.checkboxLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.logf("external click checkbox[{d}] -> n{d}", .{ index, event.link });
        try self.enqueueExternalNodePulse(event.link, scope, "click");
    }

    pub fn clickButtonAt(self: *Session, index: usize, x: usize, y: usize) !void {
        const event = try self.buttonLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        const payload = try allocRecordValue(self.arena.allocator(), &.{
            .{ .name = "x", .value = .{ .number = @floatFromInt(x) } },
            .{ .name = "y", .value = .{ .number = @floatFromInt(y) } },
        });
        try self.setLinkValue(event.link, scope, payload);
        try self.logf("external click button[{d}] -> n{d} at {d},{d}", .{ index, event.link, x, y });
        try self.enqueueExternalNodePulse(event.link, scope, null);
    }

    pub fn setSliderValue(self: *Session, index: usize, value: f64) !void {
        const event = try self.sliderLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, .{ .number = value });
        try self.logf("external slider[{d}] -> n{d} = {d}", .{ index, event.link, value });
        try self.enqueueExternalNodePulse(event.link, scope, "change");
    }

    pub fn setTextInputValue(self: *Session, index: usize, text: []const u8) !void {
        const event = try self.textInputLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, try self.textInputChangePayload(text));
        try self.setLinkKeyValue(event.link, scope, .none);
        try self.logf("external text_input[{d}] -> n{d} = {s}", .{ index, event.link, text });
        try self.enqueueExternalNodePulse(event.link, scope, "change");
    }

    pub fn setTextInputValueRef(self: *Session, event: ControlEventRef, text: []const u8) !void {
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, try self.textInputChangePayload(text));
        try self.setLinkKeyValue(event.link, scope, .none);
        try self.logf("external text_input -> n{d} = {s}", .{ event.link, text });
        try self.enqueueExternalNodePulse(event.link, scope, "change");
    }

    fn textInputChangePayload(self: *Session, text: []const u8) !Value {
        const owned = try self.arena.allocator().dupe(u8, text);
        return try allocRecordValue(self.arena.allocator(), &.{
            .{ .name = "text", .value = .{ .text = owned } },
            .{ .name = "value", .value = .{ .text = owned } },
        });
    }

    pub fn setSelectValue(self: *Session, index: usize, text: []const u8) !void {
        const event = try self.selectLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, .{ .text = try self.arena.allocator().dupe(u8, text) });
        try self.logf("external select[{d}] -> n{d} = {s}", .{ index, event.link, text });
        try self.enqueueExternalNodePulse(event.link, scope, "change");
    }

    pub fn pressTextInputKey(self: *Session, index: usize, key: []const u8) !void {
        const event = try self.textInputKeyLinkAt(index);
        const change_event = try self.textInputLinkAt(index);
        const change_scope = canonicalControlScope(change_event.scope);
        const current_text = self.getLinkValue(change_event.link, change_scope) orelse try self.currentTextInputValue(index);
        try self.pressTextInputKeyRef(event, change_event, key, try valueAsText(current_text));
        try self.logf("external text_input_key[{d}] -> n{d} = {s}", .{ index, event.link, key });
    }

    pub fn pressTextInputKeyWithText(self: *Session, index: usize, key: []const u8, current_text: []const u8) !void {
        const event = try self.textInputKeyLinkAt(index);
        const change_event = try self.textInputLinkAt(index);
        try self.pressTextInputKeyRef(event, change_event, key, current_text);
        try self.logf("external text_input_key[{d}] text = {s}", .{ index, current_text });
    }

    pub fn pressTextInputKeyRef(self: *Session, event: ControlEventRef, change_event: ControlEventRef, key: []const u8, current_text: []const u8) !void {
        const scope = canonicalControlScope(event.scope);
        const change_scope = canonicalControlScope(change_event.scope);
        try self.setLinkValue(change_event.link, change_scope, .{ .text = try self.arena.allocator().dupe(u8, current_text) });
        if (std.mem.eql(u8, key, "Backspace")) {
            try self.queue.append(self.arena.allocator(), .{
                .source = change_event.link,
                .payload = .{ .value = .{ .text = try self.arena.allocator().dupe(u8, current_text) } },
                .scope = change_scope,
                .event_name = "change",
            });
        }
        const event_fields = try self.arena.allocator().alloc(RecordField, 3);
        event_fields[0] = .{ .name = "text", .value = .{ .text = try self.arena.allocator().dupe(u8, current_text) } };
        event_fields[1] = .{ .name = "value", .value = .{ .text = try self.arena.allocator().dupe(u8, current_text) } };
        event_fields[2] = .{ .name = "key", .value = .{ .symbol = try self.arena.allocator().dupe(u8, key) } };
        if (!sameScopedLink(event.link, scope, change_event.link, change_scope)) {
            try self.setLinkValue(event.link, scope, .{ .record = event_fields });
        }
        try self.setLinkKeyValue(event.link, scope, .{ .symbol = try self.arena.allocator().dupe(u8, key) });
        try self.logf("external text_input_key -> n{d} = {s}", .{ event.link, key });
        try self.enqueueExternalNodePulse(event.link, scope, "key_down");
    }

    pub fn focusTextInput(self: *Session, index: usize) !void {
        const event = self.textInputFocusLinkAt(index) catch |err| switch (err) {
            error.InvalidTextInputIndex => return,
            else => return err,
        };
        const scope = canonicalControlScope(event.scope);
        try self.logf("external text_input_focus[{d}] -> n{d}", .{ index, event.link });
        try self.enqueueExternalNodePulse(event.link, scope, "focus");
    }

    pub fn focusTextInputRef(self: *Session, event: ControlEventRef) !void {
        const scope = canonicalControlScope(event.scope);
        try self.logf("external text_input_focus -> n{d}", .{event.link});
        try self.enqueueExternalNodePulse(event.link, scope, "focus");
    }

    pub fn blurTextInput(self: *Session, index: usize) !void {
        const event = self.textInputBlurLinkAt(index) catch |err| switch (err) {
            error.InvalidTextInputIndex => return,
            else => return err,
        };
        const scope = canonicalControlScope(event.scope);
        try self.logf("external text_input_blur[{d}] -> n{d}", .{ index, event.link });
        try self.enqueueExternalNodePulse(event.link, scope, "blur");
    }

    pub fn blurTextInputRef(self: *Session, event: ControlEventRef) !void {
        const scope = canonicalControlScope(event.scope);
        try self.logf("external text_input_blur -> n{d}", .{event.link});
        try self.enqueueExternalNodePulse(event.link, scope, "blur");
    }

    pub fn textInputSessionRef(self: *Session, index: usize) !TextInputSessionRef {
        return .{
            .change = try self.textInputLinkAt(index),
            .key = try self.textInputKeyLinkAt(index),
            .blur = self.textInputBlurLinkAt(index) catch null,
            .focus = self.textInputFocusLinkAt(index) catch null,
        };
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
        try self.enqueueExternalNodePulse(event.link, scope, "double_click");
    }

    pub fn setHover(self: *Session, index: usize, hovered: bool) !void {
        const event = try self.hoverLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        try self.setLinkValue(event.link, scope, booleanValue(hovered));
        try self.logf("external hover[{d}] -> n{d} = {s}", .{ index, event.link, if (hovered) "True" else "False" });
        try self.enqueueExternalNodePulse(event.link, scope, "hovered");
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

    fn enqueueExternalNodePulse(self: *Session, source: flow_ir.NodeId, scope: ?*const EvalScope, event_name: ?[]const u8) !void {
        try self.queue.append(self.arena.allocator(), .{
            .source = source,
            .payload = .{ .node = source },
            .scope = scope,
            .event_name = event_name,
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
        self.runtime_subscriber_nodes = &.{};
        self.runtime_scopes.deinit(allocator);
        self.runtime_scopes = .empty;

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

        self.skip_limits = try allocator.alloc(u64, node_count);
        @memset(self.skip_limits, 0);

        self.skip_limit_inited = try allocator.alloc(bool, node_count);
        @memset(self.skip_limit_inited, false);

        self.sum_values = try allocator.alloc(f64, node_count);
        @memset(self.sum_values, 0);

        self.sum_inited = try allocator.alloc(bool, node_count);
        @memset(self.sum_inited, false);

        self.timer_period_ms = try allocator.alloc(u64, node_count);
        @memset(self.timer_period_ms, 0);

        self.timer_next_fire_ms = try allocator.alloc(u64, node_count);
        @memset(self.timer_next_fire_ms, 0);

        self.state_versions = try allocator.alloc(u32, node_count);
        @memset(self.state_versions, 0);

        self.top_level_eval_values = try allocator.alloc(Value, node_count);
        for (self.top_level_eval_values) |*slot| slot.* = .none;

        self.top_level_eval_inited = try allocator.alloc(bool, node_count);
        @memset(self.top_level_eval_inited, false);

        self.top_level_eval_deps = try allocator.alloc([]CachedDependency, node_count);
        for (self.top_level_eval_deps) |*slot| slot.* = &.{};

        self.top_level_owned_nodes = try allocator.alloc(bool, node_count);
        @memset(self.top_level_owned_nodes, false);
        const top_level_visiting = try allocator.alloc(bool, node_count);
        @memset(top_level_visiting, false);
        for (self.flow.bindings) |binding| self.markTopLevelOwnedNode(binding.node, top_level_visiting);

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

        if (self.state_file_path != null) {
            try self.computePersistIds();
            try self.loadPersistedState();
        }

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
                    switch (self.builtinOp(index)) {
                        .stream_pulses => {
                            if (!self.nodeNeedsScope(index)) {
                                try self.emitPulses(index, call, null);
                            } else {
                                try self.logf("defer scoped pulses n{d}", .{index});
                            }
                        },
                        .stream_skip => {
                            self.initSkipNode(allocator, index, call, null) catch |err| switch (err) {
                                error.MissingLocalBinding,
                                error.MissingRecordField,
                                error.ExpectedRecordNode,
                                error.UnsupportedFieldAccess,
                                => try self.logf("defer scoped skip n{d}", .{index}),
                                else => return err,
                            };
                        },
                        .list_append => {
                            if (!self.nodeNeedsRuntimeScope(index)) try self.initListAppendNode(allocator, index, call);
                        },
                        .list_clear => {
                            if (!self.nodeNeedsRuntimeScope(index)) try self.initListClearNode(allocator, index, call);
                        },
                        .list_remove => try self.initListRemoveNode(allocator, index, call),
                        .list_remove_last => try self.initListRemoveLastNode(allocator, index, call),
                        .timer_interval => {
                            if (!self.nodeNeedsScope(index)) {
                                const period_ms = try self.durationMsFromCall(call, null);
                                self.timer_period_ms[index] = period_ms;
                                self.timer_next_fire_ms[index] = period_ms;
                                try self.logf("init timer n{d} every {d}ms", .{ index, period_ms });
                            } else {
                                try self.logf("defer scoped timer n{d}", .{index});
                            }
                        },
                        .math_sum => if (call.positional.len != 0) {
                            if (self.sum_inited[index]) {
                                try self.logf("restore sum n{d} = {d}", .{ index, self.sum_values[index] });
                            } else if (try self.initialNumericValue(call.positional[0])) |value| {
                                self.sum_values[index] = value;
                                self.sum_inited[index] = true;
                                self.noteTopLevelMutation(index);
                                try self.logf("init sum n{d} = {d}", .{ index, value });
                            } else {
                                try self.logf("init sum n{d} = <empty>", .{index});
                            }
                        },
                        .router_go_to => try self.logf("init router route={s}", .{try valueAsText(self.route_value)}),
                        else => {},
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
                    if (latest.initial) |initial_node| {
                        if (self.nodeNeedsScope(initial_node)) {
                            self.runtime_subscribers[subscriber] = true;
                        } else {
                            const source = self.eventDependencySource(initial_node) catch |err| switch (err) {
                                error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) continue else return err,
                                else => return err,
                            };
                            if (source != initial_node or self.flow.nodes[source].kind == .link_port) counts[source] += 1;
                        }
                    }
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
                        if (self.nodeNeedsRuntimeScope(update)) {
                            self.runtime_subscribers[subscriber] = true;
                            continue;
                        }
                        const source = self.holdTriggerSource(update) catch |err| switch (err) {
                            error.UnsupportedEventSource => {
                                if (self.nodeNeedsScope(update)) {
                                    self.runtime_subscribers[subscriber] = true;
                                    continue;
                                }
                                if (self.nodeNeedsScope(subscriber)) continue else return err;
                            },
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
                    switch (self.builtinOp(subscriber)) {
                        .stream_pulses, .stream_skip, .math_sum => if (call.positional.len != 0) {
                            if (self.streamSourceNeedsRuntimeScope(call.positional[0])) {
                                self.runtime_subscribers[subscriber] = true;
                                continue;
                            }
                            const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                                error.UnsupportedEventSource => {
                                    if (self.nodeNeedsScope(call.positional[0])) {
                                        self.runtime_subscribers[subscriber] = true;
                                        continue;
                                    }
                                    if (self.nodeNeedsScope(subscriber)) continue else return err;
                                },
                                else => return err,
                            };
                            counts[source] += 1;
                        },
                        .list_append => {
                            if (call.positional.len != 0) {
                                if (self.nodeNeedsRuntimeScope(call.positional[0])) {
                                    self.runtime_subscribers[subscriber] = true;
                                } else {
                                    counts[try self.listSourceDependency(call.positional[0])] += 1;
                                }
                            }
                            if (findNamed(call.named, "item")) |item_node| {
                                if (self.nodeNeedsRuntimeScope(item_node)) {
                                    self.runtime_subscribers[subscriber] = true;
                                } else {
                                    counts[try self.valueTriggerSource(item_node)] += 1;
                                }
                            } else if (findNamed(call.named, "on")) |on_node| {
                                if (self.nodeNeedsRuntimeScope(on_node)) {
                                    self.runtime_subscribers[subscriber] = true;
                                } else {
                                    counts[try self.valueTriggerSource(on_node)] += 1;
                                }
                            } else {
                                return error.MissingArgument;
                            }
                        },
                        .list_clear => {
                            if (call.positional.len != 0) {
                                if (self.nodeNeedsRuntimeScope(call.positional[0])) {
                                    self.runtime_subscribers[subscriber] = true;
                                } else {
                                    counts[try self.listSourceDependency(call.positional[0])] += 1;
                                }
                            }
                            const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                            if (self.nodeNeedsRuntimeScope(on_node)) {
                                self.runtime_subscribers[subscriber] = true;
                            } else {
                                counts[try self.valueTriggerSource(on_node)] += 1;
                            }
                        },
                        .list_remove_last => {
                            if (call.positional.len != 0) counts[try self.listSourceDependency(call.positional[0])] += 1;
                            const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                            if (self.nodeNeedsScope(on_node)) {
                                self.runtime_subscribers[subscriber] = true;
                            } else {
                                counts[try self.valueTriggerSource(on_node)] += 1;
                            }
                        },
                        .router_go_to => if (call.positional.len != 0) {
                            if (self.nodeNeedsRuntimeScope(call.positional[0])) {
                                self.runtime_subscribers[subscriber] = true;
                            } else {
                                counts[try self.eventDependencySource(call.positional[0])] += 1;
                            }
                        },
                        else => {},
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
                    if (latest.initial) |initial_node| {
                        if (!self.nodeNeedsScope(initial_node)) {
                            const source = self.eventDependencySource(initial_node) catch |err| switch (err) {
                                error.UnsupportedEventSource => if (self.nodeNeedsScope(subscriber)) null else return err,
                                else => return err,
                            };
                            if (source) |resolved| {
                                if (resolved != initial_node or self.flow.nodes[resolved].kind == .link_port) {
                                    try self.addSubscriber(resolved, subscriber, filled);
                                }
                            }
                        }
                    }
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
                        if (self.nodeNeedsRuntimeScope(update)) continue;
                        const source = self.holdTriggerSource(update) catch |err| switch (err) {
                            error.UnsupportedEventSource => if (self.nodeNeedsScope(update) or self.nodeNeedsScope(subscriber)) continue else return err,
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
                    switch (self.builtinOp(subscriber)) {
                        .stream_pulses, .stream_skip, .math_sum => if (call.positional.len != 0) {
                            if (self.streamSourceNeedsRuntimeScope(call.positional[0])) continue;
                            const source = self.eventDependencySource(call.positional[0]) catch |err| switch (err) {
                                error.UnsupportedEventSource => if (self.nodeNeedsScope(call.positional[0]) or self.nodeNeedsScope(subscriber)) continue else return err,
                                else => return err,
                            };
                            try self.addSubscriber(source, subscriber, filled);
                        },
                        .list_append => {
                            if (call.positional.len != 0 and !self.nodeNeedsRuntimeScope(call.positional[0])) {
                                try self.addSubscriber(try self.listSourceDependency(call.positional[0]), subscriber, filled);
                            }
                            if (findNamed(call.named, "item")) |item_node| {
                                if (!self.nodeNeedsRuntimeScope(item_node)) {
                                    try self.addSubscriber(try self.valueTriggerSource(item_node), subscriber, filled);
                                }
                            } else if (findNamed(call.named, "on")) |on_node| {
                                if (!self.nodeNeedsRuntimeScope(on_node)) {
                                    try self.addSubscriber(try self.valueTriggerSource(on_node), subscriber, filled);
                                }
                            } else {
                                return error.MissingArgument;
                            }
                        },
                        .list_clear => {
                            if (call.positional.len != 0 and !self.nodeNeedsRuntimeScope(call.positional[0])) {
                                try self.addSubscriber(try self.listSourceDependency(call.positional[0]), subscriber, filled);
                            }
                            const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                            if (!self.nodeNeedsRuntimeScope(on_node)) {
                                try self.addSubscriber(try self.valueTriggerSource(on_node), subscriber, filled);
                            }
                        },
                        .list_remove_last => {
                            if (call.positional.len != 0) try self.addSubscriber(try self.listSourceDependency(call.positional[0]), subscriber, filled);
                            const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
                            if (!self.nodeNeedsScope(on_node)) {
                                try self.addSubscriber(try self.valueTriggerSource(on_node), subscriber, filled);
                            }
                        },
                        .router_go_to => if (call.positional.len != 0) {
                            if (!self.nodeNeedsRuntimeScope(call.positional[0])) {
                                try self.addSubscriber(try self.eventDependencySource(call.positional[0]), subscriber, filled);
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        var runtime_nodes: std.ArrayList(flow_ir.NodeId) = .empty;
        defer runtime_nodes.deinit(allocator);
        for (self.runtime_subscribers, 0..) |enabled, subscriber_usize| {
            if (!enabled) continue;
            try runtime_nodes.append(allocator, @intCast(subscriber_usize));
        }
        self.runtime_subscriber_nodes = try runtime_nodes.toOwnedSlice(allocator);
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

    fn streamSourceNeedsRuntimeScope(self: *Session, node_id: flow_ir.NodeId) bool {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| self.streamSourceNeedsRuntimeScope(self.flow.bindings[binding_id].node),
            .hold => |hold| self.holdNeedsRuntimeScope(node_id, hold),
            else => self.nodeNeedsScope(node_id),
        };
    }

    fn nodeNeedsScope(self: *Session, node_id: flow_ir.NodeId) bool {
        return self.node_needs_scope[node_id];
    }

    fn nodeNeedsDeferredField(self: *Session, node_id: flow_ir.NodeId) bool {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| self.nodeNeedsDeferredField(self.flow.bindings[binding_id].node),
            .latest, .hold, .then_value, .linked_value => true,
            .builtin_call => self.node_needs_deferred_field[node_id],
            else => false,
        };
    }

    fn eventDependencySource(self: *Session, node_id: flow_ir.NodeId) !flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.eventDependencySource(self.flow.bindings[binding_id].node),
            .when => |when| try self.eventDependencySource(when.input),
            .block => |block| try self.eventDependencySource(block.result),
            .access => |access| try self.resolveAccessEventSource(node_id, access),
            .builtin_call => |call| switch (self.builtinOp(node_id)) {
                .list_latest => if (call.positional.len != 0) try self.eventDependencySource(call.positional[0]) else node_id,
                .list_map => if (findNamed(call.named, "new")) |mapper| mapper else node_id,
                else => node_id,
            },
            .binary => |binary| blk: {
                const lhs = try self.eventDependencySource(binary.lhs);
                if (lhs != binary.lhs or self.flow.nodes[lhs].kind == .link_port) break :blk lhs;
                break :blk try self.eventDependencySource(binary.rhs);
            },
            else => node_id,
        };
    }

    fn resolveAccessEventSource(self: *Session, node_id: flow_ir.NodeId, access: flow_ir.Access) !flow_ir.NodeId {
        if (std.mem.eql(u8, access.field, "press")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "press", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "change")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "change", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "click", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "double_click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "double_click", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "key_down")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "key_down", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "blur")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "blur", null)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "focus")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "focus", null)) |link| return link;
            }
        }
        if (try self.resolveStaticLinkNode(node_id)) |link| return link;
        if (try self.resolveStaticLinkNode(access.target)) |link| return link;
        if (std.mem.eql(u8, access.field, "value")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveEventSourceLink(event_target.kind.access.target, "change", null)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "text")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveEventSourceLink(event_target.kind.access.target, "change", null)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "key")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "key_down")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveEventSourceLink(event_target.kind.access.target, "key_down", null)) |link| return link;
                }
            }
        }
        return node_id;
    }

    fn pulseEventNameMatches(expected: ?[]const u8, pulse: Pulse) bool {
        const actual = pulse.event_name orelse return true;
        const wanted = expected orelse return true;
        return std.mem.eql(u8, wanted, actual);
    }

    fn pulseMatchesTriggerEvent(self: *Session, trigger_node: flow_ir.NodeId, pulse: Pulse) bool {
        return pulseEventNameMatches(self.eventDependencyName(trigger_node), pulse);
    }

    fn pulseMatchesTriggerEventForSource(self: *Session, trigger_node: flow_ir.NodeId, source: flow_ir.NodeId, pulse: Pulse) bool {
        const expected = self.triggerEventNameForSource(trigger_node, source) catch null;
        return pulseEventNameMatches(expected, pulse);
    }

    fn triggerEventNameForSource(self: *Session, node_id: flow_ir.NodeId, source: flow_ir.NodeId) anyerror!?[]const u8 {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.triggerEventNameForSource(self.flow.bindings[binding_id].node, source),
            .then_value => |then_value| blk: {
                const trigger_source = self.eventDependencySource(then_value.source) catch break :blk null;
                break :blk if (trigger_source == source) self.eventDependencyName(then_value.source) else null;
            },
            .when => |when| blk: {
                const trigger_source = self.eventDependencySource(when.input) catch break :blk null;
                break :blk if (trigger_source == source) self.eventDependencyName(when.input) else null;
            },
            .block => |block| try self.triggerEventNameForSource(block.result, source),
            .latest => |latest| blk: {
                for (latest.sources) |source_node| {
                    if (try self.triggerEventNameForSource(source_node, source)) |name| break :blk name;
                }
                break :blk null;
            },
            .hold => null,
            .builtin_call => |call| switch (self.builtinOp(node_id)) {
                .stream_pulses, .stream_skip, .math_sum, .router_go_to => if (call.positional.len != 0)
                    try self.triggerEventNameForSource(call.positional[0], source)
                else
                    null,
                .list_append => blk: {
                    if (call.positional.len != 0) {
                        const base_source = self.listSourceDependency(call.positional[0]) catch null;
                        if (base_source == source) break :blk null;
                    }
                    if (findNamed(call.named, "item")) |item_node| {
                        const item_source = self.valueTriggerSource(item_node) catch break :blk null;
                        if (item_source == source) break :blk self.eventDependencyName(item_node);
                    } else if (findNamed(call.named, "on")) |on_node| {
                        const on_source = self.valueTriggerSource(on_node) catch break :blk null;
                        if (on_source == source) break :blk self.eventDependencyName(on_node);
                    }
                    break :blk null;
                },
                .list_clear, .list_remove_last => blk: {
                    if (call.positional.len != 0) {
                        const base_source = self.listSourceDependency(call.positional[0]) catch null;
                        if (base_source == source) break :blk null;
                    }
                    const on_node = findNamed(call.named, "on") orelse break :blk null;
                    const on_source = self.valueTriggerSource(on_node) catch break :blk null;
                    break :blk if (on_source == source) self.eventDependencyName(on_node) else null;
                },
                else => blk: {
                    const trigger_source = self.eventDependencySource(node_id) catch break :blk null;
                    break :blk if (trigger_source == source) self.eventDependencyName(node_id) else null;
                },
            },
            else => blk: {
                const trigger_source = self.eventDependencySource(node_id) catch break :blk null;
                break :blk if (trigger_source == source) self.eventDependencyName(node_id) else null;
            },
        };
    }

    fn eventDependencyName(self: *Session, node_id: flow_ir.NodeId) ?[]const u8 {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| self.eventDependencyName(self.flow.bindings[binding_id].node),
            .access => |access| blk: {
                if (isEventField(access.field)) break :blk access.field;
                if (std.mem.eql(u8, access.field, "value") or std.mem.eql(u8, access.field, "text")) {
                    const target = self.flow.nodes[access.target];
                    if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) break :blk "change";
                }
                if (std.mem.eql(u8, access.field, "key")) {
                    const target = self.flow.nodes[access.target];
                    if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "key_down")) break :blk "key_down";
                }
                break :blk self.eventDependencyName(access.target);
            },
            .then_value => |then_value| self.eventDependencyName(then_value.source),
            .when => |when| self.eventDependencyName(when.input),
            .block => |block| self.eventDependencyName(block.result),
            .binary => |binary| self.eventDependencyName(binary.lhs) orelse self.eventDependencyName(binary.rhs),
            .text => |parts| blk: {
                for (parts) |part| {
                    if (self.eventDependencyName(part)) |name| break :blk name;
                }
                break :blk null;
            },
            .record => |fields| blk: {
                for (fields) |field| {
                    if (self.eventDependencyName(field.value)) |name| break :blk name;
                }
                break :blk null;
            },
            .list => |list| blk: {
                for (list.items) |item| {
                    if (self.eventDependencyName(item)) |name| break :blk name;
                }
                break :blk null;
            },
            .builtin_call => |call| switch (self.builtinOp(node_id)) {
                .stream_pulses, .stream_skip, .math_sum, .router_go_to => if (call.positional.len != 0)
                    self.eventDependencyName(call.positional[0])
                else
                    null,
                else => blk: {
                    for (call.positional) |arg| {
                        if (self.eventDependencyName(arg)) |name| break :blk name;
                    }
                    for (call.named) |arg| {
                        if (self.eventDependencyName(arg.value)) |name| break :blk name;
                    }
                    break :blk null;
                },
            },
            .user_call => |call| blk: {
                for (call.positional) |arg| {
                    if (self.eventDependencyName(arg)) |name| break :blk name;
                }
                for (call.named) |arg| {
                    if (self.eventDependencyName(arg.value)) |name| break :blk name;
                }
                if (call.pass_context) |pass_context| {
                    if (self.eventDependencyName(pass_context)) |name| break :blk name;
                }
                break :blk null;
            },
            else => null,
        };
    }

    fn isEventField(field: []const u8) bool {
        return std.mem.eql(u8, field, "press") or
            std.mem.eql(u8, field, "click") or
            std.mem.eql(u8, field, "double_click") or
            std.mem.eql(u8, field, "change") or
            std.mem.eql(u8, field, "key_down") or
            std.mem.eql(u8, field, "blur") or
            std.mem.eql(u8, field, "focus") or
            std.mem.eql(u8, field, "hovered");
    }

    fn triggerScopedEventNameForSource(self: *Session, node_id: flow_ir.NodeId, source: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!?[]const u8 {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.triggerScopedEventNameForSource(self.flow.bindings[binding_id].node, source, scope),
            .then_value => |then_value| blk: {
                const trigger_source = self.scopedEventDependencySource(then_value.source, scope) catch break :blk null;
                break :blk if (trigger_source == source) self.eventDependencyName(then_value.source) else null;
            },
            .when => |when| blk: {
                const trigger_source = self.scopedEventDependencySource(when.input, scope) catch break :blk null;
                break :blk if (trigger_source == source) self.eventDependencyName(when.input) else null;
            },
            .block => |block| try self.triggerScopedEventNameForSource(block.result, source, scope),
            .latest => |latest| blk: {
                for (latest.sources) |source_node| {
                    if (try self.triggerScopedEventNameForSource(source_node, source, scope)) |name| break :blk name;
                }
                break :blk null;
            },
            .hold => null,
            .builtin_call => |call| switch (self.builtinOp(node_id)) {
                .stream_pulses, .stream_skip, .math_sum, .router_go_to => if (call.positional.len != 0)
                    try self.triggerScopedEventNameForSource(call.positional[0], source, scope)
                else
                    null,
                else => blk: {
                    const trigger_source = self.scopedEventDependencySource(node_id, scope) catch break :blk null;
                    break :blk if (trigger_source == source) self.eventDependencyName(node_id) else null;
                },
            },
            else => blk: {
                const trigger_source = self.scopedEventDependencySource(node_id, scope) catch break :blk null;
                break :blk if (trigger_source == source) self.eventDependencyName(node_id) else null;
            },
        };
    }

    fn scopedEventDependencySource(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.scopedEventDependencySource(self.flow.bindings[binding_id].node, scope),
            .when => |when| try self.scopedEventDependencySource(when.input, scope),
            .block => |block| try self.scopedEventDependencySource(block.result, scope),
            .access => |access| try self.resolveScopedAccessEventSource(node_id, access, scope),
            .builtin_call => |call| switch (self.builtinOp(node_id)) {
                .list_latest => if (call.positional.len != 0) try self.scopedEventDependencySource(call.positional[0], scope) else node_id,
                .list_map => if (findNamed(call.named, "new")) |mapper| mapper else node_id,
                else => node_id,
            },
            .binary => |binary| blk: {
                const lhs = try self.scopedEventDependencySource(binary.lhs, scope);
                if (lhs != binary.lhs or self.flow.nodes[lhs].kind == .link_port) break :blk lhs;
                break :blk try self.scopedEventDependencySource(binary.rhs, scope);
            },
            else => node_id,
        };
    }

    fn resolveScopedAccessEventSource(self: *Session, node_id: flow_ir.NodeId, access: flow_ir.Access, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        if (std.mem.eql(u8, access.field, "press")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "press", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "change")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "change", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "click", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "double_click")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "double_click", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "key_down")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "key_down", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "blur")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "blur", scope)) |link| return link;
            }
        }
        if (std.mem.eql(u8, access.field, "focus")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                if (try self.resolveEventSourceLink(target.kind.access.target, "focus", scope)) |link| return link;
            }
        }
        if (try self.resolveScopedLinkNode(node_id, scope)) |link| return link;
        if (try self.resolveScopedLinkNode(access.target, scope)) |link| return link;
        if (std.mem.eql(u8, access.field, "value")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveEventSourceLink(event_target.kind.access.target, "change", scope)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "text")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "change")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveEventSourceLink(event_target.kind.access.target, "change", scope)) |link| return link;
                }
            }
        }
        if (std.mem.eql(u8, access.field, "key")) {
            const target = self.flow.nodes[access.target];
            if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "key_down")) {
                const event_target = self.flow.nodes[target.kind.access.target];
                if (event_target.kind == .access and std.mem.eql(u8, event_target.kind.access.field, "event")) {
                    if (try self.resolveEventSourceLink(event_target.kind.access.target, "key_down", scope)) |link| return link;
                }
            }
        }
        return node_id;
    }

    fn resolveEventSourceLink(self: *Session, node_id: flow_ir.NodeId, event_name: []const u8, scope: ?*const EvalScope) anyerror!?flow_ir.NodeId {
        if (scope != null) {
            if (try self.resolveScopedLinkNode(node_id, scope)) |link| return link;
        }
        if (try self.resolveStaticLinkNode(node_id)) |link| return link;
        return try self.resolveElementEventLink(node_id, event_name, scope);
    }

    fn resolveElementEventLink(self: *Session, node_id: flow_ir.NodeId, event_name: []const u8, scope: ?*const EvalScope) anyerror!?flow_ir.NodeId {
        const value = try self.evalNode(self.arena.allocator(), node_id, scope);
        return try self.eventLinkFromResolvedValue(self.arena.allocator(), value, event_name);
    }

    fn eventScopeForSource(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!?*const EvalScope {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.eventScopeForSource(self.flow.bindings[binding_id].node, scope),
            .then_value => |then_value| try self.eventScopeForSource(then_value.source, scope),
            .block => |block| try self.eventScopeForSource(block.result, scope),
            .access => |access| blk: {
                if (isEventAccessField(access.field)) {
                    const target = self.flow.nodes[access.target];
                    if (target.kind == .access and std.mem.eql(u8, target.kind.access.field, "event")) {
                        const value = try self.evalNode(self.arena.allocator(), target.kind.access.target, scope);
                        break :blk eventScopeFromValue(value);
                    }
                }
                break :blk null;
            },
            else => null,
        };
    }

    fn isEventAccessField(field: []const u8) bool {
        return std.mem.eql(u8, field, "press") or
            std.mem.eql(u8, field, "change") or
            std.mem.eql(u8, field, "click") or
            std.mem.eql(u8, field, "double_click") or
            std.mem.eql(u8, field, "key_down") or
            std.mem.eql(u8, field, "blur") or
            std.mem.eql(u8, field, "focus") or
            std.mem.eql(u8, field, "hovered");
    }

    fn eventScopeFromValue(value: Value) ?*const EvalScope {
        return switch (value) {
            .stripe => |stripe| stripe.event_scope,
            .label => |label| label.event_scope,
            .container => |container| container.event_scope,
            .checkbox => |checkbox| checkbox.event_scope,
            .button => |button| button.event_scope,
            .text_input => |input| input.event_scope,
            .select => |select| select.event_scope,
            .slider => |slider| slider.event_scope,
            .scoped_link => |scoped| scoped.scope,
            else => null,
        };
    }

    fn eventLinkFromResolvedValue(self: *Session, allocator: std.mem.Allocator, value: Value, event_name: []const u8) anyerror!?flow_ir.NodeId {
        return switch (value) {
            .link => |link| link,
            .scoped_link => |scoped| scoped.link,
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
                input.blur_link
            else if (std.mem.eql(u8, event_name, "focus"))
                input.focus_link
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
            .scoped_link => |scoped| scoped.link,
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
            .builtin_call => switch (self.builtinOp(node_id)) {
                .list_append, .list_clear, .list_remove, .list_remove_last => node_id,
                else => try self.eventDependencySource(node_id),
            },
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
            .access => |access| blk: {
                if (try self.resolveStaticFieldNode(access.target, access.field)) |field_node| {
                    break :blk try self.valueTriggerSource(field_node);
                }
                break :blk try self.eventDependencySource(node_id);
            },
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
            .access => |access| blk: {
                if (try self.resolveStaticFieldNode(access.target, access.field)) |field_node| {
                    break :blk try self.valueTriggerSourceScoped(field_node, scope);
                }
                break :blk try self.scopedEventDependencySource(node_id, scope);
            },
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
            .scoped_link => |scoped| scoped.link,
            .binding_ref => |binding_id| try self.resolveScopedLinkNode(self.flow.bindings[binding_id].node, scope),
            else => null,
        };
    }

    fn resolveLinkedTargetRef(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!ScopedLinkValue {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .link_port => .{ .link = node_id, .scope = try captureControlScope(allocator, scope) },
            .binding_ref => |binding_id| try self.resolveLinkedTargetRef(allocator, self.flow.bindings[binding_id].node, null),
            .local_ref => |name| if (lookupLocal(scope, name)) |value|
                try self.resolveLinkedTargetValueRef(allocator, value)
            else
                error.MissingLocalBinding,
            .linked_value => |linked| try self.resolveLinkedTargetRef(allocator, linked.target, scope),
            .access => |access| blk: {
                const target_value = switch (self.flow.nodes[access.target].kind) {
                    .symbol => |text| lookupLocal(scope, text) orelse try self.evalNode(allocator, access.target, scope),
                    else => try self.evalNode(allocator, access.target, scope),
                };
                if (try self.resolveLinkedTargetFieldRef(allocator, target_value, access.field)) |ref| break :blk ref;
                const field_node = try self.resolveStaticFieldNode(access.target, access.field) orelse return error.ExpectedLinkNode;
                break :blk try self.resolveLinkedTargetRef(allocator, field_node, scope);
            },
            else => try self.resolveLinkedTargetValueRef(allocator, try self.evalNode(allocator, node_id, scope)),
        };
    }

    fn resolveLinkedTargetFieldRef(self: *Session, allocator: std.mem.Allocator, value: Value, field_name: []const u8) anyerror!?ScopedLinkValue {
        return switch (value) {
            .record => |fields| if (findRecordValue(fields, field_name)) |field_value|
                try self.resolveLinkedTargetValueRef(allocator, field_value)
            else
                null,
            .binding_ref => |binding_id| blk: {
                const field_node = try self.resolveStaticFieldNode(self.flow.bindings[binding_id].node, field_name) orelse break :blk null;
                break :blk try self.resolveLinkedTargetRef(allocator, field_node, null);
            },
            .scoped_node => |deferred| try self.resolveLinkedTargetFieldRef(
                allocator,
                try self.evalNode(allocator, deferred.node_id, deferred.scope),
                field_name,
            ),
            else => null,
        };
    }

    fn resolveLinkedTargetValueRef(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror!ScopedLinkValue {
        return switch (value) {
            .link => |link| .{ .link = link, .scope = null },
            .scoped_link => |scoped| scoped,
            .binding_ref => |binding_id| try self.resolveLinkedTargetRef(allocator, self.flow.bindings[binding_id].node, null),
            .scoped_node => |deferred| try self.resolveLinkedTargetValueRef(
                allocator,
                try self.evalNode(allocator, deferred.node_id, deferred.scope),
            ),
            else => error.ExpectedLinkValue,
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
            for (self.list_remove_nodes) |subscriber| {
                const call = self.flow.nodes[subscriber].kind.builtin_call;
                try self.processListRemovePulse(subscriber, call, pulse);
            }
            for (self.list_remove_last_nodes) |subscriber| {
                const call = self.flow.nodes[subscriber].kind.builtin_call;
                try self.processListRemoveLastPulse(subscriber, call, pulse.source);
            }
        }
        self.queue.clearRetainingCapacity();
        if (had_pulses) {
            self.clearEvalCache();
            try self.savePersistedState();
        }
    }

    fn dispatchPulseToSubscriber(self: *Session, subscriber: flow_ir.NodeId, pulse: Pulse) !void {
        const node = self.flow.nodes[subscriber];
        if (self.nodeNeedsRuntimeScope(subscriber) and pulse.scope == null) switch (node.kind) {
            .then_value => {},
            .builtin_call => switch (self.builtinOp(subscriber)) {
                .router_go_to, .stream_skip => {},
                else => return,
            },
            else => return,
        };
        switch (node.kind) {
            .then_value => |then_value| {
                if (!self.pulseMatchesTriggerEvent(then_value.source, pulse)) return;
                if (pulse.scope) |scope| {
                    const source = self.scopedEventDependencySource(then_value.source, scope) catch |err| switch (err) {
                        error.MissingLocalBinding,
                        error.MissingRecordField,
                        error.ExpectedRecordNode,
                        error.ExpectedLinkNode,
                        error.ExpectedLinkValue,
                        error.UnsupportedFieldAccess,
                        error.UnsupportedEventSource,
                        => return,
                        else => return err,
                    };
                    if (source != pulse.source) return;
                    if (try self.eventScopeForSource(then_value.source, scope)) |expected_scope| {
                        const canonical_expected = canonicalControlScope(expected_scope) orelse expected_scope;
                        const canonical_actual = canonicalControlScope(scope) orelse scope;
                        if (canonical_expected.id != canonical_actual.id) return;
                    }
                }
                const payload: PulsePayload = value_payload: {
                    const value = self.evalNode(self.arena.allocator(), then_value.value, pulse.scope) catch |err| switch (err) {
                        error.MissingLocalBinding => break :value_payload .{ .node = subscriber },
                        else => return err,
                    };
                    if (value == .none) return;
                    break :value_payload .{ .value = value };
                };
                try self.logf("then n{d} -> n{d}", .{ subscriber, then_value.value });
                try self.queue.append(self.arena.allocator(), .{
                    .source = subscriber,
                    .payload = payload,
                    .scope = pulse.scope,
                });
            },
            .latest => |latest| {
                if (!try self.latestPulseMatches(latest, pulse)) return;
                const latest_scope = if (self.nodeNeedsScope(subscriber)) pulse.scope else null;
                const latest_payload = (try self.latestPayloadForPulse(latest, pulse)) orelse return;
                try self.setLatestPayload(subscriber, latest_scope, latest_payload);
                switch (latest_payload) {
                    .node => |payload_node| try self.logf("latest n{d} <- n{d}", .{ subscriber, payload_node }),
                    .value => try self.logf("latest n{d} <- <value>", .{subscriber}),
                }
                try self.queue.append(self.arena.allocator(), .{
                    .source = subscriber,
                    .payload = latest_payload,
                    .scope = latest_scope,
                });
            },
            .hold => |hold| {
                try self.processHoldPulse(subscriber, hold, pulse);
            },
            .linked_value => |linked| {
                const value = switch (self.flow.nodes[linked.value].kind) {
                    .when, .block, .then_value => try self.evalNode(self.arena.allocator(), linked.value, pulse.scope),
                    else => try valueFromPulsePayload(self, self.arena.allocator(), pulse.payload, pulse.scope),
                };
                if (value == .none) return;
                const target_ref = try self.resolveLinkedTargetRef(self.arena.allocator(), linked.target, pulse.scope);
                try self.setLinkValue(target_ref.link, target_ref.scope, value);
                try self.logf("linked n{d} -> n{d}", .{ subscriber, target_ref.link });
                try self.queue.append(self.arena.allocator(), .{
                    .source = target_ref.link,
                    .payload = .{ .value = value },
                    .scope = target_ref.scope,
                });
            },
            .builtin_call => |call| {
                switch (self.builtinOp(subscriber)) {
                    .stream_pulses => {
                        if (call.positional.len != 0 and !self.pulseMatchesTriggerEventForSource(call.positional[0], pulse.source, pulse)) return;
                        try self.emitPulses(subscriber, call, pulse.scope);
                    },
                    .stream_skip => {
                        if (call.positional.len != 0 and !self.pulseMatchesTriggerEventForSource(call.positional[0], pulse.source, pulse)) return;
                        try self.processSkipPulse(subscriber, call, pulse.payload, pulse.scope);
                    },
                    .math_sum => {
                        if (call.positional.len != 0 and !self.pulseMatchesTriggerEventForSource(call.positional[0], pulse.source, pulse)) return;
                        const value = try valueAsNumber(try valueFromPulsePayload(self, self.arena.allocator(), pulse.payload, pulse.scope));
                        if (self.sumSourceIsMultiSourceLatest(call)) {
                            self.sum_values[subscriber] = value;
                        } else {
                            self.sum_values[subscriber] += value;
                        }
                        self.sum_inited[subscriber] = true;
                        self.noteTopLevelMutation(subscriber);
                        try self.logf("sum n{d} <- {d} -> {d}", .{
                            subscriber,
                            value,
                            self.sum_values[subscriber],
                        });
                        try self.queue.append(self.arena.allocator(), .{ .source = subscriber, .payload = .{ .node = subscriber } });
                    },
                    .list_append => try self.processListAppendPulse(subscriber, call, pulse),
                    .list_clear => try self.processListClearPulse(subscriber, call, pulse),
                    .router_go_to => {
                        if (call.positional.len != 0 and !self.pulseMatchesTriggerEventForSource(call.positional[0], pulse.source, pulse)) return;
                        try self.dispatchRouterGoTo(subscriber, call, pulse.scope, pulse.payload);
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    fn sumSourceIsMultiSourceLatest(self: *Session, call: flow_ir.BuiltinCall) bool {
        if (call.positional.len == 0) return false;
        return self.sourceIsMultiSourceLatest(call.positional[0]);
    }

    fn sourceIsMultiSourceLatest(self: *Session, node_id: flow_ir.NodeId) bool {
        return switch (self.flow.nodes[node_id].kind) {
            .binding_ref => |binding_id| self.sourceIsMultiSourceLatest(self.flow.bindings[binding_id].node),
            .latest => |latest| latest.sources.len > 1,
            else => false,
        };
    }

    fn latestPulseMatches(self: *Session, latest: flow_ir.Latest, pulse: Pulse) anyerror!bool {
        if (latest.initial) |initial_node| {
            if (try self.latestSourceMatchesPulse(initial_node, pulse)) return true;
        }
        for (latest.sources) |source_node| {
            if (try self.latestSourceMatchesPulse(source_node, pulse)) return true;
        }
        return false;
    }

    fn latestSourceMatchesPulse(self: *Session, source_node: flow_ir.NodeId, pulse: Pulse) anyerror!bool {
        const source = if (pulse.scope) |scope|
            self.scopedEventDependencySource(source_node, scope) catch |err| switch (err) {
                error.MissingLocalBinding,
                error.MissingRecordField,
                error.ExpectedRecordNode,
                error.ExpectedLinkNode,
                error.ExpectedLinkValue,
                error.UnsupportedFieldAccess,
                error.UnsupportedEventSource,
                => return false,
                else => return err,
            }
        else
            self.eventDependencySource(source_node) catch |err| switch (err) {
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
        if (source != pulse.source) return false;
        return self.pulseMatchesTriggerEventForSource(source_node, pulse.source, pulse);
    }

    fn latestPayloadForPulse(self: *Session, latest: flow_ir.Latest, pulse: Pulse) anyerror!?PulsePayload {
        if (latest.initial) |initial_node| {
            if (try self.latestPayloadForSourcePulse(initial_node, pulse)) |payload| return payload;
        }
        for (latest.sources) |source_node| {
            if (try self.latestPayloadForSourcePulse(source_node, pulse)) |payload| return payload;
        }
        return null;
    }

    fn latestPayloadForSourcePulse(self: *Session, source_node: flow_ir.NodeId, pulse: Pulse) anyerror!?PulsePayload {
        const source = if (pulse.scope) |scope|
            self.scopedEventDependencySource(source_node, scope) catch |err| switch (err) {
                error.MissingLocalBinding,
                error.MissingRecordField,
                error.ExpectedRecordNode,
                error.ExpectedLinkNode,
                error.ExpectedLinkValue,
                error.UnsupportedFieldAccess,
                error.UnsupportedEventSource,
                => return null,
                else => return err,
            }
        else
            self.eventDependencySource(source_node) catch |err| switch (err) {
                error.MissingLocalBinding,
                error.MissingRecordField,
                error.ExpectedRecordNode,
                error.ExpectedLinkNode,
                error.ExpectedLinkValue,
                error.UnsupportedFieldAccess,
                error.UnsupportedEventSource,
                => return null,
                else => return err,
            };
        if (source != pulse.source) return null;
        if (!self.pulseMatchesTriggerEventForSource(source_node, pulse.source, pulse)) return null;
        if (source_node == source or pulse.payload == .value) return pulse.payload;
        const value = self.evalNode(self.arena.allocator(), source_node, pulse.scope) catch |err| switch (err) {
            error.MissingLocalBinding,
            error.MissingRecordField,
            error.ExpectedRecordNode,
            error.ExpectedLinkNode,
            error.ExpectedLinkValue,
            error.UnsupportedFieldAccess,
            error.UnsupportedEventSource,
            => return null,
            else => return err,
        };
        if (value == .none) return null;
        return .{ .value = value };
    }

    fn dispatchRouterGoTo(
        self: *Session,
        subscriber: flow_ir.NodeId,
        call: flow_ir.BuiltinCall,
        scope: ?*const EvalScope,
        pulse_payload: PulsePayload,
    ) !void {
        if (call.positional.len == 0) return;
        const route = route: {
            const payload_route = valueFromPulsePayload(self, self.arena.allocator(), pulse_payload, scope) catch |err| switch (err) {
                error.MissingLocalBinding => null,
                else => return err,
            };
            if (payload_route) |value| switch (value) {
                .text, .symbol => break :route value,
                else => {},
            };
            break :route self.evalNode(self.arena.allocator(), call.positional[0], scope) catch |err| switch (err) {
                error.MissingLocalBinding => return,
                else => return err,
            };
        };
        _ = valueAsText(route) catch return;
        if (route == .none) return;
        self.route_value = route;
        self.noteRouteMutation(subscriber);
        try self.logf("router_go_to n{d} -> {s}", .{ subscriber, try valueAsText(route) });
        try self.queue.append(self.arena.allocator(), .{ .source = subscriber, .payload = .{ .node = subscriber } });
    }

    fn noteRouteMutation(self: *Session, source: flow_ir.NodeId) void {
        self.noteTopLevelMutation(source);
        for (self.flow.nodes, 0..) |node, index| {
            if (node.kind != .builtin_call) continue;
            const node_id: flow_ir.NodeId = @intCast(index);
            switch (self.builtinOp(node_id)) {
                .router_route, .router_go_to => if (node_id != source) self.noteTopLevelMutation(node_id),
                else => {},
            }
        }
    }

    fn dispatchRuntimeScopedSubscribers(self: *Session, pulse: Pulse) !void {
        if (pulse.scope) |scope| {
            for (self.runtime_subscriber_nodes) |subscriber| {
                if (try self.runtimeSubscriberMatchesPulse(subscriber, pulse.source, scope)) {
                    try self.dispatchPulseToSubscriber(subscriber, pulse);
                    continue;
                }
                if (try self.listItemScopeForRuntimeSubscriber(subscriber, pulse.source, scope)) |item_scope| {
                    var scoped_pulse = pulse;
                    scoped_pulse.scope = item_scope;
                    try self.dispatchPulseToSubscriber(subscriber, scoped_pulse);
                }
            }
            return;
        }

        var scopes = self.runtime_scopes.valueIterator();
        while (scopes.next()) |scope_ptr| {
            const scope = scope_ptr.*;
            for (self.runtime_subscriber_nodes) |subscriber| {
                if (!try self.runtimeSubscriberMatchesPulse(subscriber, pulse.source, scope)) continue;
                var scoped_pulse = pulse;
                scoped_pulse.scope = scope;
                try self.dispatchPulseToSubscriber(subscriber, scoped_pulse);
            }
        }
    }

    fn listItemScopeForRuntimeSubscriber(
        self: *Session,
        subscriber: flow_ir.NodeId,
        pulse_source: flow_ir.NodeId,
        pulse_scope: *const EvalScope,
    ) anyerror!?*const EvalScope {
        const node = self.flow.nodes[subscriber];
        const source_node = switch (node.kind) {
            .then_value => |then_value| then_value.source,
            .latest => return null,
            .hold => return null,
            .linked_value => |linked| linked.value,
            .builtin_call => return null,
            else => return null,
        };
        return try self.listItemScopeForEventSource(source_node, pulse_source, pulse_scope);
    }

    fn listItemScopeForEventSource(
        self: *Session,
        source_node: flow_ir.NodeId,
        pulse_source: flow_ir.NodeId,
        pulse_scope: *const EvalScope,
    ) anyerror!?*const EvalScope {
        const local_name = self.firstLocalRefName(source_node) orelse return null;
        const allocator = self.arena.allocator();
        for (self.list_values, self.list_inited) |list_value, inited| {
            if (!inited) continue;
            const items = listItemsFromValue(list_value) catch continue;
            for (items) |item| {
                const bindings = try allocator.alloc(RecordField, 1);
                bindings[0] = .{ .name = local_name, .value = item };
                const candidate = try allocator.create(EvalScope);
                candidate.* = .{
                    .bindings = bindings,
                    .parent = pulse_scope,
                    .passed = null,
                    .id = deriveScopeId(pulse_scope, bindings, null),
                };
                const source = self.scopedEventDependencySource(source_node, candidate) catch continue;
                if (source != pulse_source) continue;
                const expected_scope = (try self.eventScopeForSource(source_node, candidate)) orelse continue;
                const canonical_expected = canonicalControlScope(expected_scope) orelse expected_scope;
                const canonical_actual = canonicalControlScope(pulse_scope) orelse pulse_scope;
                if (canonical_expected.id != canonical_actual.id) continue;
                return candidate;
            }
        }
        return null;
    }

    fn firstLocalRefName(self: *Session, node_id: flow_ir.NodeId) ?[]const u8 {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .local_ref => |name| name,
            .access => |access| self.firstLocalRefName(access.target),
            .then_value => |then_value| self.firstLocalRefName(then_value.source),
            .when => |when| self.firstLocalRefName(when.input),
            .block => |block| self.firstLocalRefName(block.result),
            .binary => |binary| self.firstLocalRefName(binary.lhs) orelse self.firstLocalRefName(binary.rhs),
            .text => |parts| blk: {
                for (parts) |part| if (self.firstLocalRefName(part)) |name| break :blk name;
                break :blk null;
            },
            .record => |fields| blk: {
                for (fields) |field| if (self.firstLocalRefName(field.value)) |name| break :blk name;
                break :blk null;
            },
            .list => |list| blk: {
                for (list.items) |item| if (self.firstLocalRefName(item)) |name| break :blk name;
                break :blk null;
            },
            .builtin_call => |call| blk: {
                for (call.positional) |argument| if (self.firstLocalRefName(argument)) |name| break :blk name;
                for (call.named) |argument| if (self.firstLocalRefName(argument.value)) |name| break :blk name;
                break :blk null;
            },
            .user_call => |call| blk: {
                for (call.positional) |argument| if (self.firstLocalRefName(argument)) |name| break :blk name;
                for (call.named) |argument| if (self.firstLocalRefName(argument.value)) |name| break :blk name;
                if (call.pass_context) |pass_context| break :blk self.firstLocalRefName(pass_context);
                break :blk null;
            },
            else => null,
        };
    }

    fn runtimeSubscriberMatchesPulse(self: *Session, subscriber: flow_ir.NodeId, pulse_source: flow_ir.NodeId, scope: *const EvalScope) anyerror!bool {
        const node = self.flow.nodes[subscriber];
        return switch (node.kind) {
            .then_value => |then_value| self.nodeNeedsScope(then_value.source) and try self.safeScopedEventSourceEquals(then_value.source, scope, pulse_source),
            .latest => |latest| blk: {
                if (latest.initial) |initial_node| {
                    if (self.nodeNeedsScope(initial_node) and try self.safeScopedLatestSourceEquals(initial_node, scope, pulse_source)) break :blk true;
                }
                for (latest.sources) |source_node| {
                    if (!self.nodeNeedsScope(source_node)) continue;
                    if (try self.safeScopedLatestSourceEquals(source_node, scope, pulse_source)) break :blk true;
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
            .builtin_call => |call| try self.runtimeBuiltinCallMatchesPulse(subscriber, call, pulse_source, scope),
            else => false,
        };
    }

    fn runtimeBuiltinCallMatchesPulse(self: *Session, subscriber: flow_ir.NodeId, call: flow_ir.BuiltinCall, pulse_source: flow_ir.NodeId, scope: *const EvalScope) anyerror!bool {
        switch (self.builtinOp(subscriber)) {
            .stream_pulses, .stream_skip, .math_sum => if (call.positional.len != 0) {
                return self.nodeNeedsScope(call.positional[0]) and try self.safeScopedEventSourceEquals(call.positional[0], scope, pulse_source);
            },
            .list_append => {
                if (call.positional.len != 0 and self.nodeNeedsScope(call.positional[0]) and try self.safeScopedListSourceEquals(call.positional[0], scope, pulse_source)) return true;
                if (findNamed(call.named, "item")) |item_node| {
                    return self.nodeNeedsScope(item_node) and try self.safeScopedValueSourceEquals(item_node, scope, pulse_source);
                }
                if (findNamed(call.named, "on")) |on_node| {
                    return self.nodeNeedsScope(on_node) and try self.safeScopedValueSourceEquals(on_node, scope, pulse_source);
                }
            },
            .list_clear, .list_remove_last => {
                if (call.positional.len != 0 and self.nodeNeedsScope(call.positional[0]) and try self.safeScopedListSourceEquals(call.positional[0], scope, pulse_source)) return true;
                const on_node = findNamed(call.named, "on") orelse return false;
                return self.nodeNeedsScope(on_node) and try self.safeScopedValueSourceEquals(on_node, scope, pulse_source);
            },
            .router_go_to => if (call.positional.len != 0) {
                return self.nodeNeedsScope(call.positional[0]) and try self.safeScopedEventSourceEquals(call.positional[0], scope, pulse_source);
            },
            else => {},
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

    fn safeScopedLatestSourceEquals(self: *Session, node_id: flow_ir.NodeId, scope: *const EvalScope, pulse_source: flow_ir.NodeId) anyerror!bool {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.safeScopedLatestSourceEquals(self.flow.bindings[binding_id].node, scope, pulse_source),
            .block => |block| try self.safeScopedLatestSourceEquals(block.result, scope, pulse_source),
            .when => |when| try self.safeScopedEventSourceEquals(when.input, scope, pulse_source),
            .then_value, .latest, .hold, .linked_value => node_id == pulse_source,
            .builtin_call => try self.safeScopedEventSourceEquals(node_id, scope, pulse_source),
            else => try self.safeScopedEventSourceEquals(node_id, scope, pulse_source),
        };
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
            .builtin_call => switch (self.builtinOp(node_id)) {
                .list_append, .list_clear, .list_remove, .list_remove_last => node_id,
                else => try self.scopedEventDependencySource(node_id, scope),
            },
            else => try self.scopedEventDependencySource(node_id, scope),
        };
    }

    fn numberFromNode(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!f64 {
        const value = try self.evalNode(self.scratch_arena.allocator(), node_id, scope);
        return try valueAsNumber(value);
    }

    fn initialNumericValue(self: *Session, node_id: flow_ir.NodeId) anyerror!?f64 {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .binding_ref => |binding_id| try self.initialNumericValue(self.flow.bindings[binding_id].node),
            .number => |number| number.value,
            .latest => blk: {
                const value = self.evalNode(self.scratch_arena.allocator(), node_id, null) catch |err| switch (err) {
                    error.ExpectedNumericValue, error.ExpectedTextValue, error.ExpectedDurationValue => break :blk null,
                    else => return err,
                };
                break :blk switch (value) {
                    .number => |number| number,
                    else => null,
                };
            },
            .link_port => if (self.getLinkValue(node_id, null)) |value| try valueAsNumber(value) else null,
            .builtin_call => blk: {
                if (self.builtinOp(node_id) == .math_sum and self.sum_inited[node_id]) {
                    break :blk self.sum_values[node_id];
                }
                break :blk null;
            },
            else => null,
        };
    }

    fn cachedControlRefs(self: *Session, kind: CachedControlKind) anyerror![]const ControlEventRef {
        switch (kind) {
            .button => if (self.cached_button_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_button_links_deps, self.cached_button_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .slider => if (self.cached_slider_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_slider_links_deps, self.cached_slider_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .text_input => if (self.cached_text_input_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_text_input_links_deps, self.cached_text_input_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .text_input_key => if (self.cached_text_input_key_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_text_input_key_links_deps, self.cached_text_input_key_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .text_input_blur => if (self.cached_text_input_blur_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_text_input_blur_links_deps, self.cached_text_input_blur_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .text_input_focus => if (self.cached_text_input_focus_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_text_input_focus_links_deps, self.cached_text_input_focus_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .label_double_click => if (self.cached_label_double_click_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_label_double_click_links_deps, self.cached_label_double_click_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .hover => if (self.cached_hover_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_hover_links_deps, self.cached_hover_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
            .select => if (self.cached_select_links) |links| {
                if (self.cachedDepsWithVersionsAreFresh(self.cached_select_links_deps, self.cached_select_links_versions)) return links;
                self.resetMemoDerivedCaches();
            },
        }

        var frame = EvalFrame{ .parent = self.current_eval_frame };
        self.current_eval_frame = &frame;
        defer {
            self.current_eval_frame = frame.parent;
            frame.deps.deinit(self.arena.allocator());
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
        const deps = try self.arena.allocator().alloc(ScopedNodeKey, frame.deps.items.len);
        const versions = try self.arena.allocator().alloc(u32, frame.deps.items.len);
        @memcpy(deps, frame.deps.items);
        for (frame.deps.items, 0..) |dep, index| versions[index] = self.stateVersion(dep);
        switch (kind) {
            .button => {
                self.cached_button_links = owned;
                self.cached_button_links_deps = deps;
                self.cached_button_links_versions = versions;
            },
            .slider => {
                self.cached_slider_links = owned;
                self.cached_slider_links_deps = deps;
                self.cached_slider_links_versions = versions;
            },
            .text_input => {
                self.cached_text_input_links = owned;
                self.cached_text_input_links_deps = deps;
                self.cached_text_input_links_versions = versions;
            },
            .text_input_key => {
                self.cached_text_input_key_links = owned;
                self.cached_text_input_key_links_deps = deps;
                self.cached_text_input_key_links_versions = versions;
            },
            .text_input_blur => {
                self.cached_text_input_blur_links = owned;
                self.cached_text_input_blur_links_deps = deps;
                self.cached_text_input_blur_links_versions = versions;
            },
            .text_input_focus => {
                self.cached_text_input_focus_links = owned;
                self.cached_text_input_focus_links_deps = deps;
                self.cached_text_input_focus_links_versions = versions;
            },
            .label_double_click => {
                self.cached_label_double_click_links = owned;
                self.cached_label_double_click_links_deps = deps;
                self.cached_label_double_click_links_versions = versions;
            },
            .hover => {
                self.cached_hover_links = owned;
                self.cached_hover_links_deps = deps;
                self.cached_hover_links_versions = versions;
            },
            .select => {
                self.cached_select_links = owned;
                self.cached_select_links_deps = deps;
                self.cached_select_links_versions = versions;
            },
        }
        return owned;
    }

    fn buttonLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        const links = try self.cachedControlRefs(.button);
        if (index >= links.len) return error.InvalidButtonIndex;
        return links[index];
    }

    fn checkboxLinkAt(self: *Session, index: usize) anyerror!ControlEventRef {
        try self.flushPendingQueue();
        var scratch = std.heap.ArenaAllocator.init(self.backing_allocator);
        defer scratch.deinit();

        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const value = try self.evalNode(scratch.allocator(), self.flow.bindings[root_binding].node, null);
        var links: std.ArrayList(ControlEventRef) = .empty;
        defer links.deinit(scratch.allocator());
        try collectCheckboxLinks(self, &links, scratch.allocator(), value);
        if (index >= links.items.len) return error.InvalidButtonIndex;
        return try cloneControlEventRefForCache(self.arena.allocator(), links.items[index]);
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

    pub fn semanticRootValue(self: *Session) anyerror!Value {
        return try self.interactionRootValue();
    }

    pub fn semanticBindingValue(self: *Session, binding_id: flow_ir.BindingId) anyerror!Value {
        return try self.evalNode(self.arena.allocator(), self.flow.bindings[binding_id].node, null);
    }

    pub fn evalSemanticNode(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!Value {
        return try self.evalNode(self.arena.allocator(), node_id, scope);
    }

    fn scopedNodeKey(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?ScopedNodeKey {
        _ = self;
        const normalized_scope = canonicalControlScope(normalizedStateScope(scope)) orelse return null;
        return .{
            .node_id = node_id,
            .scope_id = normalized_scope.id,
        };
    }

    fn linkScope(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?*const EvalScope {
        return if (self.isTopLevelOwnedNode(node_id)) null else scope;
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

    fn mergeCachedDependencies(self: *Session, deps: []const CachedDependency) !void {
        const frame = self.current_eval_frame orelse return;
        for (deps) |dep| try self.addFrameDependency(frame, dep.key);
    }

    fn recordStateDependency(self: *Session, dep: ScopedNodeKey) !void {
        const frame = self.current_eval_frame orelse return;
        try self.addFrameDependency(frame, dep);
    }

    fn stateVersion(self: *const Session, dep: ScopedNodeKey) u32 {
        return if (dep.scope_id == 0 and dep.node_id < self.state_versions.len) self.state_versions[dep.node_id] else 0;
    }

    fn clearDerivedCaches(self: *Session) void {
        self.resetMemoDerivedCaches();
    }

    fn noteStateMutation(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) void {
        const dep = self.scopedStateKey(node_id, scope);
        if (dep.scope_id == 0) {
            self.state_versions[node_id] +%= 1;
            self.clearEvalCache();
            self.clearDerivedCaches();
            return;
        }
        self.invalidateEvalCacheForDependency(dep);
    }

    fn noteTopLevelMutation(self: *Session, node_id: flow_ir.NodeId) void {
        self.noteStateMutation(node_id, null);
    }

    fn cachedEntryIsFresh(self: *const Session, cached: CachedEvalEntry) bool {
        for (cached.deps) |dep| {
            if (dep.version != self.stateVersion(dep.key)) return false;
        }
        return true;
    }

    fn cachedDepsAreFresh(self: *const Session, deps: []const CachedDependency) bool {
        for (deps) |dep| {
            if (dep.version != self.stateVersion(dep.key)) return false;
        }
        return true;
    }

    fn cachedTerminalContractIsFresh(self: *const Session) bool {
        return self.cachedDepsWithVersionsAreFresh(self.cached_terminal_contract_deps, self.cached_terminal_contract_versions);
    }

    fn cachedDepsWithVersionsAreFresh(
        self: *const Session,
        deps_opt: ?[]ScopedNodeKey,
        versions_opt: ?[]u32,
    ) bool {
        const deps = deps_opt orelse return false;
        const versions = versions_opt orelse return false;
        if (deps.len != versions.len) return false;
        for (deps, versions) |dep, version| {
            if (version != self.stateVersion(dep)) return false;
        }
        return true;
    }

    fn snapshotFrameDeps(self: *Session, frame: *const EvalFrame) !struct { deps: []ScopedNodeKey, versions: []u32 } {
        const deps = try self.arena.allocator().alloc(ScopedNodeKey, frame.deps.items.len);
        const versions = try self.arena.allocator().alloc(u32, frame.deps.items.len);
        @memcpy(deps, frame.deps.items);
        for (frame.deps.items, 0..) |dep, index| versions[index] = self.stateVersion(dep);
        return .{ .deps = deps, .versions = versions };
    }

    fn dropCachedTerminalContract(self: *Session) void {
        self.cached_terminal_contract_deps = null;
        self.cached_terminal_contract_versions = null;
        self.cached_terminal_contract = null;
    }

    fn dropCachedControlRefs(self: *Session, kind: CachedControlKind) void {
        switch (kind) {
            .button => {
                self.cached_button_links = null;
                self.cached_button_links_deps = null;
                self.cached_button_links_versions = null;
            },
            .slider => {
                self.cached_slider_links = null;
                self.cached_slider_links_deps = null;
                self.cached_slider_links_versions = null;
            },
            .text_input => {
                self.cached_text_input_links = null;
                self.cached_text_input_links_deps = null;
                self.cached_text_input_links_versions = null;
            },
            .text_input_key => {
                self.cached_text_input_key_links = null;
                self.cached_text_input_key_links_deps = null;
                self.cached_text_input_key_links_versions = null;
            },
            .text_input_blur => {
                self.cached_text_input_blur_links = null;
                self.cached_text_input_blur_links_deps = null;
                self.cached_text_input_blur_links_versions = null;
            },
            .text_input_focus => {
                self.cached_text_input_focus_links = null;
                self.cached_text_input_focus_links_deps = null;
                self.cached_text_input_focus_links_versions = null;
            },
            .label_double_click => {
                self.cached_label_double_click_links = null;
                self.cached_label_double_click_links_deps = null;
                self.cached_label_double_click_links_versions = null;
            },
            .hover => {
                self.cached_hover_links = null;
                self.cached_hover_links_deps = null;
                self.cached_hover_links_versions = null;
            },
            .select => {
                self.cached_select_links = null;
                self.cached_select_links_deps = null;
                self.cached_select_links_versions = null;
            },
        }
    }

    fn dropCachedTextInputs(self: *Session) void {
        self.cached_text_inputs = null;
        self.cached_text_inputs_deps = null;
        self.cached_text_inputs_versions = null;
    }

    fn resetMemoDerivedCaches(self: *Session) void {
        self.dropCachedTerminalContract();
        self.cached_terminal_hit_regions = null;
        self.dropCachedControlRefs(.button);
        self.dropCachedControlRefs(.slider);
        self.dropCachedControlRefs(.text_input);
        self.dropCachedControlRefs(.text_input_key);
        self.dropCachedControlRefs(.text_input_blur);
        self.dropCachedControlRefs(.text_input_focus);
        self.dropCachedControlRefs(.label_double_click);
        self.dropCachedControlRefs(.hover);
        self.dropCachedControlRefs(.select);
        self.dropCachedTextInputs();
    }

    fn scopedStateKey(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ScopedNodeKey {
        if (self.scopedNodeKey(node_id, scope)) |key| return key;
        return .{ .node_id = node_id, .scope_id = 0 };
    }

    fn rememberRuntimeScope(self: *Session, scope: ?*const EvalScope) !void {
        const normalized = canonicalControlScope(normalizedStateScope(scope)) orelse return;
        if (self.runtime_scopes.contains(normalized.id)) return;
        try self.runtime_scopes.put(self.arena.allocator(), normalized.id, try captureScope(self.arena.allocator(), normalized) orelse return);
    }

    fn recordLinkDependencies(self: *Session, link: flow_ir.NodeId, scope: ?*const EvalScope, include_key: bool) !void {
        const storage_scope = self.linkScope(link, scope);
        try self.recordStateDependency(self.scopedStateKey(link, storage_scope));
        if (include_key) try self.recordStateDependency(self.scopedStateKey(link, storage_scope));
    }

    fn invalidateEvalCacheForDependency(self: *Session, dep: ScopedNodeKey) void {
        if (dep.scope_id != 0 and self.top_level_eval_inited.len != 0) {
            @memset(self.top_level_eval_inited, false);
        }
        if (self.cached_terminal_contract_deps) |deps| {
            for (deps) |cached_dep| {
                if (cached_dep.node_id == dep.node_id and cached_dep.scope_id == dep.scope_id) {
                    self.dropCachedTerminalContract();
                    break;
                }
            }
        }
        self.clearDerivedCaches();

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
                if (cached_dep.key.node_id == dep.node_id and cached_dep.key.scope_id == dep.scope_id) {
                    keys.append(self.backing_allocator, key) catch {
                        self.invalidateEvalCache();
                        return;
                    };
                    break;
                }
            }
        }

        for (keys.items) |key| {
            _ = self.eval_cache.fetchRemove(key);
        }
    }

    fn isTopLevelBindingNode(self: *Session, node_id: flow_ir.NodeId) bool {
        for (self.flow.bindings) |binding| {
            if (binding.node == node_id) return true;
        }
        return false;
    }

    fn isTopLevelOwnedNode(self: *Session, node_id: flow_ir.NodeId) bool {
        return node_id < self.top_level_owned_nodes.len and self.top_level_owned_nodes[node_id];
    }

    fn nodeNeedsRuntimeScope(self: *Session, node_id: flow_ir.NodeId) bool {
        return self.nodeNeedsScope(node_id) and !self.isTopLevelOwnedNode(node_id);
    }

    fn markTopLevelOwnedNode(self: *Session, node_id: flow_ir.NodeId, visiting: []bool) void {
        if (node_id >= self.top_level_owned_nodes.len) return;
        if (visiting[node_id]) return;
        self.top_level_owned_nodes[node_id] = true;
        visiting[node_id] = true;
        defer visiting[node_id] = false;

        const node = self.flow.nodes[node_id];
        switch (node.kind) {
            .binding_ref => |binding_id| self.markTopLevelOwnedNode(self.flow.bindings[binding_id].node, visiting),
            .text => |parts| {
                for (parts) |part| self.markTopLevelOwnedNode(part, visiting);
            },
            .list => |list| {
                for (list.items) |item| self.markTopLevelOwnedNode(item, visiting);
            },
            .record => |fields| {
                for (fields) |field| self.markTopLevelOwnedNode(field.value, visiting);
            },
            .access => |access| self.markTopLevelOwnedNode(access.target, visiting),
            .binary => |binary| {
                self.markTopLevelOwnedNode(binary.lhs, visiting);
                self.markTopLevelOwnedNode(binary.rhs, visiting);
            },
            .block => |block| {
                for (block.bindings) |binding| self.markTopLevelOwnedNode(binding.value, visiting);
                self.markTopLevelOwnedNode(block.result, visiting);
            },
            .when => |when| {
                self.markTopLevelOwnedNode(when.input, visiting);
                for (when.arms) |arm| {
                    self.markTopLevelOwnedNode(arm.pattern, visiting);
                    self.markTopLevelOwnedNode(arm.result, visiting);
                }
            },
            .latest => |latest| {
                if (latest.initial) |initial| self.markTopLevelOwnedNode(initial, visiting);
                for (latest.sources) |source| self.markTopLevelOwnedNode(source, visiting);
            },
            .then_value => |then_value| {
                self.markTopLevelOwnedNode(then_value.source, visiting);
                self.markTopLevelOwnedNode(then_value.value, visiting);
            },
            .hold => |hold| {
                self.markTopLevelOwnedNode(hold.initial, visiting);
                for (hold.updates) |update| self.markTopLevelOwnedNode(update, visiting);
            },
            .linked_value => |linked| {
                self.markTopLevelOwnedNode(linked.value, visiting);
                self.markTopLevelOwnedNode(linked.target, visiting);
            },
            .builtin_call => |call| {
                for (call.positional) |argument| self.markTopLevelOwnedNode(argument, visiting);
                for (call.named) |argument| self.markTopLevelOwnedNode(argument.value, visiting);
            },
            .user_call => |call| {
                for (call.positional) |argument| self.markTopLevelOwnedNode(argument, visiting);
                for (call.named) |argument| self.markTopLevelOwnedNode(argument.value, visiting);
                if (call.pass_context) |pass_context| self.markTopLevelOwnedNode(pass_context, visiting);
            },
            else => {},
        }
    }

    fn holdStorageScope(self: *Session, node_id: flow_ir.NodeId, hold: flow_ir.Hold, scope: ?*const EvalScope) ?*const EvalScope {
        if (self.isTopLevelOwnedNode(node_id)) return null;
        if (normalizedStateScope(scope)) |runtime_scope| return runtime_scope;
        if (!self.holdNeedsRuntimeScope(node_id, hold)) return null;
        return normalizedStateScope(scope);
    }

    fn canonicalControlScope(scope: ?*const EvalScope) ?*const EvalScope {
        var current = scope orelse return null;
        var candidate: ?*const EvalScope = null;
        while (true) {
            if (current.bindings.len == 1 and std.mem.eql(u8, current.bindings[0].name, "element")) {
                current = current.parent orelse return candidate;
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

    fn sameScopedLink(
        lhs_link: flow_ir.NodeId,
        lhs_scope: ?*const EvalScope,
        rhs_link: flow_ir.NodeId,
        rhs_scope: ?*const EvalScope,
    ) bool {
        if (lhs_link != rhs_link) return false;
        if (lhs_scope == null and rhs_scope == null) return true;
        if (lhs_scope == null or rhs_scope == null) return false;
        return lhs_scope.?.id == rhs_scope.?.id;
    }

    fn getLinkValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?Value {
        const storage_scope = self.linkScope(node_id, scope);
        if (self.scopedNodeKey(node_id, storage_scope)) |key| return self.scoped_link_values.get(key);
        return if (self.link_inited[node_id]) self.link_values[node_id] else null;
    }

    fn setLinkValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope, value: Value) !void {
        const storage_scope = self.linkScope(node_id, scope);
        self.noteStateMutation(node_id, storage_scope);
        if (self.scopedNodeKey(node_id, storage_scope)) |key| {
            try self.rememberRuntimeScope(storage_scope);
            try self.scoped_link_values.put(self.arena.allocator(), key, value);
            return;
        }
        if (scope != null) try self.rememberRuntimeScope(scope);
        self.link_values[node_id] = value;
        self.link_inited[node_id] = true;
    }

    fn getLinkKeyValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?Value {
        const storage_scope = self.linkScope(node_id, scope);
        if (self.scopedNodeKey(node_id, storage_scope)) |key| return self.scoped_link_key_values.get(key);
        return if (self.link_key_inited[node_id]) self.link_key_values[node_id] else null;
    }

    fn setLinkKeyValue(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope, value: Value) !void {
        const storage_scope = self.linkScope(node_id, scope);
        self.noteStateMutation(node_id, storage_scope);
        if (self.scopedNodeKey(node_id, storage_scope)) |key| {
            try self.rememberRuntimeScope(storage_scope);
            try self.scoped_link_key_values.put(self.arena.allocator(), key, value);
            return;
        }
        if (scope != null) try self.rememberRuntimeScope(scope);
        self.link_key_values[node_id] = value;
        self.link_key_inited[node_id] = true;
    }

    fn getLatestPayload(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) ?PulsePayload {
        if (self.scopedNodeKey(node_id, scope)) |key| return self.scoped_latest_values.get(key);
        return self.latest_values[node_id];
    }

    fn setLatestPayload(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope, payload: PulsePayload) !void {
        self.noteStateMutation(node_id, scope);
        if (self.scopedNodeKey(node_id, scope)) |key| {
            try self.rememberRuntimeScope(scope);
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
        self.noteStateMutation(node_id, scope);
        if (self.scopedNodeKey(node_id, scope)) |key| {
            try self.rememberRuntimeScope(scope);
            try self.scoped_hold_values.put(self.arena.allocator(), key, value);
            return;
        }
        self.hold_values[node_id] = value;
        self.hold_inited[node_id] = true;
    }

    fn currentTextInputValue(self: *Session, index: usize) anyerror!Value {
        const event = try self.textInputLinkAt(index);
        const scope = canonicalControlScope(event.scope);
        if (self.getLinkValue(event.link, scope)) |value| {
            switch (value) {
                .record => |fields| {
                    if (findRecordValue(fields, "text")) |text| return text;
                    if (findRecordValue(fields, "value")) |text| return text;
                },
                else => return value,
            }
        }

        const inputs = try self.textInputValuesView();
        if (index >= inputs.len) return error.InvalidTextInputIndex;
        return inputs[index].text;
    }

    fn textInputValuesView(self: *Session) anyerror![]*TextInputValue {
        try self.flushPendingQueue();
        if (self.cached_text_inputs) |inputs| {
            if (self.cachedDepsWithVersionsAreFresh(self.cached_text_inputs_deps, self.cached_text_inputs_versions)) return inputs;
            self.resetMemoDerivedCaches();
        }

        var frame = EvalFrame{ .parent = self.current_eval_frame };
        self.current_eval_frame = &frame;
        defer {
            self.current_eval_frame = frame.parent;
            frame.deps.deinit(self.arena.allocator());
        }

        const value = try self.interactionRootValue();
        var inputs: std.ArrayList(*TextInputValue) = .empty;
        defer inputs.deinit(self.memo_arena.allocator());
        try collectTextInputValues(self, &inputs, self.memo_arena.allocator(), value);
        const owned = try inputs.toOwnedSlice(self.memo_arena.allocator());
        const deps = try self.arena.allocator().alloc(ScopedNodeKey, frame.deps.items.len);
        const versions = try self.arena.allocator().alloc(u32, frame.deps.items.len);
        @memcpy(deps, frame.deps.items);
        for (frame.deps.items, 0..) |dep, index| versions[index] = self.stateVersion(dep);
        self.cached_text_inputs = owned;
        self.cached_text_inputs_deps = deps;
        self.cached_text_inputs_versions = versions;
        return owned;
    }

    fn evalNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!Value {
        if (scope == null and node_id < self.top_level_eval_inited.len) {
            if (self.top_level_eval_inited[node_id]) {
                const deps = self.top_level_eval_deps[node_id];
                if (self.cachedDepsAreFresh(deps)) {
                    try self.mergeCachedDependencies(deps);
                    return self.top_level_eval_values[node_id];
                }
                self.top_level_eval_inited[node_id] = false;
            }
        } else {
            const cache_key = self.evalCacheKey(node_id, scope);
            if (self.eval_cache.get(cache_key)) |cached| {
                if (self.cachedEntryIsFresh(cached)) {
                    try self.mergeCachedDependencies(cached.deps);
                    return cached.value;
                }
                _ = self.eval_cache.fetchRemove(cache_key);
            }
        }

        var frame = EvalFrame{ .parent = self.current_eval_frame };
        self.current_eval_frame = &frame;
        defer {
            self.current_eval_frame = frame.parent;
            frame.deps.deinit(self.backing_allocator);
        }

        const value = try self.evalNodeUncached(allocator, node_id, scope);
        const deps = try self.arena.allocator().alloc(CachedDependency, frame.deps.items.len);
        for (frame.deps.items, 0..) |dep, index| {
            deps[index] = .{
                .key = dep,
                .version = self.stateVersion(dep),
            };
        }
        if (frame.parent) |parent| {
            for (frame.deps.items) |dep| try self.addFrameDependency(parent, dep);
        }
        if (scope == null and node_id < self.top_level_eval_inited.len) {
            self.top_level_eval_values[node_id] = value;
            self.top_level_eval_deps[node_id] = deps;
            self.top_level_eval_inited[node_id] = true;
        } else {
            const cache_key = self.evalCacheKey(node_id, scope);
            try self.eval_cache.put(self.backing_allocator, cache_key, .{
                .value = value,
                .deps = deps,
            });
        }
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
                const latest_scope = if (self.nodeNeedsScope(node_id) or normalizedStateScope(scope) != null) scope else null;
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
                if (self.isTopLevelOwnedNode(node_id)) {
                    if (self.getHoldValue(node_id, null)) |canonical| {
                        if (canonical != .none) {
                            try self.recordStateDependency(self.scopedStateKey(node_id, null));
                            break :blk canonical;
                        }
                    }
                }
                const hold_scope = self.holdStorageScope(node_id, hold, scope);
                try self.recordStateDependency(self.scopedStateKey(node_id, hold_scope));
                if (self.getHoldValue(node_id, hold_scope)) |value| break :blk value;
                const initial = try self.evalNode(allocator, hold.initial, hold_scope);
                try self.setHoldValue(node_id, hold_scope, initial);
                break :blk initial;
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
        const passed = if (scope) |parent| parent.passed else null;

        var record_scope = EvalScope{
            .bindings = &.{},
            .parent = scope,
            .passed = passed,
            .id = recordScopeIdBase(scope, passed),
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
                    record_scope.id = extendRecordScopeId(record_scope.id, spread_field);
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
                try self.rememberRuntimeScope(deferred.scope);
                break :blk Value{ .scoped_node = deferred };
            } else switch (self.flow.nodes[field.value].kind) {
                .binding_ref => |binding_id| Value{ .binding_ref = binding_id },
                .link_port => if (scope != null and !self.isTopLevelOwnedNode(field.value))
                    if (scope) |field_scope|
                        Value{ .scoped_link = .{ .link = field.value, .scope = try captureControlScope(allocator, field_scope) } }
                    else
                        unreachable
                else
                    Value{ .link = field.value },
                else => try self.evalNode(allocator, field.value, scope),
            };
            const record_field = RecordField{
                .name = field.name,
                .value = field_value,
            };
            try values.append(allocator, record_field);
            record_scope.bindings = values.items;
            record_scope.id = extendRecordScopeId(record_scope.id, record_field);
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
            switch (self.flow.nodes[field_node].kind) {
                .hold, .latest, .link_port => switch (self.flow.nodes[access.target].kind) {
                    .symbol, .local_ref => {},
                    else => return try self.evalNode(allocator, field_node, scope),
                },
                else => if (!self.nodeNeedsScope(field_node) and !self.nodeNeedsDeferredField(field_node)) {
                    return try self.evalNode(allocator, field_node, scope);
                },
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
                    .scoped_link => |scoped| try self.valueFromLink(scoped.link, scoped.scope, false, field_value),
                    .scoped_node => |deferred| if (!self.nodeNeedsScope(deferred.node_id) and self.nodeNeedsDeferredField(deferred.node_id)) blk2: {
                        const resolved = try self.evalNode(allocator, deferred.node_id, canonicalControlScope(deferred.scope));
                        break :blk2 switch (resolved) {
                            .link => |link| try self.valueFromLink(link, scope, false, resolved),
                            .scoped_link => |scoped| try self.valueFromLink(scoped.link, scoped.scope, false, resolved),
                            else => resolved,
                        };
                    } else blk2: {
                        const resolved = try self.materializeValue(allocator, field_value);
                        break :blk2 switch (resolved) {
                            .link => |link| try self.valueFromLink(link, scope, false, resolved),
                            .scoped_link => |scoped| try self.valueFromLink(scoped.link, scoped.scope, false, resolved),
                            else => resolved,
                        };
                    },
                    else => blk2: {
                        const resolved = try self.materializeValue(allocator, field_value);
                        break :blk2 switch (resolved) {
                            .link => |link| try self.valueFromLink(link, scope, false, resolved),
                            .scoped_link => |scoped| try self.valueFromLink(scoped.link, scoped.scope, false, resolved),
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
                    break :blk if (stripe.hovered_link) |link| hovered_blk: {
                        try self.recordLinkDependencies(link, stripe.event_scope orelse scope, false);
                        break :hovered_blk self.getLinkValue(link, stripe.event_scope orelse scope) orelse .{ .link = link };
                    } else .none;
                }
                break :blk error.UnsupportedFieldAccess;
            },
            .label, .checkbox, .button, .text_input, .select, .slider => blk: {
                if (std.mem.eql(u8, access.field, "event")) {
                    break :blk try controlEventValue(allocator, target);
                }
                if (std.mem.eql(u8, access.field, "hovered")) {
                    break :blk switch (target) {
                        .button => |button| if (button.hovered_link) |link| hovered_blk: {
                            try self.recordLinkDependencies(link, button.event_scope orelse scope, false);
                            break :hovered_blk self.getLinkValue(link, button.event_scope orelse scope) orelse .{ .link = link };
                        } else .none,
                        else => error.UnsupportedFieldAccess,
                    };
                }
                break :blk error.UnsupportedFieldAccess;
            },
            .scoped_link => |scoped| try self.evalLinkAccess(allocator, scoped.link, scoped.scope, access.field),
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
                    const event_text = linkEventTextValue(link_value);
                    const event_key = linkEventKeyValue(link_value, key_value);
                    const change_fields = try allocator.alloc(RecordField, 2);
                    change_fields[0] = .{
                        .name = "value",
                        .value = event_text,
                    };
                    change_fields[1] = .{
                        .name = "text",
                        .value = event_text,
                    };
                    const key_fields = try allocator.alloc(RecordField, 2);
                    key_fields[0] = .{
                        .name = "key",
                        .value = event_key,
                    };
                    key_fields[1] = .{
                        .name = "text",
                        .value = event_text,
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

    fn valueFromLink(self: *Session, link: flow_ir.NodeId, scope: ?*const EvalScope, include_key: bool, fallback: Value) !Value {
        try self.recordLinkDependencies(link, scope, include_key);
        return self.getLinkValue(link, scope) orelse fallback;
    }

    fn evalLinkAccess(self: *Session, allocator: std.mem.Allocator, link: flow_ir.NodeId, scope: ?*const EvalScope, field: []const u8) anyerror!Value {
        return blk: {
            if (std.mem.eql(u8, field, "text")) {
                try self.recordLinkDependencies(link, scope, false);
                if (self.getLinkValue(link, scope)) |link_value| {
                    if (recordFieldFromValue(link_value, "text")) |field_value| break :blk field_value;
                }
                break :blk self.getLinkValue(link, scope) orelse .{ .text = "" };
            }
            if (std.mem.eql(u8, field, "value")) {
                try self.recordLinkDependencies(link, scope, false);
                if (self.getLinkValue(link, scope)) |link_value| {
                    if (recordFieldFromValue(link_value, "value")) |field_value| break :blk field_value;
                }
                break :blk self.getLinkValue(link, scope) orelse .none;
            }
            if (std.mem.eql(u8, field, "key")) {
                try self.recordLinkDependencies(link, scope, true);
                if (self.getLinkValue(link, scope)) |link_value| {
                    if (recordFieldFromValue(link_value, "key")) |field_value| break :blk field_value;
                }
                break :blk self.getLinkKeyValue(link, scope) orelse .none;
            }
            if (std.mem.eql(u8, field, "event")) {
                try self.recordLinkDependencies(link, scope, true);
                const link_value = self.getLinkValue(link, scope);
                const key_value = self.getLinkKeyValue(link, scope);
                const event_text = linkEventTextValue(link_value);
                const event_key = linkEventKeyValue(link_value, key_value);
                const change_fields = try allocator.alloc(RecordField, 2);
                change_fields[0] = .{
                    .name = "value",
                    .value = event_text,
                };
                change_fields[1] = .{
                    .name = "text",
                    .value = event_text,
                };
                const key_fields = try allocator.alloc(RecordField, 2);
                key_fields[0] = .{
                    .name = "key",
                    .value = event_key,
                };
                key_fields[1] = .{
                    .name = "text",
                    .value = event_text,
                };
                const fields = try allocator.alloc(RecordField, 3);
                fields[0] = .{
                    .name = "press",
                    .value = .{ .scoped_link = .{ .link = link, .scope = scope } },
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
                if (recordFieldFromValue(link_value, field)) |field_value| break :blk field_value;
            }
            break :blk error.UnsupportedFieldAccess;
        };
    }

    fn evalBlock(self: *Session, allocator: std.mem.Allocator, block: flow_ir.Block, parent_scope: ?*const EvalScope) anyerror!Value {
        var bindings: std.ArrayList(RecordField) = .empty;
        defer bindings.deinit(allocator);
        const passed = if (parent_scope) |parent| parent.passed else null;

        var scope = EvalScope{
            .bindings = &.{},
            .parent = parent_scope,
            .passed = passed,
            .id = scopeIdBase(parent_scope, passed),
            .transparent_state_scope = true,
        };

        for (block.bindings) |binding| {
            const value = try self.evalNode(allocator, binding.value, &scope);
            const field = RecordField{
                .name = binding.name,
                .value = value,
            };
            try bindings.append(allocator, field);
            scope.bindings = bindings.items;
            scope.id = extendScopeId(scope.id, field);
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
                .transparent_state_scope = true,
            };
            return try self.evalNode(allocator, arm.result, &arm_scope);
        }
        return .none;
    }

    fn evalLinkedValue(self: *Session, allocator: std.mem.Allocator, linked: flow_ir.LinkedValue, scope: ?*const EvalScope) anyerror!Value {
        const raw_value = try self.evalNode(allocator, linked.value, scope);
        const value = switch (raw_value) {
            .scoped_node => |deferred| try self.evalNode(allocator, deferred.node_id, deferred.scope),
            else => raw_value,
        };
        const target_ref = try self.resolveLinkedTargetRef(allocator, linked.target, scope);
        const link = target_ref.link;
        const event_scope = target_ref.scope;
        return switch (value) {
            .stripe => |stripe| blk: {
                const rebound = try allocator.create(StripeValue);
                rebound.* = stripe.*;
                rebound.hovered_link = link;
                rebound.event_scope = try captureControlScope(allocator, event_scope);
                break :blk .{ .stripe = rebound };
            },
            .label => |label| blk: {
                const rebound = try allocator.create(LabelValue);
                rebound.* = label.*;
                rebound.double_click_link = link;
                rebound.event_scope = try captureControlScope(allocator, event_scope);
                break :blk .{ .label = rebound };
            },
            .checkbox => |checkbox| blk: {
                const rebound = try allocator.create(CheckboxValue);
                rebound.* = checkbox.*;
                rebound.click_link = link;
                rebound.event_scope = try captureControlScope(allocator, event_scope);
                break :blk .{ .checkbox = rebound };
            },
            .button => |button| blk: {
                const rebound = try allocator.create(ButtonValue);
                rebound.* = button.*;
                rebound.press_link = link;
                rebound.event_scope = try captureControlScope(allocator, event_scope);
                break :blk .{ .button = rebound };
            },
            .text_input => |input| blk: {
                const rebound = try allocator.create(TextInputValue);
                rebound.* = input.*;
                if (input.change_link != null) rebound.change_link = link;
                if (input.key_link != null) rebound.key_link = link;
                if (input.blur_link != null) rebound.blur_link = link;
                if (input.focus_link != null) rebound.focus_link = link;
                rebound.event_scope = try captureControlScope(allocator, event_scope);
                break :blk .{ .text_input = rebound };
            },
            .select => |select| blk: {
                const rebound = try allocator.create(SelectValue);
                rebound.* = select.*;
                rebound.change_link = link;
                rebound.event_scope = try captureControlScope(allocator, event_scope);
                break :blk .{ .select = rebound };
            },
            .slider => |slider| blk: {
                const rebound = try allocator.create(SliderValue);
                rebound.* = slider.*;
                rebound.change_link = link;
                rebound.event_scope = try captureControlScope(allocator, event_scope);
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
            .parent = scope,
            .passed = passed,
            .id = deriveScopeId(scope, bindings, passed),
        };
        return try self.evalNode(allocator, function.body, &function_scope);
    }

    fn styleBoolField(self: *Session, allocator: std.mem.Allocator, value: Value, name: []const u8) anyerror!bool {
        const field = recordFieldFromValue(value, name) orelse return false;
        return valueAsBoolLoose(try self.materializeStyleValue(allocator, field));
    }

    fn styleHasOutline(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror!bool {
        const raw_outline = recordFieldFromValue(value, "outline") orelse return false;
        const outline = try self.materializeStyleValue(allocator, raw_outline);
        return switch (outline) {
            .record => true,
            .symbol => |symbol| !std.mem.eql(u8, symbol, "NoOutline"),
            .text => |text| text.len != 0 and !std.mem.eql(u8, text, "NoOutline"),
            .none => false,
            else => valueAsBoolLoose(outline),
        };
    }

    fn materializeStyleValue(self: *Session, allocator: std.mem.Allocator, value: Value) anyerror!Value {
        return switch (value) {
            .scoped_node => |deferred| try self.evalNode(allocator, deferred.node_id, deferred.scope),
            .binding_ref => |binding_id| try self.evalNode(allocator, self.flow.bindings[binding_id].node, null),
            else => value,
        };
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
            .modulo => .{ .number = @mod(try valueAsNumber(lhs), try valueAsNumber(rhs)) },
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
        const op = self.builtinOp(node_id);
        if (op == .document_new or op == .scene_new) {
            const root_node = findNamed(call.named, "root") orelse if (call.positional.len != 0) call.positional[0] else return error.MissingRootArg;
            const document = try allocator.create(DocumentValue);
            document.* = .{ .root = try self.evalNode(allocator, root_node, scope) };
            return .{ .document = document };
        }
        if (op == .terminal_new) {
            const root_node = findNamed(call.named, "root") orelse if (call.positional.len != 0) call.positional[0] else return error.MissingRootArg;
            const loop_node = findNamed(call.named, "loop") orelse return error.MissingArgument;
            const terminal = try allocator.create(TerminalValue);
            terminal.* = .{
                .root = try self.evalNode(allocator, root_node, scope),
                .loop = try self.evalNode(allocator, loop_node, scope),
            };
            return .{ .terminal = terminal };
        }
        if (op == .element_svg) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const children_node = findNamed(call.named, "children") orelse return error.MissingItemsArg;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, &element_scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, children_node, &element_scope),
                .click_link = try self.resolveElementEventLink(element_node, "click", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (op == .element_svg_circle) {
            const container = try allocator.create(ContainerValue);
            container.* = .{ .child = .none };
            return .{ .container = container };
        }
        if (op == .element_stack) {
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
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .stripe = stripe };
        }
        if (op == .duration) {
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
        if (op == .terminal_columns) {
            return .{ .number = @floatFromInt(self.terminal_columns) };
        }
        if (op == .terminal_rows) {
            return .{ .number = @floatFromInt(self.terminal_rows) };
        }
        if (op == .router_route) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            return self.route_value;
        }
        if (op == .router_go_to) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            return self.route_value;
        }
        if (op == .theme_geometry) {
            return try themeGeometryValueForScope(self, allocator, scope);
        }
        if (op == .theme_lights) {
            return try themeLightsValueForScope(self, allocator, scope);
        }
        if (op == .theme_material or op == .theme_font or op == .theme_text) {
            const fields = try allocator.alloc(RecordField, 5);
            fields[0] = .{ .name = "color", .value = .{ .symbol = "DefaultColor" } };
            fields[1] = .{ .name = "gloss", .value = .{ .number = 0.2 } };
            fields[2] = .{ .name = "metal", .value = .{ .number = 0.0 } };
            fields[3] = .{ .name = "size", .value = .{ .number = 16.0 } };
            fields[4] = .{ .name = "weight", .value = .{ .symbol = "Regular" } };
            return .{ .record = fields };
        }
        if (op == .theme_number) {
            return .{ .number = 8.0 };
        }
        if (op == .theme_spring_range) {
            const fields = try allocator.alloc(RecordField, 2);
            fields[0] = .{ .name = "extend", .value = .{ .number = 6.0 } };
            fields[1] = .{ .name = "compress", .value = .{ .number = 4.0 } };
            return .{ .record = fields };
        }
        if (op == .light_prefixed) {
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
        if (op == .element_stripe or op == .scene_element_stripe) {
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
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .stripe = stripe };
        }
        if (op == .element_label or op == .scene_element_label) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const label_node = findNamed(call.named, "label") orelse return error.MissingLabelArg;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, &element_scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const label = try allocator.create(LabelValue);
            label.* = .{
                .label = try self.evalNode(allocator, label_node, &element_scope),
                .click_link = try self.resolveElementEventLink(element_node, "click", scope),
                .double_click_link = try self.resolveElementEventLink(element_node, "double_click", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .label = label };
        }
        if (op == .element_container) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const child_node = findNamed(call.named, "child") orelse return error.MissingArgument;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, child_node, &element_scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (op == .scene_element_block) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const child_node = findNamed(call.named, "child") orelse return error.MissingArgument;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, child_node, &element_scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (op == .element_paragraph or op == .scene_element_paragraph) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const contents_node = findNamed(call.named, "contents") orelse return error.MissingArgument;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const container = try allocator.create(ContainerValue);
            container.* = .{
                .child = try self.evalNode(allocator, contents_node, &element_scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .container = container };
        }
        if (op == .element_checkbox or op == .scene_element_checkbox) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const icon_node = findNamed(call.named, "icon") orelse return error.MissingArgument;
            const label_node = findNamed(call.named, "label");
            const checked_node = findNamed(call.named, "checked");
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, &element_scope) else .none;
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
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .checkbox = checkbox };
        }
        if (op == .scene_element_text) {
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
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .label = label };
        }
        if (op == .text_empty) {
            return .{ .text = "" };
        }
        if (op == .text_space) {
            return .{ .text = " " };
        }
        if (op == .text_to_number) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| .{ .number = std.fmt.parseFloat(f64, text) catch std.math.nan(f64) },
                .symbol => |text| .{ .number = std.fmt.parseFloat(f64, text) catch std.math.nan(f64) },
                .number => value,
                else => .{ .number = std.math.nan(f64) },
            };
        }
        if (op == .text_trim) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| .{ .text = try allocator.dupe(u8, std.mem.trim(u8, text, " \n\r\t")) },
                .symbol => |text| .{ .text = try allocator.dupe(u8, std.mem.trim(u8, text, " \n\r\t")) },
                else => .{ .text = "" },
            };
        }
        if (op == .text_is_not_empty) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| booleanValue(text.len != 0),
                .symbol => |text| booleanValue(text.len != 0),
                else => booleanValue(false),
            };
        }
        if (op == .text_is_empty) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const value = try self.evalNode(allocator, value_node, scope);
            return switch (value) {
                .text => |text| booleanValue(text.len == 0),
                .symbol => |text| booleanValue(text.len == 0),
                else => booleanValue(true),
            };
        }
        if (op == .text_length) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
            return .{ .number = @floatFromInt(text.len) };
        }
        if (op == .text_find) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const search_node = findNamed(call.named, "search") orelse return error.MissingArgument;
            const haystack = try valueAsText(try self.evalNode(allocator, value_node, scope));
            const needle = try valueAsText(try self.evalNode(allocator, search_node, scope));
            return .{ .number = if (std.mem.indexOf(u8, haystack, needle)) |index| @floatFromInt(index) else -1 };
        }
        if (op == .text_substring) {
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
        if (op == .text_repeat) {
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
        if (op == .text_join) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const items = try listItemsFromValue(try self.evalNode(allocator, value_node, scope));

            var output: std.ArrayList(u8) = .empty;
            defer output.deinit(allocator);

            for (items) |item| {
                try output.appendSlice(allocator, try valueAsText(item));
            }
            return .{ .text = try output.toOwnedSlice(allocator) };
        }
        if (op == .text_starts_with) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const prefix_node = findNamed(call.named, "prefix") orelse return error.MissingArgument;
            const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
            const prefix = try valueAsText(try self.evalNode(allocator, prefix_node, scope));
            return booleanValue(std.mem.startsWith(u8, text, prefix));
        }
        if (op == .bool_not) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            return booleanValue(!try valueAsBool(try self.evalNode(allocator, value_node, scope)));
        }
        if (op == .bool_toggle) {
            const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            return booleanValue(try valueAsBool(try self.evalNode(allocator, value_node, scope)));
        }
        if (op == .bool_or) {
            const lhs_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const rhs_node = findNamed(call.named, "that") orelse return error.MissingArgument;
            const lhs = try valueAsBool(try self.evalNode(allocator, lhs_node, scope));
            const rhs = try valueAsBool(try self.evalNode(allocator, rhs_node, scope));
            return booleanValue(lhs or rhs);
        }
        if (op == .bool_and) {
            const lhs_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const rhs_node = findNamed(call.named, "that") orelse return error.MissingArgument;
            const lhs = try valueAsBool(try self.evalNode(allocator, lhs_node, scope));
            const rhs = try valueAsBool(try self.evalNode(allocator, rhs_node, scope));
            return booleanValue(lhs and rhs);
        }
        if (op == .element_button or op == .scene_element_button) {
            const label_node = findNamed(call.named, "label") orelse return error.MissingLabelArg;
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, &element_scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const button = try allocator.create(ButtonValue);
            button.* = .{
                .label = try self.evalNode(allocator, label_node, &element_scope),
                .press_link = try self.resolveElementEventLink(element_node, "press", scope),
                .hovered_link = try self.resolveElementEventLink(element_node, "hovered", scope),
                .disabled = try self.styleBoolField(allocator, style_value, "disabled"),
                .outlined = try self.styleHasOutline(allocator, style_value),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .button = button };
        }
        if (op == .element_text_input or op == .scene_element_text_input) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const text_node = findNamed(call.named, "text") orelse return error.MissingArgument;
            const style_node = findNamed(call.named, "style");
            const placeholder_node = findNamed(call.named, "placeholder");
            const focus_node = findNamed(call.named, "focus");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, &element_scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const input = try allocator.create(TextInputValue);
            input.* = .{
                .text = try self.evalNode(allocator, text_node, &element_scope),
                .placeholder = if (placeholder_node) |node| try self.evalNode(allocator, node, &element_scope) else .none,
                .change_link = try self.resolveElementEventLink(element_node, "change", scope),
                .key_link = try self.resolveElementEventLink(element_node, "key_down", scope),
                .blur_link = try self.resolveElementEventLink(element_node, "blur", scope),
                .focus_link = try self.resolveElementEventLink(element_node, "focus", scope),
                .focused = if (focus_node) |node| valueAsBoolLoose(try self.evalNode(allocator, node, &element_scope)) else false,
                .disabled = try self.styleBoolField(allocator, style_value, "disabled"),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .text_input = input };
        }
        if (op == .element_select) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const selected_node = findNamed(call.named, "selected") orelse return error.MissingArgument;
            const style_node = findNamed(call.named, "style");
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const style_value = if (style_node) |node| try self.evalNode(allocator, node, &element_scope) else .none;
            const style_size = terminalStyleSizeFromValue(style_value);
            const select = try allocator.create(SelectValue);
            select.* = .{
                .selected = try self.evalNode(allocator, selected_node, &element_scope),
                .change_link = try self.resolveElementEventLink(element_node, "change", scope),
                .terminal_width = style_size.width,
                .terminal_height = style_size.height,
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .select = select };
        }
        if (op == .element_link or op == .scene_element_link) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const label_node = findNamed(call.named, "label") orelse return error.MissingLabelArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const label = try allocator.create(LabelValue);
            label.* = .{ .label = try self.evalNode(allocator, label_node, &element_scope) };
            label.terminal_bindings = extractTerminalMetadata(element_value);
            label.event_scope = try captureControlScope(allocator, &element_scope);
            return .{ .label = label };
        }
        if (op == .reference) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            return switch (element_value) {
                .stripe,
                .label,
                .container,
                .checkbox,
                .button,
                .text_input,
                .select,
                .slider,
                => element_value,
                .link => |link| blk: {
                    try self.recordLinkDependencies(link, scope, false);
                    const resolved = self.getLinkValue(link, scope) orelse break :blk .none;
                    break :blk switch (resolved) {
                        .stripe,
                        .label,
                        .container,
                        .checkbox,
                        .button,
                        .text_input,
                        .select,
                        .slider,
                        => resolved,
                        .record => error.SourceRecordIsNotElementValue,
                        else => error.ExpectedElementValue,
                    };
                },
                .scoped_link => |scoped| blk: {
                    try self.recordLinkDependencies(scoped.link, scoped.scope, false);
                    const resolved = self.getLinkValue(scoped.link, scoped.scope) orelse break :blk .none;
                    break :blk switch (resolved) {
                        .stripe,
                        .label,
                        .container,
                        .checkbox,
                        .button,
                        .text_input,
                        .select,
                        .slider,
                        => resolved,
                        .record => error.SourceRecordIsNotElementValue,
                        else => error.ExpectedElementValue,
                    };
                },
                .record => error.SourceRecordIsNotElementValue,
                else => error.ExpectedElementValue,
            };
        }
        if (op == .assets_icon) {
            const icons = try allocator.alloc(RecordField, 2);
            icons[0] = .{ .name = "checkbox_completed", .value = .{ .text = "X" } };
            icons[1] = .{ .name = "checkbox_active", .value = .{ .text = "O" } };
            return .{ .record = icons };
        }
        if (op == .element_slider) {
            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
            const element_value = try self.evalNode(allocator, element_node, scope);
            var element_scope = try withLocalBinding(allocator, scope, "element", element_value);
            const slider = try allocator.create(SliderValue);
            slider.* = .{
                .change_link = try self.resolveElementEventLink(element_node, "change", scope),
                .terminal_bindings = extractTerminalMetadata(element_value),
                .event_scope = try captureControlScope(allocator, &element_scope),
            };
            return .{ .slider = slider };
        }
        if (op == .math_sum) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.sum_inited[node_id]) return .none;
            return .{ .number = self.sum_values[node_id] };
        }
        if (op == .math_min) {
            const lhs = if (call.positional.len != 0) try self.numberFromNode(call.positional[0], scope) else return error.MissingArgument;
            const rhs_node = findNamed(call.named, "b") orelse return error.MissingArgument;
            const rhs = try self.numberFromNode(rhs_node, scope);
            return .{ .number = @min(lhs, rhs) };
        }
        if (op == .math_round) {
            const value = if (call.positional.len != 0) try self.numberFromNode(call.positional[0], scope) else return error.MissingArgument;
            return .{ .number = @round(value) };
        }
        if (op == .ulid_generate) {
            var key = if (self.persist_ids.len != 0 and node_id < self.persist_ids.len and self.persist_ids[node_id] != 0)
                self.persist_ids[node_id]
            else
                @as(u64, node_id);
            if (normalizedStateScope(scope)) |frame| key = std.hash.Wyhash.hash(key, std.mem.asBytes(&frame.id));
            return .{ .text = try std.fmt.allocPrint(allocator, "ulid-{x}", .{key}) };
        }
        if (op == .log_info or op == .log_error) {
            if (call.positional.len == 0) return .none;
            return try self.evalNode(allocator, call.positional[0], scope);
        }
        if (op == .list_append) {
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
        if (op == .list_clear) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.list_inited[node_id]) {
                const base_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                return try self.evalNode(allocator, base_node, scope);
            }
            return self.list_values[node_id];
        }
        if (op == .list_remove) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.list_inited[node_id]) {
                const base_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                const base_value = try self.evalNode(allocator, base_node, scope);
                return try self.filterRemovedItems(self.arena.allocator(), base_value, self.list_remove_tombstones[node_id]);
            }
            return self.list_values[node_id];
        }
        if (op == .list_remove_last) {
            try self.recordStateDependency(.{ .node_id = node_id, .scope_id = 0 });
            if (!self.list_inited[node_id]) {
                const base_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                return try self.evalNode(allocator, base_node, scope);
            }
            return self.list_values[node_id];
        }
        if (op == .list_count) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            return switch (list_value) {
                .list => |items| .{ .number = @floatFromInt(items.len) },
                else => error.ExpectedListValue,
            };
        }
        if (op == .list_is_empty) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            return switch (list_value) {
                .list => |items| booleanValue(items.len == 0),
                else => error.ExpectedListValue,
            };
        }
        if (op == .list_is_not_empty) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            return switch (list_value) {
                .list => |items| booleanValue(items.len != 0),
                else => error.ExpectedListValue,
            };
        }
        if (op == .list_get) {
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
        if (op == .list_range) {
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
        if (op == .list_map) {
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
        if (op == .list_retain) {
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
        if (op == .list_any or op == .list_every) {
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
            const want_all = op == .list_every;
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
        if (op == .list_sum) {
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
        if (op == .list_latest) {
            const list_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
            const list_value = try self.evalNode(allocator, list_node, scope);
            const items = switch (list_value) {
                .list => |items| items,
                else => return error.ExpectedListValue,
            };
            return if (items.len == 0) .none else items[items.len - 1];
        }
        if (op == .stream_pulses) return .none;
        if (op == .stream_skip) {
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
        if (op == .timer_interval) return .none;
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
            .builtin_call => switch (self.builtinOp(node_id)) {
                .stream_skip, .stream_pulses, .timer_interval => false,
                else => true,
            },
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

    fn appendRenderedNode(
        self: *Session,
        output: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        node_id: flow_ir.NodeId,
        scope: ?*const EvalScope,
    ) anyerror!void {
        const node = self.flow.nodes[node_id];
        switch (node.kind) {
            .number => |number| {
                var buffer: [64]u8 = undefined;
                const text = if (std.math.isFinite(number.value) and @round(number.value) == number.value)
                    try std.fmt.bufPrint(&buffer, "{d}", .{@as(i64, @intFromFloat(number.value))})
                else
                    try std.fmt.bufPrint(&buffer, "{d}", .{number.value});
                try output.appendSlice(allocator, text);
                return;
            },
            .atom => |text| {
                try output.appendSlice(allocator, text);
                return;
            },
            .symbol => |text| {
                try output.appendSlice(allocator, text);
                return;
            },
            .binding_ref => |binding_id| {
                try self.appendRenderedNode(output, allocator, self.flow.bindings[binding_id].node, null);
                return;
            },
            .local_ref => |name| {
                if (lookupLocal(scope, name)) |value| {
                    try self.appendRenderedValue(output, allocator, value);
                    return;
                }
            },
            .access => |access| {
                if (try self.resolveStaticFieldNode(access.target, access.field)) |field_node| {
                    if (!self.nodeNeedsScope(field_node) and !self.nodeNeedsDeferredField(field_node)) {
                        try self.appendRenderedNode(output, allocator, field_node, scope);
                        return;
                    }
                }
                const target_value = try self.evalNode(allocator, access.target, scope);
                if (target_value == .record) {
                    for (target_value.record) |field| {
                        if (std.mem.eql(u8, field.name, access.field)) {
                            try self.appendRenderedValue(output, allocator, field.value);
                            return;
                        }
                    }
                }
            },
            .text => |parts| {
                for (parts) |part| try self.appendRenderedNode(output, allocator, part, scope);
                return;
            },
            .list => |list| {
                for (list.items) |item| try self.appendRenderedNode(output, allocator, item, scope);
                return;
            },
            .block => |block| {
                const passed = if (scope) |parent| parent.passed else null;
                const bindings = try allocator.alloc(RecordField, block.bindings.len);

                var block_scope = EvalScope{
                    .bindings = bindings[0..0],
                    .parent = scope,
                    .passed = passed,
                    .id = scopeIdBase(scope, passed),
                    .transparent_state_scope = true,
                };

                for (block.bindings, 0..) |binding, index| {
                    const value = try self.evalNode(allocator, binding.value, &block_scope);
                    const field = RecordField{
                        .name = binding.name,
                        .value = value,
                    };
                    bindings[index] = field;
                    block_scope.bindings = bindings[0 .. index + 1];
                    block_scope.id = extendScopeId(block_scope.id, field);
                }

                try self.appendRenderedNode(output, allocator, block.result, &block_scope);
                return;
            },
            .when => |when| {
                const input = try self.evalNode(allocator, when.input, scope);
                for (when.arms) |arm| {
                    const pattern = try self.evalNode(allocator, arm.pattern, scope);
                    const capture = try patternBinding(allocator, self.flow, arm.pattern, input, pattern);
                    if (!matchesPattern(input, pattern) and capture == null) continue;

                    if (capture) |binding| {
                        var binding_storage = [1]RecordField{binding};
                        const passed = if (scope) |parent| parent.passed else null;
                        var arm_scope = EvalScope{
                            .bindings = binding_storage[0..],
                            .parent = scope,
                            .passed = passed,
                            .id = extendScopeId(scopeIdBase(scope, passed), binding_storage[0]),
                            .transparent_state_scope = true,
                        };
                        try self.appendRenderedNode(output, allocator, arm.result, &arm_scope);
                    } else {
                        try self.appendRenderedNode(output, allocator, arm.result, scope);
                    }
                    return;
                }
                return;
            },
            .user_call => |call| {
                const function = self.flow.functions[call.function];
                var bindings = try allocator.alloc(RecordField, function.params.len);
                if (call.named.len == 0 and call.positional.len == function.params.len) {
                    for (call.positional, 0..) |argument, index| {
                        bindings[index] = .{
                            .name = function.params[index],
                            .value = try self.evalNode(allocator, argument, scope),
                        };
                        if (bindings[index].value == .none) return;
                    }
                } else {
                    var filled = try allocator.alloc(bool, function.params.len);
                    @memset(filled, false);

                    var positional_index: usize = 0;
                    for (call.positional) |argument| {
                        if (positional_index >= function.params.len) return error.TooManyArguments;
                        bindings[positional_index] = .{
                            .name = function.params[positional_index],
                            .value = try self.evalNode(allocator, argument, scope),
                        };
                        if (bindings[positional_index].value == .none) return;
                        filled[positional_index] = true;
                        positional_index += 1;
                    }

                    for (call.named) |argument| {
                        const param_index = findParamIndex(function.params, argument.name) orelse return error.UnknownFunctionArgument;
                        bindings[param_index] = .{
                            .name = function.params[param_index],
                            .value = try self.evalNode(allocator, argument.value, scope),
                        };
                        if (bindings[param_index].value == .none) return;
                        filled[param_index] = true;
                    }

                    for (filled) |is_filled| {
                        if (!is_filled) return error.MissingFunctionArgument;
                    }
                }

                const passed = if (call.pass_context) |pass_context|
                    try self.evalNode(allocator, pass_context, scope)
                else if (scope) |parent|
                    parent.passed
                else
                    null;

                const function_scope = EvalScope{
                    .bindings = bindings,
                    .parent = scope,
                    .passed = passed,
                    .id = deriveScopeId(scope, bindings, passed),
                };
                try self.appendRenderedNode(output, allocator, function.body, &function_scope);
                return;
            },
            .then_value => |then_value| {
                try self.appendRenderedNode(output, allocator, then_value.value, scope);
                return;
            },
            .builtin_call => |call| {
                const op = self.builtinOp(node_id);
                switch (op) {
                    .document_new, .scene_new, .terminal_new => {
                        const root_node = findNamed(call.named, "root") orelse if (call.positional.len != 0) call.positional[0] else return error.MissingRootArg;
                        try self.appendRenderedNode(output, allocator, root_node, scope);
                        return;
                    },
                    .text_substring => {
                        const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                        const start_node = findNamed(call.named, "start") orelse return error.MissingArgument;
                        const length_node = findNamed(call.named, "length") orelse return error.MissingArgument;
                        const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
                        const start = try valueAsIndex(try self.evalNode(allocator, start_node, scope));
                        const length = try valueAsIndex(try self.evalNode(allocator, length_node, scope));
                        if (start >= text.len or length == 0) return;
                        const end = @min(start + length, text.len);
                        try output.appendSlice(allocator, text[start..end]);
                        return;
                    },
                    .text_repeat => {
                        const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                        const times_node = findNamed(call.named, "times") orelse return error.MissingArgument;
                        const text = try valueAsText(try self.evalNode(allocator, value_node, scope));
                        const times = try valueAsIndex(try self.evalNode(allocator, times_node, scope));
                        var index: usize = 0;
                        while (index < times) : (index += 1) try output.appendSlice(allocator, text);
                        return;
                    },
                    .text_join => {
                        const value_node = if (call.positional.len != 0) call.positional[0] else return error.MissingArgument;
                        try self.appendJoinedTextNode(output, allocator, value_node, scope);
                        return;
                    },
                    .element_stripe, .scene_element_stripe, .element_stack => {
                        const items_node = switch (op) {
                            .element_stack => findNamed(call.named, "layers") orelse return error.MissingItemsArg,
                            else => findNamed(call.named, "items") orelse return error.MissingItemsArg,
                        };
                        if (self.nodeNeedsScope(items_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, items_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, items_node, scope);
                        }
                        return;
                    },
                    .element_label, .scene_element_label, .scene_element_text => {
                        const label_node = if (op == .scene_element_text)
                            (findNamed(call.named, "text") orelse return error.MissingLabelArg)
                        else
                            (findNamed(call.named, "label") orelse return error.MissingLabelArg);
                        if (self.nodeNeedsScope(label_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, label_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, label_node, scope);
                        }
                        return;
                    },
                    .element_container, .scene_element_block => {
                        const child_node = findNamed(call.named, "child") orelse return error.MissingArgument;
                        if (self.nodeNeedsScope(child_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, child_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, child_node, scope);
                        }
                        return;
                    },
                    .element_paragraph, .scene_element_paragraph, .element_svg => {
                        const child_node = switch (op) {
                            .element_svg => findNamed(call.named, "children") orelse return error.MissingItemsArg,
                            else => findNamed(call.named, "contents") orelse return error.MissingArgument,
                        };
                        if (self.nodeNeedsScope(child_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, child_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, child_node, scope);
                        }
                        return;
                    },
                    .element_checkbox, .scene_element_checkbox => {
                        const icon_node = findNamed(call.named, "icon") orelse return error.MissingArgument;
                        if (self.nodeNeedsScope(icon_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, icon_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, icon_node, scope);
                        }
                        return;
                    },
                    .element_button, .scene_element_button => {
                        const label_node = findNamed(call.named, "label") orelse return error.MissingLabelArg;
                        if (self.nodeNeedsScope(label_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, label_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, label_node, scope);
                        }
                        return;
                    },
                    .element_text_input, .scene_element_text_input => {
                        const text_node = findNamed(call.named, "text") orelse return error.MissingArgument;
                        if (self.nodeNeedsScope(text_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, text_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, text_node, scope);
                        }
                        return;
                    },
                    .element_select => {
                        const selected_node = findNamed(call.named, "selected") orelse return error.MissingArgument;
                        if (self.nodeNeedsScope(selected_node)) {
                            const element_node = findNamed(call.named, "element") orelse return error.MissingElementArg;
                            const element_value = try self.evalNode(allocator, element_node, scope);
                            var binding_storage: [1]RecordField = undefined;
                            var element_scope = self.singleBindingScope(scope, "element", element_value, &binding_storage);
                            try self.appendRenderedNode(output, allocator, selected_node, &element_scope);
                        } else {
                            try self.appendRenderedNode(output, allocator, selected_node, scope);
                        }
                        return;
                    },
                    .text_empty => {
                        return;
                    },
                    .text_space => {
                        try output.append(allocator, ' ');
                        return;
                    },
                    else => {},
                }
            },
            else => {},
        }

        try self.appendRenderedValue(output, allocator, try self.evalNode(allocator, node_id, scope));
    }

    fn singleBindingScope(
        self: *Session,
        parent: ?*const EvalScope,
        name: []const u8,
        value: Value,
        storage: *[1]RecordField,
    ) EvalScope {
        _ = self;
        storage[0] = .{
            .name = name,
            .value = value,
        };
        const passed = if (parent) |frame| frame.passed else null;
        return .{
            .bindings = storage[0..],
            .parent = parent,
            .passed = passed,
            .id = extendScopeId(scopeIdBase(parent, passed), storage[0]),
        };
    }

    fn appendJoinedTextNode(
        self: *Session,
        output: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        node_id: flow_ir.NodeId,
        scope: ?*const EvalScope,
    ) anyerror!void {
        const node = self.flow.nodes[node_id];
        switch (node.kind) {
            .binding_ref => |binding_id| return try self.appendJoinedTextNode(output, allocator, self.flow.bindings[binding_id].node, null),
            .list => |list| {
                for (list.items) |item| try self.appendRenderedNode(output, allocator, item, scope);
                return;
            },
            .builtin_call => |call| {
                if (self.builtinOp(node_id) == .list_map) {
                    if (call.positional.len < 2) return error.MissingArgument;
                    const item_name = switch (self.flow.nodes[call.positional[1]].kind) {
                        .symbol => |text| text,
                        else => return error.MissingLocalBinding,
                    };
                    const mapper = findNamed(call.named, "new") orelse return error.MissingArgument;
                    if (try self.appendJoinedRangeMapNode(output, allocator, call.positional[0], item_name, mapper, scope)) return;
                    const list_value = try self.evalNode(allocator, call.positional[0], scope);
                    const items = switch (list_value) {
                        .list => |items| items,
                        else => return error.ExpectedListValue,
                    };
                    for (items) |item| {
                        var binding_storage: [1]RecordField = undefined;
                        var map_scope = self.singleBindingScope(scope, item_name, item, &binding_storage);
                        try self.appendRenderedNode(output, allocator, mapper, &map_scope);
                    }
                    return;
                }
            },
            else => {},
        }

        const items = try listItemsFromValue(try self.evalNode(allocator, node_id, scope));
        for (items) |item| try output.appendSlice(allocator, try valueAsText(item));
    }

    fn appendJoinedRangeMapNode(
        self: *Session,
        output: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        source_node: flow_ir.NodeId,
        item_name: []const u8,
        mapper: flow_ir.NodeId,
        scope: ?*const EvalScope,
    ) anyerror!bool {
        const node = self.flow.nodes[source_node];
        switch (node.kind) {
            .binding_ref => |binding_id| return try self.appendJoinedRangeMapNode(output, allocator, self.flow.bindings[binding_id].node, item_name, mapper, scope),
            .builtin_call => |call| {
                if (self.builtinOp(source_node) != .list_range) return false;
                const from_node = findNamed(call.named, "from") orelse return error.MissingArgument;
                const to_node = findNamed(call.named, "to") orelse return error.MissingArgument;
                const from_value = try valueAsIndex(try self.evalNode(allocator, from_node, scope));
                const to_value = try valueAsIndex(try self.evalNode(allocator, to_node, scope));
                if (to_value < from_value) return true;
                var current = from_value;
                while (current <= to_value) : (current += 1) {
                    var binding_storage: [1]RecordField = undefined;
                    var map_scope = self.singleBindingScope(scope, item_name, .{ .number = @floatFromInt(current) }, &binding_storage);
                    try self.appendRenderedNode(output, allocator, mapper, &map_scope);
                }
                return true;
            },
            else => return false,
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
            .slider, .link, .scoped_link, .none => {},
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
            .container => |container| try self.snapshotSizedBlock(
                allocator,
                try self.snapshotBlock(allocator, container.child),
                container.terminal_width,
                container.terminal_height,
            ),
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
            .container => |container| blk: {
                const button_index = if (container.click_link != null) blk_click: {
                    const next = counters.button;
                    counters.button += 1;
                    break :blk_click next;
                } else null;
                const child_size = try self.collectTerminalHitRegions(allocator, regions, counters, container.child, x, y);
                const width = @max(child_size.width, container.terminal_width);
                const height = @max(child_size.height, if (container.terminal_height == 0) @as(usize, 1) else container.terminal_height);
                if (button_index) |index| {
                    try regions.append(allocator, .{
                        .x = x,
                        .y = y,
                        .width = width,
                        .height = height,
                        .button_index = index,
                        .button_coordinate_payload = true,
                    });
                }
                break :blk .{ .width = width, .height = height };
            },
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
        checkbox,
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
            .checkbox => blk: {
                var links: std.ArrayList(ControlEventRef) = .empty;
                defer links.deinit(scratch.allocator());
                try collectCheckboxLinks(self, &links, scratch.allocator(), value);
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
            .checkbox => summary.clicks.items,
            .double_click => summary.double_clicks.items,
            .text_input => summary.text_inputs.items,
            .hover => summary.hovers.items,
        };
        return try controlLabelIndex(scratch.allocator(), items, label);
    }

    fn controlRefByLabel(self: *Session, allocator: std.mem.Allocator, kind: ControlKind, label: []const u8) !ControlEventRef {
        try self.flushPendingQueue();
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();

        const root_binding = self.flow.root_binding orelse return error.MissingDocumentRoot;
        const value = try self.evalNode(scratch.allocator(), self.flow.bindings[root_binding].node, null);

        var summary: ControlSummary = .{};
        defer summary.deinit(scratch.allocator());
        try self.collectControlSummary(scratch.allocator(), &summary, value);

        var links: std.ArrayList(ControlEventRef) = .empty;
        defer links.deinit(scratch.allocator());
        const items = switch (kind) {
            .click => blk: {
                try collectButtonLinks(self, &links, scratch.allocator(), value);
                break :blk summary.clicks.items;
            },
            .checkbox => blk: {
                try collectCheckboxLinks(self, &links, scratch.allocator(), value);
                break :blk summary.clicks.items;
            },
            .double_click => blk: {
                try collectLabelDoubleClickLinks(self, &links, scratch.allocator(), value);
                break :blk summary.double_clicks.items;
            },
            .text_input => blk: {
                try collectTextInputLinks(self, &links, scratch.allocator(), value);
                break :blk summary.text_inputs.items;
            },
            .hover => blk: {
                try collectHoverLinks(self, &links, scratch.allocator(), value);
                break :blk summary.hovers.items;
            },
        };
        const index = try controlLabelIndex(scratch.allocator(), items, label);
        if (index >= links.items.len) return error.UnknownControlLabel;
        return try cloneControlEventRefForCache(self.arena.allocator(), links.items[index]);
    }

    fn controlLabelIndex(allocator: std.mem.Allocator, items: []const []const u8, label: []const u8) !usize {
        for (items, 0..) |item, index| {
            if (std.mem.eql(u8, item, label)) return index;
        }
        const normalized_label = try normalizedControlLabelAlloc(allocator, label);
        for (items, 0..) |item, index| {
            const normalized_item = try normalizedControlLabelAlloc(allocator, item);
            if (std.mem.eql(u8, normalized_item, normalized_label)) return index;
        }
        if (normalized_label.len > 3) {
            for (items, 0..) |item, index| {
                const normalized_item = try normalizedControlLabelAlloc(allocator, item);
                if (std.mem.indexOf(u8, normalized_item, normalized_label) != null) return index;
            }
        }
        return error.UnknownControlLabel;
    }

    fn normalizedControlLabelAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        var index: usize = 0;
        while (index < text.len) {
            if (std.mem.startsWith(u8, text[index..], "NoElement")) {
                index += "NoElement".len;
                continue;
            }
            const byte = text[index];
            switch (byte) {
                ' ', '\t', '\r', '\n' => {},
                else => try out.append(allocator, byte),
            }
            index += 1;
        }
        return try out.toOwnedSlice(allocator);
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
        const value = try self.evalNode(self.scratch_arena.allocator(), call.positional[0], scope);
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
        for (1..@as(usize, @intCast(count)) + 1) |pulse_index| {
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
                if (self.builtinOp(node_id) == .stream_skip and !self.skip_inited[node_id]) {
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
                switch (self.builtinOp(node_id)) {
                    .stream_pulses => try self.emitPulses(node_id, call, scope),
                    .stream_skip => try self.primeScopedStream(node_id, scope),
                    else => {},
                }
            },
            else => {},
        }
    }

    fn initSkipNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, scope: ?*const EvalScope) anyerror!void {
        const source = call.positional[0];
        const limit = try self.skipLimit(call, scope);
        self.skip_limits[node_id] = limit;
        self.skip_limit_inited[node_id] = true;
        if (try self.initialStreamValue(allocator, source, scope)) |value| {
            if (limit == 0) {
                self.skip_values[node_id] = value;
                self.skip_inited[node_id] = true;
                self.noteTopLevelMutation(node_id);
            } else {
                self.skip_seen[node_id] = 1;
            }
        }
        try self.logf("init skip n{d} seen={d} limit={d}", .{ node_id, self.skip_seen[node_id], limit });
    }

    fn processSkipPulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, payload: PulsePayload, scope: ?*const EvalScope) anyerror!void {
        const limit = if (self.skip_limit_inited[node_id]) self.skip_limits[node_id] else try self.skipLimit(call, scope);
        if (self.skip_seen[node_id] < limit) {
            self.skip_seen[node_id] += 1;
            try self.logf("skip n{d} ignored pulse {d}/{d}", .{ node_id, self.skip_seen[node_id], limit });
            return;
        }

        self.skip_values[node_id] = try valueFromPulsePayload(self, self.arena.allocator(), payload, scope);
        self.skip_inited[node_id] = true;
        self.noteTopLevelMutation(node_id);
        try self.logf("skip n{d} emitted", .{node_id});
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn initListAppendNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        if (self.list_inited[node_id]) {
            try self.logf("restore list_append n{d}", .{node_id});
            return;
        }
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
        self.list_inited[node_id] = true;
        self.noteTopLevelMutation(node_id);
        try self.logf("init list_append n{d}", .{node_id});
    }

    fn initListClearNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        if (self.list_inited[node_id]) {
            try self.logf("restore list_clear n{d}", .{node_id});
            return;
        }
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
        self.list_inited[node_id] = true;
        self.noteTopLevelMutation(node_id);
        try self.logf("init list_clear n{d}", .{node_id});
    }

    fn initListRemoveNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        if (self.list_inited[node_id]) {
            try self.logf("restore list_remove n{d}", .{node_id});
            return;
        }
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try self.filterRemovedItems(self.arena.allocator(), base, self.list_remove_tombstones[node_id]);
        self.list_inited[node_id] = true;
        self.noteTopLevelMutation(node_id);
        try self.logf("init list_remove n{d}", .{node_id});
    }

    fn initListRemoveLastNode(self: *Session, allocator: std.mem.Allocator, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall) anyerror!void {
        if (call.positional.len == 0) return error.MissingArgument;
        if (self.list_inited[node_id]) {
            try self.logf("restore list_remove_last n{d}", .{node_id});
            return;
        }
        const base = try self.evalNode(allocator, call.positional[0], null);
        self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
        self.list_inited[node_id] = true;
        self.noteTopLevelMutation(node_id);
        try self.logf("init list_remove_last n{d}", .{node_id});
    }

    fn processListAppendPulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, pulse: Pulse) anyerror!void {
        const source = pulse.source;
        if (call.positional.len == 0) return error.MissingArgument;
        const base_source = try self.listSourceDependency(call.positional[0]);
        if (source == base_source) {
            const base = try self.evalNode(self.arena.allocator(), call.positional[0], null);
            self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
            self.list_inited[node_id] = true;
            self.noteTopLevelMutation(node_id);
            try self.logf("list_append n{d} mirror", .{node_id});
            try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
            return;
        }

        const item = if (findNamed(call.named, "item")) |item_node| blk: {
            if (try self.valueTriggerSource(item_node) != source) return;
            if (!self.pulseMatchesTriggerEventForSource(item_node, source, pulse)) return;
            break :blk try self.evalNode(self.arena.allocator(), item_node, null);
        } else if (findNamed(call.named, "on")) |on_node| blk: {
            if (try self.valueTriggerSource(on_node) != source) return;
            if (!self.pulseMatchesTriggerEventForSource(on_node, source, pulse)) return;
            break :blk try self.evalNode(self.arena.allocator(), on_node, null);
        } else return error.MissingArgument;
        if (item == .none) return;
        const current = try listItemsFromValue(self.list_values[node_id]);
        const next = try self.arena.allocator().alloc(Value, current.len + 1);
        @memcpy(next[0..current.len], current);
        next[current.len] = item;
        self.list_values[node_id] = .{ .list = next };
        self.list_inited[node_id] = true;
        self.noteTopLevelMutation(node_id);
        try self.logf("list_append n{d} len={d}", .{ node_id, next.len });
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn processListClearPulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, pulse: Pulse) anyerror!void {
        const source = pulse.source;
        if (call.positional.len == 0) return error.MissingArgument;
        const source_dep = try self.listSourceDependency(call.positional[0]);
        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
        if (source == source_dep) {
            const base = try self.evalNode(self.arena.allocator(), call.positional[0], null);
            self.list_values[node_id] = try cloneListValue(self.arena.allocator(), base);
            self.list_inited[node_id] = true;
            self.noteTopLevelMutation(node_id);
            try self.logf("list_clear n{d} mirror", .{node_id});
            try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
            return;
        }
        if (try self.valueTriggerSource(on_node) != source) return;
        if (!self.pulseMatchesTriggerEventForSource(on_node, source, pulse)) return;
        self.list_values[node_id] = .{ .list = &.{} };
        self.list_inited[node_id] = true;
        try self.resetListPipelineState(call.positional[0]);
        self.noteTopLevelMutation(node_id);
        try self.logf("list_clear n{d} cleared", .{node_id});
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn resetListPipelineState(self: *Session, node_id: flow_ir.NodeId) anyerror!void {
        const resolved_node = switch (self.flow.nodes[node_id].kind) {
            .binding_ref => |binding_id| self.flow.bindings[binding_id].node,
            else => node_id,
        };
        const node = self.flow.nodes[resolved_node];
        if (node.kind != .builtin_call) return;
        const call = node.kind.builtin_call;
        switch (self.builtinOp(resolved_node)) {
            .list_append, .list_clear, .list_remove, .list_remove_last => {
                if (call.positional.len != 0) try self.resetListPipelineState(call.positional[0]);
                self.list_values[resolved_node] = .{ .list = &.{} };
                self.list_inited[resolved_node] = true;
                self.noteTopLevelMutation(resolved_node);
            },
            else => {},
        }
    }

    fn processListRemovePulse(self: *Session, node_id: flow_ir.NodeId, call: flow_ir.BuiltinCall, pulse: Pulse) anyerror!void {
        if (call.positional.len < 2) return error.MissingArgument;
        const base_node = call.positional[0];
        const item_name = switch (self.flow.nodes[call.positional[1]].kind) {
            .symbol => |text| text,
            else => return error.MissingLocalBinding,
        };
        const on_node = findNamed(call.named, "on") orelse return error.MissingArgument;
        const base_source = try self.listSourceDependency(base_node);

        if (pulse.source == base_source) {
            const base = try self.evalNode(self.arena.allocator(), base_node, null);
            self.list_values[node_id] = try self.filterRemovedItems(self.arena.allocator(), base, self.list_remove_tombstones[node_id]);
            self.list_inited[node_id] = true;
            self.noteTopLevelMutation(node_id);
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
            self.noteTopLevelMutation(node_id);
            break :blk try listItemsFromValue(self.list_values[node_id]);
        };

        var kept: std.ArrayList(Value) = .empty;
        defer kept.deinit(self.arena.allocator());
        var removed: std.ArrayList(Value) = .empty;
        defer removed.deinit(self.arena.allocator());

        for (current) |item| {
            if (try self.listRemoveMatchesPulse(on_node, item_name, item, pulse)) {
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
        self.noteTopLevelMutation(node_id);
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
            self.noteTopLevelMutation(node_id);
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
            self.noteTopLevelMutation(node_id);
            break :blk try listItemsFromValue(self.list_values[node_id]);
        };

        if (current.len == 0) return;

        const next = try self.arena.allocator().alloc(Value, current.len - 1);
        @memcpy(next, current[0 .. current.len - 1]);
        self.list_values[node_id] = .{ .list = next };
        self.list_inited[node_id] = true;
        self.noteTopLevelMutation(node_id);
        try self.logf("list_remove_last n{d} len={d}", .{ node_id, next.len });
        try self.queue.append(self.arena.allocator(), .{ .source = node_id, .payload = .{ .node = node_id } });
    }

    fn skipLimit(self: *Session, call: flow_ir.BuiltinCall, scope: ?*const EvalScope) anyerror!u64 {
        const count_node = findNamed(call.named, "count") orelse return error.MissingCountArg;
        const value = try self.evalNode(self.scratch_arena.allocator(), count_node, scope);
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
            .builtin_call => switch (self.builtinOp(node_id)) {
                .stream_skip, .stream_pulses => node_id,
                else => try self.eventDependencySource(node_id),
            },
            else => try self.eventDependencySource(node_id),
        };
    }

    fn holdTriggerSourceScoped(self: *Session, node_id: flow_ir.NodeId, scope: ?*const EvalScope) anyerror!flow_ir.NodeId {
        const node = self.flow.nodes[node_id];
        return switch (node.kind) {
            .then_value => |then_value| try self.scopedEventDependencySource(then_value.source, scope),
            .latest, .hold => node_id,
            .builtin_call => switch (self.builtinOp(node_id)) {
                .stream_skip, .stream_pulses => node_id,
                else => try self.scopedEventDependencySource(node_id, scope),
            },
            else => try self.scopedEventDependencySource(node_id, scope),
        };
    }

    fn processHoldPulse(self: *Session, node_id: flow_ir.NodeId, hold: flow_ir.Hold, pulse: Pulse) anyerror!void {
        const source = pulse.source;
        const outer_scope = pulse.scope;
        const hold_scope = self.holdStorageScope(node_id, hold, outer_scope);
        const current = self.getHoldValue(node_id, hold_scope) orelse self.evalNode(self.arena.allocator(), hold.initial, hold_scope) catch |err| switch (err) {
            error.MissingLocalBinding,
            error.MissingRecordField,
            error.ExpectedRecordNode,
            error.ExpectedLinkNode,
            error.ExpectedLinkValue,
            error.UnsupportedFieldAccess,
            error.UnsupportedEventSource,
            => return,
            else => return err,
        };
        for (hold.updates) |update| {
            const update_source = if (outer_scope) |scope| scoped: {
                const scoped_source = self.holdTriggerSourceScoped(update, scope) catch |err| switch (err) {
                    error.MissingLocalBinding,
                    error.MissingRecordField,
                    error.ExpectedRecordNode,
                    error.ExpectedLinkNode,
                    error.ExpectedLinkValue,
                    error.UnsupportedFieldAccess,
                    error.UnsupportedEventSource,
                    => null,
                    else => return err,
                };
                if (scoped_source) |resolved| break :scoped resolved;
                break :scoped try self.holdTriggerSource(update);
            } else try self.holdTriggerSource(update);
            if (update_source != source) continue;
            const expected_event = if (outer_scope) |scope|
                try self.triggerScopedEventNameForSource(update, source, scope)
            else
                try self.triggerEventNameForSource(update, source);
            if (!pulseEventNameMatches(expected_event, pulse)) continue;
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
            if (next_value == .none) continue;
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

    fn listRemoveMatchesPulse(self: *Session, on_node: flow_ir.NodeId, item_name: []const u8, item: Value, pulse: Pulse) anyerror!bool {
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
            .link => |link| link == pulse.source,
            .scoped_link => |scoped| sameScopedLink(
                scoped.link,
                canonicalControlScope(scoped.scope),
                pulse.source,
                canonicalControlScope(pulse.scope),
            ),
            else => blk: {
                const trigger_source = try self.listRemoveTriggerSource(on_node);
                break :blk trigger_source != null and trigger_source.? == pulse.source;
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
        if (state.version != 1 and state.version != 2 and state.version != 3 and state.version != 4) return;

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

        for (state.lists) |entry| {
            const node_id = self.resolvePersistedNode(entry.stable_id, entry.node_id, .list) orelse continue;
            self.list_values[node_id] = try persistedScalarToValue(self.arena.allocator(), entry.value);
            self.list_inited[node_id] = true;
            try self.logf("persist read list n{d} key={x}", .{ node_id, self.persist_ids[node_id] });
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
            const persisted = valueToPersistedScalar(self, allocator, value) catch continue;
            const node_id: flow_ir.NodeId = @intCast(index);
            try holds.append(allocator, .{
                .stable_id = self.persist_ids[index],
                .node_id = node_id,
                .value = persisted,
            });
            try self.logf("persist write hold n{d} key={x}", .{ node_id, self.persist_ids[index] });
        }

        var lists: std.ArrayList(PersistedListEntry) = .empty;
        defer lists.deinit(allocator);
        for (self.list_inited, self.list_values, 0..) |inited, value, index| {
            if (!inited or self.persist_ids[index] == 0) continue;
            const persisted = valueToPersistedScalar(self, allocator, value) catch continue;
            if (persisted.kind != .list) continue;
            const node_id: flow_ir.NodeId = @intCast(index);
            try lists.append(allocator, .{
                .stable_id = self.persist_ids[index],
                .node_id = node_id,
                .value = persisted,
            });
            try self.logf("persist write list n{d} key={x}", .{ node_id, self.persist_ids[index] });
        }

        const state = PersistedState{
            .version = 4,
            .sums = try sums.toOwnedSlice(allocator),
            .holds = try holds.toOwnedSlice(allocator),
            .lists = try lists.toOwnedSlice(allocator),
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
            .sum => node.kind == .builtin_call and self.builtinOp(node_id) == .math_sum,
            .hold => node.kind == .hold,
            .list => node.kind == .builtin_call and switch (self.builtinOp(node_id)) {
                .list_append, .list_clear, .list_remove, .list_remove_last => true,
                else => false,
            },
        };
    }
};

pub fn compileAlloc(allocator: std.mem.Allocator, source: []const u8) !CompileOutcome {
    return compileAllocWithOptions(allocator, source, .{});
}

pub fn compileAllocWithOptions(allocator: std.mem.Allocator, source: []const u8, options: flow_ir.Options) !CompileOutcome {
    _ = options;
    const lowered_flow = try flow_ir.lowerAlloc(allocator, source);
    const document = switch (lowered_flow) {
        .ok => |document| document,
        .err => |failure| return .{ .err = failure },
    };

    return .{ .ok = try compileLoweredDocumentAlloc(allocator, document) };
}

fn computeNodeNeedsScopeAlloc(
    allocator: std.mem.Allocator,
    document: *const flow_ir.Document,
) ![]bool {
    const node_count = document.nodes.len;
    const state = try allocator.alloc(u8, node_count);
    @memset(state, 0);
    const result = try allocator.alloc(bool, node_count);
    @memset(result, false);
    for (document.nodes, 0..) |_, index| {
        result[index] = computeNodeNeedsScopeAt(document, state, result, @intCast(index));
    }
    return result;
}

fn computeNodeNeedsScopeAt(
    document: *const flow_ir.Document,
    state: []u8,
    result: []bool,
    node_id: flow_ir.NodeId,
) bool {
    switch (state[node_id]) {
        1, 2 => return false,
        3 => return true,
        else => {},
    }

    state[node_id] = 1;
    const node = document.nodes[node_id];
    const needs_scope = switch (node.kind) {
        .binding_ref => |binding_id| computeNodeNeedsScopeAt(document, state, result, document.bindings[binding_id].node),
        .local_ref => true,
        .special => |special| switch (special) {
            .pass_ref, .passed_ref => true,
            else => false,
        },
        .access => |access| computeNodeNeedsScopeAt(document, state, result, access.target),
        .binary => |binary| computeNodeNeedsScopeAt(document, state, result, binary.lhs) or computeNodeNeedsScopeAt(document, state, result, binary.rhs),
        .text => |parts| blk: {
            for (parts) |part| if (computeNodeNeedsScopeAt(document, state, result, part)) break :blk true;
            break :blk false;
        },
        .list => |list| blk: {
            for (list.items) |item| if (computeNodeNeedsScopeAt(document, state, result, item)) break :blk true;
            break :blk false;
        },
        .record => |fields| blk: {
            for (fields) |field| if (computeNodeNeedsScopeAt(document, state, result, field.value)) break :blk true;
            break :blk false;
        },
        .block => |block| blk: {
            for (block.bindings) |binding| if (computeNodeNeedsScopeAt(document, state, result, binding.value)) break :blk true;
            break :blk computeNodeNeedsScopeAt(document, state, result, block.result);
        },
        .when => |when| blk: {
            if (computeNodeNeedsScopeAt(document, state, result, when.input)) break :blk true;
            for (when.arms) |arm| {
                if (computeNodeNeedsScopeAt(document, state, result, arm.pattern) or computeNodeNeedsScopeAt(document, state, result, arm.result)) break :blk true;
            }
            break :blk false;
        },
        .latest => |latest| blk: {
            if (latest.initial) |initial| if (computeNodeNeedsScopeAt(document, state, result, initial)) break :blk true;
            for (latest.sources) |source| if (computeNodeNeedsScopeAt(document, state, result, source)) break :blk true;
            break :blk false;
        },
        .then_value => |then_value| computeNodeNeedsScopeAt(document, state, result, then_value.source) or computeNodeNeedsScopeAt(document, state, result, then_value.value),
        .hold => |hold| blk: {
            if (computeNodeNeedsScopeAt(document, state, result, hold.initial)) break :blk true;
            for (hold.updates) |update| if (computeNodeNeedsScopeAt(document, state, result, update)) break :blk true;
            break :blk false;
        },
        .linked_value => |linked| computeNodeNeedsScopeAt(document, state, result, linked.value) or computeNodeNeedsScopeAt(document, state, result, linked.target),
        .builtin_call => |call| blk: {
            for (call.positional) |arg| if (computeNodeNeedsScopeAt(document, state, result, arg)) break :blk true;
            for (call.named) |arg| if (computeNodeNeedsScopeAt(document, state, result, arg.value)) break :blk true;
            break :blk false;
        },
        .user_call => |call| blk: {
            for (call.positional) |arg| if (computeNodeNeedsScopeAt(document, state, result, arg)) break :blk true;
            for (call.named) |arg| if (computeNodeNeedsScopeAt(document, state, result, arg.value)) break :blk true;
            if (call.pass_context) |pass_context| break :blk computeNodeNeedsScopeAt(document, state, result, pass_context);
            break :blk false;
        },
        else => false,
    };

    state[node_id] = if (needs_scope) 3 else 2;
    result[node_id] = needs_scope;
    return needs_scope;
}

pub fn compileLoweredDocumentAlloc(allocator: std.mem.Allocator, document: flow_ir.Document) !CompiledProgram {
    errdefer {
        var cleanup = document;
        cleanup.deinit();
    }

    var metadata_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer metadata_arena.deinit();
    const meta_allocator = metadata_arena.allocator();

    const builtin_ops = try meta_allocator.alloc(BuiltinOp, document.nodes.len);
    const node_needs_scope = try computeNodeNeedsScopeAlloc(meta_allocator, &document);
    const node_needs_deferred_field = try meta_allocator.alloc(bool, document.nodes.len);
    var list_remove_nodes: std.ArrayList(flow_ir.NodeId) = .empty;
    defer list_remove_nodes.deinit(meta_allocator);
    var list_remove_last_nodes: std.ArrayList(flow_ir.NodeId) = .empty;
    defer list_remove_last_nodes.deinit(meta_allocator);

    for (document.nodes, 0..) |node, index_usize| {
        const node_id: flow_ir.NodeId = @intCast(index_usize);
        const op = switch (node.kind) {
            .builtin_call => |call| builtinOpFromPath(call.path),
            else => .unknown,
        };
        builtin_ops[index_usize] = op;
        node_needs_deferred_field[index_usize] = builtinNeedsDeferredField(op);
        switch (op) {
            .list_remove => try list_remove_nodes.append(meta_allocator, node_id),
            .list_remove_last => try list_remove_last_nodes.append(meta_allocator, node_id),
            else => {},
        }
    }

    return .{
        .metadata_arena = metadata_arena,
        .flow = document,
        .builtin_ops = builtin_ops,
        .node_needs_scope = node_needs_scope,
        .node_needs_deferred_field = node_needs_deferred_field,
        .list_remove_nodes = try list_remove_nodes.toOwnedSlice(meta_allocator),
        .list_remove_last_nodes = try list_remove_last_nodes.toOwnedSlice(meta_allocator),
    };
}

pub fn serializeCompiledProgram(writer: anytype, compiled: *const CompiledProgram) !void {
    try writer.writeAll(compiled_cache_magic);
    try writer.writeInt(u32, compiled_cache_version, .little);
    try flow_ir.serializeDocument(writer, &compiled.flow);
    try writer.writeInt(u32, @intCast(compiled.builtin_ops.len), .little);
    for (compiled.builtin_ops) |op| try writer.writeByte(@intCast(@intFromEnum(op)));
    try writer.writeInt(u32, @intCast(compiled.node_needs_scope.len), .little);
    for (compiled.node_needs_scope) |value| try writer.writeByte(if (value) 1 else 0);
    try writer.writeInt(u32, @intCast(compiled.node_needs_deferred_field.len), .little);
    for (compiled.node_needs_deferred_field) |value| try writer.writeByte(if (value) 1 else 0);
    try writer.writeInt(u32, @intCast(compiled.list_remove_nodes.len), .little);
    for (compiled.list_remove_nodes) |node_id| try writer.writeInt(u32, node_id, .little);
    try writer.writeInt(u32, @intCast(compiled.list_remove_last_nodes.len), .little);
    for (compiled.list_remove_last_nodes) |node_id| try writer.writeInt(u32, node_id, .little);
}

pub fn deserializeCompiledProgramAlloc(allocator: std.mem.Allocator, reader: anytype) !CompiledProgram {
    var magic: [compiled_cache_magic.len]u8 = undefined;
    try reader.readSliceAll(&magic);
    if (!std.mem.eql(u8, &magic, compiled_cache_magic)) return error.InvalidCacheFormat;
    const version = try reader.takeInt(u32, .little);
    if (version != compiled_cache_version) return error.InvalidCacheFormat;

    const document = try flow_ir.deserializeDocumentAlloc(allocator, reader);

    var metadata_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer metadata_arena.deinit();
    const meta_allocator = metadata_arena.allocator();

    const builtin_count = try reader.takeInt(u32, .little);
    if (builtin_count != document.nodes.len) return error.InvalidCacheFormat;
    const builtin_ops = try meta_allocator.alloc(BuiltinOp, builtin_count);
    for (builtin_ops) |*op| {
        const raw = try reader.takeByte();
        op.* = @enumFromInt(raw);
    }

    const needs_scope_count = try reader.takeInt(u32, .little);
    if (needs_scope_count != document.nodes.len) return error.InvalidCacheFormat;
    const node_needs_scope = try meta_allocator.alloc(bool, needs_scope_count);
    for (node_needs_scope) |*value| value.* = (try reader.takeByte()) != 0;

    const deferred_field_count = try reader.takeInt(u32, .little);
    if (deferred_field_count != document.nodes.len) return error.InvalidCacheFormat;
    const node_needs_deferred_field = try meta_allocator.alloc(bool, deferred_field_count);
    for (node_needs_deferred_field) |*value| value.* = (try reader.takeByte()) != 0;

    const list_remove_count = try reader.takeInt(u32, .little);
    const list_remove_nodes = try meta_allocator.alloc(flow_ir.NodeId, list_remove_count);
    for (list_remove_nodes) |*node_id| node_id.* = try reader.takeInt(u32, .little);

    const list_remove_last_count = try reader.takeInt(u32, .little);
    const list_remove_last_nodes = try meta_allocator.alloc(flow_ir.NodeId, list_remove_last_count);
    for (list_remove_last_nodes) |*node_id| node_id.* = try reader.takeInt(u32, .little);

    return .{
        .metadata_arena = metadata_arena,
        .flow = document,
        .builtin_ops = builtin_ops,
        .node_needs_scope = node_needs_scope,
        .node_needs_deferred_field = node_needs_deferred_field,
        .list_remove_nodes = list_remove_nodes,
        .list_remove_last_nodes = list_remove_last_nodes,
    };
}

pub fn runCompiledAlloc(allocator: std.mem.Allocator, compiled: CompiledProgram, options: Options) !Outcome {
    var program = compiled;

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    var memo_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer memo_arena.deinit();
    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer scratch_arena.deinit();

    var session = Session{
        .backing_allocator = allocator,
        .arena = arena,
        .memo_arena = memo_arena,
        .metadata_arena = program.metadata_arena,
        .scratch_arena = scratch_arena,
        .flow = program.flow,
        .builtin_ops = program.builtin_ops,
        .node_needs_scope = program.node_needs_scope,
        .node_needs_deferred_field = program.node_needs_deferred_field,
        .list_remove_nodes = program.list_remove_nodes,
        .list_remove_last_nodes = program.list_remove_last_nodes,
        .trace_enabled = options.trace,
        .state_file_path = if (options.state_file_path) |path| try arena.allocator().dupe(u8, path) else null,
        .clear_state = options.clear_state,
        .terminal_columns = options.terminal_columns,
        .terminal_rows = options.terminal_rows,
    };
    program = undefined;
    errdefer session.deinit();
    try session.init();
    if (options.virtual_time_ms != 0) try session.advanceTime(options.virtual_time_ms);
    return .{ .ok = session };
}

pub fn runAlloc(allocator: std.mem.Allocator, source: []const u8, options: Options) !Outcome {
    const compiled_outcome = try compileAlloc(allocator, source);
    const compiled = switch (compiled_outcome) {
        .ok => |program| program,
        .err => |failure| return .{ .err = failure },
    };
    return runCompiledAlloc(allocator, compiled, options);
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

fn linkEventTextValue(link_value: ?Value) Value {
    const value = link_value orelse return .none;
    if (recordFieldFromValue(value, "text")) |field| return field;
    if (recordFieldFromValue(value, "value")) |field| return field;
    return value;
}

fn linkEventKeyValue(link_value: ?Value, key_value: ?Value) Value {
    if (link_value) |value| {
        if (recordFieldFromValue(value, "key")) |field| return field;
    }
    return key_value orelse .none;
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

fn styleBoolField(value: Value, name: []const u8) bool {
    const field = recordFieldFromValue(value, name) orelse return false;
    return valueAsBoolLoose(field);
}

fn styleHasOutline(value: Value) bool {
    const outline = recordFieldFromValue(value, "outline") orelse return false;
    return switch (outline) {
        .record => true,
        .symbol => |symbol| !std.mem.eql(u8, symbol, "NoOutline"),
        .text => |text| text.len != 0 and !std.mem.eql(u8, text, "NoOutline"),
        .none => false,
        else => valueAsBoolLoose(outline),
    };
}

fn terminalStyleSpan(size: f64, divisor: f64) usize {
    if (size <= 0) return 0;
    return @max(@as(usize, 1), @as(usize, @intFromFloat(@ceil(size / divisor))));
}

fn persistKindLabel(kind: flow_ir.Node.Kind) ?[]const u8 {
    return switch (kind) {
        .hold => "hold",
        .builtin_call => |call| switch (builtinOpFromPath(call.path)) {
            .math_sum => "sum",
            .list_append, .list_clear, .list_remove, .list_remove_last => "list",
            else => null,
        },
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

fn valueToPersistedScalar(self: *Session, allocator: std.mem.Allocator, value: Value) !PersistedScalar {
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
        .list => |items| blk: {
            const persisted_items = try allocator.alloc(PersistedScalar, items.len);
            for (items, 0..) |item, index| {
                persisted_items[index] = try valueToPersistedScalar(self, allocator, item);
            }
            break :blk .{
                .kind = .list,
                .list = persisted_items,
            };
        },
        .record => |fields| blk: {
            const persisted_fields = try allocator.alloc(PersistedRecordField, fields.len);
            for (fields, 0..) |field, index| {
                persisted_fields[index] = .{
                    .name = try allocator.dupe(u8, field.name),
                    .value = try valueToPersistedScalar(self, allocator, field.value),
                };
            }
            break :blk .{
                .kind = .record,
                .record = persisted_fields,
            };
        },
        .link => |link| .{
            .kind = .link,
            .node_id = link,
        },
        .scoped_link => |scoped| .{
            .kind = .link,
            .node_id = scoped.link,
        },
        .scoped_node => |deferred| try valueToPersistedScalar(self, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => error.UnsupportedPersistedValue,
    };
}

fn persistedScalarToValue(allocator: std.mem.Allocator, persisted: PersistedScalar) !Value {
    return switch (persisted.kind) {
        .none => .none,
        .number => .{ .number = persisted.number orelse return error.InvalidPersistedValue },
        .text => .{ .text = persisted.text orelse return error.InvalidPersistedValue },
        .symbol => .{ .symbol = persisted.text orelse return error.InvalidPersistedValue },
        .duration_ms => .{ .duration_ms = persisted.duration_ms orelse return error.InvalidPersistedValue },
        .link => .{ .link = persisted.node_id orelse return error.InvalidPersistedValue },
        .list => blk: {
            const persisted_items = persisted.list orelse return error.InvalidPersistedValue;
            const items = try allocator.alloc(Value, persisted_items.len);
            for (persisted_items, 0..) |item, index| {
                items[index] = try persistedScalarToValue(allocator, item);
            }
            break :blk .{ .list = items };
        },
        .record => blk: {
            const persisted_fields = persisted.record orelse return error.InvalidPersistedValue;
            const fields = try allocator.alloc(RecordField, persisted_fields.len);
            for (persisted_fields, 0..) |field, index| {
                fields[index] = .{
                    .name = field.name,
                    .value = try persistedScalarToValue(allocator, field.value),
                };
            }
            break :blk .{ .record = fields };
        },
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
    const passed = if (parent) |frame| frame.passed else null;
    const id = if (std.mem.eql(u8, name, "element"))
        extendScopeIdShallow(scopeIdBase(parent, passed), bindings[0])
    else
        extendScopeId(scopeIdBase(parent, passed), bindings[0]);
    return .{
        .bindings = bindings,
        .parent = parent,
        .passed = passed,
        .id = id,
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
        .scoped_link => |scoped| .{ .scoped_link = .{
            .link = scoped.link,
            .scope = try captureControlScope(allocator, scoped.scope),
        } },
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
        .scoped_link => |scoped| destroyCapturedScope(allocator, scoped.scope),
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

fn captureControlScope(allocator: std.mem.Allocator, scope: ?*const EvalScope) !?*const EvalScope {
    return try captureScope(allocator, Session.canonicalControlScope(scope) orelse scope);
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
    var id = scopeIdBase(parent, passed);
    for (bindings) |binding| id = extendScopeId(id, binding);
    return id;
}

fn deriveRecordScopeId(parent: ?*const EvalScope, bindings: []const RecordField, passed: ?Value) u64 {
    var id = recordScopeIdBase(parent, passed);
    for (bindings) |binding| id = extendRecordScopeId(id, binding);
    return id;
}

fn scopeIdBase(parent: ?*const EvalScope, passed: ?Value) u64 {
    var hasher = std.hash.Wyhash.init(if (parent) |frame| frame.id else 0);
    if (passed) |value| {
        hasher.update("passed");
        hashValueIdentity(&hasher, value);
    }
    return hasher.final();
}

fn recordScopeIdBase(parent: ?*const EvalScope, passed: ?Value) u64 {
    var hasher = std.hash.Wyhash.init(if (parent) |frame| frame.id else 0);
    if (passed) |value| {
        hasher.update("passed");
        hashRecordScopeValueIdentity(&hasher, value);
    }
    return hasher.final();
}

fn extendScopeId(base: u64, binding: RecordField) u64 {
    var hasher = std.hash.Wyhash.init(base);
    hasher.update(binding.name);
    hashValueIdentity(&hasher, binding.value);
    return hasher.final();
}

fn extendScopeIdShallow(base: u64, binding: RecordField) u64 {
    var hasher = std.hash.Wyhash.init(base);
    hasher.update(binding.name);
    hashShallowValueIdentity(&hasher, binding.value);
    return hasher.final();
}

fn extendRecordScopeId(base: u64, binding: RecordField) u64 {
    var hasher = std.hash.Wyhash.init(base);
    hasher.update(binding.name);
    hashRecordScopeValueIdentity(&hasher, binding.value);
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
        .scoped_link => |scoped| {
            hasher.update(std.mem.asBytes(&scoped.link));
            const scope_id = if (scoped.scope) |scope| scope.id else @as(u64, 0);
            hasher.update(std.mem.asBytes(&scope_id));
        },
        .none => {},
    }
}

fn hashShallowValueIdentity(hasher: *std.hash.Wyhash, value: Value) void {
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
            const ptr_value: usize = @intFromPtr(items.ptr);
            const len = items.len;
            hasher.update(std.mem.asBytes(&ptr_value));
            hasher.update(std.mem.asBytes(&len));
        },
        .record => |fields| {
            const ptr_value: usize = @intFromPtr(fields.ptr);
            const len = fields.len;
            hasher.update(std.mem.asBytes(&ptr_value));
            hasher.update(std.mem.asBytes(&len));
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
        .scoped_link => |scoped| {
            hasher.update(std.mem.asBytes(&scoped.link));
            const scope_id = if (scoped.scope) |scope| scope.id else @as(u64, 0);
            hasher.update(std.mem.asBytes(&scope_id));
        },
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
        .scoped_link => |scoped| {
            hasher.update(std.mem.asBytes(&scoped.link));
            const scope_id = if (scoped.scope) |scope| scope.id else @as(u64, 0);
            hasher.update(std.mem.asBytes(&scope_id));
        },
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
        .scoped_link => |scoped| std.fmt.allocPrint(
            allocator,
            "link(n{d}@{?d})",
            .{ scoped.link, if (scoped.scope) |scope| scope.id else null },
        ),
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
        .symbol => |text| std.ascii.eqlIgnoreCase(text, "True"),
        .text => |text| std.ascii.eqlIgnoreCase(text, "True"),
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
    defer allocator.free(header);
    try output.appendSlice(allocator, header);
    const visible_len = @min(items.len, control_summary_limit);
    for (items[0..visible_len], 0..) |item, index| {
        const line = try std.fmt.allocPrint(allocator, "  {d} {s}\n", .{ index, item });
        defer allocator.free(line);
        try output.appendSlice(allocator, line);
    }
    if (visible_len < items.len) {
        const rest = try std.fmt.allocPrint(allocator, "  ... {d} more\n", .{items.len - visible_len});
        defer allocator.free(rest);
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
        .scoped_link => |scoped| switch (rhs) {
            .scoped_link => |other| scoped.link == other.link and scopeIdentity(scoped.scope) == scopeIdentity(other.scope),
            else => false,
        },
        .scoped_node => |deferred| switch (rhs) {
            .scoped_node => |other| deferred.node_id == other.node_id and scopeIdentity(deferred.scope) == scopeIdentity(other.scope),
            else => false,
        },
        .none => rhs == .none,
        else => false,
    };
}

fn scopeIdentity(scope: ?*const EvalScope) u64 {
    return if (scope) |frame| frame.id else 0;
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
                .scoped_link => |scoped| scoped.link,
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
            input.blur_link
        else if (std.mem.eql(u8, event_name, "focus"))
            input.focus_link
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
        .scoped_link => |scoped| scoped.link,
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
                .scoped_link => |scoped| scoped.link,
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
        .container => |container| {
            if (container.click_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = container.event_scope }));
            try collectButtonLinks(self, list, allocator, container.child);
        },
        .label => |label| if (label.click_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = label.event_scope })),
        .checkbox => |checkbox| if (checkbox.click_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = checkbox.event_scope })),
        .button => |button| if (button.press_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = button.event_scope })),
        .scoped_node => |deferred| try collectButtonLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
        else => {},
    }
}

fn collectCheckboxLinks(self: *Session, list: *std.ArrayList(ControlEventRef), allocator: std.mem.Allocator, value: Value) !void {
    switch (value) {
        .list => |items| for (items) |item| try collectCheckboxLinks(self, list, allocator, item),
        .document => |document| try collectCheckboxLinks(self, list, allocator, document.root),
        .terminal => |terminal| try collectCheckboxLinks(self, list, allocator, terminal.root),
        .stripe => |stripe| for (stripe.items) |item| try collectCheckboxLinks(self, list, allocator, item),
        .container => |container| try collectCheckboxLinks(self, list, allocator, container.child),
        .checkbox => |checkbox| if (checkbox.click_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = checkbox.event_scope })),
        .scoped_node => |deferred| try collectCheckboxLinks(self, list, allocator, try self.evalNode(allocator, deferred.node_id, deferred.scope)),
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
        .label => |label| if (label.double_click_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = label.event_scope })),
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
            if (stripe.hovered_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = stripe.event_scope }));
            for (stripe.items) |item| try collectHoverLinks(self, list, allocator, item);
        },
        .container => |container| try collectHoverLinks(self, list, allocator, container.child),
        .button => |button| if (button.hovered_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = button.event_scope })),
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
        .slider => |slider| if (slider.change_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = slider.event_scope })),
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
        .text_input => |input| if (input.change_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = input.event_scope })),
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
        .text_input => |input| try list.append(allocator, try cloneTextInputValueForCache(allocator, input)),
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
        .text_input => |input| if (input.key_link orelse input.change_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = input.event_scope })),
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
        .text_input => |input| if (input.blur_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = input.event_scope })),
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
        .text_input => |input| if (input.focus_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = input.event_scope })),
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
        .select => |select| if (select.change_link) |link| try list.append(allocator, try cloneControlEventRefForCache(allocator, .{ .link = link, .scope = select.event_scope })),
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
        \\                element: [event: [press: SOURCE]]
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
        \\    element: [event: [press: SOURCE]]
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
        \\    element: [event: [press: SOURCE]]
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
        \\            element: [event: [press: SOURCE]]
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

test "Reference accepts real element values and renders referenced label" {
    const source =
        \\title_label: Element/label(
        \\    element: []
        \\    style: []
        \\    label: TEXT { Title }
        \\)
        \\
        \\document: Document/new(root: Element/checkbox(
        \\    element: [event: [click: SOURCE]]
        \\    icon: TEXT { [ ] }
        \\    label: Reference[element: title_label]
        \\    checked: False
        \\    style: []
        \\))
    ;

    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected Reference element failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Title") != null);
}

test "Reference rejects source interface records as element values" {
    const source =
        \\sources: [
        \\    title_label: [event: [press: SOURCE]]
        \\]
        \\
        \\document: Document/new(root: Element/checkbox(
        \\    element: [event: [click: SOURCE]]
        \\    icon: TEXT { [ ] }
        \\    label: Reference[element: sources.title_label]
        \\    checked: False
        \\    style: []
        \\))
    ;

    try std.testing.expectError(error.SourceRecordIsNotElementValue, runAlloc(std.testing.allocator, source, .{ .trace = true }));
}

test "stored text input element in record exposes change and key events through headless runtime" {
    const source =
        \\store: [
        \\    elements: [
        \\        input: Element/text_input(
        \\            element: [event: [change: SOURCE, key_down: SOURCE]]
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
        \\    edit_text_event: SOURCE
        \\    edit_committed: SOURCE
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
        \\    editing_element: [event: [change: SOURCE, key_down: SOURCE]]
        \\
        \\    edit_changed_link:
        \\        editing_element.event.change
        \\        |> THEN { editing_element.event.change.text }
        \\        |> SOURCE { event_ports.edit_text_event }
        \\
        \\    edit_committed_link:
        \\        editing_element.event.key_down.key
        \\        |> WHEN {
        \\            Enter => editing_element.event.key_down.text
        \\            __ => SKIP
        \\        }
        \\        |> SOURCE { event_ports.edit_committed }
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
        \\    elements: [launch: SOURCE]
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
    try std.testing.expect(contract.keyboard_bindings[2].when);

    try session.triggerLinkWithScope(contract.keyboard_bindings[2].link, contract.keyboard_bindings[2].scope);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Rally") != null);
}

test "compiled pong terminal contract keeps Enter binding active" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const compiled_outcome = try compileAlloc(std.testing.allocator, source);
    const compiled = switch (compiled_outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected compiled pong compile failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    const outcome = try runCompiledAlloc(std.testing.allocator, compiled, .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected compiled pong run failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    var contract = (try session.terminalContractAlloc(std.testing.allocator)).?;
    defer contract.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Enter", contract.keyboard_bindings[2].keys[0]);
    try std.testing.expect(contract.keyboard_bindings[2].when);

    try session.triggerLinkWithScope(contract.keyboard_bindings[2].link, contract.keyboard_bindings[2].scope);

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Rally") != null);
}

test "serialized pong flow keeps Enter binding active after compile cache round-trip" {
    const source = @embedFile("../examples/terminal/pong/pong.bn");
    const compiled_outcome = try compileAlloc(std.testing.allocator, source);
    const compiled = switch (compiled_outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected serialized pong compile failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    defer {
        var cleanup = compiled;
        cleanup.deinit();
    }

    var encoded: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer encoded.deinit();
    try flow_ir.serializeDocument(&encoded.writer, &compiled.flow);

    var reader = std.Io.Reader.fixed(encoded.written());
    const loaded = try flow_ir.deserializeDocumentAlloc(std.testing.allocator, &reader);
    const outcome = try runCompiledAlloc(std.testing.allocator, try compileLoweredDocumentAlloc(std.testing.allocator, loaded), .{});
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected serialized pong run failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    var contract = (try session.terminalContractAlloc(std.testing.allocator)).?;
    defer contract.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Enter", contract.keyboard_bindings[2].keys[0]);
    try std.testing.expect(contract.keyboard_bindings[2].when);

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
        \\            element: [event: [press: SOURCE]]
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
        \\                element: [event: [press: SOURCE]]
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
        \\    elements: [ serve: SOURCE tick: SOURCE ]
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
        \\    elements: [ serve: SOURCE tick: SOURCE ]
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

    try session.setTextInputValue(0, "Orange");
    try session.pressTextInputKey(0, "Enter");
    const after_readd = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_readd);
    try std.testing.expect(std.mem.indexOf(u8, after_readd, "1items") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_readd, "Orange") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_readd, "Milk") == null);
    try std.testing.expect(std.mem.indexOf(u8, after_readd, "Bread") == null);

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
    try std.testing.expect(std.mem.indexOf(u8, rendered, "0 7 17 32") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, rendered, "0 7 17 32") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, rendered, "0 7 17 32") != null);
}

test "compileAlloc and runCompiledAlloc match runAlloc render output" {
    const source = @embedFile("../examples/terminal/cells/cells.bn");

    const compiled_outcome = try compileAlloc(std.testing.allocator, source);
    const compiled = switch (compiled_outcome) {
        .ok => |program| program,
        .err => |failure| {
            std.debug.print("unexpected compile failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    const compiled_session = try runCompiledAlloc(std.testing.allocator, compiled, .{});
    const compiled_value = switch (compiled_session) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected compiled run failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var compiled_runtime = compiled_value;
    defer compiled_runtime.deinit();

    const direct_outcome = try runAlloc(std.testing.allocator, source, .{});
    const direct_value = switch (direct_outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected direct run failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var direct_runtime = direct_value;
    defer direct_runtime.deinit();

    const compiled_render = try compiled_runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(compiled_render);
    const direct_render = try direct_runtime.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(direct_render);
    try std.testing.expectEqualStrings(direct_render, compiled_render);
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
    try std.testing.expect(std.mem.indexOf(u8, rendered, "0 7 17 32") != null);
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
    try session.setFirstTextInputValue(std.testing.allocator, "=add(A0, A1)7");
    try session.pressFirstTextInputKey(std.testing.allocator, "Enter");

    const rendered = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "0 5 0 30") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, rendered, "0 7 17 32") != null);
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

test "pages headless session routes through navigation links" {
    const source = @embedFile("../examples/upstream/pages/pages.bn");
    const outcome = try runAlloc(std.testing.allocator, source, .{ .trace = true });
    const session_value = switch (outcome) {
        .ok => |session| session,
        .err => |failure| {
            std.debug.print("unexpected pages router failure: {s}\n", .{failure.message});
            return error.UnexpectedHeadlessFailure;
        },
    };
    var session = session_value;
    defer session.deinit();

    try std.testing.expectEqualStrings("/", try session.routeTextView());
    try session.clickButton(1);
    try std.testing.expectEqualStrings("/about", try session.routeTextView());
    const about = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(about);
    try std.testing.expect(std.mem.indexOf(u8, about, "A multi-page Boon app") != null);

    try session.clickButton(2);
    try std.testing.expectEqualStrings("/contact", try session.routeTextView());
    const contact = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(contact);
    try std.testing.expect(std.mem.indexOf(u8, contact, "Get in touch!") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
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
    try session.clickButtonByLabel(std.testing.allocator, "×");
    const after_remove = try session.renderAlloc(std.testing.allocator);
    defer std.testing.allocator.free(after_remove);
    try std.testing.expect(std.mem.indexOf(u8, after_remove, "Buygroceries") == null);
    try std.testing.expect(std.mem.indexOf(u8, after_remove, "Cleanroom") != null);
    try std.testing.expect(std.mem.indexOf(u8, after_remove, "1itemsleft") != null);

    const trace = try session.traceAlloc(std.testing.allocator);
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external hover[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "external click label ×") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "list_remove n") != null);
}
