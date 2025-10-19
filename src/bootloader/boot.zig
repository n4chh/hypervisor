const std  = @import("std");
const uefi = std.os.uefi;

pub fn main() uefi.Status {
    // var status: uefi.Status = undefined;
    const con_out = uefi.system_table.con_out orelse return .aborted;

    con_out.clearScreen() catch unreachable;
    for ("Hello, World\n") |b| {
        _ = con_out.outputString(&[_:0]u16{b}) catch unreachable;
    }
    while (true)
        asm volatile ("hlt");

    return .success;
}
