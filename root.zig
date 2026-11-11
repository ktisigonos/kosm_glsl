//! GLSL: the `glsl` adapter for shaders, and the settings of ghostty-cursor-shaders' `cursor_warp.glsl`.

const std = @import("std");

/// Edits a shader's top-level values by name.
pub const adapter = @import("adapter.zig").adapter;
/// The settings of `cursor_warp.glsl`; build one with `from`.
pub const App = @import("App.zig");
/// Settings from the theme.
pub const from = App.from;

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(App);
    _ = @import("adapter.zig");
}
