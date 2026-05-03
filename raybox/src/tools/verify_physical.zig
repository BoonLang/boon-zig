const std = @import("std");
const raybox = @import("raybox");
const registry = @import("example_registry");
const verify_examples = @import("verify_examples.zig");

const bridge = raybox.boon_adapter.host.bridge;
const host_mod = raybox.boon_adapter.host;
const physical = raybox.render.physical_projection;

const example_name = "todo_mvc_physical";
const visual_spec_path = "fixtures/physical_visual_spec.json";

pub const TargetName = enum { native, web };

const ScenarioKind = enum {
    initial,
    two_todos,
    one_completed_dark,
    glass_dark,
    neobrutalism_light,
    neumorphism_light,
};

const Scenario = struct {
    name: []const u8,
    kind: ScenarioKind,
    expected_theme: physical.Theme,
    expected_mode: physical.Mode,
    require_completed_icon: bool = false,
};

const scenarios = [_]Scenario{
    .{ .name = "professional_light_initial", .kind = .initial, .expected_theme = .professional, .expected_mode = .light },
    .{ .name = "professional_light_two_todos", .kind = .two_todos, .expected_theme = .professional, .expected_mode = .light },
    .{ .name = "professional_dark_one_completed", .kind = .one_completed_dark, .expected_theme = .professional, .expected_mode = .dark, .require_completed_icon = true },
    .{ .name = "glassmorphism_dark", .kind = .glass_dark, .expected_theme = .glassmorphism, .expected_mode = .dark },
    .{ .name = "neobrutalism_light", .kind = .neobrutalism_light, .expected_theme = .neobrutalism, .expected_mode = .light },
    .{ .name = "neumorphism_light", .kind = .neumorphism_light, .expected_theme = .neumorphism, .expected_mode = .light },
};

const scales = [_]physical.Viewport{
    .{ .width = 1000, .height = 900, .scale = 1.0 },
    .{ .width = 1000, .height = 900, .scale = 2.0 },
};

const Status = enum { DONE, BLOCKED };

pub fn run(
    allocator: std.mem.Allocator,
    target: TargetName,
    selected: ?[]const u8,
    build_only: bool,
    examples_root: []const u8,
) !bool {
    makeReportDirs();
    const visual_spec_json = readFileAlloc(allocator, visual_spec_path, 16 * 1024) catch |err| {
        try writeTopReport(allocator, target, .BLOCKED, @errorName(err), &.{}, null);
        return false;
    };
    defer allocator.free(visual_spec_json);

    if (selected) |wanted| {
        if (!std.mem.eql(u8, wanted, example_name)) {
            try writeTopReport(allocator, target, .BLOCKED, "verify-physical supports todo_mvc_physical only", &.{}, visual_spec_json);
            return false;
        }
    }

    const expected = try verify_examples.verifyOneByName(
        allocator,
        if (target == .native) .native else .web,
        example_name,
        build_only,
        examples_root,
    );
    if (expected.status != .DONE) {
        try writeTopReport(allocator, target, .BLOCKED, expected.message, &.{}, visual_spec_json);
        return false;
    }
    if (build_only) {
        try writeTopReport(allocator, target, .DONE, "physical build-only preflight passed", &.{}, visual_spec_json);
        return true;
    }

    const example = findExample() orelse {
        try writeTopReport(allocator, target, .BLOCKED, "todo_mvc_physical missing from registry", &.{}, visual_spec_json);
        return false;
    };

    var results = std.ArrayList(ScenarioResult).empty;
    defer {
        for (results.items) |result| result.deinit(allocator);
        results.deinit(allocator);
    }

    var ok = true;
    for (scenarios) |scenario| {
        const result = try verifyScenario(allocator, target, example, examples_root, scenario, visual_spec_json);
        if (result.status != .DONE) ok = false;
        try results.append(allocator, result);
    }

    try writeTopReport(
        allocator,
        target,
        if (ok) .DONE else .BLOCKED,
        if (ok) "physical verifier passed" else "physical verifier failed",
        results.items,
        visual_spec_json,
    );
    return ok;
}

const ScenarioResult = struct {
    name: []const u8,
    status: Status,
    message: []u8,
    dirs: [][]u8,

    fn deinit(self: ScenarioResult, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        for (self.dirs) |dir| allocator.free(dir);
        allocator.free(self.dirs);
    }
};

fn verifyScenario(
    allocator: std.mem.Allocator,
    target: TargetName,
    example: registry.Example,
    examples_root: []const u8,
    scenario: Scenario,
    visual_spec_json: []const u8,
) !ScenarioResult {
    var host = try startHost(allocator, example, examples_root);
    defer host.deinit();

    driveScenario(&host, scenario.kind) catch |err| {
        return blocked(allocator, scenario.name, @errorName(err));
    };
    const output = try host.tick(0);
    var semantic = switch (output) {
        .document => |document| try physical.SemanticTree.fromDocument(allocator, document),
        .scene => |scene| try physical.SemanticTree.fromScene(allocator, scene),
        .diagnostics => |diagnostics| return blocked(allocator, scenario.name, if (diagnostics.len == 0) "runtime diagnostic" else diagnostics[0].message),
    };
    defer semantic.deinit(allocator);
    var trace = try physical.RenderTrace.project(allocator, semantic, scales[0]);
    defer trace.deinit(allocator);

    if (assertScenario(semantic, trace, scenario)) |message| {
        return blocked(allocator, scenario.name, message);
    }

    const dirs = try allocator.alloc([]u8, scales.len);
    errdefer allocator.free(dirs);
    for (scales, 0..) |viewport, index| {
        var scaled_trace = try physical.RenderTrace.project(allocator, semantic, viewport);
        defer scaled_trace.deinit(allocator);
        dirs[index] = try writeArtifacts(allocator, target, scenario, semantic, scaled_trace, viewport, visual_spec_json);
    }
    return .{
        .name = scenario.name,
        .status = .DONE,
        .message = try allocator.dupe(u8, "physical scenario passed"),
        .dirs = dirs,
    };
}

fn blocked(allocator: std.mem.Allocator, name: []const u8, message: []const u8) !ScenarioResult {
    return .{
        .name = name,
        .status = .BLOCKED,
        .message = try allocator.dupe(u8, message),
        .dirs = try allocator.alloc([]u8, 0),
    };
}

fn startHost(allocator: std.mem.Allocator, example: registry.Example, examples_root: []const u8) !bridge.BoonRuntimeHost {
    const project = try loadProject(allocator, example, examples_root);
    defer freeProject(allocator, project);

    const Context = struct {
        persist_ctx: host_mod.MemoryPersistStore,
        route_ctx: host_mod.MemoryRouteStore,
        persist: bridge.PersistStore,
        route: bridge.RouteStore,
        clock: bridge.VirtualClock,
        time: bridge.TimeSource,
    };
    const ctx = try allocator.create(Context);
    ctx.persist_ctx = host_mod.MemoryPersistStore.init(allocator);
    ctx.route_ctx = .{};
    ctx.persist = ctx.persist_ctx.store();
    ctx.route = ctx.route_ctx.store();
    ctx.clock = .{};
    ctx.time = .{ .virtual = &ctx.clock };

    var host = try bridge.BoonRuntimeHost.init(allocator, &ctx.persist, &ctx.route, &ctx.time);
    try host.loadProject(project);
    try host.clearState(example_name);
    switch (try host.runBuildFile()) {
        .not_present, .ok => {},
        .diagnostics => |diagnostics| return if (diagnostics.len == 0) error.BuildDiagnostic else error.BuildDiagnostic,
    }
    switch (try host.compileEntry()) {
        .ok => {},
        .diagnostics => return error.CompileDiagnostic,
    }
    switch (try host.start()) {
        .document => {},
        .scene => {},
        .diagnostics => return error.RuntimeDiagnostic,
    }
    return host;
}

fn driveScenario(host: *bridge.BoonRuntimeHost, kind: ScenarioKind) !void {
    switch (kind) {
        .initial => {},
        .two_todos => {
            try addTodo(host, "Buy groceries");
            try addTodo(host, "Clean room");
        },
        .one_completed_dark => {
            try addTodo(host, "Buy groceries");
            const first_todo_checkbox = try host.checkboxHandle(1);
            _ = try host.dispatch(.{ .checkbox_ref_change = .{ .handle = first_todo_checkbox, .checked = true } });
            _ = try host.dispatch(.{ .click_text = "Dark mode" });
        },
        .glass_dark => {
            _ = try host.dispatch(.{ .click_text = "Dark mode" });
            _ = try host.dispatch(.{ .click_text = "Glass" });
        },
        .neobrutalism_light => {
            _ = try host.dispatch(.{ .click_text = "Brutalist" });
        },
        .neumorphism_light => {
            _ = try host.dispatch(.{ .click_text = "Neumorphic" });
        },
    }
}

fn addTodo(host: *bridge.BoonRuntimeHost, text: []const u8) !void {
    _ = try host.dispatch(.{ .change_text = .{ .link = 0, .text = text } });
    _ = try host.dispatch(.{ .key_down = .{ .link = 0, .key = .enter, .text = text } });
}

fn assertScenario(semantic: physical.SemanticTree, trace: physical.RenderTrace, scenario: Scenario) ?[]const u8 {
    if (!physical.containsVisible(semantic.rendered_text, "todos") or !hasCommand(trace, .bevel, "title_text", "todos")) return "title todos is not visible and large";
    if (semantic.inputs.len == 0 or !semantic.inputs[0].focused) return "new todo input is not focused";
    if (!hasCommand(trace, .inner_shadow, "text_input", "")) return "text input has no inner shadow command";
    if (!hasCommand(trace, .shadow, "main_card", "")) return "main card has no drop shadow command";
    if (!hasCommand(trace, .bevel, "button", "")) return "buttons have no raised bevel command";
    if (semantic.checkboxes.len != 0 and !hasCommand(trace, .inner_shadow, "checkbox", "")) return "checkboxes have no recessed command";
    if (!hasButton(semantic, "Professional") or !hasButton(semantic, "Glass") or !hasButton(semantic, "Brutalist") or !hasButton(semantic, "Neumorphic")) return "theme buttons are not visible";
    if (trace.theme != scenario.expected_theme) return "selected theme visual did not match scenario";
    if (trace.mode != scenario.expected_mode) return "mode toggle state did not match scenario";
    if (!physical.containsVisible(semantic.rendered_text, scenario.expected_mode.toggleLabel())) return "mode toggle label did not match scenario";
    if (scenario.expected_theme == .glassmorphism and !hasAlphaBelowOne(trace)) return "glass theme has no translucent surface";
    if (scenario.expected_theme == .neobrutalism and !mainCardSharp(trace)) return "neobrutalism main card is not sharp";
    if (scenario.expected_theme == .neumorphism and !neumorphicShadow(trace)) return "neumorphism shadow blur is too small";
    if (!hasCommand(trace, .glow, "text_input", "")) return "focused input has no glow command";
    if (scenario.require_completed_icon and !hasCommand(trace, .svg_path, "checkbox", "checkbox_completed")) return "completed checkbox icon is missing";
    return null;
}

fn hasCommand(trace: physical.RenderTrace, kind: raybox.render.renderer.CustomKind, role: []const u8, label_or_icon: []const u8) bool {
    for (trace.commands) |command| {
        if (command.base.kind != kind) continue;
        if (!std.mem.eql(u8, command.role, role)) continue;
        if (label_or_icon.len == 0) return true;
        if (physical.containsVisible(command.label, label_or_icon)) return true;
        if (command.base.icon_name) |icon| {
            if (physical.containsVisible(icon, label_or_icon)) return true;
        }
    }
    return false;
}

fn hasButton(semantic: physical.SemanticTree, label: []const u8) bool {
    for (semantic.buttons) |button| {
        if (physical.containsVisible(button.label, label)) return true;
    }
    return false;
}

fn hasAlphaBelowOne(trace: physical.RenderTrace) bool {
    for (trace.commands) |command| {
        if (command.base.alpha > 0 and command.base.alpha < 1) return true;
        if (command.base.color.a > 0 and command.base.color.a < 1) return true;
    }
    return false;
}

fn mainCardSharp(trace: physical.RenderTrace) bool {
    for (trace.commands) |command| {
        if (std.mem.eql(u8, command.role, "main_card") and command.base.radius.top_left <= 0.5) return true;
    }
    return false;
}

fn neumorphicShadow(trace: physical.RenderTrace) bool {
    for (trace.commands) |command| {
        if (std.mem.eql(u8, command.role, "main_card") and command.base.kind == .shadow and command.base.blur_radius > 15) return true;
    }
    return false;
}

fn writeArtifacts(
    allocator: std.mem.Allocator,
    target: TargetName,
    scenario: Scenario,
    semantic: physical.SemanticTree,
    trace: physical.RenderTrace,
    viewport: physical.Viewport,
    visual_spec_json: []const u8,
) ![]u8 {
    const scale_name = if (viewport.scale == 1.0) "scale1" else "scale2";
    const scenario_name = try std.fmt.allocPrint(allocator, "{s}_{s}", .{ scenario.name, scale_name });
    defer allocator.free(scenario_name);
    const dir = try std.fs.path.join(allocator, &.{ "zig-out", "verification", "physical", @tagName(target), example_name, scenario_name });
    errdefer allocator.free(dir);
    try makePath(dir);
    try writeSemanticJson(allocator, dir, semantic, trace, viewport);
    try writeTraceJson(allocator, dir, trace);
    try writeReportJson(allocator, dir, scenario, trace, visual_spec_json);
    try writeScreenshot(allocator, dir, trace, viewport);
    try writeDiffPlaceholder(allocator, dir);
    return dir;
}

fn writeSemanticJson(allocator: std.mem.Allocator, dir: []const u8, semantic: physical.SemanticTree, trace: physical.RenderTrace, viewport: physical.Viewport) !void {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.print("{{\n  \"theme\": \"{s}\",\n  \"mode\": \"{s}\",\n  \"viewport\": {{ \"width\": {d}, \"height\": {d}, \"scale\": {d} }},\n  \"rendered_text\": \"", .{ trace.theme.name(), @tagName(trace.mode), viewport.width, viewport.height, viewport.scale });
    try writeJsonStringContent(w, semantic.rendered_text);
    try w.writeAll("\",\n  \"inputs\": [");
    for (semantic.inputs, 0..) |input, i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("{ \"text\": \"");
        try writeJsonStringContent(w, input.text);
        try w.writeAll("\", \"placeholder\": \"");
        try writeJsonStringContent(w, input.placeholder);
        try w.print("\", \"focused\": {s}, \"disabled\": {s} }}", .{ boolText(input.focused), boolText(input.disabled) });
    }
    try w.writeAll("],\n  \"buttons\": [");
    for (semantic.buttons, 0..) |button, i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("{ \"label\": \"");
        try writeJsonStringContent(w, button.label);
        try w.print("\", \"outlined\": {s}, \"disabled\": {s} }}", .{ boolText(button.outlined), boolText(button.disabled) });
    }
    try w.writeAll("],\n  \"checkboxes\": [");
    for (semantic.checkboxes, 0..) |checkbox, i| {
        if (i != 0) try w.writeAll(", ");
        try w.writeAll("{ \"label\": \"");
        try writeJsonStringContent(w, checkbox.label);
        try w.print("\", \"checked\": {s} }}", .{boolText(checkbox.checked)});
    }
    try w.writeAll("]\n}\n");
    try writeJoinedFile(allocator, dir, "semantic_tree.json", out.written());
}

fn writeTraceJson(allocator: std.mem.Allocator, dir: []const u8, trace: physical.RenderTrace) !void {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.writeAll("{\n  \"commands\": [\n");
    for (trace.commands, 0..) |command, i| {
        if (i != 0) try w.writeAll(",\n");
        try w.print("    {{ \"kind\": \"{s}\", \"role\": \"", .{@tagName(command.base.kind)});
        try writeJsonStringContent(w, command.role);
        try w.writeAll("\", \"label\": \"");
        try writeJsonStringContent(w, command.label);
        try w.writeAll("\", \"icon_name\": \"");
        if (command.base.icon_name) |icon| try writeJsonStringContent(w, icon);
        try w.print("\", \"radius\": {d}, \"alpha\": {d}, \"blur_radius\": {d}, \"z\": {d}, \"outline_width\": {d}, \"text_size\": {d} }}", .{ command.base.radius.top_left, command.base.color.a, command.base.blur_radius, command.base.z, command.base.outline_width, command.text_size });
    }
    try w.writeAll("\n  ]\n}\n");
    try writeJoinedFile(allocator, dir, "render_trace.json", out.written());
}

fn writeReportJson(allocator: std.mem.Allocator, dir: []const u8, scenario: Scenario, trace: physical.RenderTrace, visual_spec_json: []const u8) !void {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.print("{{\n  \"status\": \"DONE\",\n  \"scenario\": \"{s}\",\n  \"theme\": \"{s}\",\n  \"mode\": \"{s}\",\n  \"render_command_count\": {d},\n  \"visual_tolerance\": ", .{ scenario.name, trace.theme.name(), @tagName(trace.mode), trace.commands.len });
    try writeIndentedJson(&out.writer, visual_spec_json, 2);
    try out.writer.writeAll("\n}\n");
    try writeJoinedFile(allocator, dir, "report.json", out.written());
}

fn writeScreenshot(allocator: std.mem.Allocator, dir: []const u8, trace: physical.RenderTrace, viewport: physical.Viewport) !void {
    var image = try physical.PixelImage.init(allocator, viewport.width, viewport.height, .{ .r = 0, .g = 0, .b = 0, .a = 1 });
    defer image.deinit();
    image.renderTrace(trace);
    const png = try physical.pngAlloc(allocator, image);
    defer allocator.free(png);
    try writeJoinedFile(allocator, dir, "screenshot.png", png);
}

fn writeDiffPlaceholder(allocator: std.mem.Allocator, dir: []const u8) !void {
    var image = try physical.PixelImage.init(allocator, 16, 16, .{ .r = 0, .g = 0, .b = 0, .a = 1 });
    defer image.deinit();
    const png = try physical.pngAlloc(allocator, image);
    defer allocator.free(png);
    try writeJoinedFile(allocator, dir, "native_vs_web.diff.png", png);
}

fn writeTopReport(allocator: std.mem.Allocator, target: TargetName, status: Status, message: []const u8, results: []const ScenarioResult, visual_spec_json: ?[]const u8) !void {
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    const w = &out.writer;
    try w.print("{{\n  \"target\": \"{s}\",\n  \"example\": \"{s}\",\n  \"status\": \"{s}\",\n  \"message\": \"", .{ @tagName(target), example_name, @tagName(status) });
    try writeJsonStringContent(w, message);
    try w.writeAll("\",\n  \"visual_tolerance\": ");
    if (visual_spec_json) |spec| {
        try writeIndentedJson(w, spec, 2);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\n  \"scenarios\": [\n");
    for (results, 0..) |result, i| {
        if (i != 0) try w.writeAll(",\n");
        try w.writeAll("    { \"name\": \"");
        try writeJsonStringContent(w, result.name);
        try w.writeAll("\", \"status\": \"");
        try writeJsonStringContent(w, @tagName(result.status));
        try w.writeAll("\", \"message\": \"");
        try writeJsonStringContent(w, result.message);
        try w.writeAll("\", \"artifact_dirs\": [");
        for (result.dirs, 0..) |dir, dir_index| {
            if (dir_index != 0) try w.writeAll(", ");
            try w.writeByte('"');
            try writeJsonStringContent(w, dir);
            try w.writeByte('"');
        }
        try w.writeAll("] }");
    }
    try w.writeAll("\n  ]\n}\n");
    const path = if (target == .native) "zig-out/reports/physical_visual_native.json" else "zig-out/reports/physical_visual_web.json";
    try writeFile(path, out.written());
}

fn findExample() ?registry.Example {
    for (registry.examples) |example| {
        if (std.mem.eql(u8, example.name, example_name)) return example;
    }
    return null;
}

const project_files = [_][]const u8{
    "RUN.bn",
    "BUILD.bn",
    "Generated/Assets.bn",
    "Theme/Theme.bn",
    "Theme/Professional.bn",
    "Theme/Glassmorphism.bn",
    "Theme/Neobrutalism.bn",
    "Theme/Neumorphism.bn",
    "assets/icons/checkbox_active.svg",
    "assets/icons/checkbox_completed.svg",
};

fn loadProject(allocator: std.mem.Allocator, example: registry.Example, examples_root: []const u8) !bridge.Project {
    const files = try allocator.alloc(bridge.ProjectFile, project_files.len);
    errdefer allocator.free(files);
    var loaded: usize = 0;
    errdefer {
        for (files[0..loaded]) |file| {
            allocator.free(file.path);
            allocator.free(file.contents);
        }
    }
    for (project_files, 0..) |relative, index| {
        const path = try std.fs.path.join(allocator, &.{ examples_root, example.name, relative });
        defer allocator.free(path);
        files[index] = .{
            .path = try allocator.dupe(u8, relative),
            .contents = try readFileAlloc(allocator, path, 4 * 1024 * 1024),
            .generated = std.mem.startsWith(u8, relative, "Generated/"),
        };
        loaded += 1;
    }
    return .{ .name = example.name, .entry_file = example.entry_file, .files = files };
}

fn freeProject(allocator: std.mem.Allocator, project: bridge.Project) void {
    for (project.files) |file| {
        allocator.free(file.path);
        allocator.free(file.contents);
    }
    allocator.free(project.files);
}

fn boolText(value: bool) []const u8 {
    return if (value) "true" else "false";
}

fn writeJsonStringContent(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |byte| switch (byte) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => try writer.writeByte(byte),
    };
}

fn writeIndentedJson(writer: *std.Io.Writer, value: []const u8, indent_spaces: usize) !void {
    var at_line_start = false;
    for (std.mem.trim(u8, value, " \t\r\n")) |byte| {
        try writer.writeByte(byte);
        if (byte == '\n') {
            at_line_start = true;
            for (0..indent_spaces) |_| try writer.writeByte(' ');
        } else if (at_line_start and byte != ' ' and byte != '\t') {
            at_line_start = false;
        }
    }
}

fn writeJoinedFile(allocator: std.mem.Allocator, dir: []const u8, name: []const u8, bytes: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ dir, name });
    defer allocator.free(path);
    try writeFile(path, bytes);
}

fn makeReportDirs() void {
    _ = c_mkdir("zig-out", 0o777);
    _ = c_mkdir("zig-out/reports", 0o777);
    _ = c_mkdir("zig-out/verification", 0o777);
    _ = c_mkdir("zig-out/verification/physical", 0o777);
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
