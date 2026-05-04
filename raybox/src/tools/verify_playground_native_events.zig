const std = @import("std");
const app_mod = @import("playground_app");
const playground_layout = @import("playground_layout");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    try verifyTodoMvcNativeEvents(allocator);
    try verifyTodoMvcNativeSdlTextInputPath(allocator);
    try verifyIntervalNativeTimers(allocator);
    try verifyShoppingListNativeEvents(allocator);
    try verifyCounterNativeEvents(allocator);
    try verifyTemperatureConverterNativeEvents(allocator);
    try verifyCircleDrawerNativeEvents(allocator);
    try verifyCrudNativeEvents(allocator);
    try verifyTodoMvcNativeStress(allocator);
    try verifyExampleTabs(allocator);
    try verifyPongNativeButtons(allocator);
    try verifyPlaygroundLayoutContract();
}

fn verifyCounterNativeEvents(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("counter"), "counter example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectEqualText("0", std.mem.trim(u8, app.renderedTextForTest(), " \t\r\n"), "counter starts at zero");
    try app.clickButtonForTest(0);
    try expectEqualText("1", std.mem.trim(u8, app.renderedTextForTest(), " \t\r\n"), "counter button click increments through stable control ref");
}

fn verifyCircleDrawerNativeEvents(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("circle_drawer"), "circle_drawer example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectContains(app.renderedTextForTest(), "Circles:0", "circle_drawer starts empty");
    try expect(app.svgClickHasHandleForTest(0), "circle_drawer canvas must carry stable click handle");
    try app.clickCanvasForTest();
    try expect(app.lastSvgClickDispatchedForTest(), "circle_drawer canvas click dispatches svg event");
    if (app.lastErrorForTest()) |err| {
        std.log.err("circle_drawer dispatch error: {s}", .{err});
        return error.NativePlaygroundEventVerificationFailed;
    }
    try expectContains(app.renderedTextForTest(), "Circles:1", "circle_drawer canvas click updates Boon state");
}

fn verifyIntervalNativeTimers(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("interval"), "interval example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectEqualText("", std.mem.trim(u8, app.renderedTextForTest(), " \t\r\n"), "interval starts empty");
    try app.advanceTimeForTest(1100);
    try expectEqualText("1", std.mem.trim(u8, app.renderedTextForTest(), " \t\r\n"), "interval shows first tick after one second");
    try app.advanceTimeForTest(1000);
    try expectEqualText("2", std.mem.trim(u8, app.renderedTextForTest(), " \t\r\n"), "interval shows second tick after another second");

    var hold_app = app_mod.PlaygroundApp{};
    try expect(hold_app.setInitialExample("interval_hold"), "interval_hold example must exist");
    try hold_app.initForNativeEventTest(allocator);
    defer hold_app.deinitForNativeEventTest();
    try expectEqualText("", std.mem.trim(u8, hold_app.renderedTextForTest(), " \t\r\n"), "interval_hold starts empty");
    try hold_app.advanceTimeForTest(1100);
    try expectEqualText("1", std.mem.trim(u8, hold_app.renderedTextForTest(), " \t\r\n"), "interval_hold shows first tick after one second");

    var frame_app = app_mod.PlaygroundApp{};
    try expect(frame_app.setInitialExample("interval"), "interval example must exist");
    try frame_app.initForNativeEventTest(allocator);
    defer frame_app.deinitForNativeEventTest();
    for (0..35) |_| try frame_app.advanceFrameTimeForTest(33);
    try expectEqualText("1", std.mem.trim(u8, frame_app.renderedTextForTest(), " \t\r\n"), "interval advances through normal app frame timer path");
}

fn verifyTodoMvcNativeEvents(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("todo_mvc"), "todo_mvc example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectContains(app.renderedTextForTest(), "2 items left", "todo_mvc initial count");
    try expect(app.buttonOutlinedForTest("All") orelse false, "All filter starts outlined");

    try app.clickInputViaSdlEventForTest(0);
    try app.typeAsciiForTest("151");
    try expectEqualText("151", app.inputTextForTest(0) orelse "", "todo_mvc typed draft");
    app.pressEnterForTest();
    try expectContains(app.renderedTextForTest(), "151", "todo_mvc appended typed todo");
    try expectContains(app.renderedTextForTest(), "3 items left", "todo_mvc count after add");
    try expectEqualText("", app.inputTextForTest(0) orelse "", "todo_mvc input clears after Enter");

    try app.clickInputViaSdlEventForTest(0);
    try expectEqualInt(1, std.mem.count(u8, app.renderedTextForTest(), "151"), "todo_mvc refocusing input must not replay previous Enter");
    try expectContains(app.renderedTextForTest(), "3 items left", "todo_mvc count remains stable after refocus");
    try expect(app.textInputCaretVisibleForTest(), "focused todo_mvc input shows caret immediately after focus");
    try app.advanceUiTimeForTest(600);
    try expect(!app.textInputCaretVisibleForTest(), "focused todo_mvc input caret blinks off");
    try app.typeAsciiForTest("x");
    try expect(app.textInputCaretVisibleForTest(), "typing resets focused todo_mvc input caret blink phase");

    try app.clickCheckboxForTest(1);
    try expect(app.checkboxCheckedForTest(1) orelse false, "todo_mvc first item checkbox toggles from projected click");
    try expectContains(app.renderedTextForTest(), "2 items left", "todo_mvc count after checkbox click");

    try app.clickButtonByLabelForTest("Completed");
    try expect(app.buttonOutlinedForTest("Completed") orelse false, "Completed filter button click updates outline");
    try expectContains(app.renderedTextForTest(), "Buy groceries", "Completed filter shows completed item");
}

fn verifyTodoMvcNativeSdlTextInputPath(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("todo_mvc"), "todo_mvc example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try app.clickInputViaSdlEventForTest(0);
    if (app.lastErrorForTest()) |err| {
        std.log.err("todo_mvc SDL input click error: {s}", .{err});
        return error.NativePlaygroundEventVerificationFailed;
    }
    try app.typeAsciiViaSdlEventsForTest("151");
    if (app.lastErrorForTest()) |err| {
        std.log.err("todo_mvc SDL text event error: {s}", .{err});
        return error.NativePlaygroundEventVerificationFailed;
    }
    try expectEqualText("151", app.nativeInputDraftForTest(), "todo_mvc SDL text event updates native draft");
    try expectEqualText("151", app.inputTextForTest(0) orelse "", "todo_mvc SDL text event updates draft");
    app.pressEnterViaSdlEventForTest();
    if (app.lastErrorForTest()) |err| {
        std.log.err("todo_mvc SDL enter event error: {s}", .{err});
        return error.NativePlaygroundEventVerificationFailed;
    }
    try expectContains(app.renderedTextForTest(), "151", "todo_mvc SDL text path appends typed todo");
    try expectContains(app.renderedTextForTest(), "3 items left", "todo_mvc SDL text path updates count");
    try expectEqualText("", app.inputTextForTest(0) orelse "", "todo_mvc SDL text path clears input after Enter");
}

fn verifyTodoMvcNativeStress(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("todo_mvc"), "todo_mvc example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    for (0..20) |index| {
        try app.clickInputForTest(0);
        var title_buffer: [16]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buffer, "x{d}", .{index});
        try app.typeAsciiForTest(title);
        app.pressEnterForTest();
    }

    try expectContains(app.renderedTextForTest(), "22 items left", "todo_mvc stress count after adding twenty todos");
    try expectEqualInt(20, std.mem.count(u8, app.renderedTextForTest(), "x"), "todo_mvc stress should add each x todo exactly once");
    try expectEqualInt(23, app.checkboxCountForTest(), "todo_mvc stress should expose toggle-all plus twenty-two todo checkboxes");

    try app.clickInputForTest(0);
    const typing_start_ns = monotonicNanoseconds();
    try app.typeAsciiForTest("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    const typing_elapsed_ms = nanosecondsToMilliseconds(monotonicNanoseconds() - typing_start_ns);
    if (typing_elapsed_ms >= 1000.0) std.log.err("todo_mvc held typing elapsed {d:.3}ms", .{typing_elapsed_ms});
    try expect(typing_elapsed_ms < 1000.0, "todo_mvc held key typing after twenty todos must stay below the native Debug regression budget");
    try expectEqualText("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", app.inputTextForTest(0) orelse "", "todo_mvc held key typing preserves the focused input text");
    if (app.lastErrorForTest()) |err| {
        std.log.err("todo_mvc held typing error: {s}", .{err});
        return error.NativePlaygroundEventVerificationFailed;
    }

    app.pressEnterForTest();
    try app.clickInputViaSdlEventForTest(0);
    var sdl_held_text: [64]u8 = undefined;
    @memset(&sdl_held_text, 'g');
    const sdl_typing_start_ns = monotonicNanoseconds();
    for (sdl_held_text) |_| try app.typeAsciiViaSdlEventsForTest("g");
    const sdl_typing_elapsed_ms = nanosecondsToMilliseconds(monotonicNanoseconds() - sdl_typing_start_ns);
    if (sdl_typing_elapsed_ms >= 1000.0) std.log.err("todo_mvc SDL held typing elapsed {d:.3}ms", .{sdl_typing_elapsed_ms});
    try expect(sdl_typing_elapsed_ms < 1000.0, "todo_mvc SDL held key typing after twenty todos must stay below the native Debug regression budget");
    try expectEqualText(&sdl_held_text, app.nativeInputDraftForTest(), "todo_mvc SDL held key typing preserves exact native draft text");
    try expectEqualText(&sdl_held_text, app.inputTextForTest(0) orelse "", "todo_mvc SDL held key typing preserves exact projected draft text");
    if (app.lastErrorForTest()) |err| {
        std.log.err("todo_mvc SDL held typing error: {s}", .{err});
        return error.NativePlaygroundEventVerificationFailed;
    }
    app.pressEnterForTest();

    const start_ns = monotonicNanoseconds();
    try app.clickCheckboxForTest(0);
    const elapsed_ms = nanosecondsToMilliseconds(monotonicNanoseconds() - start_ns);
    try expect(elapsed_ms < 5000.0, "todo_mvc toggle-all after twenty todos must stay below the native Debug regression budget");
    try expectContains(app.renderedTextForTest(), "0 items left", "todo_mvc stress toggle-all completes all todos");
}

fn verifyShoppingListNativeEvents(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("shopping_list"), "shopping_list example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectContains(app.renderedTextForTest(), "0 items", "shopping_list initial count");
    try app.clickInputForTest(0);
    try app.typeAsciiForTest("Milk");
    app.pressEnterForTest();
    try expectContains(app.renderedTextForTest(), "Milk", "shopping_list appended typed item");
    try expectContains(app.renderedTextForTest(), "1 items", "shopping_list count after Enter");
}

fn verifyTemperatureConverterNativeEvents(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("temperature_converter"), "temperature_converter example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectContains(app.renderedTextForTest(), "Temperature Converter", "temperature_converter title");
    try app.clickInputForTest(0);
    try app.typeAsciiForTest("100");
    try expectEqualText("100", app.inputTextForTest(0) orelse "", "temperature_converter celsius draft");
    try expectEqualTrimmed("212", app.inputTextForTest(1) orelse "", "temperature_converter fahrenheit update");

    try app.clickInputForTest(1);
    app.pressBackspaceForTest();
    app.pressBackspaceForTest();
    app.pressBackspaceForTest();
    app.pressBackspaceForTest();
    app.pressBackspaceForTest();
    try app.typeAsciiForTest("32");
    try expectEqualTrimmed("32", app.inputTextForTest(1) orelse "", "temperature_converter fahrenheit draft");
    try expectEqualTrimmed("0", app.inputTextForTest(0) orelse "", "temperature_converter celsius update");

    try app.clickInputForTest(0);
    try app.typeAsciiForTest("x");
    try expectEqualTrimmed("nan", app.inputTextForTest(1) orelse "", "temperature_converter invalid celsius shows nan fahrenheit");
}

fn verifyCrudNativeEvents(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("crud"), "crud example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectContains(app.renderedTextForTest(), "CRUD", "crud title");
    try app.clickInputForTest(0);
    try app.typeAsciiForTest("M");
    try expectContains(app.renderedTextForTest(), "Mustermann", "crud filter keeps Mustermann");
    try expectNotContains(app.renderedTextForTest(), "Hans", "crud filter hides Hans");

    try app.clickInputForTest(0);
    app.pressBackspaceForTest();
    try app.clickInputForTest(1);
    try app.typeAsciiForTest("John");
    try app.clickInputForTest(2);
    try app.typeAsciiForTest("Doe");
    try app.clickButtonByLabelForTest("Create");
    try expectContains(app.renderedTextForTest(), "Doe", "crud create adds Doe");
}

fn verifyExampleTabs(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("counter"), "counter example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try app.clickExampleTabForTest("crud");
    try expectEqualText("crud", app.currentExampleNameForTest(), "example tab switches to crud");
    try expectContains(app.renderedTextForTest(), "CRUD", "crud renders after tab switch");

    try app.clickExampleTabForTest("temperature_converter");
    try expectEqualText("temperature_converter", app.currentExampleNameForTest(), "example tab switches to temperature_converter");
    try expectContains(app.renderedTextForTest(), "Temperature Converter", "temperature_converter renders after tab switch");
}

fn verifyPongNativeButtons(allocator: std.mem.Allocator) !void {
    var app = app_mod.PlaygroundApp{};
    try expect(app.setInitialExample("pong"), "pong example must exist");
    try app.initForNativeEventTest(allocator);
    defer app.deinitForNativeEventTest();

    try expectContains(app.renderedTextForTest(), "Press Enter", "pong initial serve prompt");
    try app.clickButtonForTest(2);
    try expectContains(app.renderedTextForTest(), "STATUS", "pong still renders after serve button click");
}

fn verifyPlaygroundLayoutContract() !void {
    try expect(playground_layout.window_width >= 1600, "playground window must leave room for readable sidebar and preview");
    try expect(playground_layout.window_height >= 1000, "playground window must leave room for source panel");
    try expect(playground_layout.sidebar_width >= 540, "playground examples panel must not collapse back to debug-panel width");
    try expect(playground_layout.examples_column_width >= 460, "playground examples column must keep three readable tab columns");
    try expect(playground_layout.source_panel_width >= 540, "playground source panel must stay wide enough to read code");
    try expect(playground_layout.tab_columns == 3, "playground example tabs use the tested three-column hit grid");
    try expect(playground_layout.tab_width >= 150, "playground example tabs must remain readable");
    try expect(playground_layout.tab_height >= 40, "playground example tabs must remain clickable");
    try expect(playground_layout.tab_font_size >= 18, "playground example tab text must remain readable");
    try expect(playground_layout.source_font_size >= 24, "playground source text must remain readable");
    try expect(playground_layout.source_panel_height >= 760, "playground source panel must show enough context");
    try expect(playground_layout.source_visible_lines >= 20, "playground source panel must render enough lines for visual debugging");
    try expect(playground_layout.source_preview_columns <= 44, "playground source preview lines must fit the source panel");
    try expect(playground_layout.preview_left >= playground_layout.outer_padding + playground_layout.sidebar_width + playground_layout.content_gap + playground_layout.source_panel_width + playground_layout.content_gap, "preview must start after info panels");
    const preview_width = @as(f32, @floatFromInt(playground_layout.window_width)) - playground_layout.preview_left - playground_layout.outer_padding;
    try expect(preview_width >= 700, "playground preview must keep enough width after info panels");
}

fn expect(condition: bool, message: []const u8) !void {
    if (!condition) {
        std.log.err("{s}", .{message});
        return error.NativePlaygroundEventVerificationFailed;
    }
}

fn expectContains(haystack: []const u8, needle: []const u8, message: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.log.err("{s}: missing '{s}' in '{s}'", .{ message, needle, haystack });
        return error.NativePlaygroundEventVerificationFailed;
    }
}

fn expectNotContains(haystack: []const u8, needle: []const u8, message: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.log.err("{s}: unexpectedly found '{s}' in '{s}'", .{ message, needle, haystack });
        return error.NativePlaygroundEventVerificationFailed;
    }
}

fn expectEqualText(expected: []const u8, actual: []const u8, message: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        std.log.err("{s}: expected '{s}', got '{s}'", .{ message, expected, actual });
        return error.NativePlaygroundEventVerificationFailed;
    }
}

fn expectEqualInt(expected: usize, actual: usize, message: []const u8) !void {
    if (expected != actual) {
        std.log.err("{s}: expected {d}, got {d}", .{ message, expected, actual });
        return error.NativePlaygroundEventVerificationFailed;
    }
}

fn expectEqualTrimmed(expected: []const u8, actual: []const u8, message: []const u8) !void {
    try expectEqualText(expected, std.mem.trim(u8, actual, " \t\r\n"), message);
}

fn monotonicNanoseconds() u64 {
    const linux = std.os.linux;
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

fn nanosecondsToMilliseconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}
