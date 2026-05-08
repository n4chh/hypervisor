const std = @import("std");
const build_options = @import("build_options");

// Create a drain function for the UefiWriter vtable
//
fn uefiDrainer(_: *std.Io.Writer, data: []const []const u8, _: usize) LogError!usize {
    var bytes: u16 = 0;
    // Not sure which version introduce this but now system_table is comptime.
    // Is better to check it in the same drainer function than in other places
    const writer = std.os.uefi.system_table.con_out orelse return error.WriteFailed;

    for (data) |slice| {
        for (slice) |byte| {
            _ = writer.outputString(&[_:0]u16{byte}) catch unreachable;
            bytes += 1;
        }
    }
    return bytes;
}

var UefiWriter = std.Io.Writer{ .vtable = &std.Io.Writer.VTable{ .drain = uefiDrainer }, .buffer = &.{} };
//

// Must match the vtable's expected error type.
const LogError = std.Io.Writer.Error;

// Let's have this as const, there is no need to change the log on runtime (yet)
const LogLevel: std.log.Level = @enumFromInt(@intFromEnum(build_options.log_level));

// Create the main function that implement the Zig's log function
fn log(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime fmt: []const u8, args: anytype) void {
    const scope_str = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const level_str = "[" ++ @tagName(level) ++ "] ";

    // This function has changed from version 15.
    if (@intFromEnum(LogLevel) > @intFromEnum(level)) return;
    std.Io.Writer.print(&UefiWriter, level_str ++ scope_str ++ fmt ++ "\r\n", args) catch unreachable;
}

pub const default_log_options = std.Options{
    .logFn = log,
};
