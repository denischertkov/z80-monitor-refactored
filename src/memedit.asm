; MEMEDIT: 256-byte memory editor with an address cursor.
; Enter edits the selected byte; READ_HEX16 buffers input and commits only
; after Enter. Esc/Ctrl-C cancel without changing memory.
; Arrows move by byte/row. N/SPACE/PgDn and P/PgUp change pages.
; Only edit addresses that are known to be writable and safe.
; =========================================================
; Z80 MEMORY EDITOR
; Built-in sjasmplus module; no separate ORG.
; =========================================================

MEMEDIT:
        CALL READ_HEX16
        RET C                           ; Cancel returns to the monitor
        LD (me_cursor),HL
        LD L,0
        LD (baseaddr),HL                ; Align page to the selected address

me_main:
        CALL me_draw_page

me_waitkey:
        RST 10h
        CP 1Bh
        JP Z,me_escape_key
        CP 0Dh
        JP Z,me_edit_byte
        AND $5F                         ; lowercase -> uppercase
        CP 'Q'
        JP Z,me_exit
        CP 'N'
        JR Z,me_next_page
        CP ' '
        JR Z,me_next_page
        CP 'P'
        JR Z,me_prev_page
        CP 'G'
        JR Z,me_goto_addr
        CP 'F'
        JP Z,me_fill_byte
        JR me_waitkey

me_next_page:
        LD HL,(me_cursor)
        INC H                           ; Preserve cursor position within page
        LD (me_cursor),HL
        JR me_update_page

me_prev_page:
        LD HL,(me_cursor)
        DEC H
        LD (me_cursor),HL
        JR me_update_page

me_move_up:
        ; Each displayed row contains 16 bytes, so vertical movement is +/-$10.
        LD HL,(me_cursor)
        LD DE,-16
        ADD HL,DE
        JR me_move_cursor
me_move_down:
        LD HL,(me_cursor)
        LD DE,16
        ADD HL,DE
        JR me_move_cursor
me_move_left:
        LD HL,(me_cursor)
        DEC HL
        JR me_move_cursor
me_move_right:
        LD HL,(me_cursor)
        INC HL
me_move_cursor:
        ; Save the new absolute address before checking whether it needs a new page.
        LD (me_cursor),HL
me_update_page:
        ; Compare the cursor's page (high byte, low byte forced to zero) with
        ; baseaddr. SBC needs Carry cleared first; OR A does that without changing HL.
        LD L,0
        LD DE,(baseaddr)
        OR A
        SBC HL,DE
        JR Z,me_cursor_only             ; Same page: move terminal cursor only
        ; Cursor crossed a $100-byte page boundary: align baseaddr to its new page
        ; and redraw because the bytes currently shown no longer match that page.
        LD HL,(me_cursor)
        LD L,0
        LD (baseaddr),HL                ; Scroll when cursor crosses a page edge
        JP me_main

me_cursor_only:
        CALL me_position_cursor
        JP me_waitkey

me_goto_addr:
        LD HL,me_goto_msg
        CALL PRINT
        CALL READ_HEX16
        JP C,me_main                    ; Cancel keeps the current cursor
        JP Z,me_main                    ; Empty Enter keeps the current cursor
        LD (me_cursor),HL
        LD L,0
        LD (baseaddr),HL
        JP me_main

; Read arrows: Up/Down move one 16-byte row; Left/Right move one byte.
me_escape_key:
        RST 10h                         ; '['
        CP '['
        JP NZ,me_waitkey
        RST 10h
        CP 'A'
        JP Z,me_move_up
        CP 'B'
        JP Z,me_move_down
        CP 'C'
        JP Z,me_move_right
        CP 'D'
        JP Z,me_move_left
        CP '5'
        JR Z,me_escape_pgup
        CP '6'
        JR Z,me_escape_pgdown
        JP me_waitkey

me_escape_pgup:
        RST 10h                         ; '~'
        CP '~'
        JP NZ,me_waitkey
        JP me_prev_page
me_escape_pgdown:
        RST 10h                         ; '~'
        CP '~'
        JP NZ,me_waitkey
        JP me_next_page

; Edit into a temporary value; only store the byte after Enter confirms.
me_edit_byte:
        ; DE is preserved by the cursor-position routine. Clear only the two
        ; characters on screen; the actual memory byte is not changed yet.
        LD DE,(me_cursor)
        CALL me_position_cursor
        LD A,' '
        RST 08h
        RST 08h                         ; Clear old byte without changing memory
        CALL me_position_cursor
        CALL READ_HEX16
        JP C,me_main                    ; Cancel: redraw the original byte
        JP Z,me_main                    ; Empty Enter: leave memory unchanged
        LD A,B
        CP 3
        JR NC,me_edit_byte              ; Byte accepts at most two hex digits
        CP 1                            ; If only one digit, 
        JR NZ,me_byte_echoed            ; Two typed digits are already displayed correctly.
        ; READ_HEX16 echoes input and emits CR/LF on Enter. For one digit,
        ; restore the byte cursor and overwrite it with the zero-padded value.
        PUSH HL
        CALL me_position_cursor
        POP HL
        LD A,L                          ; print a leading zero to match the two-digit format
        CALL PRINT_HEX8
me_byte_echoed:
        ; READ_HEX16 returns the parsed value in HL. Use the low byte (L), then
        ; reload the selected address because the input routine uses HL.
        LD A,L
        LD C,A
        LD HL,(me_cursor)
        LD (HL),C                       ; Commit only after valid Enter
        CALL me_refresh_ascii           ; Update only this byte's character cell
        ; JP me_main                    ; don't redraw the whole page; just print the new byte and reposition the cursor
        JP me_cursor_only

; Draw the 16x16 page in the same layout as MEMDUMP.
me_draw_page:
        LD HL,UI_CLEAR_SCREEN
        CALL PRINT
        LD HL,me_title
        CALL PRINT
        LD HL,(baseaddr)
        CALL PRINT_HEX16
        LD HL,me_title2
        CALL PRINT
        LD HL,(baseaddr)
        LD B,16

me_line_loop:
        PUSH BC
        CALL PRINT_HEX16
        LD A,':'
        RST 08h
        LD A,' '
        RST 08h
        LD C,16
me_hex_loop:
        LD A,(HL)
        CALL PRINT_HEX8
        LD A,' '
        RST 08h
        INC HL
        DEC C
        JR NZ,me_hex_loop
        LD A,' '
        RST 08h
        RST 08h
        LD DE,-16
        ADD HL,DE
        LD C,16
me_ascii_loop:
        LD A,(HL)
        CP $20
        JR C,me_not_printable
        CP $7F
        JR NC,me_not_printable
        JR me_ascii_out
me_not_printable:
        LD A,'.'
me_ascii_out:
        RST 08h
        INC HL
        DEC C
        JR NZ,me_ascii_loop
        CALL TXCRLF
        POP BC
        DJNZ me_line_loop
        LD HL,me_help
        CALL PRINT
        JP me_position_cursor             ; Leave terminal cursor on selected byte

; Position terminal cursor at the selected byte's first HEX digit.
; Cursor offset = me_cursor - baseaddr. The display starts on terminal row 4;
; each row covers 16 bytes, so the offset's upper nibble selects the row.
; Each HEX byte takes 3 columns ('H''H' plus a space), starting at column 7.
me_position_cursor:
        PUSH DE
        LD HL,(me_cursor)
        LD DE,(baseaddr)
        OR A
        SBC HL,DE
        ; Emit ANSI CSI: ESC '[' row ';' column 'H'. HL now contains the offset.
        LD A,1Bh
        RST 08h
        LD A,'['
        RST 08h
        LD A,L
        RRCA
        RRCA
        RRCA
        RRCA
        AND $0F
        ADD A,4
        CALL me_print_decimal
        LD A,';'
        RST 08h
        LD A,L
        AND $0F
        LD C,A
        ; column = 7 + 3 * byte_index within the row.
        ADD A,A
        ADD A,C
        ADD A,7
        CALL me_print_decimal
        LD A,'H'
        RST 08h
        POP DE
        RET

; Refresh the ASCII character corresponding to the selected byte.
; ASCII starts at column 57; its row matches the HEX byte's row.
me_refresh_ascii:
        PUSH BC
        PUSH DE
        PUSH HL
        LD HL,(me_cursor)
        LD DE,(baseaddr)
        OR A
        SBC HL,DE                       ; HL = selected byte's offset in the page
        LD A,1Bh
        RST 08h
        LD A,'['
        RST 08h
        LD A,L
        RRCA
        RRCA
        RRCA
        RRCA
        AND $0F
        ADD A,4
        CALL me_print_decimal           ; Row = offset high nibble + 4
        LD A,';'
        RST 08h
        LD A,L
        AND $0F
        ADD A,57
        CALL me_print_decimal           ; Column = ASCII start + byte index
        LD A,'H'
        RST 08h
        LD HL,(me_cursor)
        LD A,(HL)
        CP $20
        JR C,me_refresh_ascii_dot
        CP $7F
        JR NC,me_refresh_ascii_dot
        JR me_refresh_ascii_out
me_refresh_ascii_dot:
        LD A,'.'
me_refresh_ascii_out:
        RST 08h
        POP HL
        POP DE
        POP BC
        RET

; Print unsigned decimal A (0..52) without leading zeroes.
; Repeated subtraction finds the tens digit in B and remainder in C.
me_print_decimal:
        LD B,0
me_decimal_tens:
        CP 10
        JR C,me_decimal_units
        SUB 10
        INC B
        JR me_decimal_tens
me_decimal_units:
        LD C,A
        LD A,B
        OR A
        JR Z,me_decimal_unit_only
        ADD A,'0'
        RST 08h
        LD A,C
        ADD A,'0'
        RST 08h
        RET
me_decimal_unit_only:
        LD A,C
        ADD A,'0'
        RST 08h
        RET

me_fill_byte:
        LD HL,me_fill_from_msg
        CALL PRINT
        CALL READ_HEX16                 ; read the starting address for the fill
        JP C,me_main                    ; Cancel keeps the current cursor
        JP Z,me_main                    ; Empty Enter keeps the current cursor
        LD (me_fill_from_address),HL


        LD HL,me_fill_to_msg
        CALL PRINT
        CALL READ_HEX16                 ; read the ending address for the fill
        JP C,me_main                    ; Cancel keeps the current cursor
        JP Z,me_main                    ; Empty Enter keeps the current cursor
        LD (me_fill_to_address),HL

        LD HL,me_fill_value_msg
        CALL PRINT
        CALL READ_HEX16                 ; read the byte value to fill with
        JP C,me_main                    ; Cancel keeps the current cursor
        JP Z,me_main                    ; Empty Enter keeps the current cursor
        LD A,L                          ; Z80 supports LD (nn),A, not LD (nn),L
        LD (me_fill_value),A

        ; Check the B < 3 (number of entered digits) to ensure the value is in the range 0-FFh.
        LD A,B
        CP 3
        JR C,me_fill_value_ok           ; Accept one or two hex digits

        LD HL,me_fill_error_value_msg
        CALL PRINT                      ; print an error message for invalid range
        RST 10h                         ; Wait for any key
        JP me_main                      ; Invalid range: ignore the fill command

me_fill_value_ok:
        ; Check that the range is valid: From < To

        LD HL,(me_fill_from_address)
        LD DE,(me_fill_to_address)
        OR A
        SBC HL,DE                       ; check that the range is valid
        JR C,me_fill_range_valid
        
        LD HL,me_fill_error_range_msg
        CALL PRINT                      ; print an error message for invalid range
        RST 10h                         ; Wait for any key
        JP me_main                      ; Invalid range: ignore the fill command

me_fill_range_valid:
        LD HL,(me_fill_from_address)
        LD DE,(me_fill_to_address)
        LD A,(me_fill_value)            ; Binary value of the byte
        LD C,A

me_fill_loop:
        LD (HL),C
        PUSH HL
        OR A                            ; Clear Carry before SBC
        SBC HL,DE                       ; HL = HL - DE; if HL = DE, then Z= 1
        POP HL
        JR Z,me_fill_done               ; if HL = DE, go to done; else continue filling
        INC HL
        JR me_fill_loop

me_fill_done:
        LD HL,me_fill_ok_msg
        CALL PRINT                      ; print a success message
        RST 10h                         ; Wait for any key
        JP me_main   

me_exit:
        LD HL,me_exit_cursor            ; save the current screen (set cursor on the bottom)
        CALL PRINT
        RET                             ; exit to Monitor


me_title:
        DB "Z80 MEMORY EDITOR by Denis@Chertkov.info",13,10
        DB "PAGE: ",0
me_title2:
        DB "h",13,10,13,10,0
me_help:
        DB 13,10
        DB "Arrows       move cursor",13,10
        DB "ENTER        edit/save byte",13,10
        DB "Use only safe writable RAM",13,10
        DB "N/SPACE,PgDn next page",13,10
        DB "P,PgUp       previous page",13,10
        DB "G            goto address",13,10
        DB "Q            quit",13,10
        DB 0
me_goto_msg:
        db ESC,"[3;1H"                  ; ANSI cursor positions
        DB "Address: ",0
me_fill_from_msg:
        db ESC,"[21;34H"                ; ANSI cursor positions
        DB "Fill range"
        db ESC,"[22;34H"                ; ANSI cursor positions
        DB "From :",0
me_fill_to_msg:
        db ESC,"[23;34H"                ; ANSI cursor positions
        DB "To   :",0
me_fill_value_msg:
        db ESC,"[24;34H"                ; ANSI cursor positions
        DB "Value:",0
me_fill_error_range_msg:
        db ESC,"[25;34H"                ; ANSI cursor positions
        DB "ERROR: From value must be more than To!",0
me_fill_error_value_msg:
        db ESC,"[25;34H"                ; ANSI cursor positions
        DB "ERROR: The value must be in range 0-FFh!",0
me_fill_ok_msg:
        db ESC,"[25;34H"                ; ANSI cursor positions
        DB "Fill completed successfully!",0
me_fill_from_address:                   ; fill start address
        DW 0000h
me_fill_to_address:                     ; fill end address
        DW 00FFh
me_fill_value:                          ; fill byte value
        DB 00h
me_exit_cursor:
        db ESC,"[18;1H",13,10,0               ; ANSI cursor positions to the bottom of the screen
