; Implementation reference:
;   (https://iquilezles.org/articles/sfrand/)
;
;   *seed = 0x00269ec3 + (*seed)*0x000343fd;
;   ires = ((((unsigned int)*seed)>>9 ) | 0x3f800000);
;   return fres - 1.0f;
%macro frand_unsigned 1
    mov     ebp, [r15+Thread.seed]
    mov     eax, 0x000343FD
    imul    ebp                     ; eax: seed * 0x000343FD
    add     eax, 0x00269EC3         ; eax: 0x000269EC3 + seed * 0x000343FD
    mov     [r15+Thread.seed], eax               ; store seed result
    shr     eax, 9
    or      eax, 0x3F800000         ; eax: ((uint)seed)>>9 | 0x3F800000
    movd    %1, eax
    subss   %1, [v4_one]
%endmacro

%macro frand_signed 1
    mov     ebp, [r15+Thread.seed]
    mov     eax, 0x000343FD
    imul    ebp                     ; eax: seed * 0x000343FD
    add     eax, 0x00269EC3         ; eax: 0x000269EC3 + seed * 0x000343FD
    mov     [r15+Thread.seed], eax               ; store seed result
    shr     eax, 9
    or      eax, 0x40000000         ; eax: ((uint)seed)>>9 | 0x40000000
    movd    %1, eax
    subss   %1, [v4_three]
%endmacro

; %1 cannot be xmm0
%macro frand_normal 1
    frand_unsigned %1
    frand_unsigned xmm0
    addss %1, xmm0
    frand_unsigned xmm0
    addss %1, xmm0
    frand_unsigned xmm0
    addss %1, xmm0
    subss %1, [v4_two]
%endmacro
