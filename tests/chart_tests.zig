const std = @import("std");
const testing = std.testing;
const zz = @import("zigzag");

test "sparkline buckets data with summary mode" {
    const allocator = testing.allocator;

    var spark = zz.Sparkline.init(allocator);
    defer spark.deinit();

    spark.setWidth(4);
    spark.setSummary(.average);
    spark.setRetentionLimit(null);
    spark.setStyle((zz.Style{}).inline_style(true));
    spark.setGlyphs(&.{ " ", ".", ":", "*", "#" });

    try spark.setData(&.{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const view = try spark.view(allocator);
    defer allocator.free(view);

    try testing.expectEqual(@as(usize, 4), zz.width(view));
    try testing.expect(std.mem.indexOfAny(u8, view, ".:*#") != null);
}

test "canvas renders braille dots" {
    const allocator = testing.allocator;

    var canvas = zz.Canvas.init(allocator);
    defer canvas.deinit();

    canvas.setSize(2, 1);
    canvas.setMarker(.braille);
    canvas.setRanges(.{ .min = 0, .max = 1 }, .{ .min = 0, .max = 1 });
    try canvas.drawPoint(0, 0);
    try canvas.drawPoint(1, 1);

    const view = try canvas.view(allocator);
    defer allocator.free(view);

    try testing.expect(zz.width(view) == 2);
    try testing.expect(!std.mem.eql(u8, view, "  "));
}

test "chart renders titles and legend" {
    const allocator = testing.allocator;

    var chart = zz.Chart.init(allocator);
    defer chart.deinit();

    chart.setSize(30, 10);
    chart.setMarker(.ascii);
    chart.setLegendPosition(.top);
    chart.x_axis = .{ .title = "Time", .tick_count = 3, .show_grid = true };
    chart.y_axis = .{ .title = "Load", .tick_count = 3, .show_grid = true };

    var dataset = try zz.ChartDataset.init(allocator, "CPU");
    dataset.setGraphType(.line);
    dataset.setShowPoints(true);
    dataset.setStyle((zz.Style{}).inline_style(true));
    try dataset.setPoints(&.{
        .{ .x = 0, .y = 10 },
        .{ .x = 1, .y = 40 },
        .{ .x = 2, .y = 25 },
    });
    try chart.addDataset(dataset);

    const view = try chart.view(allocator);
    defer allocator.free(view);
    const plain = try stripAnsi(allocator, view);
    defer allocator.free(plain);
    try testing.expect(std.mem.indexOf(u8, plain, "CPU") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "Time") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "Load") != null);
}

test "chart dataset supports curved interpolation modes" {
    const allocator = testing.allocator;

    var chart = zz.Chart.init(allocator);
    defer chart.deinit();

    chart.setSize(32, 12);
    chart.setMarker(.ascii);
    chart.x_axis = .{ .tick_count = 4 };
    chart.y_axis = .{ .tick_count = 4 };

    var smooth = try zz.ChartDataset.init(allocator, "smooth");
    smooth.setGraphType(.line);
    smooth.setInterpolation(.monotone_cubic);
    smooth.setInterpolationSteps(12);
    try smooth.setPoints(&.{
        .{ .x = 0, .y = 10 },
        .{ .x = 1, .y = 35 },
        .{ .x = 2, .y = 18 },
        .{ .x = 3, .y = 42 },
    });
    try chart.addDataset(smooth);

    var stepped = try zz.ChartDataset.init(allocator, "step");
    stepped.setGraphType(.line);
    stepped.setInterpolation(.step_center);
    try stepped.setPoints(&.{
        .{ .x = 0, .y = 8 },
        .{ .x = 1, .y = 14 },
        .{ .x = 2, .y = 9 },
        .{ .x = 3, .y = 20 },
    });
    try chart.addDataset(stepped);

    const view = try chart.view(allocator);
    defer allocator.free(view);
    const plain = try stripAnsi(allocator, view);
    defer allocator.free(plain);

    try testing.expect(std.mem.indexOf(u8, plain, "smooth") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "step") != null);
}

test "horizontal bar chart supports negative values" {
    const allocator = testing.allocator;

    var chart = zz.BarChart.init(allocator);
    defer chart.deinit();

    chart.setSize(24, 6);
    chart.setOrientation(.horizontal);
    chart.show_values = true;
    chart.label_style = (zz.Style{}).inline_style(true);
    chart.axis_style = (zz.Style{}).inline_style(true);
    try chart.addBar(try zz.Bar.init(allocator, "api", 12));
    try chart.addBar(try zz.Bar.init(allocator, "db", -8));

    const view = try chart.view(allocator);
    defer allocator.free(view);
    const plain = try stripAnsi(allocator, view);
    defer allocator.free(plain);

    try testing.expect(std.mem.indexOf(u8, plain, "api") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "db") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "│") != null);
}

fn stripAnsi(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    defer out.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b) {
            i += 1;
            if (i < input.len and input[i] == '[') {
                i += 1;
                while (i < input.len) : (i += 1) {
                    const c = input[i];
                    if ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                        i += 1;
                        break;
                    }
                }
                continue;
            }
        }

        try out.append(input[i]);
        i += 1;
    }

    return try out.toOwnedSlice();
}
