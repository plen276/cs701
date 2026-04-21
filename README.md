# Group 4 GP1

## Getting Started

Instructions are to be entered in the `.asm` file found in `gp-1/assembler`. Run `asm.py` to generate `.mif` file

```bash
python asm.py test.asm
```

The available instructions are all core instruction provided for this project:

Instruction format: `| AM(2) | Opcode(6) | Rz(4) | Rx(4) | Operand(16) |`

Addressing modes:

- `00` — inherent (no operand)
- `01` — immediate (`#value`)
- `10` — direct (`$address`)
- `11` — register (`Rx`)

---

## Core Instructions

|    | Instruction           |
|----|-----------------------|
| 1  | `AND Rz Rx #value`    |
| 2  | `AND Rz Rz Rx`        |
|    |                       |
| 3  | `OR Rz Rx #value`     |
| 4  | `OR Rz Rz Rx`         |
|    |                       |
| 5  | `ADD Rz Rx #value`    |
| 6  | `ADD Rz Rz Rx`        |
|    |                       |
| 7  | `SUBV Rz Rx #value`   |
| 8  | `SUB Rz #value`       |
|    |                       |
| 9  | `LDR Rz #value`       |
| 10 | `LDR Rz Rx`           |
| 11 | `LDR Rz $address`     |
|    |                       |
| 12 | `STR Rz #value`       |
| 13 | `STR Rz Rx`           |
| 14 | `STR Rx $address`     |
|    |                       |
| 15 | `JMP #address`        |
| 16 | `JMP Rx`              |
|    |                       |
| 17 | `PRESENT Rz #Operand` |
| 18 | `DATACALL Rx`         |
| 19 | `DATACALL Rx #value`  |
| 20 | `SZ #address`         |
| 21 | `CLFZ`                |
| 22 | `LSIP Rz`             |
| 23 | `SSOP Rx`             |
| 24 | `NOOP`                |
| 25 | `STRPC $address`      |

## Running Testbenches

1. Open `gp-1.qpf` through Quartus Project Manager Wizard.
2. Open ModelSim via Quartus using `Tools` => `Run Simulation Tool` => `RTL Simulation`
3. Compile the relevant testbenches inside `simulation/modelsim`

## Demoing Implementation

1. To synthesise the design to the board, compile the design using the same Quartus project above
2. Upload the `.sof` file found in `output_files`
3. Update memory initialisation file after making changes to the `.asm` file and compiling a new MIF file using `Processing` => `Update Memory Initialization File`

## Peripherals

- SW[0] enables debugging mode, use KEY[3] to step through FSM while in debugging mode
- KEY[0] is used to reset the program
- SW[1] '0' shows PC, '1' shows Rz (HEX[3..0])
- HEX[5] displays the current state of the FSM while in debugging mode.
