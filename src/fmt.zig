const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const parser = @import("parser.zig");

pub const Outcome = union(enum) {
    ok: []u8,
    err: diag.Diagnostic,
};

const Comment = struct {
    start: usize,
    end: usize,
    is_standalone: bool,
};

const indent_unit = "    ";
const max_line_width: usize = 90;
const max_inline_pipe_parts: usize = 3;
const max_last_arg_prefix: usize = 40;

pub fn formatAlloc(allocator: std.mem.Allocator, source: []const u8) !Outcome {
    const parsed = try parser.parseAlloc(allocator, source);
    switch (parsed) {
        .ok => |document| {
            var parsed_document = document;
            defer parsed_document.deinit();

            const comments = try collectCommentsAlloc(allocator, source);
            var formatter = Formatter.init(allocator, source, comments);
            try formatter.formatProgram(parsed_document.root.items);
            return .{ .ok = try formatter.finish() };
        },
        .err => |failure| return .{ .err = failure },
    }
}

const ValueLayout = enum {
    inline_value,
    same_line_start,
    next_line,
};

const Formatter = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    comments: []Comment,
    comment_cursor: usize = 0,
    buf: std.ArrayList(u8),
    indent: usize = 0,
    force_vertical_pipe: bool = false,

    fn init(allocator: std.mem.Allocator, source: []const u8, comments: []Comment) Formatter {
        return .{
            .allocator = allocator,
            .source = source,
            .comments = comments,
            .buf = .empty,
        };
    }

    fn deinit(self: *Formatter) void {
        self.buf.deinit(self.allocator);
        self.allocator.free(self.comments);
    }

    fn finish(self: *Formatter) ![]u8 {
        self.emitRemainingComments();
        while (self.buf.items.len > 0 and
            (self.buf.items[self.buf.items.len - 1] == '\n' or self.buf.items[self.buf.items.len - 1] == ' '))
        {
            _ = self.buf.pop();
        }
        try self.buf.append(self.allocator, '\n');
        return try self.buf.toOwnedSlice(self.allocator);
    }

    fn write(self: *Formatter, text: []const u8) !void {
        try self.buf.appendSlice(self.allocator, text);
    }

    fn writeByte(self: *Formatter, byte: u8) !void {
        try self.buf.append(self.allocator, byte);
    }

    fn newline(self: *Formatter) !void {
        try self.writeByte('\n');
    }

    fn writeIndent(self: *Formatter) !void {
        var index: usize = 0;
        while (index < self.indent) : (index += 1) {
            try self.write(indent_unit);
        }
    }

    fn currentLineWidth(self: *Formatter) usize {
        const last_newline = std.mem.lastIndexOfScalar(u8, self.buf.items, '\n') orelse return self.buf.items.len;
        return self.buf.items.len - last_newline - 1;
    }

    fn tokenText(self: *Formatter, token: ast.Token) []const u8 {
        return self.source[token.span.start..token.span.end];
    }

    fn formatProgram(self: *Formatter, items: []ast.Expr) !void {
        for (items, 0..) |expr, index| {
            if (index > 0) {
                const prev = items[index - 1];
                if (self.isFunctionBoundary(prev, expr) or self.isItemMultiline(prev) or self.isItemMultiline(expr)) {
                    try self.newline();
                }
            }
            self.emitCommentsBefore(ast.exprSpan(expr).start);
            try self.formatTopLevelExpression(expr);
            const next_start = if (index + 1 < items.len) ast.exprSpan(items[index + 1]).start else self.source.len;
            self.emitTrailingComment(ast.exprSpan(expr).end, next_start);
            try self.newline();
        }
    }

    fn isFunctionBoundary(self: *Formatter, lhs: ast.Expr, rhs: ast.Expr) bool {
        _ = self;
        return isFunctionDecl(lhs) or isFunctionDecl(rhs);
    }

    fn formatTopLevelExpression(self: *Formatter, expr: ast.Expr) !void {
        if (isBinding(expr) or isFunctionDecl(expr)) {
            try self.writeIndent();
        } else {
            try self.writeIndent();
        }
        try self.formatExpression(expr);
    }

    fn formatExpression(self: *Formatter, expr: ast.Expr) anyerror!void {
        switch (expr) {
            .token => |token| try self.write(self.tokenText(token)),
            .path => |path| try self.formatPath(path),
            .group => |group| try self.formatStandaloneGroup(group),
            .apply => |apply| try self.formatApply(apply),
            .access => |access| try self.formatAccess(access),
            .unary => |unary| try self.formatUnary(unary),
            .binary => |binary| try self.formatBinary(binary),
        }
    }

    fn formatPath(self: *Formatter, path: *ast.Path) !void {
        for (path.segments, 0..) |segment, index| {
            if (index > 0) try self.write("/");
            try self.write(self.tokenText(segment));
        }
    }

    fn formatStandaloneGroup(self: *Formatter, group: *ast.Group) !void {
        switch (group.delimiter) {
            .parentheses => try self.formatDelimitedInline(group, "(", ")"),
            .brackets => try self.formatStructuredGroup(group, "[", "]"),
            .braces => try self.formatStructuredGroup(group, "{", "}"),
            .root => unreachable,
        }
    }

    fn formatStructuredGroup(self: *Formatter, group: *ast.Group, open: []const u8, close: []const u8) !void {
        if (countNonCommaItems(group.items) == 0) {
            try self.write(open);
            try self.write(close);
            return;
        }

        if (try self.tryInlineGroupItems(group.items)) |inline_text| {
            defer self.allocator.free(inline_text);
            if (self.currentLineWidth() + open.len + inline_text.len + close.len <= max_line_width) {
                try self.write(open);
                try self.write(inline_text);
                try self.write(close);
                return;
            }
        }

        try self.write(open);
        try self.newline();
        self.indent += 1;
        try self.formatGroupItems(group.items);
        self.indent -= 1;
        try self.writeIndent();
        try self.write(close);
    }

    fn formatDelimitedInline(self: *Formatter, group: *ast.Group, open: []const u8, close: []const u8) !void {
        try self.write(open);
        if (group.items.len == 0) {
            try self.write(close);
            return;
        }

        var first = true;
        for (group.items) |item| {
            if (!first) try self.write(", ");
            first = false;
            try self.formatExpression(item);
        }
        try self.write(close);
    }

    fn formatAccess(self: *Formatter, access: *ast.Access) !void {
        try self.formatExpression(access.target);
        switch (access.kind) {
            .direct => try self.write("."),
            .optional => try self.write("?."),
        }
        try self.write(self.tokenText(access.field));
    }

    fn formatUnary(self: *Formatter, unary: *ast.Unary) !void {
        switch (unary.operator) {
            .negate => try self.write("-"),
            .spread => try self.write("..."),
        }
        try self.formatExpression(unary.operand);
    }

    fn formatBinary(self: *Formatter, binary: *ast.Binary) !void {
        switch (binary.operator) {
            .bind => try self.formatBinding(binary),
            .arm_arrow => try self.formatArm(binary),
            .pipe_forward => try self.formatPipe(binary),
            else => {
                try self.formatExpression(binary.lhs);
                try self.write(" ");
                try self.write(binaryOperatorText(binary.operator));
                try self.write(" ");
                try self.formatExpression(binary.rhs);
            },
        }
    }

    fn formatBinding(self: *Formatter, binary: *ast.Binary) !void {
        try self.formatExpression(binary.lhs);
        try self.write(":");

        const layout = try self.valueLayout(binary.rhs, 1);
        switch (layout) {
            .inline_value, .same_line_start => {
                try self.write(" ");
                try self.formatExpression(binary.rhs);
            },
            .next_line => {
                try self.newline();
                self.indent += 1;
                defer self.indent -= 1;
                try self.writeIndent();
                if (isPipe(binary.rhs)) self.force_vertical_pipe = true;
                try self.formatExpression(binary.rhs);
            },
        }
    }

    fn formatArm(self: *Formatter, binary: *ast.Binary) !void {
        try self.formatExpression(binary.lhs);
        const layout = try self.valueLayout(binary.rhs, " => ".len);
        switch (layout) {
            .inline_value, .same_line_start => {
                try self.write(" => ");
                try self.formatExpression(binary.rhs);
            },
            .next_line => {
                try self.write(" =>");
                try self.newline();
                self.indent += 1;
                defer self.indent -= 1;
                try self.writeIndent();
                if (isPipe(binary.rhs)) self.force_vertical_pipe = true;
                try self.formatExpression(binary.rhs);
            },
        }
    }

    fn formatPipe(self: *Formatter, binary: *ast.Binary) !void {
        var chain = std.ArrayList(ast.Expr).empty;
        defer chain.deinit(self.allocator);
        try self.collectPipeChain(binary.lhs, &chain);
        try chain.append(self.allocator, binary.rhs);

        const force_vertical = self.force_vertical_pipe;
        self.force_vertical_pipe = false;

        if (!force_vertical) {
            if (try self.tryInlinePipeChain(chain.items)) |inline_text| {
                defer self.allocator.free(inline_text);
                if (self.currentLineWidth() + inline_text.len <= max_line_width) {
                    try self.write(inline_text);
                    return;
                }
            }
        }

        const first_inline = try self.estimateInline(chain.items[0]);
        const first_fits = if (first_inline) |inline_text| blk: {
            defer self.allocator.free(inline_text);
            break :blk self.currentLineWidth() + inline_text.len <= max_line_width;
        } else false;

        if (!force_vertical and first_fits and chain.items.len == 2) {
            try self.formatExpression(chain.items[0]);
            const hug_width = if (try self.estimateInline(chain.items[1])) |inline_text| blk: {
                defer self.allocator.free(inline_text);
                break :blk " |> ".len + inline_text.len;
            } else " |> ".len + try self.estimateOpeningWidth(chain.items[1]);

            if (self.currentLineWidth() + hug_width <= max_line_width) {
                try self.write(" |> ");
                try self.formatExpression(chain.items[1]);
            } else {
                try self.newline();
                try self.writeIndent();
                try self.write("|> ");
                try self.formatExpression(chain.items[1]);
            }
            return;
        }

        try self.formatExpression(chain.items[0]);
        for (chain.items[1..]) |segment| {
            try self.newline();
            try self.writeIndent();
            try self.write("|> ");
            try self.formatExpression(segment);
        }
    }

    fn collectPipeChain(self: *Formatter, expr: ast.Expr, chain: *std.ArrayList(ast.Expr)) !void {
        if (expr == .binary and expr.binary.operator == .pipe_forward) {
            try self.collectPipeChain(expr.binary.lhs, chain);
            try chain.append(self.allocator, expr.binary.rhs);
        } else {
            try chain.append(self.allocator, expr);
        }
    }

    fn formatApply(self: *Formatter, apply: *ast.Apply) !void {
        if (try self.formatSpecialApply(apply)) return;

        try self.formatExpression(apply.head);
        switch (apply.kind) {
            .call => {
                if (apply.arguments.len == 1 and apply.arguments[0] == .group and apply.arguments[0].group.delimiter == .parentheses) {
                    try self.formatCallArguments(apply.arguments[0].group);
                } else {
                    for (apply.arguments) |arg| {
                        try self.write(" ");
                        try self.formatExpression(arg);
                    }
                }
            },
            .keyword_form => {
                for (apply.arguments) |arg| {
                    try self.write(" ");
                    try self.formatExpression(arg);
                }
            },
            .tagged_value => {
                for (apply.arguments) |arg| {
                    try self.write(" ");
                    try self.formatExpression(arg);
                }
            },
        }
    }

    fn formatSpecialApply(self: *Formatter, apply: *ast.Apply) !bool {
        if (try self.formatFunctionDecl(apply)) return true;
        if (try self.formatBlockKeyword(apply, "BLOCK")) return true;
        if (try self.formatBlockKeyword(apply, "LATEST")) return true;
        if (try self.formatBlockKeyword(apply, "WHEN")) return true;
        if (try self.formatBlockKeyword(apply, "WHILE")) return true;
        if (try self.formatKeywordWithState(apply, "HOLD")) return true;
        if (try self.formatKeywordBraceValue(apply, "LINK")) return true;
        if (try self.formatKeywordBraceValue(apply, "THEN")) return true;
        if (try self.formatKeywordBraceValue(apply, "FLUSH")) return true;
        if (try self.formatListLike(apply, "LIST")) return true;
        if (try self.formatListLike(apply, "MAP")) return true;
        if (try self.formatText(apply)) return true;
        return false;
    }

    fn formatFunctionDecl(self: *Formatter, apply: *ast.Apply) !bool {
        if (apply.kind != .keyword_form or apply.arguments.len != 3) return false;
        if (!tokenIsText(apply.head, self.source, "FUNCTION")) return false;
        if (apply.arguments[0] != .token or apply.arguments[1] != .group or apply.arguments[2] != .group) return false;
        if (apply.arguments[1].group.delimiter != .parentheses or apply.arguments[2].group.delimiter != .braces) return false;

        try self.write("FUNCTION ");
        try self.write(self.tokenText(apply.arguments[0].token));
        try self.write("(");
        var first = true;
        for (apply.arguments[1].group.items) |param| {
            if (isCommaToken(param)) continue;
            if (!first) try self.write(", ");
            first = false;
            try self.formatExpression(param);
        }
        try self.write(") {");
        try self.newline();
        self.indent += 1;
        try self.formatBodyItems(apply.arguments[2].group.items);
        self.indent -= 1;
        try self.writeIndent();
        try self.write("}");
        return true;
    }

    fn formatBlockKeyword(self: *Formatter, apply: *ast.Apply, keyword: []const u8) !bool {
        if (apply.kind != .keyword_form or apply.arguments.len != 1) return false;
        if (!tokenIsText(apply.head, self.source, keyword)) return false;
        if (apply.arguments[0] != .group or apply.arguments[0].group.delimiter != .braces) return false;

        try self.write(keyword);
        try self.write(" {");
        try self.newline();
        self.indent += 1;
        try self.formatBodyItems(apply.arguments[0].group.items);
        self.indent -= 1;
        try self.writeIndent();
        try self.write("}");
        return true;
    }

    fn formatKeywordWithState(self: *Formatter, apply: *ast.Apply, keyword: []const u8) !bool {
        if (apply.kind != .keyword_form or apply.arguments.len != 2) return false;
        if (!tokenIsText(apply.head, self.source, keyword)) return false;
        if (apply.arguments[1] != .group or apply.arguments[1].group.delimiter != .braces) return false;

        try self.write(keyword);
        try self.write(" ");
        try self.formatExpression(apply.arguments[0]);
        try self.write(" {");
        try self.newline();
        self.indent += 1;
        try self.formatBodyItems(apply.arguments[1].group.items);
        self.indent -= 1;
        try self.writeIndent();
        try self.write("}");
        return true;
    }

    fn formatKeywordBraceValue(self: *Formatter, apply: *ast.Apply, keyword: []const u8) !bool {
        if (apply.kind != .keyword_form or apply.arguments.len != 1) return false;
        if (!tokenIsText(apply.head, self.source, keyword)) return false;
        if (apply.arguments[0] != .group or apply.arguments[0].group.delimiter != .braces) return false;

        if (try self.tryInlineBraceBody(apply.arguments[0].group.items)) |inline_text| {
            defer self.allocator.free(inline_text);
            const total = keyword.len + " { ".len + inline_text.len + " }".len;
            if (self.currentLineWidth() + total <= max_line_width) {
                try self.write(keyword);
                try self.write(" { ");
                try self.write(inline_text);
                try self.write(" }");
                return true;
            }
        }

        try self.write(keyword);
        try self.write(" {");
        try self.newline();
        self.indent += 1;
        try self.formatBodyItems(apply.arguments[0].group.items);
        self.indent -= 1;
        try self.writeIndent();
        try self.write("}");
        return true;
    }

    fn formatListLike(self: *Formatter, apply: *ast.Apply, keyword: []const u8) !bool {
        if (apply.kind != .keyword_form or apply.arguments.len != 1) return false;
        if (!tokenIsText(apply.head, self.source, keyword)) return false;
        if (apply.arguments[0] != .group or apply.arguments[0].group.delimiter != .braces) return false;

        const items = apply.arguments[0].group.items;
        if (countNonCommaItems(items) == 0) {
            try self.write(keyword);
            try self.write(" {}");
            return true;
        }

        try self.write(keyword);
        try self.write(" {");
        try self.newline();
        self.indent += 1;
        var previous_item: ?ast.Expr = null;
        for (items) |item| {
            if (isCommaToken(item)) continue;
            if (previous_item) |prev| {
                if (self.isItemMultiline(prev) or self.isItemMultiline(item)) {
                    try self.newline();
                }
            }
            previous_item = item;
            try self.writeIndent();
            try self.formatExpression(item);
            try self.newline();
        }
        self.indent -= 1;
        try self.writeIndent();
        try self.write("}");
        return true;
    }

    fn formatText(self: *Formatter, apply: *ast.Apply) !bool {
        if (apply.kind != .keyword_form or apply.arguments.len != 1) return false;
        if (!tokenIsText(apply.head, self.source, "TEXT")) return false;
        if (apply.arguments[0] != .group or apply.arguments[0].group.delimiter != .braces) return false;

        const content = try self.groupSourceTrimmed(apply.arguments[0].group);
        defer self.allocator.free(content);

        const inline_len = "TEXT { ".len + content.len + " }".len;
        if (self.currentLineWidth() + inline_len <= max_line_width) {
            try self.write("TEXT { ");
            try self.write(content);
            try self.write(" }");
            return true;
        }

        try self.write("TEXT {");
        try self.newline();
        self.indent += 1;
        try self.writeIndent();
        try self.write(content);
        try self.newline();
        self.indent -= 1;
        try self.writeIndent();
        try self.write("}");
        return true;
    }

    fn formatCallArguments(self: *Formatter, group: *ast.Group) !void {
        const args = group.items;
        try self.write("(");
        if (countNonCommaItems(args) == 0) {
            try self.write(")");
            return;
        }

        if (try self.tryInlineArguments(args)) |inline_text| {
            defer self.allocator.free(inline_text);
            const available = max_line_width -| (self.currentLineWidth() + 1);
            if (inline_text.len <= available) {
                try self.write(inline_text);
                try self.write(")");
                return;
            }
        }

        const filtered_last = lastNonCommaItem(args) orelse unreachable;
        if (countNonCommaItems(args) > 0) {
            const last = filtered_last;
            const has_multiline_last = (try self.estimateInline(last)) == null;
            if (has_multiline_last) {
                if (try self.tryLastArgPrefix(args)) |prefix| {
                    defer self.allocator.free(prefix);
                    if (prefix.len <= max_last_arg_prefix and self.currentLineWidth() + prefix.len <= max_line_width) {
                        try self.write(prefix);
                        try self.formatArgumentValue(last);
                        try self.write(")");
                        return;
                    }
                }
            }
        }

        try self.newline();
        self.indent += 1;
        var previous_arg: ?ast.Expr = null;
        for (args) |arg| {
            if (isCommaToken(arg)) continue;
            if (previous_arg) |prev| {
                if (self.isArgumentMultiline(prev) or self.isArgumentMultiline(arg)) {
                    try self.newline();
                }
            }
            previous_arg = arg;
            self.emitCommentsBefore(ast.exprSpan(arg).start);
            try self.writeIndent();
            try self.formatArgument(arg);
            const next_start = nextNonCommaStart(args, arg, self.source.len);
            self.emitTrailingComment(ast.exprSpan(arg).end, next_start);
            try self.newline();
        }
        self.indent -= 1;
        try self.writeIndent();
        try self.write(")");
    }

    fn formatArgument(self: *Formatter, expr: ast.Expr) !void {
        if (isCommaToken(expr)) return;
        if (expr == .binary and expr.binary.operator == .bind) {
            try self.formatExpression(expr.binary.lhs);
            try self.write(":");
            const layout = try self.valueLayout(expr.binary.rhs, 1);
            switch (layout) {
                .inline_value, .same_line_start => {
                    try self.write(" ");
                    try self.formatExpression(expr.binary.rhs);
                },
                .next_line => {
                    try self.newline();
                    self.indent += 1;
                    defer self.indent -= 1;
                    try self.writeIndent();
                    if (isPipe(expr.binary.rhs)) self.force_vertical_pipe = true;
                    try self.formatExpression(expr.binary.rhs);
                },
            }
            return;
        }

        try self.formatExpression(expr);
    }

    fn formatArgumentValue(self: *Formatter, expr: ast.Expr) !void {
        if (expr == .binary and expr.binary.operator == .bind) {
            try self.formatExpression(expr.binary.rhs);
            return;
        }
        try self.formatExpression(expr);
    }

    fn formatBodyItems(self: *Formatter, items: []ast.Expr) !void {
        var previous_item: ?ast.Expr = null;
        for (items) |item| {
            if (isCommaToken(item)) continue;
            if (previous_item) |prev| {
                if (self.isItemMultiline(prev) or self.isItemMultiline(item)) {
                    try self.newline();
                }
            }
            previous_item = item;
            self.emitCommentsBefore(ast.exprSpan(item).start);
            try self.writeIndent();
            try self.formatExpression(item);
            const next_start = nextNonCommaStart(items, item, self.source.len);
            self.emitTrailingComment(ast.exprSpan(item).end, next_start);
            try self.newline();
        }
    }

    fn formatGroupItems(self: *Formatter, items: []ast.Expr) !void {
        var previous_item: ?ast.Expr = null;
        for (items) |item| {
            if (isCommaToken(item)) continue;
            if (previous_item) |prev| {
                if (self.isItemMultiline(prev) or self.isItemMultiline(item)) {
                    try self.newline();
                }
            }
            previous_item = item;
            self.emitCommentsBefore(ast.exprSpan(item).start);
            try self.writeIndent();
            try self.formatExpression(item);
            const next_start = nextNonCommaStart(items, item, self.source.len);
            self.emitTrailingComment(ast.exprSpan(item).end, next_start);
            try self.newline();
        }
    }

    fn valueLayout(self: *Formatter, expr: ast.Expr, separator_width: usize) !ValueLayout {
        const available = self.currentLineWidth() + separator_width;
        if (try self.shouldInlineValue(expr)) {
            if (try self.estimateInline(expr)) |inline_text| {
                defer self.allocator.free(inline_text);
                if (available + inline_text.len <= max_line_width) return .inline_value;
            }
        }

        return switch (expr) {
            .apply => |apply| switch (apply.kind) {
                .call => if (apply.arguments.len > 0) .same_line_start else .inline_value,
                .keyword_form => if (startsWithSameLineKeyword(apply, self.source)) .same_line_start else .next_line,
                .tagged_value => .same_line_start,
            },
            .group => |group| switch (group.delimiter) {
                .brackets, .braces => if (group.items.len > 0) .same_line_start else .inline_value,
                .parentheses => if (group.items.len > 0) .same_line_start else .inline_value,
                .root => .next_line,
            },
            .binary => |binary| if (binary.operator == .pipe_forward) blk: {
                var chain = std.ArrayList(ast.Expr).empty;
                defer chain.deinit(self.allocator);
                try self.collectPipeChain(binary.lhs, &chain);
                try chain.append(self.allocator, binary.rhs);
                if (chain.items.len == 2) {
                    if (try self.estimateInline(chain.items[0])) |first| {
                        defer self.allocator.free(first);
                        const hug_width = if (try self.estimateInline(chain.items[1])) |inline_text| blk2: {
                            defer self.allocator.free(inline_text);
                            break :blk2 " |> ".len + inline_text.len;
                        } else " |> ".len + try self.estimateOpeningWidth(chain.items[1]);
                        if (available + first.len + hug_width <= max_line_width) break :blk .same_line_start;
                    }
                }
                break :blk .next_line;
            } else .next_line,
            else => .next_line,
        };
    }

    fn shouldInlineValue(self: *Formatter, expr: ast.Expr) !bool {
        return switch (expr) {
            .token, .path, .access => true,
            .unary => |unary| try self.shouldInlineValue(unary.operand),
            .binary => |binary| switch (binary.operator) {
                .equal, .not_equal, .greater, .greater_equal, .less, .less_equal, .add, .subtract, .multiply, .divide, .modulo, .power => blk: {
                    if (try self.estimateInline(expr)) |inline_text| {
                        defer self.allocator.free(inline_text);
                        break :blk inline_text.len <= 40;
                    }
                    break :blk false;
                },
                .pipe_forward => (try self.tryInlinePipeChain(&.{expr})) != null,
                else => false,
            },
            .group => |group| switch (group.delimiter) {
                .brackets, .braces => (try self.tryInlineGroupItems(group.items)) != null,
                .parentheses => group.items.len == 0,
                .root => false,
            },
            .apply => |apply| switch (apply.kind) {
                .call => (try self.tryInlineArguments(apply.arguments)) != null,
                .keyword_form => blk: {
                    if (tokenIsText(apply.head, self.source, "TEXT")) {
                        if (try self.estimateInline(expr)) |inline_text| {
                            defer self.allocator.free(inline_text);
                            break :blk inline_text.len <= 60;
                        }
                    }
                    break :blk false;
                },
                .tagged_value => true,
            },
        };
    }

    fn isMultiline(self: *Formatter, expr: ast.Expr) bool {
        return switch (expr) {
            .apply => |apply| switch (apply.kind) {
                .call => apply.arguments.len > 0,
                .keyword_form => startsWithMultilineKeyword(apply, self.source),
                .tagged_value => false,
            },
            .binary => |binary| switch (binary.operator) {
                .bind, .arm_arrow => true,
                .pipe_forward => true,
                else => false,
            },
            .group => |group| group.items.len > 0,
            else => false,
        };
    }

    fn isVariableMultiline(self: *Formatter, expr: ast.Expr) bool {
        if (!(expr == .binary and expr.binary.operator == .bind)) return self.isMultiline(expr);
        const lhs_len = self.exprInlineWidth(expr.binary.lhs) catch return true;
        const prefix = self.indent * indent_unit.len + lhs_len + 2;
        if (self.estimateInline(expr.binary.rhs) catch null) |inline_text| {
            defer self.allocator.free(inline_text);
            return prefix + inline_text.len > max_line_width;
        }
        return true;
    }

    fn isArgumentMultiline(self: *Formatter, expr: ast.Expr) bool {
        if (!(expr == .binary and expr.binary.operator == .bind)) {
            if (self.estimateInline(expr) catch null) |inline_text| {
                defer self.allocator.free(inline_text);
                return self.indent * indent_unit.len + inline_text.len > max_line_width;
            }
            return true;
        }
        const lhs_len = self.exprInlineWidth(expr.binary.lhs) catch return true;
        const prefix = self.indent * indent_unit.len + lhs_len + 2;
        if (self.estimateInline(expr.binary.rhs) catch null) |inline_text| {
            defer self.allocator.free(inline_text);
            return prefix + inline_text.len > max_line_width;
        }
        return true;
    }

    fn isItemMultiline(self: *Formatter, expr: ast.Expr) bool {
        if (isFunctionDecl(expr)) return true;
        if (expr == .binary and expr.binary.operator == .bind) return self.isVariableMultiline(expr);
        if (self.estimateInline(expr) catch null) |inline_text| {
            defer self.allocator.free(inline_text);
            return self.indent * indent_unit.len + inline_text.len > max_line_width;
        }
        return true;
    }

    fn exprInlineWidth(self: *Formatter, expr: ast.Expr) !usize {
        if (try self.estimateInline(expr)) |inline_text| {
            defer self.allocator.free(inline_text);
            return inline_text.len;
        }
        return error.NotInlineable;
    }

    fn estimateInline(self: *Formatter, expr: ast.Expr) !?[]u8 {
        const empty_comments = try self.allocator.alloc(Comment, 0);
        var temp = Formatter.init(self.allocator, self.source, empty_comments);
        defer temp.deinit();
        temp.comment_cursor = temp.comments.len;
        try temp.formatExpression(expr);
        if (std.mem.indexOfScalar(u8, temp.buf.items, '\n') != null) return null;
        return try self.allocator.dupe(u8, temp.buf.items);
    }

    fn estimateOpeningWidth(self: *Formatter, expr: ast.Expr) !usize {
        return switch (expr) {
            .apply => |apply| switch (apply.kind) {
                .call => blk: {
                    if (apply.head == .path) {
                        var width: usize = 0;
                        for (apply.head.path.segments, 0..) |segment, index| {
                            if (index > 0) width += 1;
                            width += self.tokenText(segment).len;
                        }
                        break :blk width + 1;
                    }
                    break :blk 1;
                },
                .keyword_form => if (apply.head == .token) self.tokenText(apply.head.token).len + " {".len else 1,
                .tagged_value => 1,
            },
            .group => |group| switch (group.delimiter) {
                .parentheses => 1,
                .brackets => 1,
                .braces => 1,
                .root => 0,
            },
            else => 0,
        };
    }

    fn tryInlineArguments(self: *Formatter, args: []ast.Expr) !?[]u8 {
        var parts = std.ArrayList([]u8).empty;
        defer {
            for (parts.items) |part| self.allocator.free(part);
            parts.deinit(self.allocator);
        }

        for (args) |arg| {
            if (isCommaToken(arg)) continue;
            if (arg == .binary and arg.binary.operator == .bind) {
                const lhs = try self.estimateInline(arg.binary.lhs) orelse return null;
                errdefer self.allocator.free(lhs);
                const rhs = try self.estimateInline(arg.binary.rhs) orelse {
                    self.allocator.free(lhs);
                    return null;
                };
                errdefer self.allocator.free(rhs);
                const part = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ lhs, rhs });
                self.allocator.free(lhs);
                self.allocator.free(rhs);
                try parts.append(self.allocator, part);
            } else {
                const inline_text = try self.estimateInline(arg) orelse return null;
                try parts.append(self.allocator, inline_text);
            }
        }
        return try std.mem.join(self.allocator, ", ", parts.items);
    }

    fn tryInlineGroupItems(self: *Formatter, items: []ast.Expr) !?[]u8 {
        var parts = std.ArrayList([]u8).empty;
        defer {
            for (parts.items) |part| self.allocator.free(part);
            parts.deinit(self.allocator);
        }

        for (items) |item| {
            if (isCommaToken(item)) continue;
            if (item == .binary and item.binary.operator == .bind) {
                const lhs = try self.estimateInline(item.binary.lhs) orelse return null;
                errdefer self.allocator.free(lhs);
                const rhs = try self.estimateInline(item.binary.rhs) orelse {
                    self.allocator.free(lhs);
                    return null;
                };
                errdefer self.allocator.free(rhs);
                const part = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ lhs, rhs });
                self.allocator.free(lhs);
                self.allocator.free(rhs);
                try parts.append(self.allocator, part);
            } else {
                const inline_text = try self.estimateInline(item) orelse return null;
                try parts.append(self.allocator, inline_text);
            }
        }

        return try std.mem.join(self.allocator, ", ", parts.items);
    }

    fn tryLastArgPrefix(self: *Formatter, args: []ast.Expr) !?[]u8 {
        const last = lastNonCommaItem(args) orelse return null;
        if (!(last == .binary and last.binary.operator == .bind)) return null;

        var parts = std.ArrayList([]u8).empty;
        defer {
            for (parts.items) |part| self.allocator.free(part);
            parts.deinit(self.allocator);
        }

        for (args) |arg| {
            if (isCommaToken(arg)) continue;
            if (std.meta.eql(arg, last)) break;
            if (arg == .binary and arg.binary.operator == .bind) {
                const lhs = try self.estimateInline(arg.binary.lhs) orelse return null;
                errdefer self.allocator.free(lhs);
                const rhs = try self.estimateInline(arg.binary.rhs) orelse {
                    self.allocator.free(lhs);
                    return null;
                };
                errdefer self.allocator.free(rhs);
                const part = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ lhs, rhs });
                self.allocator.free(lhs);
                self.allocator.free(rhs);
                try parts.append(self.allocator, part);
            } else {
                const inline_text = try self.estimateInline(arg) orelse return null;
                try parts.append(self.allocator, inline_text);
            }
        }

        const last_name = try self.estimateInline(last.binary.lhs) orelse return null;
        defer self.allocator.free(last_name);

        const prefix_join = try std.mem.join(self.allocator, ", ", parts.items);
        defer self.allocator.free(prefix_join);

        if (prefix_join.len == 0) return try std.fmt.allocPrint(self.allocator, "{s}: ", .{last_name});
        return try std.fmt.allocPrint(self.allocator, "{s}, {s}: ", .{ prefix_join, last_name });
    }

    fn tryInlinePipeChain(self: *Formatter, chain: []const ast.Expr) !?[]u8 {
        if (chain.len > max_inline_pipe_parts) return null;
        var parts = std.ArrayList([]u8).empty;
        defer {
            for (parts.items) |part| self.allocator.free(part);
            parts.deinit(self.allocator);
        }
        for (chain) |expr| {
            const inline_text = try self.estimateInline(expr) orelse return null;
            try parts.append(self.allocator, inline_text);
        }
        return try std.mem.join(self.allocator, " |> ", parts.items);
    }

    fn tryInlineBraceBody(self: *Formatter, items: []ast.Expr) !?[]u8 {
        if (items.len != 1) return null;
        return try self.estimateInline(items[0]);
    }

    fn groupSourceTrimmed(self: *Formatter, group: *ast.Group) ![]u8 {
        const inner_start = group.span.start + 1;
        const inner_end = group.span.end - 1;
        const trimmed = std.mem.trim(u8, self.source[inner_start..inner_end], " \n\r\t");
        return try self.allocator.dupe(u8, trimmed);
    }

    fn writeComment(self: *Formatter, comment: Comment) void {
        self.write(self.source[comment.start..comment.end]) catch unreachable;
    }

    fn emitCommentsBefore(self: *Formatter, before_pos: usize) void {
        var prev_comment_end: ?usize = null;
        while (self.comment_cursor < self.comments.len) {
            const comment = self.comments[self.comment_cursor];
            if (comment.start >= before_pos) break;
            if (comment.is_standalone) {
                if (prev_comment_end) |prev_end| {
                    const between = self.source[prev_end..comment.start];
                    const newline_count = std.mem.count(u8, between, "\n");
                    if (newline_count >= 2) self.newline() catch unreachable;
                }
                self.writeIndent() catch unreachable;
                self.writeComment(comment);
                self.newline() catch unreachable;
                prev_comment_end = comment.end;
            }
            self.comment_cursor += 1;
        }
        if (prev_comment_end) |prev_end| {
            const between = self.source[prev_end..before_pos];
            const newline_count = std.mem.count(u8, between, "\n");
            if (newline_count >= 2) self.newline() catch unreachable;
        }
    }

    fn emitTrailingComment(self: *Formatter, after_pos: usize, before_next_pos: usize) void {
        while (self.comment_cursor < self.comments.len) {
            const comment = self.comments[self.comment_cursor];
            if (comment.start >= before_next_pos) break;
            if (comment.start >= after_pos and !comment.is_standalone) {
                self.write("  ") catch unreachable;
                self.writeComment(comment);
                self.comment_cursor += 1;
                return;
            }
            if (comment.start >= after_pos and comment.is_standalone) break;
            self.comment_cursor += 1;
        }
    }

    fn emitRemainingComments(self: *Formatter) void {
        while (self.comment_cursor < self.comments.len) {
            const comment = self.comments[self.comment_cursor];
            if (comment.is_standalone) {
                self.writeIndent() catch unreachable;
                self.writeComment(comment);
                self.newline() catch unreachable;
            } else {
                self.write("  ") catch unreachable;
                self.writeComment(comment);
                self.newline() catch unreachable;
            }
            self.comment_cursor += 1;
        }
    }
};

fn collectCommentsAlloc(allocator: std.mem.Allocator, source: []const u8) ![]Comment {
    var comments: std.ArrayList(Comment) = .empty;
    defer comments.deinit(allocator);

    var index: usize = 0;
    while (index + 1 < source.len) {
        if (source[index] == '-' and source[index + 1] == '-') {
            const start = index;
            var end = index + 2;
            while (end < source.len and source[end] != '\n') : (end += 1) {}

            var line_start = start;
            while (line_start > 0 and source[line_start - 1] != '\n') : (line_start -= 1) {}
            const prefix = source[line_start..start];
            const is_standalone = std.mem.trim(u8, prefix, " \t\r").len == 0;

            try comments.append(allocator, .{
                .start = start,
                .end = end,
                .is_standalone = is_standalone,
            });
            index = end;
            continue;
        }
        index += 1;
    }

    return try comments.toOwnedSlice(allocator);
}

fn nextNonCommaStart(items: []const ast.Expr, current: ast.Expr, default: usize) usize {
    var seen_current = false;
    for (items) |item| {
        if (isCommaToken(item)) continue;
        if (!seen_current) {
            if (std.meta.eql(item, current)) seen_current = true;
            continue;
        }
        return ast.exprSpan(item).start;
    }
    return default;
}

fn tokenIsText(expr: ast.Expr, source: []const u8, text: []const u8) bool {
    return expr == .token and std.mem.eql(u8, source[expr.token.span.start..expr.token.span.end], text);
}

fn startsWithSameLineKeyword(apply: *ast.Apply, source: []const u8) bool {
    if (apply.head != .token) return false;
    const text = source[apply.head.token.span.start..apply.head.token.span.end];
    return std.mem.eql(u8, text, "LATEST") or
        std.mem.eql(u8, text, "WHEN") or
        std.mem.eql(u8, text, "WHILE") or
        std.mem.eql(u8, text, "HOLD") or
        std.mem.eql(u8, text, "LINK") or
        std.mem.eql(u8, text, "THEN") or
        std.mem.eql(u8, text, "FLUSH") or
        std.mem.eql(u8, text, "BLOCK") or
        std.mem.eql(u8, text, "TEXT") or
        std.mem.eql(u8, text, "LIST") or
        std.mem.eql(u8, text, "MAP");
}

fn startsWithMultilineKeyword(apply: *ast.Apply, source: []const u8) bool {
    if (apply.head != .token) return false;
    const text = source[apply.head.token.span.start..apply.head.token.span.end];
    return std.mem.eql(u8, text, "LATEST") or
        std.mem.eql(u8, text, "WHEN") or
        std.mem.eql(u8, text, "WHILE") or
        std.mem.eql(u8, text, "HOLD") or
        std.mem.eql(u8, text, "BLOCK");
}

fn isFunctionDecl(expr: ast.Expr) bool {
    return expr == .apply and
        expr.apply.kind == .keyword_form and
        expr.apply.head == .apply and
        expr.apply.head.apply.kind == .keyword_form and
        expr.apply.head.apply.head == .token;
}

fn isBinding(expr: ast.Expr) bool {
    return expr == .binary and expr.binary.operator == .bind;
}

fn isPipe(expr: ast.Expr) bool {
    return expr == .binary and expr.binary.operator == .pipe_forward;
}

fn isCommaToken(expr: ast.Expr) bool {
    return expr == .token and expr.token.kind == .comma;
}

fn countNonCommaItems(items: []const ast.Expr) usize {
    var count: usize = 0;
    for (items) |item| {
        if (!isCommaToken(item)) count += 1;
    }
    return count;
}

fn lastNonCommaItem(items: []const ast.Expr) ?ast.Expr {
    var index = items.len;
    while (index > 0) {
        index -= 1;
        if (!isCommaToken(items[index])) return items[index];
    }
    return null;
}

fn binaryOperatorText(operator: ast.BinaryOp) []const u8 {
    return switch (operator) {
        .equal => "==",
        .not_equal => "=/=",
        .greater => ">",
        .greater_equal => ">=",
        .less => "<",
        .less_equal => "<=",
        .add => "+",
        .subtract => "-",
        .multiply => "*",
        .divide => "/",
        .modulo => "%",
        .power => "^",
        .bind, .pipe_forward, .arm_arrow => unreachable,
    };
}

fn expectFormatsTo(comptime input: []const u8, comptime expected: []const u8) !void {
    const outcome = try formatAlloc(std.testing.allocator, input);
    const formatted = switch (outcome) {
        .ok => |formatted| formatted,
        .err => |failure| {
            std.debug.print("format failure: {s}\n", .{failure.message});
            return error.UnexpectedFormatFailure;
        },
    };
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings(expected, formatted);
}

test "format simple variable" {
    try expectFormatsTo("x: 5", "x: 5\n");
}

test "format function" {
    try expectFormatsTo(
        "FUNCTION foo(x, y) { x + y }",
        "FUNCTION foo(x, y) {\n    x + y\n}\n",
    );
}

test "format latest" {
    try expectFormatsTo(
        "x: LATEST { 1 2 }",
        "x: LATEST {\n    1\n    2\n}\n",
    );
}

test "format text literal" {
    try expectFormatsTo("x: TEXT { hello world }", "x: TEXT { hello world }\n");
}

test "format when" {
    try expectFormatsTo(
        "x: WHEN { True => 1 False => 0 }",
        "x: WHEN {\n    True => 1\n    False => 0\n}\n",
    );
}

test "format block with bindings" {
    try expectFormatsTo(
        "x: BLOCK { y: 1 z: 2 y + z }",
        "x: BLOCK {\n    y: 1\n    z: 2\n\n    y + z\n}\n",
    );
}

test "format multiline object with multiline field" {
    try expectFormatsTo(
        "x: [a: 1 b: BLOCK { y: 2 y }]",
        "x: [\n    a: 1\n\n    b: BLOCK {\n        y: 2\n        y\n    }\n]\n",
    );
}

test "format preserves standalone comments" {
    try expectFormatsTo(
        "x: 1\n\n-- section\n\ny: 2",
        "x: 1\n\n-- section\n\ny: 2\n",
    );
}

test "format link stays on same line" {
    try expectFormatsTo(
        "x: LINK { foo.bar }",
        "x: LINK { foo.bar }\n",
    );
}
