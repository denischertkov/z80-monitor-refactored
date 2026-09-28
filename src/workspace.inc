; RAM workspace used by the monitor (addresses only; not emitted into ROM)
serABuf         EQU $4000
serAInPtr       EQU serABuf + SER_BUFSIZE
serARdPtr       EQU serAInPtr + 2
serABufUsed     EQU serARdPtr + 2
serBBuf         EQU serABufUsed + 1
serBInPtr       EQU serBBuf + SER_BUFSIZE
serBRdPtr       EQU serBInPtr + 2
serBBufUsed     EQU serBRdPtr + 2

primaryIO       EQU serBBufUsed + 1
secNo           EQU primaryIO + 1
dmaAddr         EQU secNo + 1

stackSpace      EQU dmaAddr + 2
STACK           EQU stackSpace + 32
baseaddr        EQU STACK               ; memview base address variable (2 bytes)
portno          EQU baseaddr+2          ; porttest port number variable (1 byte)
value           EQU portno+1            ; porttest value variable (1 byte)
me_cursor       EQU value+1             ; memedit selected address (2 bytes)

; The stack grows down from STACK=$40AE; baseaddr starts just above it.
; Reserved stack: $408E..$40AD, 32 bytes. Workspace variables continue above it.
WORKSPACE_END   EQU me_cursor+2
        ASSERT STACK == $40AE
        ASSERT baseaddr == $40AE
        ASSERT portno == $40B0
        ASSERT value == $40B1
        ASSERT me_cursor == $40B2
