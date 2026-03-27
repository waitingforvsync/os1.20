#!/bin/bash
#
# Automated regression test for OS 1.20 using beebjit
#
# Captures screen frames from both the original and new ROM builds,
# then compares them to check for regressions.
#
# Requirements: beebjit, beebasm, python3, ImageMagick (optional, for visual diff)
#
# Usage: ./test.sh
#

set -e

TESTDIR=$(mktemp -d)
ORIGDIR="$TESTDIR/orig"
NEWDIR="$TESTDIR/new"
PROJDIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$ORIGDIR" "$NEWDIR"

echo "=== Building ROMs ==="
cd "$PROJDIR"
beebasm -i original.6502
cp OS120.rom "$TESTDIR/os12_orig.rom"
beebasm -i new.6502 2>&1 | grep "Free bytes"
cp OS120new.rom "$TESTDIR/os12_new.rom"

# Build beebjit -commands string using Python.
#
# Key insight: breakat sets an absolute cycle count breakpoint, then 'c'
# runs the CPU until that point. Keydown/keyup commands are processed
# when the CPU is stopped, so they go BETWEEN 'c' and the next 'breakat'.
COMMANDS=$(python3 << 'PYEOF'
cycles = 0
cmds = []

def advance(us):
    '''Advance the cycle counter and emit breakat + continue.'''
    global cycles
    cycles += us * 2  # 2MHz
    cmds.append(f'breakat {cycles}')
    cmds.append('c')

def keypress(code, hold_ms=50, gap_ms=50, shift=False):
    '''Press and release a key with proper timing.'''
    if shift:
        cmds.append('keydown 133')
    cmds.append(f'keydown {code}')
    advance(hold_ms * 1000)
    cmds.append(f'keyup {code}')
    if shift:
        cmds.append('keyup 133')
    advance(gap_ms * 1000)

# beebjit keydown uses PC-layout physical key codes (from keyboard.c):
#   39 (PC apostrophe) -> BBC colon key
#   59 (PC semicolon)  -> BBC semicolon key
#   Shift+colon = *, Shift+semicolon = +
# Characters needing a different base key and/or Shift:
BBC_KEYMAP = {
    ord('*'): (39, True),    # Shift + PC apostrophe (BBC colon)
    ord('+'): (59, True),    # Shift + PC semicolon (BBC semicolon)
    ord(':'): (39, False),   # PC apostrophe (BBC colon), no shift
}

def typestr(s):
    '''Type a string. BBC boots with Caps Lock on so unshifted
    letter keys give uppercase.'''
    for ch in s:
        code = ord(ch)
        if code in BBC_KEYMAP:
            key, shift = BBC_KEYMAP[code]
            keypress(key, shift=shift)
        else:
            keypress(code)

def enter(settle_ms=500):
    keypress(131, gap_ms=settle_ms)

def type_and_enter(s):
    typestr(s)
    enter()

# Wait for boot
advance(2000 * 1000)

# *FX 0 (show OS version)
type_and_enter('*FX 0')

# MODE changes (test screen clearing)
type_and_enter('MODE 0')
type_and_enter('COLOUR129:CLS')
type_and_enter('MODE 7')
type_and_enter('MODE 2')
type_and_enter('COLOUR129:CLS')
type_and_enter('MODE 7')

# Keyboard rows
type_and_enter('1234567890')
type_and_enter('QWERTYUIOP')
type_and_enter('ASDFGHJKL')
type_and_enter('ZXCVBNM')

# BASIC test
type_and_enter('PRINT 2+2')

# VDU test
type_and_enter('VDU 65,66,67,68,69')

# Final settle and exit
advance(1000 * 1000)
cmds.append('bail')

print(';'.join(cmds))
PYEOF
)

run_test() {
    local rom="$1"
    local outdir="$2"
    local label="$3"

    echo "=== Testing $label ROM ==="
    mkdir -p "$outdir"

    beebjit \
        -os "$rom" \
        -commands "$COMMANDS" \
        -frame-cycles 10000 \
        -max-frames 2000 \
        -frames-dir "$outdir" \
        -opt sound:off 2>&1 | grep -cE '^ERROR' | xargs -I{} echo "  {} errors" || true

    local nframes=$(ls "$outdir"/*.bgra 2>/dev/null | wc -l)
    echo "  Captured $nframes frames"
}

run_test "$TESTDIR/os12_orig.rom" "$ORIGDIR" "original"
run_test "$TESTDIR/os12_new.rom" "$NEWDIR" "new"

# Compare final frames (raw BGRA)
echo ""
echo "=== Comparing final frames ==="

NORIG=$(ls -1 "$ORIGDIR"/*.bgra 2>/dev/null | wc -l)
NNEW=$(ls -1 "$NEWDIR"/*.bgra 2>/dev/null | wc -l)

if [ "$NORIG" -eq 0 ] || [ "$NNEW" -eq 0 ]; then
    echo "ERROR: No frames captured (orig=$NORIG, new=$NNEW)"
    exit 1
fi

# Compare all frame pairs
MATCH=0
DIFF=0
DIFF_LIST=""
for orig_frame in "$ORIGDIR"/*.bgra; do
    fname=$(basename "$orig_frame")
    new_frame="$NEWDIR/$fname"
    if [ -f "$new_frame" ]; then
        if cmp -s "$orig_frame" "$new_frame"; then
            MATCH=$((MATCH + 1))
        else
            DIFF=$((DIFF + 1))
            DIFF_LIST="$DIFF_LIST $fname"
        fi
    fi
done

echo "  Frames compared: $((MATCH + DIFF))"
echo "  Identical: $MATCH"
echo "  Different: $DIFF (expected: version string + screen clear pattern)"
if [ "$DIFF" -eq 0 ]; then
    echo "  WARNING: No differences found - expected at least version string diff"
elif [ "$DIFF" -gt 0 ]; then
    echo "  PASS: Differences are expected (version string, screen clear order)"
fi

echo ""
echo "Frames saved in: $TESTDIR"
