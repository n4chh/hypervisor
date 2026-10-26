// Ref to constraint strings: 
// https://releases.llvm.org/10.0.0/docs/LangRef.html#inline-asm-constraint-string
// https://ziglang.org/documentation/master/#Assembly
//
// IMPORTANT THIS IS AT&T
// Remember there they always put source first.
//
const std = @import("std");

pub inline fn loadCr(control_register: u8, value: u64) void {
    const constraint_string = "mov %[reg], %%cr{d}";
    switch (control_register) {
        0...8 => {
            asm volatile (
                std.fmt.comptimePrint(constraint_string, .{control_register})
                :
                : [reg] "r" (value)
            );
        },
        else => unreachable,
    }
}

pub inline fn readCr(control_register: u8) u64 {
    var value: u64 = undefined;
    const constraint_string = "mov %%cr{d}, %[reg]";
    switch (control_register) {
        0...4,8 => {
            asm volatile (
                std.fmt.comptimePrint(constraint_string, .{control_register})
                : [reg] "=r" (value)
            );
        },
        else => unreachable,
    }
    return value;
}

pub inline fn readMsr(ecx: u32) u64 {
    return asm volatile (
        \\ rdmsr
        // : [ret] "={edx:eax}" (-> u64),
        : [ret] "={eax}" (-> u64),
        : [ecx] "{ecx}" (ecx)
    );
}

pub inline fn loadMsr(ecx: u32, value: u64) void  {
    return asm volatile (
        \\ wrmsr
        :
        : 
        [ecx] "{ecx}" (ecx),
        // [ret] "={edx:eax}" (value),
        [ret] "{eax}" (value),
    );
}

 
pub inline fn setup() void {
    // This function must be used as a template for needed setup, in our case,
    // we need to setup PML4 
    // CR4
    //
    //
    // CR0 
    // PG = 1, 31 bit
    const pg: u64 = 1 << 31;
    // IA32_EFER.LME = 1
    // INITIALIZING IA-32e Mode (long mode)

    // 1. Disable paging
    //
    var cr0 = readCr(0);
    cr0 &= ~pg;
    loadCr(0, cr0);

    // 2. Enable Physical Address Extension & Disable 57-bit Linear Addresses
    //
    // PAE = 1, 5bit
    // LA57 = 0, 12bit 
    const pae: u64 = 1 << 5;
    const la57: u64 = 1 << 12;
    var cr4 = readCr(4);
    cr4 |= pae;
    cr4 &= ~la57;
    loadCr(4, cr4);
    // Following the manual, we should place here our PML4 entry in CR3

    // 3. Enable Long Mode Enable in Extended Feature Enable Register
    const lme = 1<<8;
    const ia32_efer_addr: u32 = 0xc0000080;
    var ia32_efer = readMsr(ia32_efer_addr);
    ia32_efer |= lme;
    loadMsr(ia32_efer_addr, ia32_efer);

    // 4. Set again Paging
    cr0 = readCr(0);
    cr0 |= pg;
    loadCr(0, cr0);
}
