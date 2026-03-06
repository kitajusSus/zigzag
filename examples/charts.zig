//! Charts example showcasing line charts, bar charts, sparklines, and the plotting canvas.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    chart: zz.Chart,
    bars: zz.BarChart,
    spark: zz.Sparkline,
    phase: f64,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
        tick: zz.msg.Tick,
    };

    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.chart = zz.Chart.init(ctx.persistent_allocator);
        self.chart.setSize(44, 16);
        self.chart.setMarker(.braille);
        self.chart.setLegendPosition(.top);
        self.chart.x_axis = .{
            .title = "Time",
            .tick_count = 5,
            .show_grid = true,
        };
        self.chart.y_axis = .{
            .title = "Load",
            .tick_count = 5,
            .show_grid = true,
        };

        var cpu = zz.ChartDataset.init(ctx.persistent_allocator, "CPU") catch unreachable;
        cpu.setStyle((zz.Style{}).fg(zz.Color.cyan()).bold(true));
        cpu.setShowPoints(true);
        var mem = zz.ChartDataset.init(ctx.persistent_allocator, "Memory") catch unreachable;
        mem.setStyle((zz.Style{}).fg(zz.Color.magenta()));

        for (0..24) |i| {
            const x = @as(f64, @floatFromInt(i));
            cpu.appendPoint(.{ .x = x, .y = 55.0 + @sin(x / 3.0) * 18.0 }) catch unreachable;
            mem.appendPoint(.{ .x = x, .y = 40.0 + @cos(x / 4.0) * 14.0 }) catch unreachable;
        }

        self.chart.addDataset(cpu) catch unreachable;
        self.chart.addDataset(mem) catch unreachable;

        self.bars = zz.BarChart.init(ctx.persistent_allocator);
        self.bars.setSize(30, 12);
        self.bars.setOrientation(.horizontal);
        self.bars.show_values = true;
        self.bars.label_style = (zz.Style{}).fg(zz.Color.gray(18)).inline_style(true);
        self.bars.positive_style = (zz.Style{}).fg(zz.Color.green()).inline_style(true);
        self.bars.negative_style = (zz.Style{}).fg(zz.Color.red()).inline_style(true);
        self.bars.axis_style = (zz.Style{}).fg(zz.Color.gray(10)).inline_style(true);
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "api", 31) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "db", -12) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "queue", 22) catch unreachable) catch unreachable;
        self.bars.addBar(zz.Bar.init(ctx.persistent_allocator, "cache", 14) catch unreachable) catch unreachable;

        self.spark = zz.Sparkline.init(ctx.persistent_allocator);
        self.spark.setWidth(28);
        self.spark.setSummary(.average);
        self.spark.setRetentionLimit(120);
        self.spark.setGradient(zz.Color.hex("#F97316"), zz.Color.hex("#22C55E"));

        for (0..60) |i| {
            const x = @as(f64, @floatFromInt(i));
            self.spark.push(30.0 + 10.0 * @sin(x / 5.0)) catch unreachable;
        }

        self.phase = 0;
        return zz.Cmd(Msg).tickMs(80);
    }

    pub fn deinit(self: *Model) void {
        self.chart.deinit();
        self.bars.deinit();
        self.spark.deinit();
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |key| switch (key.key) {
                .char => |c| if (c == 'q') return .quit,
                .escape => return .quit,
                else => {},
            },
            .tick => {
                self.phase += 1.0;

                var cpu = &self.chart.datasets.items[0];
                var mem = &self.chart.datasets.items[1];
                if (cpu.points.items.len >= 32) _ = cpu.points.orderedRemove(0);
                if (mem.points.items.len >= 32) _ = mem.points.orderedRemove(0);

                const next_x = if (cpu.points.items.len == 0) 0.0 else cpu.points.items[cpu.points.items.len - 1].x + 1.0;
                cpu.appendPoint(.{ .x = next_x, .y = 55.0 + @sin((self.phase + next_x) / 3.0) * 18.0 }) catch {};
                mem.appendPoint(.{ .x = next_x, .y = 40.0 + @cos((self.phase + next_x) / 4.0) * 14.0 }) catch {};
                self.chart.x_axis.bounds = .{ .min = @max(0.0, next_x - 31.0), .max = next_x };

                self.spark.push(30.0 + 10.0 * @sin((self.phase + next_x) / 5.0)) catch {};

                self.bars.bars.items[0].value = 20.0 + @sin(self.phase / 3.0) * 18.0;
                self.bars.bars.items[1].value = -5.0 - @cos(self.phase / 4.0) * 15.0;
                self.bars.bars.items[2].value = 12.0 + @sin(self.phase / 5.0) * 12.0;
                self.bars.bars.items[3].value = 8.0 + @cos(self.phase / 6.0) * 10.0;

                return zz.Cmd(Msg).tickMs(80);
            },
        }

        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const line_chart = self.chart.view(ctx.allocator) catch "";
        const bars = self.bars.view(ctx.allocator) catch "";
        const spark = self.spark.view(ctx.allocator) catch "";
        const canvas = self.renderCanvas(ctx) catch "";

        const top = zz.joinHorizontal(ctx.allocator, &.{
            box(ctx, "Trend", line_chart) catch line_chart,
            "  ",
            box(ctx, "Bars", bars) catch bars,
        }) catch line_chart;
        const bottom = zz.joinHorizontal(ctx.allocator, &.{
            box(ctx, "Sparkline", spark) catch spark,
            "  ",
            box(ctx, "Canvas", canvas) catch canvas,
        }) catch spark;

        const content = zz.joinVertical(ctx.allocator, &.{ top, "", bottom, "", "Press q to quit" }) catch top;
        return zz.place.place(ctx.allocator, ctx.width, ctx.height, .center, .middle, content) catch content;
    }

    fn renderCanvas(self: *const Model, ctx: *const zz.Context) ![]const u8 {
        var canvas = zz.Canvas.init(ctx.allocator);
        defer canvas.deinit();

        canvas.setSize(28, 10);
        canvas.setMarker(.braille);
        canvas.setRanges(.{ .min = -1.2, .max = 1.2 }, .{ .min = -1.2, .max = 1.2 });

        var point_style = zz.Style{};
        point_style = point_style.fg(zz.Color.yellow());
        point_style = point_style.inline_style(true);

        for (0..80) |i| {
            const t = self.phase / 10.0 + @as(f64, @floatFromInt(i)) / 18.0;
            const x = @sin(t * 1.7);
            const y = @cos(t * 2.3);
            try canvas.drawPointStyled(x, y, point_style, null);
        }

        return try canvas.view(ctx.allocator);
    }
};

fn box(ctx: *const zz.Context, title: []const u8, body: []const u8) ![]const u8 {
    var style = zz.Style{};
    style = style.borderAll(zz.Border.rounded);
    style = style.borderForeground(zz.Color.gray(12));
    style = style.paddingAll(1);

    var header_style = zz.Style{};
    header_style = header_style.bold(true);
    header_style = header_style.fg(zz.Color.cyan());
    header_style = header_style.inline_style(true);
    const header = try header_style.render(ctx.allocator, title);

    const content = try std.fmt.allocPrint(ctx.allocator, "{s}\n\n{s}", .{ header, body });
    return try style.render(ctx.allocator, content);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();
    try program.run();
}
