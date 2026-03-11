//! Debug file logging for ZigZag applications.
//! Since stdout is owned by the renderer, this provides file-based logging.

const std = @import("std");

const Mutex = if (@hasDecl(std, "Io") and @hasDecl(std.Io, "Mutex"))
    std.Io.Mutex
else
    std.Thread.Mutex;

/// Logger that writes timestamped messages to a file
pub const Logger = struct {
    file: if (@hasDecl(std, "Io")) std.Io.File else std.fs.File,
    mutex: Mutex,
    io: if (@hasDecl(std, "Io")) std.Io else void = undefined,

    /// Initialize a logger that writes to the given file path
    pub fn init(io_context: anytype, path: []const u8) !Logger {
        if (@hasDecl(std, "Io")) {
            const io = io_context;
            const cwd = io.cwd();
            const file = try cwd.createFile(io, path, .{ .truncate = false });

            return .{
                .file = file,
                .mutex = if (@hasDecl(Mutex, "init")) Mutex.init else Mutex{},
                .io = io,
            };
        } else {
            const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
            file.seekFromEnd(0) catch {};

            return .{
                .file = file,
                .mutex = .{},
                .io = {},
            };
        }
    }

    /// Close the log file
    pub fn deinit(self: *Logger) void {
        if (@hasDecl(std, "Io")) {
            self.file.close(self.io);
        } else {
            self.file.close();
        }
    }

    /// Write a log message with timestamp prefix
    pub fn log(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
        const day_seconds = epoch_seconds.getDaySeconds();

        if (@hasDecl(std, "Io")) {
            // In Zig 0.16.dev, streaming file operations typically require a buffer
            var buf: [2048]u8 = undefined;
            var writer = std.Io.File.writerStreaming(self.file, self.io, &buf);

            writer.print("[{d:0>2}:{d:0>2}:{d:0>2}] ", .{
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
            }) catch return;

            writer.print(fmt, args) catch return;
            writer.writeByte('\n') catch return;

            // Safeguard in case the writer implementation requires an explicit flush
            if (@hasDecl(@TypeOf(writer), "flush")) {
                writer.flush() catch {};
            }
        } else {
            const writer = self.file.writer();

            writer.print("[{d:0>2}:{d:0>2}:{d:0>2}] ", .{
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
            }) catch return;

            writer.print(fmt, args) catch return;
            writer.writeByte('\n') catch return;
        }
    }
};

