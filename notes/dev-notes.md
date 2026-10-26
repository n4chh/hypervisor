The page fault may be due to a wrong memcpy when setting our new writable page:
**qemu:**
```
!!!! X64 Exception Type - 0E(#PF - Page-Fault)  CPU Apic ID - 00000000 !!!!
ExceptionData - 000000000000000B  I:0 R:1 U:0 W:1 P:1 PK:0 SS:0 SGX:0
```
**gdb:**
```
gef> x/20x 0x000000001E3C2000
0x1e3c2000:	0x1fc02023	0x00000000	0x00000000	0x00000000
0x1e3c2010:	0x00000000	0x00000000	0x00000000	0x00000000
0x1e3c2020:	0x00000000	0x00000000	0x00000000	0x00000000
gef> info reg cr0
cr0            0x80010033          [ PG WP NE ET MP PE ]
gef> info reg cr2
cr2            0xffffffff80100000  0xffffffff80100000
gef> info reg cr3
cr3            0x1e3c2000          [ PDBR=123842 PCID=0 ]
```

