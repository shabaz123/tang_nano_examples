"""Usage: py -m pip install pyserial; py test_loopback.py COM7"""
import sys
import time
import serial

port = sys.argv[1] if len(sys.argv) > 1 else 'COM7'
payload = bytes(range(256)) + b'PDM UART loopback\r\n' + bytes(reversed(range(256)))
with serial.Serial(port, 115200, timeout=3, write_timeout=3,
                   rtscts=False, dsrdtr=False, xonxoff=False) as ser:
    time.sleep(0.15)
    ser.reset_input_buffer()
    ser.write(payload)
    ser.flush()
    reply = ser.read(len(payload))
    if reply != payload:
        for i, (expected, received) in enumerate(zip(payload, reply)):
            if expected != received:
                print(f'First mismatch at byte {i}: sent {expected:02X}, received {received:02X}')
                break
        print(f'FAIL: sent {len(payload)} bytes, received {len(reply)} bytes')
        sys.exit(1)
    print(f'PASS: {len(payload)} bytes echoed exactly at 115200 baud')
