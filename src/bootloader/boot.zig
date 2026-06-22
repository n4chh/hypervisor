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

fn loadKernel(kernel: *uefi.protocol.File, header: *const std.elf.Header, boot_services: *uefi.tables.BootServices) uefi.Error!void {

    // const kernel_buffer: []align(8) u8 = boot_services.allocatePool(.loader_data, kernel) catch |err| {
    //     log.err("Couldn't allocate memory to read the kernel header: {}", .{err});
    //     return uefi.Error.Aborted;
    // };
    log.debug("{}, {}", .{ header, boot_services });
    var kernel_info_buffer: [1000]u8 = undefined;
    const kernel_info: *uefi.protocol.File.Info.File = try kernel.getInfo(.file, @alignCast(&kernel_info_buffer));
    log.debug("kernel info {}", .{kernel_info});

    const kernel_buffer = boot_services.allocatePool(.loader_data, kernel_info.file_size) catch |err| {
        log.err("Couldn't allocate memory to read the kernel header: {}", .{err});
        return uefi.Error.Aborted;
    };
    log.debug("Bytes readed: {d}", .{try kernel.read(kernel_buffer)});

    var iter = std.elf.Header.iterateProgramHeadersBuffer(header, kernel_buffer);

    const Addr = std.elf.Elf64.Addr;
    var kernel_start_virt: Addr = std.math.maxInt(Addr);
    var kernel_start_phys: Addr = std.math.maxInt(Addr);
    var kernel_end_phys: Addr = 0;
    while (true) {
        const h = iter.next() catch |e| {
            log.err("Error iterating kernel headers {}", .{e});
            return uefi.Error.LoadError;
        } orelse break;
        if (h.p_type != std.elf.PT_LOAD) continue;
        if (h.p_vaddr < kernel_start_virt) kernel_start_virt = h.p_vaddr;
        if (h.p_paddr < kernel_start_phys) kernel_start_phys = h.p_paddr;
        if (h.p_paddr + h.p_memsz > kernel_end_phys) kernel_end_phys = h.p_paddr + h.p_memsz;
    }

    const pages_4kib = (kernel_end_phys - kernel_start_phys + (page_size - 1)) / page_size;
    log.debug("Kernel image: 0x{X:0>16} - 0x{X:0>16} (0x{X} pages).", .{ kernel_start_phys, kernel_end_phys, pages_4kib });

    const pages = boot_services.allocatePages(.{ .address = @ptrFromInt(kernel_start_phys) }, .loader_data, pages_4kib) catch |e| {
        log.err("Error allocating memory for kernel {}", .{e});
        return uefi.Error.LoadError;
    };
    log.debug("Pages allocated {any}", .{pages});

    for (0..pages_4kib) |i| {
        arch.impl.map4kTo(kernel_start_virt + page_size * i, kernel_start_phys + page_size * i, .read_write, boot_services) catch |e| {
            log.err("Error allocating memory for kernel {}", .{e});
            return uefi.Error.LoadError;
        };
    }
    log.debug("Mapped memory for kernel image.", .{});
}

fn parseKernel(kernel: *uefi.protocol.File, boot_services: *uefi.tables.BootServices) uefi.Error!std.elf.Header {
    const header_size: usize = @sizeOf(std.elf.Elf64.Ehdr);
    const header_buffer: []align(8) u8 = boot_services.allocatePool(.loader_data, header_size) catch |err| {
        log.err("Couldn't allocate memory to read the kernel header: {}", .{err});
        return uefi.Error.Aborted;
    };

    const read_bytes = kernel.*.read(header_buffer) catch |err| {
        log.err("Error reading the kernel {}", .{err});
        return uefi.Error.Aborted;
    };
    log.info("Kernel loaded on memory", .{});
    log.debug("Readed bytes from kernel file: {d}", .{read_bytes});
    // Is safe to constCast here because there is no modification
    // of the reader pointer inside the read function.
    const header = std.elf.Header.read(@constCast(&Reader.fixed(header_buffer))) catch |err| {
        log.err("Error parsing headers of kernel binary: {}", .{err});
        return uefi.Error.Aborted;
    };
    return header;
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

    const kernel = root_dir.open(kernel_name, uefi.protocol.File.OpenMode.read, .{}) catch |err| {
        log.err("Couldn't open kernel file: {}", .{err});
        return uefi.Error.Aborted;
    };
    return kernel;
}

// Store Base image of our application in a known address to debug it with gdb
pub fn storeSymbols(boot_services: *uefi.tables.BootServices) uefi.Error!void {
    const loadedImage: *uefi.protocol.LoadedImage =
        boot_services.locateProtocol(uefi.protocol.LoadedImage, null) catch |e| {
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

    const kernel: *uefi.protocol.File = try readKernel(boot_services);

    log.info("Kernel loaded", .{});
    log.debug("Kernel: {}", .{kernel});
    const header: std.elf.Header = try parseKernel(kernel, boot_services);
    log.info(
        \\Kernel headers:
        \\    Entry Point: 0x{X}
        \\    ABI: {}
        \\    header.endian: {}
    , .{
        header.entry,
        header.os_abi,
        header.endian,
    });
    log.debug("Kernel headers parsed: {}", .{header});
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

    try loadKernel(kernel, &header, boot_services);

    while (true)
        asm volatile ("hlt");
}
