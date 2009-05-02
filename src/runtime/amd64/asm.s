// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.


TEXT	_rt0_amd64(SB),7,$-8

	// copy arguments forward on an even stack

	MOVQ	0(SP), AX		// argc
	LEAQ	8(SP), BX		// argv
	SUBQ	$(4*8+7), SP		// 2args 2auto
	ANDQ	$~7, SP
	MOVQ	AX, 16(SP)
	MOVQ	BX, 24(SP)

	// set the per-goroutine and per-mach registers

	LEAQ	m0(SB), R14		// dedicated m. register
	LEAQ	g0(SB), R15		// dedicated g. register
	MOVQ	R15, 0(R14)		// m has pointer to its g0

	// create istack out of the given (operating system) stack

	LEAQ	(-8192+104)(SP), AX
	MOVQ	AX, 0(R15)		// 0(R15) is stack limit (w 104b guard)
	MOVQ	SP, 8(R15)		// 8(R15) is base

	CLD				// convention is D is always left cleared
	CALL	check(SB)

	MOVL	16(SP), AX		// copy argc
	MOVL	AX, 0(SP)
	MOVQ	24(SP), AX		// copy argv
	MOVQ	AX, 8(SP)
	CALL	args(SB)
	CALL	osinit(SB)
	CALL	schedinit(SB)

	// create a new goroutine to start program
	PUSHQ	$mainstart(SB)		// entry
	PUSHQ	$16			// arg size
	CALL	sys·newproc(SB)
	POPQ	AX
	POPQ	AX

	// start this M
	CALL	mstart(SB)

	CALL	notok(SB)		// never returns
	RET

TEXT mainstart(SB),7,$0
	CALL	main·init(SB)
	CALL	initdone(SB)
	CALL	main·main(SB)
	PUSHQ	$0
	CALL	sys·Exit(SB)
	POPQ	AX
	CALL	notok(SB)
	RET

TEXT	sys·Breakpoint(SB),7,$0
	BYTE	$0xcc
	RET

/*
 *  go-routine
 */
TEXT gogo(SB), 7, $0
	MOVQ	8(SP), AX		// gobuf
	MOVQ	0(AX), SP		// restore SP
	MOVQ	8(AX), AX
	MOVQ	AX, 0(SP)		// put PC on the stack
	MOVL	$1, AX			// return 1
	RET

TEXT gosave(SB), 7, $0
	MOVQ	8(SP), AX		// gobuf
	MOVQ	SP, 0(AX)		// save SP
	MOVQ	0(SP), BX
	MOVQ	BX, 8(AX)		// save PC
	MOVL	$0, AX			// return 0
	RET

/*
 * support for morestack
 */

// morestack trampolines
TEXT	sys·morestack00+0(SB),7,$0
	MOVQ	$0, AX
	MOVQ	AX, 8(R14)
	MOVQ	$sys·morestack+0(SB), AX
	JMP	AX

TEXT	sys·morestack01+0(SB),7,$0
	SHLQ	$32, AX
	MOVQ	AX, 8(R14)
	MOVQ	$sys·morestack+0(SB), AX
	JMP	AX

TEXT	sys·morestack10+0(SB),7,$0
	MOVLQZX	AX, AX
	MOVQ	AX, 8(R14)
	MOVQ	$sys·morestack+0(SB), AX
	JMP	AX

TEXT	sys·morestack11+0(SB),7,$0
	MOVQ	AX, 8(R14)
	MOVQ	$sys·morestack+0(SB), AX
	JMP	AX

// return point when leaving new stack.  save AX, jmp to lessstack to switch back
TEXT retfromnewstack(SB), 7, $0
	MOVQ	AX, 16(R14)	// save AX in m->cret
	MOVQ	$lessstack(SB), AX
	JMP	AX

// gogo, returning 2nd arg instead of 1
TEXT gogoret(SB), 7, $0
	MOVQ	16(SP), AX			// return 2nd arg
	MOVQ	8(SP), BX		// gobuf
	MOVQ	0(BX), SP		// restore SP
	MOVQ	8(BX), BX
	MOVQ	BX, 0(SP)		// put PC on the stack
	RET

TEXT setspgoto(SB), 7, $0
	MOVQ	8(SP), AX		// SP
	MOVQ	16(SP), BX		// fn to call
	MOVQ	24(SP), CX		// fn to return
	MOVQ	AX, SP
	PUSHQ	CX
	JMP	BX
	POPQ	AX
	RET

// bool cas(int32 *val, int32 old, int32 new)
// Atomically:
//	if(*val == old){
//		*val = new;
//		return 1;
//	} else
//		return 0;
TEXT cas(SB), 7, $0
	MOVQ	8(SP), BX
	MOVL	16(SP), AX
	MOVL	20(SP), CX
	LOCK
	CMPXCHGL	CX, 0(BX)
	JZ 3(PC)
	MOVL	$0, AX
	RET
	MOVL	$1, AX
	RET

// void jmpdefer(byte*);
// 1. pop the caller
// 2. sub 5 bytes from the callers return
// 3. jmp to the argument
TEXT jmpdefer(SB), 7, $0
	MOVQ	8(SP), AX	// function
	ADDQ	$(8+56), SP	// pop saved PC and callers frame
	SUBQ	$5, (SP)	// reposition his return address
	JMP	AX		// and goto function
