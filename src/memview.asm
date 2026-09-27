; MEMDUMP: entered via JP from MAIN; RET returns to the monitor.
; Clobbers AF/BC/DE/HL and baseaddr; no additional RAM buffers.
; Pages are aligned to $100; memory is read twice for HEX and ASCII,
; so bytes updated by interrupts may differ between the two columns.
; G: 1..4 HEX digits + Enter; Backspace edits, Esc/Ctrl-C cancels.
; ESC parsing remains blocking: a lone ESC waits for more input.
; =========================================================
; Z80 MEMORY VIEWER
; Built-in sjasmplus module; no separate ORG.
;
; Commands:
; N or SPACE - next 256 bytes
; P          - previous 256 bytes
; G          - goto address
; Q          - return to Monitor
;
; Denis Chertkov, denis@chertkov.info, 20260912
; =========================================================

; ---------------------------------------------------------
; Entry point called from Monitor
; ---------------------------------------------------------

MEMDUMP:
        CALL READ_HEX16
        RET C                           ; Cancel returns to the monitor
        ; Empty Enter returns HL=0: M without an address opens $0000.
mv_setaddr:
        LD L,00h                        ; round the address down to the start of a 256-byte page
        LD (baseaddr),HL

mv_main_view:
        call mv_draw_page


mv_waitkey:
        rst 10h

        cp 1bh                          ; ESC?
        jp z,mv_escape_key

        cp ' '
        jr z,mv_next_page

        and 5fh                         ; lowercase -> uppercase

        cp 'N'
        jr z,mv_next_page

        cp 'P'
        jr z,mv_prev_page

        cp 'G'
        jr z,mv_goto_addr

        cp 'Q'
        ret z

        jr mv_waitkey


; ---------------------------------------------------------
; Next 256-byte page
; ---------------------------------------------------------

mv_next_page:
        ; baseaddr is a RAM word with a zero low byte. DE is now preserved.
        ; Flag changes are not observed: the following draw_page sets them again.
        ld hl,(baseaddr)
        inc h                           ; +$100, L=0; wraps FF00 -> 0000
        ld (baseaddr),hl
        jr mv_main_view


; ---------------------------------------------------------
; Previous 256-byte page
; ---------------------------------------------------------

mv_prev_page:
        ld hl,(baseaddr)
        dec h                           ; -$100, L=0; wraps 0000 -> FF00
        ld (baseaddr),hl
        jr mv_main_view


; ---------------------------------------------------------
; Ask for new address
; Shared address editor: Enter confirms, Esc/Ctrl-C cancels.
; ---------------------------------------------------------

mv_goto_addr:
        ld hl,mv_goto_msg
        call PRINT
        call READ_HEX16
        jr c,mv_main_view               ; Cancel: redraw the current page
        jr z,mv_main_view               ; Empty Enter: keep baseaddr unchanged
        jp mv_setaddr                   ; Shared address alignment and storage

; ---------------------------------------------------------
; Draw complete 256-byte page
; ---------------------------------------------------------

mv_draw_page:
        ; Input: baseaddr. Output: page and help text displayed.
        ; Clobbers AF/BC/DE/HL. The stack is balanced on all paths.
        ; B counts rows, C counts bytes; PUSH BC protects the row counter.

        ; Clear screen + cursor home

        ld hl,UI_CLEAR_SCREEN
        call PRINT

        ld hl,mv_title
        call PRINT

        ; Display base address in heading

        ld hl,(baseaddr)
        call PRINT_HEX16

        ld hl,mv_title2
        call PRINT

        ; HL = first memory byte

        ld hl,(baseaddr)

        ; 16 lines

        ld b,16


mv_line_loop:
        push bc

        ; Address

        call PRINT_HEX16

        ld a,':'
        rst 08h

        ld a,' '
        rst 08h

        ; ---------------------------------------------
        ; HEX part - 16 bytes
        ; ---------------------------------------------

        ld c,16


mv_hex_loop:
        ld a,(hl)
        call PRINT_HEX8

        ld a,' '
        rst 08h

        inc hl

        dec c
        jr nz,mv_hex_loop


        ; two spaces before ASCII

        ld a,' '
        rst 08h

        ld a,' '
        rst 08h


        ; HL currently points to NEXT line.
        ; Move back 16 bytes.

        ld de,-16
        add hl,de


        ; ---------------------------------------------
        ; ASCII part
        ; ---------------------------------------------

        ld c,16


mv_ascii_loop:
        ld a,(hl)

        ; printable ASCII = 20h..7Eh

        cp 20h
        jr c,mv_not_printable

        cp 7fh
        jr nc,mv_not_printable

        jr mv_ascii_out


mv_not_printable:
        ld a,'.'


mv_ascii_out:
        rst 08h

        inc hl

        dec c
        jr nz,mv_ascii_loop


        ; CR/LF

        call TXCRLF                     ; Preserves BC/DE/HL

        pop bc

        djnz mv_line_loop


        ; command mv_help

        ld hl,mv_help
        jp PRINT                        ; Tail call; return to mv_main_view

; ---------------------------------------------------------
; ANSI escape sequences
;
; PgUp:   ESC [ 5 ~
; PgDown: ESC [ 6 ~
; ---------------------------------------------------------

mv_escape_key:
        ; Keep the original protocol: ESC [ A/B and ESC [ 5~/6~.
        ; There is no timeout. An incomplete sequence waits for more input;
        ; an unknown byte is consumed before returning to command input.
        rst 10h                         ; Wait for '['
        cp '['
        jp nz,mv_waitkey

        rst 10h

        ; Arrow keys
        cp 'A'                          ; Up
        jp z,mv_prev_page

        cp 'B'                          ; Down
        jp z,mv_next_page

        ; Page Up / Page Down

        cp '5'
        jr z,mv_escape_pgup

        cp '6'
        jr z,mv_escape_pgdown

        jp mv_waitkey


mv_escape_pgup:
        rst 10h                         ; Wait for '~'
        cp '~'
        jp nz,mv_waitkey

        jp mv_prev_page


mv_escape_pgdown:
        rst 10h                         ; Wait for '~'
        cp '~'
        jp nz,mv_waitkey

        jp mv_next_page




; UI strings; screen clearing is defined in terminal.asm.

mv_title:
        db "Z80 MEMORY VIEWER by Denis@Chertkov.info",13,10
        db "PAGE: ",0


mv_title2:
        db "h",13,10,13,10,0


mv_help:
        db 13,10
        db "N/SPACE,PgDn next page",13,10
        db "P,PgUp       previous page",13,10
        db "G            goto address",13,10
        db "Q            quit",13,10
        db 0


mv_goto_msg:
        db 13,10
        db "Address:     ",0
