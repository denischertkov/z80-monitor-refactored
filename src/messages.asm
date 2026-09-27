SIGNON          DB "Z80 SBC Boot ROM 1.2"
        DB " by G. Searle / D. Chertkov"
        DB $0D,$0A
        INCLUDE "../build_info.inc"     ; add the build info string
        DB "Type ? for options"
        DB $0D,$0A,$00

BASTXT
        DB $0D,$0A
        DB "Cold or Warm ?"
        DB $0D,$0A,$00

CKSUMERR        DB "Checksum error"
        DB $0D,$0A,$00

INITTXT
        DB $0C
        DB "Press [SPACE] to activate console"
        DB $0D,$0A, $00

LDETXT
        DB "Load complete."
        DB $0D,$0A, $00


HLPTXT
        DB $0D,$0A
        DB "R           - Reset"
        DB $0D,$0A
        DB "BC or BW    - ROM BASIC Cold or Warm"
        DB $0D,$0A
        DB "X           - Boot CP/M (load $D000-$FFFF from disk)"
        DB $0D,$0A
        DB ":nnnnnn...  - Load Intel-Hex file record"
        DB $0D,$0A
        DB "Mxxxx       - Memory dump"
        DB $0D,$0A
        DB "P           - Port test", 13, 10
        DB "Gxxxx       - Goto address", 13, 10
        DB $00
