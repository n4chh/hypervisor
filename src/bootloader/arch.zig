// This file will act as an API to interact with various implementations
// of the platforms. At the day of writing this, 05/29/26, we will only
// need to implement the page structure of the CPU to succesfully load 
// the kernel. But if some extra hardware-dependant needs arise during development,
// we will be able to code them here.
const builtin = @import("builtin");


const x86_64 = @import("arch/x86_64/arch.zig");

const impl = switch (builtin.target.cpu.arch) {
    else => @compileError("Unsupported platform."),
};

