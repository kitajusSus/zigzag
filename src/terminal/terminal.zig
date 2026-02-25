//! Terminal abstraction layer providing cross-platform terminal control.
//! Handles raw mode, alternate screen, mouse tracking, and input/output.

const std = @import("std");
const builtin = @import("builtin");
pub const ansi = @import("ansi.zig");
pub const screen = @import("screen.zig");
const unicode = @import("../unicode.zig");

// Platform-specific implementation
const platform = if (builtin.os.tag == .windows)
    @import("platform/windows.zig")
else
    @import("platform/posix.zig");

pub const Size = platform.Size;
pub const TerminalError = platform.TerminalError;

pub const UnicodeWidthCapabilities = struct {
    mode_2027: bool = false,
    kitty_text_sizing: bool = false,
    strategy: unicode.WidthStrategy = .legacy_wcwidth,
};

pub const ImageCapabilities = struct {
    kitty_graphics: bool = false,
};

pub const KittyImageFormat = enum(u16) {
    rgb = 24,
    rgba = 32,
    png = 100,
};

pub const KittyImageOptions = struct {
    format: KittyImageFormat = .png,
    width_cells: ?u16 = null,
    height_cells: ?u16 = null,
    image_id: ?u32 = null,
    placement_id: ?u32 = null,
    move_cursor: bool = true,
    quiet: bool = true,
};

pub const KittyImageFileOptions = struct {
    width_cells: ?u16 = null,
    height_cells: ?u16 = null,
    image_id: ?u32 = null,
    placement_id: ?u32 = null,
    move_cursor: bool = true,
    quiet: bool = true,
};

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
    unicode_width_caps: UnicodeWidthCapabilities = .{},
    image_caps: ImageCapabilities = .{},

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

        self.detectUnicodeWidthCapabilities();
        self.detectImageCapabilities();

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

        if (self.unicode_width_caps.mode_2027) {
            self.writeBytes(ansi.unicode_width_mode_disable) catch {};
            self.unicode_width_caps.mode_2027 = false;
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

    pub fn getUnicodeWidthCapabilities(self: *const Terminal) UnicodeWidthCapabilities {
        return self.unicode_width_caps;
    }

    pub fn getImageCapabilities(self: *const Terminal) ImageCapabilities {
        return self.image_caps;
    }

    pub fn supportsKittyGraphics(self: *const Terminal) bool {
        return self.image_caps.kitty_graphics;
    }

    /// Draw image bytes using Kitty graphics protocol (`t=d`).
    /// Returns `false` when unsupported or no data is provided.
    pub fn drawKittyImage(self: *Terminal, image_data: []const u8, options: KittyImageOptions) !bool {
        if (!self.image_caps.kitty_graphics or image_data.len == 0) return false;

        var params_buf: [160]u8 = undefined;
        var stream = std.io.fixedBufferStream(&params_buf);
        const params_writer = stream.writer();

        try params_writer.print("a=T,t=d,f={d}", .{@intFromEnum(options.format)});
        if (options.quiet) try params_writer.writeAll(",q=2");
        if (options.width_cells) |cols| try params_writer.print(",c={d}", .{cols});
        if (options.height_cells) |rows| try params_writer.print(",r={d}", .{rows});
        if (options.image_id) |id| try params_writer.print(",i={d}", .{id});
        if (options.placement_id) |id| try params_writer.print(",p={d}", .{id});
        if (!options.move_cursor) try params_writer.writeAll(",C=1");

        try self.sendKittyGraphicsPayload(stream.getWritten(), image_data);
        return true;
    }

    /// Draw a PNG image by file path using Kitty graphics protocol (`t=f`).
    /// Returns `false` when unsupported or path is empty.
    pub fn drawKittyImageFromFile(self: *Terminal, path: []const u8, options: KittyImageFileOptions) !bool {
        if (!self.image_caps.kitty_graphics or path.len == 0) return false;

        var params_buf: [160]u8 = undefined;
        var stream = std.io.fixedBufferStream(&params_buf);
        const params_writer = stream.writer();

        try params_writer.writeAll("a=T,t=f,f=100");
        if (options.quiet) try params_writer.writeAll(",q=2");
        if (options.width_cells) |cols| try params_writer.print(",c={d}", .{cols});
        if (options.height_cells) |rows| try params_writer.print(",r={d}", .{rows});
        if (options.image_id) |id| try params_writer.print(",i={d}", .{id});
        if (options.placement_id) |id| try params_writer.print(",p={d}", .{id});
        if (!options.move_cursor) try params_writer.writeAll(",C=1");

        try self.sendKittyGraphicsPayload(stream.getWritten(), path);
        return true;
    }

    fn detectUnicodeWidthCapabilities(self: *Terminal) void {
        self.unicode_width_caps = .{
            .kitty_text_sizing = self.queryKittyTextSizingSupport() catch false,
        };

        if (!self.isTty()) {
            return;
        }

        if (builtin.os.tag != .windows) {
            self.unicode_width_caps.mode_2027 = self.queryMode2027Support() catch false;
            if (self.unicode_width_caps.mode_2027) {
                self.writeBytes(ansi.unicode_width_mode_enable) catch {};
            }
        }

        self.unicode_width_caps.strategy = self.selectWidthStrategy();
    }

    fn detectImageCapabilities(self: *Terminal) void {
        self.image_caps = .{
            .kitty_graphics = self.isTty() and looksLikeKittyTerminal(),
        };
    }

    fn sendKittyGraphicsPayload(self: *Terminal, first_params: []const u8, payload: []const u8) !void {
        const encoder = std.base64.standard.Encoder;
        var b64_buf: [4096]u8 = undefined;
        const raw_chunk_max: usize = (b64_buf.len / 4) * 3;

        var src_index: usize = 0;
        var first = true;

        while (true) {
            const remaining = payload.len - src_index;
            const take = @min(remaining, raw_chunk_max);
            const chunk = payload[src_index .. src_index + take];

            const encoded_len = encoder.calcSize(chunk.len);
            const encoded = encoder.encode(b64_buf[0..encoded_len], chunk);
            const has_more = src_index + take < payload.len;

            if (first) {
                var first_chunk_params: [192]u8 = undefined;
                const params = try std.fmt.bufPrint(
                    &first_chunk_params,
                    "{s},m={d}",
                    .{ first_params, if (has_more) @as(u8, 1) else @as(u8, 0) },
                );
                try ansi.kittyGraphics(self.writer(), params, encoded);
                first = false;
            } else {
                const params = if (has_more) "m=1" else "m=0";
                try ansi.kittyGraphics(self.writer(), params, encoded);
            }

            if (!has_more) break;
            src_index += take;
        }
    }

    fn queryMode2027Support(self: *Terminal) !bool {
        try self.writeBytes(ansi.unicode_width_mode_query);
        try self.flush();

        var collected: [512]u8 = undefined;
        var collected_len: usize = 0;
        const deadline_ms = std.time.milliTimestamp() + 250;

        while (std.time.milliTimestamp() < deadline_ms) {
            var chunk: [128]u8 = undefined;
            const n = self.readInput(&chunk, 40) catch 0;
            if (n == 0) continue;

            const copy_len = @min(n, collected.len - collected_len);
            if (copy_len > 0) {
                @memcpy(collected[collected_len .. collected_len + copy_len], chunk[0..copy_len]);
                collected_len += copy_len;
            }

            if (parseMode2027Response(collected[0..collected_len])) |supported| {
                return supported;
            }
        }

        return false;
    }

    fn parseMode2027Response(bytes: []const u8) ?bool {
        const prefix = "\x1b[?2027;";
        var search_from: usize = 0;

        while (search_from < bytes.len) {
            const start = std.mem.indexOfPos(u8, bytes, search_from, prefix) orelse return null;
            var i = start + prefix.len;
            var param: usize = 0;
            var saw_digit = false;

            while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {
                saw_digit = true;
                param = param * 10 + (bytes[i] - '0');
            }

            if (!saw_digit) {
                search_from = start + 1;
                continue;
            }

            if (i + 1 < bytes.len and bytes[i] == '$' and bytes[i + 1] == 'y') {
                return param != 0;
            }

            search_from = start + 1;
        }

        return null;
    }

    fn selectWidthStrategy(self: *const Terminal) unicode.WidthStrategy {
        if (isInsideMultiplexer()) {
            return .legacy_wcwidth;
        }

        if (self.unicode_width_caps.mode_2027) {
            return .unicode;
        }

        if (self.unicode_width_caps.kitty_text_sizing) {
            return .unicode;
        }

        if (isKnownUnicodeWidthTerminal()) {
            return .unicode;
        }

        return .legacy_wcwidth;
    }

    fn queryKittyTextSizingSupport(self: *Terminal) !bool {
        if (!looksLikeKittyTerminal()) return false;

        const cpr = "\x1b[6n";
        // CR, CPR, draw 2-cell space via kitty OSC 66 width-only, CPR.
        const probe = "\r" ++ cpr ++ "\x1b]66;w=2; \x07" ++ cpr;
        try self.writeBytes(probe);
        try self.flush();

        var buf: [512]u8 = undefined;
        var len: usize = 0;
        const deadline_ms = std.time.milliTimestamp() + 250;

        while (std.time.milliTimestamp() < deadline_ms) {
            var chunk: [128]u8 = undefined;
            const n = self.readInput(&chunk, 40) catch 0;
            if (n == 0) continue;

            const copy_len = @min(n, buf.len - len);
            if (copy_len > 0) {
                @memcpy(buf[len .. len + copy_len], chunk[0..copy_len]);
                len += copy_len;
            }

            if (parseTwoCprColumns(buf[0..len])) |cols| {
                return cols.second == cols.first + 2;
            }
        }

        return false;
    }

    fn parseTwoCprColumns(bytes: []const u8) ?struct { first: usize, second: usize } {
        var idx: usize = 0;
        var found: [2]usize = .{ 0, 0 };
        var count: usize = 0;

        while (idx < bytes.len and count < 2) {
            const esc = std.mem.indexOfPos(u8, bytes, idx, "\x1b[") orelse break;
            var i = esc + 2;

            while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
            if (i >= bytes.len or bytes[i] != ';') {
                idx = esc + 1;
                continue;
            }
            i += 1;

            const col_start = i;
            while (i < bytes.len and bytes[i] >= '0' and bytes[i] <= '9') : (i += 1) {}
            if (i >= bytes.len or bytes[i] != 'R' or col_start == i) {
                idx = esc + 1;
                continue;
            }

            const col = std.fmt.parseInt(usize, bytes[col_start..i], 10) catch {
                idx = esc + 1;
                continue;
            };
            found[count] = col;
            count += 1;
            idx = i + 1;
        }

        if (count == 2) {
            return .{ .first = found[0], .second = found[1] };
        }
        return null;
    }

    fn isInsideMultiplexer() bool {
        return envVarExists("TMUX") or envVarExists("ZELLIJ") or envVarContains("TERM", "screen");
    }

    fn isKnownUnicodeWidthTerminal() bool {
        // Terminals known to use grapheme-aware width by default.
        return envVarEquals("TERM_PROGRAM", "WezTerm") or
            envVarEquals("TERM_PROGRAM", "iTerm.app") or
            envVarContains("TERM", "wezterm") or
            envVarContains("TERM", "ghostty");
    }

    fn looksLikeKittyTerminal() bool {
        return envVarExists("KITTY_WINDOW_ID") or envVarContains("TERM", "kitty");
    }

    fn envVarExists(name: []const u8) bool {
        const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
        defer std.heap.page_allocator.free(value);
        return value.len > 0;
    }

    fn envVarEquals(name: []const u8, expected: []const u8) bool {
        const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
        defer std.heap.page_allocator.free(value);
        return std.ascii.eqlIgnoreCase(value, expected);
    }

    fn envVarContains(name: []const u8, needle: []const u8) bool {
        const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
        defer std.heap.page_allocator.free(value);
        return std.mem.indexOf(u8, value, needle) != null;
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
