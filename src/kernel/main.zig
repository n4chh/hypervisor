const std = @import("std");

// UEFI calling convetion is the same as Windows (x86_64_win, specifically win64 uses fastcall
// that passes first argumetns to registers), 
//
// Setting calling convention to naked means that functions have no prolog and epilog.
// This means this functinos will be uncallable from regular zig code.
//
// This is really usefull for us to load this function from our bootloader
// using it as a trampoling to then load our kernel. As we want to completly replace the stack
// with our kernel. We will switch to our kernel stack from this function.
//
// Ref: https://ziglang.org/documentation/master/std/#std.builtin.CallingConvention
export fn kernelEntry() callconv(.naked) noreturn {
    
    while (true)
        // As a reminder: volatile keyword is the same as in C.
        // "volatile" specifies the compiler that memory can be modified asynchronously
        // by something outside the program (e.g.  hardware devices, interrupt). 
        // That way we ensure code executed is exactly the same we wrote and avoid 
        // compiler to add optimizations to our code.
        //
        // From official docs: https://ziglang.org/documentation/master/#volatile
        // "Loads and stores in a volatile variable, are guaranteed to all happen
        // and in the same order as in source code"
        asm volatile ("hlt");
}
