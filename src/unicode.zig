//! Unicode utilities for display width calculation.

pub const display_width = @import("unicode/display_width.zig");
pub const charWidth = display_width.charWidth;
pub const codepointWidth = display_width.codepointWidth;
pub const strWidth = display_width.strWidth;

test {
    _ = display_width;
}
