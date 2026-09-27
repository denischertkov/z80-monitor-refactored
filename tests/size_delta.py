"""Count encoded bytes of all changed regions, independently of sjasmplus.

This is a deliberately limited instruction-length counter, NOT an assembler.
It fails on unsupported instructions. No padding/alignment was added or removed.
Reference for encodings: https://www.zilog.com/docs/z80/um0080.pdf
Run: python3 tests/size_delta.py [--instructions]
"""
import sys
from test_refactor import Machine, ROOT, expand, section


def instruction_size(op, arg):
    args = [s.strip() for s in arg.split(',')]
    reg8 = ('a', 'b', 'c', 'd', 'e', 'h', 'l', '(hl)')
    reg16 = ('bc', 'de', 'hl', 'sp')
    if op in ('ret', 'rst', 'scf', 'push', 'pop', 'rrca'):
        return 1
    if op in ('jr', 'djnz', 'bit', 'srl', 'rr'):
        return 2
    if op in ('call', 'jp'):
        return 1 if op == 'jp' and arg == '(hl)' else 3
    if op in ('inc', 'dec') and arg in reg8 + reg16:
        return 1
    if op == 'ld':
        dst, src = args
        if dst in reg8 and src in reg8:
            return 1
        if dst in reg8 and not src.startswith('('):
            return 2
        if dst == 'hl' and src.startswith('('):
            return 3
        if dst in reg16 and not src.startswith('('):
            return 3
        if dst.startswith('(') and src == 'hl':
            return 3
    if op == 'add':
        dst, src = args
        if dst == 'hl' and src in reg16:
            return 1
        if dst == 'a':
            return 1 if src in reg8 else 2
    if op in ('sub', 'cp', 'and', 'or', 'xor'):
        return 1 if arg in reg8 else 2
    raise ValueError(f'Unsupported encoding: {op} {arg}')


def regions():
    before = (ROOT / 'tests/fixtures/before-unification.asm').read_text()
    after = expand(ROOT / 'monitor-sjasmplus.asm')
    return [
        ('GETHL / GETX', section(before, 'GETHL\t', 'BCTOA\t'), ''),
        ('ECHO', section(before, 'ECHO\t', 'LOAD:'), ''),
        ('READ_HEX16 (GETHL alias)', '', section(after, 'GETHL:', 'LOAD:')),
        ('GOTO', section(before, 'GOTO\t', 'BASIC\n'), section(after, 'GOTO ', 'BASIC\n')),
        ('MEMDUMP entry', section(before, 'MEMDUMP:', 'mv_main_view:'), section(after, 'MEMDUMP:', 'mv_main_view:')),
        ('memview G', section(before, 'mv_goto_addr:', 'mv_draw_page:'), section(after, 'mv_goto_addr:', 'mv_draw_page:')),
    ]


def count(text):
    return sum(instruction_size(op, arg) for op, arg in Machine(text).code)


def saving():
    return sum(count(old)-count(new) for _, old, new in regions())


if __name__ == '__main__':
    old_total = new_total = 0
    for name, old, new in regions():
        a, b = count(old), count(new)
        old_total += a
        new_total += b
        print(f'{name:28} {a:3} -> {b:3} bytes')
        if '--instructions' in sys.argv:
            for caption, text in [('Before', old), ('After', new)]:
                if text:
                    print(caption)
                    for op, arg in Machine(text).code:
                        print(f'  {instruction_size(op, arg)}  {op} {arg}')
    print(f'Total changed regions: {old_total} -> {new_total}; saved {old_total-new_total} bytes')
    print('Instruction-length calculation; real assembly confirmation is a separate test.')
