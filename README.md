# Introduction
This project is aimed for understanding how Hypervirtualization works under the hood.
I will be building a little bare-metal HyperVirsor in Zig.

# Versions
Zig >=0.15.0 is used to compile the project.

# Distro differences
Depending on the distro used to install the project the `build.zig` file must be edited to set the qemu bios flag to the right location of the OVMF Firmware Device (.fd).

## Gentoo
The `qemu` ebuild will install package `edk2-bin`. This ebuild will install `ovmf` binaries at `/usr/share/edk2-ovmf/`
The desired BIOS to provide to qemu must be `OVMF_CODE.fd`.

# Requirements
## Gentoo
```bash
emerge -a app-emulation/qemu acct-group/kvm
```
