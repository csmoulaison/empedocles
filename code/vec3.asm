; All scalar values are assumed 32 bit, unless otherwise
; specified.

macro v3norm dst, v, xr0, xr1, xr2 {
    local is_zero
    local end
    movaps  xr0, v
    movaps  xr1, xr0          ; xr0 and xr1 both have vector
    dpps    xr1, xr1, 11111111b ; xr1 has dot product
    sqrtps  xr1, xr1          ; xr1 has magnitude
    pxor    xr2, xr2
    ucomiss xr1, xr2          ; if xr1 has magnitude 0, we return 0
    je      is_zero

    divps   xr0, xr1
    movaps  dst, xr0
    jmp end
is_zero:
    movaps  dst, xr1           ; xr1 should be zero here
end:
}
