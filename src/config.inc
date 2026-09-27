; Original monitor hardware constants. Port addresses are unchanged.
CR              EQU 0DH
LF              EQU 0AH
ESC             EQU 1BH
CTRLC           EQU 03H
CLS             EQU 0CH

; CF registers
CF_DATA         EQU $10
CF_FEATURES     EQU $11
CF_ERROR        EQU $11
CF_SECCOUNT     EQU $12
CF_SECTOR       EQU $13
CF_CYL_LOW      EQU $14
CF_CYL_HI       EQU $15
CF_HEAD         EQU $16
CF_STATUS       EQU $17
CF_COMMAND      EQU $17
CF_LBA0         EQU $13
CF_LBA1         EQU $14
CF_LBA2         EQU $15
CF_LBA3         EQU $16

; CF Features
CF_8BIT         EQU 1
CF_NOCACHE      EQU 082H
; CF Commands
CF_READ_SEC     EQU 020H
CF_WRITE_SEC    EQU 030H
CF_SET_FEAT     EQU 0EFH


loadAddr        EQU 0D000h              ; CP/M load address
numSecs         EQU 24                  ; Number of 512 sectors to be loaded


; BASIC cold and warm entry points
BASCLD          EQU $2000
BASWRM          EQU $2003

SER_BUFSIZE     EQU 40H
SER_FULLSIZE    EQU 30H
SER_EMPTYSIZE   EQU 5

RTS_HIGH        EQU 0E8H
RTS_LOW         EQU 0EAH

SIOA_D          EQU $00
SIOA_C          EQU $02
SIOB_D          EQU $01
SIOB_C          EQU $03
