; Снимок предыдущего рефакторинга до унификации; INCLUDE раскрыты для сравнения.
;==================================================================================
; 
; Based on the original Z80 Monitor Rom by Grant Searle (http://searle.hostei.com/grant/index.html)
; Added the new memory viewer and build info string to the signon message.
; Fix Intel HEX loading for non-data record types (0000h and 0001h RAM address corruption).
; Denis Chertkov, denis@chertkov.info, 20260912
;
;==================================================================================
;
; Contents of this file are copyright Grant Searle
; HEX routines from Joel Owens.
;
; You have permission to use this for NON COMMERCIAL USE ONLY
; If you wish to use it elsewhere, please include an acknowledgement to myself.
;
; http://searle.hostei.com/grant/index.html
;
; eMail: home.micros01@btinternet.com
;==================================================================================

; Рефакторинг для sjasmplus 1.24.0.
; Это только монитор, а НЕ полный образ ROM с BASIC.
; Абсолютные RST-векторы и рабочая RAM сохраняют прежние адреса.
; Аппаратные константы исходного монитора. Адреса портов не изменены.
CR				EQU	0DH
LF				EQU	0AH
ESC				EQU	1BH
CTRLC			EQU	03H
CLS				EQU	0CH

; CF registers
CF_DATA			EQU	$10
CF_FEATURES		EQU	$11
CF_ERROR		EQU	$11
CF_SECCOUNT		EQU	$12
CF_SECTOR		EQU	$13
CF_CYL_LOW		EQU	$14
CF_CYL_HI		EQU	$15
CF_HEAD			EQU	$16
CF_STATUS		EQU	$17
CF_COMMAND		EQU	$17
CF_LBA0			EQU	$13
CF_LBA1			EQU	$14
CF_LBA2			EQU	$15
CF_LBA3			EQU	$16

;CF Features
CF_8BIT			EQU	1
CF_NOCACHE		EQU	082H
;CF Commands
CF_READ_SEC		EQU	020H
CF_WRITE_SEC	EQU	030H
CF_SET_FEAT		EQU 0EFH


loadAddr		EQU	0D000h					; CP/M load address
numSecs			EQU	24						; Number of 512 sectors to be loaded


;BASIC cold and warm entry points
BASCLD			EQU	$2000
BASWRM			EQU	$2003

SER_BUFSIZE		EQU	40H
SER_FULLSIZE	EQU	30H
SER_EMPTYSIZE	EQU	5

RTS_HIGH		EQU	0E8H
RTS_LOW			EQU	0EAH

SIOA_D			EQU	$00
SIOA_C			EQU	$02
SIOB_D			EQU	$01
SIOB_C			EQU	$03

; RAM workspace used by the monitor (addresses only; not emitted into ROM)
serABuf        	EQU $4000
serAInPtr      	EQU serABuf + SER_BUFSIZE
serARdPtr      	EQU serAInPtr + 2
serABufUsed    	EQU serARdPtr + 2
serBBuf        	EQU serABufUsed + 1
serBInPtr      	EQU serBBuf + SER_BUFSIZE
serBRdPtr      	EQU serBInPtr + 2
serBBufUsed    	EQU serBRdPtr + 2

primaryIO      	EQU serBBufUsed + 1
secNo          	EQU primaryIO + 1
dmaAddr        	EQU secNo + 1

stackSpace     	EQU dmaAddr + 2
STACK          	EQU stackSpace + 32
baseaddr	   	EQU STACK					; memview base address variable (2 bytes)
portno			EQU baseaddr+2				; porttest port number variable (1 byte)		
value			EQU portno+1				; porttest value variable (1 byte)
											; the next variable should use the value+1 address!

; Стек растёт вниз от STACK=$40AE; baseaddr начинается ровно над ним.
; Зарезервированный стек: $408E..$40AD, 32 байта. Не расширяем его
; молча: адреса переменных и пользовательского загрузчика должны сохраниться.
WORKSPACE_END EQU value+1
        ASSERT STACK == $40AE
        ASSERT baseaddr == $40AE
        ASSERT portno == $40B0
        ASSERT value == $40B1

		ORG $0000		; MONITOR ROM RESET VECTOR
MON:
;------------------------------------------------------------------------------
; Reset
;------------------------------------------------------------------------------
RST00	DI				;Disable INTerrupts
		JP	INIT		;Initialize Hardware and go
		NOP
		NOP
		NOP
		NOP
;------------------------------------------------------------------------------
; TX a character over RS232 wait for TXDONE first.
;------------------------------------------------------------------------------
RST08		JP	conout
		NOP
		NOP
		DB 'ROM'		; ROM mark instead of NOPs to make it easier to find the ROM in memory
;------------------------------------------------------------------------------
; RX a character from buffer wait until char ready.
;------------------------------------------------------------------------------
RST10		JP	conin
		NOP
		NOP
		NOP
		NOP
		NOP
;------------------------------------------------------------------------------
; Check input buffer status
;------------------------------------------------------------------------------
RST18		JP	CKINCHAR

;------------------------------------------------------------------------------
; SIO Vector = 0x60
;------------------------------------------------------------------------------

		; Заполнитель сохраняет непрерывный raw-образ и вектор IM2 по $0060.
		DS $0060-$, $FF
SIO_VECTOR:
		DW	serialInt
		ASSERT SIO_VECTOR == $0060

; SIO: инструкции оригинального драйвера сохранены, включая DI/EI и задержки.
; conin сохраняет BC/DE/HL, возвращает символ в A; F изменены, включает IRQ.
; conout сохраняет AF/BC/DE/HL; ждёт готовности передатчика.
serialInt:	PUSH	AF
		PUSH	HL

		; Check if there is a char in channel A
		; If not, there is a char in channel B
		SUB	A
		OUT 	(SIOA_C),A
		IN   	A,(SIOA_C)	; Status byte D2=TX Buff Empty, D0=RX char ready	
		RRCA			; Rotates RX status into Carry Flag,	
		JR	NC, serialIntB

serialIntA:
		LD	HL,(serAInPtr)
		INC	HL
		LD	A,L
		CP	(serABuf+SER_BUFSIZE) & $FF
		JR	NZ, notAWrap
		LD	HL,serABuf
notAWrap:
		LD	(serAInPtr),HL
		IN	A,(SIOA_D)
		LD	(HL),A

		LD	A,(serABufUsed)
		INC	A
		LD	(serABufUsed),A
		CP	SER_FULLSIZE
		JR	C,rtsA0
	    LD   	A,$05
		OUT  	(SIOA_C),A
	    LD   	A,RTS_HIGH
		OUT  	(SIOA_C),A
rtsA0:
		POP	HL
		POP	AF
		EI
		RETI

serialIntB:
		LD	HL,(serBInPtr)
		INC	HL
		LD	A,L
		CP	(serBBuf+SER_BUFSIZE) & $FF
		JR	NZ, notBWrap
		LD	HL,serBBuf
notBWrap:
		LD	(serBInPtr),HL
		IN	A,(SIOB_D)
		LD	(HL),A

		LD	A,(serBBufUsed)
		INC	A
		LD	(serBBufUsed),A
		CP	SER_FULLSIZE
		JR	C,rtsB0
	    LD   	A,$05
		OUT  	(SIOB_C),A
	    LD   	A,RTS_HIGH
		OUT  	(SIOB_C),A
rtsB0:
		POP	HL
		POP	AF
		EI
		RETI

;------------------------------------------------------------------------------
; Console input routine
; Use the "primaryIO" flag to determine which input port to monitor.
;------------------------------------------------------------------------------
conin:
		PUSH	HL
		LD	A,(primaryIO)
		CP	0
		JR	NZ,coninB
coninA:

waitForCharA:
		LD	A,(serABufUsed)
		CP	$00
		JR	Z, waitForCharA
		LD	HL,(serARdPtr)
		INC	HL
		LD	A,L
		CP	(serABuf+SER_BUFSIZE) & $FF
		JR	NZ, notRdWrapA
		LD	HL,serABuf
notRdWrapA:
		DI
		LD	(serARdPtr),HL

		LD	A,(serABufUsed)
		DEC	A
		LD	(serABufUsed),A

		CP	SER_EMPTYSIZE
		JR	NC,rtsA1
	    LD  A,$05
		OUT (SIOA_C),A
	    LD  A,RTS_LOW
		OUT (SIOA_C),A
rtsA1:
		LD	A,(HL)
		EI

		POP	HL

		RET	; Char ready in A


coninB:

waitForCharB:
		LD	A,(serBBufUsed)
		CP	$00
		JR	Z, waitForCharB
		LD	HL,(serBRdPtr)
		INC	HL
		LD	A,L
		CP	(serBBuf+SER_BUFSIZE) & $FF
		JR	NZ, notRdWrapB
		LD	HL,serBBuf
notRdWrapB:
		DI
		LD	(serBRdPtr),HL

		LD	A,(serBBufUsed)
		DEC	A
		LD	(serBBufUsed),A

		CP	SER_EMPTYSIZE
		JR	NC,rtsB1
	    LD  A,$05
		OUT (SIOB_C),A
	    LD  A,RTS_LOW
		OUT (SIOB_C),A
rtsB1:
		LD	A,(HL)
		EI

		POP	HL

		RET	; Char ready in A

;------------------------------------------------------------------------------
; Console output routine
; Use the "primaryIO" flag to determine which output port to send a character.
;------------------------------------------------------------------------------
conout:	PUSH	AF		; Store character
		LD	A,(primaryIO)
		CP	0
		JR	NZ,conoutB1
		JR	conoutA1
conoutA:
		PUSH	AF

conoutA1:	CALL	CKSIOA		; See if SIO channel A is finished transmitting
		JR	Z,conoutA1	; Loop until SIO flag signals ready
		POP	AF		; RETrieve character
		OUT	(SIOA_D),A	; OUTput the character
		RET

conoutB:
		PUSH	AF

conoutB1:	CALL	CKSIOB		; See if SIO channel B is finished transmitting
		JR	Z,conoutB1	; Loop until SIO flag signals ready
		POP	AF		; RETrieve character
		OUT	(SIOB_D),A	; OUTput the character
		RET

;------------------------------------------------------------------------------
; I/O status check routine
; Use the "primaryIO" flag to determine which port to check.
;------------------------------------------------------------------------------
CKSIOA
		SUB	A
		OUT 	(SIOA_C),A
		IN   	A,(SIOA_C)	; Status byte D2=TX Buff Empty, D0=RX char ready	
		RRCA			; Rotates RX status into Carry Flag,	
		BIT  	1,A		; Set Zero flag if still transmitting character	
        RET

CKSIOB
		SUB	A
		OUT 	(SIOB_C),A
		IN   	A,(SIOB_C)	; Status byte D2=TX Buff Empty, D0=RX char ready	
		RRCA			; Rotates RX status into Carry Flag,	
		BIT  	1,A		; Set Zero flag if still transmitting character	
        RET

;------------------------------------------------------------------------------
; Check if there is a character in the input buffer
; Use the "primaryIO" flag to determine which port to check.
;------------------------------------------------------------------------------
CKINCHAR
		LD	A,(primaryIO)
		CP	0
		JR	NZ,ckincharB

ckincharA:

		LD	A,(serABufUsed)
		CP	$0
		RET

ckincharB:

		LD	A,(serBBufUsed)
		CP	$0
		RET

; Фильтрация символов для командной строки; viewer использует сырые RST.
RDCHR	RST	10H
		CP	LF
		JR	Z,RDCHR		; Ignore LF
		CP	ESC
		JR	NZ,RDCHR1
		LD	A,CTRLC		; Change ESC to CTRL-C
RDCHR1	RET

WRCHR	CP	CR
		JR	Z,WRCRLF	; When CR, write CRLF
		CP	CLS
		JR	Z,WR		; Allow write of "CLS"
		CP	' '			; Don't write out any other control codes
		JR	C,NOWR		; ie. < space
WR		RST	08H
NOWR		RET

WRCRLF	LD	A,CR
		RST	08H
		LD	A,LF
		RST	08H
		LD	A,CR
		RET

; Инициализация SIO/IM2 без изменений. В конце — fall-through в MAIN.
INIT	LD   SP,STACK		; Set the Stack Pointer

		LD	HL,serABuf
		LD	(serAInPtr),HL
		LD	(serARdPtr),HL

		LD	HL,serBBuf
		LD	(serBInPtr),HL
		LD	(serBRdPtr),HL

		XOR A				;0 to accumulator
		LD (serABufUsed),A
		LD	(serBBufUsed),A

;	Initialise SIO

		LD	A,$00
		OUT	(SIOA_C),A
		LD	A,$18
		OUT	(SIOA_C),A

		LD	A,$04
		OUT	(SIOA_C),A
		LD	A,$C4
		OUT	(SIOA_C),A

		LD	A,$01
		OUT	(SIOA_C),A
		LD	A,$18
		OUT	(SIOA_C),A

		LD	A,$03
		OUT	(SIOA_C),A
		LD	A,$E1
		OUT	(SIOA_C),A

		LD	A,$05
		OUT	(SIOA_C),A
		LD	A,RTS_LOW
		OUT	(SIOA_C),A

		LD	A,$00
		OUT	(SIOB_C),A
		LD	A,$18
		OUT	(SIOB_C),A

		LD	A,$04
		OUT	(SIOB_C),A
		LD	A,$C4
		OUT	(SIOB_C),A

		LD	A,$01
		OUT	(SIOB_C),A
		LD	A,$18
		OUT	(SIOB_C),A

		LD	A,$02
		OUT	(SIOB_C),A
		LD	A,$60		; INTERRUPT VECTOR ADDRESS
		OUT	(SIOB_C),A
	
		LD	A,$03
		OUT	(SIOB_C),A
		LD	A,$E1
		OUT	(SIOB_C),A

		LD	A,$05
		OUT	(SIOB_C),A
		LD	A,RTS_LOW
		OUT	(SIOB_C),A

		; Interrupt vector in page 0
		LD	A,$00
		LD	I,A

		IM	2
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
		jr	Z,notInA
		LD	A,$00
		LD	(primaryIO),A
		CALL	conin
		CP	' '
		JP	NZ, waitForSpace
		JR	spacePressed

notInA:
		CALL ckincharB
		JR	Z,waitForSpace
		LD	A,$01
		LD	(primaryIO),A
		CALL	conin
		CP	' '
		JP	NZ, waitForSpace
		JR	spacePressed

spacePressed:

		; Clear message on both consoles
		LD	A,$0C
		CALL	conoutA
		CALL	conoutB

		; primaryIO is now set to the channel where SPACE was pressed
	

		CALL TXCRLF	; TXCRLF
		LD   HL,SIGNON	; Print SIGNON message
		CALL PRINT

; Диспетчер кладёт MAIN в стек и делает JP в обработчик команды.
; Поэтому MEMDUMP/PORTTEST должны завершаться RET, не сбрасывая SP.
MAIN  	LD   HL,MAIN	; Save entry point for Monitor	
		PUSH HL			; This is the return address
MAIN0	CALL TXCRLF		; Entry point for Monitor, Normal	
		LD   A,'>'		; Get a ">"	
		RST 08H			; print it

MAIN1	CALL RDCHR		; Get a character from the input port
		CP   ' '		; <spc> or less? 	
		JR   C,MAIN1	; Go back
	
		CP   ':'		; ":"?
		JP   Z,LOAD		; First character of a HEX l	oad

		CALL WRCHR		; Print char on console

		CP   '?'
		JP   Z,	HELP

		AND  $5F		; Make character uppercase

		CP   'R'
		JP   Z,RST00

		CP   'B'
		JP   Z,BASIC

		CP   'G'
		JP   Z,GOTO

		CP   'M'
		JP   Z,MEMDUMP			; Memory viewer

		CP   'P'
		JP   Z,PORTTEST			; Port test

		CP   'X'
		JP   Z,CPMLOAD

		LD   A,'?'	; Get a "?"	
		RST 08H		; Print it
		JR   MAIN0
	
;------------------------------------------------------------------------------
; Gxxxx: разбор адреса и переход; RET C отменяет команду.
;------------------------------------------------------------------------------
GOTO	CALL GETHL		; ENTRY POINT FOR <G>oto addr. Get XXXX from user.
		RET  C			; Return if invalid       	
		PUSH HL
		RET				; Jump to HL address value
; BC/BW: существующие точки входа BASIC, код BASIC в сборку не включён.
BASIC
    	LD HL,BASTXT
		CALL PRINT
		CALL GETCHR
		RET Z	; Cancel if CTRL-C
		AND  $5F ; uppercase
		CP 'C'
		JP  Z,BASCLD
		CP 'W'
		JP  Z,BASWRM
		RET

;------------------------------------------------------------------------------
; Display Help command
;------------------------------------------------------------------------------
HELP   	LD   HL,HLPTXT	; Print Help message
		CALL PRINT
		RET

; Общие процедуры вывода; RST $08 сохраняет AF/BC/DE/HL.
; PRINT: HL -> NUL-строка; выход HL -> NUL, A=0, Z=1; BC/DE сохранены.
; TXCRLF: печатает CR/LF, A=LF; BC/DE/HL сохранены.
; PRINT_HEX8: A -> две цифры; AF изменены, BC/DE/HL сохранены.
; HEXDIGIT: A=0..15 -> одна цифра; AF изменены, BC/DE/HL сохранены.
; PRINT_HEX16: HL -> четыре цифры; AF изменены, BC/DE/HL сохранены.
PRINT	LD   A,(HL)	; Get character
		OR   A		; Is it $00 ?
		RET  Z		; Then RETurn on terminator
		RST  08H	; Print it
		INC  HL		; Next Character
		JR   PRINT	; Continue until $00


TXCRLF	LD   A,$0D	; 
		RST  08H	; Print character 
		LD   A,$0A	; 
		RST  08H	; Print character
		RET

;------------------------------------------------------------------------------
; Print A as two hexadecimal digits
;------------------------------------------------------------------------------
PRINT_HEX8:
        PUSH AF

        RRCA
        RRCA
        RRCA
        RRCA
        AND  $0F
        CALL HEXDIGIT

        POP  AF
        AND  $0F

HEXDIGIT:
        ADD  A,'0'
        CP   '9'+1
        JR   C,HEXOUT

        ADD  A,7

HEXOUT:
        RST  08H
        RET

;------------------------------------------------------------------------------
; Print HL as four hexadecimal digits
; HL preserved
;------------------------------------------------------------------------------
PRINT_HEX16:
        LD   A,H
        CALL PRINT_HEX8
        LD   A,L
        JP   PRINT_HEX8        ; tail call: HL уже сохраняется в PRINT_HEX8

; Исходный разбор ввода оставлен совместимым, включая permissive GETHL.
; GETHL: HL=адрес, C=1 при пустом вводе/прерывании; AF изменены.
; GET2: A=байт, E=накопитель checksum; BC/AF изменены, D/HL сохранены.
GETCHR	CALL RDCHR	; RX a Character
		CP   $03	; <ctrl-c> User break?
		RET  Z			
		CP   $20	; <space> or better?
		JR   C,GETCHR	; Do it again until we get something usable
		RET
;------------------------------------------------------------------------------
; Gets two ASCII characters from the console (assuming them to be HEX 0-9 A-F)
; Moves them into B and C, converts them into a byte value in A and updates a
; Checksum value in E
;------------------------------------------------------------------------------
GET2	CALL GETCHR	; Get us a valid character to work with
		LD   B,A	; Load it in B
		CALL GETCHR	; Get us another character
		LD   C,A	; load it in C
		CALL BCTOA	; Convert ASCII to byte
		LD   C,A	; Build the checksum
		LD   A,E
		SUB  C		; The checksum should always equal zero when checked
		LD   E,A	; Save the checksum back where it came from
		LD   A,C	; Retrieve the byte and go back
		RET
;------------------------------------------------------------------------------
; Gets four Hex characters from the console, converts them to values in HL
;------------------------------------------------------------------------------
GETHL	LD   HL,$0000	; Gets xxxx but sets Carry Flag on any Terminator
		CALL ECHO		; RX a Character
		CP   $0D		; <CR>?
		JR   NZ,GETX2	; other key		
SETCY	SCF				; Set Carry Flag
		RET             ; and Return to main program		
;------------------------------------------------------------------------------
; This routine converts last four hex characters (0-9 A-F) user types into a value in HL
; Rotates the old out and replaces with the new until the user hits a terminating character
;------------------------------------------------------------------------------
GETX	LD   HL,$0000	; CLEAR HL
GETX1	CALL ECHO	; RX a character from the console
		CP   $0D	; <CR>
		RET  Z		; quit
		CP   $2C	; <,> can be used to safely quit for multiple entries
		RET  Z		; (Like filling both DE and HL from the user)
GETX2	CP   $03	; Likewise, a <ctrl-C> will terminate clean, too, but
		JR   Z,SETCY	; It also sets the Carry Flag for testing later.
		ADD  HL,HL	; Otherwise, rotate the previous low nibble to high
		ADD  HL,HL	; rather slowly
		ADD  HL,HL	; until we get to the top
		ADD  HL,HL	; and then we can continue on.
		SUB  $30	; Convert ASCII to byte	value
		CP   $0A	; Are we in the 0-9 range?
		JR   C,GETX3	; Then we just need to sub $30, but if it is A-F
		SUB  $07	; We need to take off 7 more to get the value down to
GETX3	AND  $0F	; to the right hex value
		ADD  A,L	; Add the high nibble to the low
		LD   L,A	; Move the byte back to A
		JR   GETX1	; and go back for next character until he terminates
;------------------------------------------------------------------------------
; Convert ASCII characters in B C registers to a byte value in A
;------------------------------------------------------------------------------
BCTOA	LD   A,B	; Move the hi order byte to A
		SUB  $30	; Take it down from Ascii
		CP   $0A	; Are we in the 0-9 range here?
		JR   C,BCTOA1	; If so, get the next nybble
		SUB  $07	; But if A-F, take it down some more
BCTOA1	RLCA		; Rotate the nybble from low to high
		RLCA		; One bit at a time
		RLCA		; Until we
		RLCA		; Get there with it
		LD   B,A	; Save the converted high nybble
		LD   A,C	; Now get the low order byte
		SUB  $30	; Convert it down from Ascii
		CP   $0A	; 0-9 at this point?
		JR   C,BCTOA2	; Good enough then, but
		SUB  $07	; Take off 7 more if it's A-F
BCTOA2	ADD  A,B	; Add in the high order nybble
		RET

;------------------------------------------------------------------------------
; Get a character and echo it back to the user
;------------------------------------------------------------------------------
ECHO	CALL	RDCHR
		CALL	WRCHR
		RET

; Intel HEX: сохраняем потоковую запись DATA до проверки checksum.
; Это не транзакционный загрузчик: при ошибке уже записанные байты не откатываются.
; Вход после ':', используется RET к MAIN; AF/BC/DE/HL изменены.
; Типы 02..05 потребляются, но НЕ задают старшие разряды адреса.
LOAD:
        LD   E,0            ; checksum accumulator

        ; Record length
        CALL GET2
        LD   D,A            ; D = number of data bytes

        ; Load address high byte
        CALL GET2
        LD   H,A

        ; Load address low byte
        CALL GET2
        LD   L,A

        ; Record type
        CALL GET2

        CP   $00            ; DATA record?
        JR   Z,LOAD2

        CP   $01            ; EOF record?
        JR   Z,LOAD_EOF

        ; Any other Intel HEX record type:
        ; consume it, but DO NOT write to RAM
        JR   LOAD_SKIP

;------------------------------------------------------------------------------
; Type 00 - DATA record
; D  = number of bytes
; HL = destination address
;------------------------------------------------------------------------------

LOAD2:
        LD   A,D
        AND  A
        JR   Z,LOAD3

        CALL GET2           ; get next data byte
        LD   (HL),A         ; write it to memory
        INC  HL

        LD   A,'.'
        RST  08H

        DEC  D
        JR   LOAD2


;------------------------------------------------------------------------------
; End of DATA record - read and verify checksum
;------------------------------------------------------------------------------

LOAD3:
        CALL GET2           ; checksum byte

        LD   A,E
        AND  A
        RET  Z              ; checksum OK

        JR   LOADERR


;------------------------------------------------------------------------------
; Type 01 - End Of File
;------------------------------------------------------------------------------

LOAD_EOF:
        CALL GET2           ; checksum byte

        LD   A,E
        AND  A
        JR   Z,LOAD00       ; checksum OK, print "Load complete."

        JR   LOADERR


;------------------------------------------------------------------------------
; Unsupported Intel HEX record type
;
; Important: read all data bytes so the serial stream remains synchronized,
; but do NOT write them to memory.
;------------------------------------------------------------------------------

LOAD_SKIP:
        LD   A,D
        AND  A
        JR   Z,LOAD3


LOAD_SKIP_LOOP:
        CALL GET2           ; read byte, update checksum
                            ; but DON'T do LD (HL),A

        DEC  D
        JR   NZ,LOAD_SKIP_LOOP


        JR   LOAD3          ; общая проверка checksum DATA/SKIP

LOADERR	LD   HL,CKSUMERR  ; Get "Checksum Error" message
		CALL PRINT	; Print Message from (HL) and terminate the load
		RET

LOAD00  LD   HL,LDETXT	; Print load complete message
		CALL PRINT
		RET

; Загрузка CP/M и низкоуровневый CF-драйвер: инструкции не изменены.
; cfWait проверяет только BUSY, не DRQ/ошибки. Задержки rdByte сохранены.
CPMLOAD
    	LD HL,CPMTXT
		CALL PRINT
		CALL GETCHR
		RET Z	; Cancel if CTRL-C
		AND  $5F ; uppercase
		CP 'Y'
		JP  Z,CPMLOAD2
		RET
CPMTXT
		DB	$0D,$0A
		DB	"Boot CP/M?"
		DB	$00

CPMTXT2
		DB	$0D,$0A
		DB	"Loading CP/M..."
		DB	$0D,$0A,$00

CPMLOAD2
    	LD HL,CPMTXT2
		CALL PRINT


		CALL	cfWait
		LD 	A,CF_8BIT	; Set IDE to be 8bit
		OUT	(CF_FEATURES),A
		LD	A,CF_SET_FEAT
		OUT	(CF_COMMAND),A


		CALL	cfWait
		LD 	A,CF_NOCACHE	; No write cache
		OUT	(CF_FEATURES),A
		LD	A,CF_SET_FEAT
		OUT	(CF_COMMAND),A

		LD	B,numSecs

		LD	A,0
		LD	(secNo),A
		LD	HL,loadAddr
		LD	(dmaAddr),HL
processSectors:

		CALL	cfWait

		LD	A,(secNo)
		OUT 	(CF_LBA0),A
		LD	A,0
		OUT 	(CF_LBA1),A
		OUT 	(CF_LBA2),A
		LD	a,0E0H
		OUT 	(CF_LBA3),A
		LD 	A,1
		OUT 	(CF_SECCOUNT),A

		call	read

		LD	DE,0200H
		LD	HL,(dmaAddr)
		ADD	HL,DE
		LD	(dmaAddr),HL
		LD	A,(secNo)
		INC	A
		LD	(secNo),A

		djnz	processSectors

; Start CP/M using entry at top of BIOS
; The current active console stream ID is pushed onto the stack
; to allow the CBIOS to pick it up
; 0 = SIO A, 1 = SIO B
		
		ld	A,(primaryIO)
		PUSH	AF
		ld	HL,($FFFE)
		jp	(HL)


;------------------------------------------------------------------------------

; Read physical sector from host

read:
		PUSH 	AF
		PUSH 	BC
		PUSH 	HL

		CALL 	cfWait

		LD 	A,CF_READ_SEC
		OUT 	(CF_COMMAND),A

		CALL 	cfWait

		LD 	c,4
		LD 	HL,(dmaAddr)
rd4secs:
		LD 	b,128
rdByte:
		nop
		nop
		in 	A,(CF_DATA)
		LD 	(HL),A
		INC 	HL
		dec 	b
		JR 	NZ, rdByte
		dec 	c
		JR 	NZ,rd4secs

		POP 	HL
		POP 	BC
		POP 	AF

		RET


; Wait for disk to be ready (busy=0,ready=1)
cfWait:
		PUSH 	AF
cfWait1:
		in 	A,(CF_STATUS)
		AND 	080H
		cp 	080H
		JR	Z,cfWait1
		POP 	AF
		RET

SIGNON	DB	"Z80 SBC Boot ROM 1.2"
		DB	" by G. Searle / D. Chertkov"
		DB	$0D,$0A
; Фрагмент SIGNON: здесь НЕ должно быть NUL, иначе подсказка ниже не видна.
; Для воспроизводимой сборки дата не обновляется автоматически.
BUILD_INFO:
        DB "Build: 2026-09-12",13,10

		DB	"Type ? for options"
		DB	$0D,$0A,$00

BASTXT
		DB	$0D,$0A
		DB	"Cold or Warm ?"
		DB	$0D,$0A,$00

CKSUMERR	DB	"Checksum error"
		DB	$0D,$0A,$00

INITTXT  
		DB	$0C
		DB	"Press [SPACE] to activate console"
		DB	$0D,$0A, $00

LDETXT  
		DB	"Load complete."
		DB	$0D,$0A, $00


HLPTXT
		DB	$0D,$0A
		DB	"R           - Reset"
		DB	$0D,$0A
		DB	"BC or BW    - ROM BASIC Cold or Warm"
		DB	$0D,$0A
		DB	"X           - Boot CP/M (load $D000-$FFFF from disk)"
		DB	$0D,$0A
		DB	":nnnnnn...  - Load Intel-Hex file record"
		DB	$0D,$0A
        DB  "Mxxxx       - Memory dump"
        DB  $0D,$0A
		DB  "P           - Port test", 13, 10
		DB  "Gxxxx       - Goto address", 13, 10
		DB   $00

; Общие ANSI-данные, независимые от memview и porttest.
; Использование: LD HL,UI_CLEAR_SCREEN / CALL PRINT.
UI_CLEAR_SCREEN:
        DB ESC,"[2J",ESC,"[H",0

; MEMDUMP: вызывается JP из MAIN, RET возвращает в монитор.
; Изменяет AF/BC/DE/HL и baseaddr; дополнительных RAM-буферов нет.
; Страницы всегда выровнены по $100; память читается дважды (HEX/ASCII),
; поэтому изменяемые IRQ байты могут отличаться между двумя колонками.
; G принимает ровно 4 HEX-цифры; неизвестные символы игнорируются.
; ESC-разбор блокирующий, как в исходнике (одиночный ESC ждёт продолжения).
; =========================================================
; Z80 MEMORY VIEWER
; Встроенный модуль для sjasmplus, без собственного ORG.
;
; Commands:
;   N or SPACE - next 256 bytes
;   P          - previous 256 bytes
;   G          - goto address
;   Q          - return to Monitor
;
; Denis Chertkov, denis@chertkov.info, 20260912
; =========================================================

; ---------------------------------------------------------
; Entry point called from Monitor
; ---------------------------------------------------------
 
MEMDUMP:
        CALL GETHL
        JR NC, mv_setaddr                  ; if defined - use it, otherwise start from 0000h
        LD H,00h                        ; If not defined - start from 0000h
mv_setaddr:
        LD L,00h                        ; round the address down to the start of a 256-byte page
        LD (baseaddr),HL

mv_main_view:
        call mv_draw_page


mv_waitkey:
        rst 10h

        cp 1bh              ; ESC?
        jp z,mv_escape_key

        cp ' '
        jr z,mv_next_page

        and 5fh             ; lowercase -> uppercase

        cp 'N'
        jr z,mv_next_page

        cp 'P'
        jr z,mv_prev_page

        cp 'G'
        jr z,mv_goto_addr

        cp 'Q'
        ret z

        jr mv_waitkey


; ---------------------------------------------------------
; Next 256-byte page
; ---------------------------------------------------------

mv_next_page:
        ; baseaddr — слово RAM, младший байт всегда 0. DE больше не портится.
        ; Изменения F не наблюдаемы: следующий draw_page заново задаёт флаги.
        ld hl,(baseaddr)
        inc h               ; +$100, L=0; переход FF00 -> 0000
        ld (baseaddr),hl
        jr mv_main_view


; ---------------------------------------------------------
; Previous 256-byte page
; ---------------------------------------------------------

mv_prev_page:
        ld hl,(baseaddr)
        dec h               ; -$100, L=0; переход 0000 -> FF00
        ld (baseaddr),hl
        jr mv_main_view


; ---------------------------------------------------------
; Ask for new address
; Four HEX digits, no ENTER needed.
; ---------------------------------------------------------

mv_goto_addr:
        ; HL накапливает адрес; B — оставшиеся цифры, C — текущий nibble.
        ; Не используем GETHL: здесь ровно 4 цифры без Enter, а у GETHL
        ; другой протокол (терминатор и permissive-разбор символов).
        ld hl,mv_goto_msg
        call PRINT

        ld hl,0000h
        ld b,4


mv_goto_digit:

mv_goto_wait:
        rst 10h

        ; Сначала проверяем цифры 0..9
        cp '0'
        jr c,mv_goto_try_letter

        cp '9'+1
        jr c,mv_goto_number


mv_goto_try_letter:
        ; Теперь можно безопасно привести буквы к uppercase
        and 5fh

        cp 'A'
        jr c,mv_goto_wait

        cp 'F'+1
        jr nc,mv_goto_wait

        ; A-F -> 10..15

        rst 08h             ; conout сохраняет AF: PUSH/POP не нужны

        sub 'A'-10
        jr mv_goto_have_digit


mv_goto_number:
        rst 08h             ; conout сохраняет AF: PUSH/POP не нужны

        sub '0'


mv_goto_have_digit:
        ld c,a

        ; HL = HL * 16
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl

        ; добавить nibble
        ld a,l
        or c
        ld l,a

        djnz mv_goto_digit

        ; округлить адрес до начала 256-байтной страницы
        ld l,00h

        ; сохранить новый адрес
        ld (baseaddr),hl

        ; перерисовать страницу
        jp mv_main_view

; ---------------------------------------------------------
; Draw complete 256-byte page
; ---------------------------------------------------------

mv_draw_page:
        ; Вход: baseaddr. Выход: страница/подсказка напечатаны.
        ; AF/BC/DE/HL изменены. Стек сбалансирован на всех путях.
        ; B считает строки, C — байты; PUSH BC защищает счётчик строк.

        ; Clear screen + cursor home

        ld hl,UI_CLEAR_SCREEN
        call PRINT

        ld hl,mv_title
        call PRINT

        ; Display base address in heading

        ld hl,(baseaddr)
        call PRINT_HEX16

        ld hl,mv_title2
        call PRINT

        ; HL = first memory byte

        ld hl,(baseaddr)

        ; 16 lines

        ld b,16


mv_line_loop:
        push bc

        ; Address

        call PRINT_HEX16

        ld a,':'
        rst 08h

        ld a,' '
        rst 08h

        ; ---------------------------------------------
        ; HEX part - 16 bytes
        ; ---------------------------------------------

        ld c,16


mv_hex_loop:
        ld a,(hl)
        call PRINT_HEX8

        ld a,' '
        rst 08h

        inc hl

        dec c
        jr nz,mv_hex_loop


        ; two spaces before ASCII

        ld a,' '
        rst 08h

        ld a,' '
        rst 08h


        ; HL currently points to NEXT line.
        ; Move back 16 bytes.

        ld de,-16
        add hl,de


        ; ---------------------------------------------
        ; ASCII part
        ; ---------------------------------------------

        ld c,16


mv_ascii_loop:
        ld a,(hl)

        ; printable ASCII = 20h..7Eh

        cp 20h
        jr c,mv_not_printable

        cp 7fh
        jr nc,mv_not_printable

        jr mv_ascii_out


mv_not_printable:
        ld a,'.'


mv_ascii_out:
        rst 08h

        inc hl

        dec c
        jr nz,mv_ascii_loop


        ; CR/LF

        call TXCRLF         ; BC/DE/HL сохраняются

        pop bc

        djnz mv_line_loop


        ; command mv_help

        ld hl,mv_help
        jp PRINT            ; tail call; return к mv_main_view

; ---------------------------------------------------------
; ANSI escape sequences
;
; PgUp:   ESC [ 5 ~
; PgDown: ESC [ 6 ~
; ---------------------------------------------------------

mv_escape_key:
        ; Сохраняем исходный протокол: ESC [ A/B и ESC [ 5~/6~.
        ; Здесь нет таймера. Неполная последовательность ждёт ввод,
        ; неизвестный байт поглощается, затем возврат к ожиданию команды.
        rst 10h             ; ожидаем '['
        cp '['
        jp nz,mv_waitkey

        rst 10h

        ; стрелки
        cp 'A'              ; Up
        jp z,mv_prev_page

        cp 'B'              ; Down
        jp z,mv_next_page

        ; Page Up / Page Down

        cp '5'
        jr z,mv_escape_pgup

        cp '6'
        jr z,mv_escape_pgdown

        jp mv_waitkey


mv_escape_pgup:
        rst 10h             ; ожидаем '~'
        cp '~'
        jp nz,mv_waitkey

        jp mv_prev_page


mv_escape_pgdown:
        rst 10h             ; ожидаем '~'
        cp '~'
        jp nz,mv_waitkey

        jp mv_next_page




; Строки интерфейса; очистка экрана определена в terminal.asm.

mv_title:
        db "Z80 MEMORY VIEWER by Denis@Chertkov.info",13,10
        db "PAGE: ",0


mv_title2:
        db "h",13,10,13,10,0


mv_help:
        db 13,10
        db "N/SPACE,PgDn next page",13,10
        db "P,PgUp       previous page",13,10
        db "G            goto address",13,10
        db "Q            quit",13,10
        db 0


mv_goto_msg:
        db 13,10
        db "Address:     ",0

; PORTTEST: JP из MAIN, RET назад; изменяет AF/BC/HL, portno/value.
; R/O выполняют ровно один IN/OUT. Рисование не читает порты.
; BC=$00pp: B намеренно обнуляется — это старшие 8 бит адреса I/O.
; IRQ остаются включены. Доступ к SIO/CF/банковому регистру может
; нарушить консоль или переключить память; никаких автоматических записей.
; =========================================================
; Z80 PORT TEST
; Встроенный модуль для sjasmplus, без собственного ORG.
;
; Controls:
;   A - port --
;   D - port ++
;   S - value --
;   W - value ++
;   R - read port
;   O - output value to port
;   Q - return to monitor
;
; Grant Searle monitor services:
;   RST 08h - console output
;   RST 10h - console input
; =========================================================


PORTTEST:
        ld a,10h                                ; initial port number
        ld (portno),a

        xor a                                   ; initial value
        ld (value),a

pt_main:
        call pt_draw

pt_waitkey:
        rst 10h
        and 5fh

        cp 'Q'
        ret z

        cp 'A'
        jr z,pt_port_dec

        cp 'D'
        jr z,pt_port_inc

        cp 'S'
        jr z,pt_value_dec

        cp 'W'
        jr z,pt_value_inc

        cp 'R'
        jr z,pt_port_read

        cp 'O'
        jr z,pt_port_write

        jr pt_waitkey


pt_port_dec:
        ld hl,portno
        jr pt_decrement
pt_port_inc:
        ld hl,portno
        jr pt_increment
pt_value_dec:
        ld hl,value
pt_decrement:
        dec (hl)            ; 8-битное изменение с wrap 00 -> FF
        jr pt_main
pt_value_inc:
        ld hl,value
pt_increment:
        inc (hl)            ; 8-битное изменение с wrap FF -> 00
        jr pt_main

; ---------------------------------------------------------
; Read selected port
; ---------------------------------------------------------
pt_port_read:
        ld a,(portno)
        ld c,a
        ld b,0

        in a,(c)
        ld (value),a

        jr pt_main


; ---------------------------------------------------------
; Write VALUE to selected port
; ---------------------------------------------------------
pt_port_write:
        ld a,(portno)
        ld c,a
        ld b,0

        ld a,(value)
        out (c),a

        jr pt_main


; ---------------------------------------------------------
; Draw screen
; ---------------------------------------------------------
pt_draw:
        ld hl,UI_CLEAR_SCREEN
        call PRINT

        ld hl,pt_title
        call PRINT

        ld hl,pt_porttxt
        call PRINT

        ld a,(portno)
        call PRINT_HEX8

        ld hl,pt_valuetxt
        call PRINT

        ld a,(value)
        call PRINT_HEX8

        ld hl,pt_helptxt
        jp PRINT            ; tail call

pt_title:
        db "Z80 PORT TEST by Denis@Chertkov.info",13,10,13,10,0

pt_porttxt:
        db "PORT  : ",0

pt_valuetxt:
        db 13,10
        db "VALUE : ",0

pt_helptxt:
        db 13,10,13,10
        db "A/D  port -/+",13,10
        db "S/W  value -/+",13,10
        db "R    read port",13,10
        db "O    output value",13,10
        db "Q    return to monitor",13,10
        db 0


MONITOR_END:
; Не заполнять до $4000: BASIC уже скопирован из оригинального ROM.
        ASSERT MONITOR_END <= BASCLD
        ASSERT RST00 == $0000
        ASSERT RST08 == $0008
        ASSERT RST10 == $0010
        ASSERT RST18 == $0018
        ASSERT WORKSPACE_END <= $4100
