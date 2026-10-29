SECTIONS {
	.memory : {
		. = 0x000800;
		*(.init);
		*(.text);
		*(*);
		. = ALIGN(4);
		end = .;
	}
}

