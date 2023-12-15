import os
out_f = open("OS.img", "wb")
in_f = open("Bootloader.bin", "rb")
out_f.write(in_f.read())

target_size = 737792
bytes = b'\x00' * (target_size - os.path.getsize("Bootloader.bin"))
out_f.write(bytes)

in_f = open("Kernel.bin", "rb")
out_f.write(in_f.read())

target_size = 1474560-512
bytes = b'\x00' * (target_size - os.path.getsize("OS.img"))
out_f.write(bytes)