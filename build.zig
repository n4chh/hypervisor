const std = @import("std");
const IMG_DIR_NAME = "img";

pub fn buildUefi(b: *std.Build) *std.Build.Step.Compile {
    // Create the bootloader executable
    const bootloader = b.addExecutable(.{
        .name = "BOOTX64.EFI",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bootloader/boot.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .uefi,
            }),
            .optimize = b.standardOptimizeOption(.{}),
        }),
        .linkage = .static,
    });

    b.installArtifact(bootloader);

    // Place the executable in the EFI fs
    const install_bootloader = b.addInstallFile(
        bootloader.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ IMG_DIR_NAME, bootloader.name }),
    );
    b.getInstallStep().dependOn(&install_bootloader.step);
    return bootloader;
}

pub fn buildKernel(b: *std.Build) *std.Build.Step.Compile {
    // Create the kernel executable
    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel/main.zig"),
            .target = b.resolveTargetQuery(.{
                .os_tag = .freestanding,
                .cpu_arch = .x86_64,
                .ofmt = .elf,
            }),
            .code_model = .kernel,
        }),
        .linkage = .static,
    });
    kernel.entry = .{ .symbol_name = "kernelEntry" };
    kernel.linker_script = b.path("src/kernel/linker.ld");
    b.installArtifact(kernel);
    // Place the kernel inside EFI
    const install_kernel = b.addInstallFile(
        kernel.getEmittedBin(),
        b.fmt("{s}/{s}", .{ IMG_DIR_NAME, kernel.name }),
    );
    b.getInstallStep().dependOn(&install_kernel.step);

    return kernel;
}

pub fn build(b: *std.Build) void {
    const ovmf_path = b.option([]const u8, "ovmf-path", "Path to OVMF firmware file") orelse findOvmfPath(b);
    const log_level_str = b.option([]const u8, "log-level", "Log level of the application.") orelse "info";
    const log_level: std.log.Level = std.meta.stringToEnum(std.log.Level, log_level_str) orelse @panic("Invalid log level provided");

    const build_options = b.addOptions();
    build_options.addOption(std.log.Level, "log_level", log_level);

    const bootloader = buildUefi(b);
    const kernel = buildKernel(b);

    build_options.addOption([]const u8, "kernel_main", kernel.name);
    bootloader.root_module.addOptions("build_options", build_options);

    const qemu_args = [_][]const u8{
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-bios",
        ovmf_path,
        // "-drive",
        // "if=pflash,format=raw,unit=0,file.filename=" ++ ovmf_path ++ ",file.locking=off,readonly=on",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{ b.install_path, IMG_DIR_NAME }),
        "-nographic",
        "-serial",
        "mon:stdio",
        "-no-reboot",
        "-enable-kvm",
        "-cpu",
        "host",
        "-s",
    };
    const macos_qemu_args = [_][]const u8{
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-L",
        "/Users/nachh/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{ b.install_path, IMG_DIR_NAME }),
        "-nographic",
        "-serial",
        "mon:stdio",
        "-no-reboot",
        "-s",
        "-drive",
        "if=pflash,format=raw,unit=0,file.filename=/Users/nachh/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/edk2-x86_64-code.fd,file.locking=off,readonly=on",
        // "if=pflash,format=raw,unit=0,file.filename=" ++ ovmf_path ++ ",file.locking=off,readonly=on",
    };

    var qemu_cmd: *std.Build.Step.Run = undefined;
    if (b.graph.host.result.os.tag == .macos) {
        qemu_cmd = b.addSystemCommand(&macos_qemu_args);
    } else {
        qemu_cmd = b.addSystemCommand(&qemu_args);
    }
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_qemu_step = b.step("run", "Run QEMU");
    run_qemu_step.dependOn(&qemu_cmd.step);

    var debug_qemu_cmd: *std.Build.Step.Run = undefined;
    if (b.graph.host.result.os.tag == .macos) {
        debug_qemu_cmd = b.addSystemCommand(&macos_qemu_args ++ [_][]const u8{"-S"});
    } else {
        debug_qemu_cmd = b.addSystemCommand(&qemu_args ++ [_][]const u8{"-S"});
    }
    debug_qemu_cmd.step.dependOn(b.getInstallStep());

    const debug_qemu_step = b.step("debug", "Run QEMU and stop execution before boot.");
    debug_qemu_step.dependOn(&debug_qemu_cmd.step);
}

// Find OVMF firmware device
fn findOvmfPath(b: *std.Build) []const u8 {
    const candidates: []const []const u8 = switch (b.graph.host.result.os.tag) {
        .macos => &.{
            // Unsure if this one can be resolved by using env variables
            "/Users/nachh/Library/Containers/com.utmapp.UTM/Data/Library/Caches/qemu/edk2-x86_64-code.fd", // UTM
            "/opt/homebrew/share/qemu/edk2-x86_64-code.fd", // Homebrew (Apple Silicon)
            "/usr/local/share/qemu/edk2-x86_64-code.fd", // Homebrew (Intel)
        },
        .linux => &.{
            "/usr/share/edk2-ovmf/OVMF_CODE.fd", // Gentoo
            "/usr/share/edk2/ovmf/OVMF_CODE.fd", // Fedora
            "/usr/share/OVMF/OVMF_CODE.fd", // Debian/Ubuntu
            "/usr/share/ovmf/OVMF.fd", // Ubuntu (alt)
            "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd", // Arch
        },
        else => &.{},
    };
    for (candidates) |path| {
        std.Io.Dir.accessAbsolute(std.Io.Threaded.global_single_threaded.io(), path, .{}) catch continue;
        return path;
    }
    std.debug.print(
        \\error: OVMF firmware not found. Specify the path manually with:
        \\  zig build -Dovmf-path=<path>
        \\
    , .{});
    std.process.exit(1);
}
