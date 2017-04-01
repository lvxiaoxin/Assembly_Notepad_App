; ---------------------------------------------------------------------------------------
; Created by: 吕鑫
; Study ID: 201411212012
; Subject: 汇编语言程序设计
; Date: 2016-12-29
;	Complete Date: 2017-01-02
; Description: - Program: SHOW.ASM   main program
; 						 - Purpose: Text file displayer
; 						 - Input: File name from command line or prompt (eg. SHOW.EXE TEST.ASM)
; 						 - Output: Display file to screen
;----------------------------------------------------------------------------------------

;--------------------------------------------------------------------------
; Table of Content
;--------------------------------------------------------------------------
; 0.0 - Declarations (.Model & .Stack)
; 1.0 - .DATA
;		  1.1 - Status line
;		  1.2 - Variables for Screen Handling
;		  1.3 - Variables for	buffer and file	handling
;		  1.4 - Call table
; 2.0 - .Code segment
; 		2.1 - Adjust memory	allocation
; 		2.2 - Allocate dynamic memory for file buffer
;			2.3 - Check the vision of DOS
; 		2.4 - Adjust for current mode and and video	adapter
;			2.5 - Try to open command line file
;			2.6 - Prompt for file
;			2.7 - Copy file name to status line
;			2.8 - Check	file size
;			2.9 - Search back for EOF marker and adjust	if necessary
;     2.10 - Display first	page
;			2.11 - Handle keys events
;			2.12 - keypad event, shortcut process
;--------------------------------------------------------------------------



; 0.0 - Declarations

PAGE	  60,132
TITLE	  SHOW

DOSSEG
	.MODEL  small

  INCLUDE dos.inc
  INCLUDE bios.inc

 	.STACK  100h

	.DATA



	; 1.1 - Status line
	PUBLIC  statline, linenum, statSearch, searchPos
	statSearch 	 DB   "/",100 dup(" ")
	statline 		 DB	  " Line:         " ; 在状态栏显示行号
	statfile 		 DB	  " File:                " ; 在状态栏显示正在读取的文件名字
	stathelp 		 DB	  "Search:ENTER Quit:ESC Move:  PGUP PGDN HOME END "
	linenum		 	 DW	  1

	; 1.2 - Variables for	screen handling
	PUBLIC  cell, rows, columns, vidadr, statatr, scrnatr, cga ; 依次声明屏幕显示单元、行、列、缓冲地址、配色1、配色2、CGA标识（对应vidadr）
	cell	  LABEL	  WORD		; Cell (character and attribute)
	char	  DB	  " "		; Initialize to	space
	attr	  DB	  ?		; Attribute
	columns	  EQU	  80		; Number of columns
	rows	  DW	  24		; Number of rows - status line takes one more
	mode	  DB	  ?		; Initial mode
	pag	  DB	  ?		; Initial display page
	newvid	  DB	  0		; Video	change flag
	cga	  DB	  1		; CGA flag - default yes
	vidadr	  DW	  0B800h	; Video	buffer address - default CGA
	mono	  EQU	  0B000h	; Monochrome address
	statatr	  DB	  030h		; Color	default	- black	on cyan
	bwstat	  EQU	  070h		; B&W default -	black on white
	scrnatr	  DB	  017h		; Color	default	- white	on blue
	bwscrn	  EQU	  007h		; B&W default -	white on black



	; 1.3 - Variables for	buffer and file	handling
	PUBLIC  buffer,pbuffer,sbuffer,fsize,namebuf ; 依次声明缓冲、缓冲偏移、缓冲段基址、文件大小
	buffer	  LABEL	  DWORD
	pbuffer	  DW	  0		; Position in buffer (offset)
	sbuffer	  DW	  ?		; Base of buffer (segment)
	lbuffer	  DW	  ?		; Length of buffer
	fhandle	  DW	  ?		; Holds	file handle on open
	fsize	 		DW	  ?		; File size after dosopen
	searchPos DW 		0
	prompt	  DB	  13,10,13,10,"Enter filename: $"
	prompt2	  DB	  13,10,"File problem. Try again? $"
	namebuf	  DB	  66,?
	filename  DB	  66 DUP (0)		; Buffer for file name
	err1	  DB	  13,10,"Must have DOS 2.0 or higher",13,10,"$"
	err2	  DB	  13,10,"File too big",13,10,"$"

	; 1.4 - Call table
	; 这里定义了函数调用
	exkeys	  DB	  71,72,73,79,80,81	; Extended key codes
	lexkeys	  EQU	  $-exkeys		; Table	of keys
	extable	  DW	  homek
  DW	  upk
  DW	  pgupk
  DW	  endk
  DW	  downk
  DW	  pgdnk
  DW	  nonek

	; 2.0 - .Code

	  .CODE
		EXTRN	  pager: PROC, isEGA:PROC	; Routines in other module
		start:
						mov	  ax,@DATA		; Initialize data segment as DATA
					  mov	  ds,ax
					  cli								; Turn off interrupts
					  mov	  ss,ax				; Initialize stack segment as DATA
					  mov	  sp,OFFSET STACK	; Initialize stack pointer
					  sti								; 打开中断


		;2.1 - Adjust memory allocation
					  mov	  bx,sp			; Convert stack	pointer	to paragraphs
					  mov	  cl,4			; to get stack size
					  shr	  bx,cl
					  add	  ax,bx			; Add SS to get	end of program
					  mov	  bx,es			; Get start of program
					  sub	  ax,bx			; Subtract start from end
					  @ModBlok ax			; Release memory after program

		;2.2 - Allocate dynamic memory for file buffer
					  @GetBlok 0FFFh			; Try to allocate 64K
					  mov	  sbuffer,ax		; Save buffer segment
					  mov	  lbuffer,bx		; Save actual length allocated

		;2.3 - Check the vision of DOS
					  @GetVer			; Get DOS version
					  cmp	  al,2			; Requires DOS 2.0
					  jge	  video
					  @DispStr err1			;   else error and quit
					  int	  20h

		;2.4 - Adjust for current mode and and video adapter, so as to check if the EGA is active, and return the number of row, if not, return 0
		; 判断EGA or VGA
		video:
						call isEGA						; EGA (or VGA)?
					  or	  ax,ax						; If 0 must be CGA or MA
					  je	  modechk					; Leave	default, 0 now, jump to modechk
					  mov	  rows,ax					; or Load rows
					  dec	  cga							; Not CGA
		;识别显示模式
		modechk:
						@GetMode			; Get video mode
					  mov	  mode,al		; Save initial mode and	page
					  mov	  pag,bh		; store the page
					  mov	  dl,al			; Work on copy
					  cmp	  dl,7			; Is it	mono 7?
					  je	  loadmono	; Yes? Set mono
					  cmp	  dl,15			; Is it	mono 15?
					  jne	  graphchk	; No? Check graphics

		loadmono:
				 		mov	  vidadr,mono		; Load mono address
					  mov	  statatr,bwstat	; Set B&W defaults for status line
					  mov	  scrnatr,bwscrn	;   and	screen background
					  dec	  cga			; Not CGA
					  cmp	  al,15			; Is it	mono 15?
					  jne	  cmdchk		; No? Done
					  mov	  dl,7			; Yes? Set standard mono
					  jmp	  SHORT	chmode

		graphchk:
						cmp	  dl,7			; 7 or higher?
					  jg	  color			; 8 to 14 are color (7 and 15 done)
					  cmp	  dl,4			; 4 or higher?
					  jg	  bnw				; 5 and	6 are probably black and white
					  je	  color			; 4 is color
					  test	  dl,1		; Even?
					  jz	  bnw				; 0 and	2 are black and	white

			color:								; 1 and	3 are color
					  cmp	  dl,3			; 3?
					  je	  cmdchk		; Yes? Done
					  mov	  dl,3			; Change mode to 3
					  jmp	  SHORT	chmode
			;配色方案
				bnw:
						mov	  statatr, bwstat	; Set B&W defaults for status line
					  mov	  scrnatr, bwscrn	; and	screen background
					  cmp	  dl,2			; 2?
					  je	  cmdchk		; Yes? Done
					  mov	  dl,2			; Make it 2
			;设置显示模式
			chmode:
						@SetMode dl				; Set video mode
					  @SetPage 0				; Set video page
					  mov	  newvid,1		; Set flag

			;2.5 - Try to open command line file
			cmdchk:
						mov	  bl,es:[80h]		; Get length
					  sub	  bh,bh
					  mov	  WORD PTR es:[bx+81h],0; Convert to ASCIIZ
					  push	  ds
					  @OpenFil 82h,0,es		; Open argument
					  pop	  ds
					  jc	  getname		; If error, get	from prompt
					  mov	  fhandle,ax		;   else save handle
					  push	  ds
					  @GetFirst 82h,,es		; Let DOS convert to file name
					  pop	  ds
					  jnc	  opened		; If OK	file is	open


			;2.6 - Prompt for file
			getname:										;get the filename
						@DispStr prompt				; Prompt for file
					  @GetStr namebuf,0			; Get response as ASCIIZ
					  @OpenFil filename,0		; Try to open response
					  jc	  badfile					; If successful, continue
					  mov	  fhandle,ax			; Save handle
					  @GetFirst filename		; Let DOS convert to file name
					  jnc	  opened					; If OK, file is opened

			badfile:  								  ; 打开失败了
						@DispStr prompt2			; else prompt to try	again
					  @GetKey 0,1,0
					  and	  al,11011111b		; Convert key to uppercase
					  cmp	  al,"Y"		;		If yes,
					  je	  getname		;   try	again
					  jmp	  quit			;   else quit

			;2.7 - Copy file name to status line
			opened:
						mov	  si, 9Eh		; Load FCB as as source
					  mov	  di, OFFSET statfile[5]	; Load status line as destination
					  mov	  al, es:[si]		; Load first byte
					  inc	  si
			copy:
				 		mov	  [di], al		; Save and load	bytes until 0
					  inc	  di
					  mov	  al, es:[si]
					  inc	  si
					  or	  al, al			; Check	for 0, 这里只要不是0，就会继续复制
					  loopne  copy

			;2.8 - Check	file size
					  @GetFilSz fhandle		; Get file size
					  or	  dx,dx					; Larger than 64K?
					  jne	  big						; Yes? Too big
					  mov	  fsize,ax			; Save file size
					  mov	  cx,4					; Convert to paragraphs
					  shr	  ax,cl
					  cmp	  ax,lbuffer		; Is it	larger than buffer
					  jle	  fileread			; No? Continue

   			big:
			  		@DispStr err2			;  错误，因为文件太大了
	  			  @Exit	  2

      	fileread:										; 文件读取
					push	  ds
				  @Read	  buffer,fsize,fhandle
				  pop	  ds
				  jnc	  readok		; If no	read error continue
				  jmp	  getname		;   else try again


			;2.9 - Search back for EOF marker and adjust	if necessary
      readok:
					mov	  di,ax			; Load file length
				  push	es			; Save ES and load buffer segment
				  mov	  es,sbuffer
				  std				; Look backward	for 255	characters
				  mov	  cx,0FFh
				  mov	  al,1Ah		; Search for EOF marker
				  repne	  scasb
				  cld
				  jcxz	  noeof			; If none, we're OK
				  inc	  di			;   else adjust	and save file size
				  mov	  fsize,di

			noeof:
			  	pop	  es
				  @SetCurPos 0,43		; Turn off cursor by moving off	screen


			;2.10 - Display first	page
	  			xor	  ax,ax			; Start	at 0
	  			push	  ax
			firstpg:
			  	call	  pager


			;2.11 - Handle keys events
			nextkey:
					@GetKey 0,0,0			; Get a	key
			nextkey2:
					cmp	  al,0			; Is it	a null?
				  je	  extended		; Yes? Must be extended	code
				  cmp	  al,27			; Is it	ESCAPE?
					je quit
					cmp al, 13			; 搜索
					je  searchDriver
					call Enterk
				  jmp	  nextkey		; No? Ignore unknown command

			searchDriver:
					call searchk
					jmp nextkey


			quit:
					cmp rows, 23
					je searchDriver
			 		@ClosFil fhandle		; Yes? Close file 这里是ESC
				  @FreeBlok sbuffer		; Release buffer
				  cmp	  newvid,1		; Restore video?
				  jne	  thatsall		; No?
				  @SetMode mode			; Restore video	mode, page, and	cursor
				  @SetPage pag
			thatsall:						;行数滚动更新
					mov	  dx,rows		; Load last row	and first column
				  xchg	dl,dh
				  mov	  cx,dx			; Make row the same
				  mov	  dl,79
				  @Scroll 0				; Clear	last line
				  sub	  dl,dl
				  @SetCurPos			; Set cursor

	  			@Exit	  0			; Quit

			extended:
					@GetKey 0,0,0			; Get extended code
				  push	  es
				  push	  ds			; Load DS into ES
				  pop	  es
				  lea	  di, exkeys	; Load address and length of key list
				  mov	  cx,lexkeys+1
				  repne	  scasb			; Find position
				  pop	  es
				  sub	  di,(OFFSET exkeys)+1	; Point	to key
				  shl	  di,1			; Adjust pointer for word addresses
				  call	  extable[di]		; Call procedure
				  jmp	  nextkey


			homek:
			  	mov	  pbuffer,0		; HOME - set position to 0
				  push  pbuffer
				  mov	  linenum,1
				  call	pager
				  retn

	  	upk:
					mov	  ax,-1			; UP - scroll back 1 line
				  push	ax
				  call	pager
				  retn

			pgupk:
					mov	  ax,rows		; PGUP - Page back
				  neg	  ax
				  push  ax
				  call	pager
				  retn

			endk:
					mov	  ax,fsize			; END -	Get last byte of file
				  mov	  pbuffer,ax		; Make it the file position
				  mov	  linenum,-1		; Set illegal line number as flag
				  mov	  ax,rows				; Page back
				  neg	  ax
				  push	ax
				  call	pager
				  retn

			downk:
					mov	  ax,1			; down - scroll	forward	1 line
				  push	ax
				  call	pager
				  retn

			pgdnk:
					push	rows			; pgdn - page forward
				  call	pager
				  retn

			nonek:
					retn				; ignore unknown key


			;2.12 - keypad event, shortcut process
			searchk:
					cmp rows,24
					jne result1
					mov ax, 23
					jmp result2
			result1:
					mov ax ,24
			result2:
			  	mov rows,ax
					mov ax, searchPos     ; 初始化buffer
			result3:
			 		mov si,9
					cmp ax,0
					jne  result4
					mov searchPos, ax
					xor ax, ax
					push ax
					call pager
					retn
			result4:
					dec ax
					add si,ax
					mov statSearch[si],' '
					cmp ax,0
					jne result3

			; enter to search
			enterk:								;搜索栏激活判断
					cmp rows,23
					jne	cEnter4

			cEnter1:
					mov si,9
					add si,searchPos
					cmp al,8					;退格键？
					je cEnter2
					mov statSearch[si], al		;	输出字串并更新位置
					inc searchPos
					jmp cEnter3
			cEnter2:
					cmp searchPos,0			;退到头
					je cEnter4
					dec si
					mov statSearch[si],' '
					dec searchPos
					jmp cEnter3
  		cEnter3:
					xor ax, ax
					push ax
					call pager
			cEnter4:
					retn

				  end	 start
