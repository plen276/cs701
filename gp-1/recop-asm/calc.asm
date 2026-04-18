; ============================================================
; GP1 Calculator  -  add/sub of single decimal digits (0-9)
;
; Buttons (active-high inside CPU, inverted in recop_top):
;   KEY0 = reset (handled by hardware)
;   KEY1 = '+'
;   KEY2 = '-'
;   KEY3 = '='
;
; Switches SW[9:0] = digits 0..9 (one-hot).  If more than one
; switch is on when a key is pressed the sample is ignored and
; LEDR[9:0] flashes as a warning.
;
; Displays:
;   HEX0 = operand A
;   HEX5 = operand B
;   HEX3 = result tens digit OR '-' (code 10) OR blank (15)
;   HEX2 = result ones digit (0..9) OR blank
;
; MMIO (decimal, 12-bit physical address, decoded with opr[11:8]=F):
;   HEX0 = 3840   ( 0xF00 )
;   HEX1 = 3841
;   HEX2 = 3842
;   HEX3 = 3843
;   HEX4 = 3844
;   HEX5 = 3845
;   LEDR = 3856   ( 0xF10 )
;   SW   = 3872   ( 0xF20 )  - read only
;   KEY  = 3873   ( 0xF21 )  - read only, bit i = NOT KEY(i)
;
; Register usage:
;   R0  - always 0 (reset init, never written)
;   R1,R2,R7 - scratch
;   R3  - operator state: 0=none, 1=+, 2=-
;   R4  - operand A (0..9)
;   R5  - operand B (0..9)
;   R6  - result    (-9..18)
; ============================================================

start	NOOP
	LDR R3 #0
	LDR R7 #15			; blank code
	STR R7 $3840			; HEX0 blank
	STR R7 $3842			; HEX2 blank
	STR R7 $3843			; HEX3 blank
	STR R7 $3845			; HEX5 blank
	LDR R7 #0
	STR R7 $3856			; LEDR off

; ---------- wait for a key to be pressed ----------
main	LDR R1 $3873
	AND R1 R1 #14			; mask KEY[3:1]
	SZ main

	; dispatch on which key
	AND R2 R1 #2
	SUB R2 #2
	SZ kplus
	AND R2 R1 #4
	SUB R2 #4
	SZ kminus
	AND R2 R1 #8
	SUB R2 #8
	SZ kequal
	JMP wrel			; nothing matched (shouldn't happen)

kplus	LDR R3 #1
	JMP capa
kminus	LDR R3 #2
	JMP capa
kequal	SUB R3 #0
	SZ wrel				; no operator set -> ignore
	JMP capb

; ---------- capture operand A (after + or -) ----------
capa	LDR R1 $3872			; SW
	AND R1 R1 #1023
	SZ inva				; all-off -> invalid
	ADD R2 R1 #0			; R2 = R1
	SUBV R2 R2 #1			; R2 = R1 - 1
	AND R2 R2 R1			; (R1-1) & R1  == 0 iff popcount==1
	SZ deca
	JMP inva

deca	LDR R4 #0
	SUB R1 #1
	SZ gota
	LDR R4 #1
	SUB R1 #2
	SZ gota
	LDR R4 #2
	SUB R1 #4
	SZ gota
	LDR R4 #3
	SUB R1 #8
	SZ gota
	LDR R4 #4
	SUB R1 #16
	SZ gota
	LDR R4 #5
	SUB R1 #32
	SZ gota
	LDR R4 #6
	SUB R1 #64
	SZ gota
	LDR R4 #7
	SUB R1 #128
	SZ gota
	LDR R4 #8
	SUB R1 #256
	SZ gota
	LDR R4 #9
	SUB R1 #512
	SZ gota
	JMP inva

gota	STR R4 $3840			; HEX0 = A
	JMP wrel

; ---------- capture operand B (after =), compute, display ----------
capb	LDR R1 $3872
	AND R1 R1 #1023
	SZ inva
	ADD R2 R1 #0
	SUBV R2 R2 #1
	AND R2 R2 R1
	SZ decb
	JMP inva

decb	LDR R5 #0
	SUB R1 #1
	SZ gotb
	LDR R5 #1
	SUB R1 #2
	SZ gotb
	LDR R5 #2
	SUB R1 #4
	SZ gotb
	LDR R5 #3
	SUB R1 #8
	SZ gotb
	LDR R5 #4
	SUB R1 #16
	SZ gotb
	LDR R5 #5
	SUB R1 #32
	SZ gotb
	LDR R5 #6
	SUB R1 #64
	SZ gotb
	LDR R5 #7
	SUB R1 #128
	SZ gotb
	LDR R5 #8
	SUB R1 #256
	SZ gotb
	LDR R5 #9
	SUB R1 #512
	SZ gotb
	JMP inva

gotb	STR R5 $3845			; HEX5 = B
	SUB R3 #1
	SZ adop				; op=1 -> add
	; op=2: subtract
	ADD R6 R4 #0			; R6 = A
	SUBV R6 R6 R5			; R6 = A - B
	JMP disp

adop	ADD R6 R4 #0
	ADD R6 R6 R5			; R6 = A + B

; ---------- display R6 (-9..18) on HEX3:HEX2 ----------
disp	AND R2 R6 #32768		; test sign bit
	SZ pos				; not set -> non-negative
	; negative: show '-' and |R6|
	LDR R7 #0
	SUBV R7 R7 R6			; R7 = -R6
	STR R7 $3842			; HEX2 = |R6|
	LDR R7 #10			; '-' code
	STR R7 $3843			; HEX3 = '-'
	LDR R3 #0
	JMP wrel

pos	ADD R7 R6 #0
	SUBV R7 R7 #10			; R7 = R6 - 10
	AND R2 R7 #32768
	SZ tens				; Z means no underflow -> R6 >= 10
	; 0..9
	STR R6 $3842
	LDR R7 #15
	STR R7 $3843
	LDR R3 #0
	JMP wrel

tens	STR R7 $3842			; ones digit = R6 - 10
	LDR R7 #1
	STR R7 $3843			; tens digit
	LDR R3 #0
	JMP wrel

; ---------- invalid input -> flash LEDR (about 0.4 s) ----------
inva	LDR R1 #1023
	STR R1 $3856			; LEDR all on
	LDR R2 #20			; outer counter
outer	LDR R7 #60000			; inner counter
flsh	SUBV R7 R7 #1
	SZ inndn
	JMP flsh
inndn	SUBV R2 R2 #1
	SZ flof
	JMP outer
flof	LDR R1 #0
	STR R1 $3856
	JMP wrel

; ---------- wait until every key is released ----------
wrel	LDR R1 $3873
	AND R1 R1 #14
	SZ main				; no key held -> restart main loop
	JMP wrel

ENDPROG
END
