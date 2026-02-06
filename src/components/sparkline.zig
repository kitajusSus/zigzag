//! Sparkline component for mini charts using Unicode block elements.
//! Displays data as a compact bar chart.

const std = @import("std");
const style_mod = @import("../style/style.zig");
const Color = @import("../style/color.zig").Color;

pub const Sparkline = struct {
    allocator: std.mem.Allocator,
    data: std.array_list.Managed(f64),
    display_width: u16,
    spark_style: style_mod.Style,

    const block_chars = [_][]const u8{ " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇" };

    pub fn init(allocator: std.mem.Allocator) Sparkline {
        return .{
            .allocator = allocator,
            .data = std.array_list.Managed(f64).init(allocator),
            .display_width = 40,
            .spark_style = blk: {
                var s = style_mod.Style{};
                s = s.fg(Color.green());
                s = s.inline_style(true);
                break :blk s;
            },
        };
    }

    pub fn deinit(self: *Sparkline) void {
        self.data.deinit();
    }

    /// Push a new value (ring buffer behavior: oldest removed when exceeding width)
    pub fn push(self: *Sparkline, value: f64) !void {
        try self.data.append(value);
        // Keep only display_width values
        while (self.data.items.len > self.display_width) {
            _ = self.data.orderedRemove(0);
        }
    }

    /// Set all data at once
    pub fn setData(self: *Sparkline, data: []const f64) !void {
        self.data.clearRetainingCapacity();
        try self.data.appendSlice(data);
        while (self.data.items.len > self.display_width) {
            _ = self.data.orderedRemove(0);
        }
    }

    /// Set display width
    pub fn setWidth(self: *Sparkline, w: u16) void {
        self.display_width = w;
    }

    /// Set style
    pub fn setStyle(self: *Sparkline, s: style_mod.Style) void {
        self.spark_style = s;
    }

    /// Render the sparkline
    pub fn view(self: *const Sparkline, allocator: std.mem.Allocator) ![]const u8 {
        if (self.data.items.len == 0) {
            return try allocator.dupe(u8, "");
        }

        // Find min/max of visible window
        var min_val: f64 = self.data.items[0];
        var max_val: f64 = self.data.items[0];
        for (self.data.items) |v| {
            if (v < min_val) min_val = v;
            if (v > max_val) max_val = v;
        }

        var result = std.array_list.Managed(u8).init(allocator);
        const writer = result.writer();

        const range = max_val - min_val;

        for (self.data.items) |v| {
            const normalized: f64 = if (range > 0) (v - min_val) / range else 0.5;
            const idx: usize = @intFromFloat(@min(7.0, normalized * 7.0));
            const styled = try self.spark_style.render(allocator, block_chars[idx]);
            try writer.writeAll(styled);
        }

        // Pad remaining width
        if (self.data.items.len < self.display_width) {
            const remaining = self.display_width - @as(u16, @intCast(self.data.items.len));
            for (0..remaining) |_| {
                try writer.writeAll(" ");
            }
        }

        return result.toOwnedSlice();
    }
};
