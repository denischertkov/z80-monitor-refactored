        ORG $0000                       ; MONITOR ROM RESET VECTOR
MON:
; ------------------------------------------------------------------------------
; Reset
; ------------------------------------------------------------------------------
RST00           DI                      ; Disable INTerrupts
        JP INIT                         ; Initialize Hardware and go
        NOP
        NOP
        NOP
        NOP
; ------------------------------------------------------------------------------
; TX a character over RS232 wait for TXDONE first.
; ------------------------------------------------------------------------------
RST08           JP conout
        NOP
        NOP
        DB 'ROM'                        ; ROM mark instead of NOPs to make it easier to find the ROM in memory
; ------------------------------------------------------------------------------
; RX a character from buffer wait until char ready.
; ------------------------------------------------------------------------------
RST10           JP conin
        NOP
        NOP
        NOP
        NOP
        NOP
; ------------------------------------------------------------------------------
; Check input buffer status
; ------------------------------------------------------------------------------
RST18           JP CKINCHAR

; ------------------------------------------------------------------------------
; SIO Vector = 0x60
; ------------------------------------------------------------------------------

        ; Padding keeps the raw image contiguous and the IM2 vector at $0060.
        DS $0060-$, $FF
SIO_VECTOR:
        DW serialInt
        ASSERT SIO_VECTOR == $0060
