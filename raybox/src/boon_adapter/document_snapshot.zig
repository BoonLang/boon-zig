const std = @import("std");
const host = @import("boon_runtime_host.zig");

pub fn rootText(snapshot: host.bridge.DocumentSnapshot) ?[]const u8 {
    if (snapshot.root >= snapshot.values.len) return null;
    return valueText(snapshot.values[snapshot.root]);
}

pub fn valueText(value: host.bridge.RuntimeValue) ?[]const u8 {
    return switch (value) {
        .text => |text| text,
        .number => |number| blk: {
            _ = number;
            break :blk null;
        },
        else => null,
    };
}

pub fn appendPlainText(writer: *std.Io.Writer, snapshot: host.bridge.DocumentSnapshot) !void {
    if (snapshot.root >= snapshot.values.len) return;
    try appendValueText(writer, snapshot.values[snapshot.root], snapshot.values);
}

fn appendValueText(writer: *std.Io.Writer, value: host.bridge.RuntimeValue, values: []const host.bridge.RuntimeValue) anyerror!void {
    switch (value) {
        .none => {},
        .number => |number| try writer.print("{d}", .{number}),
        .bool => |b| try writer.writeAll(if (b) "true" else "false"),
        .text => |text| try writer.writeAll(text),
        .symbol => |symbol| try writer.writeAll(symbol),
        .list => |items| for (items) |id| {
            if (id < values.len) try appendValueText(writer, values[id], values);
        },
        .record => |fields| for (fields) |field| {
            if (field.value < values.len) try appendValueText(writer, values[field.value], values);
        },
        .element => |element| try appendElementText(writer, element, values),
    }
}

fn appendElementText(writer: *std.Io.Writer, element: host.bridge.ElementNode, values: []const host.bridge.RuntimeValue) anyerror!void {
    if (std.mem.eql(u8, element.kind, "document") or
        std.mem.eql(u8, element.kind, "terminal"))
    {
        try appendFieldText(writer, element, "root", values);
        return;
    }
    if (std.mem.eql(u8, element.kind, "stripe")) {
        try appendFieldText(writer, element, "items", values);
        return;
    }
    if (std.mem.eql(u8, element.kind, "label")) {
        try appendFieldText(writer, element, "label", values);
        return;
    }
    if (std.mem.eql(u8, element.kind, "container")) {
        try appendFieldText(writer, element, "child", values);
        return;
    }
    if (std.mem.eql(u8, element.kind, "checkbox")) {
        return;
    }
    if (std.mem.eql(u8, element.kind, "button")) {
        try writer.writeByte('[');
        try appendFieldText(writer, element, "label", values);
        try writer.writeByte(']');
        return;
    }
    if (std.mem.eql(u8, element.kind, "text_input")) {
        try writer.writeByte('<');
        try appendFieldText(writer, element, "text", values);
        try writer.writeByte('>');
        return;
    }
    if (std.mem.eql(u8, element.kind, "select")) {
        try writer.writeByte('<');
        try appendFieldText(writer, element, "selected", values);
        try writer.writeByte('>');
        return;
    }
    if (std.mem.eql(u8, element.kind, "slider")) {
        try writer.writeAll("<slider>");
        return;
    }
    for (element.args) |field| {
        if (field.value < values.len) try appendValueText(writer, values[field.value], values);
    }
}

fn appendFieldText(writer: *std.Io.Writer, element: host.bridge.ElementNode, name: []const u8, values: []const host.bridge.RuntimeValue) anyerror!void {
    const value_id = findField(element, name) orelse return;
    if (value_id < values.len) try appendValueText(writer, values[value_id], values);
}

fn findField(element: host.bridge.ElementNode, name: []const u8) ?host.bridge.ValueId {
    for (element.args) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.value;
    }
    return null;
}

fn runtimeBool(value: host.bridge.RuntimeValue) bool {
    return switch (value) {
        .bool => |b| b,
        .symbol => |symbol| std.mem.eql(u8, symbol, "True") or std.mem.eql(u8, symbol, "true"),
        .text => |text| std.mem.eql(u8, text, "True") or std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "checked"),
        else => false,
    };
}
