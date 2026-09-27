; The dispatcher pushes MAIN and enters command handlers via JP.
; MEMDUMP/PORTTEST must therefore return with RET without resetting SP.
MAIN            LD HL,MAIN              ; Save entry point for Monitor
        PUSH HL                         ; This is the return address
MAIN0           CALL TXCRLF             ; Entry point for Monitor, Normal
        LD A,'>'                        ; Get a ">"
        RST 08H                         ; print it

MAIN1           CALL RDCHR              ; Get a character from the input port
        CP ' '                          ; <spc> or less?
        JR C,MAIN1                      ; Go back

        CP ':'                          ; ":"?
        JP Z,LOAD                       ; First character of a HEX l oad

        CALL WRCHR                      ; Print char on console

        CP '?'
        JP Z, HELP

        AND $5F                         ; Make character uppercase

        CP 'R'
        JP Z,RST00

        CP 'B'
        JP Z,BASIC

        CP 'G'
        JP Z,GOTO

        CP 'M'
        JP Z,MEMDUMP                    ; Memory viewer

        CP 'P'
        JP Z,PORTTEST                   ; Port test

        CP 'X'
        JP Z,CPMLOAD

        LD A,'?'                        ; Get a "?"
        RST 08H                         ; Print it
        JR MAIN0

; ------------------------------------------------------------------------------
; Gxxxx: read the address and jump; RET C cancels the command.
; ------------------------------------------------------------------------------
GOTO            CALL READ_HEX16
        RET C                           ; Cancel
        RET Z                           ; Empty Enter: do not jump to address zero
        JP (HL)                         ; Explicit 0000 is valid; the program's RET returns to MAIN
; BC/BW: existing BASIC entry points; BASIC code is not part of this build.
BASIC
        LD HL,BASTXT
        CALL PRINT
        CALL GETCHR
        RET Z                           ; Cancel if CTRL-C
        AND $5F                         ; uppercase
        CP 'C'
        JP Z,BASCLD
        CP 'W'
        JP Z,BASWRM
        RET

; ------------------------------------------------------------------------------
; Display Help command
; ------------------------------------------------------------------------------
HELP            LD HL,HLPTXT            ; Print Help message
        CALL PRINT
        RET
