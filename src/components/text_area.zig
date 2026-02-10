//! Multi-line text area component.
//! Provides text editing with multiple lines, cursor navigation, and scrolling.

const std = @import("std");
const keys = @import("../input/keys.zig");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;
const measure = @import("../layout/measure.zig");
const unicode = @import("../unicode.zig");

pub const TextArea = struct {
    allocator: std.mem.Allocator,

    // Content
    lines: std.array_list.Managed(std.array_list.Managed(u8)),

    // Cursor position
    cursor_row: usize,
    cursor_col: usize,

    // Viewport
    viewport_row: usize,
    viewport_col: usize,
    width: u16,
    height: u16,

    // Appearance
    placeholder: []const u8,
    line_numbers: bool,
    word_wrap: bool,

    // Styling
    text_style: style_mod.Style,
    cursor_style: style_mod.Style,
    line_number_style: style_mod.Style,
    placeholder_style: style_mod.Style,

    // State
    focused: bool,

    // Limits
    max_lines: ?usize,
    max_cols: ?usize,
    char_limit: ?usize,

    pub fn init(allocator: std.mem.Allocator) TextArea {
        var lines = std.array_list.Managed(std.array_list.Managed(u8)).init(allocator);
        lines.append(std.array_list.Managed(u8).init(allocator)) catch {};

        return .{
            .allocator = allocator,
            .lines = lines,
            .cursor_row = 0,
            .cursor_col = 0,
            .viewport_row = 0,
            .viewport_col = 0,
            .width = 80,
            .height = 10,
            .placeholder = "",
            .line_numbers = false,
            .word_wrap = false,
            .text_style = blk: {
                var s = style_mod.Style{};
                s = s.inline_style(true);
                break :blk s;
            },
            .cursor_style = blk: {
                var s = style_mod.Style{};
                s = s.reverse(true);
                s = s.inline_style(true);
                break :blk s;
            },
            .line_number_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(Color.gray(12));
                s = s.inline_style(true);
                break :blk s;
            },
            .placeholder_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(Color.gray(12));
                s = s.inline_style(true);
                break :blk s;
            },
            .focused = true,
            .max_lines = null,
            .max_cols = null,
            .char_limit = null,
        };
    }

    pub fn deinit(self: *TextArea) void {
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.deinit();
    }

    /// Set the content
    pub fn setValue(self: *TextArea, text: []const u8) !void {
        // Clear existing lines
        for (self.lines.items) |*line| {
            line.deinit();
        }
        self.lines.clearRetainingCapacity();

        // Parse lines
        var iter = std.mem.splitScalar(u8, text, '\n');
        while (iter.next()) |line_text| {
            var line = std.array_list.Managed(u8).init(self.allocator);
            try line.appendSlice(line_text);
            try self.lines.append(line);
        }

        if (self.lines.items.len == 0) {
            try self.lines.append(std.array_list.Managed(u8).init(self.allocator));
        }

        // Reset cursor
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.viewport_row = 0;
    }

    /// Get the content as a string
    pub fn getValue(self: *const TextArea, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.array_list.Managed(u8).init(allocator);

        for (self.lines.items, 0..) |line, i| {
            if (i > 0) try result.append('\n');
            try result.appendSlice(line.items);
        }

        return result.toOwnedSlice();
    }

    /// Get total character count
    pub fn charCount(self: *const TextArea) usize {
        var count: usize = 0;
        for (self.lines.items, 0..) |line, i| {
            if (i > 0) count += 1; // Newline
            count += line.items.len;
        }
        return count;
    }

    /// Get line count
    pub fn lineCount(self: *const TextArea) usize {
        return self.lines.items.len;
    }

    /// Set dimensions
    pub fn setSize(self: *TextArea, width: u16, height: u16) void {
        self.width = width;
        self.height = height;
        self.ensureVisible();
    }

    /// Focus the text area
    pub fn focus(self: *TextArea) void {
        self.focused = true;
    }

    /// Blur the text area
    pub fn blur(self: *TextArea) void {
        self.focused = false;
    }

    /// Handle key event
    pub fn handleKey(self: *TextArea, key: keys.KeyEvent) void {
        if (!self.focused) return;

        if (key.modifiers.ctrl) {
            switch (key.key) {
                .char => |c| switch (c) {
                    'a' => self.cursor_col = 0, // Home
                    'e' => self.cursor_col = self.currentLine().items.len, // End
                    'k' => self.killToEndOfLine(), // Kill line
                    'u' => self.killToStartOfLine(), // Kill to start
                    'd' => self.deleteLine(), // Delete line
                    else => {},
                },
                else => {},
            }
            return;
        }

        switch (key.key) {
            .char => |c| self.insertChar(c),
            .enter => self.insertNewline(),
            .backspace => self.deleteBackward(),
            .delete => self.deleteForward(),
            .up => self.moveCursorUp(),
            .down => self.moveCursorDown(),
            .left => self.moveCursorLeft(),
            .right => self.moveCursorRight(),
            .home => self.cursor_col = 0,
            .end => self.cursor_col = self.currentLine().items.len,
            .page_up => self.pageUp(),
            .page_down => self.pageDown(),
            .tab => self.insertTab(),
            else => {},
        }

        self.ensureVisible();
    }

    fn currentLine(self: *TextArea) *std.array_list.Managed(u8) {
        return &self.lines.items[self.cursor_row];
    }

    fn insertChar(self: *TextArea, c: u21) void {
        // Check char limit
        if (self.char_limit) |limit| {
            if (self.charCount() >= limit) return;
        }

        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(c, &buf) catch return;

        const line = self.currentLine();
        const pos = @min(self.cursor_col, line.items.len);
        line.insertSlice(pos, buf[0..len]) catch return;
        self.cursor_col = pos + len;
    }

    fn insertNewline(self: *TextArea) void {
        if (self.max_lines) |max| {
            if (self.lines.items.len >= max) return;
        }

        const line = self.currentLine();
        const rest = line.items[self.cursor_col..];

        // Create new line with rest of content
        var new_line = std.array_list.Managed(u8).init(self.allocator);
        new_line.appendSlice(rest) catch return;

        // Truncate current line
        line.shrinkRetainingCapacity(self.cursor_col);

        // Insert new line
        self.lines.insert(self.cursor_row + 1, new_line) catch return;

        self.cursor_row += 1;
        self.cursor_col = 0;
    }

    fn insertTab(self: *TextArea) void {
        // Insert spaces for tab
        for (0..4) |_| {
            self.insertChar(' ');
        }
    }

    fn deleteBackward(self: *TextArea) void {
        if (self.cursor_col > 0) {
            // Delete character before cursor
            const line = self.currentLine();
            var pos = self.cursor_col - 1;

            // Find start of UTF-8 sequence
            while (pos > 0 and (line.items[pos] & 0xC0) == 0x80) {
                pos -= 1;
            }

            const len = self.cursor_col - pos;
            for (0..len) |_| {
                _ = line.orderedRemove(pos);
            }
            self.cursor_col = pos;
        } else if (self.cursor_row > 0) {
            // Join with previous line
            const current = self.lines.orderedRemove(self.cursor_row);
            self.cursor_row -= 1;
            const prev_line = self.currentLine();
            self.cursor_col = prev_line.items.len;
            prev_line.appendSlice(current.items) catch {};
            @constCast(&current).deinit();
        }
    }

    fn deleteForward(self: *TextArea) void {
        const line = self.currentLine();
        if (self.cursor_col < line.items.len) {
            // Delete character at cursor
            const byte_len = std.unicode.utf8ByteSequenceLength(line.items[self.cursor_col]) catch 1;
            for (0..byte_len) |_| {
                if (self.cursor_col < line.items.len) {
                    _ = line.orderedRemove(self.cursor_col);
                }
            }
        } else if (self.cursor_row < self.lines.items.len - 1) {
            // Join with next line
            const next = self.lines.orderedRemove(self.cursor_row + 1);
            line.appendSlice(next.items) catch {};
            @constCast(&next).deinit();
        }
    }

    fn killToEndOfLine(self: *TextArea) void {
        const line = self.currentLine();
        line.shrinkRetainingCapacity(self.cursor_col);
    }

    fn killToStartOfLine(self: *TextArea) void {
        const line = self.currentLine();
        std.mem.copyForwards(u8, line.items[0..], line.items[self.cursor_col..]);
        line.shrinkRetainingCapacity(line.items.len - self.cursor_col);
        self.cursor_col = 0;
    }

    fn deleteLine(self: *TextArea) void {
        if (self.lines.items.len > 1) {
            var removed = self.lines.orderedRemove(self.cursor_row);
            removed.deinit();
            if (self.cursor_row >= self.lines.items.len) {
                self.cursor_row = self.lines.items.len - 1;
            }
            self.cursor_col = @min(self.cursor_col, self.currentLine().items.len);
        } else {
            self.currentLine().clearRetainingCapacity();
            self.cursor_col = 0;
        }
    }

    fn moveCursorUp(self: *TextArea) void {
        if (self.cursor_row > 0) {
            self.cursor_row -= 1;
            self.cursor_col = @min(self.cursor_col, self.currentLine().items.len);
        }
    }

    fn moveCursorDown(self: *TextArea) void {
        if (self.cursor_row < self.lines.items.len - 1) {
            self.cursor_row += 1;
            self.cursor_col = @min(self.cursor_col, self.currentLine().items.len);
        }
    }

    fn moveCursorLeft(self: *TextArea) void {
        if (self.cursor_col > 0) {
            self.cursor_col -= 1;
            // Handle UTF-8 continuation bytes
            const line = self.currentLine();
            while (self.cursor_col > 0 and (line.items[self.cursor_col] & 0xC0) == 0x80) {
                self.cursor_col -= 1;
            }
        } else if (self.cursor_row > 0) {
            self.cursor_row -= 1;
            self.cursor_col = self.currentLine().items.len;
        }
    }

    fn moveCursorRight(self: *TextArea) void {
        const line = self.currentLine();
        if (self.cursor_col < line.items.len) {
            const byte_len = std.unicode.utf8ByteSequenceLength(line.items[self.cursor_col]) catch 1;
            self.cursor_col = @min(self.cursor_col + byte_len, line.items.len);
        } else if (self.cursor_row < self.lines.items.len - 1) {
            self.cursor_row += 1;
            self.cursor_col = 0;
        }
    }

    fn pageUp(self: *TextArea) void {
        if (self.cursor_row >= self.height) {
            self.cursor_row -= self.height;
        } else {
            self.cursor_row = 0;
        }
        self.cursor_col = @min(self.cursor_col, self.currentLine().items.len);
    }

    fn pageDown(self: *TextArea) void {
        if (self.cursor_row + self.height < self.lines.items.len) {
            self.cursor_row += self.height;
        } else {
            self.cursor_row = self.lines.items.len - 1;
        }
        self.cursor_col = @min(self.cursor_col, self.currentLine().items.len);
    }

    fn ensureVisible(self: *TextArea) void {
        // Vertical scrolling
        if (self.cursor_row < self.viewport_row) {
            self.viewport_row = self.cursor_row;
        } else if (self.cursor_row >= self.viewport_row + self.height) {
            self.viewport_row = self.cursor_row - self.height + 1;
        }

        // Horizontal scrolling using display columns
        const effective_width = self.width -| (if (self.line_numbers) @as(u16, 5) else 0);
        const display_col = self.cursorDisplayCol();
        if (display_col < self.viewport_col) {
            self.viewport_col = display_col;
        } else if (display_col >= self.viewport_col + effective_width) {
            self.viewport_col = display_col - effective_width + 1;
        }
    }

    /// Render the text area
    pub fn view(self: *const TextArea, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.array_list.Managed(u8).init(allocator);
        const writer = result.writer();

        const line_num_width: usize = if (self.line_numbers) 5 else 0;
        const text_width = self.width -| @as(u16, @intCast(line_num_width));

        // Check for empty content
        const is_empty = self.lines.items.len == 1 and self.lines.items[0].items.len == 0;

        for (0..self.height) |row| {
            if (row > 0) try writer.writeByte('\n');

            const line_idx = self.viewport_row + row;

            // Line numbers
            if (self.line_numbers) {
                if (line_idx < self.lines.items.len) {
                    const num_str = try std.fmt.allocPrint(allocator, "{d:>4} ", .{line_idx + 1});
                    const styled = try self.line_number_style.render(allocator, num_str);
                    try writer.writeAll(styled);
                } else {
                    try writer.writeAll("     ");
                }
            }

            if (line_idx < self.lines.items.len) {
                const line = self.lines.items[line_idx];

                // Show placeholder on first empty line
                if (is_empty and line_idx == 0 and self.placeholder.len > 0) {
                    const styled = try self.placeholder_style.render(allocator, self.placeholder);
                    try writer.writeAll(styled);
                    continue;
                }

                // Render line content with cursor
                try self.renderLine(writer, allocator, line.items, line_idx, text_width);
            }
        }

        return result.toOwnedSlice();
    }

    fn renderLine(self: *const TextArea, writer: anytype, allocator: std.mem.Allocator, line: []const u8, line_idx: usize, max_width: u16) !void {
        const is_cursor_line = line_idx == self.cursor_row;

        // Apply horizontal scroll
        var col: usize = 0;
        var byte_idx: usize = 0;

        // Skip to viewport_col (using display columns)
        while (col < self.viewport_col and byte_idx < line.len) {
            const byte_len = std.unicode.utf8ByteSequenceLength(line[byte_idx]) catch 1;
            if (byte_idx + byte_len <= line.len) {
                const cp = std.unicode.utf8Decode(line[byte_idx..][0..byte_len]) catch {
                    byte_idx += 1;
                    col += 1;
                    continue;
                };
                col += unicode.charWidth(cp);
            }
            byte_idx += byte_len;
        }

        // Render visible portion
        var rendered_width: usize = 0;
        while (byte_idx < line.len and rendered_width < max_width) {
            const is_cursor = is_cursor_line and self.focused and byte_idx == self.cursor_col;

            const byte_len = std.unicode.utf8ByteSequenceLength(line[byte_idx]) catch 1;
            if (byte_idx + byte_len > line.len) break;
            const char_slice = line[byte_idx..][0..byte_len];

            const cp = std.unicode.utf8Decode(line[byte_idx..][0..byte_len]) catch {
                byte_idx += 1;
                rendered_width += 1;
                continue;
            };
            const cw = unicode.charWidth(cp);

            // Wide char won't fit — stop
            if (rendered_width + cw > max_width) break;

            if (is_cursor) {
                const styled = try self.cursor_style.render(allocator, char_slice);
                try writer.writeAll(styled);
            } else {
                const styled = try self.text_style.render(allocator, char_slice);
                try writer.writeAll(styled);
            }

            byte_idx += byte_len;
            col += cw;
            rendered_width += cw;
        }

        // Cursor at end of line
        if (is_cursor_line and self.focused and byte_idx == self.cursor_col and rendered_width < max_width) {
            const styled = try self.cursor_style.render(allocator, " ");
            try writer.writeAll(styled);
            rendered_width += 1;
        }

        // Pad remaining width
        while (rendered_width < max_width) {
            try writer.writeByte(' ');
            rendered_width += 1;
        }
    }

    /// Convert byte-offset cursor_col to display column width.
    fn cursorDisplayCol(self: *const TextArea) usize {
        const line = self.lines.items[self.cursor_row];
        var display_col: usize = 0;
        var byte_idx: usize = 0;
        while (byte_idx < self.cursor_col and byte_idx < line.items.len) {
            const byte_len = std.unicode.utf8ByteSequenceLength(line.items[byte_idx]) catch 1;
            if (byte_idx + byte_len <= line.items.len) {
                const cp = std.unicode.utf8Decode(line.items[byte_idx..][0..byte_len]) catch {
                    byte_idx += 1;
                    display_col += 1;
                    continue;
                };
                display_col += unicode.charWidth(cp);
            }
            byte_idx += byte_len;
        }
        return display_col;
    }
};
