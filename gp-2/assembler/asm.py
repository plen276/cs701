#!/usr/bin/env python3
# ReCOP assembler -> Quartus MIF  (IR: AM[31:30] OP[29:24] Rz[23:20] Rx[19:16] opr[15:0])
# each 32-bit instruction is stored as two consecutive 16-bit words (upper first)
# usage: python asm.py <source.asm> [-o out.mif] [--depth 32768]

from __future__ import annotations

import argparse
import re
import sys
from typing import Callable, Dict, List, Optional, Tuple


# opcodes (mirror design_files/opcodes.vhd)
OP: Dict[str, int] = {
    "ldr":       0x00,
    "str":       0x02,
    "subvr":     0x03,
    "subr":      0x04,
    "andr":      0x08,
    "orr":       0x0C,
    "clfz":      0x10,
    "sz":        0x14,
    "jmp":       0x18,
    "present":   0x1C,
    "strpc":     0x1D,
    "max":       0x1E,
    "datacall":  0x28,  # register form
    "datacall2": 0x29,  # immediate form
    "noop":      0x34,
    "ler":       0x36,
    "lsip":      0x37,
    "ssop":      0x3A,
    "ssvop":     0x3B,
    "addr":      0x38,
    "cer":       0x3C,
    "ceot":      0x3E,
    "seot":      0x3F,
}

AM_INH, AM_IMM, AM_DIR, AM_REG = 0b00, 0b01, 0b10, 0b11

WORDS_PER_INSTR = 2  # 32-bit instruction stored as two 16-bit words


def ir_encode(op: int, am: int, rz: int = 0, rx: int = 0, opr: int = 0) -> int:
    return (
        ((am & 0x3)   << 30)
        | ((op & 0x3F) << 24)
        | ((rz & 0xF)  << 20)
        | ((rx & 0xF)  << 16)
        |  (opr & 0xFFFF)
    )


class AsmError(Exception):
    pass


def err(src: str, msg: str) -> AsmError:
    return AsmError(f"{src}: {msg}")


RE_REG        = re.compile(r"^R(\d+)$", re.IGNORECASE)
RE_NUM        = re.compile(r"^(-?0[xX][0-9A-Fa-f]+|-?0[bB][01]+|-?\d+)$")
RE_LABEL_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def parse_number(s: str) -> int:
    s = s.strip()
    if s.startswith("-"):
        return -parse_number(s[1:])
    if s[:2].lower() == "0x":
        return int(s[2:], 16)
    if s[:2].lower() == "0b":
        return int(s[2:], 2)
    return int(s)


def match_register(tok: str, src: str) -> Optional[int]:
    m = RE_REG.match(tok)
    if not m:
        return None
    n = int(m.group(1))
    if n > 15:
        raise err(src, f"register out of range: '{tok}' (max R15)")
    return n


class Operand:
    __slots__ = ("kind", "value", "raw")

    REG = "REG"  # value = int register index 0..15
    IMM = "IMM"  # value = str payload after '#'
    DIR = "DIR"  # value = str payload after '$'
    SYM = "SYM"  # value = str bare label reference
    NUM = "NUM"  # value = int bare integer literal

    def __init__(self, kind: str, value, raw: str):
        self.kind = kind
        self.value = value
        self.raw = raw

    def __repr__(self) -> str:  # pragma: no cover
        return f"<{self.kind}:{self.value!r}>"


def classify(tok: str, src: str) -> Operand:
    reg = match_register(tok, src)
    if reg is not None:
        return Operand(Operand.REG, reg, tok)
    if tok.startswith("#"):
        return Operand(Operand.IMM, tok[1:], tok)
    if tok.startswith("$"):
        return Operand(Operand.DIR, tok[1:], tok)
    if RE_NUM.match(tok):
        return Operand(Operand.NUM, parse_number(tok), tok)
    if RE_LABEL_NAME.match(tok):
        return Operand(Operand.SYM, tok, tok)
    raise err(src, f"cannot parse operand '{tok}'")


MNEMONICS = {
    # inherent
    "NOOP", "CLFZ", "CER", "CEOT", "SEOT",
    # load / store
    "LDR", "STR", "STRPC",
    # arithmetic & logic
    "ADD", "SUBV", "SUB", "AND", "OR", "MAX",
    # control
    "JMP", "SZ", "PRESENT",
    # reactive
    "LSIP", "SSOP", "SSVOP", "LER",
    # data thread
    "DATACALL",
}

DIRECTIVES = {"ORG", "ENDPROG", "END", "ENDP", "EQU"}


class Assembler:
    def __init__(self) -> None:
        self.labels:  Dict[str, int] = {}
        self.equ:     Dict[str, int] = {}
        self.program: List[Tuple[int, str, List[str], str]] = []  # (pc, mnem, tokens, src)
        self.pc: int = 0  # current word address

    def _value_of(self, token: str, src: str, width: int = 16) -> int:
        t = token.strip()
        if RE_NUM.match(t):
            v = parse_number(t)
        elif t in self.equ:
            v = self.equ[t]
        elif t in self.labels:
            v = self.labels[t]
        else:
            raise err(src, f"undefined symbol '{t}'")
        mask = (1 << width) - 1
        # signed negatives are accepted; reject anything outside [-2^(w-1), 2^w)
        if v < -(1 << (width - 1)) or v > mask:
            raise err(src, f"value {v} does not fit in {width} bits")
        return v & mask

    def _reg_of(self, op: Operand, src: str, role: str) -> int:
        if op.kind != Operand.REG:
            raise err(src, f"expected {role}, got '{op.raw}'")
        return op.value

    def assemble(self, text: str, srcname: str = "<input>") -> List[Tuple[int, int]]:
        self._pass1(text, srcname)
        return self._pass2()

    def _pass1(self, text: str, srcname: str) -> None:
        for lineno, raw in enumerate(text.splitlines(), 1):
            src = f"{srcname}:{lineno}"
            line = raw.split(";", 1)[0]
            if not line.strip():
                continue

            stripped = line.lstrip()
            has_ws   = (line != stripped)
            parts    = [p for p in re.split(r"[\s,]+", stripped.strip()) if p]
            if not parts:
                continue

            # EQU: NAME EQU value  (NAME may be at col 0)
            if len(parts) >= 3 and parts[1].upper() == "EQU":
                name = parts[0]
                if not RE_LABEL_NAME.match(name):
                    raise err(src, f"invalid EQU name '{name}'")
                if name in self.equ:
                    raise err(src, f"EQU '{name}' redefined")
                self.equ[name] = parse_number(parts[2])
                continue

            # label: first token at col 0 that is not a mnemonic/directive
            first_upper = parts[0].upper()
            if (not has_ws) and first_upper not in MNEMONICS \
               and first_upper not in DIRECTIVES:
                name = parts[0]
                if not RE_LABEL_NAME.match(name):
                    raise err(src, f"invalid label '{name}'")
                if name in self.labels:
                    raise err(src, f"label '{name}' redefined")
                self.labels[name] = self.pc
                parts = parts[1:]
                if not parts:
                    continue
                first_upper = parts[0].upper()

            if first_upper in DIRECTIVES:
                self._directive(first_upper, parts[1:], src)
                continue
            if first_upper not in MNEMONICS:
                raise err(src, f"unknown mnemonic '{parts[0]}'")

            self.program.append((self.pc, first_upper, parts[1:], src))
            self.pc += WORDS_PER_INSTR

    def _directive(self, mnem: str, operands: List[str], src: str) -> None:
        if mnem == "ORG":
            if len(operands) != 1:
                raise err(src, "ORG takes 1 argument")
            self.pc = parse_number(operands[0]) & 0xFFFF
            return
        if mnem in ("ENDPROG", "END", "ENDP"):
            return
        raise err(src, f"unknown directive '{mnem}'")

    def _pass2(self) -> List[Tuple[int, int]]:
        out: List[Tuple[int, int]] = []
        for pc, mnem, operand_tokens, src in self.program:
            encoder = ENCODERS[mnem]
            ops = [classify(t, src) for t in operand_tokens]
            ir32 = encoder(self, ops, src)
            out.append((pc, ir32 & 0xFFFFFFFF))
        return out


Encoder = Callable[[Assembler, List[Operand], str], int]

ENCODERS: Dict[str, Encoder] = {}


def _inh(key: str) -> Encoder:
    def enc(asm: Assembler, ops: List[Operand], src: str) -> int:
        if ops:
            raise err(src, f"{key.upper()} takes no operands")
        return ir_encode(OP[key], AM_INH)
    return enc


ENCODERS["NOOP"] = _inh("noop")
ENCODERS["CLFZ"] = _inh("clfz")
ENCODERS["CER"]  = _inh("cer")
ENCODERS["CEOT"] = _inh("ceot")
ENCODERS["SEOT"] = _inh("seot")


def _enc_ldr(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 2:
        raise err(src, "LDR takes 2 operands")
    rz = asm._reg_of(ops[0], src, "Rz")
    src_op = ops[1]
    if src_op.kind == Operand.IMM:
        return ir_encode(OP["ldr"], AM_IMM, rz, 0, asm._value_of(src_op.value, src))
    if src_op.kind == Operand.DIR:
        return ir_encode(OP["ldr"], AM_DIR, rz, 0, asm._value_of(src_op.value, src))
    if src_op.kind == Operand.REG:
        return ir_encode(OP["ldr"], AM_REG, rz, src_op.value, 0)
    raise err(src, f"LDR does not accept '{src_op.raw}' as source")


ENCODERS["LDR"] = _enc_ldr


def _enc_str(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 2:
        raise err(src, "STR takes 2 operands")
    reg = asm._reg_of(ops[0], src, "first operand")
    second = ops[1]
    if second.kind == Operand.DIR:   # STR Rx $addr  -> M[addr] <- Rx
        return ir_encode(OP["str"], AM_DIR, 0, reg, asm._value_of(second.value, src))
    if second.kind == Operand.IMM:   # STR Rz #val   -> M[Rz] <- val
        return ir_encode(OP["str"], AM_IMM, reg, 0, asm._value_of(second.value, src))
    if second.kind == Operand.REG:   # STR Rz Rx     -> M[Rz] <- Rx
        return ir_encode(OP["str"], AM_REG, reg, second.value, 0)
    raise err(src, f"STR does not accept '{second.raw}' as source")


ENCODERS["STR"] = _enc_str


def _enc_strpc(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 1 or ops[0].kind != Operand.DIR:
        raise err(src, "STRPC syntax: STRPC $addr")
    return ir_encode(OP["strpc"], AM_DIR, 0, 0, asm._value_of(ops[0].value, src))


ENCODERS["STRPC"] = _enc_strpc


# ADD / AND / OR: register form Rz Rz Rx, or immediate form Rz Rx #val
def _alu3(op_key: str) -> Encoder:
    def enc(asm: Assembler, ops: List[Operand], src: str) -> int:
        if len(ops) != 3:
            raise err(src, f"{op_key.upper()} takes 3 operands")
        rz = asm._reg_of(ops[0], src, "Rz")
        second = ops[1]
        third = ops[2]
        if second.kind == Operand.REG and third.kind == Operand.REG:
            if second.value != rz:
                raise err(
                    src,
                    f"register-form {op_key.upper()} requires Rz == Rz"
                    f" (saw R{rz} R{second.value})",
                )
            return ir_encode(OP[op_key], AM_REG, rz, third.value, 0)
        if second.kind == Operand.REG and third.kind == Operand.IMM:
            return ir_encode(
                OP[op_key], AM_IMM, rz, second.value,
                asm._value_of(third.value, src),
            )
        raise err(src, f"{op_key.upper()} expects 'Rz Rx #val' or 'Rz Rz Rx'")
    return enc


ENCODERS["ADD"] = _alu3("addr")
ENCODERS["AND"] = _alu3("andr")
ENCODERS["OR"]  = _alu3("orr")


def _enc_subv(asm: Assembler, ops: List[Operand], src: str) -> int:
    # hw only supports immediate: SUBV Rz Rx #val
    if len(ops) != 3:
        raise err(src, "SUBV takes 3 operands (Rz Rx #val)")
    rz = asm._reg_of(ops[0], src, "Rz")
    rx = asm._reg_of(ops[1], src, "Rx")
    if ops[2].kind != Operand.IMM:
        raise err(src, "SUBV third operand must be an immediate (#val)")
    return ir_encode(OP["subvr"], AM_IMM, rz, rx, asm._value_of(ops[2].value, src))


ENCODERS["SUBV"] = _enc_subv


def _enc_sub(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 2:
        raise err(src, "SUB takes 2 operands (Rz #val)")
    rz = asm._reg_of(ops[0], src, "Rz")
    if ops[1].kind != Operand.IMM:
        raise err(src, "SUB second operand must be an immediate (#val)")
    return ir_encode(OP["subr"], AM_IMM, rz, 0, asm._value_of(ops[1].value, src))


ENCODERS["SUB"] = _enc_sub


def _enc_max(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 2:
        raise err(src, "MAX takes 2 operands (Rz #val)")
    rz = asm._reg_of(ops[0], src, "Rz")
    if ops[1].kind != Operand.IMM:
        raise err(src, "MAX second operand must be an immediate (#val)")
    return ir_encode(OP["max"], AM_IMM, rz, 0, asm._value_of(ops[1].value, src))


ENCODERS["MAX"] = _enc_max


# accepts #val, bare number, or label; used for branch/jump targets
def _target_as_imm(asm: Assembler, op: Operand, src: str) -> int:
    if op.kind == Operand.IMM:
        return asm._value_of(op.value, src)
    if op.kind == Operand.NUM:
        return op.value & 0xFFFF
    if op.kind == Operand.SYM:
        return asm._value_of(op.value, src)
    raise err(src, f"expected immediate target, got '{op.raw}'")


def _enc_jmp(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 1:
        raise err(src, "JMP takes 1 operand")
    op = ops[0]
    if op.kind == Operand.REG:  # JMP Rx
        return ir_encode(OP["jmp"], AM_REG, 0, op.value, 0)
    return ir_encode(OP["jmp"], AM_IMM, 0, 0, _target_as_imm(asm, op, src))


ENCODERS["JMP"] = _enc_jmp


def _enc_sz(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 1:
        raise err(src, "SZ takes 1 operand")
    return ir_encode(OP["sz"], AM_IMM, 0, 0, _target_as_imm(asm, ops[0], src))


ENCODERS["SZ"] = _enc_sz


def _enc_present(asm: Assembler, ops: List[Operand], src: str) -> int:
    if len(ops) != 2:
        raise err(src, "PRESENT takes 2 operands (Rz target)")
    rz = asm._reg_of(ops[0], src, "Rz")
    tgt = _target_as_imm(asm, ops[1], src)
    return ir_encode(OP["present"], AM_IMM, rz, 0, tgt)


ENCODERS["PRESENT"] = _enc_present


# LSIP/LER use Rz; SSOP/SSVOP use Rx
def _enc_single_reg(op_key: str, role: str) -> Encoder:
    def enc(asm: Assembler, ops: List[Operand], src: str) -> int:
        if len(ops) != 1:
            raise err(src, f"{op_key.upper()} takes 1 operand (R{role})")
        r = asm._reg_of(ops[0], src, f"R{role}")
        if role == "z":
            return ir_encode(OP[op_key], AM_REG, r, 0, 0)
        else:
            return ir_encode(OP[op_key], AM_REG, 0, r, 0)
    return enc


ENCODERS["LSIP"]  = _enc_single_reg("lsip",  "z")
ENCODERS["LER"]   = _enc_single_reg("ler",   "z")
ENCODERS["SSOP"]  = _enc_single_reg("ssop",  "x")
ENCODERS["SSVOP"] = _enc_single_reg("ssvop", "x")


def _enc_datacall(asm: Assembler, ops: List[Operand], src: str) -> int:
    # DATACALL Rx        -> opcode 0x28, AM=register
    # DATACALL Rx #value -> opcode 0x29, AM=immediate
    if len(ops) == 1:
        rx = asm._reg_of(ops[0], src, "Rx")
        return ir_encode(OP["datacall"], AM_REG, 0, rx, 0)
    if len(ops) == 2:
        rx = asm._reg_of(ops[0], src, "Rx")
        if ops[1].kind != Operand.IMM:
            raise err(src, "DATACALL second operand must be an immediate")
        return ir_encode(OP["datacall2"], AM_IMM, 0, rx, asm._value_of(ops[1].value, src))
    raise err(src, "DATACALL: expected 'Rx' or 'Rx #val'")


ENCODERS["DATACALL"] = _enc_datacall


def write_mif(
    instructions: List[Tuple[int, int]],
    depth: int = 32768,
    fill: int = 0x0000,
) -> str:
    mem: Dict[int, int] = {}
    for pc, ir in instructions:
        if pc + 1 >= depth:
            raise AsmError(
                f"instruction at word {pc:#06x} exceeds memory depth {depth}"
            )
        mem[pc]     = (ir >> 16) & 0xFFFF
        mem[pc + 1] =  ir        & 0xFFFF

    lines: List[str] = []
    lines.append("WIDTH = 16;")
    lines.append(f"DEPTH = {depth};")
    lines.append("ADDRESS_RADIX = HEX;")
    lines.append("DATA_RADIX = HEX;")
    lines.append("")
    lines.append("CONTENT BEGIN")
    addrs = sorted(mem)
    prev = -1
    for a in addrs:
        # emit a range line for any gap
        if a > prev + 1 and prev + 1 < a:
            if a - 1 > prev + 1:
                lines.append(f"    [{prev+1:04X}..{a-1:04X}] : {fill:04X};")
            else:
                lines.append(f"    {prev+1:04X} : {fill:04X};")
        lines.append(f"    {a:04X} : {mem[a]:04X};")
        prev = a
    if prev + 1 < depth:
        if prev + 1 == depth - 1:
            lines.append(f"    {prev+1:04X} : {fill:04X};")
        else:
            lines.append(f"    [{prev+1:04X}..{depth-1:04X}] : {fill:04X};")
    lines.append("END;")
    return "\n".join(lines) + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    ap = argparse.ArgumentParser(
        prog="asm.py",
        description="Assemble a ReCOP .asm source into a .mif for GP1.",
    )
    ap.add_argument("source", help=".asm source file")
    ap.add_argument(
        "-o", "--output", default=None,
        help="output .mif path (default: <source stem>.mif)",
    )
    ap.add_argument(
        "--depth", type=int, default=32768,
        help="program-memory depth in 16-bit words (default: 32768)",
    )
    ap.add_argument(
        "--fill", default="0",
        help="value (hex or decimal) to fill unused ROM slots; default 0",
    )
    ap.add_argument(
        "-v", "--verbose", action="store_true",
        help="print the resolved label table after assembly",
    )
    args = ap.parse_args(argv)

    try:
        with open(args.source, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError as exc:
        print(f"error: cannot read '{args.source}': {exc}", file=sys.stderr)
        return 2

    asm = Assembler()
    try:
        words = asm.assemble(text, srcname=args.source)
        mif = write_mif(
            words,
            depth=args.depth,
            fill=parse_number(args.fill) & 0xFFFF,
        )
    except AsmError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    out_path = args.output
    if out_path is None:
        if args.source.lower().endswith(".asm"):
            out_path = args.source[:-4] + ".mif"
        else:
            out_path = args.source + ".mif"

    try:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(mif)
    except OSError as exc:
        print(f"error: cannot write '{out_path}': {exc}", file=sys.stderr)
        return 2

    n_inst = len(words)
    print(
        f"assembled {n_inst} instruction{'s' if n_inst != 1 else ''} "
        f"({n_inst * WORDS_PER_INSTR} words) -> {out_path}"
    )
    if args.verbose and asm.labels:
        print("labels:")
        for name, addr in sorted(asm.labels.items(), key=lambda kv: kv[1]):
            print(f"  {name:<12s} = 0x{addr:04X}  ({addr})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
