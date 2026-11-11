# kosm_glsl

GLSL shaders for kosm: the `glsl` adapter, and the settings of ghostty-cursor-shaders'
`cursor_warp.glsl`.

## The adapter

`glsl` edits `.glsl`, `.frag` and `.vert` files in place; it never writes a whole shader. A
top-level declaration with a value is a path named after its variable: `const float DURATION =
0.2;` holds `DURATION`, `vec4 TRAIL_COLOR = vec4(...);` holds `TRAIL_COLOR`. Declarations inside
functions are invisible. Floats always keep a `.`, and colors are `vec4(r, g, b, a)` with sRGB
channels 0..1. A shader with a syntax error is refused.

## The app

The app sets the configuration block at the top of `cursor_warp.glsl`; every other line stays as
it is. Ghostty runs the shader through `custom-shader = <path>`, which stays yours to set.
`from(theme)` sets nothing: the shipped trail already takes ghostty's cursor color. With nothing
set, the shader is not read.

Colors are written as `vec4(sRGBToLinear(vec3(r, g, b)), a)`, since the shader blends in linear
light; set `format.color` for another spelling.

## Fields

| Field | Default |
|---|---|
| `file` | `~/.config/ghostty/shaders/cursor_warp.glsl` |
| `format` | `.{}`: colors in linear light as above, then the adapter's |
| `trail_color` | null: as shipped, ghostty's cursor color |
| `duration` | null: as shipped, 0.2 seconds |
| `trail_size` | null: as shipped, 0.8 (0 moves every corner together, 1 smears the most) |
| `threshold_min_distance` | null: as shipped, 0 cursor heights |
| `blur` | null: as shipped, 1 pixel |
| `trail_thickness` | null: as shipped, 1 (the cursor's full height) |
| `trail_thickness_x` | null: as shipped, 0.9 |
| `fade_enabled` | null: as shipped, off |
| `fade_exponent` | null: as shipped, 5 |
| `extra` | none: other top-level values by name, `.{ .path = "SPRING_STIFFNESS", .value = .{ .float = 12 } }` |
