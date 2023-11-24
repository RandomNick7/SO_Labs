import os

def write_names(name_str):
    for i in range (0,10):
        out_f.write(name_str)
    
    bytes = b'\x00'*(512*29 - len(name_str)*10)
    out_f.write(bytes)
    
    for i in range (0,10):
        out_f.write(name_str)
    
    bytes = b'\x00'*(512 - len(name_str)*10)
    out_f.write(bytes)

fname = "Lab3"

in_f = open(fname+".bin", "rb")
out_f = open(fname+".img", "wb")
out_f.write(in_f.read())

# Place the specific strings at specififc places in memory
target_size = 584192
bytes = b'\x00' * (target_size - os.path.getsize(fname+".bin"))
out_f.write(bytes)
write_names(b"@@@FAF-212 Vladislav CRUCERESCU###") # Sector 1141 - 1170 | 8 EA00 - 9 2400

target_size = 737792-512 # Don't count the last added sector...
bytes = b'\x00' * (target_size - os.path.getsize(fname+".img"))
out_f.write(bytes)

write_names(b"@@@FAF-212 Dorin OTGON###") # Sector 1441 - 1470 | B 4200 - B 7C00

target_size = 753152-512
bytes = b'\x00' * (target_size - os.path.getsize(fname+".img"))
out_f.write(bytes)

write_names(b"@@@FAF-212 Inga PALADI###") # Sector 1471 - 1500 | B 7E00 - B B800

# Fill in the rest of the file
target_size = 1474560-512
bytes = b'\x00' * (target_size - os.path.getsize(fname+".img"))
out_f.write(bytes)
