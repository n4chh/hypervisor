// Ref: Intel Software Developer Manual, Volume 3, Chapter 5, (5.3, 5.4 and 5.5)

// Skiping PML5 by now...
const TableType = enum {
    PML4E,      // Page Mode Level 4 Entry
    PDPTE,      // Page Directory Pointer Table Entry
    PDE,        // Page Directory Entry
    PTE,        // Page Table Entry
};




fn EntryBase(_table_type: TableType) type {
// this is kinda equivalent to __attribute__((packed)) in C. 
// We really want to keep the offset of this structure to match intel's deffinition of the page entries.
// This will laid the structure to memory as it is defined, maintaining the size,
// and also the offsets of fields without adding padding between them.
// https://ziglang.org/documentation/0.16.0/#packed-struct
    return packed struct {
        // This is a way of tracking the type for using it on next functions
        const Self = @This();
        const table_type = _table_type;
        
        // Present.
        present: bool = true,
        // Read/Write
        // If set to false, write is not allowed to the region.
        rw: bool = true,
        // User/Supervisor
        // If set to false, user-mode access is not allowed to the region.
        us: bool = true,

    };
}
