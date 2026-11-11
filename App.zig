//! ghostty-cursor-shaders' `cursor_warp.glsl`: the settings at the top of the shader, set in
//! place; every other line stays as it is. Ghostty runs it through its `custom-shader` setting.

const App = @This();

const std = @import("std");
const kosm = @import("kosm");

/// The shader to edit; each set value's declaration must be in it already.
/// Default: `~/.config/ghostty/shaders/cursor_warp.glsl`.
file: []const u8 = "~/.config/ghostty/shaders/cursor_warp.glsl",
/// How values are spelled. Null fields take the app's: colors as
/// `vec4(sRGBToLinear(vec3(r, g, b)), a)`, since the shader blends in linear light; then the
/// adapter's.
format: kosm.Format = .{},
/// The trail's color and alpha. null: as shipped, ghostty's cursor color.
trail_color: ?kosm.Color = null,
/// Seconds the animation takes. null: as shipped, 0.2.
duration: ?f64 = null,
/// How far the trailing corners lag: 0 moves every corner together, 1 smears the most.
/// null: as shipped, 0.8.
trail_size: ?f64 = null,
/// The shortest jump that shows a trail, in cursor heights. null: as shipped, 0.
threshold_min_distance: ?f64 = null,
/// Antialiasing blur in pixels. null: as shipped, 1.
blur: ?f64 = null,
/// The trail's height relative to the cursor's: 1 is the full height. null: as shipped, 1.
trail_thickness: ?f64 = null,
/// The trail's width relative to the cursor's. null: as shipped, 0.9.
trail_thickness_x: ?f64 = null,
/// Whether the trail fades along its length. null: as shipped, off.
fade_enabled: ?bool = null,
/// How fast the fade falls off; higher fades sooner. null: as shipped, 5.
fade_exponent: ?f64 = null,
/// Values the app doesn't cover, by the variable's name:
/// `.{ .path = "SPRING_STIFFNESS", .value = .{ .float = 12 } }`. The shader must declare it at
/// the top level already. Default: none.
extra: []const kosm.Setting = &.{},

/// How the app spells colors: the shader works in linear light and converts with its own
/// `sRGBToLinear`.
const linear_color: kosm.ColorFormat = .init("vec4(sRGBToLinear(vec3({}, {}, {})), {})", &.{ .red_01, .green_01, .blue_01, .alpha_01 });

/// Nothing from the theme: the shipped trail already takes ghostty's cursor color, which
/// follows the theme. Set `trail_color` for another.
pub fn from(theme: kosm.Theme) App {
    _ = theme;
    return .{};
}

/// Sets every set value, then the extras, in `file`. With nothing set, the file is not read.
pub fn apply(self: App, output: *kosm.Output) !void {
    var settings: std.ArrayList(kosm.Setting) = .empty;
    inline for (.{ "duration", "trail_size", "threshold_min_distance", "blur", "trail_thickness", "trail_thickness_x", "fade_exponent" }) |name| {
        if (@field(self, name)) |value| try settings.append(output.allocator, .{ .path = comptime upperCase(name), .value = .{ .float = value } });
    }
    if (self.trail_color) |color| try settings.append(output.allocator, .{ .path = "TRAIL_COLOR", .value = .{ .color = color } });
    if (self.fade_enabled) |enabled| try settings.append(output.allocator, .{ .path = "FADE_ENABLED", .value = .{ .float = if (enabled) 1 else 0 } });
    try settings.appendSlice(output.allocator, self.extra);
    if (settings.items.len == 0) return;

    var selection = try output.edit(.{ .files = self.file, .lang = "glsl", .format = self.format.orElse(.{ .color = linear_color }) });
    for (settings.items) |setting| try selection.set(setting.path, setting.value);
}

/// The shader's name for a field: `trail_size` is `TRAIL_SIZE`.
fn upperCase(comptime name: []const u8) []const u8 {
    comptime var upper: [name.len]u8 = undefined;
    inline for (name, 0..) |character, index| upper[index] = std.ascii.toUpper(character);
    const result = upper;
    return &result;
}

const testing = std.testing;
const adapter = @import("adapter.zig").adapter;

/// The configuration block of `cursor_warp.glsl` as shipped.
const shipped =
    \\vec3 sRGBToLinear(vec3 c) {
    \\    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
    \\}
    \\
    \\// --- CONFIGURATION ---
    \\vec4 TRAIL_COLOR = vec4(sRGBToLinear(iCurrentCursorColor.rgb), iCurrentCursorColor.a); // for custom color
    \\const float DURATION = 0.2; // total animation time
    \\const float TRAIL_SIZE = 0.8;
    \\const float THRESHOLD_MIN_DISTANCE = 0;
    \\const float BLUR = 1.0;
    \\const float TRAIL_THICKNESS = 1.0;
    \\const float TRAIL_THICKNESS_X = 0.9;
    \\
    \\const float FADE_ENABLED = 0.0; // 1.0 to enable fade gradient along the trail, 0.0 to disable
    \\const float FADE_EXPONENT = 5.0;
    \\const float SPRING_STIFFNESS = 9.0;
    \\
;

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings = undefined,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output = undefined,

    const directory = ".config/ghostty/shaders";

    fn init(fixture: *Fixture) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        try fixture.tmp.dir.createDirPath(testing.io, directory);
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = directory ++ "/cursor_warp.glsl", .data = shipped });
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "cursor_warp",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }
};

test "the trail color is written in linear light and nothing else changes" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const app: App = .{ .trail_color = kosm.hex("33669980") };
    try app.apply(&fixture.output);
    const expected = try replace(&fixture, shipped, "vec4(sRGBToLinear(iCurrentCursorColor.rgb), iCurrentCursorColor.a)", "vec4(sRGBToLinear(vec3(0.2, 0.4, 0.6)), 0.501961)");
    try testing.expectEqualStrings(expected, fixture.plan.files.items[0].new);
}

test "numbers, the fade switch and extras are written as floats" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const app: App = .{
        .duration = 0.3,
        .threshold_min_distance = 1,
        .fade_enabled = true,
        .extra = &.{.{ .path = "SPRING_STIFFNESS", .value = .{ .float = 12 } }},
    };
    try app.apply(&fixture.output);
    var expected: []const u8 = shipped;
    inline for (.{
        .{ "DURATION = 0.2", "DURATION = 0.3" },
        .{ "DISTANCE = 0;", "DISTANCE = 1.0;" },
        .{ "FADE_ENABLED = 0.0", "FADE_ENABLED = 1.0" },
        .{ "STIFFNESS = 9.0", "STIFFNESS = 12.0" },
    }) |change| expected = try replace(&fixture, expected, change[0], change[1]);
    try testing.expectEqualStrings(expected, fixture.plan.files.items[0].new);
}

test "a value the shader does not declare fails naming it" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const app: App = .{ .extra = &.{.{ .path = "GLOW", .value = .{ .float = 1 } }} };
    try testing.expectError(error.NoMatch, app.apply(&fixture.output));
    try testing.expect(std.mem.indexOf(u8, fixture.diagnostics.message(), "GLOW") != null);
}

test "an app with nothing set does not need the shader" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const app: App = .{ .file = "~/missing.glsl" };
    try app.apply(&fixture.output);
    try testing.expectEqual(0, fixture.plan.files.items.len);
}

/// `text` with its one `needle` replaced.
fn replace(fixture: *Fixture, text: []const u8, needle: []const u8, replacement: []const u8) ![]const u8 {
    try testing.expectEqual(1, std.mem.count(u8, text, needle));
    return std.mem.replaceOwned(u8, fixture.arena.allocator(), text, needle, replacement);
}
