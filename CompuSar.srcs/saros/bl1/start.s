.global _start
_start:
        lui     ra, 0                   # Set return address to NULL
.option push
.option norelax
        la      gp, __global_pointer$
        la      sp, __stack_end         # Set stack pointer to end of pre-cached memory (16KB + base)
.option pop
        lui     tp, 0
        j       bl1_main
