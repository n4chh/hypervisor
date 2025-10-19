const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
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
    
    b.installArtifact(bootloader);

    const out_dir_name = "img";
    const install_bootloader = b.addInstallFile(
        bootloader.getEmittedBin(),
        b.fmt("{s}/efi/boot/{s}", .{out_dir_name, bootloader.name}),
    );
    b.getInstallStep().dependOn(&install_bootloader.step);


    const qemu_args = [_][]const u8{
        "qemu-system-x86_64",
        "-m",
        "512M",
        "-bios",
        "/usr/share/ovmf/OVMF.fd",
        "-drive",
        b.fmt("file=fat:rw:{s}/{s},format=raw", .{b.install_path, out_dir_name}),
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
