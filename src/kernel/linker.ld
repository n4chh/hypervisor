/*
 * Same standar as Linux kerenel We'll probably change this in the future to our own thing:
 * kernel base -> 0xFFFFFFFF80000000
 * kernel text -> 0xFFFFFFFF80100000
 * Direct map (where heap allocates) -> 0xFFFF888000000000 - 0xFFFF88FFFFFFFFF
 * Ref??? Need to figure out which one is the most updated, claude found the first one, but during my google research I found the second one.
 * 	https://docs.kernel.org/arch/x86/x86_64/mm.html
 * 	https://www.kernel.org/doc/Documentation/x86/x86_64/mm.txt
 */

KERNEL_VADDR_BASE = 0xFFFFFFFF80000000;
KERNEL_VADDR_TEXT = 0xFFFFFFFF80100000;

/*
 * 
 * Prefix 'l' in the section stands from large. In x86_64 medium code model, large globals are placed further away 
 * from  small globals.
 * So lbss is Large Block Symbol Section
 * Ref: https://lld.llvm.org/ELF/large_sections.html
 * */
SECTIONS {
	. = KERNEL_VADDR_TEXT;
	
	.text ALIGN(4K) : AT (ADDR(.text) - KERNEL_VADDR_BASE) {
		*(.text)
		*(.ltext)
	}

	.rodata ALIGN(4K) : AT (ADDR(.rodata) - KERNEL_VADDR_BASE) {
		/* TODO 
		 * Must investigate why we don't create a lrodata section
		 * */
		*(.rodata)
	}

	.data ALIGN(4K) : AT (ADDR(.data) - KERNEL_VADDR_BASE) {
		*(.data)
		*(.ldata)
	}

	.bss ALIGN(4K) : AT (ADDR(.bss) - KERNEL_VADDR_BASE) {
		*(COMMON)
		*(.bss)
		*(.lbss)
	}
}
