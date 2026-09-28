"""Source-level regression tests, NOT an assembler or cycle-accurate emulator.

Run: python3 -m unittest discover -s tests -v
The small interpreter executes selected original/refactored instructions;
SIO RST, PRINT and GET2 are mocked. Real assembly and hardware tests remain required.
"""
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(name):
    return (ROOT / name).read_text()


def section(text, start, end):
    a = re.search(r'^' + re.escape(start), text, re.M).start()
    b = re.search(r'^' + re.escape(end), text, re.M).start()
    return text[a:b]


def normalized(text):
    return [' '.join(line.split()) for raw in text.splitlines()
            if (line := raw.split(';', 1)[0].strip())]


def expand(path):
    text = path.read_text()
    return re.sub(r'^\s*include\s+[\"\']([^\"\']+)[\"\'].*$',
                  lambda m: expand(path.parent / m[1]), text, flags=re.M | re.I)


class Machine:
    """Only instructions needed by tested routines. Unknown instructions fail."""
    def __init__(self, source):
        self.code, self.labels = [], {}
        for raw in source.splitlines():
            line = raw.split(';', 1)[0].rstrip()
            if not line.strip():
                continue
            if not line[0].isspace():
                parts = line.split(None, 1)
                self.labels[parts[0].rstrip(':')] = len(self.code)
                line = parts[1] if len(parts) > 1 else ''
            if line.strip():
                p = line.strip().split(None, 1)
                arg = p[1] if len(p) > 1 else ''
                chunks = re.split(r"('[^']*')", arg)
                for i in range(0, len(chunks), 2):
                    chunks[i] = re.sub(r'\b(?:AF|BC|DE|HL|A|B|C|D|E|H|L)\b',
                                       lambda m: m[0].lower(), chunks[i])
                self.code.append((p[0].lower(), ''.join(chunks)))
        self.r = dict.fromkeys('abcdehl', 0)
        self.c = self.z = False
        self.mem = bytearray(65536)
        self.stack = []
        self.output, self.messages, self.io = [], [], []
        self.inputs, self.records = [], []
        self.jump_target = None
        self.sym = {'baseaddr': 0x40ae, 'portno': 0x40b0, 'value': 0x40b1,
                    'CKSUMERR': 0x9000, 'LDETXT': 0x9100,
                    'goto_msg': 0x9200, 'mv_goto_msg': 0x9200}

    def number(self, x):
        x = x.strip()
        if x in self.sym:
            return self.sym[x]
        if x.startswith("'"):
            end = x.index("'", 1)
            n = ord(x[1:end])
            return n + int(x[end+1:] or '0')
        if x.startswith('$'):
            return int(x[1:], 16)
        if x.lower().endswith('h'):
            return int(x[:-1], 16)
        return int(x)

    def get(self, x, width=8):
        if x in self.r:
            return self.r[x]
        if x in ('bc', 'de', 'hl'):
            return (self.r[x[0]] << 8) | self.r[x[1]]
        if x.startswith('('):
            addr = self.get(x[1:-1], 16)
            return self.mem[addr] if width == 8 else self.mem[addr] | (self.mem[(addr+1)&65535] << 8)
        return self.number(x)

    def put(self, x, v, width=8):
        if x in self.r:
            self.r[x] = v & 255
        elif x in ('bc', 'de', 'hl'):
            self.r[x[0]], self.r[x[1]] = (v >> 8) & 255, v & 255
        elif x.startswith('('):
            addr = self.get(x[1:-1], 16)
            self.mem[addr] = v & 255
            if width == 16:
                self.mem[(addr+1)&65535] = (v >> 8) & 255
        else:
            raise AssertionError(x)

    def run(self, entry, stops=()):
        pc = self.labels[entry]
        stop_pc = {self.labels[s] for s in stops}
        for _ in range(10000):
            if pc in stop_pc:
                return
            op, arg = self.code[pc]
            pc += 1
            args = [x.strip() for x in arg.split(',')]
            if op == 'ld':
                dst, src = args
                width = 16 if dst in ('bc', 'de', 'hl') or src in ('bc', 'de', 'hl') else 8
                self.put(dst, self.get(src, width), width)
            elif op in ('inc', 'dec'):
                old = self.get(arg)
                width = 16 if arg in ('bc', 'de', 'hl') else 8
                v = (old + (1 if op == 'inc' else -1)) & ((1 << width)-1)
                self.put(arg, v, width)
                if width == 8:
                    self.z = v == 0
            elif op in ('and', 'or', 'xor', 'sub', 'cp'):
                a, b = self.r['a'], self.get(arg)
                v = {'and': lambda: a & b, 'or': lambda: a | b,
                     'xor': lambda: a ^ b, 'sub': lambda: a-b, 'cp': lambda: a-b}[op]()
                self.c, self.z = v < 0, (v & 255) == 0
                if op != 'cp':
                    self.r['a'] = v & 255
            elif op in ('add', 'sbc'):
                dst, src = args
                width = 16 if dst == 'hl' else 8
                a, b = self.get(dst), self.get(src)
                v = a+b if op == 'add' else a-b-int(self.c)
                self.c = not 0 <= v < (1 << width)
                if width == 8 or op == 'sbc':
                    self.z = (v & ((1 << width)-1)) == 0
                self.put(dst, v, width)
            elif op == 'rrca':
                a = self.r['a']
                self.c = bool(a & 1)
                self.r['a'] = (a >> 1) | ((a & 1) << 7)
            elif op == 'bit':
                bit, reg = args
                self.z = not bool(self.get(reg) & (1 << int(bit)))
            elif op in ('srl', 'rr'):
                value = self.get(arg)
                carry = self.c
                self.c = bool(value & 1)
                result = (value >> 1) | (128 if op == 'rr' and carry else 0)
                self.put(arg, result)
                self.z = result == 0
            elif op == 'scf':
                self.c = True
            elif op in ('push', 'pop'):
                if op == 'push':
                    self.stack.append((self.r['a'], self.c, self.z) if arg == 'af' else self.get(arg))
                elif arg == 'af':
                    self.r['a'], self.c, self.z = self.stack.pop()
                else:
                    self.put(arg, self.stack.pop(), 16)
            elif op == 'rst':
                if self.number(arg) == 8:
                    self.output.append(chr(self.r['a']))  # AF preserved by conout
                elif self.number(arg) == 16:
                    self.r['a'] = self.inputs.pop(0)
                else:
                    raise AssertionError(arg)
            elif op in ('call', 'jp', 'jr', 'ret', 'djnz'):
                if op == 'djnz':
                    self.r['b'] = (self.r['b']-1) & 255
                    if self.r['b']:
                        pc = self.labels[arg]
                    continue
                condition = args[0] if len(args) == 2 or (op == 'ret' and arg) else None
                if condition and not {'z': self.z, 'nz': not self.z, 'c': self.c, 'nc': not self.c}[condition.lower()]:
                    continue
                target = args[-1]
                if op == 'ret':
                    if not self.stack:
                        return
                    pc = self.stack.pop()
                elif target == '(hl)':
                    self.jump_target = self.get('hl')
                    return
                elif target == 'GET2':
                    a = self.records.pop(0)
                    self.r['a'], self.r['c'] = a, a
                    self.r['e'] = (self.r['e']-a) & 255
                elif target == 'PRINT':
                    self.messages.append(self.get('hl'))
                    self.r['a'], self.z = 0, True
                    if op != 'call':
                        if not self.stack:
                            return
                        pc = self.stack.pop()
                else:
                    if op == 'call':
                        self.stack.append(pc)
                    pc = self.labels[target]
            elif op in ('in', 'out'):
                self.io.append((op, self.get('bc'), self.r['a'] if op == 'out' else None))
                if op == 'in':
                    self.r['a'] = 0xa5
            else:
                raise AssertionError((op, arg))
        raise AssertionError('instruction limit')


class RefactorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = read('baseline/monitor-sjasmplus.asm')
        cls.new = expand(ROOT / 'monitor-sjasmplus.asm')

    def test_hardware_and_parser_instruction_streams_unchanged(self):
        for file, start, end in [('serial.asm', 'serialInt:', 'RDCHR\t'),
                                 ('console_io.asm', 'RDCHR\t', 'INIT\t'),
                                 ('init.asm', 'INIT\t', 'MAIN  \t'),
                                 ('cf_boot.asm', 'CPMLOAD\n', 'SIGNON\t')]:
            self.assertEqual(normalized(section(self.original, start, end)), normalized(read('src/'+file)), file)
        old = section(self.original, 'GETCHR\t', 'GETHL\t') + section(self.original, 'BCTOA\t', 'ECHO\t')
        self.assertEqual(normalized(old), normalized(read('src/hex_input.asm')))

    def test_layout_guards_and_unique_labels(self):
        labels = re.findall(r'^(\w+)(?=:|\s|$)', self.new, re.M)
        self.assertEqual(len(labels), len(set(labels)))
        self.assertIn('ASSERT MONITOR_END <= BASCLD', self.new)
        self.assertNotRegex('\n'.join(normalized(self.new)), r'(?i)DS\s+\$4000')
        constants = {}
        for name, value in re.findall(r'^(\w+)\s+EQU\s+([^;\n]+)', self.new, re.M | re.I):
            expr = re.sub(r'\$([0-9A-Fa-f]+)', r'0x\1', value)
            expr = re.sub(r'\b([0-9][0-9A-Fa-f]*)[hH]\b', r'0x\1', expr)
            constants[name] = eval(expr, {'__builtins__': {}}, constants)
        for name, addr in [('STACK', 0x40ae), ('baseaddr', 0x40ae), ('portno', 0x40b0), ('value', 0x40b1), ('me_cursor', 0x40b2), ('WORKSPACE_END', 0x40b4)]:
            self.assertEqual(constants[name], addr)

    def test_hex_formatters(self):
        for text in (self.original, self.new):
            for n in range(256):
                vm = Machine(text)
                vm.r.update(a=n, b=0x12, c=0x34, d=0x56, e=0x78, h=0xab, l=0xcd)
                vm.run('PRINT_HEX8')
                self.assertEqual(''.join(vm.output), f'{n:02X}')
                self.assertEqual([vm.get(x) for x in ('bc', 'de', 'hl')], [0x1234, 0x5678, 0xabcd])
            for n in [0, 1, 15, 16, 255, 256, 4095, 4096, 65535, *range(0, 65536, 257)]:
                vm = Machine(text)
                vm.put('hl', n)
                vm.run('PRINT_HEX16')
                self.assertEqual(''.join(vm.output), f'{n:04X}')
                self.assertEqual(vm.get('hl'), n)

    def test_page_navigation_all_pages(self):
        for text, prefix in [(read('baseline/memview.asm'), ''), (read('src/memview.asm'), 'mv_')]:
            for page in range(256):
                for direction, delta in [('next_page', 1), ('prev_page', -1)]:
                    vm = Machine(text)
                    vm.put('(baseaddr)', page << 8, 16)
                    vm.run(prefix+direction, [prefix+'main_view'])
                    self.assertEqual(vm.get('(baseaddr)', 16), ((page+delta)&255) << 8)

    def address(self, entered, entry='READ_HEX16', stops=()):
        vm = Machine(self.new)
        vm.inputs = list(entered.encode('latin1'))
        vm.put('de', 0x9876)
        vm.put('(baseaddr)', 0x5600, 16)
        vm.run(entry, stops)
        self.assertEqual(vm.get('de'), 0x9876)
        self.assertEqual(vm.stack, [])
        return vm

    def test_address_values_echo_and_empty(self):
        for entered, echo, value, empty in [
            ('\r', '\r\n', 0, True), ('0\r', '0\r\n', 0, False),
            ('0000\r', '0000\r\n', 0, False), ('fFfF\r', 'FFFF\r\n', 0xffff, False),
            ('a\r', 'A\r\n', 10, False), ('?a!1z2/3\r', 'A123\r\n', 0xa123, False),
            ('123456\r', '1234\r\n', 0x1234, False),
            ('\n\t, \r', '\r\n', 0, True),
        ]:
            vm = self.address(entered)
            self.assertEqual(''.join(vm.output), echo)
            self.assertEqual(vm.get('hl'), value)
            self.assertFalse(vm.c)
            self.assertEqual(vm.z, empty)
        # Four digits alone must still wait for Enter; source interpreter exhausts input.
        with self.assertRaises(IndexError):
            self.address('1234')

    def test_address_all_single_byte_inputs(self):
        for char in range(256):
            if char in (3, 8, 13, 27, 127):
                continue  # control keys tested separately
            vm = self.address(chr(char)+'\r')
            valid = chr(char) in '0123456789ABCDEFabcdef'
            self.assertEqual(''.join(vm.output), (chr(char).upper() if valid else '')+'\r\n', char)
            self.assertEqual(vm.z, not valid, char)
            self.assertEqual(vm.get('hl'), int(chr(char), 16) if valid else 0, char)
            self.assertFalse(vm.c)

    def test_address_cancel_and_backspace(self):
        for prefix in ('', '0', '01', '012', '0123', '012345'):
            for cancel in ('\x03', '\x1b'):
                vm = self.address(prefix+cancel)
                self.assertTrue(vm.c)
                self.assertEqual(''.join(vm.output), prefix[:4])
        for bs in ('\x08', '\x7f'):
            for entered, value, empty, echo in [
                (bs+'\r', 0, True, '\r\n'),
                ('a'+bs+'\r', 0, True, 'A\b \b\r\n'),
                ('1234'+bs+'f\r', 0x123f, False, '1234\b \bF\r\n'),
                ('1234'+bs*5+'\r', 0, True, '1234'+'\b \b'*4+'\r\n'),
            ]:
                vm = self.address(entered)
                self.assertEqual(vm.get('hl'), value)
                self.assertEqual(vm.z, empty)
                self.assertFalse(vm.c)
                self.assertEqual(''.join(vm.output), echo)

    def test_address_command_integration(self):
        for entered, target in [('\r', None), ('\x03', None), ('12\x1b', None),
                                ('0000\r', 0), ('f123\r', 0xf123)]:
            self.assertEqual(self.address(entered, 'GOTO').jump_target, target)
        for entered, expected in [('\r', 0), ('1234\r', 0x1200),
                                  ('\x03', 0x5600), ('12\x1b', 0x5600)]:
            vm = self.address(entered, 'MEMDUMP', ['mv_main_view'])
            self.assertEqual(vm.get('(baseaddr)', 16), expected)
        for entered, expected in [('\r', 0x5600), ('1234\r', 0x1200),
                                  ('\x03', 0x5600), ('12\x1b', 0x5600), ('0000\r', 0)]:
            vm = self.address(entered, 'mv_goto_addr', ['mv_main_view'])
            self.assertEqual(vm.get('(baseaddr)', 16), expected)

    def test_address_relative_branches_fit(self):
        from size_delta import instruction_size
        vm = Machine(read('src/address_input.asm'))
        offsets = [0]
        for op, arg in vm.code:
            offsets.append(offsets[-1] + instruction_size(op, arg))
        for index, (op, arg) in enumerate(vm.code):
            if op == 'jr':
                target = arg.split(',')[-1].strip()
                displacement = offsets[vm.labels[target]] - offsets[index+1]
                self.assertTrue(-128 <= displacement <= 127, (arg, displacement))

    def test_port_controls_all_values(self):
        for text, prefix, stop in [(read('baseline/porttest.asm'), '', 'main'), (read('src/porttest.asm'), 'pt_', 'pt_main')]:
            for value in range(256):
                for entry, target, delta in [('port_dec', 'portno', -1), ('port_inc', 'portno', 1), ('value_dec', 'value', -1), ('value_inc', 'value', 1)]:
                    vm = Machine(text)
                    vm.put('(portno)', value)
                    vm.put('(value)', value)
                    vm.run(prefix+entry, [stop])
                    self.assertEqual(vm.get('('+target+')'), (value+delta)&255)
                    self.assertEqual(vm.get('(value)' if target == 'portno' else '(portno)'), value)
                    self.assertEqual(vm.io, [])
            for port in (0, 0x10, 0x38, 255):
                for entry in ('port_read', 'port_write'):
                    vm = Machine(text)
                    vm.r['b'] = 255
                    vm.put('(portno)', port)
                    vm.put('(value)', 0x81)
                    vm.run(prefix+entry, [stop])
                    self.assertEqual(vm.io, [('in', port, None)] if entry == 'port_read' else [('out', port, 0x81)])

    def test_ihex_data_skip_eof_and_checksums(self):
        for text in (self.original, self.new):
            for kind in (0, 1, 2, 3, 4, 5, 255):
                for payload in ([], [0], [0x12, 0x34], list(range(255))):
                    if kind == 1 and payload:  # legacy malformed EOF deliberately not changed
                        continue
                    for corrupt in (False, True):
                        vm = Machine(text)
                        header = [len(payload), 0x80, 0, kind]
                        checksum = (-sum(header+payload) + int(corrupt)) & 255
                        vm.records = header + payload + [checksum]
                        vm.mem[0x8000:0x8100] = b'\xcc'*256
                        vm.run('LOAD')
                        self.assertEqual(vm.records, [])
                        expected = bytearray(b'\xcc'*256)
                        if kind == 0:
                            expected[:len(payload)] = bytes(payload)
                        self.assertEqual(vm.mem[0x8000:0x8100], expected)
                        self.assertEqual(vm.messages, [0x9000] if corrupt else ([0x9100] if kind == 1 else []))
                        self.assertEqual(''.join(vm.output), '.'*len(payload) if kind == 0 else '')

    def test_signon_fragment_has_no_early_nul(self):
        db = [s for s in normalized(read('build_info.inc')) if s.upper().startswith('DB ')]
        self.assertTrue(db)
        self.assertTrue(all(not re.search(r',\s*0\s*$', s) for s in db))

    @unittest.skipUnless(shutil.which('sjasmplus'), 'sjasmplus not installed; binary verification pending')
    def test_real_assembly_and_binary_layout(self):
        binaries = []
        for directory, source, stem in [
            (ROOT / 'baseline', 'monitor-sjasmplus.asm', 'monitor-sjasmplus'),
            (ROOT, 'tests/fixtures/before-unification.asm', 'before-unification'),
            (ROOT, 'monitor-sjasmplus.asm', 'monitor-sjasmplus'),
        ]:
            build = directory / 'build'
            build.mkdir(exist_ok=True)
            target = build / (stem+'.bin')
            subprocess.run(['sjasmplus', '--cleanonerror', '--raw='+str(target),
                            '--lst='+str(build / (stem+'.lst')),
                            '--sym='+str(build / (stem+'.sym')),
                            source], cwd=directory, check=True,
                           capture_output=True, text=True)
            binaries.append(target.read_bytes())
        old, before, new = binaries
        from size_delta import saving
        self.assertEqual(len(before)-len(new), saving())
        self.assertLess(len(new), len(old))
        self.assertLessEqual(len(new), 0x2000)
        self.assertEqual(new[0], 0xf3)
        for offset in (1, 8, 16, 24):
            self.assertEqual(new[offset], 0xc3)
        self.assertEqual(new[13:16], b'ROM')
        self.assertEqual(new[0x1b:0x60], b'\xff'*(0x60-0x1b))
        self.assertEqual(new[0x60:0x62], b'\x62\x00')
        print(f'\nAssembled monitor: {len(old)} -> {len(new)} bytes; saved {len(old)-len(new)}')
        print(f'Address unification: {len(before)} -> {len(new)} bytes; saved {len(before)-len(new)}')


if __name__ == '__main__':
    unittest.main()
