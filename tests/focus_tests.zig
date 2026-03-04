//! Tests for the focus management system.

const std = @import("std");
const zz = @import("zigzag");

// ---------------------------------------------------------------------------
// isFocusable comptime checks
// ---------------------------------------------------------------------------

test "isFocusable — positive for conforming type" {
    const Good = struct {
        focused: bool = false,
        pub fn focus(self: *@This()) void {
            self.focused = true;
        }
        pub fn blur(self: *@This()) void {
            self.focused = false;
        }
    };
    try std.testing.expect(zz.isFocusable(Good));
}

test "isFocusable — negative when field missing" {
    const Bad = struct {
        pub fn focus(_: *@This()) void {}
        pub fn blur(_: *@This()) void {}
    };
    try std.testing.expect(!zz.isFocusable(Bad));
}

test "isFocusable — negative when blur missing" {
    const Bad = struct {
        focused: bool = false,
        pub fn focus(_: *@This()) void {}
    };
    try std.testing.expect(!zz.isFocusable(Bad));
}

test "isFocusable — negative when focus missing" {
    const Bad = struct {
        focused: bool = false,
        pub fn blur(_: *@This()) void {}
    };
    try std.testing.expect(!zz.isFocusable(Bad));
}

// ---------------------------------------------------------------------------
// Built-in components satisfy the protocol
// ---------------------------------------------------------------------------

test "isFocusable — TextInput" {
    try std.testing.expect(zz.isFocusable(zz.TextInput));
}

test "isFocusable — TextArea" {
    try std.testing.expect(zz.isFocusable(zz.TextArea));
}

test "isFocusable — Confirm" {
    try std.testing.expect(zz.isFocusable(zz.Confirm));
}

// ---------------------------------------------------------------------------
// FocusGroup cycling
// ---------------------------------------------------------------------------

const TestItem = struct {
    focused: bool = false,
    pub fn focus(self: *TestItem) void {
        self.focused = true;
    }
    pub fn blur(self: *TestItem) void {
        self.focused = false;
    }
};

test "FocusGroup — initFocus focuses first, blurs rest" {
    var a = TestItem{};
    var b = TestItem{};
    var c = TestItem{};

    var fg: zz.FocusGroup(3) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.add(&c);
    fg.initFocus();

    try std.testing.expect(a.focused);
    try std.testing.expect(!b.focused);
    try std.testing.expect(!c.focused);
    try std.testing.expectEqual(@as(usize, 0), fg.focused());
}

test "FocusGroup — focusNext cycles forward" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    fg.focusNext();
    try std.testing.expect(!a.focused);
    try std.testing.expect(b.focused);
    try std.testing.expectEqual(@as(usize, 1), fg.focused());
}

test "FocusGroup — focusNext wraps around" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    fg.focusNext(); // -> 1
    fg.focusNext(); // -> 0 (wrap)
    try std.testing.expectEqual(@as(usize, 0), fg.focused());
    try std.testing.expect(a.focused);
    try std.testing.expect(!b.focused);
}

test "FocusGroup — focusPrev wraps around" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    fg.focusPrev(); // wrap from 0 -> 1
    try std.testing.expectEqual(@as(usize, 1), fg.focused());
    try std.testing.expect(!a.focused);
    try std.testing.expect(b.focused);
}

test "FocusGroup — no wrap mode" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{ .wrap = false };
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    // Prev at 0 should stay at 0
    fg.focusPrev();
    try std.testing.expectEqual(@as(usize, 0), fg.focused());

    // Next to 1, then next should stay at 1
    fg.focusAt(1);
    fg.focusNext();
    try std.testing.expectEqual(@as(usize, 1), fg.focused());
}

test "FocusGroup — focusAt" {
    var a = TestItem{};
    var b = TestItem{};
    var c = TestItem{};

    var fg: zz.FocusGroup(3) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.add(&c);

    fg.focusAt(2);
    try std.testing.expect(!a.focused);
    try std.testing.expect(!b.focused);
    try std.testing.expect(c.focused);
    try std.testing.expect(fg.isFocused(2));
    try std.testing.expect(!fg.isFocused(0));
}

test "FocusGroup — focusAt out of range does nothing" {
    var a = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.initFocus();

    fg.focusAt(99); // should not crash
    try std.testing.expectEqual(@as(usize, 0), fg.focused());
}

test "FocusGroup — blurAll" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();
    try std.testing.expect(a.focused);

    fg.blurAll();
    try std.testing.expect(!a.focused);
    try std.testing.expect(!b.focused);
}

test "FocusGroup — len" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(4) = .{};
    try std.testing.expectEqual(@as(usize, 0), fg.len());

    fg.add(&a);
    try std.testing.expectEqual(@as(usize, 1), fg.len());

    fg.add(&b);
    try std.testing.expectEqual(@as(usize, 2), fg.len());
}

// ---------------------------------------------------------------------------
// handleKey
// ---------------------------------------------------------------------------

test "FocusGroup — handleKey Tab moves forward" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    const tab = zz.KeyEvent{ .key = .tab, .modifiers = .{} };
    const consumed = fg.handleKey(tab);
    try std.testing.expect(consumed);
    try std.testing.expectEqual(@as(usize, 1), fg.focused());
}

test "FocusGroup — handleKey Shift+Tab moves backward" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();
    fg.focusAt(1);

    const shift_tab = zz.KeyEvent{ .key = .tab, .modifiers = .{ .shift = true } };
    const consumed = fg.handleKey(shift_tab);
    try std.testing.expect(consumed);
    try std.testing.expectEqual(@as(usize, 0), fg.focused());
}

test "FocusGroup — handleKey non-Tab returns false" {
    var a = TestItem{};

    var fg: zz.FocusGroup(1) = .{};
    fg.add(&a);
    fg.initFocus();

    const letter = zz.KeyEvent{ .key = .{ .char = 'x' }, .modifiers = .{} };
    try std.testing.expect(!fg.handleKey(letter));

    const enter = zz.KeyEvent{ .key = .enter, .modifiers = .{} };
    try std.testing.expect(!fg.handleKey(enter));

    const escape = zz.KeyEvent{ .key = .escape, .modifiers = .{} };
    try std.testing.expect(!fg.handleKey(escape));
}

// ---------------------------------------------------------------------------
// Custom key bindings
// ---------------------------------------------------------------------------

test "FocusGroup — addNextKey with arrow keys" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    // Down arrow should not work by default
    const down = zz.KeyEvent{ .key = .down, .modifiers = .{} };
    try std.testing.expect(!fg.handleKey(down));

    // Add Down as next key
    try std.testing.expect(fg.addNextKey(.{ .key = .down }));

    // Now it should work
    try std.testing.expect(fg.handleKey(down));
    try std.testing.expectEqual(@as(usize, 1), fg.focused());
}

test "FocusGroup — addPrevKey with arrow keys" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();
    fg.focusAt(1);

    // Up arrow should not work by default
    const up = zz.KeyEvent{ .key = .up, .modifiers = .{} };
    try std.testing.expect(!fg.handleKey(up));

    // Add Up as prev key
    try std.testing.expect(fg.addPrevKey(.{ .key = .up }));

    // Now it should work
    try std.testing.expect(fg.handleKey(up));
    try std.testing.expectEqual(@as(usize, 0), fg.focused());
}

test "FocusGroup — vim j/k keys" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    _ = fg.addNextKey(.{ .key = .{ .char = 'j' } });
    _ = fg.addPrevKey(.{ .key = .{ .char = 'k' } });

    // j moves forward
    const j = zz.KeyEvent{ .key = .{ .char = 'j' }, .modifiers = .{} };
    try std.testing.expect(fg.handleKey(j));
    try std.testing.expectEqual(@as(usize, 1), fg.focused());

    // k moves backward
    const k_key = zz.KeyEvent{ .key = .{ .char = 'k' }, .modifiers = .{} };
    try std.testing.expect(fg.handleKey(k_key));
    try std.testing.expectEqual(@as(usize, 0), fg.focused());

    // Tab still works (default binding preserved)
    const tab = zz.KeyEvent{ .key = .tab, .modifiers = .{} };
    try std.testing.expect(fg.handleKey(tab));
    try std.testing.expectEqual(@as(usize, 1), fg.focused());
}

test "FocusGroup — setNextKey replaces defaults" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    // Replace Tab with Down arrow only
    fg.setNextKey(.{ .key = .down });

    // Tab should no longer work
    const tab = zz.KeyEvent{ .key = .tab, .modifiers = .{} };
    try std.testing.expect(!fg.handleKey(tab));

    // Down should work
    const down = zz.KeyEvent{ .key = .down, .modifiers = .{} };
    try std.testing.expect(fg.handleKey(down));
    try std.testing.expectEqual(@as(usize, 1), fg.focused());
}

test "FocusGroup — clearNextKeys removes all bindings" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    fg.clearNextKeys();

    // Tab no longer works
    const tab = zz.KeyEvent{ .key = .tab, .modifiers = .{} };
    try std.testing.expect(!fg.handleKey(tab));
}

test "FocusGroup — modifier matching is exact" {
    var a = TestItem{};
    var b = TestItem{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&a);
    fg.add(&b);
    fg.initFocus();

    // Ctrl+Tab should NOT match default Tab binding
    const ctrl_tab = zz.KeyEvent{ .key = .tab, .modifiers = .{ .ctrl = true } };
    try std.testing.expect(!fg.handleKey(ctrl_tab));

    // Alt+Tab should NOT match
    const alt_tab = zz.KeyEvent{ .key = .tab, .modifiers = .{ .alt = true } };
    try std.testing.expect(!fg.handleKey(alt_tab));

    // Plain Tab still works
    const tab = zz.KeyEvent{ .key = .tab, .modifiers = .{} };
    try std.testing.expect(fg.handleKey(tab));
}

test "FocusGroup — addNextKey returns false when full" {
    var a = TestItem{};

    var fg: zz.FocusGroup(1) = .{};
    fg.add(&a);
    fg.initFocus();

    // Slot 0: Tab (default), fill remaining 3 slots
    try std.testing.expect(fg.addNextKey(.{ .key = .down }));
    try std.testing.expect(fg.addNextKey(.{ .key = .right }));
    try std.testing.expect(fg.addNextKey(.{ .key = .{ .char = 'j' } }));

    // 5th should fail (4 slots max)
    try std.testing.expect(!fg.addNextKey(.{ .key = .{ .char = 'n' } }));
}

test "KeyBind — matches with modifiers" {
    const bind = zz.KeyBind{ .key = .{ .char = 'n' }, .modifiers = .{ .ctrl = true } };

    // Exact match
    const match = zz.KeyEvent{ .key = .{ .char = 'n' }, .modifiers = .{ .ctrl = true } };
    try std.testing.expect(bind.matches(match));

    // Missing modifier
    const no_mod = zz.KeyEvent{ .key = .{ .char = 'n' }, .modifiers = .{} };
    try std.testing.expect(!bind.matches(no_mod));

    // Extra modifier
    const extra = zz.KeyEvent{ .key = .{ .char = 'n' }, .modifiers = .{ .ctrl = true, .shift = true } };
    try std.testing.expect(!bind.matches(extra));

    // Wrong key
    const wrong = zz.KeyEvent{ .key = .{ .char = 'x' }, .modifiers = .{ .ctrl = true } };
    try std.testing.expect(!bind.matches(wrong));
}

// ---------------------------------------------------------------------------
// Mixed concrete types in one FocusGroup
// ---------------------------------------------------------------------------

test "FocusGroup — heterogeneous items" {
    const Alpha = struct {
        focused: bool = false,
        value: u32 = 42,
        pub fn focus(self: *@This()) void {
            self.focused = true;
        }
        pub fn blur(self: *@This()) void {
            self.focused = false;
        }
    };

    const Beta = struct {
        focused: bool = false,
        name: []const u8 = "beta",
        pub fn focus(self: *@This()) void {
            self.focused = true;
        }
        pub fn blur(self: *@This()) void {
            self.focused = false;
        }
    };

    var alpha = Alpha{};
    var beta = Beta{};

    var fg: zz.FocusGroup(2) = .{};
    fg.add(&alpha);
    fg.add(&beta);
    fg.initFocus();

    try std.testing.expect(alpha.focused);
    try std.testing.expect(!beta.focused);

    fg.focusNext();
    try std.testing.expect(!alpha.focused);
    try std.testing.expect(beta.focused);

    // Original data preserved
    try std.testing.expectEqual(@as(u32, 42), alpha.value);
    try std.testing.expectEqualStrings("beta", beta.name);
}
