#!/usr/bin/env python3
"""Stop-and-wait PSRAM burst uploader for the proposed v1 FPGA protocol.
Requires matching FPGA firmware (not included in this engineering package).
"""
import argparse
import struct
import sys
from pathlib import Path

import serial

REQ_MAGIC = b'\xa5\x5a'
RESP_MAGIC = b'\x5a\xa5'
CMD_WRITE = 1
CMD_READ = 2
CAPACITY = 131072 * 32


def crc16(data):
    c = 0xffff
    for byte in data:
        c ^= byte << 8
        for _ in range(8):
            c = ((c << 1) ^ (0x1021 if c & 0x8000 else 0)) & 0xffff
    return c


def read_exact(port, n):
    out = bytearray()
    while len(out) < n:
        chunk = port.read(n - len(out))
        if not chunk:
            raise TimeoutError(f'UART timeout ({len(out)}/{n} response bytes)')
        out.extend(chunk)
    return bytes(out)


def transaction(port, command, channel, index, payload=b'', attempts=3):
    if not 0 <= channel <= 1 or not 0 <= index < 131072:
        raise ValueError('invalid channel/burst index')
    frame = REQ_MAGIC + struct.pack('<BBIB', command, channel, index, len(payload)) + payload
    frame += struct.pack('<H', crc16(frame))
    for attempt in range(attempts):
        port.reset_input_buffer()
        port.write(frame)
        port.flush()
        try:
            head = read_exact(port, 10)
            if head[:2] != RESP_MAGIC:
                raise ValueError('response sync mismatch')
            rc, ch, ix, status, n = struct.unpack('<BBIBB', head[2:])
            if n > 32:
                raise ValueError('oversized response')
            body = read_exact(port, n + 2)
            expected_crc = crc16(head + body[:-2])
            received_crc = struct.unpack('<H', body[-2:])[0]

            if expected_crc != received_crc:
                print(f"Response:     {(head + body).hex(' ')}")
                print(f"Calculated CRC: 0x{expected_crc:04X}")
                print(f"Received CRC:   0x{received_crc:04X}")
                raise ValueError('response CRC mismatch')
            if (rc, ch, ix) != (command, channel, index):
                raise ValueError('response command/channel/index mismatch')
            if status != 0:
                raise RuntimeError(f'FPGA returned status {status}')
            return body[:-2]
        except (TimeoutError, ValueError) as exc:
            if attempt == attempts - 1:
                raise
            print(f'retrying burst {index}: {exc}', file=sys.stderr)
    raise RuntimeError('unreachable')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('port')
    ap.add_argument('binfile', type=Path)
    ap.add_argument('--channel', type=int, choices=[0, 1], required=True)
    ap.add_argument('--baud', type=int, default=115200)
    ap.add_argument('--limit-bursts', type=int)
    args = ap.parse_args()
    data = args.binfile.read_bytes()
    if not data or len(data) > CAPACITY:
        ap.error(f'BIN length must be 1..{CAPACITY} bytes')
    count = (len(data) + 31) // 32
    if args.limit_bursts is not None:
        count = min(count, args.limit_bursts)
    with serial.Serial(args.port, args.baud, timeout=2.0, write_timeout=2.0) as port:
        for index in range(count):
            chunk = data[index*32:(index+1)*32].ljust(32, b'\0')
            if transaction(port, CMD_WRITE, args.channel, index, chunk):
                raise ValueError('WRITE unexpectedly returned payload')
            actual = transaction(port, CMD_READ, args.channel, index)
            if actual != chunk:
                raise ValueError(f'PSRAM mismatch at channel {args.channel}, burst {index}: '
                                 f'expected {chunk.hex()}, got {actual.hex()}')
            if index % 256 == 0 or index == count-1:
                print(f'Verified {index+1}/{count} bursts', flush=True)
    print(f'PASS: {count*32} PSRAM bytes written/read back exactly; '
          f'original BIN length {len(data)} bytes, channel {args.channel}')


if __name__ == '__main__':
    main()
