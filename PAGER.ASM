; ---------------------------------------------------------------------------------------
; Created by: 吕鑫
; Study ID: 201411212012
; Subject: 汇编语言程序设计
; Date: 2016-12-29
;	Complete Date: 2017-01-02
; Description: - Program: PAGER.ASM
; 						 - Purpose: Displays status and	text lines
; 						 - Input: Stack variable: lines to scroll (negative up, positive down)
; 						 - Output: Display to screen
;							 - Global Variables: "sbuffer", "pbuffer", "linenum"
;----------------------------------------------------------------------------------------

;--------------------------------------------------------------------------
; Table of Content
;--------------------------------------------------------------------------
; 0.0 - Declarations (.Model)
; 1.0 - .DATA
; 2.0 - .CODE
; 		2.1 - Display the status line and text
;			2.2 - scroll dirction
;			2.3 - Write	line number to status line
;		  2.4 - BinToStr (linenum,OFFSET statline[7]) - subfunction called
;			2.5 - Fill in status line
;			2.6 - CellWrt (DS,OFFSET statline,0,cell) - subfunction called
;			2.7 - To show the content of file
;			2.8 - CellWrt (sbuffer,position,line,cell) - subfunction called
;		  2.9 - show the search line
;			2.10 - Fill the rest	with spaces
;     2.10 - Display first	page
;		  2.11 - Cellwrt function 向屏幕缓冲区写一行
;	  	2.12 - CellFil function 向屏幕显示一定数量的字符
;		  2.13 - FillTab function 填充Tab
;			2.14 - GoBack of Buffer to search function
;		  2.15 - GoForwd of buffer to search function
;		  2.16 - calculate the line number backward function
;		  2.17 - search string in lines
;			2.18 - highlight function
;		  2.19 - whether EGA is active
;		  2.20 - Converts integer to string
;  	  2.21 - wirte in CGA model
;			2.22 - Calculate the tab number
;--------------------------------------------------------------------------


; 0.0 - Declarations (.Model)
PAGE	  60,132
.MODEL  small


; 1.0 - .DATA
.DATA ;***************************************
		EXTRN	  statatr:BYTE,scrnatr:BYTE,sbuffer:WORD,pbuffer:WORD
		EXTRN	  fsize:WORD,cell:WORD,statline:BYTE,linenum:WORD,statSearch:BYTE,searchPos:WORD
		EXTRN	  rows:WORD,vidadr:WORD,cga:BYTE


; 2.0 - .CODE
.CODE
	  PUBLIC  Pager,isEGA


; 2.1 - Display the status line and text
Pager	  PROC
	  push	bp
	  mov	  bp,sp

	  mov	  es,sbuffer		; Initialize buffer position, es为段基址
	  mov	  di,pbuffer		; offset


; 2.2 - scroll dirction
	  mov	  cx,[bp+4]		; Get count argument
	  mov	  ax,10			; Search for linefeed, 这个是ASCII10

	  or	  cx,cx			; Argument 0? 滚动方向判断，大于0则forward，小于0则backward
	  jg	  forward		; If above, forward
	  jl	  backward		; If below, backward
	  jmp	  SHORT	show		; If equal, done 这是没滚动
backward: 																	;这种是向上滚
		call	GoBack		; Adjust backward
	  jmp	  SHORT	show		; Show screen
forward: 																		;这种为向下滚动
		call	GoForwd		; Adjust forward


; 2.3 - Write	line number to status line
show:
		cld							; Go forward
	  push	di
	  push	es
	  push	ds			; Load DS to ES
	  pop	 	es

; 2.4 - BinToStr (linenum,OFFSET statline[7]) - subfunction called
	  push linenum							; Arg 1
	  mov	 ax,OFFSET statline[6]
	  push ax									; Arg 2
	  call BinToStr						; Convert 行号 to string

; 2.5 - Fill in status line 打印显示
	  mov	 cx,7			; Seven	spaces to fill
	  sub	 cx,ax			; Subtract those already done
	  mov	 al," "		; Fill with space
	  rep	 stosb
	  pop	 es
	  mov	 bl,statatr		; Load status attribute
	  mov	 BYTE PTR cell[1],bl

; 2.6 - CellWrt (DS,OFFSET statline,0,cell) - subfunction called
	  push	ds								; Arg 1
	  lea		ax, statline	; Arg 2
	  push	ax
	  sub	 	ax,ax								; Arg 3
	  push	ax
	  push	cell							; Arg 4
	  call	CellWrt		; Write	status line 确定了status line 的颜色
	  pop	  di
	  mov	  bl,scrnatr		; Load screen attribute 刚刚的配色
	  mov	  BYTE PTR cell[1],bl
	  mov	  si,di			; Update position, buffer offset
	  mov	  cx,rows		; Lines	per screen 行数/页

; 2.7 - To show the content of file
show1:
		mov	  bx,rows		; Lines	of text
	  inc	  bx				; Adjust for 0
	  sub	  bx,cx			; Calculate current row
	  push	cx				; Save line number
		push	si				; Save buffer offset

; 2.8 - CellWrt (sbuffer,position,line,cell) - subfunction called, 写入第0行
	  push	sbuffer		; Arg 1
	  push	si			; Arg 2
	  push	bx			; Arg 3
	  push	cell			; Arg 4
	  call	cellwrt		; Write	line, 缓冲区内容写入
	  push	ss			; Restore DS from SS
	  pop	  ds
		pop 	si
	  pop	  cx			; Restore line number
		cmp 	rows, 23
		jne 		NoneResult
		mov bx, rows
		inc bx
		sub bx, cx
		push bx
		push si
		push ax
		call SearchStr
NoneResult:
	  mov	  si,ax			; Get returned position
	  cmp	  ax,fsize		; Beyond end of	file? 文末检测
	  jae	  fillout		; Yes? Fill screen with	spaces
	  loop	show1			;    else next line
; 2.9 - show the search line
		mov	  bl,statatr
		mov	  BYTE PTR cell[1],bl
		cmp		rows,23
		jne		fillout
		push	ds			; Arg 1
		lea	  ax, statSearch	; Arg 2
		push	ax
		mov	  ax,24			; Arg 3
		push	ax
		push	cell			; Arg 4
		call  CellWrt
		jmp	  SHORT	pagedone	; Get out if done

; 2.10 - Fill the rest	with spaces
fillout:
		dec	  cx			; Adjust
	  jcxz	pagedone
	  mov	  al,80			; Columns times	remaining lines
	  mul	  cl
	  push	sbuffer		; Arg 1
	  push	ax			; Arg 2
	  push	cell			; Arg 3
	  call	CellFil		; Fill screen with spaces 通过调用 CellFil (sbuffer,count,cell)
	  push	ss			; Restore DS from SS
	  pop	  ds

pagedone:
		pop	  bp
	  ret	  2
Pager	  ENDP

; 2.11 - Cellwrt function 向屏幕缓冲区写一行
; Procedure CellWrt (segment,offset,line,cell)
; Input	    Stack variables:
;									 1 - segment of line 缓冲段
;					 		     2 - offset   缓冲偏移
;							     3 - line number 行号
;			    				 4 - attribute   配色
; Output    Line to screen buffer

CellWrt	  PROC
	  push	bp
	  mov	  bp,sp
	  sub	  dx,dx			; Clear	as flag	for scan
	  cmp	  cga,1			; CGA?
	  jne	  noscan
	  mov	  dx,03DAh		; Load port #
noscan:
		mov	  es,vidadr		; Load screen buffer segment
	  mov	  ds,[bp+10]		; Buffer segment
	  mov	  si,[bp+8]		; Buffer position
	  mov	  cx,80			; Cells	per row
	  mov	  ax,[bp+6]		; Starting row
	  mov	  bx,80*2		; Bytes	per row
	  mul	  bl			; Figure columns per row
	  mov	  di,ax			; Load as destination
	  mov	  bx,di			; Save start for tab calculation
	  mov	  ax,[bp+4]		; Attribute
movechar:
		lodsb						; Get character
	  cmp	  al,13			; CR?
	  je	  fillspc
	  cmp	  al,9			; Tab?
	  jne	  notab
	  call  filltab		; Yes? fill with spaces
	  jcxz	nextline		; If beyond limit done
	  jmp	  SHORT	movechar

notab:
		or	  dx,dx			; CGA?
	  je	  notab2
	  call	Retrace		; Yes? Write during retrace
	  loop	movechar
	  jmp	  SHORT	nextline

notab2:
		stosw						; Write
	  loop	movechar
	  jmp	  SHORT	nextline	; Done

fillspc:
		mov	  al," "		; Fill with space
	  or	  dx,dx			; CGA?
	  je	  space2
space1:
		call	Retrace		; Yes? Write during retrace
	  loop	space1
	  inc	  si			; Adjust
	  jmp	  SHORT	exit		; Done

space2:
		rep	  stosw			; Write
	  inc	  si			; Adjust for LF
	  jmp	  SHORT	exit		; Done

nextline:
		mov	  ah,10			; Search for next line feed
chklf:
		lodsb				; Load and compare
	  cmp	  al,ah
	  loopne  chklf

exit:
		mov	  ax,si			; Return position
	  pop	  bp
	  ret	  8
CellWrt	  ENDP


; 2.12 - CellFil function 向屏幕显示一定数量的字符
; Procedure CellFil (segment,count,cell)
; Input	    Stack variables:
;										1 - segment of text (offset 0)
;							      2 - number	of characters   数量
;			    				  3 - attribute and character 配色
; Output    Characters to screen buffer

CellFil	  PROC
	  push	bp
	  mov	  bp,sp
	  sub	  dx,dx			; Clear	as flag	for scan
	  cmp	  cga,1			; CGA?
	  jne	  noscan2
	  mov	  dx,03DAh		; Load port #

noscan2:
		mov	  es,vidadr		; Load screen buffer segment
	  mov	  ds,[bp+8]		; Buffer segment (position 0)
	  mov	  cx,[bp+6]		; Characters to	fill
	  mov	  ax,[bp+4]		; Attribute
	  or	  dx,dx			; CGA?
	  je	  fillem2
fillem1:
		call	Retrace		; Yes? Write during retrace
	  loop	fillem1
	  jmp	  SHORT	filled		; Done
fillem2:
 		rep	  stosw			; Write

filled:
 		pop	  bp
	  ret	  6
CellFil	  ENDP


; 2.13 - FillTab function 用空格填充Tab
; Procedure FillTab
; Input	    BX points to start of line,	DI points to current position  各种指向行位置
; Output    Spaces to screen buffer

FillTab	  PROC
	  push	bx
	  push	cx

	  sub	  bx,di			; Get current position in line
	  neg	  bx
	  shr	  bx,1			; Divide by 2 bytes per	character

	  mov	  cx,8			; Default count	8
	  and	  bx,7			; Get modulus
	  sub	  cx,bx			; Subtract
	  mov	  bx,cx			; Save modulus

	  mov	  al," "		; Spaces
	  or	  dx,dx			; CGA?
	  je	  tabem2

tabem1:
		call	Retrace		; Yes? Write during retrace
	  loop	tabem1
	  jmp	  SHORT	tabbed
tabem2:
		rep	  stosw			; Write

tabbed:
 		pop	  cx
	  sub	  cx,bx			; Adjust count
	  jns	  nomore		; Make negative	count 0
	  sub	  cx,cx
nomore:
 		pop	  bx
	  ret
FillTab	  ENDP


; 2.14 - GoBack of Buffer to search function
; Procedure GoBack
; Input	    CX has number of lines; ES:DI has buffer position
; Output    Updates "linenum" and "pbuffer"

GoBack	  PROC
	  std						; Go backward
	  neg	  cx			; Make count positive
	  mov	  dx,cx			; Save a copy
	  inc	  cx			; One extra to go up one
	  or	  di,di			; Start	of file?
	  je	  exback		; If so, ignore
findb:
 		push	cx			;   else save count
	  mov	  cx,0FFh		; Load maximum character count
	  cmp	  cx,di			; Near start of	buffer?
	  jl	  notnear		; No? Continue
	  mov	  cx,di			;   else search	only to	start
notnear:
		repne	scasb			; Find last previous LF
	  jcxz	atstart		; If not found,	must be	at start
	  pop	 	cx
	  loop	findb
	  cmp	 	linenum,0FFFFh	; End of file flag?
	  jne	 	notend		; No? Continue
	  add	 	di,2			; Adjust for cr/lf
	  mov	  pbuffer,di		; Save position
	  call	EndCount		; Count	back to	get line number
	  ret
notend:
		sub	  linenum,dx		; Calculate line number
	  jg	  positive
	  mov	  linenum,1		; Set to 1 if negative
positive:
		add	  di,2			; Adjust for cr/lf
	  mov	  pbuffer,di		; Save position
	  ret

atstart:  pop	  cx
	  sub	  di,di			; Load start of	file
	  mov	  linenum,1		; Line 1
	  mov	  pbuffer,di		; Save position
exback:
		ret
GoBack	  ENDP


; 2.15 - GoForwd of buffer to search function
; Procedure GoForwd
; Input	    CX has number of lines; ES:DI has buffer position
; Output    Updates "linenum" and "pbuffer"

GoForwd	  PROC
	  cld							; Go forward
	  mov	  dx,cx			; Copy count
findf:
		push	cx			; Save count
	  mov	  cx,0FFh		; Load maximum character count
	  repne	scasb			; Find next LF
	  jcxz	atend			; If not found,	must be	at end
	  cmp	  di,fsize		; Beyond end?
	  jae	  atend
	  pop	  cx
	  loop	findf
	  add	  linenum,dx		; Calulate line	number
	  mov	  pbuffer,di		; Save position
	  ret

atend:
		pop	  cx
	  mov	  di,pbuffer		; Restore position
	  ret
GoForwd	  ENDP


; 2.16 - calculate the line number backward function
; Procedure EndCount
; Input	    ES:DI has buffer position
; Output    Modifies "linenum"

EndCount  PROC
	  push  di

	  mov	  al,13			; Search for CR
	  mov	  linenum,0		; Initialize

findstrt:
		inc	  linenum		; Adjust count
	  mov	  cx,0FFh		; Load maximum character count
	  cmp	  cx,di			; Near start of	buffer?
	  jl	  notnear2		; No? Continue
	  mov	  cx,di			;   else search	only to	start
notnear2:
		repne	  scasb			; Find last previous cr
	  jcxz	  found			; If not found,	must be	at start
	  jmp		  SHORT	findstrt

found:
 		pop	  di
	  ret
EndCount  ENDP

; 2.17 - search string in lines
; Procedure SearchStr
; Purpose: search string in certain line and call highlight func
; Input			- line number
;						- address of string
; 					- endstring address of file
; output 		None

SearchStr proc
		push	bp
		mov	  bp,sp  		;Arg1
		push  si
		push  di
		push  ax
		push  cx
		push  es
		push  bx
	  mov   di,[bp+6] 	 	;Arg2
	  mov   [bp+10],di		;Arg3
lp1:
		mov   es,sbuffer
		mov   di,[bp+6]				;initilize primary address with input buffer
	  lea   si, statSearch
	  add 	si,9
	  mov   cx,searchPos		;length
	  cmp   cx,0
	  je    exitf
	  cld
	  repz  cmpsb
	  jz  	lp2
		mov		ax,[bp+6]         ;shifft 1 bit
		inc		ax
		mov	  [bp+6],ax
		jmp lp3
lp2:
    mov	  ax,[bp+10]          ; encount number of tab
    push	ax
    mov	  ax,[bp+6]						; primary address load
    push	ax
    call	CalTab							; calculate the number
    mov		bx,ax								; store res
	  mov		ax,[bp+8]           ;lines number
	  push	ax
	  mov		ax,[bp+6]
	  sub	  ax,[bp+10]         ; offset inlines
	  add		ax,bx              ; total with tab
	  push	ax
	  mov		ax,searchPos
	  push	ax
	  call	HighLight				; highlight the result string
		mov		ax,[bp+6]
    add		ax,searchPos
    mov		[bp+6],ax
  	jmp		lp3
lp3:												; check if this is the end of lines
		mov		ax,[bp+4]
		cmp		di,ax
		jb		lp1									; not equal to 1, not the end < , jump to lp1
exitf:
		pop bx
		pop es
		pop cx
		pop ax
		pop di
		pop si
		pop bp
		ret 6

		SearchStr endp


; 2.18 - highlight function
; Procedure HighLight
;	Purpose		highlight the search string if exist
;	Input 		- line number
;						- primary address
;						- characters number
;Output			None

HighLight proc
		push bp
		mov	 bp,sp
		push ax
		push bx
		push cx
		push es
		push di
		mov	 es,vidadr
		mov	 ax,[bp+8]		; Arg1
		mov	 bx,80*2			; characters number in the line
		mul	 bl
		mov	 di,ax
		add  di,[bp+6]
		add  di,[bp+6]	        ; Arg2
		mov  cx,[bp+4]         ; Arg3
		cmp  cx,0
		jne  t2
t1:
		pop di
		pop es
		pop cx
		pop bx
		pop ax
		pop bp
		ret 6
t2:
		mov bx,es:[di] ;修改配色
		mov bh,statatr
		mov es:[di],bx
		add di,2
		dec cx
		cmp cx,0
		jne t2
		jmp t1

		HighLight endp



; 2.19 - whether EGA is active
; Procedure isEGA
; Input	    None
; Output    0 if no; lines per screen if yes

isEGA	  PROC
	  push	bp
	  push	es
	  mov	  ah,12h		; Call EGA status function
	  mov	  bl,10h
	  sub	  cx,cx			; Clear	status bits
	  int	  10h
	  sub	  ax,ax			; Segment 0 and	assume no EGA
	  jcxz	noega			; If status still clear, no EGA

	  mov	  es,ax			; ES=0
	  test	BYTE PTR es:[487h],1000b ; Test active bit
	  jnz	  noega			; If set, not active
	  mov	  ax,1130h		; Get EGA information
	  int	  10h
	  mov	  al,dl			; Return lines per screen
	  cbw

noega:
		pop	  es
	  pop	  bp
	  ret
isEGA	  ENDP


; 2.20 - Converts integer to string
; Procedure BinToStr (number,address)
; Input	    Stack arguments: 1 - Number	to convert; 2 -	Near address for write
; Output    AX has characters written
BinToStr  PROC
	  push	bp
	  mov	  bp,sp
	  mov	  ax,[bp+6]		; Arg 1
	  mov	  di,[bp+4]		; Arg 2

	  sub	  cx,cx			; Clear	counter
	  mov	  bx,10			; Divide by 10

; Convert and save on stack backwards

getdigit:
		sub	  dx,dx			; Clear	top
	  div	  bx			; Divide to get	last digit as remainder
	  add	  dl,"0"		; Convert to ASCII
	  push	dx			; Save on stack
	  or	  ax,ax			; Quotient 0?
	  loopnz  getdigit		; No? Get another

; Take off the stack and store forward

	  neg	  cx			; Negate and save count
	  mov	  dx,cx
putdigit:
		pop	  ax			; Get character
	  stosb					; Store	it
	  loop	putdigit
	  mov	  ax,dx		; Return digit count

	  pop	  bp
	  ret	  4
BinToStr  ENDP


; 2.21 - wirte in CGA model
; Procedure Retrace
; Input	    ES:DI has screen buffer position, AX has cell
; Output    Character to screen	buffer

Retrace	  PROC
	  push  bx
	  mov	  bx,ax			; Save character
lscan2:
		in	  al,dx			; Look in the port
	  shr	  al,1			;   until it goes low
	  jc	  lscan2
	  cli
hscan2:
 		in	  al,dx			; Look in the port
	  shr	  al,1			;   until it goes high
	  jnc	  hscan2
	  mov	  ax,bx			; Restore and write it
	  stosw
	  sti
	  pop	  bx
	  ret
Retrace	  ENDP

; 2.22 - Calculate the tab number
; Procedure CalTab
; Input			- initial offset
;						- end offset
; Output		the number of tab to placeholder
CalTab proc
		push	bp
		mov	  bp,sp
		push  di
		push  bx
		xor 	ax, ax
		mov   di,[bp+6]			 ;Arg 1
		mov   [bp+8],di 			 ;Arg 2
lb1:
		mov   bl, es:[di]
		cmp   bl,9
		jne   lb2
		mov   bx,di
		sub   bx,[bp+8]        ; calculate the tab position
		add   bx,ax
		and   bx,7
		sub   bx,8
		neg   bx
		dec   bx               ; exinclude the initial one
		add   ax,bx
lb2:
		inc		di
		cmp   di,[bp+4]
		jb    lb1
lb3:
		pop		bx
		pop		di
		pop		bp
		ret 	4
		CalTab endp

	  END
