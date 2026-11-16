#!/usr/bin/env python3
"""Generate the seed dumps in testsuite/ (x86_64 dump files crash can open with mayhem/crash/fixture.c as namelist)."""
import os
import struct
import sys
import zlib

MEM = b"MAYHEM-CRASH-OK!" + bytes(range(16))
PADDR = 0x1000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "testsuite")


def note(name, typ, desc):
    n = name.encode() + b"\0"
    return (struct.pack("<III", len(n), len(desc), typ) + n + b"\0" * (-len(n) % 4)
            + desc + b"\0" * (-len(desc) % 4))


def elf64_core(segments, vmcoreinfo=None):
    notes = note("CORE", 1, b"\0" * 336)
    if vmcoreinfo:
        notes += note("VMCOREINFO", 0, vmcoreinfo)
    phnum = 1 + len(segments)
    off = 64 + 56 * phnum
    data_off = (off + len(notes) + 15) & ~15
    eh = (b"\x7fELF" + bytes([2, 1, 1, 0]) + bytes(8)
          + struct.pack("<HHIQQQIHHHHHH", 4, 62, 1, 0, 64, 0, 0, 64, 56, phnum, 0, 0, 0))
    phs = struct.pack("<IIQQQQQQ", 4, 0, off, 0, 0, len(notes), 0, 0)
    blob = b""
    for paddr, mem in segments:
        phs += struct.pack("<IIQQQQQQ", 1, 7, data_off + len(blob), 0xffff880000000000 + paddr,
                           paddr, len(mem), len(mem), 0x1000)
        blob += mem
    body = eh + phs + notes
    return body + b"\0" * (data_off - len(body)) + blob


def kdump(pages, version=2, compress=False, bs=4096):
    uts = b"".join(s.ljust(65, b"\0") for s in
                   (b"Linux", b"fixture", b"5.14.0", b"#1 SMP", b"x86_64", b""))
    max_mapnr = 64
    bitmap_blocks = 2
    hdr = b"KDUMP   " + struct.pack("<i", version) + uts
    hdr = hdr.ljust(408, b"\0") + struct.pack("<qq", 0, 0)
    hdr += struct.pack("<IiiIIIIIIi", 0, bs, 1, bitmap_blocks, max_mapnr,
                       len(pages), len(pages), len(pages), 0, 1)
    hdr = hdr.ljust(bs, b"\0")
    sub = struct.pack("<QiiQQqQqQqQQQQ", 0, 0, 0, 0, max_mapnr, 0, 0, 0, 0, 0, 0, 0, max_mapnr, max_mapnr)
    sub = sub.ljust(bs, b"\0")
    bm = bytearray(bs * bitmap_blocks)
    for pfn in pages:
        bm[pfn // 8] |= 1 << (pfn % 8)
        bm[bs + pfn // 8] |= 1 << (pfn % 8)
    data_off = bs * (2 + bitmap_blocks)
    descs = b""
    data = b""
    base = data_off + 24 * len(pages)
    for pfn in sorted(pages):
        page = pages[pfn].ljust(bs, b"\0")
        if compress:
            page, flags = zlib.compress(page), 1
        else:
            flags = 0
        descs += struct.pack("<qIIQ", base + len(data), len(page), flags, 0)
        data += page
    return hdr + sub + bytes(bm) + descs + data


def main():
    os.makedirs(OUT, exist_ok=True)
    files = {
        "elf64.core": elf64_core([(PADDR, MEM)]),
        "elf64-two-segments.core": elf64_core([(PADDR, MEM), (0x100000, b"SECOND-SEGMENT!!" * 8)]),
        "elf64-vmcoreinfo.core": elf64_core(
            [(PADDR, MEM)],
            b"OSRELEASE=5.14.0\nPAGESIZE=4096\nSYMBOL(init_uts_ns)=ffffffff82000000\nKERNELOFFSET=0\n"
            b"NUMBER(phys_base)=0\nNUMBER(KERNEL_IMAGE_SIZE)=1073741824\n"),
        "kdump-v2.dump": kdump({1: MEM}),
        "kdump-v2-zlib.dump": kdump({1: MEM, 2: b"ZLIB-PAGE-TWO!!!" * 16}, compress=True),
    }
    for name, data in files.items():
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(data)
        print(name, len(data))


if __name__ == "__main__":
    sys.exit(main())
