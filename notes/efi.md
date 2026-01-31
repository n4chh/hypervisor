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
That way they offer a taylored way of loading an operative system once main components are already initilalized and available.
One example can be [GRUB](https://en.wikipedia.org/wiki/GNU_GRUB). They are computer programs which mean they are not stored on the hardware, in the context of this document we expect them to be stored on the ESP.

## EFI System Table
EFI has a table which contains a list of pointers to available runtime and boot services that the computer will be able to use to successfully compleate a bootloading process.
Except for the Table Header field, all elements in the table are pointers to functions. Before a call to EFI_BOOT_SERVICES.BootServices, all of the elements of the table contain valid addresses.
Once the Operating System has taken the control flow of the execution, only the `Hdr`, `FirmwareVendor`, `FirmwareRevision`, `NumberOfTableEntries`, `ConfigurationTable` and `RuntimeServices` will contain valid values.

```c
#define EFI_SYSTEM_TABLE_SIGNATURE 0x5453595320494249
#define EFI_2_90_SYSTEM_TABLE_REVISION ((2<<16) | (90))
#define EFI_2_80_SYSTEM_TABLE_REVISION ((2<<16) | (80))
#define EFI_2_70_SYSTEM_TABLE_REVISION ((2<<16) | (70))
#define EFI_2_60_SYSTEM_TABLE_REVISION ((2<<16) | (60))
#define EFI_2_50_SYSTEM_TABLE_REVISION ((2<<16) | (50))
#define EFI_2_40_SYSTEM_TABLE_REVISION ((2<<16) | (40))
#define EFI_2_31_SYSTEM_TABLE_REVISION ((2<<16) | (31))
#define EFI_2_30_SYSTEM_TABLE_REVISION ((2<<16) | (30))
#define EFI_2_20_SYSTEM_TABLE_REVISION ((2<<16) | (20))
#define EFI_2_10_SYSTEM_TABLE_REVISION ((2<<16) | (10))
#define EFI_2_00_SYSTEM_TABLE_REVISION ((2<<16) | (00))
#define EFI_1_10_SYSTEM_TABLE_REVISION ((1<<16) | (10))
#define EFI_1_02_SYSTEM_TABLE_REVISION ((1<<16) | (02))
#define EFI_SPECIFICATION_VERSION    EFI_SYSTEM_TABLE_REVISION
#define EFI_SYSTEM_TABLE_REVISION    EFI_2_90_SYSTEM_TABLE_REVISION

typedef struct {
  EFI_TABLE_HEADER                 Hdr;
  CHAR16                           *FirmwareVendor;
  UINT32                           FirmwareRevision;
  EFI_HANDLE                       ConsoleInHandle;
  EFI_SIMPLE_TEXT_INPUT_PROTOCOL   *ConIn;
  EFI_HANDLE                       ConsoleOutHandle;
  EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL  *ConOut;
  EFI_HANDLE                       StandardErrorHandle;
  EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL  *StdErr;
  EFI_RUNTIME_SERVICES             *RuntimeServices;
  EFI_BOOT_SERVICES                *BootServices;
  UINTN                            NumberOfTableEntries;
  EFI_CONFIGURATION_TABLE          *ConfigurationTable;
} EFI_SYSTEM_TABLE;


```

### Console Handles and Protocols
EFI contains 3 pair of fields for all Console I/O operations. Each pair has a `Handle` value and a `Text Protocol`.

#### Handle
The handle will be the function that program will call to mange output or input on the console. The handle must support its corresponding `Text Protocol`.
The `ConsoleInHandle` apart from `EFI_SIMPLE_TEXT_INPUT_PROTOCOL`, will also need to support `EFI_SIMPLE_TEXT_INPUT_EX_PROTOCOL` which is an extension of the first mentioned protocol that introduce modern capabilities. 

#### Text Protocol
The text protocols are interfaces which contain the necesary information to interact with a Console device. The Handle will use the information available in the interface to produce different behaviours on the console, like printing characters or reading inputs.

For example, this is the interface for the `EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL`:
```c
typedef struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
 EFI_TEXT_RESET                           Reset;
 EFI_TEXT_STRING                          OutputString;
 EFI_TEXT_TEST_STRING                     TestString;
 EFI_TEXT_QUERY_MODE                      QueryMode;
 EFI_TEXT_SET_MODE                        SetMode;
 EFI_TEXT_SET_ATTRIBUTE                   SetAttribute;
 EFI_TEXT_CLEAR_SCREEN                    ClearScreen;
 EFI_TEXT_SET_CURSOR_POSITION             SetCursorPosition;
 EFI_TEXT_ENABLE_CURSOR                   EnableCursor;
 SIMPLE_TEXT_OUTPUT_MODE                  *Mode;
} EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
```

### Boot Services
During boot we mentioned that resourced are owned by the firmware. Boot services are functions that acts as interfaces to communicate and manage those services.
This functions are categorized as `global`, if they manage services and are available in all platforms (as services are always available in all platforms), or as `handle-based`, if they receive a handle to manage an speciffic device that may be not available in all platforms

The main objective of the boot service is to assist UEFI OS in preparing to boot the operating system. When the UEFI loader takes the control of the system and completes OS boot process, the operating system will call `ExitBootServices()` indicating that boot has been successful and is able to assume control of platform and resources.

### Runtime Services
