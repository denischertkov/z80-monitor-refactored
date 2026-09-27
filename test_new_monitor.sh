#!/usr/bin/env bash
# Prepare a RAM test. Device writes require an explicit --upload.
# rom_loader.asm is the user's existing hardware-specific loader - it
# disable the ROM and copy the monitor to RAM and restart it from 0000h.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
upload=0
serial_port=/dev/ttyUSB0
while (( $# )); do
    case "$1" in
        --upload) upload=1; shift ;;
        --port)
            [[ $# -ge 2 ]] || { echo 'Missing --port value' >&2; exit 2; }
            serial_port=$2; shift 2 ;;
        *) echo 'Usage: bash test_new_monitor.sh [--upload] [--port /dev/ttyUSB0]' >&2; exit 2 ;;
    esac
done
command -v srec_cat >/dev/null || { echo 'Required: srec_cat' >&2; exit 1; }
if (( upload )); then
    [[ -f rom_loader.asm ]] || { echo 'Add your existing rom_loader.asm before upload.' >&2; exit 1; }
    command -v ascii-xfr >/dev/null || { echo 'Required: ascii-xfr' >&2; exit 1; }
    [[ -c "$serial_port" && -w "$serial_port" ]] || { echo 'Serial port must be a writable character device.' >&2; exit 1; }
fi
bash build.sh
srec_cat build/monitor-sjasmplus.bin -Binary -offset 0x5000 \
    -o build/monitor-test.hex -Intel -line-length 80
if (( ! upload )); then
    echo 'Prepared build/monitor-test.hex. No device was accessed.'
    exit 0
fi
sjasmplus --raw=build/rom_loader.bin --lst=build/rom_loader.lst \
    --sym=build/rom_loader.sym --cleanonerror rom_loader.asm
loader_size=$(wc -c < build/rom_loader.bin)
if (( loader_size == 0 || loader_size > 0x5000 - 0x4100 )); then
    echo 'Loader is empty or overlaps the staged monitor at 5000h.' >&2
    exit 1
fi
srec_cat build/rom_loader.bin -Binary -offset 0x4100 \
    -o build/rom_loader.hex -Intel -line-length 80
# An initial copy of the original ROM, including BASIC, is still required.
# The short monitor-test.hex does not fill the remainder of the staging area.
# -s means send; transfer text Intel HEX records with a 50 ms line delay.
ascii-xfr -s -l 0 build/monitor-test.hex > "$serial_port"
ascii-xfr -s -l 0 build/rom_loader.hex > "$serial_port"
printf 'g4100\r' > "$serial_port"
echo 'Transfer sent. Verify the monitor on the terminal; no acknowledgement was checked.'
