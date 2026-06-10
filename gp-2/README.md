# GP-2 — HMPSoC Power-System Frequency Monitor

DE1-SoC demo guide for the GP-2 board build. The system synthesises an
emulated grid frequency on-chip, measures it through a heterogeneous ASP
pipeline, and raises an alarm when the frequency drifts out of band.

```text
SW[3:0] -> ReCOP -> ADC-ASP -> AVG-ASP -> COR-ASP -> PD-ASP -> ReCOP -> LEDR/HEX
 (pick f)         (DDS sine)  (avg L=8)  (corr 192) (period)   (alarm + display)
```

All blocks sit on an 8-port TDMA-MIN NoC. The ReCOP runs the application in
[`test/app.asm`](test/app.asm); the board top is [`src/top_level.vhd`](src/top_level.vhd).

---

## Quick start

1. Program the board with the GP-2 bitstream (`gp-2.sof`) in Quartus 18.1.
2. Press **KEY(0)** to reset. **LEDR(0)** lights (running heartbeat).
3. The board boots in **RAW** mode: **HEX3:0** shows the latest raw ADC sample.
4. Use the controls below to drive the demo.

To rebuild the program after editing `app.asm` (from the `gp-2/` directory):

```text
python assembler/asm.py test/app.asm -o assembler/test.mif
```

Then recompile in Quartus so the updated `test.mif` is baked into the bitstream.

---

## Board controls

| Control | Function |
|---|---|
| **KEY(0)** | Reset (active-low button → active-high internal reset) |
| **KEY(1)** | Cycle operating mode **RAW ↔ MEASURE** |
| **KEY(2)** | Acknowledge / clear the alarm latch |
| **KEY(3)** | Unused (debug-step scaffolding, inert) |
| **SW[3:0]** | FTW select — emulated grid frequency (see table below) |
| **SW[5:4]** | Sample rate (00 = 8 kHz default, 01 = 16 k, 10 = 32 k, 11 = 48 k). Leave at 00 for the calibrated demo — other rates rescale the period and the alarm band no longer maps to the same Hz |
| **SW[9:6]** | Unused (old debug view/freeze, now disconnected) |

> **Switches are sampled only on (re)configuration.** The app reads `SW[3:0]`
> inside its mode-config routines, **not** in the main loop. After changing the
> switches, **press KEY(1)** to re-run a mode config and push the new frequency
> to the ADC. Changing the switch alone does nothing until you do.

## Board observables

| Indicator | Meaning |
|---|---|
| **LEDR(0)** | Running heartbeat (lit while the main loop executes) |
| **LEDR(1)** | Mode (0 = RAW, 1 = MEASURE) |
| **LEDR(2)** | MEASURE pipeline active (lights with LEDR(1)) |
| **LEDR(9:7)** | Alarm — period outside the accept band (KEY(2) clears) |
| **LEDR(6:3)** | Unused |
| **HEX3:0** | RAW: latest raw ADC sample · MEASURE: PD period count (`$FF4`) |
| **HEX5:4** | Blank |

---

## Operating modes

- **RAW** — `ADC → ReCOP`. HEX shows the raw ADC sample. No measurement, no
  alarm. Useful to confirm the ADC is alive and responding to `SW[3:0]`.
- **MEASURE** — full chain `ADC → AVG → COR → PD → ReCOP`. HEX shows the PD
  period count, and the absolute period-band alarm is active.

KEY(1) toggles between them. On entering MEASURE the alarm latch is cleared and
the full pipeline is (re)configured downstream-first.

---

## FTW switch table

`SW[3:0]` selects an emulated grid frequency from a 16-entry lookup table the
app builds at boot. The selected entry is a 16-bit **Frequency Tuning Word**
loaded into the ADC-ASP's DDS:

```text
f_out = FTW × Fs / 2^16 = FTW × 8000 / 65536   (ADC SR = 00 → Fs = 8 kHz)
```

Switch values are **not** in frequency order — 0–7 are a coarse sweep, 8–F fill
the half-Hz gaps.

| SW | Freq (Hz) | FTW | Expected | SW | Freq (Hz) | FTW | Expected |
|:--:|:--:|:--:|:--|:--:|:--:|:--:|:--|
| 0 | 47.00 | 0x0181 | 🔴 Alarm (low)  | 8 | 47.50 | 0x0185 | 🔴 Alarm (low) |
| 1 | 48.00 | 0x0189 | 🔴 Alarm (low)  | 9 | 48.50 | 0x018D | 🟢 OK |
| 2 | 49.00 | 0x0191 | 🟢 OK            | A | 49.25 | 0x0193 | 🟢 OK |
| 3 | 49.50 | 0x0195 | 🟢 OK            | B | 49.75 | 0x0197 | 🟢 OK |
| 4 | **50.00** | 0x019A | 🟢 OK (nominal) | C | 50.25 | 0x019C | 🟢 OK |
| 5 | 50.50 | 0x019E | 🟢 OK            | D | 50.75 | 0x01A0 | 🟢 OK |
| 6 | 51.00 | 0x01A2 | 🟢 OK            | E | 51.50 | 0x01A6 | 🟢 OK |
| 7 | 52.00 | 0x01AA | 🔴 Alarm (high) | F | 52.50 | 0x01AE | 🔴 Alarm (high) |

**Accept band: 48.5–51.5 Hz (inclusive).** The alarm compares the PD period
count against `PMIN = 76` and `PMAX = 83` ([app.asm](test/app.asm)): period > 83
⇒ frequency too low; period ≤ 76 ⇒ too high. **Validated on board:** all 16 SW
settings trip (or stay clear) exactly as the table shows, including the band
endpoints 48.5 Hz (SW = 9) and 51.5 Hz (SW = E), which both read in-band.

---

## Alarm behaviour

The alarm is a **latch**: once a period falls out of band it stays lit until
**KEY(2)** acknowledges it. This is intentional — a momentary excursion should
not be missed if the operator looks away.

### Why the alarm fires when you switch RAW → MEASURE

You will usually see the alarm trip immediately on the first RAW → MEASURE
transition, even at a perfectly nominal `SW = 0100` (50 Hz). **This is a
warm-up transient, not a real out-of-band frequency.** Acknowledge it with
KEY(2) and it will not return once the pipeline has settled.

The cause is a timing mismatch between the alarm warm-up guard and the real
pipeline fill time:

- Entering MEASURE configures a **cold** pipeline. AVG (window L = 8), COR
  (correlation window = 192 samples), and PD all start with empty or stale
  buffers from the previous configuration.
- At 10 MHz with the ADC at 8 kHz (1250 clk/sample), the COR window alone needs
  **192 × 1250 ≈ 240 000 cycles ≈ 24 ms** before it produces its first
  *trustworthy* correlation, and PD needs several correlations after that to
  lock onto a stable period.
- The app guards against this with two checks ([app.asm](test/app.asm)): it
  skips the alarm while the period reads 0 (`$FF4` is zero until PD's first
  packet), and it counts down a warm-up inhibit `R10 = 64` loop iterations.
- But 64 loop iterations is only **≈ 1 ms** — roughly 20× shorter than the
  ~24 ms the pipeline actually needs. So the inhibit expires while PD is still
  emitting **transient, partially-filled-window periods**. One of those bogus
  (non-zero, out-of-band) values slips through the threshold test and **latches
  the alarm**.
- Because the latch holds, that single early false reading stays lit until you
  press KEY(2) — after which the now-settled pipeline reports the true period
  and the alarm stays clear (for an in-band frequency).

**For the demo:** after switching to MEASURE, wait a moment for the pipeline to
settle, then press **KEY(2)** once to clear the warm-up alarm. From then on the
alarm reflects the real measured frequency.

**Proper fix (future work):** lengthen the warm-up inhibit so it covers the full
pipeline fill (size `R10` against the ~24 ms COR-window settle, not a fixed 64),
or gate the alarm on an explicit "pipeline settled" signal rather than a loop
count. Tracked as a follow-up; the KEY(2) workaround is sufficient for the demo.

---

## Suggested demo script

1. **Reset** — KEY(0). LEDR(0) on, RAW mode, HEX shows raw ADC samples.
2. **Show RAW responds to frequency** — change `SW[3:0]`, press KEY(1) twice
   (cycle back to RAW) to reconfigure the ADC; the raw sample stream changes.
3. **Enter MEASURE** — set `SW = 0100` (50 Hz nominal), press KEY(1). LEDR(1)
   and LEDR(2) light. HEX switches to the period count.
4. **Clear the warm-up alarm** — wait ~1 s for the pipeline to settle, press
   **KEY(2)**. Alarm clears and stays clear at 50 Hz.
5. **Trigger a real alarm (over-frequency)** — set `SW = 0111` (52 Hz), press
   KEY(1) twice to reconfigure MEASURE with the new frequency. LEDR(9:7) light.
6. **Acknowledge** — press KEY(2); alarm clears.
7. **Trigger under-frequency** — set `SW = 0000` (47 Hz), KEY(1) ×2 → alarm.
8. **Return to nominal** — `SW = 0100`, KEY(1) ×2, KEY(2) → stable, no alarm.

---

## Runtime program-memory reload (W6 reconfig demo)

> A **separate demo program** from the frequency monitor above. It uses the same
> board architecture but a different ReCOP program, so it needs its own
> `test.mif` and Quartus build (see "Switching demos" below).

Demonstrates reloading the ReCOP's program memory **at runtime** — over the NoC,
with no resynthesis — using the reconfig node on port 6 and the dual-port
program memory (`prog_mem_dp`).

The ReCOP runs a small loader ([reconfig_demo.asm](test/reconfig_demo.asm)) that:

1. Shows a **BEFORE** state: HEX = `1111`, LEDR0 on.
2. Waits for **KEY(1)**.
3. Streams a second program ("Program B",
   [reconfig_payload.asm](test/reconfig_payload.asm)) into program memory at word
   address `0x1000` as Conf-Prog packets to the reconfig node, which writes them
   through `prog_mem_dp` port B.
4. Jumps to `0x1000`. Program B shows the **AFTER** state: HEX = **the switch
   value `SW[9:0]` captured at reload**, LEDR1 on.

**Why an operator-chosen value (not a fixed `2222`):** a fixed value could be
dismissed as a hardcoded program. Instead the loader reads `SW[9:0]` at reload
time and bakes it into Program B's display instruction (sent as the `WRITE_WORD`
payload). So the displayed value **could not have been in the bitstream**, and it
is **frozen** — Program B never re-reads the switches, so moving them after reload
does *not* change HEX until you reload again. Operator-chosen yet
frozen-until-reload is the signature of code written into program memory at
runtime, not read live.

Conf-Prog packets are built with the immediate-form `DATACALL` (`DPCR = {R1, imm}`);
`recop_ni` routes on `DPCR[27:24]`, so an upper word of `0xF6xx` targets port 6:

| Command | R1 | imm | Effect |
|---|:--:|:--:|---|
| SET_ADDR | `0xF610` | addr | Set the PM write pointer to `addr` |
| WRITE_WORD | `0xF620` | word | Write `word` at the pointer, then auto-increment |

### Board steps

1. Assemble the demo, then rebuild in Quartus:

   ```text
   python assembler/asm.py test/reconfig_demo.asm -o assembler/test.mif
   ```

2. Set a recognizable pattern on **SW[9:0]** (e.g. `0x155`). Press **KEY(0)** (reset). HEX shows `1111`, LEDR0 on.
3. Press **KEY(1)**. HEX changes to **your switch value** (`0155`), LEDR1 on — Program B, written into PM at runtime, is now executing.
4. **Move the switches** (e.g. to `0x2AA`). HEX **stays** `0155` — the value is baked into the reloaded code, not read live. *(This is the step that rules out a hardcoded program.)*
5. **KEY(0)** then **KEY(1)** reloads with the new switch value (HEX → `02AA`); repeat freely.

### Switching demos

`test.mif` holds whichever program you last assembled, and it is baked into the
bitstream — so each demo is its own Quartus build:

| Demo | Assemble command (then rebuild in Quartus) |
|---|---|
| Frequency monitor (W5) | `python assembler/asm.py test/app.asm -o assembler/test.mif` |
| Reconfig reload (W6) | `python assembler/asm.py test/reconfig_demo.asm -o assembler/test.mif` |

> Sim-verified by [tb_reconfig_demo.vhd](test/tb_reconfig_demo.vhd) (T1–T4),
> exercising the full path ReCOP → NI → NoC fabric → reconfig node →
> `prog_mem_dp` port B → fetch.

---

## Heterogeneous MPSoC: Nios II reprograms ReCOP (W7)

The second processor — a **Nios II** (the *non-critical support* core) — reprograms
the ReCOP *critical part* at runtime, over the NoC. This is what makes the system a
genuine **heterogeneous** MPSoC: a reactive ReCOP and a von-Neumann Nios II, plus the
four ASPs, all on the one TDMA-MIN fabric.

**Hardware** (Platform Designer system on NoC port 5 — see [w7-nios-plan.md](docs/w7-nios-plan.md)):

- Nios II/e + JTAG-UART (console) + on-chip RAM
- a **custom ISA instruction** `confprog_build` that assembles a Conf-Prog packet in one instruction (R8)
- `noc_avalon_bridge` — an Avalon-MM ⇄ TDMA-MIN adapter (the Avalon-side analogue of `recop_ni`)
- a PIO that lets Nios hold ReCOP in reset
- **two clock domains** — Nios at 50 MHz (reliable JTAG), critical side at 10 MHz — joined only by an Avalon clock-crossing bridge (the sole CDC)

**Software** ([software/nios/nios_reconfig.c](software/nios/nios_reconfig.c)): Nios
holds ReCOP in reset, streams a small program into PM via the reconfig node (each
`WRITE_WORD` packet built by the custom instruction), then releases ReCOP. The loaded
program is a live **switch echo** (`LDR R1 $FF0 ; STR R1 $FF3 ; JMP`), so after the
reload **HEX tracks SW[9:0]**.

### Board steps

1. Program the FPGA, then load `nios_reconfig.c` onto the Nios (JTAG download).
2. On reset: HEX shows `0000` (ReCOP held); the JTAG console prints "reprogramming…".
3. ReCOP boots the loaded program → **move the switches, HEX follows them live.**

**HEX-follows-the-switches is the proof:** an *independent* processor wrote that code
into ReCOP's memory at runtime (no resynthesis), using a custom instruction — the
spec's "change of program object code of the critical part."

> Running the Nios reconfig overwrites whatever ReCOP program is baked into `test.mif`
> (Nios holds ReCOP and rewrites `PM[0]`). So for the W5 / W6 demos above, don't run
> the Nios reconfig software — load a passive Nios program, or none.

---

## Node / NoC map

| NoC port | Node | id |
|:--:|---|:--:|
| 0 | ReCOP + recop_ni | 0 |
| 1 | ADC-ASP (DDS sine source) | 1 |
| 2 | AVG-ASP (moving average) | 2 |
| 3 | COR-ASP (via cor_asp_noc) | 3 |
| 4 | PD-ASP (PeakDetector) | 4 |
| 5 | Nios II subsystem (W7 — bridge + custom instr) | 5 |
| 6 | reconfig node (W6 PM reload) | 6 |
| 7 | spare | 7 |

Reference data pipeline (configured by the ReCOP boot program):
`ADC(1) → AVG(2) → COR(3) → PD(4)`, results back to `ReCOP(0)`.
