const std  = @import("std");
const uefi = std.os.uefi;

pub fn main() uefi.Status {
    while (true)
        asm volatile ("hlt");
    return .success;
}
