const std = @import("std");
const uefi = std.os.uefi;
const blog = @import("log.zig");
const build_options = @import("build_options");
const log = std.log.scoped(.bootloader);
const Reader = std.Io.Reader;
const FileReader = std.Io.File.Reader;
const arch = @import("arch.zig");
const page_size = arch.impl.page_size_4k;
const page_mask = arch.impl.page_mask_4k;

// Desipite this is a global variable, the overriden of the function must be done on the
// root file.
// Ref: https://github.com/ziglang/zig/blob/master/lib/std/std.zig#L111
pub const std_options = blog.default_log_options;
const Addr = std.elf.Elf64.Addr;

const Kernel = struct {
    pstart: Addr,
    pend: Addr,
    vstart: Addr,
    vend: Addr,
    pages_4kib: u64,
    program: []u8,
    // TODO: Should we include a header field?? Is it used otherplace after parsing?
    // headers: std.elf.Header,

};

fn createKernelReader(kernel: *uefi.protocol.File, boot_services: *uefi.tables.BootServices) uefi.Error!std.Io.Reader {
    // This buffer is used by UEFI getInfo function to place the File Information. Our kernel_info pointer will point to it.
    // Ref: https://uefi.org/specs/UEFI/2.10/13_Protocols_Media_Access.html#id36
    var buf:[1000]u8 = undefined;
    const kernel_info: *uefi.protocol.File.Info.File = try kernel.getInfo(.file, @alignCast(&buf));
    const kernel_buffer =  boot_services.allocatePool(.loader_data, kernel_info.file_size) catch |err| {
        log.err("Error allocating memory: {}", .{err});
        return err;
    };
    log.info(
        \\ kernel_info: {*}
        \\ buff:        {*}
        , .{kernel_info, &buf});
    const bytes_readed = kernel.read(kernel_buffer) catch |err| {
        log.err("Error reading kernel file: {}", .{err});
        return err;
    };
    log.debug("Kernel bytes readed: {d}", .{bytes_readed});

    const reader = Reader.fixed(kernel_buffer);
    return reader;
}

fn loadKernel(kernel: *const Kernel, boot_services: *uefi.tables.BootServices) uefi.Error!void {
    const pages = boot_services.allocatePages(.{ .address = @ptrFromInt(kernel.pstart) }, .loader_data, kernel.pages_4kib) catch |e| {
        log.err("Error allocating memory pages for kernel: {}", .{e});
        return uefi.Error.LoadError;
    };
    log.debug("Bytes allocated: {any}", .{pages});

    for (0..kernel.pages_4kib) |i| {
        arch.impl.map4kTo(kernel.vstart + page_size * i, kernel.pstart + page_size * i, .read_write, boot_services) catch |e| {
            log.err("Error mapping memory for kernel: {}", .{e});
            return uefi.Error.LoadError;
        };
    }
    log.debug("Mapped memory for kernel image.", .{});
}

fn parseKernel(kernel_reader: *Reader) uefi.Error!Kernel {
    const header =  std.elf.Header.read(kernel_reader) catch |err| {
        log.err("Error reading the kernel headers: {}", .{err});
        return uefi.Error.Aborted;
    };
    var kernel: Kernel = undefined;
    var iter = std.elf.Header.iterateProgramHeadersBuffer(&header, kernel_reader.buffer);
    log.debug(\\Program Headers Iterator initialized: 
              \\    Endian:                 {}
              \\    Is 64:                  {}
              \\    Program Headers number: {}
              \\    Program Headers offset: 0x{x}
              \\    Index:                  {}
        , .{iter.endian, iter.is_64, iter.phnum, iter.phoff, iter.index});

    kernel.vstart = std.math.maxInt(Addr);
    kernel.pstart = std.math.maxInt(Addr);
    kernel.pend= 0;
    var i_a: u8 = 0;
    while (true) {
        log.debug("{d}", .{i_a});
        i_a += 1;
        const h = iter.next() catch |e| {
            log.err("Error iterating kernel headers {}", .{e});
            return uefi.Error.LoadError;
        } orelse break;
        log.debug("h: {any}", .{h});
        if (h.p_type != std.elf.PT_LOAD) continue;
        log.debug("PT_LOAD Header found", .{});
        if (h.p_vaddr < kernel.vstart) kernel.vstart = h.p_vaddr;
        if (h.p_paddr < kernel.pstart) kernel.pstart = h.p_paddr;
        if (h.p_paddr + h.p_memsz > kernel.pend) kernel.pend = h.p_paddr + h.p_memsz;
    }
    log.debug(\\PT_LOAD Headers analized
        \\  Kernel Start Virtual Address:   {d}
        \\  Kernel Start Physical Address:  {d}
        \\  Kernel End Physical Address:    {d}
        , .{kernel.vstart, kernel.pstart, kernel.pend});

    kernel.pages_4kib = (kernel.pend - kernel.pstart + (page_size - 1)) / page_size;
    log.debug("Kernel image: 0x{X:0>16} - 0x{X:0>16} (0x{X} pages).", .{ kernel.pstart, kernel.pend, kernel.pages_4kib });

    return kernel;
}

test "parse-kernel" {
    const io = std.testing.io;
    const kernel_file_path = "zig-out/" ++ build_options.kernel_path;
    const kernel_stats = try std.Io.Dir.cwd().statFile(
        io,
        kernel_file_path,
        .{
            .follow_symlinks = true,
        }
        );
    try std.testing.expect(kernel_stats.size > 0);

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const buf2 = try alloc.alloc(u8, kernel_stats.size);
    defer alloc.free(buf2);
    
    var file = try std.Io.Dir.cwd().openFile(
        io,
        kernel_file_path,
        .{.allow_directory = true}
    );
    defer file.close(io);
    var read_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const kernel: Kernel = try parseKernel(&reader.interface);
    try std.testing.expect(kernel.vstart != std.math.maxInt(Addr));
    try std.testing.expect(kernel.pstart != std.math.maxInt(Addr));
    try std.testing.expect(kernel.pend != 0);
}

fn readKernel(boot_services: *uefi.tables.BootServices) uefi.Error!*uefi.protocol.File {
    // Read kernel file into the UEFI application.
    // Remember that all operations with periferials must be done using uefi services

    // Brief zig explanation of the order of catching and unwrapping:
    //
    // locateProtocol(...) LocateProtocolError!?*Protocol
    // function returns either an optional value or an error (imagine ! acts like a separator between
    // the 2 possible values: Error|Optional). However we want a real value.
    // First we need to handle every result that the function may return:
    //  - Error is returned: We must handle it, for example using catch.
    //  - An Optional is returned: We need to ensure if our optional holds a value or not (is null)
    //    before we use it. To do this in the same line, after we "catch" an error we are able to
    //    unwrap the optional into a value (e.g. using orelse to handle both scenarios).
    //
    // The order of our handling matters, before we can't unwrap an optional if we didn't ensure we don't
    // have an error.
    //
    // Diagram:
    // if error -> abort -> else if optional == null -> abort -> else -> value
    //
    const fs: *uefi.protocol.SimpleFileSystem =
        boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null) catch |err| {
            log.err("Couldn't locate the filesystem protocol {}", .{err});
            return uefi.Error.Aborted;
        } orelse {
            log.err("Filesystem protocol returned null.", .{});
            return uefi.Error.Aborted;
        };
    log.info("Retrieved file system handler: {*}", .{fs});
    log.debug("File system: {}", .{fs});

    const root_dir = fs.openVolume() catch |err| {
        log.err("Couldn't open root directory of volume: {}", .{err});
        return uefi.Error.Aborted;
    };
    log.info("Root directory of volume opened: {*}", .{root_dir});
    log.debug("Volume: {}", .{root_dir});

    // we need to figure out a better way of converting from utf8 to utf16
    var buf: [1000]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const allocator = fba.allocator();
    const kernel_name = std.unicode.utf8ToUtf16LeAllocZ(allocator, build_options.kernel_main) catch |err| {
        log.info("Couldn't generate kernel name: {}", .{err});
        return uefi.Error.Aborted;
    };

    const kernel_file = root_dir.open(kernel_name, uefi.protocol.File.OpenMode.read, .{}) catch |err| {
        log.err("Couldn't open kernel file: {}", .{err});
        return uefi.Error.Aborted;
    };
    return kernel_file;
}

// Store Base image of our application in a known address to debug it with gdb
pub fn storeSymbols(boot_services: *uefi.tables.BootServices) uefi.Error!void {
    const loadedImage =
        boot_services.handleProtocol(uefi.protocol.LoadedImage, uefi.handle) catch |e| {
            log.err("Couldn't locate the LoadedImage protocol {}", .{e});
            return uefi.Error.Aborted;
        } orelse {
            log.err("LoadedImage protocol returned null.", .{});
            return uefi.Error.Aborted;
        };
    log.warn("Located UEFI Application base address at {*}", .{loadedImage.image_base});
    const image_base_ptr: *volatile u64 = @ptrFromInt(0x10008);
    const watchpoint_ptr: *volatile u64 = @ptrFromInt(0x10000);
    image_base_ptr.* = @intFromPtr(loadedImage.image_base);
    // We will use this pointer to create a watchpoint over the known direction to tell lldb
    // to stop execution when addr 0x10000 has the value 0xAAAABBBB.
    // Once that we could look to 0x10008 to get the base address of the UEFI application
    // and apply it so then symbols are resolved.
    watchpoint_ptr.* = 0xAAAABBBB;
}

pub fn main() uefi.Error!void {
    log.info("Hello from UEFI!!", .{});
    const boot_services: *uefi.tables.BootServices = uefi.system_table.boot_services orelse {
        log.err("Failed to get boot services.", .{});
        return uefi.Error.Aborted;
    };
    log.info("Located boot_services at {*}", .{boot_services});
    log.debug("Boot Services: {}", .{boot_services});

    try storeSymbols(boot_services);

    const kernel_file: *uefi.protocol.File = try readKernel(boot_services);
    const kernel_reader: Reader = createKernelReader(kernel_file, boot_services) catch |err| {
        log.err("Error creating the kernel Reader: {}", .{err});
        return err;
    };
    log.info("Kernel file loaded", .{});
    const kernel: Kernel = try parseKernel(@constCast(&kernel_reader)); 
    // I think I've found UEFI docs that warns you about page privileges:
    // https://uefi.org/specs/UEFI/2.10/02_Overview.html#x64-platforms
    log.debug("Setting CR3 to a writable page.", .{});
    arch.impl.setPML4TableWritable(boot_services) catch |e| {
        log.err("Memory error: {}", .{e});
        return uefi.Error.Aborted;
    };
    log.debug("Alocatting memory", .{});
    arch.impl.map4kTo(0xFFFF_FFFF_DEAD_0000, 0x10_0000, .read_write, boot_services) catch |e| {
        log.err("Memory error: {}", .{e});
        return uefi.Error.Aborted;
    };
    log.info("Memory page allocated.", .{});

    try loadKernel(&kernel, boot_services);

    while (true)
        asm volatile ("hlt");
}


test "Test std.elf.Header read and itereate" {
    log.info("trying: {any}", .{build_options});
}
