# Group 4 GP1 &mdash; ReCOP Processor on DE1-SoC

Full implementation of the ReCOP processor on the Intel DE1-SoC (Cyclone V) board, including assembler, datapath, multicycle control unit, program memory, data memory, and on-board debug peripherals.

## Building and Running a Program

### 1. Write assembly

Edit `gp-1/assembler/test.asm`. See the **Core Instructions** table below for supported mnemonics.

Example:

```asm
        LDR R1, #0xABCD    ; R1 ← 0xABCD
        JMP #0             ; loop forever
```

### 2. Assemble to MIF

```bash
cd gp-1/assembler
python asm.py test.asm
```

This generates `test.mif` &mdash; a 16-bit wide, 32768-deep ROM image. Each 32-bit instruction is stored as two consecutive 16-bit words (high word at `2N`, low word at `2N+1`).

### 3. Compile and program the board

1. Open `gp-1/gp_1.qpf` in Quartus 18.1.
2. **Processing &rarr; Start Compilation** (full compile).
3. **Tools &rarr; Programmer**, load `output_files/gp_1.sof`, then **Start**.

### 4. Updating just the MIF (no full recompile)

After changing `test.asm` and regenerating `test.mif`, you do **not** need a full Quartus recompile:

**Processing &rarr; Update Memory Initialization File**, then **Processing &rarr; Start &rarr; Start Assembler**, then reprogram the board.

## Board Peripherals

### Inputs

| Input      | Function                                                                     |
|------------|------------------------------------------------------------------------------|
| `CLOCK_50` | 50 MHz master clock                                                          |
| `KEY[0]`   | **Reset** (active low &mdash; hold to reset, release to run)                 |
| `KEY[3]`   | **Single-step** the FSM (only active when debug mode is on)                  |
| `SW[0]`    | **Debug mode enable** &mdash; `'1'` freezes the FSM between `KEY[3]` presses |
| `SW[1]`    | **HEX[3:0] display select** &mdash; `'0'` = PC, `'1'` = Rz                   |

### Outputs (debug mode, `SW[0]='1'`)

| Output      | Function                                                                   |
|-------------|----------------------------------------------------------------------------|
| `LEDR[0]`   | Debug mode indicator (mirrors `SW[0]`)                                     |
| `LEDR[1]`   | **Z flag** (ALU zero flag)                                                 |
| `LEDR[7:2]` | **Opcode** of the current instruction (6 bits from IR)                     |
| `LEDR[9:8]` | **AM** &mdash; Addressing Mode of the current instruction (2 bits from IR) |
| `HEX[3:0]`  | **PC** or **Rz** (16-bit value as 4 hex digits, selected by `SW[1]`)       |
| `HEX[5]`    | **FSM state** (single hex digit, see table below)                          |
| `HEX[4]`    | Blanked                                                                    |

### Outputs (run mode, `SW[0]='0'`)

At 50 MHz the processor state changes far too fast to read, so the displays show a
simple "alive" heartbeat instead. The processor is still running normally in the
background &mdash; switch back to debug mode to inspect it.

| Output        | Function                                                     |
|---------------|--------------------------------------------------------------|
| `LEDR[9:0]`   | All off                                                      |
| `HEX[5,3:0]`  | Rotating outer-ring segment (~6 Hz) &mdash; heartbeat        |
| `HEX[4]`      | Blanked                                                      |

### FSM state encoding on HEX[5]

| Digit | State              |
|-------|--------------------|
| `0`   | IDLE               |
| `1`   | FETCH_1 / FETCH_1B |
| `2`   | FETCH_2 / FETCH_2B |
| `3`   | WAIT_MEM           |
| `4`   | EXECUTE            |
| `5`   | FETCH_JUMP         |

## Debug Mode Usage

Debug mode lets you step through the processor one FSM state at a time. Essential for verifying behavior &mdash; at 50 MHz the PC changes too fast to read.

1. Set `SW[0] = '1'` (debug mode on, `LEDR[0]` lights up).
2. Press and release `KEY[0]` to reset &mdash; FSM goes to IDLE, PC = 0.
3. Press `KEY[3]` once per FSM state advance. Each press moves the FSM one state forward.
4. For each instruction, the FSM steps through:
   `FETCH_1` &rarr; `FETCH_1B` &rarr; `FETCH_2` &rarr; `FETCH_2B` &rarr; [`WAIT_MEM` &rarr;] `EXECUTE` &rarr; [`FETCH_JUMP` &rarr;] `FETCH_1` ...`
5. Watch `HEX[5]` to confirm the state, `HEX[3:0]` to watch PC or Rz, and `LEDR[9:2]` to see the AM and opcode fields of the currently-latched instruction.

To run the processor at full speed, set `SW[0] = '0'`.

## Simulation

1. Open `gp-1/gp_1.qpf` in Quartus.
2. **Tools &rarr; Run Simulation Tool &rarr; RTL Simulation** (launches ModelSim).
3. In ModelSim, compile the testbenches from `gp-1/simulation/modelsim/`:
   - `tb_datapath.vhd` &mdash; exercises datapath control signals directly
   - `tb_control_unit.vhd` &mdash; exercises the FSM transitions

---
---

## Core Instructions

Instruction format: `| AM(2) | Opcode(6) | Rz(4) | Rx(4) | Operand(16) |`

Addressing modes (AM field):

| AM   | Name      | Syntax     |
|------|-----------|------------|
| `00` | inherent  | no operand |
| `01` | immediate | `#value`   |
| `10` | direct    | `$address` |
| `11` | register  | `Rx`       |

|    | Instruction           | Effect                              |
|----|-----------------------|-------------------------------------|
| 1  | `AND Rz Rx #value`    | `Rz ← Rx AND value`                 |
| 2  | `AND Rz Rz Rx`        | `Rz ← Rz AND Rx`                    |
| 3  | `OR  Rz Rx #value`    | `Rz ← Rx OR value`                  |
| 4  | `OR  Rz Rz Rx`        | `Rz ← Rz OR Rx`                     |
| 5  | `ADD Rz Rx #value`    | `Rz ← Rx + value`                   |
| 6  | `ADD Rz Rz Rx`        | `Rz ← Rz + Rx`                      |
| 7  | `SUBV Rz Rx #value`   | `Rz ← Rx - value` (stores)          |
| 8  | `SUB Rz #value`       | `Z ← (Rz - value == 0)` (flag only) |
| 9  | `LDR Rz #value`       | `Rz ← value`                        |
| 10 | `LDR Rz Rx`           | `Rz ← DM[Rx]`                       |
| 11 | `LDR Rz $address`     | `Rz ← DM[address]`                  |
| 12 | `STR Rz #value`       | `DM[Rz] ← value`                    |
| 13 | `STR Rz Rx`           | `DM[Rz] ← Rx`                       |
| 14 | `STR Rx $address`     | `DM[address] ← Rx`                  |
| 15 | `JMP #address`        | `PC ← address`                      |
| 16 | `JMP Rx`              | `PC ← Rx`                           |
| 17 | `PRESENT Rz #address` | if `Rz == 0` then `PC ← address`    |
| 18 | `DATACALL Rx`         | `DPCR ← Rx & R7`                    |
| 19 | `DATACALL Rx #value`  | `DPCR ← Rx & value`                 |
| 20 | `SZ #address`         | if `Z == 1` then `PC ← address`     |
| 21 | `CLFZ`                | clear `Z` flag                      |
| 22 | `LSIP Rz`             | `Rz ← SIP` (external input port)    |
| 23 | `SSOP Rx`             | `SOP ← Rx` (external output port)   |
| 24 | `NOOP`                | no operation                        |
| 25 | `STRPC $address`      | `DM[address] ← PC`                  |

Labels are supported &mdash; precede any instruction with `LABEL:` and reference it in JMP/SZ/PRESENT/STRPC.

---
---

## Example: Verifying the Board

A minimal sanity-check program:

```asm
        LDR R1, #0xABCD    ; R1 ← 0xABCD
        JMP #0             ; loop forever
```

In run mode (`SW[0]=0`), the HEX displays show the heartbeat &mdash; the processor is running in the background but its state is not visible.

In debug mode (`SW[0]=1`), step through with `KEY[3]` and verify:

- After the first full fetch/execute cycle: `SW[1]=1` &rarr; `HEX[3:0]` shows `ABCD` (R1 contents)
- `HEX[3:0]` with `SW[1]=0` cycles `0000` &rarr; `0002` as the PC loops
- `LEDR[7:2]` alternates between LDR opcode (`000000`) and JMP opcode (`011000`) as each instruction latches into IR

## Known Problems

1. Bug 1 (debug gating): In debug mode, FSM holds in a state but combinational outputs keep firing &rarr; PC races at 50 MHz. Fixed by gating `ir_load`/`op_load` in the output process

2. Bug 2 (ROM address latency): The `altsyncram` has a registered address &mdash; when you change the address input, `q` doesn't update until the next clock edge. Fixed by adding wait states.

**Why FETCH_2B is needed (every instruction):**

- FETCH_1B: `ir_load=1`, PC increments from N to N+1 at the rising edge
- ROM samples address at the same edge &rarr; registers N+1
- `q` only becomes `mem[N+1]` after the edge
- If FETCH_2 fired `op_load` next edge, it would still latch `mem[N]` (stale)
- FETCH_2B inserts a wait so `q` settles to `mem[N+1]` before `op_load` fires

**Why FETCH_1B is needed (for jumps):**

- FETCH_JUMP: `pc_load=1`, PC overwrites with target at rising edge
- ROM hasn't seen the new address yet
- Without FETCH_1B, the next FETCH_1 would assert `ir_load` and latch the pre-jump memory word
- FETCH_1B gives ROM one cycle to output `mem[target]`

For RESET &rarr; IDLE &rarr; FETCH_1 (first ever fetch), FETCH_1B is technically redundant because PC=0 has been stable for many cycles. But keeping it makes the fetch timing uniform across all paths (sequential, after-jump, after-reset).
