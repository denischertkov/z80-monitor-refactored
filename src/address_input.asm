; Shared 16-bit HEX address editor for G, M, and G inside memview.
; Input: none. Reads raw console input via RST $10; echoes via RST $08.
; Accepts 1..4 digits from 0..9/A..F/a..f; CR (Enter) confirms.
; LF and invalid bytes are ignored. A fifth digit is ignored without echo.
; BS ($08) and DEL ($7F) erase the last digit: emit BS, space, BS.
; Esc or Ctrl-C cancels immediately; pending input is not flushed.
;
; Output:
; C=0,Z=0: HL=address, including an explicitly entered 0000.
; C=0,Z=1: empty Enter, HL=0.
; C=1:     cancelled; do not use HL/Z.
; Clobbers AF/BC/HL; preserves DE/IX/IY. No additional RAM required.
; B=digit count (0..4), C=nibble value or shift counter.
; Enter emits CR/LF; after cancellation the caller restores the screen.
; GETHL remains an alias, but now follows the contract described above.
GETHL:
READ_HEX16:
        LD HL,0
        LD B,0
addr_wait:
        RST $10
        CP $0D
        JR Z,addr_done
        CP $03
        JR Z,addr_cancel
        CP $1B
        JR Z,addr_cancel
        CP $08
        JR Z,addr_backspace
        CP $7F
        JR Z,addr_backspace

        BIT 2,B                         ; B=4? Check AFTER handling control keys.
        JR NZ,addr_wait
        SUB '0'
        CP 10
        JR C,addr_digit
        SUB 17                          ; ('A'-'0')=17: A..F -> 0..5, a..f -> 32..37
        AND $DF                         ; Clear only the letter case bit
        CP 6                            ; Strict validation: reject all other bytes
        JR NC,addr_wait
        ADD A,10
addr_digit:
        LD C,A
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        LD A,L
        OR C
        LD L,A
        INC B
        LD A,C
        CALL HEXDIGIT                   ; Shared uppercase echo; preserves BC/HL
        JR addr_wait

addr_backspace:
        LD A,B
        OR A
        JR Z,addr_wait                  ; Empty input: do not erase the prompt
        DEC B
        LD C,4
addr_shift:
        SRL H
        RR L                            ; HL >>= 1; transfer H to L through Carry
        DEC C                           ; DEC preserves Carry
        JR NZ,addr_shift
        LD A,$08
        RST $08
        LD A,' '
        RST $08
        LD A,$08
        RST $08
        JR addr_wait

addr_done:
        CALL TXCRLF
        LD A,B
        OR A                            ; C=0; Z describes input length, not the value of HL
        RET
addr_cancel:
        SCF
        RET
