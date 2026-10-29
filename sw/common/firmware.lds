SECTIONS {
    .memory : {
        . = ORG;            /* set up with --defsym=ORG=0x0 or --defsym=ORG=0x800 */
        *(.init); 
		*(.text); 
		*(*);
        . = ALIGN(4);
        end = .;
    }
}