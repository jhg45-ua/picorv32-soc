SECTIONS {
    .memory : {
        . = ORG;            /* se pasa con --defsym=ORG=0x0 o 0x800 */
        *(.init); 
		*(.text); 
		*(*);
        . = ALIGN(4);
        end = .;
    }
}