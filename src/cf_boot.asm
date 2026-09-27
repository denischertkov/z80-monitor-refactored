; CP/M loader and low-level CF driver: instructions are unchanged.
; cfWait checks only BUSY, not DRQ/errors. rdByte delays are retained.
CPMLOAD
        LD HL,CPMTXT
        CALL PRINT
        CALL GETCHR
        RET Z                           ; Cancel if CTRL-C
        AND $5F                         ; uppercase
        CP 'Y'
        JP Z,CPMLOAD2
        RET
CPMTXT
        DB $0D,$0A
        DB "Boot CP/M?"
        DB $00

CPMTXT2
        DB $0D,$0A
        DB "Loading CP/M..."
        DB $0D,$0A,$00

CPMLOAD2
        LD HL,CPMTXT2
        CALL PRINT


        CALL cfWait
        LD A,CF_8BIT                    ; Set IDE to be 8bit
        OUT (CF_FEATURES),A
        LD A,CF_SET_FEAT
        OUT (CF_COMMAND),A


        CALL cfWait
        LD A,CF_NOCACHE                 ; No write cache
        OUT (CF_FEATURES),A
        LD A,CF_SET_FEAT
        OUT (CF_COMMAND),A

        LD B,numSecs

        LD A,0
        LD (secNo),A
        LD HL,loadAddr
        LD (dmaAddr),HL
processSectors:

        CALL cfWait

        LD A,(secNo)
        OUT (CF_LBA0),A
        LD A,0
        OUT (CF_LBA1),A
        OUT (CF_LBA2),A
        LD a,0E0H
        OUT (CF_LBA3),A
        LD A,1
        OUT (CF_SECCOUNT),A

        call read

        LD DE,0200H
        LD HL,(dmaAddr)
        ADD HL,DE
        LD (dmaAddr),HL
        LD A,(secNo)
        INC A
        LD (secNo),A

        djnz processSectors

; Start CP/M using entry at top of BIOS
; The current active console stream ID is pushed onto the stack
; to allow the CBIOS to pick it up
; 0 = SIO A, 1 = SIO B

        ld A,(primaryIO)
        PUSH AF
        ld HL,($FFFE)
        jp (HL)


; ------------------------------------------------------------------------------

; Read physical sector from host

read:
        PUSH AF
        PUSH BC
        PUSH HL

        CALL cfWait

        LD A,CF_READ_SEC
        OUT (CF_COMMAND),A

        CALL cfWait

        LD c,4
        LD HL,(dmaAddr)
rd4secs:
        LD b,128
rdByte:
        nop
        nop
        in A,(CF_DATA)
        LD (HL),A
        INC HL
        dec b
        JR NZ, rdByte
        dec c
        JR NZ,rd4secs

        POP HL
        POP BC
        POP AF

        RET


; Wait for disk to be ready (busy=0,ready=1)
cfWait:
        PUSH AF
cfWait1:
        in A,(CF_STATUS)
        AND 080H
        cp 080H
        JR Z,cfWait1
        POP AF
        RET
