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

The new version (OS 1.2B) adds:
- **Line editor** — OSWORD 0 reimplemented with insert/delete, cursor movement within the line, cursor up/down by screen width, and single-line history recall via CRC16 matching
- **Shift+cursor** — in the default `*FX 4,1` mode, Shift+cursor keys enter split cursor editing mode
- **Size optimizations** — compact screen clear loop, dead code removal, and micro-optimizations from the original disassembly annotations
