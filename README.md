# BBC Micro OS 1.20

A disassembly of the BBC Micro OS 1.20 ROM as 6502 assembly source, assemblable by [BeebAsm](https://github.com/stardot/beebasm).

## Building

```
beebasm -i original.6502 -o OS120.rom     # byte-identical to original ROM
beebasm -i new.6502 -o OS120new.rom       # optimized version, reports free bytes
```

## About

OS 1.20 is the final version of the BBC Micro's Machine Operating System (MOS), providing the core firmware for the BBC Model B and B+ microcomputers. This project aims to produce a fully documented, annotated source file that assembles to a byte-identical copy of the original ROM, with conditional assembly support for size optimizations that free up space for new functionality.
