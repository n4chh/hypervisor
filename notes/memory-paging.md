# Introduction

Memory Paging is a management of the memory that introduce an abstraction between physical and logical addresses. This provides many benefits to handle memory of the programs:
1. Program can use memory that isn't contiguous.
2. Memory can be separated into spaces allowing setting permissions at different regions of the memory. Depending on the processor used, page entries will look different and enable different set's of capabilities, such as page flags in Intel.

To use memory paging, the CPU must have a [Memory Management Unit](https://en.wikipedia.org/wiki/Memory_management_unit) which is the main hardware that performs memory translation. It will also need that the operating system kernel gives the corresponding code to handle the pages.

Performing all the translations can be slow, that way the Translation Layer Buffer will cache recent accessed pages to speed up the process.

Before we load our kernel, we must set a usable way of accessing ram, we will implement memory management for our hypervisor during the bootloader, taking advantage of UEFI services to access the hardware.


## Intel
Memory paging is enabled by a `mov` instruction to `CR0`. There are 4 different type of memory paging modes:


| Mode | Bits | CR0.PG | CR4.PAE | IA32_EFER.LME | CR4.LA57 | Max Physical Address |
|---|---|---|---|---|---|---|
| 32-bit paging | 32 | 1 | 0 | — | — | 40-bit (with PSE-36) |
| PAE (Physical Address Extension) paging | 32 | 1 | 1 | 0 | — | 52-bit |
| 4-level paging (IA-32e) | 48 | 1 | 1 | 1 | 0 | 52-bit |
| 5-level paging (IA-32e) | 57 | 1 | 1 | 1 | 1 | 52-bit |

Switching between memory paging modes requires to fully disable it (unsetting `CR0`) and enabling the corresponding flags/registers for the desired mode.


### (TODO) Pages Entries
Depending on the mode, page entries will vary in size and offer different capabilities.

> **Why offset bits = log2(page size)**
> The page offset must be able to address every single byte inside a page. A page of N bytes needs exactly log2(N) bits for that, because 2^bits = number of addressable bytes. So:
> - 4KB  = 2^12 bytes → 12 offset bits
> - 2MB  = 2^21 bytes → 21 offset bits
> - 4MB  = 2^22 bytes → 22 offset bits
> - 1GB  = 2^30 bytes → 30 offset bits
>
> The remaining bits of the address are then split among the paging table indices, each one selecting a 512- or 1024-entry table at that level.

#### 32-bit Paging

32-bit paging uses 10-bit indices (1024 = 2^10 entries per table).

**4KB pages** (CR4.PSE=0 or PDE.PS=0):

| Bits 31:22 | Bits 21:12 | Bits 11:0 |
|---|---|---|
| PD index (10 bits) | PT index (10 bits) | Page offset (12 bits) |

**4MB pages** (CR4.PSE=1 and PDE.PS=1):

| Bits 31:22 | Bits 21:0 |
|---|---|
| PD index (10 bits) | Page offset (22 bits) |



**Page-Directory Entry (PDE)**

| Bit(s) | Name | Description |
|---|---|---|

**Page-Table Entry (PTE)**

| Bit(s) | Name | Description |
|---|---|---|

#### PAE Paging

PAE uses 9-bit indices (512 = 2^9 entries per table), but only 2 bits for the top-level PDPT (4 entries).

**4KB pages** (PDE.PS=0):

| Bits 31:30 | Bits 29:21 | Bits 20:12 | Bits 11:0 |
|---|---|---|---|
| PDPT index (2 bits) | PD index (9 bits) | PT index (9 bits) | Page offset (12 bits) |

**2MB pages** (PDE.PS=1):

| Bits 31:30 | Bits 29:21 | Bits 20:0 |
|---|---|---|
| PDPT index (2 bits) | PD index (9 bits) | Page offset (21 bits) |

**Page-Directory-Pointer-Table Entry (PDPTE)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Directory Entry (PDE)**
| Bit(s) | Name | Description |
|---|---|---|

**Page-Table Entry (PTE)**
| Bit(s) | Name | Description |
|---|---|---|

#### 4-Level Paging (IA-32e)

All tables use 9-bit indices (512 entries). Only bits 47:0 are used for translation — bits 63:48 must be copies of bit 47 (the highest used bit). This is called a **canonical address**; violating it causes a #GP fault. It splits the address space into two regions:
- `0x0000_0000_0000_0000 – 0x0000_7FFF_FFFF_FFFF` — user space (bit 47 = 0, so bits 63:48 = 0)
- `0xFFFF_8000_0000_0000 – 0xFFFF_FFFF_FFFF_FFFF` — kernel space (bit 47 = 1, so bits 63:48 = 1)

The gap in between is non-canonical and always faults. Intel reserves those bits for future extensions (5-level paging already uses bit 56).

**4KB pages** (PDE.PS=0):

| Bits 63:48 | Bits 47:39 | Bits 38:30 | Bits 29:21 | Bits 20:12 | Bits 11:0 |
|---|---|---|---|---|---|
| Sign ext. (must match bit 47) | PML4 index (9 bits) | PDPT index (9 bits) | PD index (9 bits) | PT index (9 bits) | Page offset (12 bits) |

**2MB pages** (PDE.PS=1):

| Bits 63:48 | Bits 47:39 | Bits 38:30 | Bits 29:21 | Bits 20:0 |
|---|---|---|---|---|
| Sign ext. (must match bit 47) | PML4 index (9 bits) | PDPT index (9 bits) | PD index (9 bits) | Page offset (21 bits) |

**1GB pages** (PDPTE.PS=1):

| Bits 63:48 | Bits 47:39 | Bits 38:30 | Bits 29:0 |
|---|---|---|---|
| Sign ext. (must match bit 47) | PML4 index (9 bits) | PDPT index (9 bits) | Page offset (30 bits) |

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

#### 5-Level Paging (IA-32e)

Same structure as 4-level but adds one more table level, extending the address space to 57 bits. Now bit 56 is the canonical bit — bits 63:57 must all match it.

**4KB pages** (PDE.PS=0):

| Bits 63:57 | Bits 56:48 | Bits 47:39 | Bits 38:30 | Bits 29:21 | Bits 20:12 | Bits 11:0 |
|---|---|---|---|---|---|---|
| Sign ext. (must match bit 56) | PML5 index (9 bits) | PML4 index (9 bits) | PDPT index (9 bits) | PD index (9 bits) | PT index (9 bits) | Page offset (12 bits) |

**2MB pages** (PDE.PS=1):

| Bits 63:57 | Bits 56:48 | Bits 47:39 | Bits 38:30 | Bits 29:21 | Bits 20:0 |
|---|---|---|---|---|---|
| Sign ext. (must match bit 56) | PML5 index (9 bits) | PML4 index (9 bits) | PDPT index (9 bits) | PD index (9 bits) | Page offset (21 bits) |

**1GB pages** (PDPTE.PS=1):

| Bits 63:57 | Bits 56:48 | Bits 47:39 | Bits 38:30 | Bits 29:0 |
|---|---|---|---|---|
| Sign ext. (must match bit 56) | PML5 index (9 bits) | PML4 index (9 bits) | PDPT index (9 bits) | Page offset (30 bits) |

**Page-Map Level-5 Entry (PML5E)**
| Bit(s) | Name | Description |
|---|---|---|
