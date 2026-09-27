; Intel HEX: DATA bytes are still written before checksum validation.
; Writes are not transactional: checksum errors do not roll back stored bytes.
; Enter after ':'; RET returns to MAIN. Clobbers AF/BC/DE/HL.
; Types 02..05 are consumed but do not set the upper address bits.
LOAD:
        LD E,0                          ; checksum accumulator

        ; Record length
        CALL GET2
        LD D,A                          ; D = number of data bytes

        ; Load address high byte
        CALL GET2
        LD H,A

        ; Load address low byte
        CALL GET2
        LD L,A

        ; Record type
        CALL GET2

        CP $00                          ; DATA record?
        JR Z,LOAD2

        CP $01                          ; EOF record?
        JR Z,LOAD_EOF

        ; Any other Intel HEX record type:
        ; consume it, but DO NOT write to RAM
        JR LOAD_SKIP

; ------------------------------------------------------------------------------
; Type 00 - DATA record
; D  = number of bytes
; HL = destination address
; ------------------------------------------------------------------------------

LOAD2:
        LD A,D
        AND A
        JR Z,LOAD3

        CALL GET2                       ; get next data byte
        LD (HL),A                       ; write it to memory
        INC HL

        LD A,'.'
        RST 08H

        DEC D
        JR LOAD2


; ------------------------------------------------------------------------------
; End of DATA record - read and verify checksum
; ------------------------------------------------------------------------------

LOAD3:
        CALL GET2                       ; checksum byte

        LD A,E
        AND A
        RET Z                           ; checksum OK

        JR LOADERR


; ------------------------------------------------------------------------------
; Type 01 - End Of File
; ------------------------------------------------------------------------------

LOAD_EOF:
        CALL GET2                       ; checksum byte

        LD A,E
        AND A
        JR Z,LOAD00                     ; checksum OK, print "Load complete."

        JR LOADERR


; ------------------------------------------------------------------------------
; Unsupported Intel HEX record type
;
; Important: read all data bytes so the serial stream remains synchronized,
; but do NOT write them to memory.
; ------------------------------------------------------------------------------

LOAD_SKIP:
        LD A,D
        AND A
        JR Z,LOAD3


LOAD_SKIP_LOOP:
        CALL GET2                       ; read byte, update checksum
        ; but DON'T do LD (HL),A

        DEC D
        JR NZ,LOAD_SKIP_LOOP


        JR LOAD3                        ; Shared DATA/SKIP checksum check

LOADERR         LD HL,CKSUMERR          ; Get "Checksum Error" message
        CALL PRINT                      ; Print Message from (HL) and terminate the load
        RET

LOAD00          LD HL,LDETXT            ; Print load complete message
        CALL PRINT
        RET
