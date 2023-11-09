org 0x7c00									; Hard offset - this is where the boot sector begins

; Int 10h ax 00h - Set Video Mode
mov al, 0x3									; 80x25 text mode
xor ah, ah									; AH = 0, Set Video Mode
int 0x10

copy_memory:
	mov ah, 0x02
	mov al, 4								; Read 4 sectors
    mov cx, 2           					; ch = 0 - cylinder, cl = 2 - sector number
	mov dh, 0								; Head #0
	mov dl, 0								; Drive: Diskette
	mov bx, 0
    mov es, bx
    mov bx, 0x7e00   						; Write to RAM starting from 0:7e00 - keep code contiguous
    int 0x13								; Read Sectors, Load to RAM

	mov ah, 0x02							; Move cursor 1 line above screen - Echo moves 1 line below by default
	mov bh, 0
	mov dh, -1
	mov dl, 0
	int 0x10

print_prompt_prefix:
	mov word [cpy_addr], prompt_prefix
	call cpy_str_to_buffer
	
	mov word [echo_attr], 0x0c
	mov byte [go_next_line], 0
	call echo_text
	
read_key:
	mov ah, 0
	int 0x16

	cmp ah, 0x0e							; AH = 0x0e -> BKSP pressed
	je command_bksp
	cmp ah, 0x1c							; AH = 0x1c -> ENTER pressed
	je command_enter
	
	cmp al, 0x20							; If ASCII < 0x20, do not try to print (Control characters)
	jl read_key
	cmp al, 0x7f							; Don't try to print [DEL]
	je read_key

	cmp si, command_buffer + 256			; If buffer is at max size (256), ignore further inputs
	je read_key
	mov [si], al
	inc si

	mov ah, 0x09							; Print the scanned char at cursor location
	mov bl, 0x07
	mov cx, 1
	int 10h
	
	mov ah, 0x03							; Get current cursor location
	mov bh, 0
	int 0x10								; DX will store (x,y) coordinates [DH = y, DL = x]

	mov ah, 0x02							; Move cursor either to next column or next row, if at end of row
	cmp dl, 79
	jl set_prompt_cursor
	inc dh
	mov dl, -1
	
set_prompt_cursor:	
	inc dl
	int 0x10

	cmp dh, 24								; If at the bottom-right corner...
	jl read_key
	
	cmp dl, 79
	jl read_key
	
	mov ah, 0x06							; Scroll down once to make space for the string
	mov al, 1
	mov bh, 0x07							; Draw new line as White on Black
	mov cx, 0								; (0,0): Top-left corner of the screen
	mov dx, 0x184f							; (79,24): Bottom-right corner of the screen
	int 0x10								; Scroll Up / Clear Screen Rectangle
	
	mov ah, 0x02							; Move the cursor in its corresponding position
	mov bh, 0
	mov dx, 0x174f							; (79,23): 1 row above bottom right, where current input end is
	int 0x10
	
	jmp read_key

command_bksp:
	cmp si, command_buffer					; If buffer isn't empty...
	je read_key								; If it is, don't do anything
	dec si
	mov byte [si], 0						; Eliminate last char in buffer
	
	mov ah, 0x03							; Int 10h 03h: Query Cursor Position and Size
	mov bh, 0
	int 0x10

	cmp dl, 0								; If cursor is at y=0...
	jz prev_line							; Move cursor to previous line

	mov ah, 0x02							; Else, move cursor to previous char
	dec dl
	int 0x10								; Int 10h 02h: Set Cursor Position
	jmp overwrite_char

prev_line:
	mov ah, 0x02
	mov dl, 79
	dec dh
	int 0x10								; Int 10h 02h: Set Cursor Position

overwrite_char:
	mov ah, 0xa								; Overwrite existing character
	mov al, 0x20							; 20h in ASCII = ' ' (Space)
	mov cx, 1								; Write only 1 space
	int 0x10								; Int 10h 0eH: Write Character to Cursor Location
	jmp read_key							; Go back to reading input

command_enter:
	cmp si, command_buffer
	je print_prompt_prefix
	
	mov ecx, command_array					; ECX will store comparison string array index
	sub ecx, 4								; Prepare ECX for first iteration

command_check_next:
	add ecx, 4
	
	cmp dword [ecx], 0						; If current string is null, no matching command found
	je command_err
	
	mov edi, [ecx]							; EDI - Get address to string from string array
	mov si, command_buffer					; Set SI as 1st character of buffer

command_check_loop:
	cmp byte [si], 0x20						; Reaching first space delimitation in buffer...
	je command_length_check	
	
	cmp byte [si], 0						; Reaching end of buffer...
	je command_length_check

	cmp byte [edi], 0						; Too long to match reference command
	je command_check_next

	mov bl, [si]							; Auxiliary register
	cmp bl, [edi]							; Compare the commands, character by character
	jne command_check_next

	inc si
	inc edi
	
	jmp command_check_loop

command_length_check:
	cmp byte [edi], 0						; Check if command and buffer string end at the same spot
	jne command_check_next
	
	add ecx, command_addresses
	sub ecx, command_array					; On success, get offset from cx
	
	cmp word [ecx], echo_text
	jne command_call
	
	mov di, command_buffer + 5				; Overwrite "echo " with argument
	mov si, command_buffer

echo_overwrite:
	mov bl, [di]							; Loop to shift buffer 5 chars to left (to not leave empty space)
	mov [si], bl
	
	inc si
	inc di
	cmp byte [di], 0
	jne echo_overwrite

	mov dword [si], 0						; Overwrite the 5 empty bytes "echo " was holding with 0s
	add si, 4
	mov byte [si], 0
	
command_call:
	mov word [echo_attr], 0x0f
	mov byte [go_next_line], 1
	call dword [ecx]						; Jump to corresponding part of code using offset
	jmp print_prompt_prefix

command_err:
	mov word [cpy_addr], command_err_text
	call cpy_str_to_buffer
	
	mov word [echo_attr], 0x04
	mov byte [go_next_line], 1
	call echo_text
	jmp print_prompt_prefix

echo_text:
	inc si
	cmp byte [si], 0						; Move SI to the end of the string in buffer
	jne echo_text

	mov ah, 0x03
	mov bh, 0
	int 0x10								; DX will store (x,y) coordinates [DH = y, DL = x]

	sub si, command_buffer					; If buffer is empty, don't print anything
	jz clear_buffer							; Just write a new line instead
	
	cmp dh, 24
	jl print_echo
	
	mov ah, 0x06							; Scroll down once to make space for the string
	mov al, 1
	mov bh, 0x07							; Draw new line as White on Black
	mov cx, 0								; (0,0): Top-left corner of the screen
	mov dx, 0x184f							; (79,24): Bottom-right corner of the screen
	int 0x10								; Scroll Up / Clear Screen Rectangle
	mov dh, 0x17							; Move cursor 1 line above target
	
	cmp byte [stay_on_line], 1
	jne print_echo
	mov ah, 0x03
	mov bh, 0
	int 0x10
	dec dh
	
print_echo:
	mov bh, 0 								; Video page number.
	mov ax, 0
	mov es, ax 								; ES:BP is the pointer to the buffer
	mov bp, command_buffer

	mov bl, [echo_attr]						; Custom attribute
	mov cx, si								; String length
	
	dec dl
	cmp byte [stay_on_line], 1				; If stay_on_line == 1, print string from current cursor position
	je write_echo
	
	inc dh									; y coordinate
	mov dl, 0								; x coordinate
	jmp write_echo

write_echo:
	mov ax, 0x1301							; Write mode: character only, cursor moved
	int 0x10								; Int 10h 13001H: Display String & Update Cursor

clear_buffer:
	mov si, command_buffer

clear_buffer_loop:
	mov byte [si], 0						; Replace every non 0 byte to 0 in the buffer
	inc si
	cmp byte [si], 0
	jne clear_buffer_loop
	mov si, command_buffer
	ret

cpy_str_to_buffer:
	call clear_buffer
	mov di, [cpy_addr]
	mov si, command_buffer
str_set_buffer: 
	mov bl, [di]
	mov byte [si], bl
	inc si
	inc di
	cmp byte [di], 0
	jne str_set_buffer
	ret

times 510 - ($ - $$) db 0					; Pad to 510 bytes
dw 0xaa55									; Boot signature at byte 511, 512

; Sector 2 - 0x7e00 - Extra Commands
about:
	mov word [cpy_addr], about_name
	call cpy_str_to_buffer
	mov word [echo_attr], 0x04
	mov byte [go_next_line], 0
	call echo_text
	
	mov word [cpy_addr], about_name_desc
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0c
	mov byte [go_next_line], 1
	mov byte [stay_on_line], 1
	call echo_text
	
	mov word [cpy_addr], about_version
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0d
	mov byte [stay_on_line], 0
	call echo_text
	
	mov word [cpy_addr], about_release
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0d
	call echo_text
	
	mov word [cpy_addr], about_author
	call cpy_str_to_buffer
	mov word [echo_attr], 0x03
	mov byte [go_next_line], 0
	call echo_text
	
	mov word [cpy_addr], about_author_name
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0b
	mov byte [stay_on_line], 1
	call echo_text
	ret

help:
	mov word [cpy_addr], help_text
	call cpy_str_to_buffer
	mov word [echo_attr], 0x02
	mov byte [go_next_line], 0
	call echo_text
	
	mov word [cpy_addr], help_help
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0e
	mov byte [stay_on_line], 0
	call echo_text
	
	mov word [cpy_addr], help_help_desc
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	mov byte [stay_on_line], 1
	mov byte [go_next_line], 1
	call echo_text
	
	mov word [cpy_addr], help_echo
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0e
	mov byte [stay_on_line], 0
	call echo_text
	
	mov word [cpy_addr], help_echo_args
	call cpy_str_to_buffer
	mov word [echo_attr], 0x06
	mov byte [stay_on_line], 1
	call echo_text
	
	mov word [cpy_addr], help_echo_desc
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	mov byte [stay_on_line], 1
	mov byte [go_next_line], 1
	call echo_text
	
	mov word [cpy_addr], help_about
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0e
	mov byte [stay_on_line], 0
	call echo_text
	
	mov word [cpy_addr], help_about_desc
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	mov byte [stay_on_line], 1
	mov byte [go_next_line], 1
	call echo_text
	
	mov word [cpy_addr], help_ascii
	call cpy_str_to_buffer
	mov word [echo_attr], 0x0e
	mov byte [stay_on_line], 0
	call echo_text
	
	mov word [cpy_addr], help_ascii_desc
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	mov byte [stay_on_line], 1
	mov byte [go_next_line], 1
	call echo_text
	ret

ascii:
	mov word [cpy_addr], ascii_row_1
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	mov byte [stay_on_line], 0
	mov byte [go_next_line], 1
	call echo_text

	mov word [cpy_addr], ascii_row_2
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	call echo_text
	
	mov word [cpy_addr], ascii_row_3
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	call echo_text
	
	mov word [cpy_addr], ascii_row_4
	call cpy_str_to_buffer
	mov word [echo_attr], 0x07
	call echo_text

ascii_loop:
	cmp byte [ascii_buffer + 1], 127
	je ascii_break
	
	mov word [cpy_addr], ascii_buffer
	call cpy_str_to_buffer
	
	mov word [echo_attr], 0x07
	mov byte [stay_on_line], 1
	mov byte [go_next_line], 0
	
	mov bl, 7
	and bl, byte [ascii_buffer + 1]
	cmp bl, 7
	jne ascii_call
	mov byte [go_next_line], 1
	mov byte [stay_on_line], 0

ascii_call:
	call echo_text
	
	inc byte [ascii_buffer + 1]				; Increment last 3 digits as "Counter"
	inc byte [ascii_buffer + 7]
	cmp byte [ascii_buffer + 7], 0x3a
	jl ascii_loop
	
	mov byte [ascii_buffer + 7], 0x30
	inc byte [ascii_buffer + 6]
	cmp byte [ascii_buffer + 6], 0x3a
	jl ascii_loop
	
	mov byte [ascii_buffer + 6], 0x30
	inc byte [ascii_buffer + 5]
	jmp ascii_loop

ascii_break:
	mov byte [ascii_buffer + 1], 0
	mov byte [ascii_buffer + 5], 0x30
	mov byte [ascii_buffer + 6], 0x30
	mov byte [ascii_buffer + 7], 0x30
	ret


align 512

; Sector 3 - 0x8000 - Variables
echo_attr db 0x0f
stay_on_line db 0
go_next_line db 0
prompt_prefix db "KAOS>",0
command_err_text db "Unknown command",0
cpy_addr dw 0x0000

command_0 db "echo", 0
command_1 db "about", 0
command_2 db "ascii", 0
command_3 db "help", 0
command_array dd command_0, command_1, command_2, command_3, 0	; List of 4 byte addresses of each string
command_addresses dd echo_text, about, ascii, help				; List of 4 byte addresses of other jmp addresses

about_name db "KAOS", 0
about_name_desc db ": Kernel Application Operating System", 0
about_version db "Version 0.0.1", 0
about_release db "Released: 09/11/2023", 0
about_author db "With ", 0x03, " by ", 0
about_author_name db "<Random", 0xfe, "Researchist>", 0

help_text db "The following commands are supported, any unmentioned arguments are ignored.",0
help_help db "help",0
help_help_desc db ": Show this text", 0
help_echo db "echo", 0
help_echo_args db " [string]", 0
help_echo_desc db ": Display a given line of text", 0
help_about db "about", 0
help_about_desc db ": Show general system information", 0
help_ascii db "ascii", 0
help_ascii_desc db ": Show the ASCII table",0
align 512

; Sector 4 - 0x8200 - ASCII control characters & buffer

ascii_row_1 db 0xba,"NUL 000",0xba,"SOH 001",0xba,"STX 002",0xba,"ETX 003",0xba,"EOT 004",0xba,"ENQ 005",0xba,"ACK 006",0xba,"BEL 007", 0
ascii_row_2 db 0xba,"BS  008",0xba,"HT  009",0xba,"LF  010",0xba,"VT  011",0xba,"FF  012",0xba,"CR  013",0xba,"SO  014",0xba,"SI  015", 0
ascii_row_3 db 0xba,"DLE 016",0xba,"DC1 017",0xba,"DC2 018",0xba,"DC3 019",0xba,"DC4 020",0xba,"NAK 021",0xba,"SYN 022",0xba,"ETB 023", 0
ascii_row_4 db 0xba,"CAN 024",0xba,"EM  025",0xba,"SUB 026",0xba,"ESC 027",0xba,"FS  028",0xba,"GS  029",0xba,"RS  030",0xba,"US  031", 0
ascii_buffer db 0xba, 0x1f, 0x20, 0x20, 0x20, 0x30, 0x33, 0x32, 0

; Sector 5 - 0x8400 - All-purpose Command Buffer
command_buffer times 256 db 0x0, 0
align 512