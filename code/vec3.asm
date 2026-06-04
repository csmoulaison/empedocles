; The following macros reserve xmm8-xmm15 for calling code
; and freely use xmm0-xmm7
;
; All scalar values are assumed 32 bit, unless otherwise
; specified.

;===========================================================
; Returns normalized vector.
;
; input:
;   v: xmm register
; output:
;   v: normalized
; volatile:
;   xmm1-xmm2
macro v3norm v {
    local is_zero
    local end
    movaps  xmm1, v             ; v and xmm1 both have vector
    dpps    xmm1, xmm1, 01110111b ; xmm1 has dot product
    rsqrtps xmm1, xmm1          ; xmm1 has reciprocal square root
    pxor    xmm2, xmm2
    ucomiss xmm1, xmm2          ; if xmm1 has magnitude 0, we return 0
    je      is_zero

    mulps   v, xmm1
    jmp end
is_zero:
    movaps  v, xmm2             ; xmm1 should be zero here
end:
}

;===========================================================
; Cross product from here (Method 3):
;   (https://geometrian.com/resources/cross_product/)
;
; The comments will reference the variable names from
; there.
;
; Cross product:
;   x = a1*b2 - a2*b1,
;   y = a2*b0 - a0*b2,
;   z = a0*b1 - a1*b0

; input:
;   a: xmm register
;   b: xmm register
; output:
;   a: cross product
; volatile:
;   xmm0-xmm3
macro v3cross a, b {
    ; Method 3
    movaps  xmm2, b
    shufps  xmm2, xmm2, 11001001b   ; xmm2 is tmp0
    movaps  xmm3, a
    shufps  xmm3, xmm3, 11001001b   ; xmm3 is tmp1
    mulps   xmm2, a
    mulps   xmm3, b
    subps   xmm2, xmm3              ; xmm2 is tmp2
    shufps  xmm2, xmm2, 11001001b   ; xmm2 is cross product
    movaps  a, xmm2                 ; a has cross product

    ; Method 5: reportedly faster but I made a mistake
    ; somewhere and don't care to fix it
   
    ;shufps  a, a, 11001001b   ; a is tmp0, no more upvector
    ;                                ; 3, 0, 2, 1
    ;movaps  xmm2, b              ; xmm2 is vec1 (basis w)
    ;shufps  xmm2, xmm2, 11010010b   ; xmm2 is tmp1
    ;                                ; 3, 1, 0, 2
    ;movaps  xmm3, a              ; xmm3 is tmp0
    ;mulps   xmm3, xmm2              ; xmm3 is tmp2
    ;mulps   a, xmm2              ; a is tmp3
    ;movaps  xmm4, xmm3              ; xmm4 is tmp2
    ;shufps  xmm4, xmm4, 11001001b   ; xmm4 is tmp4
    ;                                ; 3, 0, 2, 1
    ;subps   a, xmm4              ; a is cross(upvector, basis_w)
}


