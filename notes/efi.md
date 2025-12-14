# Introduction
EFI (Extensible Firmware Interface) System Partition or ESP, is a partition on a drive that is used by systems that are compatible UEFI (Unified Extensible Firmware Interface).

UEFI is a **first stage boot loader** which reads the ESP to load all the necessary services and processes to finally load the operative system or a **second stage boot loader** (which is also stored on ESP).
As a quick overview of the booting process, UEFI will firstly perform some security check to verify integrity of the firmware through a SEC phase. Then it will trigger PEI (Pre-EFI-Initialitation), loading and initialiting some necessary hardware components like DRAM, perform any ACPI operations and dispatch PEIMs (PEI Modules).
Then it will load all the remaining drivers during DXE (Driver Execution Environment) but also setup and initialize important parts such as the CPU, the main board, some IO devices and booting devices (during Boot Devices Selector). Lastly UEFI will hands-off the control flow to the operative system after the TSL (Transitien System Load). 
On RT (Run Time) phase, the UEFI compatible Operative System now has the control flow and will unload all the resources used by the UEFI firmware (mainly drivers), as modern OSs usually use kernel drivers to interact and handle hardware devices. 

## Main Components
### Boot Loader, Boot Managers and Kernel Images
This element are the responsables of loading the operating system.
#### Kernel Images
Nowadays a kernel can be loaded without having a boot loader using an EFI System Partition. This task is possible configuring [efi stubs](https://en.wikipedia.org/wiki/EFI_system_partition#Linux_Kernel_EFI_Boot_Stub).
#### Boot Loaders and Boot Manager
A boot loader is a type of firmware which is the main responsable of booting a computer and loading an Operating System. 
If they offers a menu with several options to select the operating system to boot (e.g. [GRUB](https://en.wikipedia.org/wiki/GNU_GRUB)) is also called a `boot manager`.

##### First Stage bootloader
Load the required hardware devices of the computer like RAM, CPU, ACPI, etc and hands-off the execution flow to an operative system.
One example can be [UEFI]. They are firmwares, which means they are stored on hardware and frecuently loaded from [boot ROM](https://en.wikipedia.org/wiki/Boot_ROM).
##### Second Stage bootloader
They perform extra operation, like extra drivers, loading a temporary root filesystem (e.g. [initrd](https://en.wikipedia.org/wiki/Initial_ramdisk)) and pass booting parameters to the kernel.
That way the offer a taylored way of loading an operative system once main components are already initilalized and available.
One example can be [GRUB](https://en.wikipedia.org/wiki/GNU_GRUB). They are computer programs which mean they are not stored on the hardware, in the context of this document we expect them to be stored on the ESP.
