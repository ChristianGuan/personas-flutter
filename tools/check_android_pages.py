#!/usr/bin/env python3
"""Check ELF64 LOAD segments and uncompressed APK .so offsets for 16 KB compatibility.

This is a static artifact check. It does not replace execution on a 16 KB device.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

PAGE = 16384


def elf_loads(data):
    if len(data) < 64 or data[:4] != b'\x7fELF' or data[4] not in (1, 2) or data[5] not in (1, 2):
        raise ValueError('Invalid ELF header')
    bits = 64 if data[4] == 2 else 32
    endian = '<' if data[5] == 1 else '>'
    if bits == 64:
        offset = struct.unpack_from(endian + 'Q', data, 32)[0]
        size, count = struct.unpack_from(endian + 'HH', data, 54)
        expected_size = 56
    else:
        offset = struct.unpack_from(endian + 'I', data, 28)[0]
        size, count = struct.unpack_from(endian + 'HH', data, 42)
        expected_size = 32
    if size < expected_size or offset + size * count > len(data):
        raise ValueError('Truncated ELF program table')
    segments = []
    for index in range(count):
        start = offset + index * size
        if struct.unpack_from(endian + 'I', data, start)[0] != 1:
            continue
        if bits == 64:
            file_offset, address = struct.unpack_from(endian + 'QQ', data, start + 8)
            alignment = struct.unpack_from(endian + 'Q', data, start + 48)[0]
        else:
            file_offset, address = struct.unpack_from(endian + 'II', data, start + 4)
            alignment = struct.unpack_from(endian + 'I', data, start + 28)[0]
        segments.append({'offset': file_offset, 'vaddr': address, 'alignment': alignment,
                         'aligned_16kb': alignment >= PAGE and alignment % PAGE == 0
                         and file_offset % PAGE == address % PAGE})
    if not segments:
        raise ValueError('ELF contains no LOAD segments')
    return bits, segments


def inspect(path):
    path = Path(path)
    libraries = []
    is_apk = path.suffix.lower() == '.apk'
    with zipfile.ZipFile(path) as archive, path.open('rb') as raw:
        for info in archive.infolist():
            if not info.filename.endswith('.so') or '/lib/' not in '/' + info.filename:
                continue
            bits, segments = elf_loads(archive.read(info))
            zip_aligned = None
            if is_apk and info.compress_type == zipfile.ZIP_STORED:
                raw.seek(info.header_offset)
                header = raw.read(30)
                if header[:4] != b'PK\x03\x04':
                    raise ValueError('Invalid ZIP local header')
                name_length, extra_length = struct.unpack_from('<HH', header, 26)
                zip_aligned = (info.header_offset + 30 + name_length + extra_length) % PAGE == 0
            libraries.append({'path': info.filename, 'bits': bits, 'required_16kb': bits == 64,
                              'min_load_alignment': min(s['alignment'] for s in segments),
                              'elf_aligned_16kb': all(s['aligned_16kb'] for s in segments),
                              'apk_uncompressed_zip_aligned_16kb': zip_aligned})
    required = [lib for lib in libraries if lib['required_16kb']]
    ok = bool(required) and all(lib['elf_aligned_16kb'] and lib['apk_uncompressed_zip_aligned_16kb'] is not False for lib in required)
    return {'artifact': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'static_16kb_pass': ok, 'elf64_libraries': len(required), 'libraries': libraries,
            'runtime_16kb': 'not_tested',
            'bundle_zip_alignment': 'Check BundleConfig and generated APK with bundletool' if not is_apk else 'checked for uncompressed native libraries'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        report = inspect(args.artifact)
    except (ValueError, OSError, zipfile.BadZipFile, struct.error) as error:
        parser.exit(1, f'Artifact check failed: {error}\n')
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report['static_16kb_pass'] else 1)


if __name__ == '__main__':
    main()
