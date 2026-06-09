; ============================================================
; reconfig_payload.asm  (GP-2 W6.4)  -- "Program B"
;
; The program the reconfig demo loads into program memory AT RUNTIME
; (word address 0x1000) through the NoC reconfig node (port 6).
;
; This file is the authoritative source for Program B. Assemble it to
; read off the 10 machine words; reconfig_demo.asm streams those words
; as WRITE_WORD payloads, then jumps to 0x1000 to run them.
;
;   python assembler/asm.py test/reconfig_payload.asm -o /tmp/payload.mif
;
; Program B shows the AFTER state (HEX = the switch value the loader
; injects at reload, LEDR1), distinct from the loader's BEFORE state
; (HEX = 0x1111, LEDR0), proving the executed words were written into PM
; at runtime. This template uses 0x0000 as a placeholder for that
; immediate (word 0x1001); reconfig_demo.asm overwrites it with the live
; switch value via a WRITE_WORD whose payload comes from $FF0.
; ============================================================

        ORG 0x1000
pb      LDR R1 #0x0000     ; placeholder -- loader overwrites with live switch value
        STR R1 $0xFF3       ; IO_HEX <- switch value
        LDR R1 #0x0002
        STR R1 $0xFF2       ; IO_LED <- bit1 (LEDR1)
pbspin  JMP pbspin         ; hold (spin in place)
        END
