const am = @import("asm.zig");
const std = @import("std");
const uefi = @import("std").os.uefi;
// Ref: Intel Software Developer Manual, Volume 3, Chapter 5, (5.3, 5.4 and 5.5)

// Skipping PML5 by now ...
const TableType = enum {
    PML4E,      // Page Mode Level 4 Entry
    PDPTE,      // Page Directory Pointer Table Entry
    PDE,        // Page Directory Entry
    PTE,        // Page Table Entry
};

// To avoid risk of mixing Phys address with Virtual ones, we define 2 types
// that will indicate weather the address is physical or virtual.
// We will also try to include a prefix to determine if a memory is virtual or physicall
// to the name of the variable:
//  - paddr/phys -> Physicall
//  - vaddr/virt -> Virtual
pub const Virt = u64;
pub const Phys = u64;




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


        const LowerType = switch(_table_type) {
            .PML4E => PDPTE,
            .PDPTE => PDE,
            .PDE => PTE,
            .PTE => struct {},
        };

        // Methods
        pub inline fn address(self: Self) Phys {
            // We left shift this 12 bits because that's the way translation is performed
            // Ref: SDM Volume 3, Chapter 5, Section 5.2
            // We will left this here as for now we operate using 4KiB pages, 
            // but depending on the size of the page we must adjust the bits we shift.
            return @as(u64, @intCast(self.phys)) << 12;
        }

        pub fn newMapPage(present: bool, phys: Phys) Self {
            // by now we are only going to operate with 2MiB or with 4KiB pages,
            // 1GiB will be disabled at compile time 
            if (table_type == .PML4E) @compileError("PML4E can not map to a page.");
            return Self{
                .present = present,
                .ps = true,
                .us = false,
                .rw = true,
                .phys = @truncate(phys >> 12),
            };
        }
        
        pub fn newMapTable(table: [*]LowerType, present: bool) Self {
            if (table_type == .PTE) @compileError("PTE can not point to a table.");
            return Self{
                .present = present,
                .ps = true,
                .us = false,
                .rw = true,
                .phys = @truncate(@intFromPtr(table) >> 12),
            };
        }

    };
}

const PTE = EntryBase(.PTE);
const PDE = EntryBase(.PDE);
const PDPTE = EntryBase(.PDPTE);
const PML4E = EntryBase(.PML4E);


const page_mask_4k: u64 = 0xFFF;
// This is pretty straight forward, every table will have 512 if pages is of 4KiB or 2MiB.
// Look to linear addresses structure in the notes or SDM for more reference
const num_table_entries = 512;
fn getTable(T: type, addr: Phys) []T {
    const ptr: [*]T = @ptrFromInt(addr & ~page_mask_4k);
    return ptr[0..num_table_entries];
}

// As defined on SDM Volume 3 Section 5, first table will be located at CR3
fn getPML4ETable(cr3: Phys) []PML4E {
    return getTable(PML4E, cr3);
}

fn getPDPTETable(pml4_paddr: Phys) []PDPTE {
    return getTable(PDPTE, pml4_paddr);
}

fn getPDETable(pdpte_paddr: Phys) []PDE {
    return getTable(PDE, pdpte_paddr);
}

fn getPTETable(pde_paddr: Phys) []PTE {
    return getTable(PTE, pde_paddr);
}

fn getEntry(T: type, vaddr: Virt, paddr: Phys) *T {
    const table = getTable(T, paddr);
    const shift = switch (T) {
        PML4E => 39,
        PDPTE => 30,
        PDE => 21,
        PTE => 12,
        else => @compileError("Unsupported page entry type."),
    };
    return &table[(vaddr >> shift) & 0x1FF];
}

fn getPML4E(vaddr: Virt, cr3: Phys) *PML4E {
    return getEntry(PML4E, vaddr, cr3);
}

fn getPDPTE(vaddr: Virt, pdpte_table_paddr: Phys) *PDPTE {
    return getEntry(PDPTE, vaddr, pdpte_table_paddr);
}

fn getPDE(vaddr: Virt, pde_table_paddr: Phys) *PDE {
    return getEntry(PDE, vaddr, pde_table_paddr);
}

fn getPTE(vaddr: Virt, pte_table_paddr: Phys) *PTE {
    return getEntry(PTE, vaddr, pte_table_paddr);
}

pub const PageAttribute = enum {
    // RO
    read_only,
    // RW 
    read_write,
    // RX
    executable,
};

pub const PageError = error { NoMemory, NotPresent, NotCannonical, InvalidAddress, AlreadyMapped };
pub fn map4kTo(vaddr: Virt, paddr: Phys, attr: PageAttribute, bs: *uefi.tables.BootServices) PageError!void {
    const rw = switch (attr) {
        .read_only, .executable => false,
        .read_write => true,
    };

    const pml4e = getPML4E(vaddr, am.readCr3());
    if (!pml4e.present) try allocateNewTable(PML4E, pml4e, bs);

    const pdpte = getPDPTE(vaddr, pml4e.address());
    if (!pdpte.present) try allocateNewTable(PDPTE, pdpte, bs);

    const pde = getPDE(vaddr, pdpte.address());
    if (!pde.present) try allocateNewTable(PDE, pde, bs);

    const pte = getPTE(vaddr, pde.address());
    if (pte.present) return PageError.AlreadyMapped;

    var new_pte = PTE.newMapPage(true, paddr);
    new_pte.rw = rw;
    pte.* = new_pte;
    // No need to flush TLB because the page was not present before
    // But as documentation we can flush TLB by:
    //  - Clearing PCIDE or PGE in CR4 if one of those flags are set (then restore it)
    //  - Mov from CR3 to other register and then mov back again from that register to CR3
    // Ref: Intel SDM, Volume 3 Chapter 14, Section 14.12.4
}

pub const kib = 1024;
pub const page_size_4k = 4 * kib;

pub fn setPML4TableWritable(bs: *uefi.tables.BootServices) PageError!void {
    const ptr = bs.allocatePages(.any, .boot_services_data, 1) catch |e| {
        std.log.err("Couldn't allocate page: {}", .{e});
        return PageError.NoMemory;
    };
    const new_pml4etable_ptr: [*]PML4E = @ptrFromInt(@intFromPtr(ptr.ptr));
    const new_pml4etable = new_pml4etable_ptr[0..num_table_entries];
    const orig_pml4etable = getPML4ETable(am.readCr3());
    @memcpy(new_pml4etable, orig_pml4etable);
    am.loadCr3(@intFromPtr(new_pml4etable));
}

pub fn allocateNewTable(T: type, entry: *T, bs: *uefi.tables.BootServices) PageError!void {
    // TODO: call allocatePages with other memory type and observe behaviour.
    // Hypervisor guide explicitly specifies that we use .boot_service_data memory type because we are 
    // going to use this memory after the execution is transfered to the kernel. However, after I've read
    // the UEFI manual, I couldn't find any explicit/implicit specification why we shouldn't use .loader_data
    // (which imv is the one we should use as this is a UEFI application).
    // Ref: https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html#memory-type-usage-after-exitbootservices
    const ptr = bs.allocatePages(.any, .boot_services_data, 1) catch |e| {
        std.log.err("Couldn't allocate page: {}", .{e});
        return PageError.NoMemory;
    };
    const paddr: Phys = @intFromPtr(ptr.ptr);
    // Couldn't find in the docs if clearing the memory is necesary but is a 
    // good practice to set everything to 0 :)
    clearPage(paddr);
    entry.* = T.newMapTable(@ptrFromInt(paddr), true);
}

fn clearPage(paddr: Phys) void {
    const page_ptr: [*]u8 = @ptrFromInt(paddr);
    @memset(page_ptr[0..page_size_4k],0);
}
