const std = @import("std");
const surtr = @import("src/bootloader");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const log_level_str = b.option([]const u8, "log-level", "Log level of the application.") orelse "info";
    const log_level: std.log.Level = std.meta.stringToEnum(std.log.Level, log_level_str) orelse @panic("Invalid log level provided");

    const build_options = b.addOptions();
    build_options.addOption(std.log.Level, "log_level", log_level);

    const bootloader = b.addExecutable(.{
        .name = "BOOTX64.EFI",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bootloader/boot.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .uefi,
            }),
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    bootloader.root_module.addOptions("build_options", build_options);
    b.installArtifact(bootloader);

    const out_dir_name = "img";
    const install_bootloader = b.addInstallFile(
        bootloader.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{ out_dir_name, bootloader.name }),
    );
    b.getInstallStep().dependOn(&install_bootloader.step);

    const ovmf_path = b.option([]const u8, "ovmf-path", "Path to OVMF firmware file") orelse findOvmfPath(b);

    const qemu_args = [_][]const u8{
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-bios",
        ovmf_path,
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{ b.install_path, out_dir_name }),
        "-nographic",
        "-serial",
        "mon:stdio",
        "-no-reboot",
        "-enable-kvm",
        "-cpu",
        "host",
        "-s",
    };

    const qemu_cmd = b.addSystemCommand(&qemu_args);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_qemu_cmd = b.step("run", "Run QEMU");
    run_qemu_cmd.dependOn(&qemu_cmd.step);
}

// Find OVMF firmware device
fn findOvmfPath(b: *std.Build) []const u8 {
    const candidates: []const []const u8 = switch (b.graph.host.result.os.tag) {
        .macos => &.{
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
