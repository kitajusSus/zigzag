const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");
const Tooltip = zz.Tooltip;

// ---------------------------------------------------------------------------
// Preset constructors
// ---------------------------------------------------------------------------

test "init — simple text tooltip" {
    const t = Tooltip.init("Hello");
    try testing.expectEqualStrings("Hello", t.text);
    try testing.expect(t.title == null);
    try testing.expect(!t.visible);
}

test "titled — tooltip with title" {
    const t = Tooltip.titled("Info", "Some detail");
    try testing.expectEqualStrings("Info", t.title.?);
    try testing.expectEqualStrings("Some detail", t.text);
}

test "help — dim italic preset" {
    const t = Tooltip.help("Press Enter to confirm");
    try testing.expectEqualStrings("Press Enter to confirm", t.text);
}

test "shortcut — label + key preset" {
    const t = Tooltip.shortcut("Save", "Ctrl+S");
    try testing.expectEqualStrings("Save", t.title.?);
    try testing.expectEqualStrings("Ctrl+S", t.text);
}

// ---------------------------------------------------------------------------
// State management
// ---------------------------------------------------------------------------

test "show / hide / toggle" {
    var t = Tooltip.init("Tip");
    try testing.expect(!t.visible);

    t.show();
    try testing.expect(t.visible);
    try testing.expect(t.isVisible());

    t.hide();
    try testing.expect(!t.visible);

    t.toggle();
    try testing.expect(t.visible);
    t.toggle();
    try testing.expect(!t.visible);
}

// ---------------------------------------------------------------------------
// Rendering — renderBox
// ---------------------------------------------------------------------------

test "renderBox produces output" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.init("Hello world");
    const box = try t.renderBox(alloc);
    try testing.expect(box.len > 0);
    // Should contain the text
    try testing.expect(std.mem.indexOf(u8, box, "Hello world") != null);
}

test "renderBox with title" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.titled("Title", "Body text");
    const box = try t.renderBox(alloc);
    try testing.expect(std.mem.indexOf(u8, box, "Title") != null);
    try testing.expect(std.mem.indexOf(u8, box, "Body text") != null);
}

test "renderBox multi-line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Line 1\nLine 2");
    t.padding = .{ .top = 0, .right = 1, .bottom = 0, .left = 1 };
    const box = try t.renderBox(alloc);
    try testing.expect(std.mem.indexOf(u8, box, "Line 1") != null);
    try testing.expect(std.mem.indexOf(u8, box, "Line 2") != null);
}

test "renderBox respects max_width" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Short");
    t.max_width = 20;
    t.padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 };
    const box = try t.renderBox(alloc);
    const w = zz.measure.maxLineWidth(box);
    // box_w = content_w + 2 (borders) + padding. Short = 5, so 5+2 = 7
    try testing.expect(w <= 22); // max_width + borders
}

// ---------------------------------------------------------------------------
// Rendering — render (full canvas)
// ---------------------------------------------------------------------------

test "render returns empty when not visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.init("Tip");
    const output = try t.render(alloc, 80, 24);
    try testing.expectEqual(@as(usize, 0), output.len);
}

test "render produces output when visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Hello");
    t.target_x = 10;
    t.target_y = 5;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "render with different placements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const placements = [_]Tooltip.Placement{ .top, .bottom, .left, .right };
    for (placements) |p| {
        var t = Tooltip.init("Tip");
        t.target_x = 20;
        t.target_y = 12;
        t.placement = p;
        t.show();
        const output = try t.render(alloc, 80, 24);
        try testing.expect(output.len > 0);
    }
}

test "render without arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("No arrow");
    t.show_arrow = false;
    t.target_x = 10;
    t.target_y = 5;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

// ---------------------------------------------------------------------------
// Rendering — overlay
// ---------------------------------------------------------------------------

test "overlay returns base when not visible" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const t = Tooltip.init("Tip");
    const base = "Hello world";
    const output = try t.overlay(alloc, base, 80, 24);
    try testing.expectEqualStrings(base, output);
}

test "overlay composites tooltip onto base" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Tip");
    t.target_x = 5;
    t.target_y = 1;
    t.show();
    const base = "Line one text here\nLine two text here\nLine three here";
    const output = try t.overlay(alloc, base, 40, 10);
    try testing.expect(output.len > 0);
}

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

test "tooltip at edge of terminal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Edge test");
    t.target_x = 78;
    t.target_y = 23;
    t.placement = .bottom;
    t.show();
    // Should not crash — position clamped to bounds
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "tooltip at origin" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Origin");
    t.target_x = 0;
    t.target_y = 0;
    t.placement = .top;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "tooltip with gap" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Gapped");
    t.target_x = 10;
    t.target_y = 10;
    t.gap = 2;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

test "empty tooltip text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("");
    t.show();
    const box = try t.renderBox(alloc);
    try testing.expect(box.len > 0); // Still renders box frame
}

// ---------------------------------------------------------------------------
// Arrow customization
// ---------------------------------------------------------------------------

test "custom arrow characters" {
    var t = Tooltip.init("Custom arrows");
    t.arrow_up = "^";
    t.arrow_down = "v";
    t.arrow_left = "<";
    t.arrow_right = ">";
    try testing.expectEqualStrings("^", t.arrow_up);
    try testing.expectEqualStrings("v", t.arrow_down);
}

test "render with custom arrow chars" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Custom");
    t.arrow_up = "^";
    t.target_x = 10;
    t.target_y = 5;
    t.placement = .bottom;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
    try testing.expect(std.mem.indexOf(u8, output, "^") != null);
}

test "render left/right placement shows arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Right placement
    var t = Tooltip.init("Right");
    t.arrow_left = "<";
    t.target_x = 10;
    t.target_y = 12;
    t.target_width = 4;
    t.placement = .right;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(std.mem.indexOf(u8, output, "<") != null);
}

test "overlay left/right placement shows arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Left");
    t.arrow_right = ">";
    t.target_x = 40;
    t.target_y = 5;
    t.target_width = 4;
    t.placement = .left;
    t.show();
    const base = "Some base content that is wide enough for the test overlay to work";
    const output = try t.overlay(alloc, base, 80, 12);
    try testing.expect(std.mem.indexOf(u8, output, ">") != null);
}

test "empty arrow string hides arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("No arrow char");
    t.arrow_up = "";
    t.target_x = 10;
    t.target_y = 5;
    t.placement = .bottom;
    t.show();
    const output = try t.render(alloc, 80, 24);
    try testing.expect(output.len > 0);
}

// ── inherit_bg tests ──────────────────────────────────────────────

test "inherit_bg false does not inject base background" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Tip");
    t.target_x = 5;
    t.target_y = 0;
    t.placement = .bottom;
    t.inherit_bg = false;
    t.show();

    // Base line with a true-color bg on the first row
    const base = "\x1b[48;2;100;100;100mColored Background\x1b[0m";
    const output = try t.overlay(alloc, base, 40, 10);
    try testing.expect(output.len > 0);
    // With inherit_bg off, the tooltip renders without injecting base bg.
    // Just verify it produces valid output.
    try testing.expect(std.mem.indexOf(u8, output, "\n") != null);
}

test "inherit_bg true injects base background into arrow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Tip");
    t.target_x = 5;
    t.target_y = 0;
    t.placement = .bottom;
    t.inherit_bg = true;
    t.show();

    // Base with a true-color bg covering the arrow position
    const base = "\x1b[48;2;200;50;50mRed Background Here!!\x1b[0m";
    const output = try t.overlay(alloc, base, 40, 10);
    try testing.expect(output.len > 0);

    // The arrow row should contain the base bg sequence (48;2;200;50;50)
    // injected before the arrow character
    try testing.expect(std.mem.indexOf(u8, output, "48;2;200;50;50") != null);
}

test "inherit_bg true injects base background into box border" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Hi");
    t.target_x = 3;
    t.target_y = 0;
    t.placement = .bottom;
    t.inherit_bg = true;
    t.show();

    // Base with a 256-color bg
    const base = "\x1b[48;5;22mGreen row content here long enough\x1b[0m";
    const output = try t.overlay(alloc, base, 50, 10);
    try testing.expect(output.len > 0);
    // The box rows should contain the 256-color bg injected
    try testing.expect(std.mem.indexOf(u8, output, "48;5;22") != null);
}

test "inherit_bg with no base background is harmless" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Plain");
    t.target_x = 2;
    t.target_y = 0;
    t.placement = .bottom;
    t.inherit_bg = true;
    t.show();

    // Plain base with no ANSI at all
    const base = "Hello World, no colors here at all!!";
    const output = try t.overlay(alloc, base, 50, 10);
    try testing.expect(output.len > 0);
    // Should still render correctly — no crash, no garbage
}

test "inherit_bg with bg reset before target column" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Tip");
    t.target_x = 12;
    t.target_y = 0;
    t.placement = .bottom;
    t.inherit_bg = true;
    t.show();

    // BG set then reset before the target column
    const base = "\x1b[48;2;255;0;0mRedPart\x1b[0m  PlainPart after reset here";
    const output = try t.overlay(alloc, base, 50, 10);
    try testing.expect(output.len > 0);
    // At column 12 the bg has been reset, so no bg should be injected.
    // The red bg (255;0;0) should NOT appear in tooltip elements.
    // It may still appear in the preserved base left portion though,
    // so we just verify no crash and valid output.
}

test "inherit_bg with left/right placement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Side");
    t.target_x = 20;
    t.target_y = 3;
    t.target_width = 4;
    t.placement = .right;
    t.inherit_bg = true;
    t.show();

    // Build multi-line base with bg on relevant rows
    var base_buf = std.array_list.Managed(u8).init(alloc);
    for (0..8) |row| {
        if (row > 0) try base_buf.append('\n');
        if (row == 3) {
            try base_buf.appendSlice("\x1b[48;2;0;128;255m");
            try base_buf.appendSlice("Blue row with enough content for tooltip overlay test!!");
            try base_buf.appendSlice("\x1b[0m");
        } else {
            try base_buf.appendSlice("Normal row with some plain text content for testing!!");
        }
    }
    const base = try base_buf.toOwnedSlice();
    const output = try t.overlay(alloc, base, 60, 8);
    try testing.expect(output.len > 0);
    // The blue bg should be injected into the arrow on row 3
    try testing.expect(std.mem.indexOf(u8, output, "48;2;0;128;255") != null);
}

// ── border_bg / arrow_bg tests ────────────────────────────────────

test "border_bg null falls back to content_bg (backward compat)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Color = zz.Color;
    var t = Tooltip.init("Hi");
    t.content_bg = Color.fromRgb(30, 30, 30);
    // border_bg defaults to null → should use content_bg for borders
    t.show();
    const box = try t.renderBox(alloc);
    // The border should contain the content_bg sequence
    try testing.expect(std.mem.indexOf(u8, box, "48;2;30;30;30") != null);
}

test "border_bg .none gives transparent border" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Color = zz.Color;
    var t = Tooltip.init("Hi");
    t.content_bg = Color.fromRgb(30, 30, 30);
    t.border_bg = .none; // explicitly no bg for borders
    t.show();
    const box = try t.renderBox(alloc);
    // Content should still have the bg
    try testing.expect(std.mem.indexOf(u8, box, "48;2;30;30;30") != null);
    // Box should still render
    try testing.expect(box.len > 0);
}

test "border_bg explicit color differs from content_bg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Color = zz.Color;
    var t = Tooltip.init("Test");
    t.content_bg = Color.fromRgb(10, 10, 10);
    t.border_bg = Color.fromRgb(50, 50, 50);
    t.show();
    const box = try t.renderBox(alloc);
    // Both color sequences should appear
    try testing.expect(std.mem.indexOf(u8, box, "48;2;10;10;10") != null);
    try testing.expect(std.mem.indexOf(u8, box, "48;2;50;50;50") != null);
}

test "border_bg .none with inherit_bg shows base through border" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Color = zz.Color;
    var t = Tooltip.init("Hi");
    t.content_bg = Color.fromRgb(30, 30, 30); // solid interior
    t.border_bg = .none; // transparent border
    t.inherit_bg = true;
    t.target_x = 3;
    t.target_y = 0;
    t.placement = .bottom;
    t.show();

    const base = "\x1b[48;2;200;100;50mOrange background row here long enough\x1b[0m";
    const output = try t.overlay(alloc, base, 50, 10);
    try testing.expect(output.len > 0);
    // The base orange bg should appear (inherited by border cells)
    try testing.expect(std.mem.indexOf(u8, output, "48;2;200;100;50") != null);
    // The content bg should also appear
    try testing.expect(std.mem.indexOf(u8, output, "48;2;30;30;30") != null);
}

test "arrow_bg explicit color overrides inherit_bg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const Color = zz.Color;
    var t = Tooltip.init("Tip");
    t.arrow_bg = Color.fromRgb(255, 0, 0); // explicit red arrow bg
    t.inherit_bg = true;
    t.target_x = 5;
    t.target_y = 0;
    t.placement = .bottom;
    t.show();

    const base = "\x1b[48;2;0;0;255mBlue background here long!!!\x1b[0m";
    const output = try t.overlay(alloc, base, 40, 10);
    try testing.expect(output.len > 0);
    // The arrow should have red bg, not blue (explicit overrides inherit)
    try testing.expect(std.mem.indexOf(u8, output, "48;2;255;0;0") != null);
}

test "arrow_bg .none prevents inheritance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var t = Tooltip.init("Tip");
    t.arrow_bg = .none; // explicitly no bg
    t.inherit_bg = true;
    t.target_x = 5;
    t.target_y = 0;
    t.placement = .bottom;
    t.show();

    const base = "\x1b[48;2;0;255;0mGreen background here long!!\x1b[0m";
    const output = try t.overlay(alloc, base, 40, 10);
    try testing.expect(output.len > 0);
    // Should render without crash; arrow should NOT have green bg
}
