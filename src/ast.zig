const std = @import("std");

pub const Span = struct {
    start: usize,
    end: usize,

    pub fn init(start: usize, end: usize) Span {
        return .{ .start = start, .end = end };
    }
};

pub const Delimiter = enum {
    root,
    parentheses,
    brackets,
    braces,
};

pub const TokenKind = enum {
    snake_identifier,
    pascal_identifier,
    keyword,
    wildcard,
    numeric_literal,
    atom,
    l_paren,
    r_paren,
    l_bracket,
    r_bracket,
    l_brace,
    r_brace,
    comma,
    colon,
    dot,
    question,
    spread,
    pipe_forward,
    fat_arrow,
    single_equals,
    eq,
    neq,
    gt,
    gte,
    lt,
    lte,
    plus,
    minus,
    star,
    slash,
    percent,
    caret,
};

pub const Token = struct {
    kind: TokenKind,
    span: Span,
};

pub const BinaryOp = enum {
    bind,
    pipe_forward,
    arm_arrow,
    equal,
    not_equal,
    greater,
    greater_equal,
    less,
    less_equal,
    add,
    subtract,
    multiply,
    divide,
    modulo,
    power,
};

pub const UnaryOp = enum {
    negate,
    spread,
};

pub const AccessKind = enum {
    direct,
    optional,
};

pub const ApplyKind = enum {
    call,
    keyword_form,
    tagged_value,
};

pub const Expr = union(enum) {
    token: Token,
    group: *Group,
    path: *Path,
    apply: *Apply,
    access: *Access,
    unary: *Unary,
    binary: *Binary,
};

pub const Group = struct {
    delimiter: Delimiter,
    span: Span,
    items: []Expr,
};

pub const Path = struct {
    segments: []Token,
    span: Span,
};

pub const Apply = struct {
    kind: ApplyKind,
    head: Expr,
    arguments: []Expr,
    span: Span,
};

pub const Access = struct {
    kind: AccessKind,
    target: Expr,
    field: Token,
    span: Span,
};

pub const Unary = struct {
    operator: UnaryOp,
    operator_span: Span,
    operand: Expr,
    span: Span,
};

pub const Binary = struct {
    operator: BinaryOp,
    lhs: Expr,
    rhs: Expr,
    operator_span: Span,
    span: Span,
};

pub fn exprSpan(expr: Expr) Span {
    return switch (expr) {
        .token => |token| token.span,
        .group => |group| group.span,
        .path => |path| path.span,
        .apply => |apply| apply.span,
        .access => |access| access.span,
        .unary => |unary| unary.span,
        .binary => |binary| binary.span,
    };
}

pub fn exprTailToken(expr: Expr) ?Token {
    return switch (expr) {
        .token => |token| token,
        .path => |path| if (path.segments.len == 0) null else path.segments[path.segments.len - 1],
        .apply => |apply| exprTailToken(apply.head),
        .access => |access| access.field,
        .group, .unary, .binary => null,
    };
}

pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    root: Group,
    token_count: usize,
    group_count: usize,
    form_count: usize,
    source_len: usize,

    pub fn deinit(self: *Document) void {
        self.arena.deinit();
    }
};
