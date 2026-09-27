; SIO/IM2 initialization is unchanged. Falls through into MAIN.
INIT            LD SP,STACK             ; Set the Stack Pointer

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
        LD A,$C4
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
        LD A,$C4
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
