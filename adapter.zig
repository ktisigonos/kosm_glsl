//! GLSL: values of a shader's top-level declarations, set by name. Floats always keep a `.`,
//! since GLSL reads `1` as an integer; colors are `vec4(r, g, b, a)` with sRGB channels 0..1.

const std = @import("std");
const kosm = @import("kosm");

extern fn tree_sitter_glsl() callconv(.c) *const kosm.treesitter.Language;

/// Edits shaders through `output.edit`. A top-level declaration with a value is a path named
/// after its variable: `const float DURATION = 0.2;` and `vec4 TRAIL_COLOR = vec4(...);` hold
/// `DURATION` and `TRAIL_COLOR`. Declarations inside functions are invisible. Edits only:
/// kosm never writes a whole shader.
pub const adapter: kosm.Adapter = .{
    .name = "glsl",
    .extensions = &.{ ".glsl", ".frag", ".vert" },
    .default_format = .{
        .color = .init("vec4({}, {}, {}, {})", &.{ .red_01, .green_01, .blue_01, .alpha_01 }),
        .boolean = .true_false,
    },
    .comment = .{ .line = "//" },
    .format = format,
    .parser = kosm.treesitter.parser(tree_sitter_glsl, .{
        .pair = "init_declarator",
        .key = "declarator",
        .value = "value",
        .nest = &.{"translation_unit"},
        .transparent = &.{"declaration"},
    }),
};

/// Longest float `format` prints; kosm caps a float's magnitude and decimals well below it.
const max_float_length = 64;

/// One value as GLSL spells it. GLSL has no strings, lists or tables.
fn format(writer: *std.Io.Writer, value: kosm.Value, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    switch (value) {
        .raw => |text| try writer.writeAll(text),
        .joined => |parts| for (parts) |part| try format(writer, part, context),
        .integer => |integer| try writer.print("{d}", .{integer}),
        .float => |float| try writeFloat(writer, float, context),
        .boolean => |boolean| {
            if (context.format.boolean != .true_false)
                return context.unsupported("GLSL spells booleans only as true and false; leave format.boolean at .true_false", .{});
            try context.writeBoolean(writer, boolean);
        },
        .color => |color| try context.writeColor(writer, color),
        .string => return context.unsupported("GLSL has no strings; write the expression as a raw value", .{}),
        .list, .table => return context.unsupported("GLSL values here are single expressions, not lists or tables; write a raw value", .{}),
    }
}

/// `value` at the file's precision, with `.0` added when it would print as an integer.
fn writeFloat(writer: *std.Io.Writer, value: f64, context: *kosm.Adapter.Context) kosm.Adapter.Error!void {
    if (!std.math.isFinite(value)) return context.unsupported("GLSL has no infinity or NaN literal", .{});
    var buffer: [max_float_length]u8 = undefined;
    var float_writer: std.Io.Writer = .fixed(&buffer);
    context.writeFloat(&float_writer, value) catch return context.unsupported("the float prints more than {d} bytes", .{buffer.len});
    const text = float_writer.buffered();
    try writer.writeAll(text);
    if (std.mem.indexOfAny(u8, text, ".e") == null) try writer.writeAll(".0");
}

const testing = std.testing;

const Fixture = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    plan: kosm.Plan,
    diagnostics: kosm.Diagnostics = .{},
    warnings: kosm.Warnings = undefined,
    home_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined,
    output: kosm.Output = undefined,

    fn init(fixture: *Fixture, source: []const u8) !void {
        fixture.* = .{ .tmp = testing.tmpDir(.{}), .arena = .init(testing.allocator), .plan = .init(testing.allocator, testing.io) };
        try fixture.tmp.dir.writeFile(testing.io, .{ .sub_path = "shader.glsl", .data = source });
        fixture.warnings = .init(fixture.arena.allocator());
        const length = try fixture.tmp.dir.realPath(testing.io, &fixture.home_buffer);
        fixture.output = .{
            .allocator = fixture.arena.allocator(),
            .home = fixture.home_buffer[0..length],
            .adapters = &.{adapter},
            .plan = &fixture.plan,
            .diagnostics = &fixture.diagnostics,
            .warnings = &fixture.warnings,
            .app = "shader",
        };
    }

    fn deinit(fixture: *Fixture) void {
        fixture.plan.deinit();
        fixture.arena.deinit();
        fixture.tmp.cleanup();
    }

    fn edit(fixture: *Fixture) !kosm.Output.Selection {
        return fixture.output.edit(.{ .files = "~/shader.glsl" });
    }

    fn planned(fixture: *Fixture) []const u8 {
        return fixture.plan.files.items[0].new;
    }
};

/// The top of ghostty-cursor-shaders' `cursor_warp.glsl`, cut short.
const cursor_warp =
    \\// sRGB -> Linear conversion
    \\vec3 sRGBToLinear(vec3 c) {
    \\    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
    \\}
    \\
    \\// --- CONFIGURATION ---
    \\vec4 TRAIL_COLOR = vec4(sRGBToLinear(iCurrentCursorColor.rgb), iCurrentCursorColor.a); // for custom color: vec4(0.2, 0.6, 1.0, 0.5);
    \\const float DURATION = 0.2; // total animation time
    \\const float THRESHOLD_MIN_DISTANCE = 0; // min distance to show trail
    \\const float TRAIL_THICKNESS = 1.0;  // 1.0 = full cursor height
    \\
    \\void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    \\    float DURATION = 1.0;
    \\    fragColor = TRAIL_COLOR * DURATION;
    \\}
    \\
;

test "only the set values' bytes change, comments and spacing stay" {
    var fixture: Fixture = undefined;
    try fixture.init(cursor_warp);
    defer fixture.deinit();
    var selection = try fixture.edit();
    try selection.set("TRAIL_COLOR", kosm.Value{ .color = kosm.hex("336699") });
    try selection.set("THRESHOLD_MIN_DISTANCE", kosm.Value{ .float = 2 });
    try selection.set("TRAIL_THICKNESS", kosm.Value{ .float = 0.75 });
    const expected =
        \\// sRGB -> Linear conversion
        \\vec3 sRGBToLinear(vec3 c) {
        \\    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
        \\}
        \\
        \\// --- CONFIGURATION ---
        \\vec4 TRAIL_COLOR = vec4(0.2, 0.4, 0.6, 1); // for custom color: vec4(0.2, 0.6, 1.0, 0.5);
        \\const float DURATION = 0.2; // total animation time
        \\const float THRESHOLD_MIN_DISTANCE = 2.0; // min distance to show trail
        \\const float TRAIL_THICKNESS = 0.75;  // 1.0 = full cursor height
        \\
        \\void mainImage(out vec4 fragColor, in vec2 fragCoord) {
        \\    float DURATION = 1.0;
        \\    fragColor = TRAIL_COLOR * DURATION;
        \\}
        \\
    ;
    try testing.expectEqualStrings(expected, fixture.planned());
}

test "a declaration inside a function is not a path" {
    var fixture: Fixture = undefined;
    try fixture.init("void main() {\n    const float BLUR = 1.0;\n}\n");
    defer fixture.deinit();
    var selection = try fixture.edit();
    try testing.expectError(error.NoMatch, selection.set("BLUR", kosm.Value{ .float = 2 }));
    try testing.expect(std.mem.indexOf(u8, fixture.diagnostics.message(), "BLUR") != null);
}

test "every variable of a declaration with several is its own path" {
    var fixture: Fixture = undefined;
    try fixture.init("const float A = 1.0, B = 2.0;\n");
    defer fixture.deinit();
    var selection = try fixture.edit();
    try selection.set("B", kosm.Value{ .integer = 3 });
    try testing.expectEqualStrings("const float A = 1.0, B = 3;\n", fixture.planned());
}

test "a shader that does not parse is refused naming the line" {
    var fixture: Fixture = undefined;
    try fixture.init("const float A = 1.0;\nconst float = ;\n");
    defer fixture.deinit();
    try testing.expectError(error.InvalidSyntax, fixture.edit());
    try testing.expect(std.mem.indexOf(u8, fixture.diagnostics.message(), "line 2") != null);
}

test "values GLSL cannot spell fail with a reason" {
    var fixture: Fixture = undefined;
    try fixture.init("const float A = 1.0;\n");
    defer fixture.deinit();
    var selection = try fixture.edit();
    try testing.expectError(error.UnsupportedValue, selection.set("A", kosm.Value{ .string = "x" }));
    try testing.expectError(error.UnsupportedValue, selection.set("A", kosm.Value{ .float = std.math.inf(f64) }));
}
