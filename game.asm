%include "/usr/local/share/csc314/asm_io.inc"

; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define WALL_CHAR '#'
%define PLAYER_CHAR 'O'
%define COLLECTABLE '$'
%define HARM_CHAR 'X'

; the size of the game screen in characters
%define HEIGHT 20
%define WIDTH 40
%define BOARDSIZE (WIDTH * HEIGHT)

; the player starting position.
; top left is considered (0,0)
%define STARTX 1
%define STARTY 1

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'w'
%define LEFTCHAR 'a'
%define DOWNCHAR 's'
%define RIGHTCHAR 'd'


segment .data
	; used to fopen() the board file defined above
	board_file			db BOARD_FILE,0

	; used to change the terminal mode
	mode_r				db "r",0
	raw_mode_on_cmd		db "stty raw -echo",0
	raw_mode_off_cmd	db "stty -raw echo",0

	; ANSI escape sequence to clear/refresh the screen
	clear_screen_code	db	27,"[2J",27,"[H",0

	; things the program will print
	help_str			db 13,10,"Controls: ", \
							UPCHAR,"=UP / ", \
							LEFTCHAR,"=LEFT / ", \
							DOWNCHAR,"=DOWN / ", \
							RIGHTCHAR,"=RIGHT / ", \
							EXITCHAR,"=EXIT / ", \
							COLLECTABLE,"=COLLECTABLE / ", \
							HARM_CHAR,"=HAZARD", \
							13,10,10,0
	; print the score
	score_str			db "Score: ",0,10

segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resd	1
	ypos	resd	1

	; variables to store the current collectible position and score value
	score	resd 1

	rand_seed resd 12345678

segment .text

	global	asm_main
	global  raw_mode_on
	global  raw_mode_off
	global  init_board
	global  render

	extern	system
	extern	putchar
	extern	getchar
	extern	printf
	extern	fopen
	extern	fread
	extern	fgetc
	extern	fclose
	extern  rand

asm_main:
	push	ebp
	mov		ebp, esp


	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable
	call	init_board

	; set the player at the proper start position
	mov		DWORD [xpos], STARTX
	mov		DWORD [ypos], STARTY

	; set score to zero
	mov DWORD [score], 0

	; the game happens in this loop
	; the steps are...
	;   1. render (draw) the current board and score
	;   2. get a character from the user
	;	3. store current xpos,ypos in esi,edi
	;	4. update xpos,ypos based on character from user
	;	5. check what's in the buffer (board) at new xpos,ypos
	;	6. if it's a wall, reset xpos,ypos to saved esi,edi
	;	7. otherwise, check to see if its a collectable. If so, add 1 to score and call subprogram to generate new collectable
	;	8. otherwise, just continue! (xpos,ypos are ok)

	game_loop:

		; draw the game board
		call	render

		; display score
		mov eax, score_str
		call print_string
		mov eax, [score]
		call print_int
		call print_nl

		; get an action from the user
		call	getchar

		; store the current position
		; we will test if the new position is legal
		; if not, we will restore these
		mov		esi, DWORD [xpos]
		mov		edi, DWORD [ypos]

		; choose what to do
		cmp		eax, EXITCHAR
		je		game_loop_end
		cmp		eax, UPCHAR
		je 		move_up
		cmp		eax, LEFTCHAR
		je		move_left
		cmp		eax, DOWNCHAR
		je		move_down
		cmp		eax, RIGHTCHAR
		je		move_right
		jmp		input_end			; or just do nothing

		; move the player according to the input character
		move_up:
			dec		DWORD [ypos]
			jmp		input_end
		move_left:
			dec		DWORD [xpos]
			jmp		input_end
		move_down:
			inc		DWORD [ypos]
			jmp		input_end
		move_right:
			inc		DWORD [xpos]
		input_end:

		; (Width * y) + x = pos

		; compare the current position to the wall character
		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, DWORD [xpos]
		lea		eax, [board + eax]
		cmp		BYTE [eax], WALL_CHAR
		jne		valid_move
			; opps, that was an invalid move, reset
			mov		DWORD [xpos], esi
			mov		DWORD [ypos], edi
		valid_move:
		; compare the current position to the collectable character
			cmp byte [eax], COLLECTABLE
			jne harm_check				; if not collectable, check for harm

		    ; else, increase score
    		inc dword [score]

  		  ; remove the collectable from the board
    		mov byte [eax], ' '       ; replace character with space

    	; place a new collectable somewhere random
    	call place_collectable
		call place_hazard		; place new hazard with every new score

		jmp		game_loop			; jump back to the start of game loop

		harm_check:
		; compare current position to hazard character
			cmp byte [eax], HARM_CHAR
			jne game_loop		; if not equal, ignore

			; else, decrease score
			dec dword [score]
			mov byte [eax], ' ' ; replace "used" hazard with space
			jmp game_loop		; jump back through the game loop

	game_loop_end:

	; restore old terminal functionality
	call raw_mode_off

	mov		eax, 0
	mov		esp, ebp
	pop		ebp
	ret

raw_mode_on:

	push	ebp
	mov		ebp, esp

	push	raw_mode_on_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

raw_mode_off:

	push	ebp
	mov		ebp, esp

	push	raw_mode_off_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

init_board:

	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	board_file
	call	fopen
	add		esp, 8
	mov		DWORD [ebp - 4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp - 8], 0
	read_loop:
	cmp		DWORD [ebp - 8], HEIGHT
	je		read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp - 8]
		lea		ebx, [board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp - 4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp - 4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp - 8]
	jmp		read_loop
	read_loop_end:

	call place_collectable ; place the collectable

	; close the open file handle
	push	DWORD [ebp - 4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

render:

	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	sub		esp, 8

	; clear the screen
	push	clear_screen_code
	call	printf
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp - 4], 0
	y_loop_start:
	cmp		DWORD [ebp - 4], HEIGHT
	je		y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp - 8], 0
		x_loop_start:
		cmp		DWORD [ebp - 8], WIDTH
		je 		x_loop_end

			; check if (xpos,ypos)=(x,y)
			mov		eax, DWORD [xpos]
			cmp		eax, DWORD [ebp - 8]
			jne		print_board
			mov		eax, DWORD [ypos]
			cmp		eax, DWORD [ebp - 4]
			jne		print_board
				; if both were equal, print the player
				push	PLAYER_CHAR
				call	putchar
				add		esp, 4
				jmp		print_end
			print_board:
				; otherwise print whatever's in the buffer
				mov		eax, DWORD [ebp - 4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, DWORD [ebp - 8]
				mov		ebx, 0
				mov		bl, BYTE [board + eax]
				push	ebx
				call	putchar
				add		esp, 4
			print_end:

		inc		DWORD [ebp - 8]
		jmp		x_loop_start
		x_loop_end:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp - 4]
	jmp		y_loop_start
	y_loop_end:

	mov		esp, ebp
	pop		ebp
	ret

place_collectable:
    push ebp
    mov  ebp, esp

find_spot_collect:
        ; eax = random board index (0 .. WIDTH*HEIGHT-1)
        call rand_gen

        ; ebx = &board[eax]
        lea ebx, [board + eax]

        ; if it's a wall, try again
        cmp byte [ebx], WALL_CHAR
        je  find_spot_collect

        ; place the '$'
        mov byte [ebx], COLLECTABLE

        ; done
        mov esp, ebp
        pop ebp
        ret

rand_gen:
    push ebp
    mov  ebp, esp

	; load previous seed
    mov eax, [rand_seed]

    ; eax = eax * 1664525
    mov ebx, 1664525
    mul ebx                ; edx:eax = eax * ebx

    ; eax = eax + 1013904223
    add eax, 1013904223

    ; save new seed
    mov [rand_seed], eax



    ; now compute eax % (WIDTH*HEIGHT)
    xor edx, edx           ; clear top half for unsigned div
    mov ebx, WIDTH*HEIGHT
    div ebx                ; eax = quotient, edx = remainder

    mov eax, edx           ; return remainder (0..boardsize-1)

    mov esp, ebp
    pop ebp
    ret


place_hazard:
    push ebp
    mov  ebp, esp

find_spot_hazard:
        ; eax = random board index (0 .. WIDTH*HEIGHT-1)
        call rand_gen

        ; ebx = &board[eax]
        lea ebx, [board + eax]

        ; if it's a wall, try again
        cmp byte [ebx], WALL_CHAR
        je  find_spot_hazard

        ; place the 'X'
        mov byte [ebx], HARM_CHAR

   ; done
   mov esp, ebp
   pop ebp
   ret