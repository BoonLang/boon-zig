const bridge = @import("raybox").boon_adapter.host.bridge;
const sources = @import("playground_sources");

const files = [_]bridge.ProjectFile{
    .{ .path = "RUN.bn", .contents = sources.run_bn },
    .{ .path = "BUILD.bn", .contents = sources.build_bn },
    .{ .path = "Generated/Assets.bn", .contents = sources.generated_assets_bn, .generated = true },
    .{ .path = "Theme/Theme.bn", .contents = sources.theme_bn },
    .{ .path = "Theme/Professional.bn", .contents = sources.professional_bn },
    .{ .path = "Theme/Glassmorphism.bn", .contents = sources.glassmorphism_bn },
    .{ .path = "Theme/Neobrutalism.bn", .contents = sources.neobrutalism_bn },
    .{ .path = "Theme/Neumorphism.bn", .contents = sources.neumorphism_bn },
    .{ .path = "assets/icons/checkbox_active.svg", .contents = sources.checkbox_active_svg },
    .{ .path = "assets/icons/checkbox_completed.svg", .contents = sources.checkbox_completed_svg },
};

pub fn project() bridge.Project {
    return .{
        .name = "todo_mvc_physical",
        .entry_file = "RUN.bn",
        .files = @constCast(files[0..]),
    };
}
