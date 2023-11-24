org 0x7c00										; Hard offset - this is where the boot sector begins

mov ah, 0x02
mov al, 6										; Read 6 sectors (Sectors start count @ 1 instead of 0)
mov cx, 2           							; ch = 0 - cylinder, cl = 2 - sector number
mov dh, 0										; Head #0
mov dl, 0										; Drive: Diskette
mov bx, 0
mov es, bx
mov bx, 0x7e00   								; Write to RAM starting from 0:7e00 - keep code contiguous
int 0x13										; Read Sectors, Load to RAM

start:
	call clear_screen

	mov word [print_addr], option_pick_str
	call print_str
	
get_option:
	call clear_current_line
	mov byte [char_count], 1
	call read_int
	
	cmp byte [ret_val], 0						; Hitting ESC resets it all
	jne start
	
	cmp word [num_buffer], 1					; Switch Case with the result of read_int
	je key_to_floppy
	cmp word [num_buffer], 2
	je floppy_to_ram
	cmp word [num_buffer], 3
	je ram_to_floppy
	
	jmp get_option								; If none of these values, jump to start


key_to_floppy:
	call cursor_newline
	mov word [print_addr], str_prompt
	call print_str
	
	mov si, str_buffer
	call read_str
	
	call cursor_newline
	mov word [print_addr], repeat_prompt
	call print_str

; might add this label to read_sts function
k2f_repeat_read:
	call clear_current_line
	mov byte [char_count], 5
	call read_int
	
	cmp word [num_buffer], 1					; Min 1 repeat
	jl k2f_repeat_read
	
	cmp word [num_buffer], 30000				; Max 30000 repeats
	jg k2f_repeat_read
	
	cmp byte [ret_val], 2						; Overflow (val > 32767)
	je k2f_repeat_read
	
	cmp byte [ret_val], 1						; ESC hit
	je start
	
	mov ax, word [num_buffer]
	mov word [repeats], ax

	call cursor_newline
	call read_sts
	
	call str_to_floppy
	push ax
	call cursor_newline
	pop ax
	cmp ah, 0
	je key_to_floppy_success

key_to_floppy_fail:
	mov word [print_addr], ram_to_floppy_fail_msg
	push ax
	call print_str
	pop ax
	mov bl, ah
	call phex
	jmp key_to_floppy_end
	
key_to_floppy_success:
	mov word [print_addr], ram_to_floppy_success_msg
	call print_str

key_to_floppy_end:
	mov ah, 0x00
	int 0x16
	jmp start


floppy_to_ram:	
	call cursor_newline
	mov word [print_addr], repeat_prompt
	call print_str

floppy2ram_repeat:
	call clear_current_line
	mov byte [char_count], 5
	call read_int

	mov al, [num_buffer]
	mov [repeats], al

	cmp word [num_buffer], 1					; Min 1 repeat
	jl floppy2ram_repeat

	cmp word [num_buffer], 30000				; Max 30000 repeats
	jg floppy2ram_repeat

	cmp byte [ret_val], 2						; Overflow (val > 32767)
	je floppy2ram_repeat
	
	cmp byte [ret_val], 1						; ESC hit
	je start

	call cursor_newline
	call read_sts

	call cursor_newline
	call read_address

	cmp byte [ret_val], 1
	je start

	;setting up the interrupt
	mov ah, 0x02
	mov al, [repeats]
	mov ch, [track]
	mov cl, [sector]
	mov dl, 0
	mov dh, [side]
	mov bx, [segment_word]
	mov es, bx
	mov bx, [address_word]
	int 0x13
	push ax
	call cursor_newline
	pop ax
	cmp ah, 0
	jnz floppy2ram_error
floppy2ram_success:
	mov word [print_addr], floppy2ram_success_msg
	call print_str
	mov bx, [segment_word]
	mov es, bx
	mov bp, [address_word]
	call print_ram_sectors
	jmp start
floppy2ram_error:
	mov word [print_addr], floppy2ram_error_msg
	push ax
	call print_str
	pop ax
	mov bl, ah
	call phex
	mov ah, 0x00
	int 0x16
	jmp start

ram_to_floppy:
	call cursor_newline
	call read_address
	cmp byte [ret_val], 1
	je start

	call cursor_newline
	mov word [print_addr], byte_prompt
	call print_str
	call cursor_newline

ram_byte_count_read:
	call clear_current_line
	mov byte [char_count], 5
	call read_int

	cmp word [num_buffer], 1					; Min 1 byte
	jl ram_byte_count_read
	
	cmp byte [ret_val], 2						; Overflow (val > 32767)
	je ram_byte_count_read
	
	cmp byte [ret_val], 1						; ESC hit
	je start
	
	mov ax, word [num_buffer]
	mov word [byte_count], ax
	
	call cursor_newline
	call read_sts

	call ram_write_mem
	push ax
	call cursor_newline
	pop ax
	cmp ah, 0
	je ram_to_floppy_success

ram_to_floppy_fail:
	mov word [print_addr], ram_to_floppy_fail_msg
	push ax
	call print_str
	pop ax
	mov bl, ah
	call phex
	jmp key_to_floppy_end
	
ram_to_floppy_success:
	mov word [print_addr], ram_to_floppy_success_msg
	call print_str

ram_to_floppy_end:
	mov ah, 0x00
	int 0x16
	jmp start

times 510 - ($ - $$) db 0						; Pad to 510 bytes
dw 0xaa55										; Boot signature at byte 511, 512


; str_to_floppy - Write to the floppy a string repeated [repeats] times, one sector at a time
; Args: [Side], [Track], [Sector] - Floppy Disk Destination
;		[str_buffer] - String to be copied
;		[repeats] - Number of times to repeat the string to be copied
; Rets: AH - Error code

str_to_floppy:
	mov si, str_buffer
	mov di, floppy_buffer
	xor ax, ax

str_fill_buffer:
	cmp ax, 512							; Floppy Buffer full - stop copying
	je buffer_to_floppy
	cmp word [repeats], 0				; Remaining Repeats = 0 - stop copying as well
	je buffer_to_floppy
	mov bl, byte [si]					; Copy from str_buffer to floppy_buffer
	mov byte [di], bl
	inc ax								; Manage indices
	inc si
	inc di

	cmp byte [si], 0
	jne str_fill_buffer
	mov si, str_buffer					; If reached the end of original string, move SI back to start
	dec word [repeats]					; Reduce repeat counter

	jmp str_fill_buffer

buffer_to_floppy:
	mov ch, [track]						; Prepare data for the interrupt
	mov cl, [sector]
	mov dh, [side]
	xor dl, dl
	xor ax, ax
	mov es, ax
	mov bx, floppy_buffer
	mov ax, 0x0301
	int 0x13							; Copy 1 sector (floppy_buffer) to Floppy
	
	cmp ah, 0							; If error encountered, return early with error code
	jne str_to_floppy_end

	mov di, floppy_buffer				; Start from start of buffer, wipe it clean with 0s
floppy_buffer_clear:
	cmp byte [di], 0					; Exit loop if no more data to be erased
	je mov_floppy_write_pos
	mov byte [di], 0
	inc di
	cmp di, floppy_buffer + 512			; Exit loop if at the end of buffer
	je mov_floppy_write_pos
	jmp floppy_buffer_clear

mov_floppy_write_pos:
	cmp word [repeats], 0				; If no more repeats required, exit function
	je str_to_floppy_end

	inc byte [sector]					; Move to next sector
	cmp byte [sector], 19
	jl loop_continue

	mov byte [sector], 1				; If at max sector, flip sides
	inc byte [side]
	
	cmp byte [side], 2
	jl loop_continue
	
	mov byte [side], 0					; If used both sides, move to next track
	inc byte [track]
	
	cmp byte [track], 80
	je str_to_floppy_end

loop_continue:
	mov di, floppy_buffer				; Reinitialize data for next sector write
	xor ax, ax
	cmp byte [si], 0					; If SI is at a null terminator, go back to start of string
	jne str_fill_buffer
	mov si, str_buffer
	jmp str_fill_buffer					; Restart loop - exits when [repeats] are 0

str_to_floppy_end:
	ret

; ram_write_mem - Copies RAM memory from a specific address to Floppy
; Args: [Side], [Track], [Sector] - Floppy Disk Destination
;		[segment_word], [address_word] - RAM address to copy from
;		[byte_count] - Ammount of bytes to be copied
; Rets: AH - Error code
ram_write_mem:
	xor dx, dx
	mov ax, [byte_count]
	mov cx, 512
	div cx								; DX = count % 512, AX = count / 512
	
; TODO: Find a way to handle the partial copying of the last sector
	cmp dx, 0
	jne ram_copy_interrupt				; Don't copy the last sector too if there's nothing to copy from it
	dec ax

ram_copy_interrupt:
	inc ax
	mov ch, [track]						; Prepare data for the interrupt
	mov cl, [sector]
	mov dh, [side]
	xor dl, dl
	mov es, [segment_word]
	mov bx, [address_word]
	mov ah, 0x03
	int 0x13							; Copy AX full sectors to floppy
	
	cmp ah, 0							; If error encountered, return early with error code
	jne ram_write_over

	;pop ax
	;copy floppy_buffer to wherever the last sector's supposed to be

ram_write_over:
	ret

; print_str - Prints a string to screen, moves cursor to next line
; Args: String* set in print_addr
; Rets: Nothing
print_str:
	call get_cursor_pos
	mov si, [print_addr]
	
print_strlen:
	cmp byte [si], 0							; Get length of string - # of bytes until null termination
	je print_body
	inc si
	jmp print_strlen
	
print_body:
	sub si, [print_addr]
	mov bx, 0x0007								; Print the string using ax 1301
	mov cx, si
	mov ax, 0
	mov es, ax
	mov bp, [print_addr]
	mov ax, 0x1301
	int 0x10

	ret

; print_ram_sectors - prints the whole ram sector that was 
; args - [side], [track], [sector], [repeats], [segment_word], [address_word] (address word will be affected)
print_ram_sectors:
print_ram_sectors_for_init:
	mov di, 0
print_ram_sectors_for_cond:
	xor ax, ax
	mov al, byte [repeats]
	cmp di, ax
	jae print_ram_sectors_end
print_ram_sectors_for:
	call clear_screen
	mov word [print_addr], side_str
	call print_str
	xor ax, ax
	mov al, [side]
	push ax
	call pnum
	mov word [print_addr], track_str
	call print_str
	xor ax, ax
	mov al, [track]
	push ax
	call pnum
	mov word [print_addr], sector_str
	call print_str
	xor ax, ax
	mov al, [track]
	push ax
	call pnum
	mov word [print_addr], segadr_str
	call print_str
	push word [segment_word]
	call phex16
	mov ah, 0x0e
	mov al, ':'
	int 0x10
	push word [address_word]
	call phex16
	call cursor_newline
	mov word [print_addr], press_space
	call print_str
	mov ax, 0x1301
	mov bx, [segment_word]
	mov es, bx
	mov bx, 0x0007
	mov cx, 512
	mov dx, 0x0200
	mov bp, [address_word]
	int 0x10
	inc di
	inc byte [sector]
	add word [address_word], 512
print_ram_sectors_keyboard_check:
	mov ah, 0x00
	int 0x16
	cmp ah, 0x01		;escape hit
	je print_ram_sectors_end
	cmp al, 0x20		;space hit
	jne print_ram_sectors_keyboard_check
	jmp print_ram_sectors_for_cond
print_ram_sectors_for_end:
print_ram_sectors_end:
	ret

; read_str - Reads a string of up to 256 chars
; Args: none
; Rets: str_buffer - Input string

read_str:
	mov ah, 0
	int 0x16									; Read Next Keystroke

	cmp ah, 0x0e								; AH = 0x0e -> BKSP pressed
	je read_str_bksp
	
	cmp ah, 0x1c								; AH = 0x1c -> ENTER pressed
	je read_str_enter
	
	cmp al, 0x20								; If ASCII < 0x20, do not try to print (Control characters)
	jl read_str
	cmp al, 0x7f								; Don't try to print [DEL]
	je read_str

	cmp si, str_buffer + 256					; If buffer is at max size (256), ignore further inputs
	je read_str
	mov [si], al
	inc si
	
	mov ah, 0xe									; Echo any valid characters to screen
	int 10h
 
	jmp read_str								; Always read for keyboard inputs

read_str_bksp:
	cmp si, str_buffer							; If buffer isn't empty...
	je read_str									; If it is, don't do anything
	dec si
	mov byte [si], 0							; Eliminate last char in buffer

	call get_cursor_pos

	mov ah, 0x02
	cmp dl, 0									; If cursor is at y=0...
	jz prev_line								; Move cursor to previous line
	dec dl
	jmp overwrite_char

prev_line:
	mov dl, 79
	dec dh

overwrite_char:
	int 0x10									; Set cursor pos
	
	mov ax, 0x0a20								; 20h in ASCII = ' ' (Space)
	mov cx, 1									; Write only 1 space
	int 0x10
	jmp read_str
	
read_str_enter:
	ret

; read_int - Reads an integer of specifed size
; Args: char_count - Digit number (max 15)
; Rets: num_buffer - Input number
;		ret_val - 0 for success
;				- 1 for early ESC exit
;				- 2 for Overflow (>32767)

read_int:
	mov byte [ret_val], 0
	mov word [num_buffer], 0
	mov byte [curr_digits], 0
	xor cx, cx

read_int_input:
	xor ah, ah									; Get a key input
	int 0x16
	
	cmp ah, 0x01								; If ESC is hit, break loop early, return flag
	je read_int_esc_end
	
	cmp ah, 0x0e								; If BKSP is hit, delete last char, adjust value
	je read_int_bksp
	
	cmp ah, 0x1c								; If ENTER is hit, break loop normally
	je read_int_buffer_check
	
	mov cl, byte [curr_digits]
	cmp cl, byte [char_count]					; Check if max digit count reached
	je read_int_input
	
	cmp al, 0x30								; If less than 0 in ASCII, don't consider it
	jl read_int_input
	cmp al, 0x39								; If greater than 9 in ASCII, don't consider it
	jg read_int_input
	
	mov ah, 0x0e								; Print valid char to screen
	mov bl, 0
	int 0x10
	
	sub al, 0x30								; Get the digit itself
	mov cl, al									; Store new digit in CL
	
	mov ax, word [num_buffer]					; Digits are entered in reverse order
	mov dx, 10
	mul dx										; Multiply existing value by 10
	cmp dx, 0
	jg read_int_overflow
	
	add ax, cx									; Add it to the total
	mov word [num_buffer], ax					; Save result in buffer
	inc byte [curr_digits]						; Update digit count
	jmp read_int_input

read_int_bksp:
	cmp byte [curr_digits], 0					; If buffer is empty, don't do anything
	je read_int_input
	dec byte [curr_digits]
	
	mov ax, word [num_buffer]
	mov cx, 0xa									; Divide by 10, getting rid of last digit
	mov dx, 0
	div cx										; DX = num % 10, AX = num / 10
	mov word [num_buffer], ax
	
	call get_cursor_pos
	
	dec ah										; Move cursor to previous char
	dec dl
	int 0x10
	
	mov ax, 0x0a20								; Overwrite char at cursor with a space
	mov cx, 1									; Write once
	int 0x10
	jmp read_int_input							; Go back to reading input

read_int_buffer_check:
	cmp byte [curr_digits], 0
	jg read_int_end
	jmp read_int

read_int_overflow:
	inc byte [ret_val]							; Flag=2 when starting from here
read_int_esc_end:
	inc byte [ret_val]							; Set ESC flag
read_int_end:
	ret

; cursor_newline - move the cursor to the next line, scrolling included
; Args: none
; Rets: none

cursor_newline:
	call get_cursor_pos

	cmp dh, 24									; Check if on last line of terminal
	jl newline_scroll_skip
	
	mov ax, 0x0601								; Scroll down 1 line if needed
	mov cx, 0
	mov dx, 0x184f
	int 0x10
	mov dh, 0x17

newline_scroll_skip:
	mov ah, 0x02								; Move cursor to next line
	inc dh
	mov dl, 0
	int 0x10
	ret

; clear_current_line - erase all characters on the line the cursor is on, move cursor to line start
; Args: none
; Rets: none

clear_current_line:
	call get_cursor_pos
	
	mov ax, 0x0600								; Don't scroll, just clear entire line
	mov bh, 0x07
	mov ch, dh
	xor cl, cl
	mov dl, 0x4f
	int 0x10
	
	mov ah, 0x02
	mov bh, 0
	mov dl, 0
	int 0x10
	ret

; get_cursor_pos - Get current cursor position using int 0x10
; Args - none
; Rets - none

get_cursor_pos:
	mov ah, 0x03
	mov bh, 0
	int 0x10
	ret 

; read_address - prints "Segment:Address? ____:____" prompt, must be completed to return
; Args - none
; Rets - segment_word - value of the segment input
;		 address_word - value of the address input
;		 ret_val - 0 for success
;					1 for Escape

read_address:
    mov ax, 0x1300
    mov bl, 0x07
    mov cx, address_help_length
    mov bp, address_help
    int 0x10
	call cursor_newline
	mov ax, 0x1300
	mov bl, 0x07
	mov cx, address_space_length
	mov bp, address_space
	int 0x10
    mov di, segment_buffer
read_address_input:
    mov ah, 0x00
    int 0x16

    cmp ah, 0x0e
    je read_address_input_bksp

    cmp ah, 0x1c
    je read_address_input_enter

    cmp ah, 0x01
    je read_address_input_esc

    cmp al, 0x20
    jae read_address_input_default

    jmp read_address_input

read_address_input_bksp:
    cmp di, segment_buffer
    je read_address_input
    mov ah, 0x03
    int 0x10
    dec dl
    cmp di, address_buffer
    jne read_address_input_bksp1
    dec dl
read_address_input_bksp1:
    mov ah, 0x02
    int 0x10
    mov ah, 0x0a
    mov al, '_'
    mov bh, 0
    mov cx, 1
    int 0x10
    mov [di], byte 0
    dec di
    jmp read_address_input

read_address_input_enter:
    cmp di, address_buffer+4
    jne read_address_input

read_address_process_input:
    mov di, segment_buffer
    mov si, segment_word
read_address_process_cond:
    cmp di, segment_buffer+8
    je read_address_process_input_for_end
    mov al, [di+2]
    shl al, 4
    or al, [di+3]
    mov ah, [di]
    shl ah, 4
    or ah, [di+1]
    mov word [si], ax
    add di, 4
    add si, 2
    inc bl
    jmp read_address_process_cond
read_address_process_input_for_end:
	mov byte [ret_val], 0
	ret

read_address_input_esc:
    mov byte [ret_val], 1
    ret

read_address_input_default:
    cmp di, address_buffer+4
    je read_address_input
read_address_input_default_check_digit:
    cmp al, '0'-1
    jbe read_address_input_default_check_letter
    cmp al, '9'
    mov bl, '0'
    jbe read_address_input_default_check_positive
read_address_input_default_check_letter:
    cmp al, 'a'-1
    jbe read_address_input_default_check_negative
    cmp al, 'f'
    ja read_address_input_default_check_negative
    mov bl, 'a'-10
read_address_input_default_check_positive:
    mov ah, 0x0e
    int 0x10
    sub al, bl
    stosb
    cmp di, address_buffer
    jne read_address_input
read_address_input_default_move_cursor:
    mov ah, 0x03
    mov bh, 0
    int 0x10
    inc dl
    mov ah, 0x02
    int 0x10
read_address_input_default_check_negative:
    jmp read_address_input

; read_sts - calls all the prompts for side (or head), track, sector
; Args - None
; Rets - side
;		track
;		sector
read_sts:
	mov word [print_addr], side_prompt
	call print_str
read_sts_side:
	call clear_current_line
	mov byte [char_count], 1
	call read_int
	
	cmp byte [ret_val], 0						; Hitting ESC resets it all
	jne start
	
	mov al, [num_buffer]
	cmp al, 2									; Only accepted values are 0, 1
	jae read_sts_side
	
	mov [side], al
	
	call cursor_newline
	mov word [print_addr], track_prompt
	call print_str

read_sts_track:
	call clear_current_line
	mov byte [char_count], 2
	call read_int
	
	cmp byte [ret_val], 0						; Hitting ESC resets it all
	jne start
	
	mov al, [num_buffer]
	cmp al, 80									; Only accepted values are 0...79
	jae read_sts_track
	
	mov [track], al
	
	call cursor_newline
	mov word [print_addr], sector_prompt
	call print_str
	
read_sts_sector:
	call clear_current_line
	mov byte [char_count], 2
	call read_int
	
	cmp byte [ret_val], 0						; Hitting ESC resets it all
	jne start
	
	mov al, [num_buffer]
	cmp al, 0
	je read_sts_sector
	cmp al, 18									; Only accepted values are 1...18
	ja read_sts_sector

	mov [sector], al

read_sts_end:
	ret

clear_screen:
    mov ax, 0x0600
    mov bh, 0x07
    xor cx, cx
    mov dx, 0x184f
    int 0x10
    mov ah, 0x02
    mov bh, 0
    xor dx, dx
    int 0x10
    ret

;phex16 - function that prints hex word
;args - push word
;ret - none
phex16:
    ;[bp + 3] - argument1 high byte
    ;[bp + 2] - argument1 low byte
    mov bp, sp
    push ax
    mov ah, 0x0e

    mov al, byte [bp + 3]
    shr al, 4
    call phex16_p

    mov al, byte [bp + 3]
    and al, 0x0f
    call phex16_p

    mov al, byte [bp + 2]
    shr al, 4
    call phex16_p

    mov al, byte [bp + 2]
    and al, 0x0f
    call phex16_p

    pop ax
    ret 2

phex16_p:
    cmp al, 0x0a
    jae phex16_p_letter
    or al, 0x30
    jmp phex16_p_end
phex16_p_letter:
    add al, 0x37
phex16_p_end:
    int 0x10
    ret

;phex - function that prints hex byte
;Args : bl - hex byte to be printed
;Rets : None
phex:

    push ax
    mov ah, 0x0e

	mov al, bl
    shr al, 4
    call phex_p

    mov al, bl
    and al, 0x0f
    call phex_p

    mov al, ' '
    int 0x10
    pop ax
    ret 2

phex_p:
    cmp al, 0x0a
    jae phex_p_letter
    or al, 0x30
    jmp phex_p_end
phex_p_letter:
    add al, 0x37
phex_p_end:
    int 0x10
    ret

;push argument to be printed
pnum:
    mov bp, sp
	xor dx, dx
    mov ax, word [bp + 2]
    mov bx, ax
    cmp ax, 10000
    jae pnum_5
    cmp ax, 1000
    jae pnum_4
    cmp ax, 100
    jae pnum_3
    cmp ax, 10
    jae pnum_2
    jmp pnum_1

pnum_5:
    mov cx, 10000
    div cx
    xor ax, 0x0e30
    int 0x10
    xor ax, 0x0e30
    mul cx
    sub bx, ax
    mov ax, bx
pnum_4:
    mov cx, 1000
    div cx
    xor ax, 0x0e30
    int 0x10
    xor ax, 0x0e30
    mul cx
    sub bx, ax
    mov ax, bx
pnum_3:
    mov cx, 100
    div cx
    xor ax, 0x0e30
    int 0x10
    xor ax, 0x0e30
    mul cx
    sub bx, ax
    mov ax, bx
pnum_2:
    mov cx, 10
    div cx
    xor ax, 0x0e30
    int 0x10
    xor ax, 0x0e30
    mul cx
    sub bx, ax
    mov ax, bx
pnum_1:
    xor ax, 0x0e30
    int 0x10
pnum_end:
    mov ax, 0x0e00
    int 0x10
    ret 2

exit:

%macro define_string 2

    %1 db %2
    %1_length equ $-%1

%endmacro
option_pick_str db "1. Keyboard to Floppy", 0x0d, 0x0a, "2. Floppy to RAM", 0x0d, 0x0a, "3. RAM to Floppy", 0x0d, 0x0a
escape_str db "Press [ESC] to Cancel", 0x0d, 0x0a, 0
str_prompt db "Input Text", 0x0d, 0x0a, 0
repeat_prompt db "Repeat Count? [1-30000]", 0x0d, 0x0a, 0
side_prompt db "Side? [0-1]", 0x0d, 0x0a, 0
track_prompt db "Track? [0-79]", 0x0d, 0x0a, 0
sector_prompt db "Sector? [1-18]", 0x0d, 0x0a, 0
byte_prompt db "Byte Count? [1-32767] (Rounded up to multiples of 512)", 0
floppy2ram_success_msg db "Floppy to RAM reading succesful, press [SPACE] to view", 0
floppy2ram_error_msg db "Floppy to RAM reading failed with erorr code: ", 0
ram_to_floppy_success_msg db "Writing from RAM succesful!", 0
ram_to_floppy_fail_msg db "Writing from RAM failed with erorr code: ", 0
side_str db "Side: ", 0
track_str db "Track: ", 0
sector_str db "Sector: ", 0
segadr_str db "Seg:Adr: ", 0
press_space db "Press [SPACE] for next page", 0
repeats dw 0
byte_count dw 0
side db 0					; return value of read_sts
track db 0					; return value of read_sts
sector db 0					; return value of read_sts
print_addr dw 0
char_count db 0
curr_digits db 0
num_buffer dw 0
;segment_word and address_word must be right one after the other in the memory like this, don't change positions
segment_word dw 0   		; segment hex value, is changed in read_address function
address_word dw 0   		; address hex value, is changed in read_address function

ret_val db 0				; return value of the process, 0 = success, 1 = escape pressed, 2+ = other error
define_string address_help, "Segment:Address? "
define_string address_space, "____:____"
;segment_buffer and address_buffer must be right one after the other in the memory like this, don't change positions
segment_buffer times 4 db 0
address_buffer times 4 db 0
str_buffer times 256 db 0
floppy_buffer times 512 db 0 ; Declared for convenience