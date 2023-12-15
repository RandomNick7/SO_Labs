org 0x7c00										; Offset - this is where the boot sector begins

mov ah, 0x01									; Hide the cursor
mov cx, 0x2020									; Set CH and CL to 0x20 to turn off the cursor
int 0x10

mov ax, 0x1300									; Print the "Bootloader" string at the top of the screen
mov bx, 0x0007									; Video Page 0, Video Attr 07 - Light Gray on Black
mov cx, 0x0015									; String length - 21
mov dx, 0x0420									; Row 4, Col 32
xor bp, bp										; Address 0:boot_msg
mov es, bp
mov bp, boot_msg
int 0x10

mov cl, 0x0a									; Length - 10
mov dx, 0x0a23									; Row 10, Col 35
mov bp, addr_prompt
int 0x10

mov cl, 0x05									; Length - 5
mov dx, 0x0c23									; Row 12, Col 35
mov bp, track_input_text
int 0x10

inc cl											; Length - 6
inc dh											; Row 13, Col 35
mov bp, sector_input_text
int 0x10

mov cl, 0x04									; Length - 4
mov dx, 0x0e24									; Row 14, Col 36
mov bp, side_input_text
int 0x10

boot_start:

mov si, 0x0002
read_track:
	mov dx, 0x0c2a								; Row 12, Col 42
	call read_prep

	cmp di, 0x004f								; Valid interval: [0-79]
	jg read_track

shl di, 8
mov [kernel_location], di

read_sector:
	mov dx, 0x0d2a								; Row 13, Col 42
	call read_prep
	
	cmp di, 0x0012								; Valid interval: [1-18]
	jg read_sector
	
	test di, di
	jz read_sector

add [kernel_location], di

dec si
read_side:
	mov dx, 0x0e2a								; Row 14, Col 42
	call read_prep
	
	cmp di, 0x0001								; Valid interval: [0-1]
	jg read_side
shl di, 8

; Try reading 1st sector
call kernel_sector_setup
int 0x13										; Read Sectors, Load to RAM

mov bx, 0x0004									; Video Page 0, Video Attr 04 - Red on Black (used for errors)

cmp ah, 0
je check_kernel_start							; If no errors, check if loaded code is part of kernel

; Display Disk read error ahead
call prep_kernel_msg
mov bp, disk_err_msg							; Address 0:disk_err
int 0x10

jmp boot_start

check_kernel_start:
	cmp word [0x8000], 0x1234
	je kernel_start_found

location_err:
	mov bp, location_err_msg					; Address 0:location_err_msg
	call prep_kernel_msg
	int 0x10

	jmp boot_start

kernel_start_found:
	call kernel_sector_setup

kernel_read_loop:

	cmp word[bx + 0x1fe], 0x4321				; Check if byte 511, 512 are 0x4321
	je kernel_read_end
	inc cx										; Increment Sector
	cmp cl, 0x13
	jl inc_floppy_end
	
	mov cl, 0x01								; Increment Side
	inc dx
	cmp dl, 0x02
	jl inc_floppy_end
	
	inc ch										; Increment Track

inc_floppy_end:
	add bx, 0x0200
	test bx, bx
	jnz kernel_read_loop_skip

	inc bx
	mov es, bx
	dec bx

kernel_read_loop_skip:
	mov ah, 0x02
	int 0x13

	jmp kernel_read_loop

kernel_read_end:
	mov bx, 0x0002									; Video Attr 02 - Green on Black
	mov bp, kernel_load_msg							; Address 0:kernel_load_msg
	call prep_kernel_msg
	int 0x10

	xor ax, ax
	int 0x16

	jmp 0x8000



; prep_kernel_msg - Sets up the registers to print Kernel status
; In - BX: Video Page & Attriibute; BP: String Location
; Out - AX, CX, DX: Parameters for int 0x10 call

prep_kernel_msg:
	mov ax, 0x1301								; Print the upcoming message string
	mov dx, 0x1421								; Row 20, Col 33
	mov cx, 0x000e								; String length - 14
	ret

; kernel_sector_setup - Sets up data needed to read 1st sector of Kernel
; In - None
; Out - AX, BX, CX, DX: Parameters for int 0x13 call

kernel_sector_setup:
	mov ax, 0x0201								; Read 1 sector										
	mov cx, [kernel_location]
	mov dx, di									; Side #
	mov bx, 0x8000   							; Write to RAM starting from 0:8000
	ret


; read_prep - Move cursor, write _ for each digit required and call read_num
; In - DX: Cursor location, SI: Max Integer length in digits
; Out - DI: Integer itself

read_prep:
	mov ah, 0x02								; Move cursor to position
	int 0x10
	
	mov ax, 0x0a5f								; Write underscores
	mov cx, si
	int 0x10

	call read_num
	ret
	

; read_num - Read a decimal integer of specified length
; In - SI: Max Integer length in digits
; Out - DI: Integer itself
; NOTE: Returns on ENTER press

read_num:
	xor di, di
	xor bx, bx
	
read_num_loop:
	xor ax, ax									; Read a key
	int 0x16

	cmp ah, 0x0e								; BKSP pressed
	je read_bksp
	cmp ah, 0x1c								; ENTER pressed
	je read_enter
	
	push ax
	mov ax, di
	mov di, 0x0a
	mul di
	mov di, ax									; DI *= 10
	pop ax
	
	cmp bx, si									; Digit limit reached
	je read_num_loop
	
	sub al, 0x30								; Offset ASCII char to correspond with digit hex values
	cmp al, 0x09								; Ignore any value above 9
	ja read_num_loop

	xor ah, ah
	add di, ax									; DI += AH
	
	add al, 0x30
	mov ah, 0x0e								; Write char as TTY
	int 0x10

	inc bl										; Increment counter
	jmp read_num_loop

read_bksp:
	cmp bl, 0
	jz read_num_loop
	dec bl

	mov ax, di
	xor dx, dx
	mov di, 0x0a
	div di
	mov di, ax									; DI /= 10

	mov ah, 0x03								; Get cursor position
	int 0x10

	dec ah										; Move cursor to previous position
	dec dl
	int 0x10

	mov ax, 0x0a5f								; Write _ at current cursor position
	mov cx, 0x0001								; Char repeats - 1
	int 0x10
	jmp read_num_loop

read_enter:
	ret

kernel_location dw 0x0000
boot_msg db "Kernel App BootLoader"
addr_prompt db "Kernel At:"
track_input_text db "Track"
side_input_text db "Side"
sector_input_text db "Sector"
disk_err_msg db 	"  Disk Error  "
location_err_msg db "Location Error"
kernel_load_msg db 	"Kernel Loaded!"

times 510 - ($ - $$) db 0						; Pad to 510 bytes
dw 0xaa55										; Boot signature at byte 511, 512