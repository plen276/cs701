; ============================================================
; GP-2 W5 application program (ReCOP)  -- v1 (approach 2a)
;
; Power-system frequency monitor with two operator modes and a
; reactive alarm overlay, driven entirely from the board via the
; new memory-mapped I/O page (see datapath.vhd):
;
;   $FF0  IO_SW      (read)  {6'b0, SW[9:0]}
;   $FF1  IO_EVENTS  (read)  bit0=KEY1 (mode), bit1=KEY2 (ack)
;   $FF1  IO_EVENTS  (write) clears the KEY event latch
;   $FF2  IO_LED     (write) LEDR drive
;   $FF3  IO_HEX     (write) HEX3:0 numeric display
;
; Modes (cycled by KEY1):
;   RAW      ADC -> ReCOP            HEX = raw ADC sample
;   MEASURE  ADC->AVG->COR->PD->ReCOP HEX = PD value (period count*)
;            + absolute period-band alarm (latched, KEY2 acknowledges)
;
;   *v1/2a note: SIP only carries the low 16 bits, so PD's max/min/
;    period sub-tag is not visible yet; HEX shows whatever PD sends.
;    Isolating the period is the 2b follow-up (small NI change).
;
; Compare technique: ReCOP has only a Z (equality) flag, so the
; magnitude tests use the MAX instruction:
;   period > PMAX :  MAX Rn #PMAX ; SUB Rn #PMAX ; Z=0 => above
;   period<= PMIN :  MAX Rn #PMIN ; SUB Rn #PMIN ; Z=1 => at/below
; Each compare is kept immediately before its SZ so Z survives.
;
; FTW (emulated grid frequency) is selected by SW[3:0] through a
; small lookup table initialised at boot. Switches choose a grid-
; frequency scenario; ReCOP translates that scenario into ADC FTW.
;
; Registers: R8 = mode (0=RAW,1=MEASURE), R9 = alarm latch (0/1)
;            R10 = alarm warm-up inhibit counter after MEASURE config
;            R1..R6 scratch, R7 = DATACALL lower-16 (register form)
; ============================================================

IO_SW   EQU 0xFF0
IO_EVT  EQU 0xFF1
IO_LED  EQU 0xFF2
IO_HEX  EQU 0xFF3
IO_PER  EQU 0xFF4        ; isolated PD period (2b)

; FTW table in data memory. Values assume ADC SR=00 (8 kHz):
;   FTW = round(f_hz * 65536 / 8000)
; SW[3:0] selects scenarios spanning low-fault, nominal, high-fault.
FTW_0   EQU 0x010       ; 47.00 Hz -> 0x0181
FTW_1   EQU 0x011       ; 48.00 Hz -> 0x0189
FTW_2   EQU 0x012       ; 49.00 Hz -> 0x0191
FTW_3   EQU 0x013       ; 49.50 Hz -> 0x0195
FTW_4   EQU 0x014       ; 50.00 Hz -> 0x019A
FTW_5   EQU 0x015       ; 50.50 Hz -> 0x019E
FTW_6   EQU 0x016       ; 51.00 Hz -> 0x01A2
FTW_7   EQU 0x017       ; 52.00 Hz -> 0x01AA
FTW_8   EQU 0x018       ; 47.50 Hz -> 0x0185
FTW_9   EQU 0x019       ; 48.50 Hz -> 0x018D
FTW_A   EQU 0x01A       ; 49.25 Hz -> 0x0193
FTW_B   EQU 0x01B       ; 49.75 Hz -> 0x0197
FTW_C   EQU 0x01C       ; 50.25 Hz -> 0x019C
FTW_D   EQU 0x01D       ; 50.75 Hz -> 0x01A0
FTW_E   EQU 0x01E       ; 51.50 Hz -> 0x01A6
FTW_F   EQU 0x01F       ; 52.50 Hz -> 0x01AE

; Period-band thresholds. PD now reports peak_time in CORRELATION SAMPLES
; (clock-independent), so for signed COR at 8 kHz the period ~= Fs/(2*f):
;   47 Hz -> 85,  49 Hz -> 82,  50 Hz -> 80,  51 Hz -> 78,  52 Hz -> 76
; Band below picks an acceptance window of ~48.5..51.5 Hz; retune on board.
PMIN    EQU 0x004C      ; period <= 76 (~>= 52 Hz) => frequency too high
PMAX    EQU 0x0053      ; period >  83 (~<= 48.5 Hz) => frequency too low

; ---- boot: alarm clear, then fall into RAW configuration ----
start   LDR R9 #0x0000
        LDR R10 #0x0000
        ; initialise FTW lookup table in data memory
        LDR R1 #0x0181
        STR R1 $FTW_0
        LDR R1 #0x0189
        STR R1 $FTW_1
        LDR R1 #0x0191
        STR R1 $FTW_2
        LDR R1 #0x0195
        STR R1 $FTW_3
        LDR R1 #0x019A
        STR R1 $FTW_4
        LDR R1 #0x019E
        STR R1 $FTW_5
        LDR R1 #0x01A2
        STR R1 $FTW_6
        LDR R1 #0x01AA
        STR R1 $FTW_7
        LDR R1 #0x0185
        STR R1 $FTW_8
        LDR R1 #0x018D
        STR R1 $FTW_9
        LDR R1 #0x0193
        STR R1 $FTW_A
        LDR R1 #0x0197
        STR R1 $FTW_B
        LDR R1 #0x019C
        STR R1 $FTW_C
        LDR R1 #0x01A0
        STR R1 $FTW_D
        LDR R1 #0x01A6
        STR R1 $FTW_E
        LDR R1 #0x01AE
        STR R1 $FTW_F

; ============ configure RAW pipeline (ADC -> ReCOP) ============
to_raw  LDR R8 #0x0000          ; mode = RAW
        LDR R9 #0x0000          ; clear alarm latch on mode change
        LDR R10 #0x0000         ; no alarm warm-up in RAW
        ; disable PD output so it does not also drive ReCOP(0)
        LDR R1 #0x9400
        DATACALL R1 #0x074A
        NOOP
        NOOP
        ; FTW from SW[3:0] scenario lookup table
        LDR R7 $IO_SW
        AND R7 R7 #0x000F
        OR  R7 R7 #0x0010
        LDR R7 R7
        ; ADC: type A, dest=1, next=0 (ReCOP), SR=00 (8 kHz), En=1, Ch0
        LDR R1 #0xA102
        DATACALL R1             ; register form: DPCR = R1 | R7(FTW)
        NOOP
        NOOP
        JMP loop

; ========== configure MEASURE pipeline (full chain) ==========
to_meas LDR R8 #0x0001          ; mode = MEASURE
        LDR R9 #0x0000          ; clear alarm latch on mode change
        LDR R10 #0x0040         ; inhibit alarm while PD/COR settle
        ; PD: enable, output -> ReCOP(0)
        LDR R1 #0x9402
        DATACALL R1 #0x074A
        NOOP
        NOOP
        ; COR: window=192, interval=1, shift=22, enable ; output -> PD(4)
        ; At ADC SR=00 (8 kHz), a 50 Hz signal is ~160 samples/cycle.
        ; Signed COR peaks are spaced around T/2, so a 192-sample window
        ; covers the 48..52 Hz band with margin. shift=22 keeps the larger
        ; signed correlation peak inside the 16-bit result.
        LDR R1 #0x9340
        DATACALL R1 #0x00C0
        NOOP
        NOOP
        LDR R1 #0x9342
        DATACALL R1 #0x0001
        NOOP
        NOOP
        LDR R1 #0x9343
        DATACALL R1 #0x0016
        NOOP
        NOOP
        LDR R1 #0x9344
        DATACALL R1 #0x0001
        NOOP
        NOOP
        ; AVG: L=8, output -> COR(3)
        LDR R1 #0x9232
        DATACALL R1 #0x0000
        NOOP
        NOOP
        ; FTW from SW[3:0] scenario lookup table
        LDR R7 $IO_SW
        AND R7 R7 #0x000F
        OR  R7 R7 #0x0010
        LDR R7 R7
        ; ADC: type A, dest=1, next=2 (AVG), SR=00 (8 kHz), En=1, Ch0
        LDR R1 #0xA122
        DATACALL R1             ; register form: DPCR = R1 | R7(FTW)
        NOOP
        NOOP
        JMP loop

; ===================== main loop =====================
loop    LDR R2 $IO_EVT          ; R2 = KEY event flags

        ; --- KEY1: cycle mode ---
        AND R3 R2 #0x0001
        SZ no_mode              ; Z=1 => bit clear => no mode press
        STR R2 $IO_EVT          ; clear event latch
        SUB R8 #0x0000          ; Z=1 if currently RAW
        SZ go_meas
        JMP to_raw             ; was MEASURE -> RAW
go_meas JMP to_meas            ; was RAW     -> MEASURE

no_mode ; --- KEY2: acknowledge alarm ---
        AND R3 R2 #0x0002
        SZ no_ack
        STR R2 $IO_EVT          ; clear event latch
        LDR R9 #0x0000          ; clear alarm latch
no_ack

        ; --- read value: period ($FF4) in MEASURE, ADC sample (LSIP) in RAW ---
        SUB R8 #0x0001          ; Z=1 if MEASURE
        SZ rd_meas
        LSIP R4                 ; RAW: latest ADC sample
        JMP rd_done
rd_meas LDR R4 $IO_PER          ; MEASURE: isolated period count
rd_done STR R4 $IO_HEX

        ; --- threshold test only in MEASURE ---
        SUB R8 #0x0001          ; Z=1 if MEASURE
        SZ chk_warm            ; MEASURE -> warm-up guard then thresholds
        JMP show_leds          ; RAW: no alarm logic

        ; $FF4 is zero until the first PD period packet arrives. Do not
        ; latch a false high-frequency alarm during MEASURE warm-up.
chk_warm SUB R4 #0x0000
        SZ show_leds

        ; Ignore the first settled-looking values after a MEASURE
        ; reconfiguration. PD/COR can emit transient or stale periods while
        ; their internal windows/baselines refill; without this, every
        ; RAW->MEASURE transition can latch a startup alarm.
        SUB R10 #0x0000
        SZ chk_max
        SUBV R10 R10 #0x0001
        JMP show_leds

chk_max ; alarm if period > PMAX (frequency too low)
        LDR R5 #0x0000
        ADD R5 R5 R4           ; R5 = period
        MAX R5 #PMAX
        SUB R5 #PMAX           ; Z=0 => period > PMAX
        SZ chk_min
        LDR R9 #0x0001         ; set alarm
        JMP show_leds

chk_min ; alarm if period <= PMIN (frequency too high)
        LDR R6 #0x0000
        ADD R6 R6 R4           ; R6 = period
        MAX R6 #PMIN
        SUB R6 #PMIN           ; Z=1 => period <= PMIN
        SZ set_min
        JMP show_leds          ; in range: leave latch unchanged (KEY2 acks)
set_min LDR R9 #0x0001         ; set alarm

        ; --- build LED word: bit0 run, bit1 mode, bit2 locked, 9:7 alarm ---
show_leds
        LDR R2 #0x0001         ; running
        SUB R8 #0x0001          ; Z=1 if MEASURE
        SZ led_meas
        JMP led_alarm
led_meas
        OR R2 R2 #0x0006      ; set mode (bit1) + locked (bit2)
led_alarm
        SUB R9 #0x0000          ; Z=1 if no alarm
        SZ led_write
        OR R2 R2 #0x0380      ; alarm bits LEDR9:7
led_write
        STR R2 $IO_LED
        JMP loop

ENDPROG
END
