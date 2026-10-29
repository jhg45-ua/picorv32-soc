import sys, serial, struct
port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyUSB1"
data = open(sys.argv[1], "rb").read()

ser = serial.Serial(port, 115200)
print("Press RESET button on the board...")
while b"READY" not in ser.readline():
    pass
ser.write(struct.pack("<I", len(data)) + data)
while True:                      # mostrar la salida de la app
    sys.stdout.write(ser.read().decode("ascii", "ignore")); sys.stdout.flush()