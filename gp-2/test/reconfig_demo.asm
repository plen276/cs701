; ============================================================
; reconfig_demo.asm  (GP-2 W6.4) -- ReCOP self-reload demo
;
; Demonstrates RUNTIME program-memory reload through the NoC reconfig
; node (port 6) and the dual-port program memory (prog_mem_dp).
;
; Sequence:
;   1. Show a BEFORE state:  HEX = 0x1111, LEDR0 on.
;   2. Wait for KEY1 (io_events bit0 at $FF1).
;   3. Stream a small program ("Program B") into PM at word address
;      0x1000 via Conf-Prog packets to the reconfig node.
;   4. JMP 0x1000. Program B shows the AFTER state: HEX = the switch
;      value captured at reload (frozen into PM code -- it ignores later
;      switch changes until the next reload), LEDR1 on -- proving the
;      words ReCOP now executes were written into PM at runtime.
;
; Why operator-chosen: a fixed value (e.g. 0x2222) could be dismissed as
; a hardcoded program. The displayed value here is read from the switches
; at reload time and baked into Program B's LDR immediate, so it cannot
; have been in the bitstream; and because it is FROZEN (Program B never
; re-reads the switches), changing SW after reload does not change HEX --
; the signature of a value compiled into program memory, not read live.
;
; Conf-Prog packet is built with the immediate-form DATACALL, which
; forms DPCR = { R1, imm }. recop_ni routes on DPCR[27:24], so an
; upper word of 0xF6xx sends to port 6 (dest=0110), type 1111:
;   R1 = 0xF610, imm = addr  -> SET_ADDR   (sub-cmd 0001)
;   R1 = 0xF620, imm = word  -> WRITE_WORD (sub-cmd 0010, auto-incr)
;
; Program B machine words (authoritative source: reconfig_payload.asm,
; ORG 0x1000). If you edit that file, re-assemble it and update the
; WRITE_WORD immediates below:
;   0x1000:4010 0x1001:<SW>   LDR R1 #<switch value>  (injected at reload)
;   0x1002:8201 0x1003:0FF3   STR R1 $0xFF3   (HEX  <- switch value)
;   0x1004:4010 0x1005:0002   LDR R1 #0x0002
;   0x1006:8201 0x1007:0FF2   STR R1 $0xFF2   (LEDR <- bit1)
;   0x1008:5800 0x1009:1008   JMP 0x1008      (spin)
; ============================================================

IO_SW   EQU 0xFF0
IO_EVT  EQU 0xFF1
IO_LED  EQU 0xFF2
IO_HEX  EQU 0xFF3

; ---- BEFORE state: HEX = 0x1111, LEDR0 ----
start   LDR R1 #0x1111
        STR R1 $IO_HEX
        LDR R1 #0x0001
        STR R1 $IO_LED

; ---- wait for KEY1 press (event bit0) ----
wait    LDR R2 $IO_EVT
        AND R2 R2 #0x0001
        SZ wait                 ; Z=1 => bit clear => keep waiting
        STR R2 $IO_EVT          ; clear the event latch

; ---- position the write pointer at 0x1000 ----
        LDR R1 #0xF610
        DATACALL R1 #0x1000     ; SET_ADDR 0x1000
        NOOP
        NOOP

; ---- stream Program B (10 words, auto-incrementing) ----
        LDR R1 #0xF620          ; WRITE_WORD command (R1 reused below)
        DATACALL R1 #0x4010
        NOOP
        NOOP
        LDR R7 $IO_SW           ; capture live switch value at reload (SW[9:0])
        DATACALL R1             ; WRITE_WORD payload = R7 -> Program B's LDR immediate
        NOOP
        NOOP
        DATACALL R1 #0x8201
        NOOP
        NOOP
        DATACALL R1 #0x0FF3
        NOOP
        NOOP
        DATACALL R1 #0x4010
        NOOP
        NOOP
        DATACALL R1 #0x0002
        NOOP
        NOOP
        DATACALL R1 #0x8201
        NOOP
        NOOP
        DATACALL R1 #0x0FF2
        NOOP
        NOOP
        DATACALL R1 #0x5800
        NOOP
        NOOP
        DATACALL R1 #0x1008
        NOOP
        NOOP

; ---- run the freshly loaded program ----
        JMP 0x1000

ENDPROG
END
