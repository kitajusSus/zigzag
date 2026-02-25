//! Runtime context for ZigZag applications.
//! Provides access to terminal state and resources.

const std = @import("std");
const Terminal = @import("../terminal/terminal.zig").Terminal;
const color_mod = @import("../style/color.zig");
const unicode_mod = @import("../unicode.zig");
const Logger = @import("log.zig").Logger;

/// Runtime context passed to init, update, and view functions
pub const Context = struct {
    /// Allocator for temporary allocations (reset each frame)
    allocator: std.mem.Allocator,

    /// Persistent allocator for model state (not reset between frames)
    persistent_allocator: std.mem.Allocator,

    /// Terminal width in columns
    width: u16,

    /// Terminal height in rows
    height: u16,

    /// Current frame number
    frame: u64,

    /// Time since program start (nanoseconds)
    elapsed: u64,

    /// Delta time since last frame (nanoseconds)
    delta: u64,

    /// Whether the terminal supports true color
    true_color: bool,

    /// Whether the terminal supports 256 colors
    color_256: bool,

    /// Color profile of the terminal
    color_profile: color_mod.ColorProfile,

    /// Whether the terminal has a dark background
    is_dark_background: bool,

    /// Active Unicode width strategy for text measurement
    unicode_width_strategy: unicode_mod.WidthStrategy,

    /// Whether DEC mode 2027 was successfully negotiated
    terminal_mode_2027: bool,

    /// Whether kitty text sizing support was detected
    kitty_text_sizing: bool,

    /// Access to internal state (for advanced use)
    _terminal: ?*Terminal,

    /// Logger for debug output
    _logger: ?*Logger = null,

    /// Log a debug message (writes to log file if configured)
    pub fn log(self: *const Context, comptime fmt: []const u8, args: anytype) void {
        if (self._logger) |logger| {
            logger.log(fmt, args);
        }
    }

    pub fn init(allocator: std.mem.Allocator, persistent_allocator: std.mem.Allocator) Context {
        const profile = color_mod.ColorProfile.detect();
        return .{
            .allocator = allocator,
            .persistent_allocator = persistent_allocator,
            .width = 80,
            .height = 24,
            .frame = 0,
            .elapsed = 0,
            .delta = 0,
            .true_color = profile.supportsTrueColor(),
            .color_256 = profile.supports256(),
            .color_profile = profile,
            .is_dark_background = color_mod.hasDarkBackground(),
            .unicode_width_strategy = unicode_mod.getWidthStrategy(),
            .terminal_mode_2027 = false,
            .kitty_text_sizing = false,
            ._terminal = null,
        };
    }

    /// Get the aspect ratio (width / height)
    pub fn aspectRatio(self: *const Context) f32 {
        if (self.height == 0) return 1.0;
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }

    /// Get center coordinates
    pub fn center(self: *const Context) struct { x: u16, y: u16 } {
        return .{
            .x = self.width / 2,
            .y = self.height / 2,
        };
    }

    /// Check if a position is within bounds
    pub fn inBounds(self: *const Context, x: u16, y: u16) bool {
        return x < self.width and y < self.height;
    }

    /// Get elapsed time in seconds (floating point)
    pub fn elapsedSec(self: *const Context) f64 {
        return @as(f64, @floatFromInt(self.elapsed)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    }

    /// Get delta time in seconds (floating point)
    pub fn deltaSec(self: *const Context) f64 {
        return @as(f64, @floatFromInt(self.delta)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    }

    /// Get frames per second (based on delta)
    pub fn fps(self: *const Context) f64 {
        if (self.delta == 0) return 0.0;
        return @as(f64, @floatFromInt(std.time.ns_per_s)) / @as(f64, @floatFromInt(self.delta));
    }

    /// Clamp a value to screen bounds
    pub fn clampX(self: *const Context, x: i32) u16 {
        if (x < 0) return 0;
        if (x >= self.width) return self.width -| 1;
        return @intCast(x);
    }

    pub fn clampY(self: *const Context, y: i32) u16 {
        if (y < 0) return 0;
        if (y >= self.height) return self.height -| 1;
        return @intCast(y);
    }

    /// Returns whether Kitty graphics protocol is available.
    pub fn supportsKittyGraphics(self: *const Context) bool {
        if (self._terminal) |term| {
            return term.supportsKittyGraphics();
        }
        return false;
    }

    /// Draw a PNG image file via Kitty graphics protocol (`t=f`).
    /// Returns false when unsupported or path is empty.
    pub fn drawKittyImageFromFile(self: *Context, path: []const u8, options: Terminal.KittyImageFileOptions) !bool {
        if (self._terminal) |term| {
            return term.drawKittyImageFromFile(path, options);
        }
        return false;
    }
};

/// Options that can be modified during runtime
pub const Options = struct {
    /// Target frame rate (frames per second)
    fps: u32 = 60,

    /// Enable mouse tracking
    mouse: bool = false,

    /// Show cursor
    cursor: bool = false,

    /// Use alternate screen buffer
    alt_screen: bool = true,

    /// Enable bracketed paste mode
    bracketed_paste: bool = true,

    /// Window title
    title: ?[]const u8 = null,

    /// Custom input file (default: stdin)
    input: ?std.fs.File = null,

    /// Custom output file (default: stdout)
    output: ?std.fs.File = null,

    /// Log file path for debug output
    log_file: ?[]const u8 = null,

    /// Enable Kitty keyboard protocol
    kitty_keyboard: bool = false,

    /// Force Unicode width strategy (`null` = auto-detect)
    unicode_width_strategy: ?unicode_mod.WidthStrategy = null,

    /// Enable suspend/resume with Ctrl+Z
    suspend_enabled: bool = true,
};
