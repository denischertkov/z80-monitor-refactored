; =========================================================
; Z80 MEMORY VIEWER
; z80asm syntax
;
; Load address: 8000h
;
; Commands:
;   N or SPACE - next 256 bytes
;   P          - previous 256 bytes
;   G          - goto address
;   Q          - return to Monitor
;
; Denis Chertkov, denis@chertkov.info, 20260912
; =========================================================

; ---------------------------------------------------------
; Entry point called from Monitor
; ---------------------------------------------------------
 
MEMDUMP:
        CALL GETHL
        ; RET C				; exit if empty address (C-flag set by GETHL)
        JR NC, setaddr                  ; if defined - use it, otherwise start from 0000h
        LD H,00h                        ; If not defined - start from 0000h
setaddr:
        LD L,00h                        ; round the address down to the start of a 256-byte page
        LD (baseaddr),HL

main_view:
        call draw_page


waitkey:
        rst 10h

        cp 1bh              ; ESC?
        jp z,escape_key

        cp ' '
        jr z,next_page

        and 5fh             ; lowercase -> uppercase

        cp 'N'
        jr z,next_page

        cp 'P'
        jr z,prev_page

        cp 'G'
        jr z,goto_addr

        cp 'Q'
        ret z

        jr waitkey


; ---------------------------------------------------------
; Next 256-byte page
; ---------------------------------------------------------

next_page:
        ld hl,(baseaddr)
        ld de,0100h
        add hl,de
        ld (baseaddr),hl
        jr main_view


; ---------------------------------------------------------
; Previous 256-byte page
; ---------------------------------------------------------

prev_page:
        ld hl,(baseaddr)
        ld de,0100h
        or a
        sbc hl,de
        ld (baseaddr),hl
        jr main_view


; ---------------------------------------------------------
; Ask for new address
; Four HEX digits, no ENTER needed.
; ---------------------------------------------------------

goto_addr:
        ld hl,goto_msg
        call PRINT

        ld hl,0000h
        ld b,4


goto_digit:

goto_wait:
        rst 10h

        ; Сначала проверяем цифры 0..9
        cp '0'
        jr c,goto_try_letter

        cp '9'+1
        jr c,goto_number


goto_try_letter:
        ; Теперь можно безопасно привести буквы к uppercase
        and 5fh

        cp 'A'
        jr c,goto_wait

        cp 'F'+1
        jr nc,goto_wait

        ; A-F -> 10..15

        push af
        rst 08h             ; echo
        pop af

        sub 'A'-10
        jr goto_have_digit


goto_number:
        push af
        rst 08h             ; echo
        pop af

        sub '0'


goto_have_digit:
        ld c,a

        ; HL = HL * 16
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl

        ; добавить nibble
        ld a,l
        or c
        ld l,a

        djnz goto_digit

        ; округлить адрес до начала 256-байтной страницы
        ld l,00h

        ; сохранить новый адрес
        ld (baseaddr),hl

        ; перерисовать страницу
        jp main_view

; ---------------------------------------------------------
; Draw complete 256-byte page
; ---------------------------------------------------------

draw_page:

        ; Clear screen + cursor home

        ld hl,cls
        call PRINT

        ld hl,title
        call PRINT

        ; Display base address in heading

        ld hl,(baseaddr)
        call PRINT_HEX16

        ld hl,title2
        call PRINT

        ; HL = first memory byte

        ld hl,(baseaddr)

        ; 16 lines

        ld b,16


line_loop:
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


hex_loop:
        ld a,(hl)
        call PRINT_HEX8

        ld a,' '
        rst 08h

        inc hl

        dec c
        jr nz,hex_loop


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


ascii_loop:
        ld a,(hl)

        ; printable ASCII = 20h..7Eh

        cp 20h
        jr c,not_printable

        cp 7fh
        jr nc,not_printable

        jr ascii_out


not_printable:
        ld a,'.'


ascii_out:
        rst 08h

        inc hl

        dec c
        jr nz,ascii_loop


        ; CR/LF

        ld a,13
        rst 08h

        ld a,10
        rst 08h

        pop bc

        djnz line_loop


        ; command help

        ld hl,help
        call PRINT

        ret

; USED PROCEDURES FROM MONITOR
; ; ---------------------------------------------------------
; ; Print HL as four HEX digits
; ;
; ; HL is preserved.
; ; ---------------------------------------------------------

; hex16:
;         push hl

;         ld a,h
;         call hex8

;         ld a,l
;         call hex8

;         pop hl
;         ret


; ; ---------------------------------------------------------
; ; Print A as two HEX digits
; ; ---------------------------------------------------------

; hex8:
;         push af

;         rrca
;         rrca
;         rrca
;         rrca

;         and 0fh
;         call hex_digit

;         pop af

;         and 0fh


; hex_digit:
;         add a,'0'

;         cp '9'+1
;         jr c,hex_out

;         add a,7


; hex_out:
;         rst 08h
;         ret


; ---------------------------------------------------------
; Print zero-terminated string
; HL -> string
; ---------------------------------------------------------
; Will use Monitor print routine
; print:
;         ld a,(hl)
;         or a
;         ret z

;         rst 08h

;         inc hl
;         jr print


; ---------------------------------------------------------
; ANSI escape sequences
;
; PgUp:   ESC [ 5 ~
; PgDown: ESC [ 6 ~
; ---------------------------------------------------------

escape_key:
        rst 10h             ; ожидаем '['
        cp '['
        jp nz,waitkey

        rst 10h

        ; стрелки
        cp 'A'              ; Up
        jp z,prev_page

        cp 'B'              ; Down
        jp z,next_page

        ; Page Up / Page Down

        cp '5'
        jr z,escape_pgup

        cp '6'
        jr z,escape_pgdown

        jp waitkey


escape_pgup:
        rst 10h             ; ожидаем '~'
        cp '~'
        jp nz,waitkey

        jp prev_page


escape_pgdown:
        rst 10h             ; ожидаем '~'
        cp '~'
        jp nz,waitkey

        jp next_page




; ---------------------------------------------------------
; Variables
; ---------------------------------------------------------

; baseaddr:
;         dw 0000h


; ---------------------------------------------------------
; Strings
; ---------------------------------------------------------

cls:
        db 1bh,"[2J"
        db 1bh,"[H"
        db 0


title:
        db "Z80 MEMORY VIEWER by Denis@Chertkov.info",13,10
        db "PAGE: ",0


title2:
        db "h",13,10,13,10,0


help:
        db 13,10
        db "N/SPACE,PgDn next page",13,10
        db "P,PgUp       previous page",13,10
        db "G            goto address",13,10
        db "Q            quit",13,10
        db 0


goto_msg:
        db 13,10
        db "Address:     ",0
