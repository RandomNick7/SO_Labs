org 0x8000									; Offset - Specific place where Kernel's supposed to begin
dw 0x1234

mov ah, 0x01								; Show the cursor
mov cx, 0x0e0f								; Cursor starts at Row 15, ends at 15
int 0x10

mov ax, 0x0305								; Set repeat rate & delay
xor bx, bx									; Delay 250 ms, repeat 30 Hz
int 0x16

call clear_screen

main_loop:
	call print_prefix
	call read_str
	call go_next_line

	call check_command
	jmp main_loop



; print_prefix - Prints the terminal prefix
; In - None
; Out - None
; Affects: AX, BH, CX, DX, SI, BP

print_prefix:
	mov bl, 0x0c
	mov bp, prompt_prefix
	call print_str
	ret


; check_command - Checks if input string is a command, executes it if possible
; In - None
; Out - None
; Affects: AX, BX, CX, DX, SI, DI, BP

check_command:
	cmp byte [command_buffer], 0			; If no command was input, just print an empty line
	jne check_command_body
	ret

check_command_body:
	mov si, command_arr_str

check_command_loop:
	mov bp, command_buffer
	mov di, [si]

	cmp di, 0								; If at end of command list, print an error
	je check_command_err

check_command_cmp:
	mov dl, byte [di]						; DL = char within command string
	mov bl, byte [bp]						; BL = char within input string

	cmp bl, 0								; If matching until end/first space, check if input is a valid command
	je check_command_success
	
	cmp bl, 0x20
	je check_command_success
	
	cmp dl, bl								; Check if string matches command
	jne check_command_next

	inc di									; Increment string indices
	inc bp

	jmp check_command_cmp

check_command_next:
	add si, 2								; Move to address of next string
	jmp check_command_loop

check_command_success:
	cmp dl, 0								; Check if string ends correspond
	jne check_command_next

	sub si, command_arr_str					; Use SI as index of the function address array
	add si, command_arr_addr
	call [si]								; Call matching command
	call clear_buffer
	ret

check_command_err:
	call clear_buffer
	mov bl, 0x04							; 0x04 - Red on Black
	mov bp, command_err
	call print_str							; Print the error
	call go_next_line
	ret


; clear_buffer - replaces the contents of command_buffer with 0s
; In - None
; Out - None
; Affects - SI

clear_buffer:
	mov si, command_buffer
clear_buffer_loop:
	mov byte [si], 0						; Write 0 in the buffer where there isn't one
	inc si
	cmp byte [si], 0						; Stop when finding a 0 - the rest of the buffer is already empty
	jne clear_buffer_loop
	ret


; echo_str - prints its argument on-screen
; In - None
; Out - None
; Affects - AX, BX, CX, DX, SI, BP

echo_str:
	mov bl, 0x0f							; Bright White color
	mov bp, command_buffer + 5				; Print whatever's in the space-delimited argument, if it exists
	call print_str
	call go_next_line
	ret

; print_str_sequence - Prints a sequence of strings with respective colors
; In - BP - Address of string address array; DI - Address of color address array
; Out - None
; Affects - AX, BX, CX, DX, SI, DI, BP

print_str_seq:
	cmp word [bp], 0
	je print_str_seq_end
	
	cmp word [bp], 1						; If current address is a 1, go to next line
	je print_str_new_line
	
	push bp
	mov bp, word [bp]						; De-reference address to get string
	mov bl, byte [di]						; Get color value from DI
	call print_str
	pop bp
	inc di									; Go to next color
	jmp print_str_seq_iter
	
print_str_new_line:
	call go_next_line
print_str_seq_iter:
	add bp, 2								; Go to next string address
	jmp print_str_seq
	
print_str_seq_end:
	ret


; about - Prints system information
; In - None
; Out - None
; Affects - AX, BX, CX, DX, SI, DI, BP

about:
	mov bp, about_str_seq
	mov di, about_str_col
	call print_str_seq
	ret


; help - Prints information about other commands
; In - None
; Out - None
; Affects - AX, BX, CX, DX, SI, DI, BP

help:
	mov bp, help_str_seq
	mov di, help_str_col
	call print_str_seq
	ret


; help - Prints information about latest changes
; In - None
; Out - None
; Affects - AX, BX, CX, DX, SI, DI, BP

changelog:
	mov bp, changelog_str_seq
	mov di, changelog_str_col
	call print_str_seq
	ret

; Both methods below are naive, but they work well enough for current purposes

; hex_to_bcd - Convert an 8 bit number to Binary Coded Decimal
; In - SI: Number in hex format
; Out - DI: Number in dec format
; Affects - None

hex_to_bcd:
	xor di, di
	push si

hex_to_bcd_100_loop:
	cmp si, 0x64
	jb hex_to_bcd_10
	sub si, 0x64							; Count hundreds
	inc di
	jmp hex_to_bcd_100_loop

hex_to_bcd_10:
	shl di, 4

hex_to_bcd_10_loop:
	cmp si, 0x0a
	jb hex_to_bcd_units
	sub si, 0x0a							; Count tens
	inc di
	jmp hex_to_bcd_10_loop

hex_to_bcd_units:
	shl di, 4								; Copy units
	add di, si

	pop si
	ret

; bcd_to_hex - Convert a 16 bit BCD to a hex value
; In - SI: Number in dec format
; Out - DI: Number in hex format
; Affects - None

bcd_to_hex:
	xor di, di
	push si

bcd_to_hex_1000:
	cmp si, 0x0999
	jb bcd_to_hex_100
	sub si, 0x1000
	add di, 0x03e8
	jmp bcd_to_hex_1000

bcd_to_hex_100:
	cmp si, 0x0099
	jb bcd_to_hex_10
	sub si, 0x0100
	add di, 0x0064
	jmp bcd_to_hex_100
	
bcd_to_hex_10:
	cmp si, 0x0009
	jb bcd_to_hex_units
	sub si, 0x0010
	add di, 0x000a
	jmp bcd_to_hex_10

bcd_to_hex_units:
	add di, si
	pop si
	ret

; print_bcd - Print a 3 digit BCD ("000"-"999")
; In - DI: Number in dec format
; Out - None
; Affects - AX

print_bcd:
	mov ax, di
	and ax, 0x0f00							; Print hundreds
	shr ax, 8
	add al, 0x30
	mov ah, 0x0e
	int 0x10

	mov ax, di
	and ax, 0x00f0							; Print tens
	shr ax, 4
	add al, 0x30
	mov ah, 0x0e
	int 0x10

	mov ax, di
	and ax, 0x000f							; Print units
	add al, 0x30
	mov ah, 0x0e
	int 0x10
	ret

; print_bcd_cal - Print a colored 2 digit BCD ("00"-"99"). Made specifically for the Calendar
; In - DI: Number in dec format, BL - Color, DX - Current cursor position
; Out - None
; Affects - None

print_bcd_cal:
	push ax
	push cx
	mov ax, di
	and ax, 0x00f0							; Print tens
	shr ax, 4
	add al, 0x30
	mov ah, 0x09
	mov cx, 0x0001
	int 0x10
	
	mov ah, 0x02							; Go to next char
	inc dl
	int 0x10

	mov ax, di
	and ax, 0x000f							; Print units
	add al, 0x30
	mov ah, 0x09
	mov cx, 0x0001
	int 0x10
	
	mov ah, 0x02							; Go to next date's spot
	add dl, 0x04
	int 0x10
	
	pop cx
	pop ax
	ret


; ascii - Print a table showing all ASCII characters (Extended included)
; In - None
; Out - None
; Affects - AX, BL, CX, DX, SI, DI

ascii:
	mov ah, 0x03
	int 0x10

	cmp dh, 0x04
	jle ascii_prep

	mov al, dh
	sub al, 0x04
	call scroll_lines						; If lower than 4 lines, scroll screen until 20 lines are free
	mov dx, 0x0400

ascii_prep:
	xor si, si
	mov cx, dx
	sub dh, ch

ascii_loop:
	add dh, ch
	mov ah, 0x02							; Set the cursor in the correct position
	int 0x10

	call hex_to_bcd
	call print_bcd

	mov ah, 0x0e							; Print a colon ':'
	mov al, 0x3a
	int 0x10

	push cx
	mov ax, si								; Print the ASCII character
	mov ah, 0x0a
	mov cx, 0x0001
	int 0x10
	pop cx
	
	cmp si, 0x00ff
	je ascii_end
	
	inc si
	inc dh
	
	sub dh, ch								; Go to next row
	cmp dh, 0x14
	jne ascii_loop
	
	sub dh, 0x14							; Go to next column
	add dl, 0x06
	
	jmp ascii_loop
	
ascii_end:
	mov dx, cx								; Move cursor below ASCII table
	add dh, 0x14
	mov ah, 0x02
	int 0x10
	ret

; print_char_seq - Prints a char a number of times in some color
; In - BP: Address of byte sequence "char, count, color"
; Out - None
; Affects - AX, BL, CL, DL

print_char_seq:
	mov ah, 0x09
	mov al, byte [bp]						; Get char, count and color at BP's address
	mov bl, byte [bp+1]
	mov cl, byte [bp+2]
	int 0x10
	
	mov ah, 0x02							; Move cursor 1 poition to the right
	add dl, cl
	int 0x10
	add bp, 3
	ret

; print_calendar_seq - Prints a specific sequence of chars with respective colors
; In - BP: address of sequence of "repeat, 4*(char, count, color)" array
; Out - None
; Affects - AX, BL, CX, DX, SI, DI, BP
print_calendar_seq:
	mov ah, 0x03							; Get cursor position
	int 0x10
	xor cx, cx
	
print_char_seq_line:
	mov al, byte [bp]
	test al, al								; If Repeats = 0, printing is complete
	jz print_char_seq_end
	xor ah, ah
	mov di, ax								; DI stores max count
	inc bp
	xor si, si								; SI stores repeat count
	
print_char_seq_loop:
	call print_char_seq
	push si
	xor si, si								; SI will be a counter for the next loop
	
print_calendar_seq_mid:
	call print_char_seq						; Print middle and delimiting sections 6 times
	call print_char_seq
	sub bp, 0x0006
	inc si
	cmp si, 0x06
	jl print_calendar_seq_mid
	
	call print_char_seq						; Print middle section one last time

	add bp, 0x0003
	call print_char_seq

	call go_next_line
	xor cx, cx
	
	pop si
	inc si
	
	cmp si, di								; If current repeats match max count, print the next line
	je print_char_seq_line

	sub bp, 0x000c							; Otherwise, print the same line again
	jmp print_char_seq_loop

print_char_seq_end:
	ret


; calendar - Start an interactive calendar
; In - None
; Out - None
; Affects - AX, BX, CX, DX, SI, DI, BP

calendar:
	mov ah, 0x03
	int 0x10

	cmp dh, 0x0c
	jle calendar_prep

	mov al, dh
	sub al, 0x0c
	call scroll_lines						; If lower than 12 lines, scroll screen until 12 lines are free
	mov dx, 0x0c00

	mov ah, 0x02
	int 0x10

calendar_prep:
	push dx
	mov bp, calendar_grid
	call print_calendar_seq					; Print the grid in blue
	pop dx

	mov ah, 0x02
	add dh, 0x03
	add dl, 0x02
	int 0x10								; Move the cursor in the bar for the weekdays

	mov bl, 0x07							; Print weekdays in light gray
	mov bp, calendar_weekdays
	xor di, di

calendar_weekday_loop:
	call print_str
	add bp, 0x0003							; Go to address of next string
	
	mov ah, 0x02
	add dl, 0x05
	int 0x10								; Move the cursor in the next box
	
	inc di
	cmp di, 0x0005
	jl calendar_weekday_loop
	mov bl, 0x0c							; Set color to Bright Red for Saturday & Sunday
	cmp di, 0x0007
	jl calendar_weekday_loop
	
calendar_number_prep:
	mov ah, 0x04							; Get current date in CX, DX - Used here for Year
	int 0x1a
	
	dec cx									; CX = Year - 1 in BCD format
	mov al, cl
	das
	mov cl, al
	cmp cl, 0x99
	jne calendar_number_formula
	dec ch
	mov al, ch
	das

calendar_number_formula:					; 01/01/<Current Year> Weekday: (1+5*(YYYY-1%4)+4*(YYYY-1%100)+6*(YYYY-1%400))%7
	mov si, cx
	call bcd_to_hex
	and di, 0x0003							; DI = (Year-1)%4 in Hex
	push di									; Store this value for determining if this year is a leap year later
	mov ax, di
	mov bl, 0x05
	mul bl
	mov dx, ax								; DX = 5*(Year-1)%4
	
	push si
	and si, 0x00ff
	call bcd_to_hex
	shl di, 2								; DI = 4*(Year-1)%100
	add dx, di
	
	pop si									; Load saved value into SI
	push si									; Store it in Stack once again for later
	shl si, 8
	call bcd_to_hex
	and di, 0x0003							; DI = ((Year-1)/100)%4

	pop si
	push di
	
	and si, 0x00ff
	call bcd_to_hex							; DI = (Year-1)%100
	pop ax
	add ax, di								; AX = (Year-1)%400
	push ax
	mov bx, 0x0006
	push dx
	mul bx
	pop dx
	add dx, ax								; DX = Sum of all above expressions
	
	mov ax, dx
	mov bl, 0x07
	div bl
	shr ax, 8
	mov di, ax								; DI contains weekday: 0 = Monday, 1 = Tuesday, 2 = Wednesday, etc.
	
	mov ah, 0x03
	int 0x10
	
	dec ah
	add dh, 0x02							; Move cursor in correct position
	mov dl, 0x02
	int 0x10

; NOTE: 400 is a multiple of 100 which is a multiple of 4
calendar_leap_year_400:						; Years that are multiples of 400 are leap years
	mov ah, 0x04							; Get current date in CX, DX - Used here for Year & Date
	int 0x1a
	xor al, al
	
	pop bx									; Get (Year-1)%400 from earlier
	cmp bx, 0x018f							; 399 in Hex
	jl calendar_leap_year_100				; If this year is a multiple, mark this as a leap year
	inc al
	
calendar_leap_year_100:						; Years that are multiples of 100 are NOT leap years
	test cx, 0x00ff							; Check if Year % 100 = 0
	jnz calendar_leap_year_4				; If this year is a multiple, remove a mark on it
	dec al

calendar_leap_year_4:						; Years that are multiples of 4 are leap years
	pop bx									; (Year-1)%4
	cmp bx, 0x0003
	jl calendar_date_offset					; If this year is a multiple, set a mark
	inc al


	; So far:
	; AL -> 0/1 => Regular/Leap Year
	; BX - Free
	; CX - Year
	; DX - Month/Day
	; SI - Free
	; DI - Weekday (0 = Mon, 1 = Tue, ...)
	; BP - Free
calendar_date_offset:
	push ax
	push di
	
	mov si, dx
	shr si, 8								; SI = Month in BCD format
	call bcd_to_hex
	dec di
	
	mov bp, calendar_month_days+1			; Start from January
	xor si, si
	xor cx, cx
	xor bx, bx
	
	cmp di, 0x0002							; If month we're in is past February...
	jl calendar_date_offset_loop
	add bl, al								; Account for the leap year extra day
	
calendar_date_offset_loop:
	cmp si, di
	je calendar_date_offset_days
	
	mov cl, byte [bp]						; Add up the number of days of previous months
	add bx, cx
	
	inc si
	inc bp
	jmp calendar_date_offset_loop
	
calendar_date_offset_days:
	pop ax									; Get weekday of Jan. 1st of this year
	add ax, bx
	mov bx, 0x0007
	div bl
	shr ax, 8								; Get weekday of 1st of current month instead

	dec bp
	mov bl, byte [bp]				
	mov si, bx	
	sub si, ax
	inc si									; Get the last Monday of previous month

	mov ah, 0x03
	int 0x10
	xor cx, cx								; CL = index of weekday in next loop
	mov ah, 0x02
	mov bl, 0x08							; Gray text by default

calendar_print_last_month:
	cmp cl, al
	je calendar_print_curr_prep
	
	cmp cl, 0x05
	jne calendar_print_last_skip
	mov bl, 0x04							; Red text for Saturday

calendar_print_last_skip:
	call hex_to_bcd
	call print_bcd_cal
	
	inc si
	inc cl
	jmp calendar_print_last_month


calendar_print_curr_prep:
	inc bp
	mov bl, byte [bp]
	xor bp, bp
	add bp, bx								; BP stores # of days of current month
	mov bl, 0x07							; Light gray text for weekdays
	mov si, 0x0001
	
	; TODO: Highlight current day
	; TODO: If February, `add bp, (stack)`

calendar_print_curr_month:
	cmp cl, 0x05
	jl calendar_print_curr_body
	mov bl, 0x0c							; Bright Red text for weekends
	
	cmp cl, 0x07
	jl calendar_print_curr_body
	
	inc dh									; Go to next row, default to gray dates
	mov dl, 0x02
	int 0x10
	xor cl, cl
	mov bl, 0x07
	
calendar_print_curr_body:
	cmp si, bp
	jg calendar_print_next_prep
	
	call hex_to_bcd
	call print_bcd_cal
	
	inc cl
	inc si
	jmp calendar_print_curr_month

calendar_print_next_prep:
	mov bl, 0x08							; Gray text for weekdays
	mov si, 0x0001
	
calendar_print_next_month:
	cmp cl, 0x05
	jl calendar_print_next_body
	mov bl, 0x04							; Red text for weekends
	
	cmp cl, 0x07
	je calendar_print_end

calendar_print_next_body:
	call hex_to_bcd
	call print_bcd_cal

	inc cl
	inc si
	jmp calendar_print_next_month

calendar_print_end:
	mov ah, 0x02
	add dh, 0x02
	xor dl, dl
	int 0x10
	
	pop si
	;call phex16

	
calendar_loop:
	xor ah, ah
	int 0x16
	
	cmp ah, 0x01							; ESC to Quit
	je calendar_exit
	
	;cmp ah, 0x4b							; Left Key
	;je calendar_left
	
	;cmp ah, 0x4d							; Right Key
	;je calendar_right
	jmp calendar_loop



calendar_exit:
	ret




; reboot - resets the OS, starts again from the bootloader
; In - None
; Out - None
; Affects - None

reboot:
	call clear_buffer
	jmp 0xffff:0000							; Jump to reset vector location (FFFF0)
	ret

; read_str - Reads up to 256 characters from keyboard and loads them into the command buffer
; In - None
; Out - command_buffer: input string; SI - Index+1 of last char in buffer
; Affects - AX, BX = 0x0007, CX = 0x0001, DX

read_str:
	mov si, command_buffer
	mov bx, 0x0007

read_str_loop:
	xor ax, ax
	int 0x16
	
	cmp ah, 0x0e							; AH = 0x0e -> BKSP pressed
	je read_str_bksp
	cmp ah, 0x1c							; AH = 0x1c -> ENTER pressed
	je read_str_enter

	cmp al, 0x20							; If ASCII < 0x20, do not try to print (Control characters)
	jl read_str_loop
	cmp al, 0x7f							; Don't try to print [DEL]
	je read_str_loop
	
	cmp si, command_buffer + 255			; If buffer is at max size (255), ignore further inputs
	je read_str_loop
	mov [si], al
	inc si
	
	mov ah, 0x09							; Write char at cursor
	mov cx, 0x0001
	int 0x10
	
	mov ah, 0x03
	int 0x10
	cmp dl, 0x4f							; Check if cursor is at last column
	jl mov_cursor
	
	call go_next_line
	mov dl, 0xff							; -1 unsigned, will intentionally overflow to 0

mov_cursor:
	inc dl				
	mov ah, 0x02							; Move cursor to the next position
	int 0x10

	jmp read_str_loop

read_str_bksp:
	cmp si, command_buffer					; Check if buffer is empty
	je read_str_loop
	dec si
	mov byte [si], 0						; Eliminate last char in buffer
	
	mov ah, 0x03							; Get cursor coords
	int 0x10
	
	dec ah
	cmp dl, 0								; If at start of line, move cursor to previous line
	jz prev_line
	
	dec dl									; Otherwise, just move cursor to previous position
	int 0x10
	jmp erase_char

prev_line:
	mov dl, 79								; Move cursor to end of last line
	dec dh
	int 0x10

erase_char:
	mov ax, 0x0a20							; Overwrite char at position with ' '
	int 0x10
	jmp read_str_loop
	
read_str_enter:
	ret


; print_str - Print a string to screen
; In - BL: Text Attribute, BP: String to be printed
; Out - None
; Affects - AX, BH, CX, DX, SI

print_str:
	xor bh, bh
	mov ah, 0x03
	int 0x10

	call strlen
	mov ax, 0x1301
	mov cx, si
	int 0x10
	ret


; strlen - Count length of string in buffer
; In - BP: String address
; Out - SI: Length of string
; Affects - None

strlen:
	mov si, bp
buffer_strlen_loop:
	cmp byte [si], 0
	jz buffer_strlen_end
	
	inc si
	jmp buffer_strlen_loop

buffer_strlen_end:
	sub si, bp
	ret


; go_next_line - Moves cursor to next line, scrolls if needed
; In - None
; Out - None
; Affects - AX, BH, CX, DX

go_next_line:
	mov ah, 0x03
	int 0x10
	
	cmp dh, 0x18
	jne skip_scroll_screen

	mov al, 0x01
	call scroll_lines
	
	mov dh, 0x17
	
skip_scroll_screen:
	mov ah, 0x02
	inc dh
	xor dl, dl
	int 0x10
	ret

; scroll_lines - Scrolls the screen a specified number of lines
; In - AL: Number of lines
; Out - None
; Affects - AX, BH, CX, DX

scroll_lines:
	mov ah, 0x06
	mov bh, 0x07
	xor cx, cx
	mov dx, 0x184f
	int 0x10
	xor bh, bh
	ret

; clear_screen - Erases all screen contents, moves cursor to top-left corner
; In - None
; Out - None
; Affected - AX, CX, DX

clear_screen:
	mov ax, 0x0600
	mov bh, 0x07
	xor cx, cx
	mov dx, 0x194f
	int 0x10
	
	mov ah, 0x02
	xor bh, bh
	xor dx, dx
	int 0x10
	ret




prompt_prefix db "KAOS>",0
com_echo db "echo", 0
com_clear db "clear", 0
com_about db "about", 0
com_ascii db "ascii", 0
com_help db "help", 0
com_calendar db "calendar", 0
com_changelog db "changelog", 0
com_reboot db "reboot", 0
command_err db "Unknown Command", 0

about_name db "KAOS", 0
about_name_desc db " - Kernel Application Operating System", 0
about_version db "Version 0.0.2", 0
about_release db "Released: 09/12/2023", 0
about_author db "With ", 0x03, " by ", 0
about_author_name db "<Random", 0x04, "Researchist> / Otgon Dorin", 0

help_text db "The following commands are supported, any excess arguments are ignored.",0
help_help db "help",0
help_help_desc db ": Show this text", 0
help_echo db "echo", 0
help_echo_args db " [string]", 0
help_clear db "clear", 0
help_clear_desc db ": Clears entire screen", 0
help_echo_desc db ": Display a given line of text", 0
help_about db "about", 0
help_about_desc db ": Show general system information", 0
help_ascii db "ascii", 0
help_ascii_desc db ": Show the ASCII table", 0
help_changelog db "changelog", 0
help_changelog_desc db ": Show a changelog describing changes in the latest version", 0
help_calendar db "calendar", 0
help_calendar_desc db ": Use an interactive calendar", 0
help_reboot db "reboot", 0
help_reboot_desc db ": Reboots the system", 0

changelog_version_old db "v 0.0.1 ", 0
changelog_version_arrow db 0x1a, 0
changelog_version_new db " v 0.0.2", 0
changelog_item_1 db " - Added new commands: 'calendar', 'changelog', 'reboot'", 0
changelog_item_2 db " - Refactored old code, resulting in a smaller Kernel and more extensible code", 0
changelog_item_3 db " - Changed output of ASCII command, shows Extended ASCII now too", 0
changelog_item_4 db " - Changed a few colors for 'about' output", 0

calendar_weekdays db "Mo", 0, "Tu", 0, "We", 0, "Th", 0, "Fr", 0, "Sa", 0, "Su", 0

;  Repeats |	Left Edge	  |   Center of Line  | Vertical Delimiter |    Right Edge
calendar_grid db \
	0x01,	0xc9, 0x09, 0x01,	0xcd, 0x09, 0x04,	0xcd, 0x09, 0x01,	0xbb, 0x09, 0x01, \
	0x01,	0xba, 0x09, 0x01,	0x20, 0x09, 0x04,	0x20, 0x09, 0x01,	0xba, 0x09, 0x01, \
	0x01,	0xcc, 0x09, 0x01,	0xcd, 0x09, 0x04,	0xd1, 0x09, 0x01,	0xb9, 0x09, 0x01, \
	0x01,	0xba, 0x09, 0x01,	0x20, 0x09, 0x04,	0xb3, 0x09, 0x01,	0xba, 0x09, 0x01, \
	0x01,	0xcc, 0x09, 0x01,	0xcd, 0x09, 0x04,	0xd8, 0x09, 0x01,	0xb9, 0x09, 0x01, \
	0x06,	0xba, 0x09, 0x01,	0x20, 0x09, 0x04,	0xb3, 0x09, 0x01,	0xba, 0x09, 0x01, \
	0x01,	0xc8, 0x09, 0x01,	0xcd, 0x09, 0x04,	0xcf, 0x09, 0x01,	0xbc, 0x09, 0x01, \
	0x00

; 13 Months - From December to December, inclusively
calendar_month_days db 0x1f, 0x1f, 0x1c, 0x1f, 0x1e, 0x1f, 0x1e, 0x1f, 0x1f, 0x1e, 0x1f, 0x1e, 0x1f

align 512, db 0								; Pad space out with 0s
kernel_end:
command_arr_str dw \
	com_echo, \
	com_clear, \
	com_about, \
	com_help, \
	com_ascii, \
	com_reboot, \
	com_changelog, \
	com_calendar, \
	0
command_arr_addr dw \
	echo_str, \
	clear_screen, \
	about, \
	help, \
	ascii, \
	reboot, \
	changelog, \
	calendar

about_str_seq dw \
	about_name,				about_name_desc,			1, \
	about_author,			about_author_name,			1, \
	about_version,			1, \
	about_release,			1, 0

about_str_col db \
	0x04, 0x0c, \
	0x0b, 0x09, \
	0x0a, \
	0x02

help_str_seq dw \
	help_text,				1, \
	help_help,				help_help_desc,				1, \
	help_echo,				help_echo_args,				help_echo_desc, 		1, \
	help_clear,				help_clear_desc,			1, \
	help_about,				help_about_desc,			1, \
	help_ascii,				help_ascii_desc,			1, \
	help_changelog,			help_changelog_desc,		1, \
	help_calendar,			help_calendar_desc, 		1, \
	help_reboot,			help_reboot_desc, 			1, 0

help_str_col db \
	0x02, \
	0x0e, 0x07, \
	0x0e, 0x06, 0x07, \
	0x0e, 0x07, \
	0x0e, 0x07, \
	0x0e, 0x07, \
	0x0e, 0x07, \
	0x0e, 0x07, \
	0x0e, 0x07

changelog_str_seq dw \
	changelog_version_old,	changelog_version_arrow,	changelog_version_new,	1, \
	changelog_item_1, 		1, \
	changelog_item_2, 		1, \
	changelog_item_3, 		1, \
	changelog_item_4, 		1, 0

changelog_str_col db \
	0x03, 0x0f, 0x02, \
	0x0f, \
	0x0f, \
	0x0f, \
	0x0f

command_buffer times 256 db 0x0
times 510 - ($ - kernel_end) db 0
dw 0x4321