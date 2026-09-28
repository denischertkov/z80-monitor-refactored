; ==================================================================================
;
; Based on the original Z80 Monitor Rom by Grant Searle (http://searle.hostei.com/grant/index.html)
; Added the new memory viewer and build info string to the signon message.
; Fix Intel HEX loading for non-data record types (0000h and 0001h RAM address corruption).
; Denis Chertkov, denis@chertkov.info, 20260912
;
; ==================================================================================
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
; ==================================================================================

; Refactored for sjasmplus 1.24.0.
; Monitor only; this is not a complete ROM image containing BASIC.
; Absolute RST vectors and RAM workspace retain their original addresses.
        INCLUDE "src/config.inc"
        INCLUDE "src/workspace.inc"
        INCLUDE "src/vectors.asm"
        INCLUDE "src/serial.asm"
        INCLUDE "src/console_io.asm"
        INCLUDE "src/init.asm"
        INCLUDE "src/commands.asm"
        INCLUDE "src/console_text.asm"
        INCLUDE "src/hex_input.asm"
        INCLUDE "src/address_input.asm"
        INCLUDE "src/ihex.asm"
        INCLUDE "src/cf_boot.asm"
        INCLUDE "src/messages.asm"
        INCLUDE "src/terminal.asm"
        INCLUDE "src/memview.asm"
        INCLUDE "src/memedit.asm"
        INCLUDE "src/porttest.asm"

MONITOR_END:
; Do not pad to $4000: BASIC has already been copied from the original ROM.
        ASSERT MONITOR_END <= BASCLD
        ASSERT RST00 == $0000
        ASSERT RST08 == $0008
        ASSERT RST10 == $0010
        ASSERT RST18 == $0018
        ASSERT WORKSPACE_END <= $4100
