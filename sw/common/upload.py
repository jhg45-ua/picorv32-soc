import sys, serial, struct, time

port = "/dev/ttyUSB1"
baud = 115200
bin_file = sys.argv[1]

with open(bin_file, "rb") as f:
    data = f.read()

ser = serial.Serial(port, baud, timeout=2)

# Mandar 'u' para activar el bootloader
ser.write(b"u")
time.sleep(0.1)

# Esperar respuesta READY
line = ser.readline()
if b"READY" in line:
    print(f"Cargando {len(data)} bytes...")
    # Enviar tamaño en 4 bytes (little-endian uint32)
    ser.write(struct.pack("<I", len(data)))
    # Enviar el binario completo
    ser.write(data)
    print("¡Programa cargado! Salida del procesador:")
    # Dejar el terminal abierto para ver la salida del programa
    while True:
        try:
            ch = ser.read().decode('ascii', errors='ignore')
            sys.stdout.write(ch)
            sys.stdout.flush()
        except KeyboardInterrupt:
            break