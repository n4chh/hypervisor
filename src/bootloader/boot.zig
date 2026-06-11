const std = @import("std");
const uefi = std.os.uefi;
const blog = @import("log.zig");
const build_options = @import("build_options");
const log = std.log.scoped(.bootloader);
const Reader = std.Io.Reader;
const arch = @import("arch.zig");
const page_size = arch.impl.page_size_4k;
const page_mask = arch.impl.page_mask_4k;

// Desipite this is a global variable, the overriden of the function must be done on the
// root file.
// Ref: https://github.com/ziglang/zig/blob/master/lib/std/std.zig#L111
pub const std_options = blog.default_log_options;

fn parseKernel(kernel: **uefi.protocol.File, boot_services: *uefi.tables.BootServices) uefi.Status {
    const header_size: usize = @sizeOf(std.elf.Elf64.Ehdr);
    const header_buffer: []align(8) u8 = boot_services.allocatePool(.loader_data, header_size) catch |err| {
        log.err("Couldn't allocate memory to read the kernel header: {}", .{err});
        return .aborted;
    };

    const read_bytes = kernel.*.read(header_buffer) catch |err| {
        log.err("Error reading the kernel {}", .{err});
        return .aborted;
    };
    log.info("Kernel loaded on memory", .{});
    log.debug("Readed bytes from kernel file: {d}", .{read_bytes});
    // Is safe to constCast here because there is no modification
    // of the reader pointer inside the read function.
    const header = std.elf.Header.read(@constCast(&std.Io.Reader.fixed(header_buffer))) catch |err| {
        log.err("Error parsing headers of kernel binary: {}", .{err});
        return .aborted;
    };
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
    return .success;
}

fn loadKernel(kernel: **uefi.protocol.File, boot_services: *uefi.tables.BootServices) uefi.Status {
    // Load kernel file into the UEFI application.
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
            return .aborted;
        } orelse {
            log.err("Filesystem protocol returned null.", .{});
            return .aborted;
        };
    log.info("Retrieved file system handler: {*}", .{fs});
    log.debug("File system: {}", .{fs});

    const root_dir = fs.openVolume() catch |err| {
        log.err("Couldn't open root directory of volume: {}", .{err});
        return .aborted;
    };
    log.info("Root directory of volume opened: {*}", .{root_dir});
    log.debug("Volume: {}", .{root_dir});

    // we need to figure out a better way of converting from utf8 to utf16
    var buf: [1000]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const allocator = fba.allocator();
    const kernel_name = std.unicode.utf8ToUtf16LeAllocZ(allocator, build_options.kernel_main) catch |err| {
        log.info("Couldn't generate kernel name: {}", .{err});
        return .aborted;
    };

    kernel.* = root_dir.open(kernel_name, uefi.protocol.File.OpenMode.read, .{}) catch |err| {
        log.err("Couldn't open kernel file: {}", .{err});
        return .aborted;
    };

    const Addr = std.elf.Elf64.Addr;
    var kernel_start_virt: Addr = std.math.maxInt(Addr);
    var kernel_start_phys: Addr = std.math.maxInt(Addr);
    var kernel_end_phys: Addr = 0;
    var iter = std.elf.Header.iterateProgramHeaders(kernel.*);
    while (true) {
        const header = iter.next() catch |e| {
            log.err("Error iterating kernel headers {}.", .{e});
            return .load_error;
        } orelse break;
        if (header.p_type != std.elf.PT_LOAD) continue;
        if (header.p_vaddr < kernel_start_virt) kernel_start_virt = header.p_vaddr;
        if (header.p_paddr < kernel_start_phys) kernel_start_phys = header.p_paddr;
        if (header.p_paddr + header.p_memsz > kernel_end_phys) kernel_end_phys = header.p_paddr + header.p_memsz;
    }

    const pages_4kib = (kernel_end_phys - kernel_start_phys + (page_size - 1)) / page_size;
    log.debug("Kernel image: 0x{X:0>16} - 0x{X:0>16} (0x{X} pages)", .{ kernel_start_phys, kernel_end_phys, pages_4kib });

    return .success;
}

pub fn main() uefi.Status {
    log.info("Hello from UEFI!!", .{});
    var kernel: *uefi.protocol.File = undefined;
    const boot_services: *uefi.tables.BootServices = uefi.system_table.boot_services orelse {
        log.err("Failed to get boot services.", .{});
        return .aborted;
    };
    log.info("Located boot_services at {*}", .{boot_services});
    log.debug("Boot Services: {}", .{boot_services});

    if (loadKernel(&kernel, boot_services) != .success) {
        return .aborted;
    }

    log.info("Kernel loaded", .{});
    log.debug("Kernel: {}", .{kernel});
    if (parseKernel(&kernel, boot_services) != .success) {
        return .aborted;
    }
    // I think I've found UEFI docs that warns you about page privileges:
    // https://uefi.org/specs/UEFI/2.10/02_Overview.html#x64-platforms
    log.debug("Setting CR3 to a writable page.", .{});
    arch.impl.setPML4TableWritable(boot_services) catch |e| {
        log.err("Memory error: {}", .{e});
        return .aborted;
    };
    log.debug("Alocatting memory", .{});
    arch.impl.map4kTo(0xFFFF_FFFF_DEAD_0000, 0x10_0000, .read_write, boot_services) catch |e| {
        log.err("Memory error: {}", .{e});
        return .aborted;
    };
    log.info("Memory page allocated.", .{});

    while (true)
        asm volatile ("hlt");

    return .success;
}
