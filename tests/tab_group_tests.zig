const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

fn stripAnsi(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == 0x1b) {
            i += 1;
            if (i < text.len and text[i] == '[') {
                i += 1;
                while (i < text.len) : (i += 1) {
                    const c = text[i];
                    if (c >= 0x40 and c <= 0x7E) {
                        i += 1;
                        break;
                    }
                }
            }
            continue;
        }

        try out.append(text[i]);
        i += 1;
    }
    return out.toOwnedSlice();
}

test "TabGroup addTab initializes active and focused tabs" {
    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    _ = try tabs.addTab(.{ .id = "a", .title = "Alpha" });
    _ = try tabs.addTab(.{ .id = "b", .title = "Beta" });

    try testing.expectEqual(@as(?usize, 0), tabs.activeIndex());
    try testing.expectEqual(@as(?usize, 0), tabs.focusedIndex());
}

test "TabGroup handleKey cycles next/prev with wrapping" {
    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    _ = try tabs.addTab(.{ .id = "a", .title = "A" });
    _ = try tabs.addTab(.{ .id = "b", .title = "B" });

    const next = tabs.handleKey(.{ .key = .right });
    try testing.expect(next.consumed);
    try testing.expectEqual(@as(?usize, 1), tabs.activeIndex());

    const prev = tabs.handleKey(.{ .key = .left });
    try testing.expect(prev.consumed);
    try testing.expectEqual(@as(?usize, 0), tabs.activeIndex());

    _ = tabs.handleKey(.{ .key = .left });
    try testing.expectEqual(@as(?usize, 1), tabs.activeIndex());
}

test "TabGroup skips hidden/disabled tabs when navigating" {
    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    _ = try tabs.addTab(.{ .id = "a", .title = "A" });
    _ = try tabs.addTab(.{ .id = "b", .title = "B", .enabled = false });
    _ = try tabs.addTab(.{ .id = "c", .title = "C", .visible = false });
    _ = try tabs.addTab(.{ .id = "d", .title = "D" });

    _ = tabs.handleKey(.{ .key = .right });
    try testing.expectEqual(@as(?usize, 3), tabs.activeIndex());
}

test "TabGroup manual activation separates focus and active" {
    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    tabs.activate_on_focus = false;

    _ = try tabs.addTab(.{ .id = "a", .title = "A" });
    _ = try tabs.addTab(.{ .id = "b", .title = "B" });

    _ = tabs.handleKey(.{ .key = .right });
    try testing.expectEqual(@as(?usize, 0), tabs.activeIndex());
    try testing.expectEqual(@as(?usize, 1), tabs.focusedIndex());

    _ = tabs.handleKey(.{ .key = .enter });
    try testing.expectEqual(@as(?usize, 1), tabs.activeIndex());
}

test "TabGroup number shortcuts target visible enabled tabs" {
    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    tabs.show_numbers = true;
    _ = try tabs.addTab(.{ .id = "a", .title = "A" });
    _ = try tabs.addTab(.{ .id = "b", .title = "B", .visible = false });
    _ = try tabs.addTab(.{ .id = "c", .title = "C", .enabled = false });
    _ = try tabs.addTab(.{ .id = "d", .title = "D" });

    _ = tabs.handleKey(.{ .key = .{ .char = '2' } });
    try testing.expectEqual(@as(?usize, 3), tabs.activeIndex());
}

test "TabGroup remove active chooses fallback tab" {
    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    _ = try tabs.addTab(.{ .id = "a", .title = "A" });
    _ = try tabs.addTab(.{ .id = "b", .title = "B" });
    _ = try tabs.addTab(.{ .id = "c", .title = "C" });

    _ = tabs.setActive(1, .set_active);
    const change = tabs.removeTabAt(1);
    try testing.expect(change != null);
    try testing.expectEqual(@as(?usize, 1), tabs.activeIndex());
    try testing.expectEqualStrings("c", tabs.activeTab().?.id);
}

const RouteState = struct {
    enter_count: usize = 0,
    leave_count: usize = 0,
    routed_count: usize = 0,
    text: []const u8,
};

fn routeRender(ctx: *anyopaque, allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    const state: *RouteState = @ptrCast(@alignCast(ctx));
    return state.text;
}

fn routeKey(ctx: *anyopaque, event: zz.KeyEvent) bool {
    const state: *RouteState = @ptrCast(@alignCast(ctx));
    if (event.key == .char and event.key.char == 'x') {
        state.routed_count += 1;
        return true;
    }
    return false;
}

fn routeEnter(ctx: *anyopaque) void {
    const state: *RouteState = @ptrCast(@alignCast(ctx));
    state.enter_count += 1;
}

fn routeLeave(ctx: *anyopaque) void {
    const state: *RouteState = @ptrCast(@alignCast(ctx));
    state.leave_count += 1;
}

test "TabGroup route enter/leave hooks fire on active change" {
    var a = RouteState{ .text = "A" };
    var b = RouteState{ .text = "B" };

    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    _ = try tabs.addTab(.{
        .id = "a",
        .title = "A",
        .route = .{
            .ctx = &a,
            .render_fn = routeRender,
            .on_enter_fn = routeEnter,
            .on_leave_fn = routeLeave,
        },
    });
    _ = try tabs.addTab(.{
        .id = "b",
        .title = "B",
        .route = .{
            .ctx = &b,
            .render_fn = routeRender,
            .on_enter_fn = routeEnter,
            .on_leave_fn = routeLeave,
        },
    });

    try testing.expectEqual(@as(usize, 1), a.enter_count);
    _ = tabs.setActive(1, .set_active);
    try testing.expectEqual(@as(usize, 1), a.leave_count);
    try testing.expectEqual(@as(usize, 1), b.enter_count);
}

test "TabGroup handleKeyAndRoute forwards unhandled keys" {
    var a = RouteState{ .text = "A" };

    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    _ = try tabs.addTab(.{
        .id = "a",
        .title = "A",
        .route = .{
            .ctx = &a,
            .render_fn = routeRender,
            .key_fn = routeKey,
        },
    });

    const res = tabs.handleKeyAndRoute(.{ .key = .{ .char = 'x' } });
    try testing.expect(res.consumed);
    try testing.expect(res.routed);
    try testing.expectEqual(@as(usize, 1), a.routed_count);
}

test "TabGroup viewWithContent renders tab strip and active route content" {
    var a = RouteState{ .text = "Screen A" };
    var b = RouteState{ .text = "Screen B" };

    var tabs = zz.TabGroup.init(testing.allocator);
    defer tabs.deinit();

    _ = try tabs.addTab(.{
        .id = "a",
        .title = "Alpha",
        .route = .{
            .ctx = &a,
            .render_fn = routeRender,
        },
    });
    _ = try tabs.addTab(.{
        .id = "b",
        .title = "Beta",
        .route = .{
            .ctx = &b,
            .render_fn = routeRender,
        },
    });

    tabs.max_width = 8;
    tabs.overflow_mode = .scroll;
    _ = tabs.setActive(1, .set_active);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const out = try tabs.viewWithContent(arena_alloc, null);

    const plain = try stripAnsi(testing.allocator, out);
    defer testing.allocator.free(plain);

    try testing.expect(std.mem.indexOf(u8, plain, "Beta") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "Screen B") != null);
}
