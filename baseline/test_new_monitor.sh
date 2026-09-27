#!/bin/bash
# 
# This script is used to load the new BIOS/Monitor ROM into the Z80 system.
# It uses the `ascii-xfr` utility to transfer the compiled ROM image to the device connected via `/dev/ttyUSB0`. 
# The `-s` option specifies that the transfer should be done in binary mode, 
# and the `-l 50` option sets the line delay in ms for the transfer.
# 
# Denis Chertkov, denis@chertkov.info, 20260912

set -e

PORT=/dev/ttyUSB0

MON_SRC=monitor-sjasmplus.asm
MON_BIN=build/monitor-sjasmplus.bin
MON_LST=build/monitor-sjasmplus.lst
MON_SYM=build/monitor-sjasmplus.sym
MON_TEST_HEX=build/monitor-test.hex

LOADER_SRC=rom_loader.asm
LOADER_BIN=build/rom_loader.bin
LOADER_LST=build/rom_loader.lst
LOADER_SYM=build/rom_loader.sym
LOADER_HEX=build/rom_loader.hex

mkdir -p build

echo "Build info updating..."

BUILD_DATE=$(date '+%Y-%m-%d')
BUILD_TIME=$(date '+%H:%M:%S')

cat > build_info.inc <<EOF
BUILD_INFO:
        ; DB "Build: $BUILD_DATE $BUILD_TIME",13,10,0
        DB "Build: $BUILD_DATE",13,10,0
EOF

echo "Assembling Monitor..."

sjasmplus \
    --raw="$MON_BIN" \
    --lst="$MON_LST" \
    --sym="$MON_SYM" \
    --cleanonerror \
    "$MON_SRC"

echo "Creating test Monitor HEX at 5000h..."

srec_cat "$MON_BIN" -Binary \
    -offset 0x5000 \
    -o "$MON_TEST_HEX" -Intel \
    -line-length 80

echo "Assembling ROM loader..."

sjasmplus \
    --raw="$LOADER_BIN" \
    --lst="$LOADER_LST" \
    --sym="$LOADER_SYM" \
    --cleanonerror \
    "$LOADER_SRC"

echo "Creating ROM loader HEX at 4100h..."

srec_cat "$LOADER_BIN" -Binary \
    -offset 0x4100 \
    -o "$LOADER_HEX" -Intel \
    -line-length 80

echo "Uploading Monitor image..."

ascii-xfr -s -l 50 "$MON_TEST_HEX" > "$PORT"

echo "Uploading ROM loader..."

ascii-xfr -s -l 50 "$LOADER_HEX" > "$PORT"

echo "Starting RAM Monitor..."

printf 'g4100\r' > "$PORT"

echo "Done."
