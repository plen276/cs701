; W2.4 — ADC -> AVG -> COR pipeline (PD slot watched by TB)
;
; Configures three ASPs in pipeline order; ReCOP halts; TB observes
; correlation Result packets arriving at recvs(4) (where PD will
; eventually sit). Demonstrates the new Conf-DP COR encoding works
; end-to-end through the cor_asp_noc adapter wrapper.
;
; Topology
;   port 0  ReCOP + recop_ni
;   port 1  adc_asp                  (FTW=0x4000, SR=11)
;   port 2  avg_asp                  (L=8)
;   port 3  cor_asp via cor_asp_noc  (window=64, interval=1, shift=6)
;   port 4  TB watcher               (will be PD-ASP later)
;
; Packets sent (in order — pipeline downstream-first, ADC last so
; data flow only starts once the chain is ready to receive it):
;
;   1. Conf-DP to AVG  : 0x9232_0000  (Dest=2, Next=3, Mode=L8)
;   2. Conf-DP to COR  : 0x9340_0008  (Dest=3, Next=4, MODE=SET_WINDOW,    value=8)
;   3. Conf-DP to COR  : 0x9342_0001  (Dest=3, Next=4, MODE=SET_INTERVAL,  value=1)
;   4. Conf-DP to COR  : 0x9343_0003  (Dest=3, Next=4, MODE=SET_SHIFT,     value=3)
;   5. Conf-DP to COR  : 0x9344_0001  (Dest=3, Next=4, MODE=SET_ENABLE,    value=1)
;   6. Conf-ADC to ADC : 0xA12E_4000  (Dest=1, Next=2, SR=11, En=1, Ch=0, FTW=0x4000)
;
; Sub-command IDs (bits 19:16 of Conf-DP) per cor_asp_pkg.vhd:
;   0000 = SET_WINDOW    0010 = SET_INTERVAL    0011 = SET_SHIFT
;   0100 = SET_ENABLE    0101 = RESET_BUF
; Every Conf-DP also latches cfg_dest <= pkt_next, so all four COR
; configs implicitly set the result destination to port 4 (Next=4).

start	; ---- Configure AVG-ASP (downstream first) ----
		LDR  R1, #0x9232
		DATACALL R1, #0x0000        ; Conf-DP AVG : Dest=2  Next=3  Mode=L8

		; ---- Configure COR-ASP (multi-parameter sequence) ----
		LDR  R1, #0x9340
		DATACALL R1, #0x0008        ; Conf-DP COR : SET_WINDOW   = 8

		LDR  R1, #0x9342
		DATACALL R1, #0x0001        ; Conf-DP COR : SET_INTERVAL = 1

		LDR  R1, #0x9343
		DATACALL R1, #0x0003        ; Conf-DP COR : SET_SHIFT    = 3

		LDR  R1, #0x9344
		DATACALL R1, #0x0001        ; Conf-DP COR : SET_ENABLE   = 1

		; ---- Configure ADC-ASP last (starts data flow) ----
		LDR  R1, #0xA12E
		DATACALL R1, #0x4000        ; Conf-ADC    : Dest=1  Next=2  SR=11  En=1  Ch=0  FTW=0x4000

halt	JMP halt
ENDPROG
END
