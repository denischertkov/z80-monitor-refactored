; Shared ANSI data, independent of memview and porttest.
; Usage: LD HL,UI_CLEAR_SCREEN / CALL PRINT.
UI_CLEAR_SCREEN:
        DB ESC,"[2J",ESC,"[H",0
