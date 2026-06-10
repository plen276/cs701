# Presentation Talking Points — IP + GP-2

**Author:** Pulasthi Lenaduwa
**Format:** ~3–4 min personal slot (IP results + GP-2 contribution) + a separate ~3–4 min group HMPSoC demo.
**How to use this:** these are *speaking* notes, not a script — say it in your own words. Technical terms have a short **[what it means]** note so you can explain them if asked. "📊 SHOW" lines tell you which diagram or waveform to put on screen at that moment.

---

## Quick term glossary (skim once before you go in)

- **ASP** — Application-Specific Processor. A small piece of custom hardware that does *one* job very well (here: generate a signal, or filter a signal), instead of running software on a general CPU.
- **HMPSoC** — Heterogeneous Multiprocessor System-on-Chip. One chip with several *different* kinds of processor on it (our ReCOP, the Nios II CPU, and the ASPs) all working together.
- **NoC (TDMA-MIN)** — Network-on-Chip. The on-chip "postal system" that carries 32-bit packets between the processors. TDMA-MIN = each node gets a fixed time slot to send, so timing is predictable.
- **Packet** — one 32-bit message sent over the NoC. The top 4 bits say what *type* it is (data vs config).
- **RTL** — Register Transfer Level. The level of detail we describe hardware at — registers and the logic between them.
- **FPGA / Cyclone V** — the reprogrammable chip on the DE1-SoC board our design runs on.

---

# PART A — Your personal slot (~3–4 min)

> Split roughly: **~2 min IP**, **~1 min GP-2 contribution**, ~30s buffer for a question.
> The examiners want to hear the *design decisions and the results*, not a feature list.

## A1. Opening line (sets the frame) — 15s

> "My individual project was two ASPs that sit at the **front of the frequency-measurement pipeline**: the **ADC-ASP** that produces the signal, and the **AVG-ASP** that cleans it up. Both plug straight into the team's Network-on-Chip."

📊 SHOW: the pipeline arrow `ADC → AVG → COR → PD → ReCOP` (draw it or use a slide). Point to your two boxes.

---

## A2. ADC-ASP — "I make a fake power-grid signal" — ~45s

**Plain version:**
> "Instead of wiring a real sensor to the board, the ADC-ASP *generates* a power-system sine wave internally, so the whole team can test against a known signal."

**The one clever bit to emphasise — DDS:**
> "It uses a technique called **DDS** to build the sine."

- **[DDS = Direct Digital Synthesis]** — a counter (the "phase accumulator") that ticks forward by a programmable step every sample; the step size sets the frequency. The counter's value indexes a stored sine-wave table.
- **[LUT = Look-Up Table]** — a table of pre-computed sine values stored in chip memory (a ROM). We read from it instead of calculating sine live.

**The headline result — say this number:**
> "The output frequency is `f = FTW × Fs / 2¹⁶`. That means I can **retune the emulated grid frequency at runtime** just by sending one 16-bit number — no recompiling the chip. That's exactly what lets us emulate 49, 50, 51 Hz grid deviations on demand."

- **[FTW = Frequency Tuning Word]** — the 16-bit "step size" number sent in a config packet. Bigger FTW = higher frequency.

**Round it off:** dual-channel; the sine table is built automatically when the chip is compiled (no external file needed).

📊 SHOW: **`adc_asp_datapath.png`** (Fig: DDS datapath) while you explain — then **`tb_adc_waveform.png`** to *prove* it: "here's the generated sine, and here it changes frequency live when I send a new FTW."

---

## A3. AVG-ASP — "I smooth the signal cheaply" — ~45s

**Plain version:**
> "The AVG-ASP is a **moving-average filter** — it averages the last few samples to smooth out noise. The window size L can be 4, 8, or 16 samples."

**The clever bit — why it's cheap in hardware:**
> "The obvious way to average L numbers is to add them all up every time — that needs more and more adders as L grows. I used a **running sum** instead: each new sample, I *add the new value and subtract the one leaving the window*. One add, one subtract — **no matter how big L is**."

- **[running sum]** — keep a running total; update it incrementally instead of re-adding everything. Cost stays constant.
- **[right-shift instead of divide]** — to divide by 4/8/16 (powers of two) I just shift the bits right, which is almost free in hardware. A real divider is large and slow, and the rules said no divider — so this was both required and efficient.

**The boundary decision (the brief specifically asks for this):**
> "At startup the window isn't full yet, so I hold the output during a **WARMUP** phase until L real samples have arrived. That avoids dividing by a partial, non-power-of-two count."

- **[WARMUP]** — the first L−1 samples produce no output; we wait until the window is genuinely full.

📊 SHOW: **`avg_datapath.png`** (running-sum datapath) while explaining — then **`tb_avg_asp_waveform.png`** to prove it: "input samples, the smoothed output, and you can see the WARMUP gap before valid output."

---

## A4. "How do I know it works?" — verification — ~30s

This is where you earn marks. Say the phrase **"self-checking testbench."**

> "My AVG testbench is **self-checking** — it runs the same data through a simple reference model written in C and automatically confirms the hardware gives the exact same answer, for every window size, both channels, and bypass mode."

- **[self-checking testbench]** — the test compares hardware output to a known-correct model and flags any mismatch by itself; I don't eyeball it.
- **[reference model]** — a plain, obviously-correct version (in C) used as the "ground truth" to check the hardware against.

> "And the **pipeline testbed** runs ADC → AVG end-to-end over the real NoC, so you can see the sine going in and the smoothed version coming out."

📊 SHOW: **`testbed_pipeline.png`** — pre-filter and post-filter sine, with the averaging visibly smoothing it.

---

## A5. Resources & speed (the brief requires this) — ~20s

> "Both ASPs are small and fast. The AVG filter is mostly registers because the sliding window is stored in flip-flops; the ADC is more logic because of the dual-channel DDS. Neither has a multiplier or divider, so both clear the 50 MHz board clock comfortably."

📊 SHOW: resource table.

- ADC-ASP: **537 ALMs, 216 registers** (measured).
- AVG-ASP: **268 ALMs, 594 registers** (measured).
- **[ALM = Adaptive Logic Module]** — the basic building block of logic on the Cyclone V FPGA; fewer = smaller design.

> ⚠️ **GAP TO CLOSE BEFORE THE PRESENTATION:** M10K memory blocks, DSP blocks, and **Fmax (max clock speed)** are still marked TBD in `report/resources.md`. These are *required deliverables* and a near-certain question. If you can, run a standalone Quartus compile of each ASP and fill them in (procedure is in `resources.md §1`). If asked and you don't have the number: *"both are well under the 50 MHz board clock with no multiplier or divider in the critical path"* is a defensible holding answer — but get the real Fmax if you can.

---

## A6. Your GP-2 contribution — ~45–60s

> "In GP-2, my two ASPs became the **live front-end of the frequency monitor**. On top of that I wrote the **ReCOP application** — the program that configures the whole pipeline and drives it from the board: it sends the config packets that tell each ASP what to do, picks the emulated grid frequency from the switches, and raises an alarm when the frequency drifts out of band."

- **[ReCOP]** — the small custom processor in our system that acts as the "conductor", sending config packets to set up the ASP pipeline.
- **[config packet]** — a NoC message that programs an ASP (e.g. "ADC, run at this frequency and send your output to the AVG").

> ⚠️ **Honesty check:** only claim the ReCOP app (`app.asm`) as fully yours if it was. If a teammate co-wrote it, say *"I contributed the ADC/AVG configuration parts of the ReCOP app"* and scale the claim to match.

Then hand over to the group demo.

---

# PART B — Group HMPSoC demo (~3–4 min)

> Run these as **capability demos**, not a code walkthrough. Talk to the *board*, not the assembly. Keep your eyes on HEX/LEDs and narrate what the audience sees. B1 is the application; B2 and B3 are the runtime-reconfiguration "wow" — first the ReCOP reprogramming *itself*, then the **Nios reprogramming the ReCOP** (the heterogeneous-MPSoC headline).

## B1. `app.asm` — the live application (lead with this) — ~2 min

**What it is:**
> "This is the full application running on the board: a real-time power-system frequency monitor with two modes and an alarm."

**Demo script (do it live, narrate each step):**

1. **RAW mode** (HEX shows the raw ADC sample):
   > "In RAW mode the ReCOP just reads the ADC directly — HEX shows the raw sample."
2. **Switches pick the grid frequency:**
   > "SW[3:0] selects a grid-frequency scenario from 47 to 52.5 Hz — the ADC emulates whatever I dial in."
   - **[scenario lookup]** — the switches choose an entry in a small table; the ReCOP turns that into the ADC's FTW.
3. **Press KEY1 → MEASURE mode** (full pipeline runs):
   > "KEY1 switches to MEASURE — now the signal flows through the whole pipeline, ADC → AVG → COR → PD → ReCOP, and HEX shows the measured period."
   - **[COR / PD]** — teammates' ASPs: COR (correlation) and PD (peak detect) turn the smoothed wave into a *period* measurement (how long one cycle takes).
   - **[period]** — time per cycle; it's the inverse of frequency. A bigger period = lower frequency.
4. **The alarm (the reactive part — this is the highlight):**
   > "If the frequency drifts outside the safe band — 48.5 to 51.5 Hz — the system **latches an alarm** on the red LEDs. KEY2 acknowledges and clears it."
   - **Demo it:** set an in-band switch (no alarm) → flip to an out-of-band one (alarm LEDs light and *stay* lit) → press KEY2 (clears). That visible latch-and-acknowledge is the money moment.
   - **[latched alarm]** — once tripped it stays on until a human acknowledges it, so a brief fault isn't missed.

**Credibility line:**
> "This was validated on the board across all 16 switch settings."

📊 SHOW: nothing extra needed — the board *is* the demo. Have the mode/switch/alarm behaviour rehearsed.

## B2. `reconfig_demo.asm` — runtime reprogramming (the "wow") — ~1.5 min

**What it is (plain):**
> "This proves the system can **rewrite its own program while running** — it loads a brand-new program into memory over the NoC and jumps to it, no reflashing the board."

- **[runtime PM reload]** — replacing the program in Program Memory while the chip keeps running, instead of recompiling and re-flashing.
- **[reconfig node]** — a special NoC node (port 6) that writes incoming words into program memory.

**Demo script:**

1. **BEFORE:** HEX = `0x1111`, one LED on.
   > "Before state — this is the original program."
2. **Press KEY1:** ReCOP streams a new "Program B" into memory at address 0x1000 over the NoC, then jumps to it.
3. **AFTER:** HEX shows the **switch value captured at the moment of reload**, a different LED on.

**The clinching sentence (say this slowly — it's what proves it's real):**
> "The value on HEX is read from the switches **at the instant of reload and frozen into the new program's code**. So if I change the switches *now* — after the reload — HEX does **not** change. That can only happen if those instructions were genuinely written into program memory at runtime, not baked into the chip beforehand."

- Why this matters: a hardcoded value could be dismissed as "already in the bitstream." A *frozen live switch value* can't have been — it's the fingerprint of true runtime reprogramming.

📊 SHOW: the board. Optionally have `reconfig_demo.asm`'s header comment open in case someone asks how the packets are built.

## B3. Nios II reprograms ReCOP — the heterogeneous-MPSoC headline — ~1.5 min

**What it is (plain):**
> "In the last demo the ReCOP rewrote its *own* program. Here the **other processor**
> does it: the **Nios II** CPU loads a brand-new program into the ReCOP's memory over
> the network while the ReCOP is held still, then lets it run. Two *different* kinds of
> processor cooperating is what makes this a *heterogeneous* multiprocessor — the whole
> point of the project."

- **[Nios II]** — a standard general-purpose soft CPU. In our system it's the **non-critical support processor**: configuration, debugging, and reprogramming the ReCOP — exactly the role the brief assigns it.
- **[custom instruction]** — we added our *own* machine instruction to the Nios that builds a complete reconfiguration packet in one step. The brief asks for a custom Nios instruction; this is it — and it's *used* on every packet.
- **[Avalon ↔ NoC bridge]** — a small adapter we wrote so the Nios can put packets onto our NoC like any other node.

**Demo script (live):**

1. **On reset:** HEX = `0000` — the Nios is holding the ReCOP frozen while it rewrites its memory.
2. **The JTAG console** (on the laptop) prints "reprogramming ReCOP… done" — the Nios narrating over its debug channel.
3. **The ReCOP wakes up running the Nios-loaded program** (a switch echo): **move the switches → HEX follows them live.**
   > "The ReCOP is now running code the *Nios* wrote into it — a program that reads the switches and shows them. I move the switches; the display follows."

**The clinching sentence:**
> "None of what the ReCOP is running was in the original chip image. The Nios wrote those instructions at runtime, over the network, using our custom instruction to build the packets. An independent processor reprogrammed the control core, live."

**If asked about clocking (one sentence):**
> "The ReCOP only meets timing at 10 MHz, but the Nios needs a faster clock for its debugger, so it's on its own 50 MHz domain — the two meet only through one safe crossing bridge, with everything touching the network and the ReCOP reset kept on the 10 MHz side."

⚠️ **Honesty check:** claim the Nios subsystem / custom instruction as yours only to the extent you built it; scale the wording to your actual contribution.

📊 SHOW: the board (switch-follow) + the `nios2-terminal` console window. Optionally `nios_reconfig.c` open — point at the `CONFPROG_BUILD(...)` calls (= the custom instruction in use).

---

# PART C — Setup checklist (do this BEFORE your scheduled slot)

The brief says "all set-ups have to be made and ready before the scheduled time." Don't compile anything live.

- [ ] Both `.sof` bitstreams pre-built and ready to flash (know which runs `app.asm` vs `reconfig_demo.asm`).
- [ ] Nios software (`nios_reconfig.c`) compiled and ready to download over JTAG; `nios2-terminal` window open for its console output.
- [ ] Remember the interaction: running the Nios reconfig **holds + overwrites** the ReCOP, so for the B1/B2 demos load a *passive* Nios program (or none) — only run `nios_reconfig.c` for B3.
- [ ] Board plugged in, programmer cable tested.
- [ ] ModelSim session pre-loaded with the three waveforms (`tb_avg_asp`, `tb_adc`, `testbed_pipeline`) so you can show one in 5 seconds if asked — no recompiling.
- [ ] Report diagrams open in a tab or on slides: 4 datapath/control figures + 3 waveforms + resource table.
- [ ] Decide: are you filling the TBD Fmax/M10K/DSP numbers first? (Strongly recommended.)
- [ ] Rehearse the `app.asm` alarm sequence (in-band → out-of-band → KEY2) once on the real board.
- [ ] Rehearse the `reconfig_demo` switch-freeze point so you can deliver the clinching line cleanly.

---

# One-sentence summaries (if you're cut short on time)

- **ADC-ASP:** "A DDS sine generator whose frequency I can retune at runtime with a single 16-bit word."
- **AVG-ASP:** "A moving-average filter that costs one add and one subtract regardless of window size — no divider."
- **Verification:** "Self-checking testbenches against a C reference, plus an end-to-end ADC→AVG NoC testbed."
- **GP-2:** "My ASPs are the live front-end, and I wrote the ReCOP app that configures the pipeline and runs the alarm."
- **Reconfig demo:** "The system rewrites its own program over the NoC at runtime — proven by a frozen live switch value."
- **Nios reprogramming:** "The Nios II support CPU writes a program into the ReCOP's memory at runtime over the NoC, using a custom instruction — two different processors cooperating, exactly the heterogeneous MPSoC the brief asks for."
