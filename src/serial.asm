; SIO: original driver instructions retained, including DI/EI and delays.
; conin preserves BC/DE/HL, returns the character in A, changes F, enables IRQs.
; conout preserves AF/BC/DE/HL; waits until the transmitter is ready.
serialInt:      PUSH AF
        PUSH HL

        ; Check if there is a char in channel A
        ; If not, there is a char in channel B
        SUB A
        OUT (SIOA_C),A
        IN A,(SIOA_C)                   ; Status byte D2=TX Buff Empty, D0=RX char ready
        RRCA                            ; Rotates RX status into Carry Flag,
        JR NC, serialIntB

serialIntA:
        LD HL,(serAInPtr)
        INC HL
        LD A,L
        CP (serABuf+SER_BUFSIZE) & $FF
        JR NZ, notAWrap
        LD HL,serABuf
notAWrap:
        LD (serAInPtr),HL
        IN A,(SIOA_D)
        LD (HL),A

        LD A,(serABufUsed)
        INC A
        LD (serABufUsed),A
        CP SER_FULLSIZE
        JR C,rtsA0
        LD A,$05
        OUT (SIOA_C),A
        LD A,RTS_HIGH
        OUT (SIOA_C),A
rtsA0:
        POP HL
        POP AF
        EI
        RETI

serialIntB:
        LD HL,(serBInPtr)
        INC HL
        LD A,L
        CP (serBBuf+SER_BUFSIZE) & $FF
        JR NZ, notBWrap
        LD HL,serBBuf
notBWrap:
        LD (serBInPtr),HL
        IN A,(SIOB_D)
        LD (HL),A

        LD A,(serBBufUsed)
        INC A
        LD (serBBufUsed),A
        CP SER_FULLSIZE
        JR C,rtsB0
        LD A,$05
        OUT (SIOB_C),A
        LD A,RTS_HIGH
        OUT (SIOB_C),A
rtsB0:
        POP HL
        POP AF
        EI
        RETI

; ------------------------------------------------------------------------------
; Console input routine
; Use the "primaryIO" flag to determine which input port to monitor.
; ------------------------------------------------------------------------------
conin:
        PUSH HL
        LD A,(primaryIO)
        CP 0
        JR NZ,coninB
coninA:

waitForCharA:
        LD A,(serABufUsed)
        CP $00
        JR Z, waitForCharA
        LD HL,(serARdPtr)
        INC HL
        LD A,L
        CP (serABuf+SER_BUFSIZE) & $FF
        JR NZ, notRdWrapA
        LD HL,serABuf
notRdWrapA:
        DI
        LD (serARdPtr),HL

        LD A,(serABufUsed)
        DEC A
        LD (serABufUsed),A

        CP SER_EMPTYSIZE
        JR NC,rtsA1
        LD A,$05
        OUT (SIOA_C),A
        LD A,RTS_LOW
        OUT (SIOA_C),A
rtsA1:
        LD A,(HL)
        EI

        POP HL

        RET                             ; Char ready in A


coninB:

waitForCharB:
        LD A,(serBBufUsed)
        CP $00
        JR Z, waitForCharB
        LD HL,(serBRdPtr)
        INC HL
        LD A,L
        CP (serBBuf+SER_BUFSIZE) & $FF
        JR NZ, notRdWrapB
        LD HL,serBBuf
notRdWrapB:
        DI
        LD (serBRdPtr),HL

        LD A,(serBBufUsed)
        DEC A
        LD (serBBufUsed),A

        CP SER_EMPTYSIZE
        JR NC,rtsB1
        LD A,$05
        OUT (SIOB_C),A
        LD A,RTS_LOW
        OUT (SIOB_C),A
rtsB1:
        LD A,(HL)
        EI

        POP HL

        RET                             ; Char ready in A

; ------------------------------------------------------------------------------
; Console output routine
; Use the "primaryIO" flag to determine which output port to send a character.
; ------------------------------------------------------------------------------
conout:         PUSH AF                 ; Store character
        LD A,(primaryIO)
        CP 0
        JR NZ,conoutB1
        JR conoutA1
conoutA:
        PUSH AF

conoutA1:       CALL CKSIOA             ; See if SIO channel A is finished transmitting
        JR Z,conoutA1                   ; Loop until SIO flag signals ready
        POP AF                          ; RETrieve character
        OUT (SIOA_D),A                  ; OUTput the character
        RET

conoutB:
        PUSH AF

conoutB1:       CALL CKSIOB             ; See if SIO channel B is finished transmitting
        JR Z,conoutB1                   ; Loop until SIO flag signals ready
        POP AF                          ; RETrieve character
        OUT (SIOB_D),A                  ; OUTput the character
        RET

; ------------------------------------------------------------------------------
; I/O status check routine
; Use the "primaryIO" flag to determine which port to check.
; ------------------------------------------------------------------------------
CKSIOA
        SUB A
        OUT (SIOA_C),A
        IN A,(SIOA_C)                   ; Status byte D2=TX Buff Empty, D0=RX char ready
        RRCA                            ; Rotates RX status into Carry Flag,
        BIT 1,A                         ; Set Zero flag if still transmitting character
        RET

CKSIOB
        SUB A
        OUT (SIOB_C),A
        IN A,(SIOB_C)                   ; Status byte D2=TX Buff Empty, D0=RX char ready
        RRCA                            ; Rotates RX status into Carry Flag,
        BIT 1,A                         ; Set Zero flag if still transmitting character
        RET

; ------------------------------------------------------------------------------
; Check if there is a character in the input buffer
; Use the "primaryIO" flag to determine which port to check.
; ------------------------------------------------------------------------------
CKINCHAR
        LD A,(primaryIO)
        CP 0
        JR NZ,ckincharB

ckincharA:

        LD A,(serABufUsed)
        CP $0
        RET

ckincharB:

        LD A,(serBBufUsed)
        CP $0
        RET
