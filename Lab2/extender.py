import os

target_size = 1474560

fnames = ["Lab2"]

for i in fnames:
    in_f = open(i+".bin", "rb")
    out_f = open(i+".img", "wb")

    out_f.write(in_f.read())
    bytes = b'\x00' * (target_size - os.path.getsize(i+".bin"))
    out_f.write(bytes)