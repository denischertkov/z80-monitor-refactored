; PORTTEST: JP from MAIN, RET back; clobbers AF/BC/HL and portno/value.
; R/O perform exactly one IN/OUT. Drawing does not read ports.
; BC=$00pp: B is deliberately cleared; it holds the upper 8 I/O address bits.
; IRQs remain enabled. Accessing SIO, CF, or bank-switching registers may
; disrupt the console or switch memory; no writes are performed automatically.
; =========================================================
; Z80 PORT TEST
; Built-in sjasmplus module; no separate ORG.
;
; Controls:
; A - port --
; D - port ++
; S - value --
; W - value ++
; R - read port
; O - output value to port
; Q - return to monitor
;
; Grant Searle monitor services:
; RST 08h - console output
; RST 10h - console input
; =========================================================


PORTTEST:
        ld a,10h                        ; initial port number
        ld (portno),a

        xor a                           ; initial value
        ld (value),a

pt_main:
        call pt_draw

pt_waitkey:
        rst 10h
        and 5fh

        cp 'Q'
        ret z

        cp 'A'
        jr z,pt_port_dec

        cp 'D'
        jr z,pt_port_inc

        cp 'S'
        jr z,pt_value_dec

        cp 'W'
        jr z,pt_value_inc

        cp 'R'
        jr z,pt_port_read

        cp 'O'
        jr z,pt_port_write

        jr pt_waitkey


pt_port_dec:
        ld hl,portno
        jr pt_decrement
pt_port_inc:
        ld hl,portno
        jr pt_increment
pt_value_dec:
        ld hl,value
pt_decrement:
        dec (hl)                        ; 8-bit decrement; wraps 00 -> FF
        jr pt_main
pt_value_inc:
        ld hl,value
pt_increment:
        inc (hl)                        ; 8-bit increment; wraps FF -> 00
        jr pt_main

; ---------------------------------------------------------
; Read selected port
; ---------------------------------------------------------
pt_port_read:
        ld a,(portno)
        ld c,a
        ld b,0

        in a,(c)
        ld (value),a

        jr pt_main


; ---------------------------------------------------------
; Write VALUE to selected port
; ---------------------------------------------------------
pt_port_write:
        ld a,(portno)
        ld c,a
        ld b,0

        ld a,(value)
        out (c),a

        jr pt_main


; ---------------------------------------------------------
; Draw screen
; ---------------------------------------------------------
pt_draw:
        ld hl,UI_CLEAR_SCREEN
        call PRINT

        ld hl,pt_title
        call PRINT

        ld hl,pt_porttxt
        call PRINT

        ld a,(portno)
        call PRINT_HEX8

        ld hl,pt_valuetxt
        call PRINT

        ld a,(value)
        call PRINT_HEX8

        ld hl,pt_helptxt
        jp PRINT                        ; tail call

pt_title:
        db "Z80 PORT TEST by Denis@Chertkov.info",13,10,13,10,0

pt_porttxt:
        db "PORT  : ",0

pt_valuetxt:
        db 13,10
        db "VALUE : ",0

pt_helptxt:
        db 13,10,13,10
        db "A/D  port -/+",13,10
        db "S/W  value -/+",13,10
        db "R    read port",13,10
        db "O    output value",13,10
        db "Q    return to monitor",13,10
        db 0
