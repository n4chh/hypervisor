# Introduction

Memory Paging is a management of the memory that introduce an abstraction between physical and logical addresses. This provides many benefits to handle memory of the programs:
1. Program can use memory that isn't contiguous.
2. Memory can be separated into spaces  allowing to set permissions at different regions of the memory. Depenging on the processor used, page entries will look different and enable different set's of capabilities, such as page flags in Intel.

To use memory paging, the CPU must have a [Memory Management Unit](https://en.wikipedia.org/wiki/Memory_management_unit) which is the main hardware that performs memory translation. It will also need that the operating system kernel gives the corresponding code to handle the pages.

Performing all the translations can be slow, that way the Translation Layer Buffer will cache recent accessed pages to speed up the process.

Before we load our kernel, we must set a usable way of accessing ram, we will implement memory management for our hypervisor during the bootloader, taking advantage of UEFI services to access the hardware.


## Intel
Memory paging is enabled by a `mov` instruction to `CR0`. There are 4 different type of memory paging modes:


| Mode | Bits | CR0.PG | CR4.PAE | IA32_EFER.LME | CR4.LA57 | Max Physical Address |
|---|---|---|---|---|---|---|
| 32-bit paging | 32 | 1 | 0 | — | — | 40-bit (with PSE-36) |
| PAE paging | 32 | 1 | 1 | 0 | — | 52-bit |
| 4-level paging (IA-32e) | 48 | 1 | 1 | 1 | 0 | 52-bit |
| 5-level paging (IA-32e) | 57 | 1 | 1 | 1 | 1 | 52-bit |

Switching between memory paging modes requires to fully disable it (unsetting `CR0`) and enabling the corresponding flags/registers for the desired mode.


### (TODO) Pages Entries
Depending on the mode, page entries will vary in size and also will offer different capabilities.

#### 32-bit paging

**Page-Directory Entry (PDE)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Table Entry (PTE)**
| Bit(s) | Name | Description |
|---|---|---|

#### PAE paging

**Page-Directory-Pointer-Table Entry (PDPTE)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Directory Entry (PDE)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Table Entry (PTE)**
| Bit(s) | Name | Description |
|---|---|---|

#### 4-level paging (IA-32e)

**Page-Map Level-4 Entry (PML4E)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Directory-Pointer-Table Entry (PDPTE)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Directory Entry (PDE)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Table Entry (PTE)**
| Bit(s) | Name | Description |
|---|---|---|

#### 5-level paging (IA-32e)

**Page-Map Level-5 Entry (PML5E)**
| Bit(s) | Name | Description |
|---|---|---|
