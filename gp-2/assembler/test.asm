; ============================================================
; GP-2 HMPSoC boot / pipeline-configuration program (ReCOP)
;
; Builds the reference data pipeline by sending configuration
; packets over the TDMA-MIN NoC, in consumer-before-producer
; order, enabling the ADC source LAST (per project brief):
;
;     ADC(1) -> AVG(2) -> COR(3) -> PD(4)   [results -> ReCOP(0)]
;
; A packet is the 32-bit DPCR written by DATACALL (immediate form):
;     DPCR(31:16) = Rx register   (TYPE | DEST | NEXT | MODE ...)
;     DPCR(15:0)  = #immediate    (VALUE / FTW / params)
; recop_ni routes the packet using DPCR(27:24) = DEST nibble, so the
; upper 16 bits are loaded into a register first, then DATACALL adds
; the lower 16 bits and fires the one-shot NoC send.
;
; Node ids == NoC port numbers:  ReCOP 0, ADC 1, AVG 2, COR 3, PD 4.
; The trailing NOOPs give the NoC interface FIFO time to drain a sent
; packet before the next one is queued (defensive timing margin).
; ============================================================

start   NOOP                  ; settle one cycle out of reset

; ---- PD-ASP (id 4): detection params, output dest = ReCOP(0) ----
;   upper 0xC400 = 1100(Conf-PD) 0100(dest=PD) 0000(Next=ReCOP) 0000(En=0)
;   lower 0x074A = adj_rate 2^7, hysteresis 10, lifetime 2^10
;   En is kept 0: PD ingests data but does NOT drive the NoC yet
;   (its result-send framing needs PD-side alignment first). To turn
;   PD output on once aligned, change the upper word to 0xC402.
        LDR R1, #0xC400
        DATACALL R1 #0x074A
        NOOP
        NOOP

; ---- COR-ASP (id 3): window = 64, output dest = PD(4), then enable
;   0x9340 = 1001(Conf-DP) 0011(dest=COR) 0100(Next=PD) 0000(SET_WINDOW)
        LDR R1, #0x9340
        DATACALL R1 #0x0040   ; correlation window = 64 samples
        NOOP
        NOOP
;   0x9344 = 1001(Conf-DP) 0011(dest=COR) 0100(Next=PD) 0100(SET_ENABLE)
        LDR R1, #0x9344
        DATACALL R1 #0x0001   ; enable = 1
        NOOP
        NOOP

; ---- AVG-ASP (id 2): L=8 moving average, output dest = COR(3) ----
;   0x9232 = 1001(Conf-DP) 0010(dest=AVG) 0011(Next=COR) 0010(Mode=L8)
        LDR R1, #0x9232
        DATACALL R1 #0x0000
        NOOP
        NOOP

; ---- ADC-ASP (id 1): enable LAST, ch0 output dest = AVG(2) -------
;   0xA12E = 1010(Conf-ADC) 0001(dest=ADC) 0010(Next=AVG)
;            11(SR=48 kHz) 1(En) 0(Ch0)
;   FTW 0x0044 (=68) -> ~49.8 Hz tone at the 48 kHz sample rate
        LDR R1, #0xA12E
        DATACALL R1 #0x0044
        NOOP
        NOOP

; ---- Idle loop: mirror any packet returned to ReCOP onto SOP -----
; SIP holds the low 16 bits of the last packet delivered to port 0
; (PD results, once PD output is enabled). Shown on HEX3..0 when
; SW(1) = '1'.
poll    LSIP R2
        SSOP R2
        JMP poll

ENDPROG
END
