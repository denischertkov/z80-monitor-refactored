; Command-line character filtering; the viewer uses raw RST services.
RDCHR           RST 10H
        CP LF
        JR Z,RDCHR                      ; Ignore LF
        CP ESC
        JR NZ,RDCHR1
        LD A,CTRLC                      ; Change ESC to CTRL-C
RDCHR1          RET

WRCHR           CP CR
        JR Z,WRCRLF                     ; When CR, write CRLF
        CP CLS
        JR Z,WR                         ; Allow write of "CLS"
        CP ' '                          ; Don't write out any other control codes
        JR C,NOWR                       ; ie. < space
WR              RST 08H
NOWR            RET

WRCRLF          LD A,CR
        RST 08H
        LD A,LF
        RST 08H
        LD A,CR
        RET
