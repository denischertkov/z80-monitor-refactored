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
; P - enter port
; S - value --
; W - value ++
; V - enter value
; R - read port
; O - output value to port
; Q - return to monitor
;
; Grant Searle monitor services:
; RST 08h - console output
; RST 10h - console input
; =========================================================


PORTTEST:
        ld a,33h                        ; initial port number
        ld (portno),a

        ld a,82h                        ; initial value
        ld (value),a

pt_main:
        call pt_draw

pt_waitkey:
        rst 10h
        and 5fh

        cp 'Q'
        ret z

        CP 'A'
        JP Z,pt_port_dec

        CP 'D'
        JP Z,pt_port_inc

        CP 'P'
        JP Z,pt_port_edit

        CP 'S'
        JP Z,pt_value_dec

        CP 'W'
        JP Z,pt_value_inc

        CP 'V'
        JP Z,pt_value_edit

        CP 'R'
        JP Z,pt_port_read

        CP 'O'
        JP Z,pt_port_write

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
; Edit PORT or VALUE with one or two hexadecimal digits
; ---------------------------------------------------------
pt_port_edit:
        ld de,portno
        jr pt_edit_byte

pt_value_edit:
        ld de,value

pt_edit_byte:
        ; Fields are on rows 3/4; column 9 follows each 8-character label.
        call pt_edit_position
        ld a,' '                        ; clean previous value
        rst 08h
        rst 08h
        ld a,'h'                        ; print 'h '
        RST 08h
        ld a,' '
        rst 08h       
        call pt_edit_position           ; return cursor to the field
        call READ_HEX16
        jp c,pt_main                    ; Esc/Ctrl-C cancels without changing data
        jp z,pt_main                    ; Empty Enter keeps the current value
        ld a,b                          ; B = number of entered digits
        cp 3                            ; if more than 3
        jr nc,pt_edit_retry             ; clear and enter again
        ld a,l
        ld (de),a
        jr pt_main

pt_edit_retry:
        ld hl,portno
        or a
        sbc hl,de
        jr z,pt_port_edit
        jr pt_value_edit

pt_edit_position:
        ld hl,portno
        or a
        sbc hl,de
        jr z,pt_edit_port_position
        ld hl,pt_value_cursor
        jr pt_edit_print_position
pt_edit_port_position:
        ld hl,pt_port_cursor
pt_edit_print_position:
        jp PRINT

; ---------------------------------------------------------
; Read selected port
; ---------------------------------------------------------
pt_port_read:
        ld a,(portno)
        ld c,a
        ld b,0

        in a,(c)
        ld (value),a

        jp pt_main


; ---------------------------------------------------------
; Write VALUE to selected port
; ---------------------------------------------------------
pt_port_write:
        ld a,(portno)
        ld c,a
        ld b,0

        ld a,(value)
        out (c),a

        jp pt_main


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

        ld a,(portno)                   ; print port number as two hex digits
        call PRINT_HEX8

        ld hl,pt_hex_bin
        call PRINT

        ld a,(portno)                   ; print port number as eight binary digits
        call PRINT_BIN8

        ld a,'b'
        RST 08H                         ; Print 'b' character

        ld hl,pt_valuetxt
        call PRINT

        ld a,(value)
        call PRINT_HEX8

        ld hl,pt_hex_bin
        call PRINT

        ld a,(value)                    ; print value as eight binary digits
        call PRINT_BIN8

        ld a,'b'
        RST 08H                         ; Print 'b' character

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
        db "P    enter port (hex)",13,10
        db "S/W  value -/+",13,10
        db "V    enter value (hex)",13,10
        db "R    read port",13,10
        db "O    output value",13,10
        db "Q    return to monitor",13,10
        db 0

pt_port_cursor:
        ; ANSI cursor positions for the PORT and VALUE hex fields.
        db ESC,"[3;9H",0

pt_value_cursor:
        db ESC,"[4;9H",0

pt_hex_bin:
        db "h ",0
        