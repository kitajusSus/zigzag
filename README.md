# ZigZag

A delightful TUI framework for Zig, inspired by [Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lipgloss](https://github.com/charmbracelet/lipgloss).

![Demo](assets/showcase.gif)

## Features

- **Elm Architecture** - Model-Update-View pattern for predictable state management
- **Rich Styling** - Comprehensive styling system with colors, borders, padding, margin backgrounds, per-side border colors, tab width control, style ranges, full style inheritance, text transforms, whitespace formatting controls, and unset methods
- **16 Pre-built Components** - TextInput (with autocomplete/word movement), TextArea, List (fuzzy filtering), Table (interactive with row selection), Viewport, Progress (color gradients), Spinner, Tree, StyledList, Sparkline, Notification/Toast, Confirm dialog, Help, Paginator, Timer, FilePicker
- **Keybinding Management** - Structured `KeyBinding`/`KeyMap` with matching, display formatting, and Help component integration
- **Color System** - ANSI 16, 256, and TrueColor with adaptive colors, color profile detection, and dark background detection
- **Command System** - Quit, tick, repeating tick (`every`), batch, sequence, suspend/resume, runtime terminal control (mouse, cursor, alt screen, title), print above program
- **Custom I/O** - Pipe-friendly with configurable input/output streams for testing and automation
- **Kitty Keyboard Protocol** - Modern keyboard handling with key release events and unambiguous key identification
- **Bracketed Paste** - Paste events delivered as a single message instead of individual keystrokes
- **Debug Logging** - File-based timestamped logging since stdout is owned by the renderer
- **Message Filtering** - Intercept and transform messages before they reach your model
- **ANSI Compression** - Reduce output overhead with diff-based style state tracking and redundant sequence elimination
- **Layout** - Horizontal/vertical joining, ANSI-aware measurement, 2D placement, float-based positioning, horizontal/vertical single-axis placement, overlay compositing
- **Cross-platform** - Works on macOS, Linux, and Windows
- **Zero Dependencies** - Pure Zig with no external dependencies

## Installation

Add ZigZag to your `build.zig.zon`:

```zig
.dependencies = .{
    .zigzag = .{
        .url = "https://github.com/meszmate/zigzag/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const zigzag = b.dependency("zigzag", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigzag", zigzag.module("zigzag"));
```

## Quick Start

```zig
const std = @import("std");
const zz = @import("zigzag");

const Model = struct {
    count: i32,

    pub const Msg = union(enum) {
        key: zz.KeyEvent,
    };

    pub fn init(self: *Model, _: *zz.Context) zz.Cmd(Msg) {
        self.* = .{ .count = 0 };
        return .none;
    }

    pub fn update(self: *Model, msg: Msg, _: *zz.Context) zz.Cmd(Msg) {
        switch (msg) {
            .key => |k| switch (k.key) {
                .char => |c| if (c == 'q') return .quit,
                .up => self.count += 1,
                .down => self.count -= 1,
                else => {},
            },
        }
        return .none;
    }

    pub fn view(self: *const Model, ctx: *const zz.Context) []const u8 {
        const style = zz.Style{}.bold(true).fg(zz.Color.cyan());
        const text = std.fmt.allocPrint(ctx.allocator, "Count: {d}\n\nPress q to quit", .{self.count}) catch "Error";
        return style.render(ctx.allocator, text) catch text;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var program = try zz.Program(Model).init(gpa.allocator());
    defer program.deinit();
    try program.run();
}
```

## Core Concepts

### The Elm Architecture

ZigZag uses the Elm Architecture (Model-Update-View):

1. **Model** - Your application state
2. **Msg** - Messages that describe state changes
3. **init** - Initialize your model
4. **update** - Handle messages and update state
5. **view** - Render your model to a string

### Commands

Commands let you perform side effects:

```zig
return .quit;                          // Quit the application
return .none;                          // Do nothing
return .{ .tick = ns };                // Request a tick after `ns` nanoseconds
return Cmd(Msg).everyMs(16);           // Repeating tick every 16ms (~60fps)
return Cmd(Msg).tickMs(1000);          // One-shot tick after 1 second
return .suspend_process;               // Suspend (like Ctrl+Z)
return .enable_mouse;                  // Enable mouse tracking at runtime
return .disable_mouse;                 // Disable mouse tracking
return .show_cursor;                   // Show terminal cursor
return .hide_cursor;                   // Hide terminal cursor
return .{ .set_title = "My App" };     // Set terminal window title
return .{ .println = "Log message" };  // Print above the program output
```

### Styling

The styling system is inspired by Lipgloss:

```zig
const style = zz.Style{}
    .bold(true)
    .italic(true)
    .fg(zz.Color.cyan())
    .bg(zz.Color.black())
    .paddingAll(1)
    .marginAll(2)
    .marginBackground(zz.Color.gray(3))
    .borderAll(zz.Border.rounded)
    .borderForeground(zz.Color.magenta())
    .borderTopForeground(zz.Color.cyan())    // Per-side border colors
    .borderBottomForeground(zz.Color.green())
    .tabWidth(4)
    .width(40)
    .alignH(.center);

const output = try style.render(allocator, "Hello, World!");

// Text transforms
const upper_style = zz.Style{}.transform(zz.transforms.uppercase);
const shouting = try upper_style.render(allocator, "hello"); // "HELLO"

// Whitespace formatting controls
const ws_style = zz.Style{}
    .underline(true)
    .setUnderlineSpaces(true)      // Underline extends through spaces
    .setColorWhitespace(false);     // Don't apply bg color to whitespace

// Unset individual properties
const derived = style.unsetBold().unsetPadding().unsetBorder();

// Style inheritance (unset values inherit from parent)
const child = zz.Style{}.fg(zz.Color.red()).inherit(style);

// Style ranges - apply different styles to byte ranges
const ranges = &[_]zz.StyleRange{
    .{ .start = 0, .end = 5, .s = zz.Style{}.bold(true) },
};
const ranged = try zz.renderWithRanges(allocator, "Hello World", ranges);

// Highlight specific positions (for fuzzy match results)
const highlighted = try zz.renderWithHighlights(allocator, "hello", &.{0, 2}, highlight_style, base_style);
```

### Colors

```zig
// Basic ANSI colors
zz.Color.red()
zz.Color.cyan()
zz.Color.brightGreen()

// 256-color palette
zz.Color.color256(123)
zz.Color.gray(15)  // 0-23 grayscale

// True color (24-bit)
zz.Color.fromRgb(255, 128, 64)
zz.Color.hex("#FF8040")

// Adaptive colors (change based on terminal capabilities)
const adaptive = zz.AdaptiveColor{
    .true_color = zz.Color.hex("#FF8040"),
    .color_256 = zz.Color.color256(208),
    .ansi = zz.Color.red(),
};
const resolved = adaptive.resolve(ctx.true_color, ctx.color_256);

// Color profile detection (automatic via context)
// ctx.color_profile: .ascii, .ansi, .ansi256, .true_color
// ctx.is_dark_background: bool

// Color interpolation (for gradients)
const mid = zz.interpolateColor(zz.Color.red(), zz.Color.green(), 0.5);
```

### Borders

```zig
zz.Border.normal           // ┌─┐
zz.Border.rounded          // ╭─╮
zz.Border.double           // ╔═╗
zz.Border.thick            // ┏━┓
zz.Border.ascii            // +-+
zz.Border.block            // ███
zz.Border.dashed           // ┌╌┐
zz.Border.dotted           // ┌┈┐
zz.Border.inner_half_block // ▗▄▖
zz.Border.outer_half_block // ▛▀▜
zz.Border.markdown         // |-|
```

## Components

### TextInput

Single-line text input with cursor, validation, autocomplete, and word-level movement:

```zig
var input = zz.TextInput.init(allocator);
input.setPlaceholder("Enter name...");
input.setPrompt("> ");
input.setSuggestions(&.{ "hello", "help", "world" }); // Tab to accept
// Supports: Alt+Left/Right for word movement, Ctrl+W delete word
input.handleKey(key_event);
const view = try input.view(allocator);
```

### TextArea

Multi-line text editor:

```zig
var editor = zz.components.TextArea.init(allocator);
editor.setSize(80, 24);
editor.line_numbers = true;
editor.handleKey(key_event);
```

### List

Selectable list with fuzzy filtering and status bar:

```zig
var list = zz.List(MyItem).init(allocator);
list.multi_select = true;
list.show_item_count = true;  // Shows "3/10 items"
try list.addItem(.init(item, "Item 1"));
// Fuzzy filtering: press / to filter, matches score by consecutive chars
list.handleKey(key_event);
```

### Viewport

Scrollable content area:

```zig
var viewport = zz.Viewport.init(allocator, 80, 24);
try viewport.setContent(long_text);
viewport.handleKey(key_event);  // Supports j/k, Page Up/Down, etc.
```

### Progress

Progress bar with optional color gradients:

```zig
var progress = zz.Progress.init();
progress.setWidth(40);
progress.setGradient(zz.Color.hex("#FF6B6B"), zz.Color.hex("#4ECDC4"));
progress.setPercent(75);
const bar = try progress.view(allocator);
```

### Spinner

Animated loading indicator:

```zig
var spinner = zz.Spinner.init();
spinner.update(elapsed_ns);
const view = try spinner.viewWithTitle(allocator, "Loading...");
```

### Table

Interactive tabular data display with row selection and navigation:

```zig
var table = zz.Table(3).init(allocator);
table.setHeaders(.{ "Name", "Age", "City" });
try table.addRow(.{ "Alice", "30", "NYC" });
try table.addRow(.{ "Bob", "25", "LA" });
table.focus();  // Enable interactive mode
table.show_row_borders = true;  // Horizontal separators between rows
// Supports: j/k, up/down, pgup/pgdown, g/G for navigation
table.handleKey(key_event);
const selected = table.selectedRow();  // Get highlighted row index
```

### Tree

Hierarchical tree view with customizable enumerators:

```zig
var tree = zz.Tree(void).init(allocator);
const root = try tree.addRoot({}, "project/");
const src = try tree.addChild(root, {}, "src/");
_ = try tree.addChild(src, {}, "main.zig");
const view = try tree.view(allocator);
// Output:
// project/
// └── src/
//     └── main.zig
```

### StyledList

Rendering list with enumerators (bullet, arabic, roman, alphabet):

```zig
var list = zz.StyledList.init(allocator);
list.setEnumerator(.roman);
try list.addItem("First item");
try list.addItem("Second item");
try list.addItemNested("Sub-item", 1);
// Output:
// I. First item
// II. Second item
//   I. Sub-item
```

### Sparkline

Mini chart using Unicode block elements:

```zig
var spark = zz.Sparkline.init(allocator);
spark.setWidth(20);
try spark.push(10.0);
try spark.push(25.0);
try spark.push(15.0);
const chart = try spark.view(allocator);
```

### Notification/Toast

Auto-dismissing timed messages with severity levels:

```zig
var notifs = zz.Notification.init(allocator);
try notifs.push("Build complete!", .success, 3000, current_ns);
notifs.update(current_ns);  // Removes expired notifications
const view = try notifs.view(allocator);
```

### Confirm

Simple yes/no confirmation dialog:

```zig
var confirm = zz.Confirm.init("Are you sure?");
confirm.show();
confirm.handleKey(key_event);  // Left/Right, Enter, y/n
if (confirm.result()) |yes| {
    if (yes) { /* confirmed */ }
}
```

### More Components

- **Help** - Display key bindings with responsive truncation
- **Paginator** - Pagination controls
- **Timer** - Countdown/stopwatch with warning thresholds
- **FilePicker** - File system navigation

### Keybinding Management

Structured key binding definitions with matching and Help integration:

```zig
var keymap = zz.KeyMap.init(allocator);
defer keymap.deinit();

try keymap.addChar('q', "Quit");
try keymap.addCtrl('s', "Save");
try keymap.add(.{
    .key_event = zz.KeyEvent{ .key = .up },
    .description = "Move up",
    .short_desc = "up",
});

// Check if a key event matches any binding
if (keymap.match(key_event)) |binding| {
    // Handle the matched binding
    _ = binding.description;
}

// Generate help text from keybindings
var help = try zz.components.Help.fromKeyMap(allocator, &keymap);
defer help.deinit();
const help_view = try help.view(allocator);
```

## Options

Configure the program with custom options:

```zig
var program = try zz.Program(Model).initWithOptions(gpa.allocator(), .{
    .fps = 60,                  // Target frame rate
    .alt_screen = true,         // Use alternate screen buffer
    .mouse = false,             // Enable mouse tracking
    .cursor = false,            // Show cursor
    .bracketed_paste = true,    // Enable bracketed paste mode
    .kitty_keyboard = false,    // Enable Kitty keyboard protocol
    .suspend_enabled = true,    // Enable Ctrl+Z suspend/resume
    .title = "My App",         // Window title
    .log_file = "debug.log",   // Debug log file path
    .input = custom_stdin,      // Custom input (for testing/piping)
    .output = custom_stdout,    // Custom output (for testing/piping)
});
```

### Debug Logging

Since stdout is owned by the renderer, use file-based logging:

```zig
// In your update function, log via context:
pub fn update(self: *Model, msg: Msg, ctx: *zz.Context) zz.Cmd(Msg) {
    ctx.log("received key: {s}", .{@tagName(msg)});
    // ...
}
```

### Message Filtering

Intercept and transform messages before they reach your model:

```zig
var program = try zz.Program(Model).init(gpa.allocator());
program.setFilter(&myFilter);

fn myFilter(msg: Model.Msg) ?Model.Msg {
    // Return null to drop the message, or modify it
    return msg;
}
```

### Bracketed Paste

Handle pasted text as a single event by adding a `paste` field to your Msg:

```zig
pub const Msg = union(enum) {
    key: zz.KeyEvent,
    paste: []const u8,  // Receives full pasted text
};
```

### Suspend/Resume

Ctrl+Z support is enabled by default. Handle resume events by adding a `resumed` field:

```zig
pub const Msg = union(enum) {
    key: zz.KeyEvent,
    resumed: void,  // Sent after process resumes from Ctrl+Z
};
```

## Layout

### Join

Combine multiple strings:

```zig
// Horizontal (side by side)
const row = try zz.joinHorizontal(allocator, &.{ left, middle, right });

// Vertical (stacked)
const col = try zz.joinVertical(allocator, &.{ top, middle, bottom });
```

### Measure

Get text dimensions (ANSI-aware):

```zig
const w = zz.width("Hello");           // 5
const h = zz.height("Line 1\nLine 2"); // 2
```

### Place

Position content in a bounding box:

```zig
// 2D placement in a bounding box
const centered = try zz.place.place(allocator, 80, 24, .center, .middle, content);

// Single-axis horizontal placement
const right_aligned = try zz.placeHorizontal(allocator, 80, .right, content);

// Single-axis vertical placement
const bottom_aligned = try zz.placeVertical(allocator, 24, .bottom, content);

// Float-based positioning (0.0 = left/top, 0.5 = center, 1.0 = right/bottom)
const placed = try zz.placeFloat(allocator, 80, 24, 0.75, 0.25, content);
```

## Examples

Run the examples:

```bash
zig build run-hello_world
zig build run-counter
zig build run-todo_list
zig build run-text_editor
zig build run-file_browser
zig build run-dashboard
zig build run-showcase       # Multi-tab demo of all features
```

## Building

```bash
# Build the library
zig build

# Run tests
zig build test

# Build with optimizations
zig build -Doptimize=ReleaseFast
```

## Cross-compilation

```bash
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-macos
zig build -Dtarget=x86_64-windows
```

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- [Bubble Tea](https://github.com/charmbracelet/bubbletea) - The original Go TUI framework
- [Lipgloss](https://github.com/charmbracelet/lipgloss) - Style definitions for terminal applications
- [The Elm Architecture](https://guide.elm-lang.org/architecture/) - The pattern that inspired it all
