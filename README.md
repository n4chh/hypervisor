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

# Debugging
## Instructions
First, create a target before attaching to the process. Doing this before attaching to QEMU Monitor server will be faster and save us tons of struggle.
```lldb
target create zig-out/img/efi/boot/BOOTX64.EFI
```
Then attach to the server.
```lldb
gdb-remote 1234
```
Based in [OSDEV Wiki: Debugging UEFI applications with GDB](https://wiki.osdev.org/Debugging_UEFI_applications_with_GDB), we setup a known memory address with a known value in code (see `storeSymbols` in `src/bootloader/boot.zig`).
> Debugging UEFI binaries can be challenging because you typically don't know the address where your image will be loaded at runtime, complicating both getting an initial breakpoint and symbol loading. One workaround is have your application write its loaded base address to a known memory location, together with a marker value, so GDB can watch for it and reload symbols at the correct address.

We also will add symbols in `DWARF` format as mentioned in [[#Debug format]] to the EFI binary to let LLDB automatically detect all symbols.
Then we setup a watchpoint at that memory address:
```lldb
watchpoint set expr -- 0x10000
```
Then we attach a command to the watchpoint. This will be launched anytime the watchpoint is trigger, which will be handy to reload symbols after restarting the qemu server.
```lldb
watchpoint command add
target modules load -f BOOTX64.EFI -s `*(long long *)0x10008`
DONE
```


## Tools
We will use LLDB with [LLEF](https://github.com/foundryzero/llef) to improve visuals and features of LLDB.
#### Why don't choose GDB?
Although GDB seem to have less random crashes during debugging sessions, GDB doesn't have native support to PE files. This means, that even if we include dwarf symbols inside the PE file, GDB won't detect them correctly:
```
(remote) gef➤  add-symbol-file zig-out/img/efi/boot/BOOTX64.EFI -o $base
add symbol table from file "zig-out/img/efi/boot/BOOTX64.EFI" with all sections offset by 0x1e065000
Reading symbols from zig-out/img/efi/boot/BOOTX64.EFI...
[*] Not a valid file format: Not a valid ELF file (magic)
``` 
#### Generating code for GDB
One easy way to create a valid ELF file, is to change temporarily the UEFI binary target to `.linux`. After having your `QEMU` monitor server running (using `zig build debug`), run `zig build`, to generate the ELF file once is running.
```zig
    const bootloader = b.addExecutable(.{
        .name = "BOOTX64.EFI",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bootloader/boot.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
		// ^^^ this line changed ^^^
            }),
// [...]
```
**NOTE**: Every time we run `zig build *` commands, our compiled UEFI application will be copied to the `zig-out/img/efi/boot/BOOTX64.EFI` and overwrite the existing binary that was there. Remember that UEFI uses PE format, so if you must run `zig build debug` before changing the `os_tag` to `.linux`.

### Zig build Options
#### Debug format
Debugging PDB is one of the most painful tasks of the entire process. In one hand, GDB doesn't add support for PDB files at all.
Unfortunatelly for us, [LLDB only partially read debug symbols in .pdb files](https://github.com/llvm/llvm-project/issues/78535). 

This is the first time in the entire project I ended up asking AI for hyphothesis of what it could be the reason why I didn't have debug symbols. Specifically I notice when searching a `pub fn` using `image lookup -s <symbol_name>` it gives me a valid address, while normal ones shown an empty address:
```
(lldb) image lookup -n readKernel
1 match found in /home/nachh/Desktop/Github/hypervisor/zig-out/img/efi/boot/BOOTX64.EFI:
        Address:  ()
        Summary:
(lldb) image lookup -n storeSymbols
1 match found in /home/nachh/Desktop/Github/hypervisor/zig-out/img/efi/boot/BOOTX64.EFI:
        Address: BOOTX64.EFI[0x000000000002b6a0] (BOOTX64.EFI..text + 173728)
        Summary: BOOTX64.EFI`storeSymbols at boot.zig:155
```

**TL;DR**

Solution I came up with is to force dwarf format inside zig build system:
```zig
    .dwarf_format = .@"64",
```
#### Backend
[Zig doesn't use llvm backend as default](https://ziggit.dev/t/no-symbol-in-lldb-debugger/12511/5)
If debug symbols fail to appear inside elf binaries. is wort to use llvm linker and backend:
```zig
// Add this to the different executable/artifacts inside build.zig
.use_llvm = true,
.use_lld = true,
```

### LLDB Basics
#### Scripts
All we mentioned before, could be seted up in a custom script. Unfortunately the python API for attaching functions to a specific watchpoint is not yet defined.
Before using any function defined in any script, we must import it.
```lldb
command script import watchpoints
```
Then lldb commands that accept python functions will be able to resolve them.
```llbd
watchpoint command add -F watchpoints.get_image_base
```

#### Create a module
```lldb
target modules create zig-out/bin/BOOTX64.EFI.efi --symfiles zig-out/bin/BOOTX64.EFI.pdb
```
#### Set the load address of all sections
**Note:** `-s` flag adds the provided offset to the base address defined in the object. To see the default ImageBase address use:
```bash
 llvm-readobj --headers zig-out/bin/BOOTX64.EFI.efi | grep -i ImageBase -C 4
```
**Example**
```
  SizeOfInitializedData: 40960
  SizeOfUninitializedData: 0
  AddressOfEntryPoint: 0x1C010
  BaseOfCode: 0x1000
->ImageBase: 0x0        
  SectionAlignment: 4096
  FileAlignment: 512
  MajorOperatingSystemVersion: 6
  MinorOperatingSystemVersion: 0
```

```lldb
target modules load -f BOOTX64.EFI.efi -s <offset>
```
#### Attach to the qemu's gdb server 
```lldb
gdb-remote 1234
```


### Usefull guides
[Debugging UEFI app in GDB](https://www.reddit.com/r/osdev/comments/144gojm/help_debugging_uefi_application_with_gdb_in_vs)
[Ziggit thread talking about why is not possible to debug .pdb inside GDB](https://ziggit.dev/t/how-to-change-the-debug-symbol-format-for-zig-build-on-windows/4836)
[Gdb and debug symbol in pdb](https://sourceware.org/legacy-ml/cygwin/2006-06/msg00164.html<Find>)
[Official docs of gdb](https://qemu-project.gitlab.io/qemu/system/gdb.html) 

### Manual way to find base address
One way to locate the base address in runtime will be:
1. Set up a whatchpoint in a known addres:
    ```
    # this will automatically set it to modify type watchpoint
    watchpoint set expression -- 0x10000
    ```
2. Continue application until you hit the whatcpoint.
3. Once watchpoint is hit, locate the assembly values the binary:

    **Value to search**
    ```
    1c1d7:	75 2b                	jne    0x1c204
    1c1d9:	eb 35                	jmp    0x1c210
    1c1db:	48 8b 45 e0          	mov    -0x20(%rbp),%rax
    1c1df:	48 89 45 c0          	mov    %rax,-0x40(%rbp)
    1c1e3:	eb ab                	jmp    0x1c190
    1c1e5:	48 8b 4d d8          	mov    -0x28(%rbp),%rcx
    1c1e9:	e8 f2 05 01 00       	call   0x2c7e0
    1c1ee:	48 8b 4d d8          	mov    -0x28(%rbp),%rcx
    ```

    **Commands**
    ```bash
    # Use whatever feels you better to find patterns, neovim is useful to me.
    objdump -d zig-out/bin/BOOTX64.EFI.efi | nvim
    ```
    **RegEx Pattern**
    ```regex
    jne.*\n.*jmp.*\n.*-0x20(%rbp).*%rax\n.*%rax,-0x40(%rbp)\n.*jmp.*190\n.*mov.*-0x28(%rbp),%rcx\n.*call.*7e0\n.*\n.*call.*c20
    ```
4. Substract relative address from actuall address to obtain base address.
    ```lldb
    (lldb) p/x 0x1e11d1f2 - 0x1c1f2
    (int) 0x1e101000
    ```
    **Note**: Due to some reason I still don't know, UEFI LoadedImage.BaseAddres points to a completely different address which is located in the stack of the current application (weird):
    ```
    [warn] (bootloader): Located UEFI Application base address at u8@1fe8f000
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
