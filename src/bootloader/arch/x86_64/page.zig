// Ref: Intel Software Developer Manual, Volume 3, Chapter 5, (5.3, 5.4 and 5.5)

// Skipping PML5 by now ...
const TableType = enum {
    PML4E,      // Page Mode Level 4 Entry
    PDPTE,      // Page Directory Pointer Table Entry
    PDE,        // Page Directory Entry
    PTE,        // Page Table Entry
}L;




// This function try to establish all the similarities between all the different Page Entries
// for 4-Level/5-Level paging.
// As a summary, they share same structure from bit 0 to 11 and the 63 bit.
// Ref: Figure 5-11, SDM Volume 3, Chapter 5.5.4
fn EntryBase(_table_type: TableType) type {
// This is kinda equivalent to __attribute__((packed)) in C.
// We really want to keep the offset of this structure to match intel's definition of the page entries.
// This will be laid the structure to memory as it is defined, maintaining the size,
// and the offsets of fields without adding padding between them.
// https://ziglang.org/documentation/0.16.0/#packed-struct
    return packed struct(u64) {
        // This is a way of tracking the type for using it on next functions
        const Self = @This();
        const table_type = _table_type;
        
        // Present. (P)
        present: bool = true,
        // Read/Write (R/W)
        // If set to false, write is not allowed to the region.
        rw: bool = true,
        // User/Supervisor (U/S)
        // If set to false, user-mode access is not allowed to the region.
        us: bool = true,
        // Page-level Write through (PWT)
        // Indirectly determines the memory type used to access the page or page table
        // during linear-address translation (see SDM Volume 3, Section 5.9.2)
        pwt: bool = true,
        // Page-level Cache Disable (PCD)
        // Indirectly determines the memory type used to access the page or page table
        // during linear-address translation
        pcd: bool = false,
        // Accessed (A)
        // Indicates weather the entry has been used for linear-address translation.
        accessed: bool = false,

        // Dirty bit
        // Indicates weather software has written to the 2MiB page
        // Ignored when this entry references a page table
        dirty: bool = false,
        // Page Size (PS)
        // Must be 0 (for PML4 and PML5), otherwise this entry maps a 2MiB
        ps: bool = false,
        // Global (G)
        // if CR4.PGE = 1, determines weather the translation is global, ignored otherwise
        global: bool = true,
        // 2 bits ignored
        ignored: u2 = 0,
        // Ignored except for HLAT (Hypervisor-managed Linear Address Translation) paging 
        // if not ignored and 1, linear-address translation is restarted with ordinary paging
        restart: bool = true,
        // Reserved 51 bytes (until byte 62)
        phys: u51,
        // Execute Disable (XD) if 1, instruction fetches are not allowed from the region controlled by this entry.
        // if IA32_EFER.NXE = 0 is reserved
        xd: bool = false,

        // To avoid risk of mixing Phys address with Virtual ones, we define 2 types
        // that will indicate weather the address is physical or virtual.
        pub const Virt = u64;
        pub const Phys = u64;

        pub inline fn address(self: Self) Phys {
            // We left shift this 12 bits because that's the way translation is performed
            // Ref: SDM Volume 3, Chapter 5, Section 5.2
            // We will left this here as for now we operate using 4KiB pages, 
            // but depending on the size of the page we must adjust the bits we shift.
            return @as(u64, @intCast(self.phys)) << 12;
        }
    };
}

const PTE = EntryBase(.PTE);
const PDE = EntryBase(.PDE);
const PDPTE = EntryBase(.PDPTE);
const PML4E = EntryBase(.PML4E);
