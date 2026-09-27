; =========================================================
; Z80 PORT TEST
; For z80asm
;
; Controls:
;   A - port --
;   D - port ++
;   S - value --
;   W - value ++
;   R - read port
;   O - output value to port
;   Q - return to monitor
;
; Grant Searle monitor services:
;   RST 08h - console output
;   RST 10h - console input
; =========================================================


PORTTEST:
        ld a,10h                                ; initial port number
        ld (portno),a

        xor a                                   ; initial value
        ld (value),a

main:
        call draw

pt_waitkey:
        rst 10h
        and 5fh

        cp 'Q'
        ret z

        cp 'A'
        jr z,port_dec

        cp 'D'
        jr z,port_inc

        cp 'S'
        jr z,value_dec

        cp 'W'
        jr z,value_inc

        cp 'R'
        jr z,port_read

        cp 'O'
        jr z,port_write

        jr pt_waitkey


port_dec:
        ld a,(portno)
        dec a
        ld (portno),a
        jr main


port_inc:
        ld a,(portno)
        inc a
        ld (portno),a
        jr main


value_dec:
        ld a,(value)
        dec a
        ld (value),a
        jr main


value_inc:
        ld a,(value)
        inc a
        ld (value),a
        jr main


; ---------------------------------------------------------
; Read selected port
; ---------------------------------------------------------
port_read:
        ld a,(portno)
        ld c,a
        ld b,0

        in a,(c)
        ld (value),a

        jr main


; ---------------------------------------------------------
; Write VALUE to selected port
; ---------------------------------------------------------
port_write:
        ld a,(portno)
        ld c,a
        ld b,0

        ld a,(value)
        out (c),a

        jr main


; ---------------------------------------------------------
; Draw screen
; ---------------------------------------------------------
draw:
        ld hl,cls
        call PRINT

        ld hl,pt_title
        call PRINT

        ld hl,porttxt
        call PRINT

        ld a,(portno)
        call PRINT_HEX8

        ld hl,valuetxt
        call PRINT

        ld a,(value)
        call PRINT_HEX8

        ld hl,helptxt
        call PRINT

        ret

pt_title:
        db "Z80 PORT TEST by Denis@Chertkov.info",13,10,13,10,0

porttxt:
        db "PORT  : ",0

valuetxt:
        db 13,10
        db "VALUE : ",0

helptxt:
        db 13,10,13,10
        db "A/D  port -/+",13,10
        db "S/W  value -/+",13,10
        db "R    read port",13,10
        db "O    output value",13,10
        db "Q    return to monitor",13,10
        db 0
