;
;	Copyright (C) 2021 by Ladislau Szilagyi
;
;	RTM/Z80 Multitasking kernel - part 1/2
;
*Include config.mac

	psect	text

COUNTER_OFF	equ	4	;Sem counter offset
DLIST_H_SIZE	equ	4	;List header size
TCB_H_SIZE	equ	20H	;TCB header size
;
ALLOCSTS_OFF	equ	4	;AllocStatus in TCB
BLOCKSIZE_OFF	equ	5	;BlockSize in TCB
PRI_OFF		equ	6	;Priority in TCB
SP_OFF		equ	7	;StackPointer in TCB
SEM_OFF		equ	9	;LocalSemaphore in TCB
ID_OFF		equ	15	;ID in TCB
NXPV_OFF	equ	16	;(NextTask,PrevTask)
WAITSEM_OFF	equ	20	;WaitSem
STACKW_OFF	equ	22	;StackWarning
;
COND	CMD
SYS_TASKS_NR	equ	3	;Default task + CON driver + CMD handler
ENDC
COND	NOCMD
SYS_TASKS_NR	equ	2	;Default task + CON driver 
ENDC
;
MAX_TASKS_NR	equ	32	;tasks number limit
;										NOCPM
COND	NOCPM
CODE_BASE:			;at 0000H
COND	ROM
COND	BOOT_CODE
	GLOBAL	boot
	jp	boot		;ROM boot
	defw	__FirstFromL	;used to re-make "jp __FirstFromL" at 0
	defs	3
ENDC
COND	NOBOOT_CODE
	jp	__FirstFromL
	defw	__FirstFromL
	defs	3
ENDC
ENDC
COND	NOROM
;0000H	RST	0
	jp	__FirstFromL
	defs	5
ENDC
;0008H	RST	8
	jp	__LastFromL
	defs	5
;0010H	RST	16
	jp	__NextFromL
	defs	5
;0018H	RST	24	
	jp	__AddToL
	defs	5
;0020H	RST	32
	jp	__RemoveFromL
	defs	5
;0028H	RST	40
	jp	__GetFromL
	defs	5
;0030H	RST	48
	jp	__InsertInL
	defs	5
;0038H	RST	56
COND	WATSON
	jp	Breakpoint
	defs	5
ENDC
COND	NOWATSON
	defs	8
ENDC

;0040H	SYSTEM START ADDRESS IS HERE
;
;	under DISABLE interrupts
;	LOW 64K RAM is already selected 
;
	ld	sp,UP_TO_LOW_6W	;set a temporary SP
	call	_main		;Start user code
	ld	hl,0
	ld	(_PC),hl	;set recorded PC=0 (system was shutdown)
STOP:				;RTM/Z80 was shutdown or breakpoint was reached
	jp	RTM_EXIT
;
COND	WATSON
;
;	Breakpoint was reached
;	The following registers are stored at 0DFE8H:
;	AF,BC,DE,HL,AF',BC',DE',HL',IX,IY,SP,PC
;	
Breakpoint:
	di
	ex	(sp),hl
	dec	hl			;PC decremented to RST addr
	ld	(_PC),hl		;breakpoint PC stored at 0DFFEH
	ld	hl,0
	add	hl,sp
	ld	(_PC-2),hl		;SP stored at 0DFFCH
	ex	(sp),hl
	ld	sp,_PC-2
	push	iy
	push	ix
	exx
	ex	af,af'
	push	hl
	push	de
	push	bc
	push	af
	exx
	ex	af,af'
	push	hl
	push	de
	push	bc
	push	af
	ld	sp,TCB_Dummy		;move SP to a neutral area
	call	Snapshot		;take a snapshot
	call	StopHardware		;shutdown the hardware interrupt sources
	jr	STOP			;stop and return to SCM
;
ENDC
;
;	Init Interrupts
;
_InitInts:
	di				;disable interrupts
;
;	Real Time Clock
;
;CTC_0, CTC_1, CTC_3
;
	ld	a,00000011B	;disable int,timer,prescale=16,don't care,
 				;don't care,no time constant follows,reset,control
	out 	(CTC_0),a	;CTC_0 is on hold now
	out 	(CTC_1),a	;CTC_1 is on hold now
	out 	(CTC_3),a	;CTC_3 is on hold now
;
;CTC_2	Real Time Clock
;
	ld	a,10110111B	;enable ints,timer,prescale=256,positive edge,
				;dont care,const follows,reset,control
	out	(CTC_2),a
	ld	a,144		;7.3728 MHz / 256 / 144 ==> 200Hz = 5ms interrupt period
	out	(CTC_2),a
;
;CTC interrupt vector
;
	ld	a,00000000B	;adr7 to adr3=0,vector ==> INT level 2
	out	(CTC_0),a	;set vector
;
;	SIO (async)
;
;	Init SIO
;
	ld	hl,SIO_A_TAB
	ld	c,SIO_A_C	;SIO_A
	ld	b,SIO_A_END-SIO_A_TAB
	otir			
				;HL=SIO_B_TAB
	ld	c,SIO_B_C	;SIO_B
	ld	b,SIO_B_END-SIO_B_TAB
	otir
;
;	Interrupt mode
;
;	setup IM 2 
;
	im	2
	ld	a,INT_TAB/100H
	ld	i,a
	ret			;DI still ON
;
;	Stop Hardware devices
;
;	called under DI
;	reset all hardware devices, kill all possible interrupts
;	HL not affected
;
StopHardware:
;
;	stop CTC_2
;
	ld	a,00000011B	;disable int,timer,prescale=16,don't care,
 				;don't care,no time constant follows,reset,control
	out (CTC_2),a 		;CTC_2 is on hold now
;
;	stop SIO
;
	ld	a,00011000B		;A WR0 Channel reset
	out	(SIO_A_C),a
	ld	a,00011000B		;B WR0 Channel reset
	out	(SIO_B_C),a
COND	DIG_IO
	SET_LEDS	0		;RTM/Z80 stopped
ENDC
	ret
;
;	Only to execute RETI, when this is needed
;	May be used to track the "unwanted" interrupts
IntRet:	 
	ei
	reti
;
SIO_A_TAB:
	defb	00011000B	;WR0 Channel reset
	defb	00000010B	;WR0 Pointer R2
	defb	00000000B	;WR2 interrupt address
	defb	00010100B	;Wr0 Pointer R4 + reset ex st int
	defb	11000100B	;Wr4 /64, async mode, 1 stop bit, no parity
	defb	00000011B	;WR0 Pointer R3
	defb	11100001B	;WR3 8 bit, Auto enables, Receive enable
	defb	00000101B	;WR0 Pointer R5
	defb	11101010B	;WR5 DTR, 8 bit, Transmit enable, RTS
	defb	00010001B	;WR0 Pointer R1 + reset ex st int
	defb	00011010B	;WR1 interrupt on all RX characters, TX Int enable
SIO_A_END:			;parity error is not a Special Receive condition

SIO_B_TAB:
	defb	00011000B	;WR0 Channel reset
	defb	00000010B	;WR0 Pointer R2
	defb	00010000B	;WR2 interrupt address = 10H
	defb	00010100B	;Wr0 Pointer R4 + reset ex st int
	defb	11000100B	;Wr4 /64, async mode, 1 stop bit, no parity
	defb	00000011B	;WR0 Pointer R3
	defb	11000000B	;WR3 8 bit
	defb	00000101B	;WR0 Pointer R5
	defb	01100000B	;WR5 8 bit
	defb	00010001B	;WR0 Pointer R1 + reset ex st int
	defb	00000100B	;WR1 no INTS on channel B, status affects INT vector
SIO_B_END:			;INTs: BTX,BE/SC,BRX,BSRC,ATX,AE/SC,ARX,ASRC
;
;	Default task
;
DefaultStart:
	di
	call	ClearAllGarbage		;clean all garbage
	ei
	nop		
	jr	z,DefaultStart		;if shutdown marker found...
	di				;DISABLE Interrupts	
COND	WATSON
	call	Snapshot		;move LOW_RAM to UP_RAM
ENDC
RETURN:					;return to the caller of StartUp
	call	StopHardware		;shutdown the hardware interrupt sources
	ld	sp,(_InitialSP)		;restore initial SP
	POP_ALL_REGS
	ret				;Interrupts still DISABLED
;
;	Forced exit from an interrupt, quitting RTM/Z80
;	called under DI
;
RETI_RETURN:
	call	StopHardware	;shutdown the hardware interrupt sources
	ld	sp,(_InitialSP)	;restore initial SP
	POP_ALL_REGS
	reti			;Interrupts remain DISABLED
;
;	memory pad used to fill the space till 100H
;
	defs	100H - ($ - CODE_BASE)
;
INT_TAB equ 100H
;
;	must be placed at an address multiple of 100H
;
INTERRUPTS:
	defw	IntRet;+00H
	defw	IntRet;+02H
	defw	_RTC_Int	;+04H	CTC_2 Real Time Clock (5 ms)
	defw	IntRet;+06H
	defw	IntRet;+08H
	defw	IntRet;+0AH
	defw	IntRet;+0CH
	defw	IntRet;+0EH
	defw	IntRet;+10H	SIO_B transmit buffer empty		-inactive
	defw	IntRet;+12H	SIO_B external/status change		-inactive
	defw	IntRet;+14H	SIO_B receive character available	-inactive
	defw	IntRet;+16H	SIO_B special receive condition		-inactive
	defw	_CON_TX		;+18H	SIO_A transmit buffer empty
	defw	_CON_ESC	;+1AH	SIO_A external/status change
	defw	_CON_RX		;+1CH	SIO_A receive character available
	defw	_CON_SRC	;+1EH	SIO_A special receive condition

	psect	bss

;	UNINITIALIZED DATA - at multiple of 100H
;
CleanReqB:	defs	100H	;Memory garbage cleaner requests buffer
				;contains TCB ID to clean 
				;or 0 to stop cleaning and quit Default task
SIO_buf:	defs	100H	;SIO receive buffer
;
		defs	200H	;HEX loader buffers
;
;	For SC108 - Tasks related data - placed at BSS base + 400H
;
;	WATSON POINTERS					
AllTasksH:	defs	2	;TCB_Default+NXPV_OFF	;All tasks list header
		defs	2	;TCB_Default+NXPV_OFF
_TasksH:	defs	2	;TCB_Default	;active tasks TCB's priority ordered list header
		defs	2	;TCB_Default
_RunningTask:	defs	2	;TCB_Dummy	;current active task TCB
pLists:		defs	2	;Lists		;pointer of list of headers for free mem blocks
RTC_Header:	defs	2	;RTC_Header	;Real Time clock control blocks list header
		defs	2	;RTC_Header
;	END OF POINTERS
;
TCB_Default:			;TCB of default task
	;bElement header
	defs	2	;_TasksH	;void* next;
	defs	2	;_TasksH	;void* prev;
	defs	1	;1	;char AllocStatus; 
	defs	1	;3	;char BlockSize; set for a TCB with size 80H, but NOT NEEDED
	defs	1	;0	;char Priority=0;
DefSP:	defs	2	;def_sp	;void* StackPointer;
	;local semaphore
def_sem:defs	2	;def_sem	;void*	first;
	defs	2	;def_sem	;void*	last;
	defs	2	;0	;short	Counter;
	defs	1	;1	;ID=1
	defs	2	;AllTasksH;nextTask
	defs	2	;AllTasksH;prevTask
	defs	2	;0	;WaitSem
	defs	1	;0	;StackWarning
			;local stack area (we need here ~ 60H bytes)
	defs	21H
TCB_Dummy:	;TCB of dummy task - discarded after first StartUp call (10H here)
		;placed here to gain some stack space for Default Task
	defs	2	;void* next;
	defs	2	;void* prev;
	defs	1	;char AllocStatus; 
	defs	1	;char BlockSize; 
	defs	1	;char Priority;
	defs	2	;void* StackPointer;
			;local semaphore
	defs	2	;void*	first;
	defs	2	;void*	last;
	defs	2	;short	Counter;
	defs	1	;1	;ID=1 to be used at first allocs 
			;(that's why TCB_Dummy is needed !)
	defs	2DH	;this will be the impacted area of stack (2DH here)
def_sp:			;0EH here = TOTAL ~ 70H
	defs	2	;IY
	defs	2	;IX
	defs	2	;BC
	defs	2	;DE
	defs	2	;HL
	defs	2	;AF
	defs	2	;DefaultStart	;Default Task start address
;
			;Available block list headers
L0:	defs	4
L1:	defs	4
L2:	defs	4
L3:	defs	4
L4:	defs	4
L5:	defs	4
L6:	defs	4
L7:	defs	4
L8:	defs	4
L9:	defs	4
;
Lists:	defs	20
;
Buddy:	defs	20
;
CON_IO_Wait_Sem:defs    6	;CON Driver Local semaphore
;
CON_IO_Req_Q:			;CON Device driver I/O queue
;
CON_IO_WP:defs	2	;write pointer
CON_IO_RP:defs	2	;read pointer
CON_IO_BS:defs	2	;buffer start
CON_IO_BE:defs	2	;buffer end
	  defs	1	;balloc size
	  defs	2	;batch size (allways 10)
CON_IO_RS:defs	6	;read sem
CON_IO_WS:defs	6	;write sem
;
;	we are at BSS base + 500H
;
CON_Driver_TCB:	defs	2	;CON Driver TCB
;
CMD_TCB:	defs	2	;CMD task TCB
;
_InitialSP:	defs	2	;SP of StartUp caller
;
COND	DIG_IO
IO_LEDS:defs	1	;LEDs
ENDC
;
; !!! the order below is critical, do not move them !!!
CleanRP:defs	2	;CleanReqB	;read pointer
CleanWP:defs	2	;CleanReqB	;write pointer
PrioMask:defs	1	;0FFH	;used to filter user task priorities (1 to 127)
				;will be modified to 7FH after startup !
IdCnt:	defs	1	;1	;used to generate tasks ID
TasksCount:defs	1	;1	;All tasks counter

COND	DEBUG
tmpbuf:	defs	7	;0DH,0AH,4 blanks,!
ENDC

	psect	text

ENDC
;										NOCPM
;										CPM
COND	CPM
*Include cpmdata.as
ENDC
;										CPM
	GLOBAL	RET_NULL,EI_RET_NULL,RET_FFFF,EI_RET_FFFF
	GLOBAL	Lists,L9,L0,Buddy
	GLOBAL	LastActiveTCB,TicsCount,Counter,SecondCnt,RoundRobin
	GLOBAL	CON_IO_Wait_Sem,CON_IO_Req_Q,CON_IO_WP,CON_IO_RP
	GLOBAL	CON_IO_BS,CON_IO_BE,CON_IO_RS,CON_IO_WS
	GLOBAL	SIO_WP,SIO_RP,EchoStatus
	GLOBAL	RETURN,RETI_RETURN
COND	SIO_RING
	GLOBAL	GetSIOChars
ENDC
COND	CMD
	GLOBAL _CMD_Task
ENDC

;										NOCPM
COND	NOCPM
COND	WATSON
	GLOBAL  Snapshot
ENDC
COND	NOROM
	GLOBAL	_main
ENDC
	GLOBAL	_CON_ESC,_CON_SRC
	GLOBAL	SIO_buf
ENDC
;										NOCPM
COND	C_LANG
	GLOBAL _GetHost
	GLOBAL _GetSemSts,_MakeSem,_DropSem,_Signal,_Wait,_ResetSem
	GLOBAL _GetTaskByID
ENDC
	GLOBAL	CON_CrtIO,CON_Count,_CON_TX,_CON_RX
	GLOBAL RTC_Header,CON_Driver_IO
	GLOBAL CleanWP,CleanRP,ClearAllGarbage
	GLOBAL QuickSignal
	GLOBAL __GetSemSts,__MakeSem,__DropSem,__InitSem,__InitSetSem,__Signal,__Wait,__ResetSem
	GLOBAL __GetHost
	GLOBAL __Balloc,__Bdealloc,__BallocS,_InitBMem
	GLOBAL __InitL,__AddToL,__RemoveFromL,__FirstFromL,__LastFromL,__NextFromL
	GLOBAL __InsertInL,__GetFromL,__RotateL,__AddTask,__IsInL
	GLOBAL _RunningTask,_TasksH,AllTasksH
	GLOBAL _GetID,__GetTaskByID
	GLOBAL _Reschedule,_ReschINT,Resch_or_Res,_ResumeTask,QuickStopTask
	GLOBAl IsItTask,IsItActiveTask,IsSuspended
	GLOBAL _RTC_Int
	GLOBAL __StopTaskTimer
	GLOBAL __KillTaskIO
COND	DEBUG
	GLOBAL	IsItSem,CON_Wr_Sch,DE_hex
ENDC
	GLOBAL _InitialSP,_InitInts,SecondCnt,SIO_buf,SIO_WP,SIO_RP,LastActiveTCB,TicsCount
	GLOBAL Counter,RoundRobin,EchoStatus,CON_CrtIO,TCB_Default,AllTasksH,_TasksH,TCB_Dummy
	GLOBAL _RunningTask,Lists,pLists,RTC_Header,def_sp,DefSP,def_sem,DefaultStart
	GLOBAL CON_Driver_TCB,CMD_TCB,PrioMask,_Reschedule,TasksCount,IdCnt
COND	NOCPM
	GLOBAL CleanReqB,CleanRP
COND	DEBUG
	GLOBAL tmpbuf
ENDC
ENDC

;									CPM
COND	CPM
;
;	Default task
;
DefaultStart:
	ld	a,(CON_CrtIO)		;check current CON I/O opcode
	cp	IO_RAW_READ
	jr	nz,nothing		;if not IO_RAW_READ, nothing to simulate
	ld	a,(CON_Count)
	or	a
	jr	z,nothing		;if I/O counter zero, nothing to simulate
	call	_CON_RX			;if IO_RAW_READ, go to RX interrupt, no echo, uses 14H stack space
nothing:
	di
	call	ClearAllGarbage		;clean all garbage
	ei
	nop		
	jr	z,DefaultStart		;if shutdown marker found...
	di				;DISABLE Interrupts	
RETURN:					;return to the caller of StartUp
	call	StopHardware		;shutdown the hardware interrupt sources
	ld	sp,(_InitialSP)		;restore initial SP
	POP_ALL_REGS
	ret				;Interrupts still DISABLED
;
_InitInts:
	di				;disable interrupts
COND	Z80SIM_CHECK
	ld	hl,0FB11H		;check for Udo!
	ld	a,(hl)
	cp	'U'
	jr	nz,notz80sim
	inc	hl
	ld	a,(hl)
	cp	'd'
	jr	nz,notz80sim
	inc	hl
	ld	a,(hl)
	cp	'o'
	jr	z,z80sim
notz80sim:				;NOT in Z80SIM
	ld	hl,msgNotZ80SIM		;write err msg
loopq:	
	ld	a,(hl)
	or	a
	jr	z,rebootcpm
	ld	e,a
	ld	c,2
	push	hl
	call	5
	pop	hl
	inc	hl
	jr	loopq
rebootcpm:
	ld	c,0
	call	5
msgNotZ80SIM:
	defb	0dh,0ah
	defm	'Must be executed under Z80SIM, quitting!'
	defb	0
z80sim:
ENDC				
	ld	a,jp			;valid ONLY for Z80SIM
	ld	(38H),a			;RTC int at RST 38H
	ld	hl,_RTC_Int
	ld	(39H),hl
	ld	a,1			;start RTC ints
	out	(27),a
	im	1
	ret
;
StopHardware:
					;valid ONLY for Z80SIM
	xor	a			;stop RTC ints
	out	(27),a
	ret
;
;	Forced exit from an interrupt, quitting RTM/Z80
;	called under DI
;
RETI_RETURN:
	call	StopHardware	;shutdown the hardware interrupt sources
	ld	sp,(_InitialSP)	;restore initial SP
	POP_ALL_REGS
	reti			;Interrupts remain DISABLED
;
ENDC
;									CPM
;	Get Current TCB ID
;
;	returns A=TCB_ID
;	HL,DE,IX,IY not affected
;	A, BC affected
;
_GetID:
	ld	bc,(_RunningTask)
	ld	a,ID_OFF
	add	a,c
	ld	c,a
	ld	a,(bc)		;A=TCB ID
	ret
;
;	Get Host 
;
;	returns HL=0 : CPM , HL=1 : RC2014
;
COND	C_LANG
_GetHost:
ENDC
__GetHost:
COND	CPM
	ld	hl,0
ENDC
COND	NOCPM
	ld	hl,1
ENDC
	ret
;
COND	C_LANG
;
;	GetTaskByID
;
;short	GetTaskByID(short id);
;	returns HL=TCB or 0 if not found
;
_GetTaskByID:
	ld	hl,2
	add	hl,sp
	ld	c,(hl)
	call	__GetTaskByID
	ret	nz
	jp	RET_NULL
ENDC
;
;	Search task with ID=C
;	return Z=1 & HL=0 : no TCB was found, else Z=0 & HL=TCB
;	AF,HL,DE affected
;
__GetTaskByID:
        ld      hl,AllTasksH
	ld	d,h
	ld	e,l		;DE=tasks header
NxT:  	ld      a,(hl)		;get next in list
        inc     l
        ld      h,(hl)          
	ld	l,a		;HL=TCB+NXPV_OFF
	push	hl
	or	a		;CARRY=0
        sbc     hl,de
	pop	hl
        ret	z	        ;if next=header, return Z=1
	dec	l		;HL=ID pointer
	ld	a,(hl)		;A=Crt ID
	inc	l		;HL=TCB+NXPV_OFF
	cp	c		;equal to target ID?
	jr	nz,NxT
	ld	a,l
	sub	NXPV_OFF
	ld	l,a
	or	h		;HL=TCB, Z=0
	ret
;
;	Get Sem Status
;short	GetSemSts(void* S)
;	returns HL=-1 : no sem, else HL=sem counter
COND	C_LANG
_GetSemSts:
	ld	hl,2
	add	hl,sp
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
ENDC
__GetSemSts:			;HL=Sem
	di
COND	DEBUG
	call	IsItSem
	jp	nz,EI_RET_FFFF
ENDC
	ld	a,l
	add	a,COUNTER_OFF
	ld	l,a
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a
	ei
	ret			;HL=counter
;	
COND	C_LANG
;
;	Create semaphore
;
;void*	MakeSem(void);
;	AF,BC,DE,HL,IX,IY not affected
;	returns HL = SemAddr or NULL if alloc failed
;
_MakeSem:
	push	af
	push	bc
	push	de
	call	__MakeSem
	pop	de
	pop	bc
	pop     af
	ret
;
;	Reset Semaphore
;
;void*	ResetSem(void* Semaphore)
;	returns HL=0 if task is waiting for semaphore, else not NULL
;
_ResetSem:
	push	af
	push	bc
	push	de
	ld	hl,8
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	call	__ResetSem
	pop	de
	pop	bc
	pop	af
	ret
ENDC
;
;	Create semaphore - internal
;
;	return Z=0 & HL=SemAddr or Z=1 & HL=0 if alloc failed
;	affects A,BC,DE,HL
;
__MakeSem:
	ld	c,0		;alloc 10H
	di
	call	__Balloc
	jr	z,1f		;if alloc failed, return 0
				;HL=block addr
	ld	a,B_H_SIZE
	add	a,l
	ld	l,a		;HL=sem addr=list header addr	
	call	__InitSem
1:	ei
	ret
;
;	Initialize semaphore - internal
;
;	called under DI
;	HL=SemAddr
;	return HL=SemAddr
;	does not affect BC
;
__InitSem:
	call	__InitL
	ld	a,COUNTER_OFF
	add	a,l
	ld	l,a		;HL=Sem counter pointer
	xor	a		;A=0
	ld	(hl),a		;Sem counter = 0
setcnth:inc	l
	ld	(hl),a
	ld	a,l
	sub	COUNTER_OFF+1	;Z=0 if called from MakeSem !!!
	ld	l,a		;HL=SemAddr
	ret
;
;	Initialize semaphore and set its counter - internal
;
;	called under DI
;	HL=SemAddr, C=counter
;	return HL=SemAddr
;	does not affect BC
;
__InitSetSem:
	call	__InitL
	ld	a,COUNTER_OFF
	add	a,l
	ld	l,a		;HL=Sem counter pointer
	ld	(hl),c		;Set Sem counter
	xor	a
	jr	setcnth
;
;	Reset Semaphore - internal
;
;	HL = semaphore
;	returns HL=0 if task is waiting for semaphore, else not NULL
;
__ResetSem:
	di
COND	DEBUG
	push	hl
	ld	c,(hl)
	inc	l
	ld	b,(hl)		;BC=first in sem list
	scf			;CARRY=1
	sbc	hl,bc		;is it equal to sem?
	pop	hl
	jr	z,1f		;yes, it's a semaphore
;								DIG_IO
COND DIG_IO
	OUT_LEDS ERR_SEM
ENDC
;								DIG_IO
	jp	EI_RET_NULL	;task is waiting for semaphore, return 0
1:
ENDC
	call	__InitSem
	ei
	ret
;
COND	C_LANG
;
;	Drop Semaphore
;
;short	DropSem(void* SemAddr)
;	AF,BC,DE,HL,IX,IY not affected
;	returns HL=0 if not a semaphore, else 1
;
DropSaddr	equ	8
;
_DropSem:
	push	de
	push	bc
	push	af
	ld	hl,DropSaddr
	add	hl,sp		;stack=AF,BC,DE,retaddr,Sem addr
	ld      a,(hl)
	inc	hl
	ld      h,(hl)
	ld	l,a		;HL=Sem list header pointer
	call	__DropSem
	pop     af
	pop	bc
	pop	de
	ret
ENDC
;
;	Internal Drop Semaphore 
;
;	HL=Sem addr
;	returns HL=0 if not a semaphore or task is waiting for semaphore, else 1
;	Affected regs: A,BC,DE,HL
;	IX,IY not affected
;
__DropSem:
	di
;										DEBUG
COND	DEBUG
	call	IsItSem
	jr	z,1f
;								DIG_IO
COND DIG_IO
	OUT_LEDS ERR_SEM
ENDC
;								DIG_IO
	jp	EI_RET_NULL	;no, it is no a semaphore, return 0
1:
	push	hl
COND	NORSTS
	call	__FirstFromL
ENDC
COND	RSTS
	RST	0
ENDC
	pop	hl
	jp	nz,EI_RET_NULL	;if task list not empty, cannot drop semaphore
	ld	c,0		;10H
ENDC
;										DEBUG
	ld	a,l
	sub	B_H_SIZE
	ld	l,a		;HL=10H block addr
	call	__Bdealloc	;deallocate-it
	ei
	ret
COND	C_LANG
;
;	Signal semaphore
;
;short	Signal(void* SemAddr);
;	AF,BC,DE,HL,IX,IY not affected
;	return HL=0 if wrong semaphore address provided, else not null
;
SigSem	equ	14
;
_Signal:
	PUSH_ALL_REGS
	ld	hl,SigSem
	add	hl,sp		;stack=AF,BC,DE,HL,IX,IY,retaddr,Sem addr
	ld      a,(hl)
	inc	hl
	ld      h,(hl)
	ld	l,a		;HL=Sem list header pointer
	di
;										DEBUG
COND	DEBUG
	call	IsItSem
	jr	z,1f
;								DIG_IO
COND DIG_IO
	OUT_LEDS ERR_SEM
ENDC
;								DIG_IO
				;no, it is not a semaphore, return 0
	xor	a		;Z=1 to just resume current task
	ld	h,a
	ld	l,a		;return HL=0
	jp	Resch_or_Res
1:
ENDC
;										DEBUG
	call	QuickSignal
				;Z=0? (TCB was inserted into active tasks list?)
	jp	Resch_or_Res	;yes : reschedule, else just resume current task
ENDC
;
;	Signal semaphore internal
;
;	HL=Semaphore address
;	return CARRY=1 if wrong semaphore address provided, else CARRY=0
;
__Signal:
	di
;										DEBUG
COND	DEBUG
	call	IsItSem
	jr	z,1f
;						DIG_IO
COND DIG_IO
	OUT_LEDS ERR_SEM
ENDC
;						DIG_IO
	scf			;no, it is not a semaphore, return CARRY=1
	ei
	ret
1:
ENDC
;										DEBUG
	call	QuickSignal
	jr	nz,1f		;Z=0? (TCB was inserted into active tasks list?)
	ei			;no, just resume current task 
	ret
1:				;yes : reschedule, CARRY=0
	push	af		;save CARRY value on stack
	ld	hl,-10		;space for 5 push (HL,DE,BC,IX,IY)
	add	hl,sp
	ld	sp,hl
	jp	_Reschedule
;
;	Signal semaphore without reschedule
;
;	called under DI
;	HL=Semaphore address
;	returns CARRY=0
;	returns Z=0 and A!=0 and HL=TCB inserted into active tasks list, 
;	or Z=1 and A=0 and HL not NULL if only counter was incremented
;
QuickSignal:
	push	hl
	call	__GetFromL
	pop	de		;DE = Sem list header pointer, Z=0 & HL=first TCB or Z=1 & HL=0
	jr	z,1f
	push	hl		;HL=TCB
	ld	a,WAITSEM_OFF
	add	a,l
	ld	l,a		;HL=pointer to WaitSem
	xor	a
	ld	(hl),a		;Set WaitSem=0
	inc	l
	ld	(hl),a
	pop	bc		;BC=TCB
COND	SIO_RING
	call	GetSIOChars
ENDC
	ld	hl,_TasksH	;HL=Active tasks list header
	jp	__AddTask	;insert TCB into active tasks list, return HL=TCB & Z=0 & CARRY=0
1:				;list was empty, so only increment sem counter
	ex	de,hl		;HL=Sem list header pointer
	ld	a,COUNTER_OFF
	add	a,l
	ld	l,a		;HL=Sem counter pointer, increment counter
	inc	(hl)		;inc low counter
	jr	nz,2f
	inc	l		;if (low counter) == 0, increment also high counter
	inc	(hl)
2:	xor	a		;Z=1 & CARRY=0
	ret			;HL not NULL
COND	C_LANG
;
;	Wait Semaphore
;
;short	Wait(void* SemAddr);
;	AF,BC,DE,HL,IX,IY not affected
;	return HL=0 if wrong semaphore address provided, else not null
;
WaitSem	equ	14
;
_Wait:
	PUSH_ALL_REGS
COND	CPM
lwait1:	ld	a,(CON_CrtIO)
	cp	IO_IDLE
	jr	z,nowait1
COND	IO_COMM
	cp	IO_RAW_READ
	jr	z,nowait1
ENDC
	cp	IO_WRITE
	jr	nz,isread1
	call	_CON_TX
	jr	lwait1
isread1:call	_CON_RX
	call	_CON_TX
	call	_CON_TX
	call	_CON_TX
	jr	lwait1
nowait1:
ENDC	
	ld	hl,WaitSem
	add	hl,sp		;stack=AF,BC,DE,HL,IX,IY,retaddr,Sem addr
	ld      a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a		;HL=Sem list header pointer
	di
;										DEBUG
COND	DEBUG
	call	IsItSem
	jr	z,1f
;									DIG_IO
COND DIG_IO
	OUT_LEDS ERR_SEM
ENDC
;									DIG_IO
				;no, it is not a semaphore, return 0
	xor	a		;Z=1 to just resume current task
	ld	h,a
	ld	l,a		;return HL=0
	jp	Resch_or_Res
1:
ENDC
;										DEBUG
	call	QuickWait
				;Z=0? (TCB was inserted into sem list?)
	jp	Resch_or_Res	;yes : reschedule, else just resume current task
ENDC
;
;	Wait Semaphore - internal
;
;	HL=SemAddr
;	return CARRY=1 if wrong semaphore address provided, else CARRY=0
;
__Wait:
COND	CPM
lwait:	ld	a,(CON_CrtIO)
	cp	IO_IDLE
	jr	z,nowait
COND	IO_COMM
	cp	IO_RAW_READ
	jr	z,nowait
ENDC
	cp	IO_WRITE
	jr	nz,isread
	call	_CON_TX
	jr	lwait
isread:	call	_CON_RX
	call	_CON_TX
	call	_CON_TX
	call	_CON_TX
	jr	lwait
nowait:
ENDC	
	di
;										DEBUG
COND	DEBUG
	call	IsItSem
	jr	z,1f
;									DIG_IO
COND DIG_IO
	OUT_LEDS ERR_SEM
ENDC
;									DIG_IO
	scf			;no, it is not a semaphore, return CARRY=1
	ei
	ret
1:
ENDC
;										DEBUG
	call	QuickWait
	jr	nz,1f		;Z=0? (TCB was inserted into semaphore list?)
	ei			;no, just resume current task 
	ret
1:				;yes : reschedule
	push	af		;save CARRY value on stack
	ld	hl,-10		;space for 5 push (HL,DE,BC,IX,IY)
	add	hl,sp
	ld	sp,hl
	jr	_Reschedule
;
;	Wait semaphore without reschedule
;
;	called under DI
;	HL=Semaphore address
;	returns CARRY=0
;	returns Z=0 and HL=TCB inserted into semaphore list, 
;	or Z=1 and HL not NULL if only counter was decremented
;
QuickWait:
	ld	a,COUNTER_OFF+1
	add	a,l
	ld	l,a		;HL=Sem counter pointer+1
	ld	a,(hl)		;A=counter high
	dec	l		;HL=Sem counter pointer
	or	(hl)		;counter is zero?
	jr	z,2f
				;not zero, decrement-it
	ld	a,(hl)		;A=low part before decrementing
	dec	(hl)		;decrement low part
	or	a		;if low part = 0 before being decremented...
	jr	nz,1f
	inc	l		;...decrement also high part
	dec	(hl)
1:
	xor	a		;Z=1, CARRY=0
	ret			;HL not NULL
2:				;counter was 0, so...
				;CARRY=0
	ld	a,l
	sub	COUNTER_OFF
	ld	l,a		;HL=SemAddr
	ex	de,hl		;DE=SemAddr
COND	SIO_RING
	call	GetSIOChars
ENDC
	ld	hl,(_RunningTask)
	push	hl		;HL=current active task TCB on stack
				;store SemAddr stored to WaitSem
	ld	a,WAITSEM_OFF
	add	a,l
	ld	l,a		;HL=pointer to WaitSem
	ld	(hl),e
	inc	l
	ld	(hl),d		;SemAddr stored to WaitSem
COND	SIO_RING
	call	GetSIOChars
ENDC
	ex	de,hl		;HL=SemAddr
	ex	(sp),hl		;HL=TCB, SemAddr on stack
COND	RSTS
	RST	32
ENDC
COND	NORSTS
	call	__RemoveFromL	;remove current active task TCB from active tasks list
ENDC
	ld	b,h		;returned HL=TCB
	ld	c,l		;BC=active task TCB
COND	SIO_RING
	call	GetSIOChars
ENDC
	pop	hl		;HL=SemAddr
	jp	__AddTask	;add crt task to semaphore's list,
				; return HL=current task and Z=0 and CARRY=0
;
_Reschedule:
;
;	called with JP !!!
;	DI already called, must exit with EI called
;	on stack: IY,IX,BC,DE,HL,AF,Return address
;
;	Prepare current task stack to resume later,
;	then give control to first TCB from active tasks list
;
COND	SIO_RING
	call	GetSIOChars
ENDC
				;prepare current task stack to resume later
	ld	hl,0		;save SP to current TCB
	add	hl,sp
	ex	de,hl		;DE = current SP 
	ld	hl,(_RunningTask)
	ld	a,SP_OFF	;save SP of the running task	
	add	a,l
	ld	l,a		;HL= pointer to Running Task's StackPointer
	ld	(hl),e
	inc	l
	ld	(hl),d		;SP is saved
				;now give control to first TCB from active tasks list
COND	SIO_RING
	call	GetSIOChars
ENDC
	ld	hl,_TasksH
COND	NORSTS
	call	__FirstFromL
ENDC
COND	RSTS
	RST	0
ENDC
				;returns HL=first active TCB
	jp	z,RETURN	;if HL NULL, return to the caller of the StartUp
				;if HL not NULL, go set new current active task
COND	SIO_RING
	ex	de,hl
	call	GetSIOChars
	ex	de,hl
ENDC
	ld	(_RunningTask),hl;save current TCB
	ld	d,h
	ld	e,l		;DE=crt TCB
	ld	a,SP_OFF
	add	a,l
	ld	l,a		;HL = pointer to current task SP, CARRY=0
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a		;HL = current task SP
	ld	sp,hl		;SP is restored
;									DEBUG
COND DEBUG
				;CARRY=0
	ld	bc,50H
	sbc	hl,bc		;HL(SP)=HL(SP)-50H
				;DE=crt TCB
	sbc	hl,de
	jr	nc,_ResumeTask
				;stack space < 50H (!!! this means < 34H safe space !!!)
;							DIG_IO
COND DIG_IO
	OUT_LEDS ERR_STACK
ENDC
;							DIG_IO
	ld	hl,STACKW_OFF
	add	hl,de		;HL=pointer of StackWarning
	ld	a,(hl)
	cp	0FFH		;already set?
	jr	z,_ResumeTask	;if yes, just resume task
	ld	(hl),0FFH	;no, set-it
				;check if left stack space too low...
	ld	hl,0
	add	hl,sp		;HL=SP
	ld	bc,30H
	sbc	hl,bc		;HL(SP)=HL(SP)-30H
				;DE=crt TCB
	sbc	hl,de
	jr	c,_ResumeTask	;if left stack < 30H (safe < 14H), cannot write !!!
				;30H <= left stack space <= 50H ( 14H <= safe space <= 34H )
				;Write CR,LF,<hex TCB>,! on the CPM console
	ld	hl,tmpbuf+2
	call	DE_hex		;stores Ascii(DE) in tmpbuf+2
	ld	de,tmpbuf	;msg
	ld	c,7
	call	CON_Wr_Sch	;write msg to console (uses 12H stack space)
	jr	z,_ResumeTask	;if Z=1, just resume task
	ld	(_RunningTask),hl;else set HL=CON Driver TCB as running task
	ld	a,SP_OFF
	add	a,l
	ld	l,a		;HL = pointer to current task SP, CARRY=0
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a		;HL = current task SP
	ld	sp,hl		;SP is restored
ENDC
;									DEBUG
;	called under DI
;
_ResumeTask:			;enters with di called
COND	SIO_RING
	call	GetSIOChars
ENDC
	POP_ALL_REGS
	ei
	ret
;
;	Reschedule or Resume
;
;	called with JP under DI
;	store HL as returned value stack
;	if Z=1, resume current task
;	else (Z=0) reschedule
;
Resch_or_Res:
	ex	de,hl		;store HL as return value on stack
	ld	hl,8
	add	hl,sp		;Z not affected
	ld	(hl),e
	inc	hl		;Z not affected
	ld	(hl),d
	jp	nz,_Reschedule	;Z=0 , reschedule
	jr	_ResumeTask	;Z=1 , resume current running task
;
;	_ReschINT - called from interrupts
;
;	called with JP from an interrupt under DI
;	on stack: AF,BC,DE,HL,IX,IY,Return address
;	Prepare current task stack to resume later,
;	then give control to first TCB from active tasks list
;
_ReschINT:
COND	SIO_RING
	call	GetSIOChars
ENDC
				;prepare current task stack to resume later
	ld	hl,0		;save SP to current TCB
	add	hl,sp
	ex	de,hl		;DE = current SP 
	ld	hl,(_RunningTask)
	ld	a,SP_OFF	;save SP of the running task
	add	a,l
	ld	l,a		;HL= pointer to Running Task's StackPointer
	ld	(hl),e
	inc	l
	ld	(hl),d		;SP is saved
				;now give control to first TCB from active tasks list
COND	SIO_RING
	call	GetSIOChars
ENDC
	ld	hl,_TasksH
COND	NORSTS
	call	__FirstFromL
ENDC
COND	RSTS
	RST	0
ENDC
				;returns HL=first active TCB
	jp	z,RETI_RETURN	;if HL NULL, return to the caller of the StartUp
				;if HL not NULL, set HL as new current active task
COND	SIO_RING
	ex	de,hl
	call	GetSIOChars
	ex	de,hl
ENDC
	ld	(_RunningTask),hl;save current TCB
	ld	a,SP_OFF
	add	a,l
	ld	l,a		;HL = pointer to current task SP
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a		;HL = current task SP
	ld	sp,hl		;SP is restored
COND	SIO_RING
	call	GetSIOChars
ENDC
	POP_ALL_REGS
	ei
	reti