; Implementation reference:
;   (https://iquilezles.org/articles/sfrand/)
;
;   *seed = 0x00269ec3 + (*seed)*0x000343fd;
;   ires = ((((unsigned int)*seed)>>9 ) | 0x3f800000);
;   return fres - 1.0f;
macro frand_unsigned xmm_result {
    mov     ebp, [rand_seed+r13]
    mov     eax, 0x000343FD
    imul    ebp                 ; eax: seed * 0x000343FD
    add     eax, 0x00269EC3     ; eax: 0x000269EC3 + seed * 0x000343FD
    mov     [rand_seed+r13], eax    ; store seed result
    shr     eax, 9
    or      eax, 0x3F800000     ; eax: ((uint)seed)>>9 | 0x3F800000
    movd    xmm_result, eax
    subss   xmm_result, [v4_one]
}

macro frand_signed xmm_result {
    mov     ebp, [rand_seed+r13]
    mov     eax, 0x000343FD
    imul    ebp                 ; eax: seed * 0x000343FD
    add     eax, 0x00269EC3     ; eax: 0x000269EC3 + seed * 0x000343FD
    mov     [rand_seed+r13], eax    ; store seed result
    shr     eax, 9
    or      eax, 0x40000000     ; eax: ((uint)seed)>>9 | 0x40000000
    movd    xmm_result, eax
    subss   xmm_result, [v4_three]
}

; xmm_result cannot be xmm0
macro frand_normal xmm_result {
    frand_unsigned xmm_result
    frand_unsigned xmm0
    addss xmm_result, xmm0
    frand_unsigned xmm0
    addss xmm_result, xmm0
    frand_unsigned xmm0
    addss xmm_result, xmm0
    subss xmm_result, [v4_two]
}
