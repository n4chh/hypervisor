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
This will place the binaries inside `/usr/share/edk2-ovmf/`
```bash
emerge -a app-emulation/qemu acct-group/kvm
```

## Fedora
Install `ovmf` if not installed
```bash
sudo dnf install edk2-ovmf
```
Thiw will place the binaries inside `/usr/share/edk2/ovmf/`.

## MacOS
In MacOS things aren't that easy.
Default QEMU binary packed into Brew (at least at the moment of pushing this change), is not compiled with support for HVF (Apple's Hyper Virtualization Framework). This is necessary as is the alternative of KVM in MacOS, which without it -we are not going to be able to use hardware acceleration and nest virtualization.

Moreover there is no official builted binary available in Brew for OVMF (which is needed to run UEFI Applications) 

To overcome this there are 2 alternatives:
1. **(Recommended) Use UTM**.
    [UTM](https://mac.getutm.app/) has a custom qemu binary compiled with all necesary flags. It also has all the OVMF firmware device configured.

2. **Compile OVMF and QEMU manually**.
    You can compile OVMF and QEMU manually following the documentation to enable hvf (search for `--enable-hvf` in their official docs).


### UTM

To use UTM to start our application, follow the next steps
#### 1. Download UTM
```
brew install --cask utm
```
#### 2. Ensure UTM's Qemu path in build.zig is correct

Ensure that OVMF is available in your UTM installation.
If you don't know where it is located, you can find it by creating a machine in UTM (see instructions below). Inside the VM settings (right click on your machine and select `Edit`), you can click to qemu arguments tab, then click on export command. 

#### 3. Run the application
Use zig to build and run the application:
```
zig build run
```

### Debugging
[OSDEV Wiki: Debugging UEFI applications with GDB](https://wiki.osdev.org/Debugging_UEFI_applications_with_GDB)
> Debugging UEFI binaries can be challenging because you typically don't know the address where your image will be loaded at runtime, complicating both getting an initial breakpoint and symbol loading. One workaround is have your application write its loaded base address to a known memory location, together with a marker value, so GDB can watch for it and reload symbols at the correct address.

[Debugging UEFI app in GDB](https://www.reddit.com/r/osdev/comments/144gojm/help_debugging_uefi_application_with_gdb_in_vs)
[Ziggit thread talking about why is not possible to debug .pdb inside GDB](https://ziggit.dev/t/how-to-change-the-debug-symbol-format-for-zig-build-on-windows/4836)
[Gdb and debug symbol in pdb](https://sourceware.org/legacy-ml/cygwin/2006-06/msg00164.html<Find>)
[Official docs of gdb](https://qemu-project.gitlab.io/qemu/system/gdb.html) 



#### Load EFI file inside lldb

##### Attach to the qemu's gdb server 
```lldb
gdb-remote 1234
```
##### Create a module
```lldb
target modules create zig-out/bin/BOOTX64.EFI.efi --symfiles zig-out/bin/BOOTX64.EFI.pdb
```
##### Add the symbols to the module
```lldb
target modules add -s zig-out/bin/BOOTX64.EFI.pdb
```

**TODO**: add debuging instructions

The VM is now configured to execute our EFI application.

### Create a Virtual Machine on UTM
#### 1. Create a Virtual Machine on UTM
If you are on ARM device, select Emulate (as this project creates an x86_64 EFI executable).

In operating system select `other`, then continue with the default options.

In boot Device, select `None`

Before finishing with the creation of the machine, click on `Open VM Settings`, then continue.

#### 2. Add EFI path as drive.
(If you didn't click on `Open VM Settings`, right click on your machine, then click on edit)

To launch our EFI application, we should specify it as a drive.

Go to the QEMU > Arguments section.

Scroll to the bottom and create a new one.
Specify the path of the EFI directory.

```
-drive file=fat:rw:/Users/nachh/Desktop/Github/hypervisor/zig-out/img,format=raw
```
Before exiting, create a new empty argument, then click on save, otherwise this parameter won't be saved.

**Note:** If you get an error similar to: `Couldn't read the directory </path/to/your/efi/img/>`, check you give disk access to the UTM app from the MacOS settings. If error persist, create a normal VM with any OS, go to Sharing inside VM settings, enable it and check if you are able to access your disk (e.g. your MacOS Desktop) from this new VM. If this succeed try to relaunch our initial VM.


#### 3. Remove generated drive

Go to the Drives Section.
There you can find the new drive generated on the previous steps.

Remove it.

**Note:** This is required because we are already using a "disk", which is what we specify before with the `-drive` option. If we don't remove it we will get something like:
```
QEMU exited from an errro: qemu-x86_64-softmmu: -device ide-hd,bus=ide.0,drive=drive<ID>,bootindex=0: Cant' create IDE unit 1, bus supports only 1 units
```
