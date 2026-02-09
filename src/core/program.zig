//! Program runtime for the ZigZag TUI framework.
//! Implements the Model-Update-View pattern with an event loop.

const std = @import("std");
const builtin = @import("builtin");
const Terminal = @import("../terminal/terminal.zig").Terminal;
const ansi = @import("../terminal/ansi.zig");
const keyboard = @import("../input/keyboard.zig");
const Context = @import("context.zig").Context;
const Options = @import("context.zig").Options;
const message = @import("message.zig");
const command = @import("command.zig");
const Logger = @import("log.zig").Logger;

pub const Cmd = command.Cmd;
pub const Msg = message;

/// Program runtime that manages the application lifecycle
pub fn Program(comptime Model: type) type {
    // Ensure Model has required declarations
    comptime {
        if (!@hasDecl(Model, "Msg")) {
            @compileError("Model must have a 'Msg' type declaration");
        }
        if (!@hasDecl(Model, "init")) {
            @compileError("Model must have an 'init' function");
        }
        if (!@hasDecl(Model, "update")) {
            @compileError("Model must have an 'update' function");
        }
        if (!@hasDecl(Model, "view")) {
            @compileError("Model must have a 'view' function");
        }
    }

    const UserMsg = Model.Msg;
    const UserCmd = Cmd(UserMsg);

    return struct {
        allocator: std.mem.Allocator,
        arena: std.heap.ArenaAllocator,
        model: Model,
        terminal: ?Terminal,
        context: Context,
        options: Options,
        running: bool,
        start_time: i128,
        last_frame_time: i128,
        pending_tick: ?u64,
        every_interval: ?u64,
        last_every_tick: u64,
        last_view_hash: u64,
        last_line_count: usize,
        logger: ?Logger,

        /// Message filter function
        filter: ?*const fn (UserMsg) ?UserMsg,

        const Self = @This();

        /// Initialize the program
        pub fn init(allocator: std.mem.Allocator) !Self {
            return initWithOptions(allocator, .{});
        }

        /// Initialize with custom options
        pub fn initWithOptions(allocator: std.mem.Allocator, options: Options) !Self {
            var arena = std.heap.ArenaAllocator.init(allocator);

            const self = Self{
                .allocator = allocator,
                .arena = arena,
                .model = undefined,
                .terminal = null,
                .context = Context.init(arena.allocator(), allocator),
                .options = options,
                .running = false,
                .start_time = std.time.nanoTimestamp(),
                .last_frame_time = std.time.nanoTimestamp(),
                .pending_tick = null,
                .every_interval = null,
                .last_every_tick = 0,
                .last_view_hash = 0,
                .last_line_count = 0,
                .logger = null,
                .filter = null,
            };

            return self;
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            if (self.terminal) |*term| {
                term.deinit();
            }
            if (self.logger) |*l| {
                l.deinit();
            }
            self.arena.deinit();

            // Call model's deinit if it exists
            if (@hasDecl(Model, "deinit")) {
                self.model.deinit();
            }
        }

        /// Set a message filter function
        pub fn setFilter(self: *Self, f: ?*const fn (UserMsg) ?UserMsg) void {
            self.filter = f;
        }

        /// Run the program
        pub fn run(self: *Self) !void {
            // Initialize logger if configured
            if (self.options.log_file) |log_path| {
                self.logger = Logger.init(log_path) catch null;
                if (self.logger != null) {
                    self.context._logger = &self.logger.?;
                }
            }

            // Initialize terminal
            self.terminal = try Terminal.init(.{
                .alt_screen = self.options.alt_screen,
                .hide_cursor = !self.options.cursor,
                .mouse = self.options.mouse,
                .bracketed_paste = self.options.bracketed_paste,
                .input = self.options.input,
                .output = self.options.output,
                .kitty_keyboard = self.options.kitty_keyboard,
            });

            // Set title if provided
            if (self.options.title) |title| {
                try self.terminal.?.setTitle(title);
            }

            // Get initial size
            const size = try self.terminal.?.getSize();
            self.context.width = size.cols;
            self.context.height = size.rows;
            self.context._terminal = &self.terminal.?;

            // Initialize the model
            const init_cmd = self.model.init(&self.context);
            try self.processCommand(init_cmd);

            self.running = true;

            // Main event loop
            while (self.running) {
                try self.tick();
            }
        }

        fn tick(self: *Self) !void {
            const now = std.time.nanoTimestamp();
            const delta = @as(u64, @intCast(now - self.last_frame_time));

            // Enforce framerate limit
            const min_frame_time_ns: u64 = if (self.options.fps > 0)
                @divFloor(std.time.ns_per_s, self.options.fps)
            else
                16_666_666; // ~60fps default

            if (delta < min_frame_time_ns) {
                std.Thread.sleep(min_frame_time_ns - delta);
            }

            self.last_frame_time = std.time.nanoTimestamp();
            const actual_delta = @as(u64, @intCast(self.last_frame_time - now + @as(i128, @intCast(delta))));

            self.context.delta = actual_delta;
            self.context.elapsed = @intCast(self.last_frame_time - self.start_time);
            self.context.frame += 1;

            // Reset arena for this frame
            _ = self.arena.reset(.retain_capacity);
            self.context.allocator = self.arena.allocator();

            // Check for resize
            if (self.terminal.?.checkResize()) {
                const size = try self.terminal.?.getSize();
                self.context.width = size.cols;
                self.context.height = size.rows;

                // Only send window_size message if the user model supports it
                if (@hasField(UserMsg, "window_size")) {
                    const cmd = self.dispatchToModel(.{ .window_size = .{
                        .width = size.cols,
                        .height = size.rows,
                    } });
                    try self.processCommand(cmd);
                }
            }

            // Read input
            var input_buf: [256]u8 = undefined;
            const bytes_read = try self.terminal.?.readInput(&input_buf, 16);

            if (bytes_read > 0) {
                const events = try keyboard.parseAll(self.context.allocator, input_buf[0..bytes_read]);
                for (events) |event| {
                    const user_cmd = switch (event) {
                        .key => |k| self.processKeyEvent(k),
                        .mouse => |m| self.processMouseEvent(m),
                        .none => null,
                    };
                    if (user_cmd) |cmd| {
                        try self.processCommand(cmd);
                    }
                }
            }

            // Handle pending tick
            if (self.pending_tick) |tick_ns| {
                if (self.context.elapsed >= tick_ns) {
                    self.pending_tick = null;
                    // Deliver tick to user's update if Model.Msg has a tick variant
                    if (@hasField(UserMsg, "tick")) {
                        const user_msg = UserMsg{ .tick = .{
                            .timestamp = @intCast(now),
                            .delta = delta,
                        } };
                        const cmd = self.dispatchToModel(user_msg);
                        try self.processCommand(cmd);
                    }
                }
            }

            // Handle repeating tick
            if (self.every_interval) |interval| {
                if (self.context.elapsed - self.last_every_tick >= interval) {
                    self.last_every_tick = self.context.elapsed;
                    if (@hasField(UserMsg, "tick")) {
                        const user_msg = UserMsg{ .tick = .{
                            .timestamp = @intCast(now),
                            .delta = delta,
                        } };
                        const cmd = self.dispatchToModel(user_msg);
                        try self.processCommand(cmd);
                    }
                }
            }

            // Render
            try self.render();
        }

        /// Dispatch a message to the model, applying the filter if set
        fn dispatchToModel(self: *Self, user_msg: UserMsg) UserCmd {
            if (self.filter) |f| {
                if (f(user_msg)) |filtered_msg| {
                    return self.model.update(filtered_msg, &self.context);
                }
                return .none;
            }
            return self.model.update(user_msg, &self.context);
        }

        fn processKeyEvent(self: *Self, key: keyboard.KeyEvent) ?UserCmd {
            // Check for Ctrl+C to quit
            if (key.modifiers.ctrl) {
                switch (key.key) {
                    .char => |c| {
                        if (c == 'c') {
                            self.running = false;
                            return null;
                        }
                        // Handle Ctrl+Z for suspend
                        if (c == 'z' and self.options.suspend_enabled) {
                            self.performSuspend();
                            return null;
                        }
                    },
                    else => {},
                }
            }

            // Handle paste events
            if (key.key == .paste) {
                if (@hasField(UserMsg, "paste")) {
                    const user_msg = UserMsg{ .paste = key.key.paste };
                    return self.dispatchToModel(user_msg);
                }
                // If model doesn't handle paste, send as individual key events
                if (@hasField(UserMsg, "key")) {
                    const user_msg = UserMsg{ .key = key };
                    return self.dispatchToModel(user_msg);
                }
                return null;
            }

            // Convert to user message if Model.Msg has a key variant
            if (@hasField(UserMsg, "key")) {
                const user_msg = UserMsg{ .key = key };
                return self.dispatchToModel(user_msg);
            }

            return null;
        }

        fn processMouseEvent(self: *Self, mouse_event: keyboard.MouseEvent) ?UserCmd {
            if (@hasField(UserMsg, "mouse")) {
                const user_msg = UserMsg{ .mouse = mouse_event };
                return self.dispatchToModel(user_msg);
            }

            return null;
        }

        /// Perform suspend (Ctrl+Z) — POSIX only
        fn performSuspend(self: *Self) void {
            if (builtin.os.tag == .windows) return;

            // Cleanup terminal
            if (self.terminal) |*term| {
                term.cleanup();
            }

            // Raise SIGTSTP to suspend process
            if (builtin.os.tag != .windows) {
                const posix = std.posix;
                _ = posix.raise(posix.SIG.TSTP) catch {};
            }

            // When we resume (after `fg`), re-setup terminal
            if (self.terminal) |*term| {
                term.setup() catch {};
            }

            // Force re-render
            self.last_view_hash = 0;

            // Dispatch resumed message if model supports it
            if (@hasField(UserMsg, "resumed")) {
                const cmd = self.dispatchToModel(.{ .resumed = {} });
                self.processCommand(cmd) catch {};
            }
        }

        fn processCommand(self: *Self, cmd: UserCmd) !void {
            switch (cmd) {
                .none => {},
                .quit => {
                    self.running = false;
                },
                .tick => |ns| {
                    self.pending_tick = self.context.elapsed + ns;
                },
                .every => |ns| {
                    self.every_interval = ns;
                    self.last_every_tick = self.context.elapsed;
                },
                .batch => |cmds| {
                    for (cmds) |c| {
                        try self.processCommand(c);
                    }
                },
                .sequence => |cmds| {
                    for (cmds) |c| {
                        try self.processCommand(c);
                    }
                },
                .msg => |m| {
                    const new_cmd = self.dispatchToModel(m);
                    try self.processCommand(new_cmd);
                },
                .perform => |func| {
                    if (func()) |m| {
                        const new_cmd = self.dispatchToModel(m);
                        try self.processCommand(new_cmd);
                    }
                },
                .suspend_process => {
                    self.performSuspend();
                },
                .enable_mouse => {
                    if (self.terminal) |*term| {
                        try term.enableMouse();
                    }
                },
                .disable_mouse => {
                    if (self.terminal) |*term| {
                        try term.disableMouse();
                    }
                },
                .show_cursor => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.cursor_show);
                        try term.flush();
                    }
                },
                .hide_cursor => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.cursor_hide);
                        try term.flush();
                    }
                },
                .enter_alt_screen => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.alt_screen_enter);
                        try term.flush();
                    }
                },
                .exit_alt_screen => {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.alt_screen_exit);
                        try term.flush();
                    }
                },
                .set_title => |title| {
                    if (self.terminal) |*term| {
                        try term.setTitle(title);
                    }
                },
                .println => |line| {
                    if (self.terminal) |*term| {
                        const writer = term.writer();
                        try writer.writeAll(ansi.cursor_save);
                        try writer.writeAll(ansi.cursor_home);
                        try writer.writeAll(line);
                        try writer.writeAll("\n");
                        try writer.writeAll(ansi.cursor_restore);
                        try term.flush();
                    }
                },
            }
        }

        fn render(self: *Self) !void {
            const view_output = self.model.view(&self.context);

            // Compute hash of view output
            const view_hash = std.hash.Wyhash.hash(0, view_output);

            // Only redraw if view changed
            if (view_hash != self.last_view_hash) {
                const writer = self.terminal.?.writer();

                // Start synchronized output (prevents tearing on supporting terminals)
                try writer.writeAll(ansi.sync_start);

                // Move cursor home (don't clear entire screen to reduce flicker)
                try writer.writeAll(ansi.cursor_home);

                // Write each line, clearing to end of line
                var lines = std.mem.splitScalar(u8, view_output, '\n');
                var first = true;
                var line_count: usize = 0;
                while (lines.next()) |line| {
                    if (!first) try writer.writeAll("\r\n");
                    first = false;
                    try writer.writeAll(line);
                    try writer.writeAll(ansi.line_clear_right);
                    line_count += 1;
                }

                // Clear remaining lines if previous content was taller
                if (self.last_line_count > line_count) {
                    var remaining = self.last_line_count - line_count;
                    while (remaining > 0) : (remaining -= 1) {
                        try writer.writeAll("\r\n");
                        try writer.writeAll(ansi.line_clear);
                    }
                }
                self.last_line_count = line_count;

                // End synchronized output
                try writer.writeAll(ansi.sync_end);

                try self.terminal.?.flush();

                // Save hash for comparison
                self.last_view_hash = view_hash;
            }
        }

        /// Send a message to the model
        pub fn send(self: *Self, m: UserMsg) !void {
            const cmd = self.dispatchToModel(m);
            try self.processCommand(cmd);
        }

        /// Stop the program
        pub fn quit(self: *Self) void {
            self.running = false;
        }
    };
}
