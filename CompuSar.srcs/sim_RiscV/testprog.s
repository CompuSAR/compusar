.global _start
_start:
    la t0, int_vector
    csrw mtvec, t0

    #lw a3, 32(zero)
    lw a4, (t0)
    sw a4, 64(zero)
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

int_vector:
    la  a0, mstatus
    csrr t0, mstatus
    sw  t0, (a0)
    csrr t0, mtval
    sw  t0, 4(a0)
    csrr t0, mepc
    sw  t0, 8(a0)
    csrr t0, mcause
    sw  t0, 12(a0)


mstatus:        .fill 4
mtval:          .fill 4
mepc:           .fill 4
mcause:         .fill 4
