%include "/usr/local/share/csc314/asm_io.inc"

; the file that stores the initial state
%define BOARD_FILE 'board.txt'

; how to represent everything
%define WALL_CHAR '#'
%define PLAYER_CHAR 'O'
%define COLLECTABLE '$'
%define HARM_CHAR 'X'
%define EXPLOSIVE_CHAR 'E'				;explosives title

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

; enemy defination
%define ENEMYCHAR '!'
%define ENEMYBCHAR '*'
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
							COLLECTABLE,"=COLLECTABLE / ",\
							HARM_CHAR,"=HAZARD / ",\
							ENEMYCHAR,"=CHASING_ENEMY / ",\
							ENEMYBCHAR,"=CONFUSED_ENEMY",\
							13,10,10,0

	; hp display
	hp_display_format db "HP: %d" ,13,10,0
	gomsg db "Game Over" ,13,10,0
	hp_left db "Final HP: %d" ,13,10,0
	; print the score
	score_str		db "Score: ",0,10
	;explosives
	explosives_display_format db "Explosives: %d",13,10,0

segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resd	1
	ypos	resd	1
	; player hp initalize
	hp resd 1
	; enemy positions
	enemy1x resd 1
	enemy1y resd 1
	enemy2x resd 1
	enemy2y resd 1
	; hit marker
	hit resd 1
	; score
	score resd 1
	;explosives
	explosives resd 1
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
	extern  srand

asm_main:
	push	ebp
	mov		ebp, esp
	push 8675
	call srand
	add esp, 4
	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable
	call	init_board

	; set the player at the proper start position
	mov		DWORD [xpos], STARTX
	mov		DWORD [ypos], STARTY
	; set enemy, hp, and hit vars
	mov		DWORD [hp], 5
	mov		DWORD [enemy1x], 10
	mov		DWORD [enemy1y], 10
	mov 	DWORD [enemy2x], 2
	mov 	DWORD [enemy2y], 2
	mov 	DWORD [hit], 0
	mov 	DWORD [explosives], 0			;explosives triggered
	; the game happens in this loop
	; the steps are...
	;   1. render (draw) the current board
	;   2. get a character from the user
	;	3. store current xpos,ypos in esi,edi
	;	4. update xpos,ypos based on character from user
	;	5. check what's in the buffer (board) at new xpos,ypos
	;	6. if it's a wall, reset xpos,ypos to saved esi,edi
	;	7. otherwise, just continue! (xpos,ypos are ok)
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

		; (W * y) + x = pos

		; compare the current position to the wall character
		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, DWORD [xpos]
		lea		eax, [board + eax]
		cmp		BYTE [eax], WALL_CHAR
		jne		valid_move

		;*** hit a wall and wrap around like snake ***;

		mov edx, [xpos]
		cmp edx, esi
		jl hit_left			;if new x<old, user pressed left into the wall
		jg hit_right		;if new x>old, user pressed right into the wall

		mov edx, [ypos]		;else move was up or down
		cmp edx, edi
		jl hit_up			;new y<old, user moved up
		jg hit_down			;new y>old, user moved down
		jmp wrap_done

	hit_left:
		mov DWORD [xpos], WIDTH-2
		jmp wrap_done
	hit_right:
		mov DWORD [xpos], 1
		jmp wrap_done
	hit_up:
		mov DWORD [ypos], HEIGHT-2
		jmp wrap_done
	hit_down:
		mov DWORD [ypos], 1
wrap_done:
		mov eax, WIDTH
		mul DWORD [ypos]
		add eax, DWORD [xpos]
		lea eax, [board+eax]
		jmp valid_move

	;*** changed to explosive charge ***;

valid_move:
	cmp byte [eax], EXPLOSIVE_CHAR
	jne after_explosive

		;*** stepped on explosive, remove and trigger explosion ***;
	inc DWORD [explosives]		;one explosive triggered
	mov byte [eax], ' '			;clear this place
	call trigger_explosion		;explode walls and enemies
	jmp enemy_calls				;continue as usual

after_explosive:
	;********** previous valid move contd ***********;
	cmp byte [eax], COLLECTABLE
	jne harm_check
	inc DWORD [score]
	mov byte [eax], ' '
	call place_collectable
	call place_hazard
enemy_calls:
	call enemy_update
	call check_e_col
	call enemy2_update
	call check_e_col2
	call check_hp
harm_check:
	cmp byte [eax], HARM_CHAR
	jne enemy_calls
	dec DWORD [score]
	mov byte [eax], ' '
	jmp enemy_calls
enemy_update: ; move enemy1 towards the player
	push ebp
	mov ebp, esp
	cmp DWORD [hit], 1; check if player was hit last turn
	je hit_reset ; if so, skip enemy1 turn
	mov eax, [enemy1x] ; get enemy and player positions
	mov ebx, [enemy1y]
	mov ecx, [xpos]
	mov edx, [ypos]
	cmp eax, ecx ; check x reltaions
	je y_check ; if on same x, check y
	jl e_mv_r ; if to the left, move right
	jg e_mv_l ; if to the right, move left
e_mv_r: ; move enemy right
	inc eax
	jmp y_check_done
e_mv_l: ; move enemy left
	dec eax
	jmp y_check_done
y_check: ; check if enemy y == player y
	cmp ebx, edx
	je y_check_done
	jl e_mv_d
	jg e_mv_u
e_mv_d: ; move enemy1 down
	inc ebx
	jmp y_check_done
e_mv_u: ; move enemy1 up
	dec ebx
y_check_done: ; all checks are done, move enemy1
	mov [enemy1x], eax
	mov [enemy1y], ebx
	mov esp, ebp
	pop ebp
	ret
check_e_col: ; check if enemy is touching player
	push ebp
	mov ebp, esp
	mov eax, [enemy1x]
	mov ebx, [xpos]
	cmp eax, ebx
	jne no_hit
	mov eax, [enemy1y]
	mov ebx, [ypos]
	cmp eax, ebx
	jne no_hit
	dec DWORD [hp]
	mov DWORD [hit], 1
	no_hit:
	mov esp, ebp
	pop ebp
	ret
hit_reset: ; reset hit marker and pass enemy turn
	mov DWORD [hit], 0
	jmp check_hp
enemy2_update:
	push ebp
	mov ebp, esp

	call rand
	mov ecx, 4
	xor edx, edx
	div ecx

	mov eax, [enemy2x]
	mov ebx, [enemy2y]

	cmp edx, 0
	je e2_mv1_u
	cmp edx, 1
	je e2_mv1_d
	cmp edx, 2
	je e2_mv1_l
	jmp e2_mv1_r

e2_mv1_u:
	dec ebx
	jmp e2_done1
e2_mv1_d:
	inc ebx
	jmp e2_done1
e2_mv1_l:
	dec eax
	jmp e2_done1
e2_mv1_r:
	inc eax
e2_done1:
	cmp eax, 0
	jl e2_inv_mv1
	cmp eax, WIDTH-1
	jg e2_inv_mv1
	cmp ebx, 0
	jl e2_inv_mv1
	cmp ebx, HEIGHT-1
	jg e2_inv_mv1

	mov edi, eax
	mov esi, ebx
	mov ecx, WIDTH
	imul ecx, esi
	add ecx, edi
	lea ecx, [board + ecx]
	cmp BYTE [ecx], WALL_CHAR
	je e2_inv_mv1

	mov [enemy2x], eax
	mov [enemy2y], ebx
	jmp e2_mv2

e2_inv_mv1:
	mov eax, [enemy2x]
	mov ebx, [enemy2y]

e2_mv2:
	call rand
	mov ecx, 4
	xor edx, edx
	div ecx

	mov eax, [enemy2x]
	mov ebx, [enemy2y]

	cmp edx, 0
	je e2_mv2_u
	cmp edx, 1
	je e2_mv2_d
	cmp edx, 2
	je e2_mv2_l
	jmp e2_mv2_r

e2_mv2_u:
	dec ebx
	jmp e2_done2
e2_mv2_d:
	inc ebx
	jmp e2_done2
e2_mv2_l:
	dec eax
	jmp e2_done2
e2_mv2_r:
	inc eax
	jmp e2_done2
e2_done2:
	cmp eax, 0
	jl e2_donef
	cmp eax, WIDTH-1
	jg e2_donef
	cmp ebx, 0
	jl e2_donef
	cmp ebx, HEIGHT-1
	jg e2_donef

	mov edi, eax
	mov esi, ebx
	mov ecx, WIDTH
	imul ecx, esi
	add ecx, edi
	lea ecx, [board + ecx]
	cmp BYTE [ecx], WALL_CHAR
	je e2_donef

	mov [enemy2x], eax
	mov [enemy2y], ebx
	jmp e2_donef

e2_donef:
	mov esp, ebp
	pop ebp
	ret
check_e_col2: ; check if enemy is touching player
     push ebp
     mov ebp, esp
     mov eax, [enemy2x]
     mov ebx, [xpos]
     cmp eax, ebx
     jne no_hit
     mov eax, [enemy2y]
     mov ebx, [ypos]
     cmp eax, ebx
     jne no_hit2
     dec DWORD [hp]
     mov DWORD [hit], 1
     no_hit2:
     mov esp, ebp
     pop ebp
     ret
check_hp: ; check if hp == 0
	cmp DWORD [hp], 0
	jg game_loop
	jle game_over
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
	call place_collectable
	call place_hazard
	;****place five explosives***;
	mov 	ecx, 5					;ecx is the loop counter
place_explosive_loop:
	call 	place_explosive
	loop 	place_explosive_loop				;drop one explosive at start
	; close the open file handle
	push	DWORD [ebp - 4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret


render:
    push ebp
    mov ebp, esp
    sub esp, 8          ; two ints for loop counters: [ebp-4] = y, [ebp-8] = x

    ; clear screen
    push clear_screen_code
    call printf
    add esp, 4

    ; print help / HP
    push DWORD [hp]
    push hp_display_format
    call printf
    add esp, 8

	;*****explosives***;
	push DWORD [explosives]
	push explosives_display_format
	call printf
	add esp, 8

    push help_str
    call printf
    add esp, 4

    mov DWORD [ebp-4], 0        ; y = 0
y_loop_start:
    cmp DWORD [ebp-4], HEIGHT
    je y_loop_end

        mov DWORD [ebp-8], 0    ; x = 0
x_loop_start:
        cmp DWORD [ebp-8], WIDTH
        je x_loop_end

            mov eax, [ebp-4]    ; y
            mov ebx, WIDTH
            mul ebx             ; y*WIDTH
            add eax, [ebp-8]    ; + x
            movzx eax, byte [board + eax]
            mov bl, al          ; store board char in bl

            mov ecx, [xpos]
            cmp ecx, [ebp-8]
            jne check_enemy1
            mov ecx, [ypos]
            cmp ecx, [ebp-4]
            jne check_enemy1
            mov bl, PLAYER_CHAR
            jmp print_cell

check_enemy1:
            ; check enemy1
            mov ecx, [enemy1x]
            cmp ecx, [ebp-8]
            jne check_enemy2
            mov ecx, [enemy1y]
            cmp ecx, [ebp-4]
            jne check_enemy2
            mov bl, ENEMYCHAR
            jmp print_cell

check_enemy2:
            ; check enemy2
            mov ecx, [enemy2x]
            cmp ecx, [ebp-8]
            jne print_cell
            mov ecx, [enemy2y]
            cmp ecx, [ebp-4]
            jne print_cell
            mov bl, ENEMYBCHAR

print_cell:
            push ebx
            call putchar
            add esp, 4

            ; increment x
            inc DWORD [ebp-8]
            jmp x_loop_start
x_loop_end:

        ; end of row: print CR + LF
        push 0x0d
        call putchar
        add esp, 4
        push 0x0a
        call putchar
        add esp, 4

        ; increment y
        inc DWORD [ebp-4]
        jmp y_loop_start
y_loop_end:
    mov esp, ebp
    pop ebp
    ret
place_collectable:
	push ebp
	mov ebp, esp

find_spot_collect:
	call rand_gen
	lea ebx, [board + eax]
	cmp byte [ebx], WALL_CHAR
	je find_spot_collect
	mov byte [ebx], COLLECTABLE
	mov esp, ebp
	pop ebp
	ret
rand_gen:
	push ebp
	mov ebp, esp
	mov eax, [rand_seed]
	mov ebx, 1664525
	mul ebx
	add eax, 1013904223
	mov [rand_seed], eax
	xor edx, edx
	mov ebx, WIDTH*HEIGHT
	div ebx
	mov eax, edx
	mov esp, ebp
	pop ebp
	ret
place_hazard:
	push ebp
	mov ebp, esp

find_spot_hazard:
	call rand_gen
	lea ebx, [board + eax]
	cmp byte [ebx], WALL_CHAR
	je find_spot_hazard
	mov byte [ebx], HARM_CHAR
	mov esp, ebp
	pop ebp
	ret


		;**** place explosives in the game ***;

place_explosive:
	push ebp
	mov ebp, esp

find_spot_explosive:
	call rand_gen
	lea ebx, [board+eax]

	cmp byte [ebx], WALL_CHAR			;skip walls
	je find_spot_explosive

	cmp byte [ebx], HARM_CHAR           ;skip hazards
 	je find_spot_explosive

	cmp byte [ebx], COLLECTABLE           ;skip collectible
    je find_spot_explosive

 	cmp byte [ebx], EXPLOSIVE_CHAR        ;skip another explosive
    je find_spot_explosive


	mov byte [ebx], EXPLOSIVE_CHAR         ;else put the explosive in this place

	mov esp, ebp
	pop ebp
	ret


trigger_explosion: 			;explosion covers 3 X 3
	push ebp
	mov ebp, esp
	sub esp, 8				;[ebp-4]=dy, [ebp-8]=dx

	mov DWORD [ebp-4], -1	;start with dy=-1

outer_loop_dy:
	cmp DWORD [ebp-4], 1	;while dy<=1
	jg explosion_done

	mov DWORD [ebp-8], 1	;set dx=-1

inner_loop_dx:
	cmp DWORD [ebp-8], 1	;while dx<=1
	jg next_row

	mov eax, [xpos]
	add eax, [ebp-8]		;eax=tx, tx=xpos+dx
	mov ebx, [ypos]
	mov ebx, [ebp-4]		;ebx-ty, ty=ypos+dy

	cmp eax, 0
	jl skip_cell			;tx<0, skip
	cmp eax, WIDTH
	jge skip_cell			;tx>=width, skip
	cmp ebx, 0
	jl skip_cell			;ty<0, skip
	cmp ebx, HEIGHT
	jge skip_cell			;ty>=height, skip

	mov ecx, WIDTH
	imul ecx, ebx			;ecx=ty*width
	add ecx, eax			;ecx=index
	lea edx, [board+ecx]	;edx is pointer to character in board

	; jmp to clear the area if wall or hazard or enemy
	mov al, [edx]
	cmp al, WALL_CHAR
	je clear_area
	cmp al, HARM_CHAR
	je clear_area
	cmp al, COLLECTABLE		;continue
	jne after_clear

clear_area:
	mov byte [edx], ' '

after_clear:
	mov ecx,  [enemy1x]
	cmp ecx, eax
	jne explode_enemy2
	mov ecx, [enemy1y]
	cmp ecx, ebx
	jne explode_enemy2

	mov DWORD [enemy1x], 10			;send enemy1 to its original place after explosion
	mov DWORD [enemy1y], 10

explode_enemy2:
	mov ecx, [enemy2x]
	cmp ecx, eax
	jne skip_cell
	mov ecx, [enemy2y]
	cmp ecx, ebx
	jne skip_cell

	mov DWORD [enemy2x], 2			;send enemy2 to its original place after explosion
	mov DWORD [enemy2y], 2

skip_cell:
	inc DWORD [ebp-8]		;dx++, loop again
	jmp inner_loop_dx
next_row:
	inc DWORD [ebp-4]		;dy++ when dx>1, end inner loop
	jmp outer_loop_dy

explosion_done:
	mov esp, ebp
	pop ebp
	ret
game_over: ; print a game over screen
	push ebp
	mov ebp, esp
	sub ebp, 4
	call raw_mode_off
	push clear_screen_code
	call printf
	add esp, 4
	push gomsg
	call printf
	add esp, 4
	push DWORD [hp]
	push hp_left
	call printf
	add esp, 8
	mov eax, score_str
	call print_string
	mov eax, [score]
	call print_int
	call print_nl
	;print explosives;
	push DWORD [explosives]
	push explosives_display_format
	call printf
	mov eax, 0

	mov esp, ebp;
	pop ebp
	ret