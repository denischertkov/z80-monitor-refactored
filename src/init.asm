; SIO/IM2 initialization is unchanged. Falls through into MAIN.
INIT    LD SP,STACK                     ; Set the Stack Pointer

        ; Delay before SIO initialization after a reset.
        ; Required on this hardware to allow the Z80 SIO to complete reset
        ; after power-on before programming its control registers.
        ; Without this code the SIO doesn't work, because not configured by CPU.
.delay:
        LD BC,03FFFh
.d0:
        DEC BC                          ; Do not use DJNZ: DEC BC does not update the Z flag.
        LD A,B                          ; OR B and C to check whether the counter has reached zero.
        OR C                            ; Updates the Z flag.
        JR NZ,.d0

; Initialize the serial buffers and pointers       
        LD HL,serABuf
        LD (serAInPtr),HL
        LD (serARdPtr),HL

        LD HL,serBBuf
        LD (serBInPtr),HL
        LD (serBRdPtr),HL

        XOR A                           ; 0 to accumulator
        LD (serABufUsed),A
        LD (serBBufUsed),A

; Initialise SIO

        LD A,$00
        OUT (SIOA_C),A
        LD A,$18
        OUT (SIOA_C),A

        LD A,$04
        OUT (SIOA_C),A
        LD A,$C4                        ; SIOA Control Register 1: 8N1, CLK/64. Replace with $84 for CLK/32 (230400 baud).
        OUT (SIOA_C),A

        LD A,$01
        OUT (SIOA_C),A
        LD A,$18
        OUT (SIOA_C),A

        LD A,$03
        OUT (SIOA_C),A
        LD A,$E1
        OUT (SIOA_C),A

        LD A,$05
        OUT (SIOA_C),A
        LD A,RTS_LOW
        OUT (SIOA_C),A

        LD A,$00
        OUT (SIOB_C),A
        LD A,$18
        OUT (SIOB_C),A

        LD A,$04
        OUT (SIOB_C),A
        LD A,$C4                        ; SIOB Control Register 1: 8N1, CLK/64. Replace with $84 for CLK/32 (230400 baud).
        OUT (SIOB_C),A

        LD A,$01
        OUT (SIOB_C),A
        LD A,$18
        OUT (SIOB_C),A

        LD A,$02
        OUT (SIOB_C),A
        LD A,$60                        ; INTERRUPT VECTOR ADDRESS
        OUT (SIOB_C),A

        LD A,$03
        OUT (SIOB_C),A
        LD A,$E1
        OUT (SIOB_C),A

        LD A,$05
        OUT (SIOB_C),A
        LD A,RTS_LOW
        OUT (SIOB_C),A

        ; Interrupt vector in page 0
        LD A,$00
        LD I,A

        IM 2
        EI

        ; Display the "Press space to start" message on both consoles
        LD A,$00
        LD (primaryIO),A
        LD HL,INITTXT
        CALL PRINT
        LD A,$01
        LD (primaryIO),A
        LD HL,INITTXT
        CALL PRINT

        ; Wait until space is in one of the buffers to determine the active console

waitForSpace:

        CALL ckincharA
        jr Z,notInA
        LD A,$00
        LD (primaryIO),A
        CALL conin
        CP ' '
        JP NZ, waitForSpace
        JR spacePressed

notInA:
        CALL ckincharB
        JR Z,waitForSpace
        LD A,$01
        LD (primaryIO),A
        CALL conin
        CP ' '
        JP NZ, waitForSpace
        JR spacePressed

spacePressed:

        ; Clear message on both consoles
        LD A,$0C
        CALL conoutA
        CALL conoutB

        ; primaryIO is now set to the channel where SPACE was pressed


        CALL TXCRLF                     ; TXCRLF
        LD HL,SIGNON                    ; Print SIGNON message
        CALL PRINT
