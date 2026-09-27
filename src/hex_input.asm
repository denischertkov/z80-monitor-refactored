; Intel HEX byte parsing is unchanged. Address input is in address_input.asm.
; GET2: A=byte, E=checksum accumulator; clobbers BC/AF, preserves D/HL.
GETCHR          CALL RDCHR              ; RX a Character
        CP $03                          ; <ctrl-c> User break?
        RET Z
        CP $20                          ; <space> or better?
        JR C,GETCHR                     ; Do it again until we get something usable
        RET
; ------------------------------------------------------------------------------
; Gets two ASCII characters from the console (assuming them to be HEX 0-9 A-F)
; Moves them into B and C, converts them into a byte value in A and updates a
; Checksum value in E
; ------------------------------------------------------------------------------
GET2            CALL GETCHR             ; Get us a valid character to work with
        LD B,A                          ; Load it in B
        CALL GETCHR                     ; Get us another character
        LD C,A                          ; load it in C
        CALL BCTOA                      ; Convert ASCII to byte
        LD C,A                          ; Build the checksum
        LD A,E
        SUB C                           ; The checksum should always equal zero when checked
        LD E,A                          ; Save the checksum back where it came from
        LD A,C                          ; Retrieve the byte and go back
        RET
; ------------------------------------------------------------------------------
; Convert ASCII characters in B C registers to a byte value in A
; ------------------------------------------------------------------------------
BCTOA           LD A,B                  ; Move the hi order byte to A
        SUB $30                         ; Take it down from Ascii
        CP $0A                          ; Are we in the 0-9 range here?
        JR C,BCTOA1                     ; If so, get the next nybble
        SUB $07                         ; But if A-F, take it down some more
BCTOA1          RLCA                    ; Rotate the nybble from low to high
        RLCA                            ; One bit at a time
        RLCA                            ; Until we
        RLCA                            ; Get there with it
        LD B,A                          ; Save the converted high nybble
        LD A,C                          ; Now get the low order byte
        SUB $30                         ; Convert it down from Ascii
        CP $0A                          ; 0-9 at this point?
        JR C,BCTOA2                     ; Good enough then, but
        SUB $07                         ; Take off 7 more if it's A-F
BCTOA2          ADD A,B                 ; Add in the high order nybble
        RET
