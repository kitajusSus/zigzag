//! Terminal abstraction layer providing cross-platform terminal control.
//! Handles raw mode, alternate screen, mouse tracking, and input/output.

const std = @import("std");
const builtin = @import("builtin");
pub const ansi = @import("ansi.zig");
pub const screen = @import("screen.zig");

// Platform-specific implementation
const platform = if (builtin.os.tag == .windows)
    @import("platform/windows.zig")
else
    @import("platform/posix.zig");

pub const Size = platform.Size;
pub const TerminalError = platform.TerminalError;

/// Terminal configuration options
pub const Config = struct {
    /// Use alternate screen buffer
    alt_screen: bool = true,
    /// Hide cursor during operation
    hide_cursor: bool = true,
    /// Enable mouse tracking
    mouse: bool = false,
    /// Enable bracketed paste mode
    bracketed_paste: bool = true,
    /// Custom input file (default: stdin)
    input: ?std.fs.File = null,
    /// Custom output file (default: stdout)
    output: ?std.fs.File = null,
    /// Enable Kitty keyboard protocol
    kitty_keyboard: bool = false,
};

/// Terminal abstraction
pub const Terminal = struct {
    state: platform.State,
    config: Config,
    stdout: std.fs.File,
    stdin: std.fs.File,
    write_buffer: [4096]u8 = undefined,
    write_pos: usize = 0,

    pub fn init(config: Config) !Terminal {
        const stdout = config.output orelse std.fs.File.stdout();
        const stdin = config.input orelse std.fs.File.stdin();

        var state = platform.State.init();
        // Apply custom fd overrides
        if (builtin.os.tag != .windows) {
            if (config.input) |inp| state.stdin_fd = inp.handle;
            if (config.output) |out| state.stdout_fd = out.handle;
        } else {
            if (config.input) |inp| state.stdin_handle = inp.handle;
            if (config.output) |out| state.stdout_handle = out.handle;
        }

        var term = Terminal{
            .state = state,
            .config = config,
            .stdout = stdout,
            .stdin = stdin,
        };

        try term.setup();
        return term;
    }

    pub fn deinit(self: *Terminal) void {
        self.cleanup();
    }

    pub fn setup(self: *Terminal) !void {
        // Setup signal handlers
        platform.setupSignals() catch {};

        // Enable raw mode
        try platform.enableRawMode(&self.state);

        // Enter alternate screen
        if (self.config.alt_screen) {
            try self.writeBytes(ansi.alt_screen_enter);
            self.state.in_alt_screen = true;
        }

        // Hide cursor
        if (self.config.hide_cursor) {
            try self.writeBytes(ansi.cursor_hide);
        }

        // Enable mouse
        if (self.config.mouse) {
            try self.writeBytes("\x1b[?1003h\x1b[?1006h");
            self.state.mouse_enabled = true;
        }

        // Enable bracketed paste
        if (self.config.bracketed_paste) {
            try self.writeBytes(ansi.bracketed_paste_enable);
        }

        // Enable Kitty keyboard protocol
        if (self.config.kitty_keyboard) {
            try self.writeBytes(ansi.kitty_keyboard_enable);
        }

        // Clear screen
        try self.writeBytes(ansi.screen_clear);
        try self.writeBytes(ansi.cursor_home);

        try self.flush();
    }

    pub fn cleanup(self: *Terminal) void {
        // Disable Kitty keyboard protocol
        if (self.config.kitty_keyboard) {
            self.writeBytes(ansi.kitty_keyboard_disable) catch {};
        }

        // Disable bracketed paste
        if (self.config.bracketed_paste) {
            self.writeBytes(ansi.bracketed_paste_disable) catch {};
        }

        // Disable mouse
        if (self.state.mouse_enabled) {
            self.writeBytes("\x1b[?1006l\x1b[?1003l") catch {};
            self.state.mouse_enabled = false;
        }

        // Show cursor
        if (self.config.hide_cursor) {
            self.writeBytes(ansi.cursor_show) catch {};
        }

        // Exit alternate screen
        if (self.state.in_alt_screen) {
            self.writeBytes(ansi.alt_screen_exit) catch {};
            self.state.in_alt_screen = false;
        }

        // Reset attributes
        self.writeBytes(ansi.reset) catch {};

        self.flush() catch {};

        // Restore terminal mode — always runs even if writes above failed
        platform.disableRawMode(&self.state);
    }

    /// Write bytes to internal buffer
    fn writeBytes(self: *Terminal, bytes: []const u8) !void {
        for (bytes) |byte| {
            if (self.write_pos >= self.write_buffer.len) {
                try self.flush();
            }
            self.write_buffer[self.write_pos] = byte;
            self.write_pos += 1;
        }
    }

    /// Get terminal size
    pub fn getSize(self: *Terminal) !Size {
        return platform.getSize(if (builtin.os.tag == .windows)
            self.state.stdout_handle
        else
            self.state.stdout_fd);
    }

    /// Read input with timeout (in milliseconds)
    pub fn readInput(self: *Terminal, buffer: []u8, timeout_ms: i32) !usize {
        return platform.readInput(&self.state, buffer, timeout_ms);
    }

    /// Check if terminal was resized
    pub fn checkResize(self: *Terminal) bool {
        _ = self;
        return platform.checkResize();
    }

    /// Get a simple writer interface
    pub fn writer(self: *Terminal) Writer {
        return Writer{ .terminal = self };
    }

    /// Flush output buffer
    pub fn flush(self: *Terminal) !void {
        if (self.write_pos > 0) {
            self.stdout.writeAll(self.write_buffer[0..self.write_pos]) catch |err| {
                return switch (err) {
                    error.WouldBlock => error.WouldBlock,
                    else => error.BrokenPipe,
                };
            };
            self.write_pos = 0;
        }
    }

    /// Clear the screen
    pub fn clear(self: *Terminal) !void {
        try self.writeBytes(ansi.screen_clear);
        try self.writeBytes(ansi.cursor_home);
    }

    /// Move cursor to position (0-indexed)
    pub fn moveTo(self: *Terminal, row: u16, col: u16) !void {
        var buf: [32]u8 = undefined;
        const len = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row + 1, col + 1 }) catch return;
        try self.writeBytes(len);
    }

    /// Show the cursor
    pub fn showCursor(self: *Terminal) !void {
        try self.writeBytes(ansi.cursor_show);
    }

    /// Hide the cursor
    pub fn hideCursor(self: *Terminal) !void {
        try self.writeBytes(ansi.cursor_hide);
    }

    /// Enable mouse tracking
    pub fn enableMouse(self: *Terminal) !void {
        try self.writeBytes("\x1b[?1003h\x1b[?1006h");
        self.state.mouse_enabled = true;
    }

    /// Disable mouse tracking
    pub fn disableMouse(self: *Terminal) !void {
        try self.writeBytes("\x1b[?1006l\x1b[?1003l");
        self.state.mouse_enabled = false;
    }

    /// Set window title
    pub fn setTitle(self: *Terminal, title: []const u8) !void {
        try self.writeBytes("\x1b]0;");
        try self.writeBytes(title);
        try self.writeBytes("\x07");
    }

    /// Write a string at position
    pub fn writeAt(self: *Terminal, row: u16, col: u16, str: []const u8) !void {
        try self.moveTo(row, col);
        try self.writeBytes(str);
    }

    /// Check if stdin is a TTY
    pub fn isTty(self: *Terminal) bool {
        _ = self;
        return platform.isTty(if (builtin.os.tag == .windows)
            platform.State.init().stdin_handle
        else
            std.posix.STDIN_FILENO);
    }

    /// Simple writer struct for compatibility
    pub const Writer = struct {
        terminal: *Terminal,

        pub fn writeAll(self: Writer, bytes: []const u8) !void {
            try self.terminal.writeBytes(bytes);
        }

        pub fn print(self: Writer, comptime fmt: []const u8, args: anytype) !void {
            var buf: [256]u8 = undefined;
            const result = std.fmt.bufPrint(&buf, fmt, args) catch return;
            try self.terminal.writeBytes(result);
        }
    };
};
