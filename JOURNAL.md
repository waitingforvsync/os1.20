# JOURNAL.md

Development journal documenting discoveries, hurdles, and solutions.

---

## 2026-03-27: Initial ACME to BeebAsm Conversion

### Source Material
- Fetched Toby Nelson's fully annotated ACME-format disassembly of OS 1.20 from https://tobylobster.github.io/mos/os120_acme.a (20,917 lines, ~1.1MB)
- Downloaded reference ROM from https://github.com/tom-seddon/b2/blob/master/etc/roms/OS12.ROM (16KB, MD5: `0a59a5ba15fe8557b5f7fee32bbd393a`)

### Approach
Wrote a Python conversion script (`convert.py`) to mechanically translate ACME syntax to BeebAsm. The source uses no macros, conditionals, zones, or includes — it's a straightforward linear assembly, which made automated conversion feasible.

### Conversion Rules Applied
| ACME | BeebAsm | Count |
|------|---------|-------|
| `* = $addr` | `ORG &addr` | 2 |
| `$hex` | `&hex` | throughout |
| `!byte` | `EQUB` | 1,272 |
| `!word` | `EQUW` | 129 |
| `!text` | `EQUS` | 60 |
| `!be16 expr` | `EQUB HI(expr), LO(expr)` | 77 |
| `%..####..` binary | `%00111100` standard | 768 |
| `+`/`-`/`++`/`--` anon labels | `._anonXXX` named labels | 374 |
| `.name = val` constants | `name = val` (strip dot) | 791 |
| `.label` references | `label` (strip dot) | throughout |
| `<`/`>` lo/hi byte | `LO()`/`HI()` | throughout |
| `XOR` | `EOR` | 2 |
| bare `LSR`/`ASL`/`ROL`/`ROR` | explicit `A` operand | 207 |

### Hurdles and Solutions

#### 1. Label dot semantics differ between ACME and BeebAsm
**Problem:** In ACME, the dot is part of the label name everywhere (`.myLabel` in both definitions and references). In BeebAsm, `.` is a prefix meaning "define label at current PC" and is NOT part of the name — references use the bare name.

**Solution:** The script strips dots from all label/constant references in operands, keeps dots on label definitions, and strips dots from constant definitions (`.charBELL = 7` → `charBELL = 7`).

#### 2. Forward reference in constant definition
**Problem:** BeebAsm evaluates variable assignments (`name = expr`) immediately, so forward references fail. Found one case: `mosVariablesMinus166 = mosVariables - 166` appeared before `mosVariables = &0236`.

**Solution:** Added a pre-pass to detect forward references among constant definitions and defer their output until after the dependency is defined. Only 1 out of 791 constants had this issue.

#### 3. BeebAsm requires explicit accumulator mode
**Problem:** ACME accepts bare `LSR` for accumulator mode; BeebAsm requires `LSR A`. Assembly failed with "Implied mode not allowed for this instruction."

**Solution:** Added regex to append ` A` to bare `LSR`, `ASL`, `ROL`, `ROR` instructions. 207 occurrences.

#### 4. XOR operator not supported in BeebAsm
**Problem:** ACME uses `XOR` for bitwise exclusive-or in expressions. BeebAsm uses `EOR`. Only 2 occurrences, both in character comparison expressions.

**Solution:** Simple `\bXOR\b` → `EOR` replacement.

#### 5. Zero-page address wrapping with negative offsets
**Problem:** Three instructions used a pattern like `LDA .tapeSaveEndAddressLow - $00FD,X` where ACME computes `$B4 - $FD = $FFB7` via 16-bit unsigned wraparound, assembling as absolute addressing (`LDA $FFB7,X`). BeebAsm produced a negative result and errored.

**First attempt:** Used `LO(addr - &FD)` to mask to 8 bits — assembled successfully but produced zero-page addressing (`LDA $B7,X`, 2 bytes) instead of the original's absolute addressing (`LDA $FFB7,X`, 3 bytes). This shifted all subsequent code by 3 bytes and caused 3,230 byte differences in the output!

**Second attempt:** Used `(addr - &FD) AND &FFFF` — but the leading parenthesis made BeebAsm interpret it as indirect addressing mode.

**Final solution:** Used `0 + (addr - &FD) AND &FFFF` — the leading `0 +` prevents BeebAsm from seeing the parenthesis as an indirect addressing mode indicator, while `AND &FFFF` masks to 16 bits to match ACME's unsigned wraparound. This produced the correct 3-byte absolute addressing.

#### 6. Big-endian word pseudo-op
**Problem:** ACME has `!be16` for big-endian 16-bit words. BeebAsm has no equivalent.

**Solution:** Converted `!be16 expr` to `EQUB HI(expr), LO(expr)` which outputs the high byte first, then low byte — matching big-endian byte order. 77 occurrences, used in lookup tables (multiply-by-640, multiply-by-40) and star command dispatch tables.

#### 7. ACME binary literal notation
**Problem:** ACME allows `.` for `0` and `#` for `1` in binary literals (`%..####..`), used extensively in character bitmap definitions to create a visual representation. BeebAsm only accepts standard `0` and `1`.

**Solution:** Regex replacement within `%`-prefixed binary literals: `.` → `0`, `#` → `1`. 768 occurrences. This loses the visual bitmap quality of the original but is functionally identical.

### Result
Assembly produces a byte-identical 16KB ROM. MD5 verified: `0a59a5ba15fe8557b5f7fee32bbd393a`.

---

## 2026-03-27: Fixed Address Constants and SKIPTO

### Motivation
The OS ROM has well-known entry points (OSWRCH at &FFEE, OSBYTE at &FFF4, etc.) that user programs depend on. If code modifications shift these addresses, the ROM would be incompatible. By defining them as constants and using `SKIPTO` to anchor them, the assembler will error if code grows past a fixed boundary rather than silently shifting everything.

### Changes Made
Added a "Fixed addresses" constant block before `ORG &C000` defining all well-known addresses:

- **OS entry points** (OSRDRM through OSCLI, &FFB9-&FFF7) — the public API
- **DEFVTL/DEFVTP** (&FFB6/&FFB7) — default vector table length and pointer
- **EXTVEC** (&FF00) — extended vector jump table
- **CREDITS** (&FC00) — credits string in MMIO space
- **NMIVEC** (&FFFA) — 6502 hardware vectors

In the code body, replaced `.LABEL` definitions with `SKIPTO LABEL` directives. The `ORG &FFFA` for 6502 vectors was also replaced with `SKIPTO NMIVEC`.

### Discovery: SKIPTO vs ORG
`SKIPTO` is the right choice here rather than `ORG` because `SKIPTO` advances the program counter forward (filling with zeros) and will error if you try to skip backwards — exactly the protection we want. `ORG` just sets the PC without checking.

### Result
Still assembles byte-identically. Any future code changes that would push past a fixed boundary will now produce a clear assembler error.

---

## 2026-03-27: Conditional Assembly and Size Optimizations

### Build restructure
Renamed `os120.asm` → `os120.6502`. Created two wrapper files:
- `original.6502` — sets `NEW_VERSION = FALSE`, produces byte-identical ROM
- `new.6502` — sets `NEW_VERSION = TRUE`, applies optimizations, reports free bytes

All optimizations are wrapped in `IF NEW_VERSION ... ELSE ... ENDIF` blocks.

### Fixed address: MUL640 = &C375
Added the multiply-by-640 table as a fixed address with `SKIPTO MUL640`, since some software relies on this table being at &C375.

### Optimizations applied

| Change | Bytes | Details |
|--------|-------|---------|
| Screen clear rewrite | ~252 | Replaced 80 unrolled `STA &xxxx,X` instructions, 5 entry points, lookup table, and indirect jump mechanism with a single inlined loop using `STA (zp),Y` indirect addressing. Loop starts from `vduStartScreenAddressHighByte` and increments page until high byte reaches &80 (BPL). Also merged duplicate `LDX #0` and `LDA vduStartScreenAddressHighByte` from the calling code. |
| isLetter alternative | 4 | Author-suggested `SEC/SBC #charA/CMP #26` trick instead of two CMP/BCC branches |
| Hex print decimal trick | 3 | Author-suggested `SED/CMP #10/ADC #'0'/CLD` instead of CMP/BCC/ADC chain |
| Remove initialiseScreenOnReset JMP | 3 | Sole caller now calls `initialiseVDUVariablesAndSetMODE` directly. Boot message offset uses `LO()` to handle page wrapping. |
| Sound delay → JSR RTS | 2 | `LDY #2/DEY/BNE` delay loop → `JSR exit24` (same ~12 cycle delay) |
| clearCatalogueStatusBadROM | 2 | `LDA/JSR clearTapeStatusBits` → `JSR clearCatalogueStatus` |
| Tape filename branch → RTS | 2 | `TXA/BNE exit32` (always branches) → `RTS` |
| Tape save ZP addressing | 2 | Two instructions changed from absolute,X to ZP,X using `LO()` |
| Unused PLA (MOS 0.92) | 1 | Dead code from earlier OS version |
| Unused EQUB (osbyte120) | 1 | Padding byte after routine |
| Unused EQUB (before MMIO) | 1 | Padding byte at &FBFF |
| Printer strobe BNE → RTS | 1 | `BNE exit17` (always branches to RTS) → `RTS` |
| **Total** | **271** | |

### Hurdles

#### Self-modifying code in ROM
First attempt at the screen clear loop used self-modifying code (`INC clearScreenSTA + 2` to change the STA high byte). This can't work in ROM. Replaced with `STA (vduTempStoreDE),Y` indirect addressing through a zero-page pointer — the pointer high byte is incremented instead.

#### Screen clear: eliminating the indirect jump mechanism
The original design used a table of entry point addresses, an indirect `JMP (vduJumpVectorLow)` to reach the mode-specific routine, and a second indirect JMP to loop back. First replacement kept this mechanism with 5 smaller entry points. Final version inlines the entire clear loop inside `initializeDisplayAndHomeCursor`, using `vduStartScreenAddressHighByte` (already loaded for the CRTC setup) as the loop start, and `BPL` to terminate at &80. This eliminated the entry point table, all 5 mode entry point labels, and the jump vector setup code.

#### Boot message offset after removing initialiseScreenOnReset
Removing the 3-byte JMP at `.vduBaseAddress` shifted `.bootMessage` 3 bytes earlier. The expression `bootMessage - vduBaseAddress - 1` became negative. Fixed by using `LO(bootMessage - vduBaseAddress - 1)` in the new version to wrap correctly.

### Correctness verification
All 16 conditional blocks reviewed. Key checks:
- `vduTempStoreDE`/`DF` are temporary stores — no caller depends on their values after `initializeDisplayAndHomeCursor` returns
- Screen memory always ends at &8000 for all modes, so `BPL` terminates correctly
- The hex print decimal mode trick produces correct results for 0-9 (carry clear → '0'-'9') and 10-15 (carry set → BCD fixup → 'A'-'F')
- The `isLetter` alternative preserves the same carry flag convention (clear = letter)
- The sound delay `JSR exit24` takes 12 cycles (6 JSR + 6 RTS), meeting the 8µs / 16 cycle minimum
- ZP,X wrapping for tape save: `LO(&B4 - &FD)` = &B7, and &B7 + &FD wraps to &B4 in zero page

### Result
`original.6502` produces byte-identical ROM (MD5 verified). `new.6502` reports **270 free bytes** before the MMIO region at &FC00.

### Bug fix: key table padding byte
The `EQUB 0` between `osbyte120EntryPoint` and `keyDataTable2` was initially removed as "unused". This broke keyboard handling — the QWERTYUIOP row was shifted by one key. The byte is padding that keeps the 7 key data tables spaced exactly 16 bytes apart (as required by the key lookup code). Restored unconditionally with corrected comment.

---

## 2026-03-27: Version String and Regression Test

### OS 1.2B version string
The new version now reports "OS 1.2B" (instead of "OS 1.20") in two places:
- The `*FX 0` error message (OSBYTE 0)
- The startup banner printed during boot

Both are conditional on `NEW_VERSION`.

### Automated regression test (test.sh)
Created `test.sh` using beebjit's `-os` flag (to specify the ROM without replacing files) and `-commands` interface to script a full test session:

**Test sequence:** boot → `*FX 0` → `MODE 0` → `COLOUR129:CLS` → `MODE 7` → `MODE 2` → `COLOUR129:CLS` → `MODE 7` → keyboard rows → `PRINT 2+2` → `VDU 65,66,67,68,69`

**Frame capture:** beebjit captures raw BGRA frames every 10K cycles (~200 per second). Both ROMs are run through the same sequence and all frames are compared.

**Results:** ~1100 frames captured per ROM. ~88 frames differ (version string + transient screen clear pattern), the rest are identical.

### Hurdles

#### beebjit keyboard mapping
beebjit's `keydown` command uses PC physical key codes, not BBC key codes. Most ASCII characters work directly, but symbols that are on different physical keys need translation:
- `*` = Shift (133) + PC apostrophe (39), which maps to BBC Shift+colon
- `:` = PC apostrophe (39) unshifted, which maps to BBC colon
- `+` = Shift (133) + PC semicolon (59), which maps to BBC Shift+semicolon
- `keydown 42` (ASCII `*`) is silently ignored — there's no BBC key at that position

#### beebjit frame capture requires non-fast mode
Frame capture (`-frame-cycles`) only works without the `-fast` flag. With `-fast`, no frames are written. The test runs at real-time 2MHz speed.

#### breakat uses absolute cycle counts
The `-commands` interface's `breakat` sets an absolute cycle count breakpoint, not a relative delay. The test uses a Python helper to track cumulative cycle counts and emit monotonically increasing breakpoints.
