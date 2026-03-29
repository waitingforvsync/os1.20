# BBC Micro OS 1.20

A disassembly of the BBC Micro OS 1.20 ROM as 6502 assembly source, assemblable by [BeebAsm](https://github.com/stardot/beebasm).

## Building

```
beebasm -i original.6502      # byte-identical to original OS 1.20 ROM
beebasm -i new.6502            # optimized version (OS 1.2B), reports free bytes
```

## Testing

Requires [beebjit](https://github.com/scarybeasts/beebjit).

```
./test.sh
```

The test script runs both ROMs through beebjit with scripted input (MODE changes, screen clears, keyboard input, BASIC commands) and compares captured frames. Expected differences are the version string ("OS 1.20" vs "OS 1.2B") and transient screen clear patterns.

## About

OS 1.20 is the final version of the BBC Micro's Machine Operating System (MOS), providing the core firmware for the BBC Model B and B+ microcomputers. This project aims to produce a fully documented, annotated source file that assembles to a byte-identical copy of the original ROM, with conditional assembly support for size optimizations that free up space for new functionality.

The new version (OS 1.2B) adds the following features:

### Line editor

OSWORD 0 (read line) is reimplemented with proper line editing:

- **Insert and delete** — characters are inserted at the cursor position, shifting the rest of the line right. Delete removes the character before the cursor, shifting the rest left.
- **Cursor left/right** — move the cursor within the entered line without changing it.
- **Cursor up/down** — move the cursor by one screen row (text window width) at a time, clamped to the start and end of the line.
- **History recall** — pressing cursor up on an empty line recalls the previously entered line, if the buffer contents are still intact. This is detected by comparing a CRC16 checksum of the buffer against a stored value from the last RETURN. Note: this does not work well with BASIC, which tokenises the input buffer in place after RETURN, overwriting the original text with keyword tokens.
- **RETURN, ESCAPE, CTRL+U** — these move the cursor to the end of the line before acting, so the display is left in a clean state.

All existing OSWORD 0 parameter block features are preserved: maximum line length, minimum and maximum acceptable character codes, and VDU queue handling.

### Shift+cursor split cursor mode

The OS defaults to `*FX 4,1`, which returns cursor key codes to the application for line editing. Holding Shift while pressing a cursor key enters the traditional BBC split cursor editing mode (read from screen with COPY key), allowing both features to coexist. `*FX 4,0` restores the original OS 1.20 cursor editing behaviour.

### Size optimizations

Space for the new features was created by replacing the unrolled screen clear with a compact loop, removing dead code, and applying micro-optimizations identified in the original disassembly annotations.
