; The following macros reserve xmm8-xmm15 for calling code
; and freely use xmm0-xmm7
;
; All scalar values are assumed 32 bit, unless otherwise
; specified.

;===========================================================
; Returns normalized vector.
;   %1: src and dst xmm register
;   %2: scratch xmm register (volatile)
;   %3: scratch xmm register (volatile)
%macro v3norm 3
    movaps  %2, %1                  ; %1 and %2 both have vector
    dpps    %2, %2, 01110001b       ; %2 has dot product
    rsqrtss %2, %2                  ; %2 has reciprocal square root
    pxor    %3, %3
    ucomiss %2, %3                  ; if %2 has magnitude 0, we return 0
    je      %%is_zero

    shufps  %2, %2, 0
    mulps   %1, %2
    jmp     %%end
%%is_zero:
    movaps  %1, %3                  ; %3 should be zero here
%%end:
%endmacro

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
;   %1: operand 1 and dst xmm register
;   %2: operand 2 xmm register
;   %3: scratch xmm register (volatile)
;   %4: scratch xmm register (volatile)
%macro v3cross 4
    ; Method 3
    movaps  %3, %2
    shufps  %3, %3, 11001001b       ; %3 is tmp0
    movaps  %4, %1
    shufps  %4, %4, 11001001b       ; %4 is tmp1
    mulps   %3, %1
    mulps   %4, %2
    subps   %3, %4                  ; %3 is tmp2
    shufps  %3, %3, 11001001b       ; %3 is cross product
    ; TODO: this can be skipped by making %1 the first op for shufps?
    movaps  %1, %3                  ; %1 has cross product
%endmacro
