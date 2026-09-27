const uefi = @import("std").os.uefi;
pub const magic: usize = 0x11C0FFEE_BABE1111;
pub const BootInfo = extern struct {
    // Magic byte used for checksum
    magic: usize,
    memory_map: *uefi.tables.MemoryMapSlice,
};
