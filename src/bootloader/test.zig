const build_options = @import("build_options");
const std = @import("std");
const uefi = std.os.uefi;


const log = std.log.scoped(.tests);
fn readFile(io: std.Io) !void {
    // const alloc = std.testing.allocator;
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const buf = try alloc.alloc(u8, 40000);
    defer alloc.free(buf);
    
    std.debug.print("{}", .{std.Io.Dir.cwd()});
    var file = try std.Io.Dir.cwd().openFile(
        io,
        "zig-out/" ++ build_options.kernel_path, 
        .{
            .mode = .read_only,
            .lock = .exclusive
        }
    );
    defer file.close(io);

    var reader = file.reader(io, buf);
    const header = try std.elf.Header.read(&reader.interface);
    var iter = std.elf.Header.iterateProgramHeaders(
        &header, 
        &reader
        );
    const Addr = std.elf.Elf64.Addr;
    var kernel_start_virt: Addr = std.math.maxInt(Addr);
    var kernel_start_phys: Addr = std.math.maxInt(Addr);
    var kernel_end_phys: Addr = 0;
    var i_a: u8 = 0;
    while (true) {
        std.debug.print("{d}\n", .{i_a});
        i_a += 1;
        const h = iter.next() catch |e| {
            std.debug.print("Error iterating kernel headers {}\n", .{e});
            return uefi.Error.LoadError;
        } orelse break;
        std.debug.print("h: {any}\n", .{h});
        if (h.p_type != std.elf.PT_LOAD) continue;
        std.debug.print("PT_LOAD Header found\n", .{});
        if (h.p_vaddr < kernel_start_virt) kernel_start_virt = h.p_vaddr;
        if (h.p_paddr < kernel_start_phys) kernel_start_phys = h.p_paddr;
        if (h.p_paddr + h.p_memsz > kernel_end_phys) kernel_end_phys = h.p_paddr + h.p_memsz;
    }
    std.debug.print(\\PT_LOAD Headers analized
        \\  Kernel Start Virtual Address:   {d}
        \\  Kernel Start Physical Address:  {d}
        \\  Kernel End Physical Address:    {d}
    , .{kernel_start_virt, kernel_start_phys, kernel_end_phys});
}

test "read-parse-kernel" {
    std.debug.print("HELLOOO\n", .{});
    log.info("HI", .{});
    try readFile(std.testing.io); 
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try readFile(io); 
}
