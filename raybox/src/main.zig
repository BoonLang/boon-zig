const std = @import("std");
const builtin = @import("builtin");
const app_mod = @import("app/app.zig");
const playground_layout = @import("playground_layout");
const sdl = @import("sdl");

const c = sdl.c;

var app: app_mod.PlaygroundApp = .{};
var window: ?*c.SDL_Window = null;
var renderer: ?*c.SDL_Renderer = null;
var exit_after_frames: u32 = 0;
var frame_counter: u32 = 0;
var native_smoke_script: ?[]const u8 = null;
var running = true;

const playground_title = "Boon Zig Playground";

pub fn main(process_init: std.process.Init) !void {
    const is_web = builtin.os.tag == .emscripten;
    configureRun(process_init);
    configureSdlVideoDriver(process_init);
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return sdlError("SDL_Init");
    errdefer c.SDL_Quit();

    const flags: c.SDL_WindowFlags = c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE;
    window = c.SDL_CreateWindow(playground_title, playground_layout.window_width, playground_layout.window_height, flags) orelse return sdlError("SDL_CreateWindow");
    errdefer if (window) |w| c.SDL_DestroyWindow(w);

    renderer = c.SDL_CreateRenderer(window.?, null) orelse return sdlError("SDL_CreateRenderer");
    errdefer if (renderer) |r| c.SDL_DestroyRenderer(r);
    _ = c.SDL_SetRenderVSync(renderer.?, 1);
    _ = c.SDL_SetRenderDrawBlendMode(renderer.?, c.SDL_BLENDMODE_BLEND_PREMULTIPLIED);

    logSdlBackend();
    app.init(window.?, renderer.?);
    if (native_smoke_script) |script| {
        try app.runNativeSmokeScript(script);
    }

    if (is_web) {
        emscripten_set_main_loop_arg(emscriptenFrame, null, 60, 1);
        return;
    }
    defer c.SDL_Quit();
    defer c.SDL_DestroyWindow(window.?);
    defer c.SDL_DestroyRenderer(renderer.?);
    defer app.deinit();

    while (running) {
        pumpEvents();
        frame();
    }
}

fn configureSdlVideoDriver(process_init: std.process.Init) void {
    if (builtin.os.tag != .linux) return;
    if (std.process.Environ.getPosix(process_init.minimal.environ, "SDL_VIDEO_DRIVER") != null) return;
    if (std.process.Environ.getPosix(process_init.minimal.environ, "SDL_VIDEODRIVER") != null) return;

    const session_type = std.process.Environ.getPosix(process_init.minimal.environ, "XDG_SESSION_TYPE") orelse "";
    const wayland_display = std.process.Environ.getPosix(process_init.minimal.environ, "WAYLAND_DISPLAY") orelse "";
    if (std.mem.eql(u8, session_type, "wayland") or wayland_display.len != 0) {
        _ = c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "wayland,x11");
    }
}

fn frame() void {
    app.frame();
    if (exit_after_frames != 0) {
        frame_counter +|= 1;
        if (frame_counter >= exit_after_frames) running = false;
    }
}

fn pumpEvents() void {
    var ev: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&ev)) {
        switch (ev.type) {
            c.SDL_EVENT_QUIT => running = false,
            else => app.event(&ev),
        }
    }
}

fn emscriptenFrame(_: ?*anyopaque) callconv(.c) void {
    pumpEvents();
    frame();
}

fn logSdlBackend() void {
    const video_driver = c.SDL_GetCurrentVideoDriver();
    const renderer_name = if (renderer) |r| c.SDL_GetRendererName(r) else null;
    std.log.info("SDL video={s} renderer={s}", .{
        if (video_driver) |name| std.mem.span(name) else "unknown",
        if (renderer_name) |name| std.mem.span(name) else "unknown",
    });
}

fn sdlError(comptime operation: []const u8) error{SdlFailed} {
    const err = c.SDL_GetError();
    std.log.err("{s} failed: {s}", .{ operation, if (err) |msg| std.mem.span(msg) else "unknown SDL error" });
    return error.SdlFailed;
}

fn configureRun(process_init: std.process.Init) void {
    var args = std.process.Args.Iterator.init(process_init.minimal.args);
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--interactive")) {
            exit_after_frames = 0;
            continue;
        }
        const prefix = "--exit-after-frames=";
        if (std.mem.startsWith(u8, arg, prefix)) {
            exit_after_frames = std.fmt.parseUnsigned(u32, arg[prefix.len..], 10) catch 0;
            continue;
        }
        const example_prefix = "--example=";
        if (std.mem.startsWith(u8, arg, example_prefix)) {
            if (!app.setInitialExample(arg[example_prefix.len..])) {
                std.log.err("unknown playground example: {s}", .{arg[example_prefix.len..]});
                std.log.err("run with one of the pinned registry example names from src/playground/generated_example_registry.zig", .{});
            }
            continue;
        }
        const capture_prefix = "--capture-frame=";
        if (std.mem.startsWith(u8, arg, capture_prefix)) {
            app.setCapturePath(arg[capture_prefix.len..]);
            continue;
        }
        const capture_size_prefix = "--capture-size=";
        if (std.mem.startsWith(u8, arg, capture_size_prefix)) {
            parseCaptureSize(arg[capture_size_prefix.len..]) catch |err| {
                std.log.err("invalid capture size {s}: {s}", .{ arg[capture_size_prefix.len..], @errorName(err) });
            };
            continue;
        }
        const native_smoke_prefix = "--native-smoke=";
        if (std.mem.startsWith(u8, arg, native_smoke_prefix)) {
            native_smoke_script = arg[native_smoke_prefix.len..];
            continue;
        }
    }
}

fn parseCaptureSize(text: []const u8) !void {
    const separator = std.mem.indexOfScalar(u8, text, 'x') orelse return error.InvalidCaptureSize;
    const width = try std.fmt.parseInt(i32, text[0..separator], 10);
    const height = try std.fmt.parseInt(i32, text[separator + 1 ..], 10);
    if (width <= 0 or height <= 0) return error.InvalidCaptureSize;
    app.setCaptureSize(width, height);
}

extern fn emscripten_set_main_loop_arg(
    func: *const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,
    fps: c_int,
    simulate_infinite_loop: c_int,
) void;
