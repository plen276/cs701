; W2.4 — Full ADC -> AVG -> COR -> PD -> ReCOP pipeline
;
; All four ASPs configured downstream-first. PD enabled (En=1)
; and routes results back to ReCOP(0).
;
; Topology:
;   port 0  ReCOP + recop_ni
;   port 1  adc_asp                  (FTW=0x0044, SR=48 kHz)
;   port 2  avg_asp                  (L=8)
;   port 3  cor_asp via cor_asp_noc  (window=8, interval=1, shift=3)
;   port 4  PeakDetector
;
; Packets (downstream-first so each stage is ready before its source):
;   1. 0x9402_074A  Conf-DP  PD  : Dest=4, Next=ReCOP(0), En=1, adj/hyst/lifetime
;   2. 0x9340_0008  Conf-DP  COR : Dest=3, Next=PD(4),    SET_WINDOW=8
;   3. 0x9342_0001  Conf-DP  COR : Dest=3, Next=PD(4),    SET_INTERVAL=1
;   4. 0x9343_0003  Conf-DP  COR : Dest=3, Next=PD(4),    SET_SHIFT=3
;   5. 0x9344_0001  Conf-DP  COR : Dest=3, Next=PD(4),    SET_ENABLE=1
;   6. 0x9232_0000  Conf-DP  AVG : Dest=2, Next=COR(3),   Mode=L8
;   7. 0xA12E_0044  Conf-ADC ADC : Dest=1, Next=AVG(2),   SR=48kHz En=1 Ch=0
;
; Encoding of PD Conf-DP upper word 0x9402:
;   1001 = Conf-DP, 0100 = Dest=PD(4), 0000 = Next=ReCOP(0),
;   0010 = MODE with bit17=1 -> En=1

start   NOOP

; ---- PD-ASP ----
        LDR R1, #0x9402
        DATACALL R1, #0x074A    ; adj_rate=2^7, hysteresis=10, lifetime=2^10
        NOOP
        NOOP

; ---- COR-ASP ----
        LDR R1, #0x9340
        DATACALL R1, #0x0008    ; SET_WINDOW   = 8
        NOOP
        NOOP
        LDR R1, #0x9342
        DATACALL R1, #0x0001    ; SET_INTERVAL = 1
        NOOP
        NOOP
        LDR R1, #0x9343
        DATACALL R1, #0x0003    ; SET_SHIFT    = 3
        NOOP
        NOOP
        LDR R1, #0x9344
        DATACALL R1, #0x0001    ; SET_ENABLE   = 1
        NOOP
        NOOP

; ---- AVG-ASP ----
        LDR R1, #0x9232
        DATACALL R1, #0x0000    ; L=8, Next=COR(3)
        NOOP
        NOOP

; ---- ADC-ASP (last — starts data flow) ----
        LDR R1, #0xA12E
        DATACALL R1, #0x0044    ; SR=48kHz, En=1, Ch=0, FTW=68
        NOOP
        NOOP

poll    LSIP R2
        SSOP R2
        JMP poll

ENDPROG
END
