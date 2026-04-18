#!/usr/bin/env python3
"""Minimal hand-assembler for the GP1 calculator program.

Encodes each ReCOP instruction using the HW decode used in GP1:
    IR[31:26] = OP   IR[25:24] = AM
    IR[23:20] = Rz   IR[19:16] = Rx
    IR[15:0]  = immediate / address

Emits a .mif for a 32768 x 16 program memory (two 16-bit words per
instruction: upper then lower).
"""
from collections import OrderedDict

# ---------- ISA constants ----------
OP = {
    'ldr':   0x00,
    'str':   0x02,
    'subvr': 0x03,
    'subr':  0x04,
    'andr':  0x08,
    'orr':   0x0C,
    'clfz':  0x10,
    'sz':    0x14,
    'jmp':   0x18,
    'noop':  0x34,
    'addr':  0x38,
}
AM_INH, AM_IMM, AM_DIR, AM_REG = 0, 1, 2, 3

# ---------- MMIO addresses ----------
HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 = 0xF00, 0xF01, 0xF02, 0xF03, 0xF04, 0xF05
LEDR = 0xF10
SW_A = 0xF20
KEY_A = 0xF21

def enc(op, am, rz=0, rx=0, imm=0):
    return ((op & 0x3F) << 26) | ((am & 3) << 24) | ((rz & 0xF) << 20) \
         | ((rx & 0xF) << 16) | (imm & 0xFFFF)

def noop():                 return enc(OP['noop'], AM_INH)
def ldr_i(rz, v):           return enc(OP['ldr'], AM_IMM, rz, 0, v & 0xFFFF)
def ldr_d(rz, addr):        return enc(OP['ldr'], AM_DIR, rz, 0, addr & 0xFFFF)
def str_d(rx, addr):        return enc(OP['str'], AM_DIR, 0, rx, addr & 0xFFFF)
def add_i(rz, rx, v):       return enc(OP['addr'], AM_IMM, rz, rx, v & 0xFFFF)
def add_r(rz, rx):          return enc(OP['addr'], AM_REG, rz, rx)
def subv_i(rz, rx, v):      return enc(OP['subvr'], AM_IMM, rz, rx, v & 0xFFFF)
def subv_r(rz, rx):         return enc(OP['subvr'], AM_REG, rz, rx)
def sub_i(rz, v):           return enc(OP['subr'], AM_IMM, rz, 0, v & 0xFFFF)
def and_i(rz, rx, v):       return enc(OP['andr'], AM_IMM, rz, rx, v & 0xFFFF)
def and_r(rz, rx):          return enc(OP['andr'], AM_REG, rz, rx)
def sz(addr):               return enc(OP['sz'], AM_IMM, 0, 0, addr & 0xFFFF)
def jmp(addr):              return enc(OP['jmp'], AM_IMM, 0, 0, addr & 0xFFFF)

# ---------- Program (two-pass: resolve labels) ----------
# Each entry is either a string label or a function taking label dict -> int.
prog = []
labels = {}

def L(name):
    prog.append(('LABEL', name))

def I(func_or_word):
    prog.append(('INST', func_or_word))

# Pass 1: materialise labels at their PC addresses (PC in 16-bit words).
def lay_out():
    pc = 0
    for kind, x in prog:
        if kind == 'LABEL':
            labels[x] = pc
        else:
            pc += 2  # every instruction is two 16-bit words

# Pass 2: assemble.
def assemble():
    words = []
    for kind, x in prog:
        if kind == 'LABEL':
            continue
        if callable(x):
            ir32 = x(labels)
        else:
            ir32 = x
        upper = (ir32 >> 16) & 0xFFFF
        lower = ir32 & 0xFFFF
        words.append(upper)
        words.append(lower)
    return words

# ---------- Emit the program ----------
# init
L('start')
I(noop())
I(ldr_i(3, 0))                                   # R3 = 0
I(ldr_i(7, 15))                                  # R7 = 15 (blank)
I(str_d(7, HEX0))
I(str_d(7, HEX2))
I(str_d(7, HEX3))
I(str_d(7, HEX5))
I(ldr_i(7, 0))
I(str_d(7, LEDR))

L('main')
I(ldr_d(1, KEY_A))
I(and_i(1, 1, 14))
I(lambda lab: sz(lab['main']))

I(and_i(2, 1, 2))
I(sub_i(2, 2))
I(lambda lab: sz(lab['kplus']))
I(and_i(2, 1, 4))
I(sub_i(2, 4))
I(lambda lab: sz(lab['kminus']))
I(and_i(2, 1, 8))
I(sub_i(2, 8))
I(lambda lab: sz(lab['kequal']))
I(lambda lab: jmp(lab['wrel']))

L('kplus')
I(ldr_i(3, 1))
I(lambda lab: jmp(lab['capa']))
L('kminus')
I(ldr_i(3, 2))
I(lambda lab: jmp(lab['capa']))
L('kequal')
I(sub_i(3, 0))
I(lambda lab: sz(lab['wrel']))
I(lambda lab: jmp(lab['capb']))

# --- capture operand A ---
L('capa')
I(ldr_d(1, SW_A))
I(and_i(1, 1, 1023))
I(lambda lab: sz(lab['inva']))
I(add_i(2, 1, 0))
I(subv_i(2, 2, 1))
I(and_r(2, 1))
I(lambda lab: sz(lab['deca']))
I(lambda lab: jmp(lab['inva']))

L('deca')
for i, bit in enumerate([1, 2, 4, 8, 16, 32, 64, 128, 256, 512]):
    I(ldr_i(4, i))
    I(sub_i(1, bit))
    I(lambda lab: sz(lab['gota']))
I(lambda lab: jmp(lab['inva']))

L('gota')
I(str_d(4, HEX0))
I(lambda lab: jmp(lab['wrel']))

# --- capture operand B and compute ---
L('capb')
I(ldr_d(1, SW_A))
I(and_i(1, 1, 1023))
I(lambda lab: sz(lab['inva']))
I(add_i(2, 1, 0))
I(subv_i(2, 2, 1))
I(and_r(2, 1))
I(lambda lab: sz(lab['decb']))
I(lambda lab: jmp(lab['inva']))

L('decb')
for i, bit in enumerate([1, 2, 4, 8, 16, 32, 64, 128, 256, 512]):
    I(ldr_i(5, i))
    I(sub_i(1, bit))
    I(lambda lab: sz(lab['gotb']))
I(lambda lab: jmp(lab['inva']))

L('gotb')
I(str_d(5, HEX5))
I(sub_i(3, 1))
I(lambda lab: sz(lab['adop']))
I(add_i(6, 4, 0))
I(subv_r(6, 5))
I(lambda lab: jmp(lab['disp']))

L('adop')
I(add_i(6, 4, 0))
I(add_r(6, 5))

L('disp')
I(and_i(2, 6, 32768))
I(lambda lab: sz(lab['pos']))
# negative
I(ldr_i(7, 0))
I(subv_r(7, 6))
I(str_d(7, HEX2))
I(ldr_i(7, 10))
I(str_d(7, HEX3))
I(ldr_i(3, 0))
I(lambda lab: jmp(lab['wrel']))

L('pos')
I(add_i(7, 6, 0))
I(subv_i(7, 7, 10))
I(and_i(2, 7, 32768))
I(lambda lab: sz(lab['tens']))
# 0..9
I(str_d(6, HEX2))
I(ldr_i(7, 15))
I(str_d(7, HEX3))
I(ldr_i(3, 0))
I(lambda lab: jmp(lab['wrel']))

L('tens')
I(str_d(7, HEX2))
I(ldr_i(7, 1))
I(str_d(7, HEX3))
I(ldr_i(3, 0))
I(lambda lab: jmp(lab['wrel']))

# --- invalid input: flash LEDs for ~0.4 s ---
L('inva')
I(ldr_i(1, 1023))
I(str_d(1, LEDR))
I(ldr_i(2, 20))          # outer counter
L('outer')
I(ldr_i(7, 60000))       # inner counter
L('flsh')
I(subv_i(7, 7, 1))
I(lambda lab: sz(lab['inndn']))
I(lambda lab: jmp(lab['flsh']))
L('inndn')
I(subv_i(2, 2, 1))
I(lambda lab: sz(lab['flof']))
I(lambda lab: jmp(lab['outer']))

L('flof')
I(ldr_i(1, 0))
I(str_d(1, LEDR))
I(lambda lab: jmp(lab['wrel']))

# --- wait for all keys released ---
L('wrel')
I(ldr_d(1, KEY_A))
I(and_i(1, 1, 14))
I(lambda lab: sz(lab['main']))
I(lambda lab: jmp(lab['wrel']))

# ---------- Run it ----------
lay_out()
words = assemble()

print(f"program size: {len(words)} 16-bit words "
      f"({len(words)//2} instructions)")
print("labels:")
for name, addr in labels.items():
    print(f"  {name:<8s} = 0x{addr:04X}  ({addr})")

with open('rawOutput.mif', 'w') as f:
    f.write("WIDTH = 16;\n")
    f.write("DEPTH = 32768;\n")
    f.write("ADDRESS_RADIX = HEX;\n")
    f.write("DATA_RADIX = HEX;\n\n")
    f.write("CONTENT BEGIN\n")
    for i, w in enumerate(words):
        f.write(f"    {i:04X} : {w:04X};\n")
    if len(words) < 32768:
        f.write(f"    [{len(words):04X}..7FFF] : 0000;\n")
    f.write("END;\n")
print("wrote rawOutput.mif")
