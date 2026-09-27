; Shared output routines; RST $08 preserves AF/BC/DE/HL.
; PRINT: HL -> NUL string; returns HL -> NUL, A=0, Z=1; preserves BC/DE.
; TXCRLF: emits CR/LF, returns A=LF; preserves BC/DE/HL.
; PRINT_HEX8: A -> two digits; clobbers AF, preserves BC/DE/HL.
; PRINT_BIN8: A -> eight binary digits; clobbers AF, preserves BC/DE/HL.
; HEXDIGIT: A=0..15 -> one digit; clobbers AF, preserves BC/DE/HL.
; PRINT_HEX16: HL -> four digits; clobbers AF, preserves BC/DE/HL.
PRINT   LD A,(HL)                       ; Get character
        OR A                            ; Is it $00 ?
        RET Z                           ; Then RETurn on terminator
        RST 08H                         ; Print it
        INC HL                          ; Next Character
        JR PRINT                        ; Continue until $00


TXCRLF  LD A,$0D                        ;
        RST 08H                         ; Print character
        LD A,$0A                        ;
        RST 08H                         ; Print character
        RET

; ------------------------------------------------------------------------------
; Print A as two hexadecimal digits
; ------------------------------------------------------------------------------
PRINT_HEX8:
        PUSH AF

        RRCA
        RRCA
        RRCA
        RRCA
        AND $0F
        CALL HEXDIGIT

        POP AF
        AND $0F

HEXDIGIT:
        ADD A,'0'
        CP '9'+1
        JR C,HEXOUT

        ADD A,7

HEXOUT:
        RST 08H
        RET

; ------------------------------------------------------------------------------
; Print A as eight binary digits, most-significant bit first
; ------------------------------------------------------------------------------
PRINT_BIN8:
        PUSH BC
        PUSH DE
        LD D,A
        LD B,8
print_bin8_loop:
        SLA D                           ; Shift left, MSB -> carry flag
        LD A,'0'                        ; Prepare to print '0' or '1'
        ADC A,0                         ; Add carry flag to A
        RST 08H                         ; Print character
        DJNZ print_bin8_loop
        POP DE
        POP BC
        RET

; ------------------------------------------------------------------------------
; Print HL as four hexadecimal digits
; HL preserved
; ------------------------------------------------------------------------------
PRINT_HEX16:
        LD A,H
        CALL PRINT_HEX8
        LD A,L
        JP PRINT_HEX8                   ; Tail call: PRINT_HEX8 already preserves HL
