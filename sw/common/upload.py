import sys, serial, struct, time

port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyUSB1"
data = open(sys.argv[1], "rb").read()

ser = serial.Serial(port, 115200, timeout=0.5)
ser.reset_input_buffer()
print(f"Waiting for READY ({len(data)} bytes to send). Press CPU_RESETN...")

while True:
    line = ser.readline()
    if line:
        print("RX:", line)
    if b"READY" in line:
        break

print("READY detected, sending data...")
for b in struct.pack("<I", len(data)) + data:
    ser.write(bytes([b]))
    ser.flush()
    time.sleep(0.002)          # 2 ms/byte: sin riesgo de overrun
print("Sent data. Output of the app (Ctrl+C to exit):")

try:
    while True:
        c = ser.read(1)
        if c:
            sys.stdout.write(c.decode("ascii", "ignore")); sys.stdout.flush()
except KeyboardInterrupt:
    pass