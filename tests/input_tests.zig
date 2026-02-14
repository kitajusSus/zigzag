//! Input handling tests

const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "Key parsing - single character" {
    const result = zz.input.keyboard.parse("a");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .char);
    try testing.expectEqual(@as(u21, 'a'), result.result.key.key.char);
    try testing.expectEqual(@as(usize, 1), result.consumed);
}

test "Key parsing - escape key" {
    const result = zz.input.keyboard.parse("\x1b");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .escape);
    try testing.expectEqual(@as(usize, 1), result.consumed);
}

test "Key parsing - arrow up" {
    const result = zz.input.keyboard.parse("\x1b[A");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .up);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow down" {
    const result = zz.input.keyboard.parse("\x1b[B");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .down);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow right" {
    const result = zz.input.keyboard.parse("\x1b[C");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .right);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - arrow left" {
    const result = zz.input.keyboard.parse("\x1b[D");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .left);
    try testing.expectEqual(@as(usize, 3), result.consumed);
}

test "Key parsing - backspace" {
    const result = zz.input.keyboard.parse("\x7f");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .backspace);
}

test "Key parsing - enter" {
    const result = zz.input.keyboard.parse("\x0d");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .enter);
}

test "Key parsing - function keys" {
    const f1 = zz.input.keyboard.parse("\x1bOP");
    try testing.expect(f1.result == .key);
    try testing.expect(f1.result.key.key == .f1);

    const f2 = zz.input.keyboard.parse("\x1bOQ");
    try testing.expect(f2.result == .key);
    try testing.expect(f2.result.key.key == .f2);
}

test "Key parsing - delete" {
    const result = zz.input.keyboard.parse("\x1b[3~");
    try testing.expect(result.result == .key);
    try testing.expect(result.result.key.key == .delete);
}

test "Key parsing - home/end" {
    const home = zz.input.keyboard.parse("\x1b[H");
    try testing.expect(home.result == .key);
    try testing.expect(home.result.key.key == .home);

    const end = zz.input.keyboard.parse("\x1b[F");
    try testing.expect(end.result == .key);
    try testing.expect(end.result.key.key == .end);
}

test "Key parsing - page up/down" {
    const pgup = zz.input.keyboard.parse("\x1b[5~");
    try testing.expect(pgup.result == .key);
    try testing.expect(pgup.result.key.key == .page_up);

    const pgdn = zz.input.keyboard.parse("\x1b[6~");
    try testing.expect(pgdn.result == .key);
    try testing.expect(pgdn.result.key.key == .page_down);
}

test "Modifiers struct" {
    const none = zz.Modifiers.none;
    try testing.expect(!none.any());

    const ctrl = zz.Modifiers{ .ctrl = true };
    try testing.expect(ctrl.any());
    try testing.expect(ctrl.ctrl);
    try testing.expect(!ctrl.alt);
}

test "KeyEvent format" {
    const allocator = testing.allocator;

    const event = zz.KeyEvent{
        .key = .{ .char = 'a' },
        .modifiers = .{ .ctrl = true },
    };

    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();

    try event.format("", .{}, buf.writer());
    try testing.expectEqualStrings("ctrl+a", buf.items);
}

test "parseAll multiple keys" {
    const allocator = testing.allocator;

    const events = try zz.input.keyboard.parseAll(allocator, "abc");
    defer allocator.free(events);

    try testing.expectEqual(@as(usize, 3), events.len);
    try testing.expect(events[0] == .key);
    try testing.expectEqual(@as(u21, 'a'), events[0].key.key.char);
}

test "TextInput accepts multi-character paste commits (IME-like)" {
    var input = zz.TextInput.init(testing.allocator);
    defer input.deinit();

    input.handleKey(.{ .key = .{ .paste = "中文输入" } });

    try testing.expectEqualStrings("中文输入", input.getValue());
}

test "TextArea accepts multi-character paste commits (IME-like)" {
    var area = zz.TextArea.init(testing.allocator);
    defer area.deinit();

    area.handleKey(.{ .key = .{ .paste = "中文输入" } });

    const value = try area.getValue(testing.allocator);
    defer testing.allocator.free(value);
    try testing.expectEqualStrings("中文输入", value);
}
