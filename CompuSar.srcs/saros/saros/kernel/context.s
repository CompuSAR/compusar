    .option arch, +zicsr

.global switchOutCoop
switchOutCoop:
    # The thread knows it is calling a function. Only store the callee saved registers
    li t0, 8                    # MIE bit in MSTATUS
    csrrc  x0, mstatus, t0      # Disable interrupts while switching

    sw ra, 0x74(tp)             # RA goes to the PC after restore
    sw sp, 0x04(tp)
    sw s0, 0x14(tp)
    sw s1, 0x18(tp)
    sw s2, 0x3c(tp)
    sw s3, 0x40(tp)
    sw s4, 0x44(tp)
    sw s5, 0x48(tp)
    sw s6, 0x4c(tp)
    sw s7, 0x50(tp)
    sw s8, 0x54(tp)
    sw s9, 0x58(tp)
    sw s10, 0x5c(tp)
    sw s11, 0x60(tp)

    # At this point the thread is saved. Call Saros::Kernel::Scheduler::reschedule
    j _ZN5Saros6Kernel9Scheduler10rescheduleEv

.global switchOutIrq
switchOutIrq:
    sw ra, 0x00(tp)
    sw sp, 0x04(tp)
    sw t0, 0x08(tp)
    sw t1, 0x0c(tp)

    csrr t1, mepc

    sw t2, 0x10(tp)
    sw s0, 0x14(tp)
    sw s1, 0x18(tp)
    sw a0, 0x1c(tp)
    sw a1, 0x20(tp)
    sw a2, 0x24(tp)
    sw a3, 0x28(tp)
    sw a4, 0x2c(tp)
    sw a5, 0x30(tp)
    sw a6, 0x34(tp)
    sw a7, 0x38(tp)
    sw s2, 0x3c(tp)
    sw s3, 0x40(tp)
    sw s4, 0x44(tp)
    sw s5, 0x48(tp)
    sw s6, 0x4c(tp)
    sw s7, 0x50(tp)
    sw s8, 0x54(tp)
    sw s9, 0x58(tp)
    sw s10, 0x5c(tp)
    sw s11, 0x60(tp)
    sw t3, 0x64(tp)
    sw t4, 0x68(tp)
    sw t5, 0x6c(tp)
    sw t6, 0x70(tp)
    sw t1, 0x74(tp)     # PC

    csrr sp, mscratch
    li ra, 0
    j trap_handler


.global switchIn
switchIn:
    mv tp, a0

    # Initially use a0 for Thread pointer until the pipeline finishes flushing a0 into tp

    # Load PC into t2
    lw t2, 0x74(a0)

    lw ra, 0x00(a0)
    lw sp, 0x04(a0)
    lw t0, 0x08(a0)
    lw t1, 0x0c(a0)

    # Store PC into mepc
    csrw mepc, t2

    lw t2, 0x10(tp)
    lw s0, 0x14(tp)
    lw s1, 0x18(tp)
    lw a0, 0x1c(tp)
    lw a1, 0x20(tp)
    lw a2, 0x24(tp)
    lw a3, 0x28(tp)
    lw a4, 0x2c(tp)
    lw a5, 0x30(tp)
    lw a6, 0x34(tp)
    lw a7, 0x38(tp)
    lw s2, 0x3c(tp)
    lw s3, 0x40(tp)
    lw s4, 0x44(tp)
    lw s5, 0x48(tp)
    lw s6, 0x4c(tp)
    lw s7, 0x50(tp)
    lw s8, 0x54(tp)
    lw s9, 0x58(tp)
    lw s10, 0x5c(tp)
    lw s11, 0x60(tp)
    lw t3, 0x64(tp)
    lw t4, 0x68(tp)
    lw t5, 0x6c(tp)
    lw t6, 0x70(tp)

    mret
