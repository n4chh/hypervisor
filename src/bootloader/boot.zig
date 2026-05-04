const std  = @import("std");
const uefi = std.os.uefi;
const blog = @import("log.zig");
const log = std.log;

// Desipite this is a global variable, the overriden of the function must be done on the
// root file.
// Ref: https://github.com/ziglang/zig/blob/master/lib/std/std.zig#L111 
pub const std_options = blog.default_log_options;

pub fn main() uefi.Status {
    log.info("Hello from UEFI!!", .{});
    while (true)
        asm volatile ("hlt");

    return .success;
}
