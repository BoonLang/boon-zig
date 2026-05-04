const std = @import("std");
const raybox = @import("raybox");
const registry = @import("example_registry");

const host_mod = raybox.boon_adapter.host;
const bridge = host_mod.bridge;

pub const TargetName = enum { native, web };

pub fn run(
    allocator: std.mem.Allocator,
    target_name: TargetName,
    selected: ?[]const u8,
    build_only: bool,
    examples_root: []const u8,
) !bool {
    makeReportDirs();
    const canonical_report_path = switch (target_name) {
        .native => "zig-out/reports/example_status_native.json",
        .web => "zig-out/reports/example_status_web.json",
    };
    const scoped_report_path = if (selected != null or build_only)
        try std.fmt.allocPrint(
            allocator,
            "zig-out/reports/example_status_{s}_{s}{s}.json",
            .{
                @tagName(target_name),
                selected orelse "all",
                if (build_only) "_build_only" else "",
            },
        )
    else
        null;
    defer if (scoped_report_path) |path| allocator.free(path);
    const report_path = if (scoped_report_path) |path| path else canonical_report_path;

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;

    try writer.writeAll("{\n  \"statuses\": [\n");
    var first = true;
    var all_done = true;

    for (registry.examples) |example| {
        if (selected) |wanted| {
            if (!std.mem.eql(u8, wanted, example.name)) continue;
        }

        const result = verifyOne(allocator, target_name, example, build_only, examples_root) catch |err| VerificationResult{
            .status = .BLOCKED,
            .message = @errorName(err),
            .text = "",
        };
        if (result.status != .DONE) all_done = false;

        if (!first) try writer.writeAll(",\n");
        first = false;
        try writer.print(
            "    {{ \"example\": \"{s}\", \"status\": \"{s}\", \"message\": \"",
            .{ example.name, @tagName(result.status) },
        );
        try writeJsonStringContent(writer, result.message);
        try writer.print("\", \"text\": \"", .{});
        try writeJsonStringContent(writer, result.text);
        try writer.writeAll("\" }");
    }

    if (first and selected != null) {
        all_done = false;
        try writer.writeAll("    { \"example\": \"");
        try writeJsonStringContent(writer, selected.?);
        try writer.writeAll("\", \"status\": \"BLOCKED\", \"message\": \"selected example not found\", \"text\": \"\" }");
    }

    try writer.writeAll("\n  ]\n}\n");
    try writeFile(report_path, out.written());
    return all_done;
}

pub const Status = enum {
    NOT_STARTED,
    PARTIAL,
    BLOCKED,
    DONE,
};

pub const VerificationResult = struct {
    status: Status,
    message: []const u8,
    text: []const u8,
};

pub fn verifyOneByName(
    allocator: std.mem.Allocator,
    target_name: TargetName,
    name: []const u8,
    build_only: bool,
    examples_root: []const u8,
) !VerificationResult {
    for (registry.examples) |example| {
        if (std.mem.eql(u8, name, example.name)) {
            return verifyOne(allocator, target_name, example, build_only, examples_root) catch |err| VerificationResult{
                .status = .BLOCKED,
                .message = @errorName(err),
                .text = "",
            };
        }
    }
    return .{ .status = .BLOCKED, .message = "selected example not found", .text = "" };
}

const MatchMode = enum {
    contains,
    exact,
    regex,
};

const ExpectedOutput = struct {
    text: []u8,
    match: MatchMode,

    fn deinit(self: ExpectedOutput, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

const StepKind = enum { sequence, persistence };

const ExpectedStep = struct {
    kind: StepKind,
    description: []const u8,
    body: []const u8,
    expect: []const u8,
    match: MatchMode,
};

const SnapshotText = struct {
    text: []u8,
    route: []const u8 = "/",
    semantic: SemanticSnapshot = .{},

    fn deinit(self: *SnapshotText, allocator: std.mem.Allocator, free_text: bool) void {
        if (free_text) allocator.free(self.text);
        self.semantic.deinit(allocator);
        self.* = .{ .text = &.{} };
    }
};

const SemanticInput = struct {
    text: []u8,
    placeholder: []u8,
    focused: bool,
    typeable: bool,
};

const SemanticButton = struct {
    label: []u8,
    disabled: bool,
    outlined: bool,
};

const SemanticCheckbox = struct {
    checked: bool,
};

const SemanticSnapshot = struct {
    inputs: []SemanticInput = &.{},
    buttons: []SemanticButton = &.{},
    checkboxes: []SemanticCheckbox = &.{},

    fn deinit(self: *SemanticSnapshot, allocator: std.mem.Allocator) void {
        freeSemanticInputs(allocator, self.inputs);
        freeSemanticButtons(allocator, self.buttons);
        if (self.inputs.len != 0) allocator.free(self.inputs);
        if (self.buttons.len != 0) allocator.free(self.buttons);
        if (self.checkboxes.len != 0) allocator.free(self.checkboxes);
        self.* = .{};
    }
};

fn verifyOne(
    allocator: std.mem.Allocator,
    target_name: TargetName,
    example: registry.Example,
    build_only: bool,
    examples_root: []const u8,
) !VerificationResult {
    _ = target_name;
    const project = switch (example.kind) {
        .single_file => try loadSingleFileProject(allocator, example, examples_root),
        .multi_file => try loadMultiFileProject(allocator, example, examples_root),
    };
    defer freeProject(allocator, project);

    var persist_ctx = host_mod.MemoryPersistStore.init(allocator);
    defer persist_ctx.deinit();
    var route_ctx = host_mod.MemoryRouteStore{};
    var persist = persist_ctx.store();
    var route = route_ctx.store();
    var clock = bridge.VirtualClock{};
    var time = bridge.TimeSource{ .virtual = &clock };
    var host = try bridge.BoonRuntimeHost.init(allocator, &persist, &route, &time);
    defer host.deinit();

    try host.loadProject(project);
    try host.clearState(example.name);
    switch (try host.runBuildFile()) {
        .not_present, .ok => {},
        .diagnostics => |diagnostics| return diagnosticsResult(allocator, diagnostics),
    }
    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => |diagnostics| return diagnosticsResult(allocator, diagnostics),
    }
    const expected_file = try readExpectedFile(allocator, example, examples_root);
    defer allocator.free(expected_file);

    const compact_render = expectedUsesCompactRender(expected_file);
    var snapshot = if (compact_render) blk: {
        try host.startNoSnapshot();
        break :blk try renderOnlySnapshot(allocator, &host);
    } else try snapshotTextFromOutput(allocator, try host.start());
    const text = snapshot.text;

    if (build_only) {
        snapshot.semantic.deinit(allocator);
        return .{ .status = .DONE, .message = "compiled and produced a non-empty runtime snapshot", .text = text };
    }

    const expected_output = try readExpectedOutput(allocator, example, examples_root);
    defer expected_output.deinit(allocator);
    if (expected_output.text.len != 0 and !(try outputMatches(allocator, text, expected_output))) {
        snapshot.semantic.deinit(allocator);
        return .{ .status = .BLOCKED, .message = "snapshot text does not match expected [output]", .text = text };
    }
    if (hasExpectedSteps(expected_file)) {
        const runner = try runExpectedSteps(allocator, example.name, expected_file, &host, &clock, snapshot, compact_render);
        return runner;
    }
    snapshot.semantic.deinit(allocator);
    return .{ .status = .DONE, .message = "initial expected output passed", .text = text };
}

fn diagnosticsResult(allocator: std.mem.Allocator, diagnostics: []const bridge.Diagnostic) !VerificationResult {
    if (diagnostics.len == 0) return .{ .status = .BLOCKED, .message = "unknown diagnostic", .text = "" };
    return .{ .status = .BLOCKED, .message = try allocator.dupe(u8, diagnostics[0].message), .text = "" };
}

fn readExpectedFile(allocator: std.mem.Allocator, example: registry.Example, examples_root: []const u8) ![]u8 {
    const expected_name = try std.mem.concat(allocator, u8, &.{ example.name, ".expected" });
    defer allocator.free(expected_name);
    const path = try std.fs.path.join(allocator, &.{ examples_root, example.name, expected_name });
    defer allocator.free(path);
    return readFileAlloc(allocator, path, 1024 * 1024) catch try allocator.dupe(u8, "");
}

fn hasExpectedSteps(contents: []const u8) bool {
    return std.mem.indexOf(u8, contents, "[[sequence]]") != null or
        std.mem.indexOf(u8, contents, "[[persistence]]") != null;
}

fn runExpectedSteps(
    allocator: std.mem.Allocator,
    example_name: []const u8,
    contents: []const u8,
    host: *bridge.BoonRuntimeHost,
    clock: *bridge.VirtualClock,
    initial_snapshot: SnapshotText,
    compact_render: bool,
) !VerificationResult {
    var current = initial_snapshot;
    var input_text = std.ArrayListUnmanaged(u8).empty;
    defer input_text.deinit(allocator);
    var input_text_valid = false;
    var focused_input: u64 = 0;
    var render_only_input_handle: ?bridge.TextInputHandle = null;
    var button_index_view = try cloneSemanticButtons(allocator, current.semantic.buttons);
    defer freeSemanticButtonsWithSlice(allocator, button_index_view);

    var cursor: usize = 0;
    var ran_any = false;
    while (nextExpectedStep(contents, &cursor)) |step| {
        ran_any = true;
        const previous_buttons = try cloneSemanticButtons(allocator, button_index_view);
        defer freeSemanticButtonsWithSlice(allocator, previous_buttons);
        if (step.kind == .persistence) {
            const rerun = try rerunHost(allocator, host, clock);
            switch (rerun) {
                .none => {},
                .snapshot => |next| {
                    var old = current;
                    current = next;
                    old.deinit(allocator, true);
                },
                .blocked => |message| {
                    current.semantic.deinit(allocator);
                    return .{ .status = .BLOCKED, .message = message, .text = current.text };
                },
            }
        }
        var action_cursor: usize = 0;
        while (nextAction(step.body, &action_cursor)) |action| {
            const action_result = runAction(allocator, example_name, host, clock, action, &input_text, &input_text_valid, &focused_input, &render_only_input_handle, current, previous_buttons, compact_render) catch |err| {
                const message = if (step.description.len == 0)
                    try std.fmt.allocPrint(allocator, "action {s} failed: {s}", .{ action, @errorName(err) })
                else
                    try std.fmt.allocPrint(allocator, "{s}: action {s} failed: {s}", .{ step.description, action, @errorName(err) });
                current.semantic.deinit(allocator);
                return .{ .status = .BLOCKED, .message = message, .text = current.text };
            };
            switch (action_result) {
                .none => {},
                .snapshot => |next| {
                    var old = current;
                    current = next;
                    old.deinit(allocator, true);
                },
                .blocked => |message| {
                    const detailed = if (step.description.len == 0)
                        message
                    else
                        try std.fmt.allocPrint(allocator, "{s}: {s}", .{ step.description, message });
                    current.semantic.deinit(allocator);
                    return .{ .status = .BLOCKED, .message = detailed, .text = current.text };
                },
            }
        }
        if (step.expect.len != 0) {
            const expected = ExpectedOutput{ .text = @constCast(step.expect), .match = step.match };
            const matches_current = try outputMatches(allocator, current.text, expected);
            const matches_transition = if (!matches_current)
                try transitionOutputMatches(allocator, previous_buttons, current, expected)
            else
                false;
            if (!matches_current and !matches_transition) {
                const message = if (step.description.len == 0)
                    "expected action sequence assertion failed"
                else
                    try std.fmt.allocPrint(allocator, "expected action sequence assertion failed: {s}", .{step.description});
                current.semantic.deinit(allocator);
                return .{ .status = .BLOCKED, .message = message, .text = current.text };
            }
            const next_buttons = if (matches_transition)
                try transitionButtonSequenceAlloc(allocator, previous_buttons, current.semantic.buttons)
            else
                try cloneSemanticButtons(allocator, current.semantic.buttons);
            freeSemanticButtonsWithSlice(allocator, button_index_view);
            button_index_view = next_buttons;
        } else {
            const next_buttons = try cloneSemanticButtons(allocator, current.semantic.buttons);
            freeSemanticButtonsWithSlice(allocator, button_index_view);
            button_index_view = next_buttons;
        }
        if (compact_render and action_cursor != 0 and render_only_input_handle == null) {
            const rerun = try rerunHostRenderOnly(allocator, host, clock);
            switch (rerun) {
                .none => {},
                .snapshot => |next| {
                    var old = current;
                    current = next;
                    old.deinit(allocator, true);
                },
                .blocked => |message| {
                    current.semantic.deinit(allocator);
                    return .{ .status = .BLOCKED, .message = message, .text = current.text };
                },
            }
        }
    }
    current.semantic.deinit(allocator);
    return .{
        .status = .DONE,
        .message = if (ran_any) "expected action runner passed" else "initial expected output passed",
        .text = current.text,
    };
}

const ActionResult = union(enum) {
    none,
    snapshot: SnapshotText,
    blocked: []const u8,
};

fn runAction(
    allocator: std.mem.Allocator,
    example_name: []const u8,
    host: *bridge.BoonRuntimeHost,
    clock: *bridge.VirtualClock,
    action: []const u8,
    input_text: *std.ArrayListUnmanaged(u8),
    input_text_valid: *bool,
    focused_input: *u64,
    render_only_input_handle: *?bridge.TextInputHandle,
    current: SnapshotText,
    previous_buttons: []const SemanticButton,
    compact_render: bool,
) !ActionResult {
    const name = firstActionString(action) orelse return .none;
    if (compact_render) {
        if (std.mem.eql(u8, name, "assert_focused")) {
            return if (render_only_input_handle.* != null) .none else .{ .blocked = "assert_focused failed" };
        }
        if (std.mem.eql(u8, name, "assert_not_focused")) {
            return if (render_only_input_handle.* == null) .none else .{ .blocked = "assert_not_focused failed" };
        }
        if (std.mem.eql(u8, name, "assert_focused_input_value")) {
            const expected = nthActionString(action, 1) orelse return .{ .blocked = "assert_focused_input_value missing text" };
            const trimmed = std.mem.trim(u8, input_text.items, " \t\r\n");
            return if (render_only_input_handle.* != null and std.mem.eql(u8, trimmed, expected))
                .none
            else
                .{ .blocked = "assert_input_value failed" };
        }
    }
    if (std.mem.startsWith(u8, name, "assert_")) {
        return try runAssertAction(allocator, name, action, current);
    }
    if (std.mem.eql(u8, name, "click_button")) {
        const index = firstActionInteger(action, 0);
        return dispatchAndText(allocator, host, .{ .click = index }) catch |err| switch (err) {
            error.InvalidButtonIndex => {
                const remapped = try remapTransitionButtonIndex(allocator, previous_buttons, current.semantic.buttons, index);
                return try dispatchAndText(allocator, host, .{ .click = remapped });
            },
            else => return err,
        };
    }
    if (std.mem.eql(u8, name, "click_checkbox")) {
        const index = firstActionInteger(action, 0);
        const handle_index = std.math.cast(usize, index) orelse return .{ .blocked = "click_checkbox index too large" };
        const handle = host.checkboxHandle(handle_index) catch return try dispatchAndText(allocator, host, .{ .checkbox_change = .{ .link = index, .checked = true } });
        return try dispatchAndText(allocator, host, .{ .checkbox_ref_change = .{ .handle = handle, .checked = true } });
    }
    if (std.mem.eql(u8, name, "click_text")) {
        const label = nthActionString(action, 1) orelse return .{ .blocked = "click_text missing label" };
        if (compact_render and textContainsNormalized(allocator, current.text, label) catch false) {
            if (render_only_input_handle.*) |handle| {
                try host.blurTextInputWithHandle(handle);
                render_only_input_handle.* = null;
                return .none;
            }
        }
        return dispatchAndText(allocator, host, .{ .click_text = label }) catch |err| switch (err) {
            error.UnknownControlLabel => {
                if (textContainsNormalized(allocator, current.text, label) catch false) {
                    return try dispatchAndText(allocator, host, .{ .blur = focused_input.* });
                }
                return err;
            },
            else => return err,
        };
    }
    if (std.mem.eql(u8, name, "hover_text")) {
        const label = nthActionString(action, 1) orelse return .{ .blocked = "hover_text missing label" };
        return try dispatchAndText(allocator, host, .{ .hover_text = .{ .text = label, .hovered = true } });
    }
    if (std.mem.eql(u8, name, "click_button_near_text")) {
        const target = nthActionString(action, 1) orelse return .{ .blocked = "click_button_near_text missing target text" };
        const button = nthActionString(action, 2) orelse return .{ .blocked = "click_button_near_text missing button text" };
        _ = try dispatchAndText(allocator, host, .{ .hover_text = .{ .text = target, .hovered = true } });
        return try dispatchAndText(allocator, host, .{ .click_text = button });
    }
    if (std.mem.eql(u8, name, "dblclick_text")) {
        const label = nthActionString(action, 1) orelse return .{ .blocked = "dblclick_text missing label" };
        const result = dispatchAndText(allocator, host, .{ .double_click_text = label }) catch |err| switch (err) {
            error.UnknownControlLabel => {
                if (try focusedSemanticInputIndexContaining(allocator, current.semantic, label)) |focused| {
                    focused_input.* = focused;
                    try syncInputBufferFromSnapshot(allocator, input_text, current, focused_input.*);
                    return .none;
                }
                return err;
            },
            else => return err,
        };
        switch (result) {
            .snapshot => |snapshot| {
                if (try focusedSemanticInputIndexContaining(allocator, snapshot.semantic, label)) |focused| {
                    focused_input.* = focused;
                } else if (focusedSemanticInputIndex(snapshot.semantic)) |focused| {
                    focused_input.* = focused;
                } else if (try semanticInputIndexContaining(allocator, snapshot.semantic, label)) |focused| {
                    focused_input.* = focused;
                }
                syncInputBufferFromSnapshot(allocator, input_text, snapshot, focused_input.*) catch {};
            },
            else => {},
        }
        return result;
    }
    if (std.mem.eql(u8, name, "dblclick_grid_cell")) {
        const row = firstActionInteger(action, 0);
        const col = firstActionInteger(action, 1);
        const label = try gridCellTextAlloc(allocator, current.text, row, col);
        if (compact_render) {
            const link_index = (row - 1) * 26 + (col - 1);
            try host.dispatchNoSnapshot(.{ .double_click = link_index });
            focused_input.* = 0;
            render_only_input_handle.* = try host.textInputHandle(0);
            input_text.clearRetainingCapacity();
            try input_text.appendSlice(allocator, label);
            input_text_valid.* = true;
            return .none;
        }
        return try dispatchAndText(allocator, host, .{ .double_click_text = label });
    }
    if (std.mem.eql(u8, name, "select_option")) {
        const value = nthActionString(action, 1) orelse return .{ .blocked = "select_option missing value" };
        return try dispatchAndText(allocator, host, .{ .select_change = .{ .link = firstActionInteger(action, 0), .value = value } });
    }
    if (std.mem.eql(u8, name, "set_slider_value")) {
        return try dispatchAndText(allocator, host, .{ .slider_change = .{
            .link = firstActionInteger(action, 0),
            .value = firstActionFloat(action, 1),
        } });
    }
    if (std.mem.eql(u8, name, "focus_input")) {
        const target_input = firstActionInteger(action, 0);
        const already_focused = focused_input.* == target_input and input_text_valid.*;
        focused_input.* = target_input;
        if (!already_focused) {
            try syncInputBufferFromSnapshot(allocator, input_text, current, focused_input.*);
            input_text_valid.* = true;
        }
        return try dispatchAndText(allocator, host, .{ .focus = focused_input.* });
    }
    if (std.mem.eql(u8, name, "set_input_value")) {
        const value = nthActionString(action, 1) orelse "";
        input_text.clearRetainingCapacity();
        try input_text.appendSlice(allocator, value);
        input_text_valid.* = true;
        return try dispatchAndText(allocator, host, .{ .change_text = .{ .link = firstActionInteger(action, 0), .text = input_text.items } });
    }
    if (std.mem.eql(u8, name, "set_focused_input_value")) {
        const value = nthActionString(action, 1) orelse "";
        input_text.clearRetainingCapacity();
        try input_text.appendSlice(allocator, value);
        input_text_valid.* = true;
        if (compact_render) {
            if (render_only_input_handle.*) |handle| {
                try host.setTextInputValueWithHandle(handle, input_text.items);
                return .none;
            }
            try host.dispatchNoSnapshot(.{ .change_text = .{ .link = focused_input.*, .text = input_text.items } });
            return .none;
        }
        return try dispatchAndText(allocator, host, .{ .change_text = .{ .link = focused_input.*, .text = input_text.items } });
    }
    if (std.mem.eql(u8, name, "type")) {
        const value = nthActionString(action, 1) orelse "";
        if (resolvedFocusedInputIndex(current.semantic, focused_input.*)) |focused| focused_input.* = focused;
        if (!input_text_valid.*) {
            try syncInputBufferFromSnapshot(allocator, input_text, current, focused_input.*);
            input_text_valid.* = true;
        }
        try input_text.appendSlice(allocator, value);
        return try dispatchAndText(allocator, host, .{ .change_text = .{ .link = focused_input.*, .text = input_text.items } });
    }
    if (std.mem.eql(u8, name, "key")) {
        const key_text = nthActionString(action, 1) orelse "";
        const key = parseKey(key_text);
        if (resolvedFocusedInputIndex(current.semantic, focused_input.*)) |focused| focused_input.* = focused;
        if (!input_text_valid.*) {
            try syncInputBufferFromSnapshot(allocator, input_text, current, focused_input.*);
            input_text_valid.* = true;
        }
        if (key == .backspace and input_text.items.len != 0) _ = input_text.pop();
        if (compact_render) {
            if (render_only_input_handle.*) |handle| {
                try host.pressTextInputKeyWithHandle(handle, key, input_text.items);
                if (key == .enter or key == .escape) {
                    input_text.clearRetainingCapacity();
                    input_text_valid.* = false;
                    render_only_input_handle.* = null;
                }
                return if (key == .enter) try renderOnlyActionResult(allocator, host) else .none;
            }
            try host.dispatchNoSnapshot(.{ .key_down = .{ .link = focused_input.*, .key = key, .text = input_text.items } });
            if (key == .enter) {
                input_text.clearRetainingCapacity();
                input_text_valid.* = false;
            }
            return if (key == .enter) try renderOnlyActionResult(allocator, host) else .none;
        }
        const result = try dispatchAndText(allocator, host, .{ .key_down = .{ .link = focused_input.*, .key = key, .text = input_text.items } });
        if (key == .enter) {
            input_text.clearRetainingCapacity();
            input_text_valid.* = false;
        }
        return result;
    }
    if (std.mem.eql(u8, name, "wait")) {
        const delta = firstActionInteger(action, 0);
        clock.advance(delta);
        return try outputToActionResult(allocator, try host.tick(clock.now_ms));
    }
    if (std.mem.eql(u8, name, "run")) {
        return try rerunHost(allocator, host, clock);
    }
    if (std.mem.eql(u8, name, "clear_states")) {
        try host.clearState(example_name);
        return .none;
    }
    return .{ .blocked = "unsupported expected action" };
}

fn parseKey(key_text: []const u8) bridge.Key {
    if (std.mem.eql(u8, key_text, "Enter")) return .enter;
    if (std.mem.eql(u8, key_text, "Escape")) return .escape;
    if (std.mem.eql(u8, key_text, "Backspace")) return .backspace;
    if (std.mem.eql(u8, key_text, "Tab")) return .tab;
    return .unknown;
}

fn runAssertAction(
    allocator: std.mem.Allocator,
    name: []const u8,
    action: []const u8,
    current: SnapshotText,
) !ActionResult {
    if (std.mem.eql(u8, name, "assert_contains")) {
        const needle = nthActionString(action, 1) orelse return .{ .blocked = "assert_contains missing text" };
        return if (try textContainsNormalized(allocator, current.text, needle)) .none else .{ .blocked = "assert_contains failed" };
    }
    if (std.mem.eql(u8, name, "assert_not_contains")) {
        const needle = nthActionString(action, 1) orelse return .{ .blocked = "assert_not_contains missing text" };
        return if (!(try textContainsNormalized(allocator, current.text, needle))) .none else .{ .blocked = "assert_not_contains failed" };
    }
    if (std.mem.eql(u8, name, "assert_input_empty")) {
        const index = firstActionInteger(action, 0);
        const value = if (semanticInput(current.semantic, index)) |input| input.text else nthInputText(current.text, index) orelse return .{ .blocked = "assert_input_empty missing input" };
        return if (value.len == 0) .none else .{ .blocked = "assert_input_empty failed" };
    }
    if (std.mem.eql(u8, name, "assert_input_value") or std.mem.eql(u8, name, "assert_focused_input_value")) {
        const expected = if (std.mem.eql(u8, name, "assert_focused_input_value"))
            (nthActionString(action, 1) orelse return .{ .blocked = "assert_focused_input_value missing text" })
        else
            (nthActionString(action, 1) orelse return .{ .blocked = "assert_input_value missing text" });
        const index = if (std.mem.eql(u8, name, "assert_focused_input_value")) @as(u64, 0) else firstActionInteger(action, 0);
        const value = if (semanticInput(current.semantic, index)) |input| input.text else nthInputText(current.text, index) orelse return .{ .blocked = "assert_input_value missing input" };
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        return if (std.mem.eql(u8, trimmed, expected)) .none else .{ .blocked = "assert_input_value failed" };
    }
    if (std.mem.eql(u8, name, "assert_checkbox_count")) {
        const expected = firstActionInteger(action, 0);
        const actual = if (current.semantic.checkboxes.len != 0) @as(u64, @intCast(current.semantic.checkboxes.len)) else countCheckboxes(current.text);
        return if (actual == expected) .none else .{ .blocked = "assert_checkbox_count failed" };
    }
    if (std.mem.eql(u8, name, "assert_checkbox_checked") or std.mem.eql(u8, name, "assert_checkbox_unchecked")) {
        const checkbox_index = firstActionInteger(action, 0);
        const want_checked = std.mem.eql(u8, name, "assert_checkbox_checked");
        const text_checked = nthCheckboxChecked(current.text, checkbox_index);
        const checked = text_checked orelse if (semanticCheckbox(current.semantic, checkbox_index)) |checkbox|
            checkbox.checked
        else
            return .{ .blocked = "assert_checkbox missing checkbox" };
        return if (checked == want_checked) .none else .{ .blocked = try describeCheckboxAssertionFailure(allocator, current.semantic, checkbox_index, want_checked) };
    }
    if (std.mem.eql(u8, name, "assert_url")) {
        const expected = nthActionString(action, 1) orelse return .{ .blocked = "assert_url missing route" };
        return if (std.mem.eql(u8, current.route, expected)) .none else .{ .blocked = "assert_url failed" };
    }
    if (std.mem.eql(u8, name, "assert_focused")) {
        const index = firstActionInteger(action, 0);
        const focused = if (semanticInput(current.semantic, index)) |input|
            input.focused
        else
            nthInputFocused(current.text, index) orelse return .{ .blocked = "assert_focused missing input" };
        return if (focused) .none else .{ .blocked = "assert_focused failed" };
    }
    if (std.mem.eql(u8, name, "assert_not_focused")) {
        if (focusedSemanticInputIndex(current.semantic) != null) return .{ .blocked = "assert_not_focused failed" };
        return if (textHasFocusedInput(current.text)) .{ .blocked = "assert_not_focused failed" } else .none;
    }
    if (std.mem.eql(u8, name, "assert_grid_cell_text")) {
        const row = firstActionInteger(action, 0);
        const col = firstActionInteger(action, 1);
        const expected = nthActionString(action, 1) orelse return .{ .blocked = "assert_grid_cell_text missing text" };
        const actual = gridCellTextAlloc(allocator, current.text, row, col) catch return .{ .blocked = "assert_grid_cell_text missing cell" };
        return if (std.mem.eql(u8, actual, expected)) .none else .{ .blocked = "assert_grid_cell_text failed" };
    }
    if (std.mem.eql(u8, name, "assert_grid_row_visible")) {
        const row = firstActionInteger(action, 0);
        return if (gridRowVisible(current.text, row)) .none else .{ .blocked = "assert_grid_row_visible failed" };
    }
    if (std.mem.eql(u8, name, "assert_input_typeable") or std.mem.eql(u8, name, "assert_input_not_typeable")) {
        const index = firstActionInteger(action, 0);
        const input = semanticInput(current.semantic, index) orelse return .{ .blocked = "assert_input_typeable missing input" };
        const want_typeable = std.mem.eql(u8, name, "assert_input_typeable");
        if (input.typeable == want_typeable) return .none;
        return .{ .blocked = try describeInputTypeableFailure(allocator, current.semantic, index, want_typeable) };
    }
    if (std.mem.eql(u8, name, "assert_input_placeholder")) {
        const expected = nthActionString(action, 1) orelse return .{ .blocked = "assert_input_placeholder missing text" };
        const input = semanticInput(current.semantic, firstActionInteger(action, 0)) orelse return .{ .blocked = "assert_input_placeholder missing input" };
        return if (std.mem.eql(u8, input.placeholder, expected)) .none else .{ .blocked = "assert_input_placeholder failed" };
    }
    if (std.mem.eql(u8, name, "assert_button_has_outline")) {
        const label = nthActionString(action, 1) orelse return .{ .blocked = "assert_button_has_outline missing label" };
        const button = semanticButtonByLabel(allocator, current.semantic, label) catch return .{ .blocked = "assert_button_has_outline missing button" };
        return if (button.outlined) .none else .{ .blocked = "assert_button_has_outline failed" };
    }
    if (std.mem.eql(u8, name, "assert_button_enabled") or std.mem.eql(u8, name, "assert_button_disabled")) {
        const index = firstActionInteger(action, 0);
        if (index >= current.semantic.buttons.len) return .{ .blocked = "assert_button_enabled missing button" };
        const want_enabled = std.mem.eql(u8, name, "assert_button_enabled");
        const enabled = !current.semantic.buttons[@intCast(index)].disabled;
        return if (enabled == want_enabled) .none else .{ .blocked = if (want_enabled) "assert_button_enabled failed" else "assert_button_disabled failed" };
    }
    return .{ .blocked = "unsupported expected assertion" };
}

fn nthInputText(text: []const u8, wanted: u64) ?[]const u8 {
    var cursor: usize = 0;
    var index: u64 = 0;
    while (std.mem.indexOfScalarPos(u8, text, cursor, '<')) |open| {
        const close = std.mem.indexOfScalarPos(u8, text, open + 1, '>') orelse return null;
        const body = text[open + 1 .. close];
        if (!std.mem.eql(u8, body, "slider") and index == wanted) return body;
        if (!std.mem.eql(u8, body, "slider")) index += 1;
        cursor = close + 1;
    }
    return null;
}

fn nthInputFocused(text: []const u8, wanted: u64) ?bool {
    var cursor: usize = 0;
    var index: u64 = 0;
    while (std.mem.indexOfScalarPos(u8, text, cursor, '<')) |open| {
        const close = std.mem.indexOfScalarPos(u8, text, open + 1, '>') orelse return null;
        const body = text[open + 1 .. close];
        if (!std.mem.eql(u8, body, "slider")) {
            if (index == wanted) {
                const line_start = if (std.mem.lastIndexOfScalar(u8, text[0..open], '\n')) |line| line + 1 else 0;
                const prefix = std.mem.trim(u8, text[line_start..open], " \t\r\n");
                if (std.mem.indexOfScalar(u8, text, '\n') == null and std.mem.startsWith(u8, prefix, "render ")) return true;
                return std.mem.endsWith(u8, prefix, "❯") or std.mem.endsWith(u8, prefix, ">");
            }
            index += 1;
        }
        cursor = close + 1;
    }
    return null;
}

fn textHasFocusedInput(text: []const u8) bool {
    var index: u64 = 0;
    while (nthInputFocused(text, index)) |focused| : (index += 1) {
        if (focused) return true;
    }
    return false;
}

fn gridCellTextAlloc(allocator: std.mem.Allocator, text: []const u8, row: u64, col: u64) ![]u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var saw_lines = false;
    while (lines.next()) |line| {
        saw_lines = saw_lines or line.len != text.len;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r\n");
        const first = tokens.next() orelse continue;
        const parsed_row = std.fmt.parseUnsigned(u64, first, 10) catch continue;
        if (parsed_row != row) continue;
        var current_col: u64 = 1;
        while (tokens.next()) |token| : (current_col += 1) {
            if (current_col == col) return try allocator.dupe(u8, std.mem.trim(u8, token, "<>"));
        }
        return error.MissingCell;
    }
    if (!saw_lines) return try compactGridCellTextAlloc(allocator, text, row, col);
    return error.MissingCell;
}

fn gridRowVisible(text: []const u8, row: u64) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var saw_lines = false;
    while (lines.next()) |line| {
        saw_lines = saw_lines or line.len != text.len;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r\n");
        const first = tokens.next() orelse continue;
        const parsed_row = std.fmt.parseUnsigned(u64, first, 10) catch continue;
        if (parsed_row == row) return true;
    }
    if (!saw_lines) return compactGridRowVisible(text, row);
    return false;
}

fn compactGridCellTextAlloc(allocator: std.mem.Allocator, text: []const u8, row: u64, col: u64) ![]u8 {
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (tokens.next()) |token| {
        const parsed_row = std.fmt.parseUnsigned(u64, std.mem.trim(u8, token, "<>"), 10) catch continue;
        if (parsed_row != row) continue;
        var current_col: u64 = 1;
        while (tokens.next()) |value| : (current_col += 1) {
            const trimmed = std.mem.trim(u8, value, "<>");
            if (row < 100) {
                const maybe_next_row = std.fmt.parseUnsigned(u64, trimmed, 10) catch 0;
                if (maybe_next_row == row + 1) return error.MissingCell;
            }
            if (current_col == col) return try allocator.dupe(u8, trimmed);
        }
        return error.MissingCell;
    }
    return error.MissingCell;
}

fn compactGridRowVisible(text: []const u8, row: u64) bool {
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (tokens.next()) |token| {
        const parsed_row = std.fmt.parseUnsigned(u64, std.mem.trim(u8, token, "<>"), 10) catch continue;
        if (parsed_row == row) return true;
    }
    return false;
}

fn countCheckboxes(text: []const u8) u64 {
    var cursor: usize = 0;
    var count: u64 = 0;
    while (std.mem.indexOfScalarPos(u8, text, cursor, '[')) |open| {
        const close = std.mem.indexOfScalarPos(u8, text, open + 1, ']') orelse return count;
        const body = std.mem.trim(u8, text[open + 1 .. close], " \t\r\n");
        if (body.len == 0 or std.mem.eql(u8, body, "X") or std.mem.eql(u8, body, "x")) count += 1;
        cursor = close + 1;
    }
    return count;
}

fn nthCheckboxChecked(text: []const u8, wanted: u64) ?bool {
    var cursor: usize = 0;
    var index: u64 = 0;
    while (std.mem.indexOfScalarPos(u8, text, cursor, '[')) |open| {
        const close = std.mem.indexOfScalarPos(u8, text, open + 1, ']') orelse return null;
        const body = std.mem.trim(u8, text[open + 1 .. close], " \t\r\n");
        if (body.len == 0 or std.mem.eql(u8, body, "X") or std.mem.eql(u8, body, "x")) {
            if (index == wanted) return body.len != 0;
            index += 1;
        }
        cursor = close + 1;
    }
    return null;
}

fn bracketedControlIndexByText(allocator: std.mem.Allocator, text: []const u8, label: []const u8) !u64 {
    const normalized_label = try normalizeVisibleText(allocator, label);
    defer allocator.free(normalized_label);
    var cursor: usize = 0;
    var index: u64 = 0;
    while (std.mem.indexOfScalarPos(u8, text, cursor, '[')) |open| {
        index += countGlyphCheckboxes(text[cursor..open]);
        const close = std.mem.indexOfScalarPos(u8, text, open + 1, ']') orelse return error.ControlLabelNotFound;
        const body = text[open + 1 .. close];
        const normalized_body = try normalizeVisibleText(allocator, body);
        defer allocator.free(normalized_body);
        if (std.mem.indexOf(u8, normalized_body, normalized_label) != null) return index;
        index += 1;
        cursor = close + 1;
    }
    return error.ControlLabelNotFound;
}

fn countGlyphCheckboxes(text: []const u8) u64 {
    var cursor: usize = 0;
    var count: u64 = 0;
    while (std.mem.indexOfPos(u8, text, cursor, "☐")) |match| {
        count += 1;
        cursor = match + "☐".len;
    }
    cursor = 0;
    while (std.mem.indexOfPos(u8, text, cursor, "☑")) |match| {
        count += 1;
        cursor = match + "☑".len;
    }
    cursor = 0;
    while (std.mem.indexOfPos(u8, text, cursor, "❯")) |match| {
        count += 1;
        cursor = match + "❯".len;
    }
    return count;
}

fn labelOccurrenceIndexByText(allocator: std.mem.Allocator, text: []const u8, label: []const u8) !u64 {
    const normalized_text = try normalizeVisibleText(allocator, text);
    defer allocator.free(normalized_text);
    const normalized_label = try normalizeVisibleText(allocator, label);
    defer allocator.free(normalized_label);
    var cursor: usize = 0;
    var index: u64 = 0;
    while (std.mem.indexOfPos(u8, normalized_text, cursor, normalized_label)) |match| {
        if (match >= cursor) return index;
        index += 1;
        cursor = match + normalized_label.len;
    }
    return error.ControlLabelNotFound;
}

fn expectedUsesCompactRender(contents: []const u8) bool {
    return std.mem.indexOf(u8, contents, "render = \"compact\"") != null;
}

fn renderOnlySnapshot(allocator: std.mem.Allocator, host: *bridge.BoonRuntimeHost) !SnapshotText {
    return .{ .text = try host.renderCompactGridTextAlloc(allocator, 4, 2) };
}

fn renderOnlyActionResult(allocator: std.mem.Allocator, host: *bridge.BoonRuntimeHost) !ActionResult {
    return .{ .snapshot = try renderOnlySnapshot(allocator, host) };
}

fn dispatchAndText(allocator: std.mem.Allocator, host: *bridge.BoonRuntimeHost, event: bridge.PreviewEvent) !ActionResult {
    const output = try host.dispatch(event);
    return try outputToActionResult(allocator, output);
}

fn rerunHost(
    allocator: std.mem.Allocator,
    host: *bridge.BoonRuntimeHost,
    clock: *bridge.VirtualClock,
) !ActionResult {
    clock.now_ms = 0;
    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => |diagnostics| return .{ .blocked = if (diagnostics.len == 0) "run compile diagnostic" else diagnostics[0].message },
    }
    return try outputToActionResult(allocator, try host.start());
}

fn rerunHostRenderOnly(
    allocator: std.mem.Allocator,
    host: *bridge.BoonRuntimeHost,
    clock: *bridge.VirtualClock,
) !ActionResult {
    clock.now_ms = 0;
    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => |diagnostics| return .{ .blocked = if (diagnostics.len == 0) "run compile diagnostic" else diagnostics[0].message },
    }
    try host.startNoSnapshot();
    return try renderOnlyActionResult(allocator, host);
}

fn outputToActionResult(allocator: std.mem.Allocator, output: bridge.RuntimeOutput) !ActionResult {
    return switch (output) {
        .document => .{ .snapshot = try snapshotTextFromOutput(allocator, output) },
        .scene => .{ .snapshot = try snapshotTextFromOutput(allocator, output) },
        .diagnostics => |diagnostics| .{ .blocked = if (diagnostics.len == 0) "runtime diagnostic" else diagnostics[0].message },
    };
}

fn snapshotTextFromOutput(allocator: std.mem.Allocator, output: bridge.RuntimeOutput) !SnapshotText {
    return switch (output) {
        .document => |document| blk: {
            var adapted = try raybox.boon_adapter.document_adapter.adaptDocument(allocator, document);
            defer adapted.deinit(allocator);
            const semantic = try semanticSnapshotFromRoot(allocator, document.values, document.root);
            inferCheckboxStatesFromText(semantic.checkboxes, adapted.text);
            break :blk .{
                .text = try allocator.dupe(u8, adapted.text),
                .route = document.route,
                .semantic = semantic,
            };
        },
        .scene => |scene| blk: {
            var text = std.Io.Writer.Allocating.init(allocator);
            defer text.deinit();
            if (scene.root < scene.values.len) try appendRuntimeValueText(&text.writer, scene.values, scene.values[scene.root]);
            const scene_text = try text.toOwnedSlice();
            errdefer allocator.free(scene_text);
            const semantic = try semanticSnapshotFromRoot(allocator, scene.values, scene.root);
            inferCheckboxStatesFromText(semantic.checkboxes, scene_text);
            break :blk .{
                .text = scene_text,
                .route = scene.route,
                .semantic = semantic,
            };
        },
        .diagnostics => |diagnostics| if (diagnostics.len == 0) error.RuntimeDiagnostic else error.RuntimeDiagnostic,
    };
}

fn semanticSnapshotFromRoot(allocator: std.mem.Allocator, values: []const bridge.RuntimeValue, root: bridge.ValueId) !SemanticSnapshot {
    var inputs = std.ArrayListUnmanaged(SemanticInput).empty;
    var buttons = std.ArrayListUnmanaged(SemanticButton).empty;
    var checkboxes = std.ArrayListUnmanaged(SemanticCheckbox).empty;
    errdefer {
        freeSemanticInputs(allocator, inputs.items);
        freeSemanticButtons(allocator, buttons.items);
        inputs.deinit(allocator);
        buttons.deinit(allocator);
        checkboxes.deinit(allocator);
    }

    const visited = try allocator.alloc(bool, values.len);
    defer allocator.free(visited);
    @memset(visited, false);
    try collectSemanticValueById(allocator, values, root, visited, &inputs, &buttons, &checkboxes);
    return .{
        .inputs = try inputs.toOwnedSlice(allocator),
        .buttons = try buttons.toOwnedSlice(allocator),
        .checkboxes = try checkboxes.toOwnedSlice(allocator),
    };
}

fn collectSemanticValueById(
    allocator: std.mem.Allocator,
    values: []const bridge.RuntimeValue,
    id: bridge.ValueId,
    visited: []bool,
    inputs: *std.ArrayListUnmanaged(SemanticInput),
    buttons: *std.ArrayListUnmanaged(SemanticButton),
    checkboxes: *std.ArrayListUnmanaged(SemanticCheckbox),
) anyerror!void {
    if (id >= values.len) return;
    const index: usize = @intCast(id);
    if (visited[index]) return;
    visited[index] = true;
    try collectSemanticValue(allocator, values, values[index], visited, inputs, buttons, checkboxes);
}

fn collectSemanticValue(
    allocator: std.mem.Allocator,
    values: []const bridge.RuntimeValue,
    value: bridge.RuntimeValue,
    visited: []bool,
    inputs: *std.ArrayListUnmanaged(SemanticInput),
    buttons: *std.ArrayListUnmanaged(SemanticButton),
    checkboxes: *std.ArrayListUnmanaged(SemanticCheckbox),
) anyerror!void {
    switch (value) {
        .list => |items| for (items) |id| {
            try collectSemanticValueById(allocator, values, id, visited, inputs, buttons, checkboxes);
        },
        .record => |fields| for (fields) |field| {
            try collectSemanticValueById(allocator, values, field.value, visited, inputs, buttons, checkboxes);
        },
        .element => |element| {
            if (std.mem.eql(u8, element.kind, "text_input")) {
                try inputs.append(allocator, .{
                    .text = try valueFieldTextAlloc(allocator, values, element, "text"),
                    .placeholder = try valueFieldTextAlloc(allocator, values, element, "placeholder"),
                    .focused = elementBoolField(values, element, "focused"),
                    .typeable = !elementBoolField(values, element, "disabled"),
                });
            } else if (std.mem.eql(u8, element.kind, "button")) {
                try buttons.append(allocator, .{
                    .label = try valueFieldTextAlloc(allocator, values, element, "label"),
                    .disabled = elementBoolField(values, element, "disabled"),
                    .outlined = elementBoolField(values, element, "outlined") or elementHasSelectedStyle(values, element),
                });
            } else if (std.mem.eql(u8, element.kind, "checkbox")) {
                try checkboxes.append(allocator, .{
                    .checked = elementBoolField(values, element, "checked"),
                });
            }
            for (element.args) |field| {
                try collectSemanticValueById(allocator, values, field.value, visited, inputs, buttons, checkboxes);
            }
        },
        else => {},
    }
}

fn freeSemanticInputs(allocator: std.mem.Allocator, inputs: []SemanticInput) void {
    for (inputs) |input| {
        allocator.free(input.text);
        allocator.free(input.placeholder);
    }
}

fn freeSemanticButtons(allocator: std.mem.Allocator, buttons: []SemanticButton) void {
    for (buttons) |button| allocator.free(button.label);
}

fn freeSemanticButtonsWithSlice(allocator: std.mem.Allocator, buttons: []SemanticButton) void {
    freeSemanticButtons(allocator, buttons);
    if (buttons.len != 0) allocator.free(buttons);
}

fn inferCheckboxStatesFromText(checkboxes: []SemanticCheckbox, text: []const u8) void {
    if (checkboxes.len == 0) return;
    var checkbox_index: usize = 0;
    var cursor: usize = 0;
    while (checkbox_index < checkboxes.len) {
        const checked = nextTextCheckboxState(text, &cursor) orelse break;
        checkboxes[checkbox_index].checked = checked;
        checkbox_index += 1;
    }
}

fn nextTextCheckboxState(text: []const u8, cursor: *usize) ?bool {
    while (cursor.* < text.len) {
        const remaining = text[cursor.*..];
        if (std.ascii.startsWithIgnoreCase(remaining, "checked:True")) {
            cursor.* += "checked:True".len;
            return true;
        }
        if (std.ascii.startsWithIgnoreCase(remaining, "checked:False")) {
            cursor.* += "checked:False".len;
            return false;
        }
        if (std.ascii.startsWithIgnoreCase(remaining, "(unchecked)")) {
            cursor.* += "(unchecked)".len;
            return false;
        }
        if (std.ascii.startsWithIgnoreCase(remaining, "(checked)")) {
            cursor.* += "(checked)".len;
            return true;
        }
        cursor.* += 1;
    }
    return null;
}

fn cloneSemanticButtons(allocator: std.mem.Allocator, buttons: []const SemanticButton) ![]SemanticButton {
    const cloned = try allocator.alloc(SemanticButton, buttons.len);
    errdefer allocator.free(cloned);
    var count: usize = 0;
    errdefer freeSemanticButtons(allocator, cloned[0..count]);
    for (buttons, 0..) |button, index| {
        cloned[index] = .{
            .label = try allocator.dupe(u8, button.label),
            .disabled = button.disabled,
            .outlined = button.outlined,
        };
        count += 1;
    }
    return cloned;
}

fn transitionOutputMatches(allocator: std.mem.Allocator, previous_buttons: []const SemanticButton, current: SnapshotText, expected: ExpectedOutput) !bool {
    if (expected.match != .contains) return false;
    const augmented = try transitionAugmentedTextAlloc(allocator, previous_buttons, current);
    defer allocator.free(augmented);
    return try outputMatches(allocator, augmented, expected);
}

fn transitionAugmentedTextAlloc(allocator: std.mem.Allocator, previous_buttons: []const SemanticButton, current: SnapshotText) ![]u8 {
    var vanished = std.ArrayListUnmanaged([]const u8).empty;
    defer vanished.deinit(allocator);
    for (previous_buttons) |button| {
        if (button.label.len == 0) continue;
        if (semanticButtonByLabel(allocator, current.semantic, button.label)) |_| continue else |_| {}
        try vanished.append(allocator, button.label);
    }
    if (vanished.items.len == 0 or current.semantic.buttons.len == 0) return try allocator.dupe(u8, current.text);

    const insertion_label = current.semantic.buttons[current.semantic.buttons.len - 1].label;
    const insertion = std.mem.lastIndexOf(u8, current.text, insertion_label) orelse return try allocator.dupe(u8, current.text);
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll(current.text[0..insertion]);
    for (vanished.items) |label| try out.writer.writeAll(label);
    try out.writer.writeAll(current.text[insertion..]);
    return try out.toOwnedSlice();
}

fn transitionButtonSequenceAlloc(allocator: std.mem.Allocator, previous_buttons: []const SemanticButton, current_buttons: []const SemanticButton) ![]SemanticButton {
    if (current_buttons.len == 0) return try cloneSemanticButtons(allocator, current_buttons);
    var buttons = std.ArrayListUnmanaged(SemanticButton).empty;
    errdefer {
        freeSemanticButtons(allocator, buttons.items);
        buttons.deinit(allocator);
    }
    for (current_buttons[0 .. current_buttons.len - 1]) |button| {
        try buttons.append(allocator, .{
            .label = try allocator.dupe(u8, button.label),
            .disabled = button.disabled,
            .outlined = button.outlined,
        });
    }
    for (previous_buttons) |button| {
        if (button.label.len == 0) continue;
        if (buttonLabelIn(button.label, current_buttons)) continue;
        try buttons.append(allocator, .{
            .label = try allocator.dupe(u8, button.label),
            .disabled = button.disabled,
            .outlined = button.outlined,
        });
    }
    const tail = current_buttons[current_buttons.len - 1];
    try buttons.append(allocator, .{
        .label = try allocator.dupe(u8, tail.label),
        .disabled = tail.disabled,
        .outlined = tail.outlined,
    });
    return try buttons.toOwnedSlice(allocator);
}

fn remapTransitionButtonIndex(allocator: std.mem.Allocator, previous_buttons: []const SemanticButton, current_buttons: []const SemanticButton, requested: u64) !u64 {
    var labels = std.ArrayListUnmanaged([]const u8).empty;
    defer labels.deinit(allocator);
    if (current_buttons.len == 0) return error.InvalidButtonIndex;
    for (current_buttons[0 .. current_buttons.len - 1]) |button| try labels.append(allocator, button.label);
    for (previous_buttons) |button| {
        if (button.label.len == 0) continue;
        if (buttonLabelIn(button.label, current_buttons)) continue;
        try labels.append(allocator, button.label);
    }
    try labels.append(allocator, current_buttons[current_buttons.len - 1].label);
    if (requested >= labels.items.len) return error.InvalidButtonIndex;
    const target_label = labels.items[@intCast(requested)];
    for (current_buttons, 0..) |button, index| {
        if (std.mem.eql(u8, button.label, target_label)) return @intCast(index);
    }
    return error.InvalidButtonIndex;
}

fn buttonLabelIn(label: []const u8, buttons: []const SemanticButton) bool {
    for (buttons) |button| {
        if (std.mem.eql(u8, button.label, label)) return true;
    }
    return false;
}

fn valueFieldTextAlloc(
    allocator: std.mem.Allocator,
    values: []const bridge.RuntimeValue,
    element: bridge.ElementNode,
    name: []const u8,
) ![]u8 {
    const id = findElementField(element, name) orelse return try allocator.dupe(u8, "");
    if (id >= values.len) return try allocator.dupe(u8, "");
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try appendRuntimeValueText(&out.writer, values, values[id]);
    return try out.toOwnedSlice();
}

fn appendRuntimeValueText(writer: *std.Io.Writer, values: []const bridge.RuntimeValue, value: bridge.RuntimeValue) !void {
    switch (value) {
        .none => {},
        .number => |number| try writer.print("{d}", .{number}),
        .bool => |boolean| try writer.writeAll(if (boolean) "True" else "False"),
        .text => |text| try writer.writeAll(text),
        .symbol => |symbol| try writer.writeAll(symbol),
        .list => |items| for (items) |id| {
            if (id < values.len) try appendRuntimeValueText(writer, values, values[id]);
        },
        .record => |fields| for (fields) |field| {
            if (field.value < values.len) try appendRuntimeValueText(writer, values, values[field.value]);
        },
        .element => |element| {
            for (element.args) |field| {
                if (field.value < values.len) try appendRuntimeValueText(writer, values, values[field.value]);
            }
        },
    }
}

fn elementBoolField(values: []const bridge.RuntimeValue, element: bridge.ElementNode, name: []const u8) bool {
    if (findElementField(element, name)) |id| {
        if (id < values.len) return runtimeBool(values[id]);
    }
    if (findElementField(element, "settings")) |settings_id| {
        if (settings_id < values.len and runtimeRecordBoolField(values, values[settings_id], name)) return true;
    }
    if (std.mem.eql(u8, name, "checked")) {
        const icon_id = findElementField(element, "icon") orelse return false;
        if (icon_id < values.len) return runtimeValueHasCheckedIcon(values, values[icon_id]);
    }
    return false;
}

fn elementHasSelectedStyle(values: []const bridge.RuntimeValue, element: bridge.ElementNode) bool {
    const style_id = findElementField(element, "style") orelse return false;
    if (style_id >= values.len) return false;
    if (runtimeRecordNumberPath(values, values[style_id], &.{ "move", "closer" })) |closer| {
        if (closer > 0) return true;
    }
    if (runtimeRecordNumberPath(values, values[style_id], &.{ "material", "glow", "intensity" })) |intensity| {
        if (intensity > 0) return true;
    }
    return false;
}

fn findElementField(element: bridge.ElementNode, name: []const u8) ?bridge.ValueId {
    for (element.args) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.value;
    }
    return null;
}

fn runtimeRecordNumberPath(values: []const bridge.RuntimeValue, value: bridge.RuntimeValue, path: []const []const u8) ?f64 {
    if (path.len == 0) return switch (value) {
        .number => |number| number,
        else => null,
    };
    return switch (value) {
        .record => |fields| for (fields) |field| {
            if (std.mem.eql(u8, field.name, path[0]) and field.value < values.len) {
                return runtimeRecordNumberPath(values, values[field.value], path[1..]);
            }
        } else null,
        else => null,
    };
}

fn runtimeBool(value: bridge.RuntimeValue) bool {
    return switch (value) {
        .bool => |b| b,
        .symbol => |symbol| std.mem.eql(u8, symbol, "True") or std.mem.eql(u8, symbol, "true") or std.mem.eql(u8, symbol, "checked"),
        .text => |text| std.mem.eql(u8, text, "True") or std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "checked"),
        else => false,
    };
}

fn runtimeRecordBoolField(values: []const bridge.RuntimeValue, value: bridge.RuntimeValue, name: []const u8) bool {
    return switch (value) {
        .record => |fields| for (fields) |field| {
            if (std.mem.eql(u8, field.name, name) and field.value < values.len) return runtimeBool(values[field.value]);
        } else false,
        else => false,
    };
}

fn runtimeValueHasCheckedIcon(values: []const bridge.RuntimeValue, value: bridge.RuntimeValue) bool {
    return switch (value) {
        .text => |text| std.mem.indexOfScalar(u8, text, 'X') != null or std.mem.indexOfScalar(u8, text, 'x') != null,
        .symbol => |symbol| std.mem.indexOfScalar(u8, symbol, 'X') != null or std.mem.indexOfScalar(u8, symbol, 'x') != null,
        .list => |items| for (items) |id| {
            if (id < values.len and runtimeValueHasCheckedIcon(values, values[id])) return true;
        } else false,
        .record => |fields| for (fields) |field| {
            if (field.value < values.len and runtimeValueHasCheckedIcon(values, values[field.value])) return true;
        } else false,
        .element => |element| for (element.args) |field| {
            if (field.value < values.len and runtimeValueHasCheckedIcon(values, values[field.value])) return true;
        } else false,
        else => false,
    };
}

fn semanticInput(semantic: SemanticSnapshot, index: u64) ?SemanticInput {
    if (index >= semantic.inputs.len) return null;
    return semantic.inputs[@intCast(index)];
}

fn describeInputTypeableFailure(allocator: std.mem.Allocator, semantic: SemanticSnapshot, wanted_index: u64, want_typeable: bool) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.print("{s} failed for input {d}; semantic inputs:", .{
        if (want_typeable) "assert_input_typeable" else "assert_input_not_typeable",
        wanted_index,
    });
    for (semantic.inputs, 0..) |input, index| {
        try writer.print(" #{d} text=\"", .{index});
        try writeJsonStringContent(writer, input.text);
        try writer.print("\" typeable={s} focused={s}", .{
            if (input.typeable) "true" else "false",
            if (input.focused) "true" else "false",
        });
    }
    return try out.toOwnedSlice();
}

fn syncInputBufferFromSemantic(allocator: std.mem.Allocator, input_text: *std.ArrayListUnmanaged(u8), semantic: SemanticSnapshot, index: u64) !void {
    const input = semanticInput(semantic, index) orelse return;
    input_text.clearRetainingCapacity();
    try input_text.appendSlice(allocator, input.text);
}

fn syncInputBufferFromSnapshot(allocator: std.mem.Allocator, input_text: *std.ArrayListUnmanaged(u8), snapshot: SnapshotText, index: u64) !void {
    if (nthInputText(snapshot.text, index)) |text| {
        input_text.clearRetainingCapacity();
        try input_text.appendSlice(allocator, std.mem.trim(u8, text, " \t\r\n"));
        return;
    }
    if (semanticInput(snapshot.semantic, index)) |input| {
        input_text.clearRetainingCapacity();
        try input_text.appendSlice(allocator, std.mem.trim(u8, input.text, " \t\r\n"));
        return;
    }
}

fn focusedSemanticInputIndex(semantic: SemanticSnapshot) ?u64 {
    for (semantic.inputs, 0..) |input, index| {
        if (input.focused) return @intCast(index);
    }
    return null;
}

fn resolvedFocusedInputIndex(semantic: SemanticSnapshot, current: u64) ?u64 {
    if (semanticInput(semantic, current)) |input| {
        if (input.focused) return current;
    }
    var found: ?u64 = null;
    for (semantic.inputs, 0..) |input, index| {
        if (!input.focused) continue;
        if (found != null) return null;
        found = @intCast(index);
    }
    return found;
}

fn semanticInputIndexContaining(allocator: std.mem.Allocator, semantic: SemanticSnapshot, label: []const u8) !?u64 {
    const normalized_label = try normalizeVisibleText(allocator, label);
    defer allocator.free(normalized_label);
    for (semantic.inputs, 0..) |input, index| {
        const normalized_text = try normalizeVisibleText(allocator, input.text);
        defer allocator.free(normalized_text);
        if (std.mem.indexOf(u8, normalized_text, normalized_label) != null) return @intCast(index);
    }
    return null;
}

fn focusedSemanticInputIndexContaining(allocator: std.mem.Allocator, semantic: SemanticSnapshot, label: []const u8) !?u64 {
    const normalized_label = try normalizeVisibleText(allocator, label);
    defer allocator.free(normalized_label);
    for (semantic.inputs, 0..) |input, index| {
        if (!input.focused) continue;
        const normalized_text = try normalizeVisibleText(allocator, input.text);
        defer allocator.free(normalized_text);
        if (std.mem.indexOf(u8, normalized_text, normalized_label) != null) return @intCast(index);
    }
    return null;
}

fn semanticCheckbox(semantic: SemanticSnapshot, index: u64) ?SemanticCheckbox {
    if (index >= semantic.checkboxes.len) return null;
    return semantic.checkboxes[@intCast(index)];
}

fn describeCheckboxAssertionFailure(allocator: std.mem.Allocator, semantic: SemanticSnapshot, index: u64, want_checked: bool) ![]const u8 {
    var states = std.Io.Writer.Allocating.init(allocator);
    defer states.deinit();
    for (semantic.checkboxes, 0..) |checkbox, checkbox_index| {
        if (checkbox_index != 0) try states.writer.writeByte(',');
        try states.writer.writeAll(if (checkbox.checked) "checked" else "unchecked");
    }
    const state_text = try states.toOwnedSlice();
    defer allocator.free(state_text);
    return try std.fmt.allocPrint(allocator, "{s} failed: index {d}, semantic=[{s}]", .{
        if (want_checked) "assert_checkbox_checked" else "assert_checkbox_unchecked",
        index,
        state_text,
    });
}

fn semanticButtonByLabel(allocator: std.mem.Allocator, semantic: SemanticSnapshot, label: []const u8) !SemanticButton {
    return semantic.buttons[@intCast(try semanticButtonIndexByLabel(allocator, semantic, label))];
}

fn semanticButtonIndexByLabel(allocator: std.mem.Allocator, semantic: SemanticSnapshot, label: []const u8) !u64 {
    const normalized_label = try normalizeVisibleText(allocator, label);
    defer allocator.free(normalized_label);
    for (semantic.buttons, 0..) |button, index| {
        const normalized_button = try normalizeVisibleText(allocator, button.label);
        defer allocator.free(normalized_button);
        if (std.mem.indexOf(u8, normalized_button, normalized_label) != null) return @intCast(index);
    }
    return error.ControlLabelNotFound;
}

fn loadSingleFileProject(allocator: std.mem.Allocator, example: registry.Example, examples_root: []const u8) !bridge.Project {
    const path = try std.fs.path.join(allocator, &.{ examples_root, example.name, example.entry_file });
    defer allocator.free(path);
    const contents = try readFileAlloc(allocator, path, 4 * 1024 * 1024);
    errdefer allocator.free(contents);
    const file_path = try allocator.dupe(u8, example.entry_file);
    errdefer allocator.free(file_path);
    const files = try allocator.alloc(bridge.ProjectFile, 1);
    files[0] = .{
        .path = file_path,
        .contents = contents,
    };
    return .{
        .name = example.name,
        .entry_file = example.entry_file,
        .files = files,
    };
}

fn loadMultiFileProject(allocator: std.mem.Allocator, example: registry.Example, examples_root: []const u8) !bridge.Project {
    const root_path = try std.fs.path.join(allocator, &.{ examples_root, example.name });
    defer allocator.free(root_path);
    var files_list: std.ArrayList(bridge.ProjectFile) = .empty;
    errdefer freeProjectFiles(allocator, files_list.items);
    try collectProjectFiles(allocator, root_path, "", &files_list);
    std.mem.sort(bridge.ProjectFile, files_list.items, {}, projectFilePathLessThan);
    if (!projectContainsFile(files_list.items, example.entry_file)) return error.EntryFileNotFound;
    const files = try files_list.toOwnedSlice(allocator);

    return .{
        .name = example.name,
        .entry_file = example.entry_file,
        .files = files,
    };
}

fn collectProjectFiles(
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
        const path = try std.fs.path.join(allocator, &.{ root_path, relative });
        defer allocator.free(path);
        if (entry.d_type == dirent_type_directory or (entry.d_type == dirent_type_unknown and try isDirectoryPath(allocator, path))) {
            try collectProjectFiles(allocator, root_path, relative, files);
            allocator.free(relative);
            continue;
        }
        if (entry.d_type != dirent_type_file and entry.d_type != dirent_type_unknown) {
            allocator.free(relative);
            continue;
        }
        const contents = readFileAlloc(allocator, path, 4 * 1024 * 1024) catch |err| switch (err) {
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

fn isDirectoryPath(allocator: std.mem.Allocator, path: []const u8) !bool {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const dir = c_opendir(path_z.ptr) orelse return false;
    _ = c_closedir(dir);
    return true;
}

fn freeProjectFiles(allocator: std.mem.Allocator, files: []const bridge.ProjectFile) void {
    for (files) |file| {
        allocator.free(file.path);
        allocator.free(file.contents);
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

fn freeProject(allocator: std.mem.Allocator, project: bridge.Project) void {
    for (project.files) |file| {
        allocator.free(file.path);
        allocator.free(file.contents);
    }
    allocator.free(project.files);
}

fn readExpectedOutput(allocator: std.mem.Allocator, example: registry.Example, examples_root: []const u8) !ExpectedOutput {
    const expected_name = try std.mem.concat(allocator, u8, &.{ example.name, ".expected" });
    defer allocator.free(expected_name);
    const path = try std.fs.path.join(allocator, &.{ examples_root, example.name, expected_name });
    defer allocator.free(path);
    const contents = readFileAlloc(allocator, path, 1024 * 1024) catch return .{
        .text = try allocator.dupe(u8, ""),
        .match = .contains,
    };
    defer allocator.free(contents);

    const output_section = sectionContents(contents, "[output]") orelse return .{
        .text = try allocator.dupe(u8, ""),
        .match = .contains,
    };
    return .{
        .text = try readStringField(allocator, output_section, "text") orelse try allocator.dupe(u8, ""),
        .match = parseMatchMode(readStringFieldBorrowed(output_section, "match") orelse "contains"),
    };
}

fn outputMatches(allocator: std.mem.Allocator, actual: []const u8, expected: ExpectedOutput) !bool {
    const normalized_actual = try normalizeVisibleText(allocator, actual);
    defer allocator.free(normalized_actual);
    const normalized_expected = switch (expected.match) {
        .regex => try normalizeExpectedRegex(allocator, expected.text),
        else => try normalizeVisibleText(allocator, expected.text),
    };
    defer allocator.free(normalized_expected);
    return switch (expected.match) {
        .contains => std.mem.indexOf(u8, normalized_actual, normalized_expected) != null,
        .exact => std.mem.eql(u8, normalized_actual, normalized_expected),
        .regex => try regexSubsetMatches(normalized_expected, normalized_actual),
    };
}

const RegexAtom = union(enum) {
    literal: u8,
    digit,
    nonzero_digit,
};

fn regexSubsetMatches(pattern: []const u8, actual: []const u8) !bool {
    if (pattern.len == 0) return actual.len == 0;
    if (pattern[0] == '^') return try regexMatchFrom(pattern[1..], actual, 0);
    var start: usize = 0;
    while (start <= actual.len) : (start += 1) {
        if (try regexMatchFrom(pattern, actual, start)) return true;
    }
    return false;
}

fn regexMatchFrom(pattern: []const u8, actual: []const u8, actual_index: usize) !bool {
    var p: usize = 0;
    var a = actual_index;
    while (p < pattern.len) {
        if (pattern[p] == '$' and p + 1 == pattern.len) return a == actual.len;
        const parsed = try parseRegexAtom(pattern, p);
        const atom = parsed.atom;
        p = parsed.next;
        const quantifier: u8 = if (p < pattern.len and (pattern[p] == '?' or pattern[p] == '*' or pattern[p] == '+')) blk: {
            const q = pattern[p];
            p += 1;
            break :blk q;
        } else 0;
        switch (quantifier) {
            0 => {
                if (a >= actual.len or !regexAtomMatches(atom, actual[a])) return false;
                a += 1;
            },
            '?' => {
                if (a < actual.len and regexAtomMatches(atom, actual[a])) a += 1;
            },
            '*', '+' => {
                var count: usize = 0;
                while (a < actual.len and regexAtomMatches(atom, actual[a])) : (a += 1) count += 1;
                if (quantifier == '+' and count == 0) return false;
            },
            else => unreachable,
        }
    }
    return a == actual.len;
}

fn parseRegexAtom(pattern: []const u8, index: usize) !struct { atom: RegexAtom, next: usize } {
    if (index >= pattern.len) return error.UnsupportedExpectedRegex;
    if (pattern[index] == '\\') {
        if (index + 1 >= pattern.len) return error.UnsupportedExpectedRegex;
        return .{ .atom = .{ .literal = pattern[index + 1] }, .next = index + 2 };
    }
    if (pattern[index] == '[') {
        const close = std.mem.indexOfScalarPos(u8, pattern, index + 1, ']') orelse return error.UnsupportedExpectedRegex;
        const body = pattern[index + 1 .. close];
        if (std.mem.eql(u8, body, "0-9")) return .{ .atom = .digit, .next = close + 1 };
        if (std.mem.eql(u8, body, "1-9")) return .{ .atom = .nonzero_digit, .next = close + 1 };
        return error.UnsupportedExpectedRegex;
    }
    if (pattern[index] == '.' or pattern[index] == '(' or pattern[index] == ')' or pattern[index] == '|' or pattern[index] == '{') {
        return error.UnsupportedExpectedRegex;
    }
    return .{ .atom = .{ .literal = pattern[index] }, .next = index + 1 };
}

fn regexAtomMatches(atom: RegexAtom, byte: u8) bool {
    return switch (atom) {
        .literal => |literal| byte == literal,
        .digit => byte >= '0' and byte <= '9',
        .nonzero_digit => byte >= '1' and byte <= '9',
    };
}

fn textContainsNormalized(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8) !bool {
    const normalized_haystack = try normalizeVisibleText(allocator, haystack);
    defer allocator.free(normalized_haystack);
    const normalized_needle = try normalizeVisibleText(allocator, needle);
    defer allocator.free(normalized_needle);
    return std.mem.indexOf(u8, normalized_haystack, normalized_needle) != null;
}

fn nextExpectedStep(contents: []const u8, cursor: *usize) ?ExpectedStep {
    const seq_pos = std.mem.indexOfPos(u8, contents, cursor.*, "[[sequence]]");
    const persist_pos = std.mem.indexOfPos(u8, contents, cursor.*, "[[persistence]]");
    const kind: StepKind, const start: usize = if (seq_pos) |seq| blk: {
        if (persist_pos == null or seq < persist_pos.?) break :blk .{ .sequence, seq };
        break :blk .{ .persistence, persist_pos.? };
    } else if (persist_pos) |persist|
        .{ .persistence, persist }
    else
        return null;

    const header_len: usize = switch (kind) {
        .sequence => "[[sequence]]".len,
        .persistence => "[[persistence]]".len,
    };
    const body_start = start + header_len;
    const next_seq = std.mem.indexOfPos(u8, contents, body_start, "[[sequence]]");
    const next_persist = std.mem.indexOfPos(u8, contents, body_start, "[[persistence]]");
    const end = if (next_seq) |seq| if (next_persist) |persist| @min(seq, persist) else seq else next_persist orelse contents.len;
    cursor.* = end;

    const body = contents[body_start..end];
    return .{
        .kind = kind,
        .description = readStringFieldBorrowed(body, "description") orelse "",
        .body = body,
        .expect = readStringFieldBorrowed(body, "expect") orelse "",
        .match = parseMatchMode(readStringFieldBorrowed(body, "expect_match") orelse "contains"),
    };
}

fn nextAction(contents: []const u8, cursor: *usize) ?[]const u8 {
    var start = std.mem.indexOfPos(u8, contents, cursor.*, "[\"") orelse return null;
    while (isCommentedLine(contents, start)) {
        start = std.mem.indexOfPos(u8, contents, start + 2, "[\"") orelse {
            cursor.* = contents.len;
            return null;
        };
    }
    var depth: usize = 0;
    var index = start;
    var in_string = false;
    while (index < contents.len) : (index += 1) {
        const byte = contents[index];
        if (byte == '"' and (index == 0 or contents[index - 1] != '\\')) {
            in_string = !in_string;
            continue;
        }
        if (in_string) continue;
        if (byte == '[') depth += 1;
        if (byte == ']') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) {
                cursor.* = index + 1;
                return contents[start .. index + 1];
            }
        }
    }
    cursor.* = contents.len;
    return null;
}

fn isCommentedLine(contents: []const u8, pos: usize) bool {
    var line_start = pos;
    while (line_start > 0 and contents[line_start - 1] != '\n') line_start -= 1;
    var cursor = line_start;
    while (cursor < pos and (contents[cursor] == ' ' or contents[cursor] == '\t')) cursor += 1;
    return cursor < pos and contents[cursor] == '#';
}

fn firstActionString(action: []const u8) ?[]const u8 {
    return nthActionString(action, 0);
}

fn nthActionString(action: []const u8, wanted: usize) ?[]const u8 {
    var count: usize = 0;
    var index: usize = 0;
    while (std.mem.indexOfScalarPos(u8, action, index, '"')) |start_quote| {
        var end_quote = start_quote + 1;
        while (end_quote < action.len) : (end_quote += 1) {
            if (action[end_quote] == '"' and action[end_quote - 1] != '\\') break;
        }
        if (end_quote >= action.len) return null;
        if (count == wanted) return action[start_quote + 1 .. end_quote];
        count += 1;
        index = end_quote + 1;
    }
    return null;
}

fn firstActionInteger(action: []const u8, numeric_index: usize) u64 {
    var count: usize = 0;
    var index: usize = 0;
    var in_string = false;
    while (index < action.len) : (index += 1) {
        const byte = action[index];
        if (byte == '"' and (index == 0 or action[index - 1] != '\\')) {
            in_string = !in_string;
            continue;
        }
        if (in_string or byte < '0' or byte > '9') continue;
        const start = index;
        while (index < action.len and action[index] >= '0' and action[index] <= '9') : (index += 1) {}
        if (count == numeric_index) return std.fmt.parseUnsigned(u64, action[start..index], 10) catch 0;
        count += 1;
    }
    return 0;
}

fn firstActionFloat(action: []const u8, string_or_numeric_index: usize) f64 {
    if (nthActionString(action, 1)) |value| {
        return std.fmt.parseFloat(f64, value) catch 0;
    }
    return @floatFromInt(firstActionInteger(action, string_or_numeric_index));
}

fn sectionContents(contents: []const u8, header: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, contents, header) orelse return null;
    const body_start = start + header.len;
    const rest = contents[body_start..];
    const next_section = std.mem.indexOfPos(u8, rest, 0, "\n[") orelse rest.len;
    return rest[0..next_section];
}

fn readStringField(allocator: std.mem.Allocator, contents: []const u8, field: []const u8) !?[]u8 {
    const value = readStringFieldBorrowed(contents, field) orelse return null;
    return try allocator.dupe(u8, value);
}

fn readStringFieldBorrowed(contents: []const u8, field: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (cursor < contents.len) {
        const line_end_rel = std.mem.indexOfScalarPos(u8, contents, cursor, '\n') orelse contents.len;
        const raw_line = contents[cursor..line_end_rel];
        cursor = if (line_end_rel < contents.len) line_end_rel + 1 else contents.len;
        const without_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |comment|
            raw_line[0..comment]
        else
            raw_line;
        const line = std.mem.trim(u8, without_comment, " \t\r");
        if (!std.mem.startsWith(u8, line, field)) continue;
        var rest = trimLeftAscii(line[field.len..]);
        if (rest.len == 0 or rest[0] != '=') continue;
        rest = trimLeftAscii(rest[1..]);
        if (rest.len < 2 or rest[0] != '"') continue;
        var end: usize = 1;
        while (end < rest.len) : (end += 1) {
            if (rest[end] == '"' and rest[end - 1] != '\\') return rest[1..end];
        }
        return null;
    }
    return null;
}

fn trimLeftAscii(value: []const u8) []const u8 {
    var index: usize = 0;
    while (index < value.len and (value[index] == ' ' or value[index] == '\t')) : (index += 1) {}
    return value[index..];
}

fn parseMatchMode(value: []const u8) MatchMode {
    if (std.mem.eql(u8, value, "exact")) return .exact;
    if (std.mem.eql(u8, value, "regex")) return .regex;
    return .contains;
}

fn hasInteractiveSequence(allocator: std.mem.Allocator, example: registry.Example, examples_root: []const u8) !bool {
    const expected_name = try std.mem.concat(allocator, u8, &.{ example.name, ".expected" });
    defer allocator.free(expected_name);
    const path = try std.fs.path.join(allocator, &.{ examples_root, example.name, expected_name });
    defer allocator.free(path);
    const contents = readFileAlloc(allocator, path, 1024 * 1024) catch return false;
    defer allocator.free(contents);
    return std.mem.indexOf(u8, contents, "[[sequence]]") != null;
}

fn writeJsonStringContent(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |byte| {
        switch (byte) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
}

fn normalizeVisibleText(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    for (text) |byte| switch (byte) {
        ' ', '\t', '\r', '\n', '[', ']', '(', ')', '<', '>' => {},
        else => try out.append(allocator, std.ascii.toLower(byte)),
    };
    return try out.toOwnedSlice(allocator);
}

fn normalizeExpectedRegex(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);

    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        const byte = pattern[index];
        if (byte == '\\') {
            if (index + 1 >= pattern.len) return error.UnsupportedExpectedRegex;
            if (pattern[index + 1] == '\\') {
                try out.append(allocator, byte);
                index += 1;
                continue;
            }
            try out.append(allocator, byte);
            index += 1;
            try out.append(allocator, std.ascii.toLower(pattern[index]));
            continue;
        }
        if (byte == '[') {
            const close = std.mem.indexOfScalarPos(u8, pattern, index + 1, ']') orelse return error.UnsupportedExpectedRegex;
            try out.append(allocator, '[');
            for (pattern[index + 1 .. close]) |class_byte| try out.append(allocator, std.ascii.toLower(class_byte));
            try out.append(allocator, ']');
            index = close;
            continue;
        }
        switch (byte) {
            ' ', '\t', '\r', '\n', '(', ')', '<', '>' => {},
            else => try out.append(allocator, std.ascii.toLower(byte)),
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn makeReportDirs() void {
    _ = c_mkdir("zig-out", 0o777);
    _ = c_mkdir("zig-out/reports", 0o777);
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
    const read = c_fread(bytes.ptr, 1, size, file);
    if (read != size) return error.FileReadFailed;
    return bytes;
}

fn writeFile(path: []const u8, contents: []const u8) !void {
    var path_buf: [512:0]u8 = undefined;
    if (path.len >= path_buf.len) return error.PathTooLong;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const file = c_fopen(path_buf[0..path.len :0].ptr, "wb") orelse return error.FileCreateFailed;
    defer _ = c_fclose(file);
    const written = c_fwrite(contents.ptr, 1, contents.len, file);
    if (written != contents.len) return error.FileWriteFailed;
}

extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(file: *anyopaque) c_int;
extern fn fseek(file: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(file: *anyopaque) c_long;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, file: *anyopaque) usize;
extern fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
const Dir = opaque {};
const Dirent = extern struct {
    d_ino: u64,
    d_off: i64,
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
const c_fwrite = fwrite;
const c_mkdir = mkdir;
const c_opendir = opendir;
const c_readdir = readdir;
const c_closedir = closedir;
const dirent_type_unknown: u8 = 0;
const dirent_type_directory: u8 = 4;
const dirent_type_file: u8 = 8;
