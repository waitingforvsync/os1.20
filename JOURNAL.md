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
