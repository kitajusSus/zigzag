//! ZigZag Hello World Example
//! A minimal example showing the basic structure of a ZigZag application.

const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    kitty_supported: bool,
    image_attempted: bool,
    image_path: []const u8,

    /// The message type for this model
    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    /// Initialize the model
    pub fn init(self: *Model, ctx: *zz.Context) zz.Cmd(Msg) {
        self.* = .{
            .kitty_supported = ctx.supportsKittyGraphics(),
            .image_attempted = false,
            .image_path = "/tmp/cat.png",
        };
        return .none;
    }

    /// Handle messages and update state
    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| {
                // Quit on 'q' or Escape
                switch (k.key) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'i' => {
                            self.image_attempted = true;
                            if (self.kitty_supported) {
                                return .{ .kitty_image_file = .{
                                    .path = self.image_path,
                                    .width_cells = 32,
                                    .height_cells = 16,
                                } };
                            }
                        },
                        else => {},
                    },
                    .escape => return .quit,
                    else => {},
                }
            },
        }
        return .none;
    }

    /// Render the view
    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        var title_style = zz.Style{};
        title_style = title_style.bold(true);
        title_style = title_style.fg(zz.Color.cyan());
        title_style = title_style.inline_style(true);

        var subtitle_style = zz.Style{};
        subtitle_style = subtitle_style.fg(zz.Color.gray(18));
        subtitle_style = subtitle_style.inline_style(true);

        var hint_style = zz.Style{};
        hint_style = hint_style.italic(true);
        hint_style = hint_style.fg(zz.Color.gray(12));
        hint_style = hint_style.inline_style(true);

        var image_hint_style = zz.Style{};
        image_hint_style = image_hint_style.fg(zz.Color.gray(16));
        image_hint_style = image_hint_style.inline_style(true);

        const title = title_style.render(ctx.allocator, "Hello, ZigZag!") catch "Hello, ZigZag!";
        const subtitle = subtitle_style.render(ctx.allocator, "A TUI library for Zig") catch "";
        const hint = hint_style.render(ctx.allocator, "Press 'q' to quit") catch "";

        const image_hint_text = if (self.kitty_supported)
            "Press 'i' to draw /tmp/cat.png via Kitty graphics"
        else
            "Kitty graphics not detected in this terminal";
        const image_hint = image_hint_style.render(ctx.allocator, image_hint_text) catch image_hint_text;

        const status_text = if (self.image_attempted and self.kitty_supported)
            "Image command sent (check /tmp/cat.png path)"
        else if (self.image_attempted and !self.kitty_supported)
            "Image skipped: Kitty graphics unsupported"
        else
            "";
        const status = hint_style.render(ctx.allocator, status_text) catch status_text;

        // Get max width for centering
        const title_width = zz.measure.width(title);
        const subtitle_width = zz.measure.width(subtitle);
        const hint_width = zz.measure.width(hint);
        const image_hint_width = zz.measure.width(image_hint);
        const status_width = zz.measure.width(status);
        const max_width = @max(
            title_width,
            @max(
                subtitle_width,
                @max(hint_width, @max(image_hint_width, status_width)),
            ),
        );

        // Center each element
        const centered_title = zz.place.place(ctx.allocator, max_width, 1, .center, .top, title) catch title;
        const centered_subtitle = zz.place.place(ctx.allocator, max_width, 1, .center, .top, subtitle) catch subtitle;
        const centered_hint = zz.place.place(ctx.allocator, max_width, 1, .center, .top, hint) catch hint;
        const centered_image_hint = zz.place.place(ctx.allocator, max_width, 1, .center, .top, image_hint) catch image_hint;
        const centered_status = zz.place.place(ctx.allocator, max_width, 1, .center, .top, status) catch status;

        const content = std.fmt.allocPrint(
            ctx.allocator,
            "{s}\n\n{s}\n\n{s}\n{s}\n{s}",
            .{ centered_title, centered_subtitle, centered_hint, centered_image_hint, centered_status },
        ) catch "Error rendering view";

        // Center in terminal
        return zz.place.place(
            ctx.allocator,
            ctx.width,
            ctx.height,
            .center,
            .middle,
            content,
        ) catch content;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();

    try program.run();
}
