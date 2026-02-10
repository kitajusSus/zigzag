//! Scrollable content viewport component.
//! Allows scrolling through content larger than the visible area.

const std = @import("std");
const keys = @import("../input/keys.zig");
const style = @import("../style/style.zig");
const measure = @import("../layout/measure.zig");
const unicode = @import("../unicode.zig");

pub const Viewport = struct {
    allocator: std.mem.Allocator,

    // Content
    content: []const u8,
    lines: std.array_list.Managed([]const u8),

    // Dimensions
    width: u16,
    height: u16,

    // Scroll position
    y_offset: usize,
    x_offset: usize,

    // Styling
    viewport_style: style.Style,

    // Options
    wrap: bool,
    show_scrollbar: bool,

    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) Viewport {
        return .{
            .allocator = allocator,
            .content = "",
            .lines = std.array_list.Managed([]const u8).init(allocator),
            .width = width,
            .height = height,
            .y_offset = 0,
            .x_offset = 0,
            .viewport_style = blk: {
                var s = style.Style{};
                s = s.inline_style(true);
                break :blk s;
            },
            .wrap = false,
            .show_scrollbar = true,
        };
    }

    pub fn deinit(self: *Viewport) void {
        self.lines.deinit();
    }

    /// Set content to display
    pub fn setContent(self: *Viewport, content: []const u8) !void {
        self.content = content;
        self.lines.clearRetainingCapacity();

        var iter = std.mem.splitScalar(u8, content, '\n');
        while (iter.next()) |line| {
            try self.lines.append(line);
        }

        // Ensure scroll position is valid
        self.clampScroll();
    }

    /// Set viewport dimensions
    pub fn setSize(self: *Viewport, width: u16, height: u16) void {
        self.width = width;
        self.height = height;
        self.clampScroll();
    }

    /// Scroll down by n lines
    pub fn scrollDown(self: *Viewport, n: usize) void {
        self.y_offset += n;
        self.clampScroll();
    }

    /// Scroll up by n lines
    pub fn scrollUp(self: *Viewport, n: usize) void {
        self.y_offset -|= n;
    }

    /// Scroll right by n columns
    pub fn scrollRight(self: *Viewport, n: usize) void {
        self.x_offset += n;
    }

    /// Scroll left by n columns
    pub fn scrollLeft(self: *Viewport, n: usize) void {
        self.x_offset -|= n;
    }

    /// Go to top
    pub fn gotoTop(self: *Viewport) void {
        self.y_offset = 0;
    }

    /// Go to bottom
    pub fn gotoBottom(self: *Viewport) void {
        if (self.lines.items.len > self.height) {
            self.y_offset = self.lines.items.len - self.height;
        }
    }

    /// Page down
    pub fn pageDown(self: *Viewport) void {
        self.scrollDown(self.height);
    }

    /// Page up
    pub fn pageUp(self: *Viewport) void {
        self.scrollUp(self.height);
    }

    /// Half page down
    pub fn halfPageDown(self: *Viewport) void {
        self.scrollDown(self.height / 2);
    }

    /// Half page up
    pub fn halfPageUp(self: *Viewport) void {
        self.scrollUp(self.height / 2);
    }

    /// Get current scroll percentage (0-100)
    pub fn scrollPercent(self: *const Viewport) u8 {
        if (self.lines.items.len <= self.height) return 100;
        const max_offset = self.lines.items.len - self.height;
        return @intCast(@min(100, (self.y_offset * 100) / max_offset));
    }

    /// Check if at top
    pub fn atTop(self: *const Viewport) bool {
        return self.y_offset == 0;
    }

    /// Check if at bottom
    pub fn atBottom(self: *const Viewport) bool {
        if (self.lines.items.len <= self.height) return true;
        return self.y_offset >= self.lines.items.len - self.height;
    }

    /// Total lines in content
    pub fn totalLines(self: *const Viewport) usize {
        return self.lines.items.len;
    }

    /// Handle key event
    pub fn handleKey(self: *Viewport, key: keys.KeyEvent) void {
        switch (key.key) {
            .up => self.scrollUp(1),
            .down => self.scrollDown(1),
            .left => self.scrollLeft(1),
            .right => self.scrollRight(1),
            .page_up => self.pageUp(),
            .page_down => self.pageDown(),
            .home => self.gotoTop(),
            .end => self.gotoBottom(),
            .char => |c| {
                switch (c) {
                    'j' => self.scrollDown(1),
                    'k' => self.scrollUp(1),
                    'h' => self.scrollLeft(1),
                    'l' => self.scrollRight(1),
                    'g' => self.gotoTop(),
                    'G' => self.gotoBottom(),
                    'd' => self.halfPageDown(),
                    'u' => self.halfPageUp(),
                    else => {},
                }
            },
            else => {},
        }
    }

    fn clampScroll(self: *Viewport) void {
        if (self.lines.items.len > self.height) {
            const max_y = self.lines.items.len - self.height;
            self.y_offset = @min(self.y_offset, max_y);
        } else {
            self.y_offset = 0;
        }
    }

    /// Render the viewport
    pub fn view(self: *const Viewport, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.array_list.Managed(u8).init(allocator);
        const writer = result.writer();

        const visible_width: usize = if (self.show_scrollbar and self.lines.items.len > self.height)
            self.width -| 1
        else
            self.width;

        // Render visible lines
        var rendered_lines: usize = 0;
        while (rendered_lines < self.height) : (rendered_lines += 1) {
            if (rendered_lines > 0) try writer.writeByte('\n');

            const line_idx = self.y_offset + rendered_lines;
            if (line_idx < self.lines.items.len) {
                const line = self.lines.items[line_idx];

                // Apply horizontal scroll
                const display_line = if (self.x_offset < measure.width(line))
                    try self.getSubstring(allocator, line, self.x_offset, visible_width)
                else
                    "";

                try writer.writeAll(display_line);

                // Pad to width
                const line_width = measure.width(display_line);
                if (line_width < visible_width) {
                    for (0..(visible_width - line_width)) |_| {
                        try writer.writeByte(' ');
                    }
                }
            } else {
                // Empty line
                for (0..visible_width) |_| {
                    try writer.writeByte(' ');
                }
            }

            // Scrollbar
            if (self.show_scrollbar and self.lines.items.len > self.height) {
                try self.renderScrollbar(writer, rendered_lines);
            }
        }

        return result.toOwnedSlice();
    }

    fn getSubstring(self: *const Viewport, allocator: std.mem.Allocator, line: []const u8, start_col: usize, max_width: usize) ![]const u8 {
        _ = self;
        var result = std.array_list.Managed(u8).init(allocator);

        var col: usize = 0;
        var i: usize = 0;

        // Skip to start column (using display widths)
        while (i < line.len and col < start_col) {
            const byte_len = std.unicode.utf8ByteSequenceLength(line[i]) catch 1;
            if (i + byte_len <= line.len) {
                const cp = std.unicode.utf8Decode(line[i..][0..byte_len]) catch {
                    i += 1;
                    col += 1;
                    continue;
                };
                col += unicode.charWidth(cp);
            }
            i += byte_len;
        }

        // Copy characters up to max_width (using display widths)
        var output_width: usize = 0;
        while (i < line.len and output_width < max_width) {
            const byte_len = std.unicode.utf8ByteSequenceLength(line[i]) catch 1;
            if (i + byte_len <= line.len) {
                const cp = std.unicode.utf8Decode(line[i..][0..byte_len]) catch {
                    try result.append(line[i]);
                    i += 1;
                    output_width += 1;
                    continue;
                };
                const cw = unicode.charWidth(cp);
                // Wide char would exceed max_width
                if (output_width + cw > max_width) break;
                try result.appendSlice(line[i..][0..byte_len]);
                output_width += cw;
            }
            i += byte_len;
        }

        return result.toOwnedSlice();
    }

    fn renderScrollbar(self: *const Viewport, writer: anytype, row: usize) !void {
        const total = self.lines.items.len;
        const visible = self.height;

        if (total <= visible) {
            try writer.writeByte(' ');
            return;
        }

        // Calculate scrollbar position
        const scrollbar_height = @max(1, (visible * visible) / total);
        const max_offset = total - visible;
        const scrollbar_pos = (self.y_offset * (visible - scrollbar_height)) / max_offset;

        if (row >= scrollbar_pos and row < scrollbar_pos + scrollbar_height) {
            try writer.writeAll("█");
        } else {
            try writer.writeAll("░");
        }
    }
};
