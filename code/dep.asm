;= TODOS ===================================================
; * Multi-threading with atomic increment memory regions
; * Metallic reflection
; * Refraction - with chance of reflection
; * AVX-512 path - with wavefront approach
;===========================================================

;= VECTORIZATION IDEAS =====================================
; The approach that seems most reasonable from the
; literature(*) is wavefront tracing, which treats rays with
; a breadth first approach, queuing further operations for
; the next pass.
;
; The BVH/object hierarchy is laid out in memory with the
; each level of the hierarchy contiguous, i.e.
;
;   |OBJ_1|OBJ_2|OBJ_3 \
;   |OBJ_1.1|OBJ_1.2|OBJ_2.1|OBJ_3.1|OBJ_3.2 \
;   |OBJ_1.1.1|OBJ_1.1.2 ...
;
; Each OBJ can be either a bounding hierarchy parent or a
; leaf object
;
; When a ray is traced, we first traverse the BVH, and the
; relevant information (bounding id, ray) is queued into an
; array specific to BVH hits. If we hit a leaf, we figure
; out whether the ray is reflected, absorbed, or refracted,
; and the information is queued in one of the three
; associated arrays.
;
; These can all be calculated as part of a SIMD situation
; where the results allow us to derive the offsets to get to
; the correct array.
;
; The path tracer keeps doing passes through the queues
; until they are all empty.
;
; As a side note, we can change threads from processing the
; entire scene to processing an offset of rows like we said
; before.
;
; (*) https://www.tabellion.org/et/paper17/MoonRay.pdf
;===========================================================

format ELF64

;===========================================================
section '.text' executable
;===========================================================

; When linking with gl3w, we ge an undefined reference to
; __dso_handle. This shit is a little too esoteric for my
; paygrade, but defining it here like this seems to work.
public __dso_handle
__dso_handle:
    dd 0

include 'vec3.asm'
include 'rand.asm'

CLONE_VM      = 0x00000100
CLONE_FS      = 0x00000200
CLONE_FILES	  = 0x00000400
CLONE_SIGHAND = 0x00000800
CLONE_PARENT  = 0x00008000
CLONE_THREAD  = 0x00010000
CLONE_IO      = 0x80000000
CLONE_FLAGS = CLONE_VM or CLONE_FS or CLONE_FILES or CLONE_SIGHAND or CLONE_PARENT or CLONE_THREAD or CLONE_IO

; Libc
extrn printf
extrn sinf
extrn cosf
extrn fflush
; Glfw
extrn glfwInit
extrn glfwCreateWindow
extrn glfwWindowHint
extrn glfwMakeContextCurrent
extrn glfwWindowShouldClose
extrn glfwSwapBuffers
extrn glfwPollEvents
extrn glfwTerminate
extrn glfwGetFramebufferSize
; OpenGL
extrn glClearColor
extrn glClear
extrn glViewport
extrn glGenTextures
extrn glBindTexture
extrn glTexParameteri
extrn glTexImage2D
extrn glGenVertexArrays
extrn glBindVertexArray
extrn glGenBuffers
extrn glBindBuffer
extrn glVertexAttribPointer
extrn glEnableVertexAttribArray
extrn glBufferData
extrn glCreateProgram
extrn glAttachShader
extrn glLinkProgram
extrn glDeleteShader
extrn glCreateShader
extrn glShaderSource
extrn glCompileShader
extrn glGetShaderiv
extrn glGetShaderInfoLog
extrn glUseProgram
extrn glDrawArrays
; Gl3w
extrn gl3wInit
extrn gl3wIsSupported

;= START ===================================================
public _start
_start:
    ; Initialize glfw
    call    glfwInit
    cmp     eax, 1
    jne     error

    mov     esi, 4
    mov     edi, 0x00022002     ; GLFW_CONTEXT_VERSION_MAJOR
    call    glfwWindowHint
    mov     esi, 6
    mov     edi, 0x00022003     ; GLFW_CONTEXT_VERSION_MINOR
    call    glfwWindowHint
    mov     esi, 0x00022008     ; GLFW_OPENGL_CORE_PROFILE
    mov     edi, 0x00032001     ; GLFW_OPENGL_PROFILE
    call    glfwWindowHint

    mov     r8d, 0
    mov     ecx, 0
    mov     rdx, window_name
    mov     esi, 480
    mov     edi, 640
    call    glfwCreateWindow

    mov     [glfw_window], rax
    cmp     [glfw_window], 0
    je      error
    mov     rdi, [glfw_window]
    call    glfwMakeContextCurrent

    ; Initialize gl3w
    call    gl3wInit
    cmp     eax, 0
    jne     error

    mov     esi, 3
    mov     edi, 3
    call    gl3wIsSupported
    cmp     eax, 1
    jne     error

    ; Initialize OpenGL. We will need a texture and a quad to
    ; render across the screen as well as a shader program
    mov     rsi, gl_texture     ; Screen texture
    mov     rdi, 1
    call    glGenTextures

    mov     esi, [gl_texture]
    mov     edi, 0x0DE1         ; GL_TEXTURE_2D
    call    glBindTexture

    mov     edx, 0x812F         ; GL_CLAMP_TO_EDGE
    mov     esi, 0x2802         ; GL_TEXTURE_WRAP_S
    mov     edi, 0x0DE1         ; 0x0DE1 ; GL_TEXTURE_2D
    call    glTexParameteri
    mov     edx, 0x812F         ; GL_CLAMP_TO_EDGE
    mov     esi, 0x2803         ; GL_TEXTURE_WRAP_T
    mov     edi, 0x0DE1         ; 0x0DE1 ; GL_TEXTURE_2D
    call    glTexParameteri
    mov     edx, 0x2600         ; GL_NEAREST
    mov     esi, 0x2801         ; GL_TEXTURE_MIN_FILTER
    mov     edi, 0x0DE1         ; GL_TEXTURE_2D
    call    glTexParameteri
    mov     edx, 0x2600         ; GL_NEAREST
    mov     esi, 0x2800         ; GL_TEXTURE_MAG_FILTER
    mov     edi, 0x0DE1         ; GL_TEXTURE_2D
    call    glTexParameteri

    ; Quad mesh
    mov     rsi, gl_vao
    mov     edi, 1
    call    glGenVertexArrays

    mov     edi, [gl_vao]
    call    glBindVertexArray

    sub     rsp, 16             ; make space for vbo pointer
    lea     rsi, [rsp]          ; [rsp] = vbo
    mov     edi, 1
    call    glGenBuffers

    mov     esi, [rsp]
    mov     edi, 0x8892         ; GL_ARRAY_BUFFER
    call    glBindBuffer
    add     rsp, 16             ; don't need vbo anymore

    mov     ebx, [verts_len]
    mov     ebp, 4
    imul    ebp, ebx            
    mov     ecx, 0x88E4         ; GL_STATIC_DRAW
    mov     rdx, verts
    mov     esi, ebp
    mov     edi, 0x8892         ; GL_ARRAY_BUFFER
    call    glBufferData

    mov     edi, 0
    call    glEnableVertexAttribArray

    mov     r9d, 0
    mov     r8d, 8
    mov     ecx, 0
    mov     edx, 0x1406         ; GL_FLOAT
    mov     esi, 2
    mov     edi, 0
    call    glVertexAttribPointer

    ; Shader program
    call    glCreateProgram
    mov     [gl_program], eax   ; program id

    mov     rdx, vert_src_ptr
    mov     rsi, vert_src_len
    mov     edi, 0x8B31         ; GL_VERTEX_SHADER
    call    compile_shader
    mov     r12d, eax           ; vert shader id

    mov     rdx, frag_src_ptr
    mov     rsi, frag_src_len
    mov     edi, 0x8B30         ; GL_FRAGMENT_SHADER
    call    compile_shader
    mov     r13d, eax           ; frag shader id

    mov     edi, [gl_program]
    call    glLinkProgram

    mov     edi, r12d           ; after deleting shaders, r12, r13 are free
    call    glDeleteShader
    mov     edi, r13d
    call    glDeleteShader

;= THREAD MANAGEMENT =======================================
; Threads go through the following lifecycle until the
; program ends.
;
;   thread_idle: wait for pixel regions to be available then
;   jump to render_region
;
;   render_region: render a region of pixels and return to
;   thread_idle
;
; The host thread participates in the same loop, except when
; there are no regions available, at which point it does the
; following tasks:
;
;   end_frame: swap the buffer and jump to start_frame
;
;   start_frame: pre-prepare the data used in render_region
;   such as camera/viewport data, set the region counter to
;   0, then jump to thread_idle
;
; After allocating all the threads at the start of the
; program, the host goes straight to preparing the first
; frame.
;
; Each thread has the following reserved registers:
;   r9:  current object trace index
;   r10: current pixel index
;   r11: end pixel index
;   r12: sample index
;   r13: bounce index
;   r14: random seed
;   r15: 0 if child thread
;===========================================================
if thread_count > 1
    repeat thread_count-1
        mov     rax, 56         ; sys_clone
        mov     rdi, CLONE_FLAGS ; flags
        lea     rsi, [pixels]   ; child stack pointer
        mov     rdx, 0          ; parent thread id
        mov     r10, %          ; child thread id
        mov     r8, 0           ; child thread local storage
        syscall
        mov     r15, rax        ; r15: parent or child result
        mov     r14, [rand_seeds+(%)*64] ; r13 is used to index into a random seed
        cmp     r15, 0
        je      thread_idle     ; if we are the child, we go straight to idle
        jl      exit            ; error creating thread
    end repeat
else
    mov     r15, 1              ; r15 needs to be set to not 0 or else we'll
end if                          ; think we are a child thread.
    mov     r14, [rand_seeds]   ; if we are the host we need to set our seed
    jmp     start_frame

thread_idle:
    cmp     [exit_program], 1
    je      exit_child
    ; TODO: swapping eax and r10d here should enable us to
    ; skip the mov from eax to r10d
    mov     eax, 1
    lock xadd [pixel_regions_started], eax ; eax is the next region index
    cmp     eax, pixel_regions_len
    jge     all_threads_started
    mov     r10d, pixel_regions_stride
    mul     r10d                ; edi: pixel_regions_stride * region index
    mov     r10d, eax           ; edi: pixel start index
    mov     r11d, r10d
    add     r11d, pixel_regions_stride ; r14: pixel end index
    jmp     render_region
    
all_threads_started:
    cmp     r15, 0              ; check if we are child or parent thread
    je      thread_idle         ; children keep waiting
    cmp     [pixel_regions_complete], pixel_regions_len
    jge     end_frame           ; host prepares the next frame
    jmp     thread_idle

;= RENDER REGION ===========================================
; This is the task which is pulled by threads concurrently.
; Renders a contiguous region of the pixel buffer.
;===========================================================
render_region:
pixel_start:
    pxor    xmm15, xmm15        ; xmm15: color sum
    xor     r12d, r12d          ; zero sample index
sample_start:
    xor     edx, edx
    mov     eax, r10d
    div     dword [i_pixels_w]
    mov     esi, edx            ; esi: x = (i % w)
    mov     ecx, eax            ; ecx: y = (i / w)

    ; First we deterine the ray direction by finding the
    ; point on the viewport which correlates with the
    ; current pixel coordinates, then taking the delta
    ; between that position and the camera origin and
    ; normalizing it.
    cvtsi2ss xmm11, esi         ; xmm11 will become ray direction
    frand_unsigned xmm10
    addps   xmm11, xmm10

    cvtsi2ss xmm1, ecx
    frand_unsigned xmm10
    addps   xmm1, xmm10

    shufps  xmm11, xmm11, 0     ; xmm11: x
    shufps  xmm1, xmm1, 0       ; xmm1: y
    mulps   xmm11, dqword [v4_pixel_delta_u] ; xmm11: y * pixel_delta_u
    mulps   xmm1, dqword [v4_pixel_delta_v] ; xmm1: x * pixel_delta_v
    addps   xmm11, xmm1
    addps   xmm11, dqword [v4_viewport_root] ; xmm11: pixel center
    subps   xmm11, dqword [v4_look_from]        ; xmm11: ray direction
    ;v3norm  xmm11               ; normalize ray direction
    movaps  xmm10, dqword [v4_look_from] ; xmm10: ray origin from camera position


;= TRACE RAY ===============================================
; We return here on every bounce, with the following
; registers remaining stable and updated on every bounce.
;   xmm14: closest t1
;   xmm13: current box offset
;   xmm12: closest intersection t
;   xmm11: current ray direction
;   xmm10: ray origin
;   xmm9:  current color attenuation
;   r8:    outside or inside normal
;===========================================================
    movaps  xmm0, dqword [v4_half] ; for tmp color only
    movaps  dqword [v4_tmp_color], xmm0

    xor     r13d, r13d          ; zero bounce index
    movaps  xmm9, dqword [v4_one] ; xmm9: color attenuation starts at v4(1.0)
    mov     r8, 0               ; r8: outside or inside normal
trace_ray:
    movaps  xmm12, dqword [v4_inf] ; t_near
    pxor    xmm14, xmm14
    xor     r9, r9              ; zero object index TODO: calc offset from this
test_intersection:
    lea     rsi, [box_offsets]
    mov     rax, r9
    mov     rdi, 16
    mul     rdi
    add     rsi, rax
    movaps  xmm13, dqword [rsi] ; xmm13: box offset

    ; We determine whether the ray intersects with an
    ; axis aligned box centered at the origin.
    ; Inigo with the clutch:
    ;   (https://iquilezles.org/articles/intersectors/)

    ; vec3 r_inv = 1.0 / r_dir
    movaps  xmm0, xmm11         ; calculate inverse of ray direction
    movaps  xmm1, dqword [v4_one]
    divps   xmm1, xmm0          ; xmm1 = ray inverse direction. apparently, a
                                ; divide by 0 (=infinity) still works here.
    ; vec3 n = r_inv * r_origin
    movaps  xmm7, xmm1          ; xmm7: ray inverse
    movaps  xmm0, xmm10
    subps   xmm0, xmm13         ; xmm0: offset ray
    mulps   xmm7, xmm0          ; xmm7: n
    xorps   xmm7, dqword [v4_sign_mask] ; xmm7: -n

    ; vec3 k = abs(r_inv) * box_size
    movaps  xmm6, xmm1          ; xmm6: ray inverse
    andps   xmm6, dqword [abs_mask] ; xmm6: abs(ray inverse)
    mulps   xmm6, dqword [v4_boxmax] ; xmm6: k

    ; vec3 t1 = -n - k
    ; vec3 t2 = -n + k
    movaps  xmm5, xmm6          ; xmm5: k
    addps   xmm6, xmm7          ; xmm6: t2
    subps   xmm7, xmm5          ; xmm7: t1
    insertps xmm6, [v4_inf], 0x30
    insertps xmm7, [v4_negative_inf], 0x30

    ; float t_near = max(max(t1.x, t1.y), t1.z);
    ; float t_far = min(min(t2.x, t2.y), t2.z);
    movaps  xmm5, xmm7          ; x,   y,   z,   0
    movshdup xmm4, xmm7         ; x,   x,   z,   z
    maxps   xmm5, xmm4          ; x|x, y|x, z|z, z|0
    movhlps xmm4, xmm5          ; z|z, z|0
    maxps   xmm5, xmm4          ; xmm5: t_near
    shufps  xmm5, xmm5, 0

    ; if(t_near < t_closest) update t closest
    ucomiss xmm5, xmm12
    jae     no_intersection     ; you make a movie... called flippa

    movaps  xmm4, xmm6
    movshdup xmm3, xmm6
    minps   xmm4, xmm3          ; the wahel?
    movhlps xmm3, xmm4
    minps   xmm4, xmm3          ; xmm4: t_far
    shufps  xmm4, xmm4, 0

    ; if(t_far < t_near) no intersect
    ucomiss xmm4, xmm5
    jbe     no_intersection

    ; if (t_far < 0.0) no intersect
    ucomiss xmm4, [v4_zero]
    jb      no_intersection

    ; so like inigo says if tnear is > 0 or something
    ; then we are outside.
    ucomiss xmm5, [v4_zero]
    ja      outside
    mov     rbp, 1
    jmp exit
    jmp     inside
outside:
    mov     rbp, 0
inside:

    movss   xmm12, xmm5         ; track the closest t_near
    ;shufps  xmm12, xmm12, 0
    ;mov     r8, rbp             ; track closest normal side
    cmp     r8, 0
    je      end_inter_outside
    movss   xmm8, xmm4          ; track the closest t_far
    ;shufps  xmm8, xmm8, 0
    movaps  xmm14, xmm6         ; track t2 of closest t
    jmp end_intersection
end_inter_outside:
    movaps  xmm14, xmm7         ; track t1 of closest t
    jmp     end_intersection
no_intersection:
    movaps  xmm0, xmm11
end_intersection:

    inc     r9d
    cmp     r9d, cube_iterations
    jl      test_intersection   ; is dead

    ucomiss xmm12, [v4_inf]
    je      calculate_sample_color

    ; Stop bouncing rays if we are at max depth
    inc     r13d
    cmp     r13d, bounce_max
    jg      calculate_sample_color

    ; Get normal of intersection
    cmp     r8, 0
    je      normal_outside

    movaps  xmm0, xmm8          ; xmm0: t_far
    cmpps   xmm0, xmm14, 0
    andps   xmm0, dqword [v4_one]

    ;movaps  dqword [v4_tmp_color], xmm0
    jmp normal_over
normal_outside:
    movaps  xmm0, xmm14         ; xmm0: t1
    cmpps   xmm0, xmm12, 0
    andps   xmm0, dqword [v4_one]
    ;movaps  dqword [v4_tmp_color], xmm0
normal_over:
    ; Multiply by -sign of ray direction
    movaps  xmm1, xmm11
    andps   xmm1, dqword [v4_sign_mask] ; died in a car accident
    xorps   xmm1, dqword [v4_sign_mask]
    xorps   xmm0, xmm1          ; xmm0: normal
    v3norm  xmm0
    ; TODO: on second bounce in metal this is peculiar (cool though)
    cmp     r8, 0
    je      hit_pos_outside
    ;jmp exit
    ;xorps   xmm0, dqword [v4_sign_mask]
hit_pos_outside:


    ; Calculate hit position, which is origin of our next ray
    ; r_origin + r_dir * closest_t;
    mulps   xmm12, xmm11        ; xmm12: r_dir * closest_t
    addps   xmm10, xmm12        ; xmm10: hit position, new ray origin
    movaps  xmm1, xmm0
    mulps   xmm1, dqword [v4_eps]

;    cmp     r8, 0
;    je      hit_pos_outside
;    ;xorps   xmm1, dqword [v4_sign_mask]
;hit_pos_outside:
    addps   xmm10, xmm1

; usable xmm registers: xmm1, xmm2, xmm3, xmm4, xmm6, xmm7
; material
;   0: diffuse
;   1: metallic
;   2: glass
;   3: normals
material equ 3
if material eq 0 ; DIFFUSE
    ; Attenuate color
    mulps   xmm9, dqword [v4_albedo]

    v3norm xmm11
    ; Calculate diffuse reflection
    frand_normal xmm11
    frand_normal xmm6
    shufps  xmm6, xmm6, 0
    frand_normal xmm4
    shufps  xmm4, xmm4, 0
    blendps xmm11, xmm6, 0010b
    blendps xmm11, xmm4, 0100b
    v3norm  xmm11
    addps   xmm11, xmm0          ; xmm11 is the new direction
else if material eq 1 ; METALLIC
    ; Attenuate color
    ;mulps   xmm9, dqword [v4_albedo]

    ; Calculate metallic reflection
    ; reflected vector = v - 2.0 * dot(v,n) * n
    movaps  xmm7, xmm0          ; xmm7: normal
    dpps    xmm7, xmm11, 01110111b ; xmm7: dot(v,n)
    mulps   xmm7, xmm0          ; xmm7: dot(v,n) * n
    mulps   xmm7, dqword [v4_two] ; xmm7: 2.0 * dot(v,n) * n
    subps   xmm11, xmm7         ; xmm11: reflected vector
    v3norm  xmm11

    frand_normal xmm7
    frand_normal xmm6
    shufps  xmm6, xmm6, 0
    frand_normal xmm4
    shufps  xmm4, xmm4, 0
    blendps xmm7, xmm6, 0010b
    blendps xmm7, xmm4, 0100b
    v3norm  xmm7
    mulps   xmm7, dqword [v4_fuzz_factor]
    addps   xmm11, xmm7          ; xmm11 is the new direction
else if material eq 2 ; GLASS
    ; cos_theta = min(dot(-uv,n),1.0)
    movaps  xmm4, xmm11
    v3norm  xmm4                ; uv
    xorps   xmm4, dqword [v4_sign_mask] ; -uv
    dpps    xmm4, xmm0, 01110111b ; dot(-uv, n)
    minps   xmm4, dqword [v4_one] ; cos_theta

    ; sin_theta = sqrt(1.0 - cos_theta * cos_theta)
    movaps  xmm1, xmm4
    mulps   xmm1, xmm1          ; cos_theta * cos_theta
    xorps   xmm1, dqword [v4_sign_mask]
    addps   xmm1, dqword [v4_one] ; 1.0 - cos_theta * cos_theta
    sqrtps  xmm1, xmm1          ; sin_theta

    ; refract = front_face ? 1.0/refract_index : refract_index
    cmp     r8, 0
    je      glass_refract_front_face
    ;mov     r8, 0
    movaps  xmm5, dqword [v4_refract_idx]
    jmp     glass_refract_calculated
glass_refract_front_face:
    ;mov     r8, 1
    movaps  xmm5, dqword [v4_refract_idx_reciprocal]
glass_refract_calculated:
    ; if(refract * sin_theta > 1.0) must_reflect
    mulps   xmm1, xmm5
    ucomiss xmm1, [v4_one]
    jb      glass_must_reflect

    ; r_out_perp = refract * (v + cos_theta * n)
    movaps  xmm2, xmm4          ; xmm2: cos_theta
    mulps   xmm2, xmm0          ; cos_theta * n
    addps   xmm2, xmm11         ; v + cos_theta * n
    mulps   xmm2, xmm5          ; r_out_perp

    ; r_out_parallel = -sqrt(abs(1.0 - r_out_perp.len_squared())) * n
    movaps  xmm3, xmm2
    dpps    xmm3, xmm3, 01110111b ; xmm3: len_squared(r_out_perp)
    xorps   xmm3, dqword [v4_sign_mask] ; -len_squared(r_out_perp)
    addps   xmm3, dqword [v4_one] ; 1.0 - len_squared(r_out_perp)
    andps   xmm3, dqword [abs_mask] ; absolute value
    sqrtps  xmm3, xmm3
    xorps   xmm3, dqword [v4_sign_mask]
    mulps   xmm3, xmm0

    ; new_dir = r_out_perp + r_out_parallel
    addps   xmm3, xmm2
    movaps  xmm11, xmm3
    ;v3norm  xmm11
    jmp material_over

glass_must_reflect:
    ;jmp exit
    movaps  xmm7, xmm0          ; xmm7: normal
    dpps    xmm7, xmm11, 01110111b ; xmm7: dot(v,n)
    mulps   xmm7, xmm0          ; xmm7: dot(v,n) * n
    mulps   xmm7, dqword [v4_two] ; xmm7: 2.0 * dot(v,n) * n
    subps   xmm11, xmm7         ; xmm11: reflected vector
    ;v3norm  xmm11
    movaps  xmm11, dqword [v4_green]

    ;frand_normal xmm7
    ;frand_normal xmm6
    ;shufps  xmm6, xmm6, 0
    ;frand_normal xmm4
    ;shufps  xmm4, xmm4, 0
    ;blendps xmm7, xmm6, 0010b
    ;blendps xmm7, xmm4, 0100b
    ;v3norm  xmm7
    ;mulps   xmm7, dqword [v4_fuzz_factor]
    ;addps   xmm11, xmm7          ; xmm11 is the new direction

    ; At this point we still haven't varied the reflectivity
    ; with ray angle. At steep angles, the reflectance of
    ; the surface increases.
    ;
    ; r0 = (1.0 - refract_idx) / (1.0 + refract_idx);
    ; r0 = r0 * r0;
    ; reflect_chance = r0 + (1.0 - r0) * pow(1.0 - cos_theta, 5)
else if material eq 3 ; NORMALS
    movaps  xmm11, xmm0
end if

material_over:
    ;jmp     trace_ray

calculate_sample_color:
    ;shufps  xmm11, xmm11, 10101010b
    movaps  xmm0, xmm11
    v3norm  xmm0
    ;andps   xmm0, dqword [abs_mask]
    ;addps   xmm0, dqword [v4_bg_bias]
    ;mulps   xmm0, dqword [v4_flipy]
    maxps   xmm0, dqword [v4_zero] ; clamp to min 0, otherwise
                                   ; colors cancel out and make
                                   ; (cool looking) lines.
    mulps   xmm0, xmm9          ; attenuate color from bounces
    ;mulps   xmm0, dqword [v4_1p5]
    addps   xmm15, xmm0         ; add to color sum
    inc     r12d
    cmp     r12d, sample_count
    jl      sample_start

write_to_pixel:
    divps   xmm15, dqword [v4_sample_count] ; average samples
    sqrtps  xmm15, xmm15
if debug_color
    movaps  xmm15, dqword [v4_tmp_color]
end if
    mulps   xmm15, dqword [v4_255] ; xmm15 scaled by 255 for rgb space
    cvtps2dq xmm15, xmm15         ; convert to dword integers
    packusdw xmm15, xmm15         ; pack into 16bit words
    packuswb xmm15, xmm15         ; pack into bytes
    movd    dword [pixels+r10d*4], xmm15 ; move to pixel location

if output_render
    push    r9
    push    r10
    push    r11
    push    r12
    lea     rax, [pixels+r10d*4]
    mov     rcx, [rax+2]
    mov     rdx, [rax+1]
    mov     rsi, [rax+0]
    mov     rdi, img_line
    call    printf
    pop     r12
    pop     r11
    pop     r10
    pop     r9
end if
    
    inc     r10d
    cmp     r10d, r11d
    jl      pixel_start

    ; If we have calculated the entire render pass, we
    ; return to thread_idle. Once we are rendering multiple
    ; samples per thread, we would go back to do more
    ; samples here.
    lock add [pixel_regions_complete], 1
    jmp     thread_idle

;= END FRAME ===============================================
end_frame:
    ; Update GL data
    push    0
    push    pixels
    push    0x1401              ; GL_UNSIGNED_BYTE
    push    0x1908              ; GL_RGBA
    mov     r9d, 0
    mov     r8d, pixels_h
    mov     ecx, pixels_w
    mov     edx, 0x1908         ; GL_RGBA
    mov     esi, 0
    mov     edi, 0x0DE1         ; GL_TEXTURE_2D
    call    glTexImage2D
    add     rsp, 32

    sub     rsp, 16             ; make space for framebuffer dimensions
    lea     rdx, [rsp+0x00]     ; width
    lea     rsi, [rsp+0x08]     ; height
    mov     rdi, [glfw_window]
    call    glfwGetFramebufferSize

    mov     rcx, [rsp+0x00]
    mov     rdx, [rsp+0x08]
    mov     rsi, 0
    mov     rdi, 0
    call    glViewport
    add     rsp, 16

    movss   xmm3, [clear_a]
    movss   xmm2, [clear_b]
    movss   xmm1, [clear_g]
    movss   xmm0, [clear_r]
    call    glClearColor
    mov     edi, 0x00004000     ; GL_COLOR_BUFFER_BIT
    call    glClear

    mov     edi, [gl_program]
    call    glUseProgram

    mov     esi, [gl_texture]
    mov     edi, 0x0DE1         ; GL_TEXTURE_2D
    call    glBindTexture

    mov     edi, [gl_vao]
    call    glBindVertexArray

    mov     edx, [verts_len]
    mov     esi, 0
    mov     edi, 0x0004         ; GL_TRIANGLES
    call    glDrawArrays

    mov     rdi, [glfw_window]  ; Main loop end
    call    glfwSwapBuffers
    call    glfwPollEvents

if output_render
    mov     rdi, 0
    call    fflush
end if

;= START FRAME =============================================
; Starting a new frame involves the following tasks:
; * Asking GLFW if we should exit
; * Updating camera state and calculating viewport info
; * Notifying threads to start work by setting the region
;   counter to 0
;===========================================================
start_frame:
if output_render
    mov     rdi, img_header
    call    printf
end if

    ;============
    ; QUERY GLFW
    ;============
    mov     rdi, [glfw_window]
    call    glfwWindowShouldClose
    cmp     eax, 1
    je      exit

    ;=====================
    ; UPDATE CAMERA STATE
    ;=====================
    ; Orbit camera around the origin
    ;   x = dist * sin(phi) * cos(theta);
    ;   y = dist * cos(phi);
    ;   z = dist * sin(phi) * sin(theta);
    ; theta being left/right and phi being up/down
    movss   xmm0, [cam_theta]   ; xmm0, cam_theta
    addss   xmm0, [cam_theta_per_sec]
    movss   [cam_theta], xmm0   ; cam_theta += cam_theta_per_second

    movss   xmm0, [cam_phi]   ; xmm0, cam_phi
    addss   xmm0, [cam_phi_per_sec]
    movss   [cam_phi], xmm0   ; cam_phi += cam_phi_per_second

    movss   xmm0, [cam_theta]
    call    cosf
    movss   xmm6, xmm0          ; xmm6: cos(theta)
    movss   xmm0, [cam_phi]
    call    sinf
    movss   xmm7, xmm0          ; xmm7: sin(phi)
    movss   xmm0, [cam_phi]
    call    cosf
    movss   xmm8, xmm0          ; xmm8: cos(phi)
    movss   xmm0, [cam_theta]
    call    sinf                ; xmm0: sin(theta)

    movss   xmm9, [cam_dist]    ; xmm9-11 will be x,y,z
    movss   xmm10, [cam_dist]
    movss   xmm11, [cam_dist]   ; xmm9-11: cam_dist

    mulss   xmm9, xmm7          ; xmm4: dist * sin(phi)
    mulss   xmm9, xmm6          ; xmm4: x = dist * sin(phi) * cos(theta)
    mulss   xmm10, xmm8         ; xmm5: y = dist * cos(phi)
    mulss   xmm11, xmm0         ; xmm6: dist * sin(theta)
    mulss   xmm11, xmm7         ; xmm6: z = dist * sin(phi) * sin(theta)

    movss   [v4_look_from+0x00], xmm9
    movss   [v4_look_from+0x04], xmm10
    movss   [v4_look_from+0x08], xmm11

    ;mov     rax, 3
    ;cvtss2sd xmm2, xmm9
    ;cvtss2sd xmm1, xmm10
    ;cvtss2sd xmm0, xmm11
    ;mov     rdi, debug_msg
    ;call    printf

;= RENDER PROCEDURE ========================================
; At a high level, our goal is such:
; for each pixel
;    map pixel to a viewport position
;    cast ray from origin through viewport position
;    for each cube
;        determine if cube intersects with ray
;        add cube color to sum
;    write summed color to pixel buffer
;
; More specifically:
; Implicitly, we have a camera centered at (0,0,0) pointing
; down the +Z axis, with +Y above and +X to the right. We
; have a viewport at some viewport_distance down the +Z
; axis.
;
; For each (x,y) pixel, we get the position on the viewport
; by scaling and adding x and y vectors along the viewport
; by the same ratio of pixel to screen size. We then add a
; random amount to the resulting viewport position such
; that our final position is randomly placed within the
; bounds of the viewport "pixel". We define the ray as
; (viewport_pos - cam_pos), which in this case is the same
; as viewport_pos, since the camera is at the origin.
;   (cam_pos will eventually be defined so that we can
;    rotate the camera around the voxels)
;
; We intersect the ray against 9 axis aligned cubes, summing
; the "time spent" by the ray in each cube to get our final
; color.
;
; We are more or less doing this at the moment:
;   (https://raytracing.github.io/books/RayTracingInOneWeekend.html)
;===========================================================
    ;= UPDATE_CAMERA_STATE =================================
    ; Initialization is dedicated to getting these values,
    ; and these registers will be stable throughout the
    ; inner pixel loop:
    ;   xmm12: pixel delta u
    ;   xmm13: pixel delta v
    ;   xmm14: pixel center at uv (0,0)
    ;   xmm15: look from, camera origin
    ; TODO: these values need to be stored in memory and pulled
    ; into the proper registers by the threads
    ;=======================================================
    movaps  xmm15, dqword [v4_look_from] ; xmm15 has lookfrom

    ; Calculate camera basis vectors:
    ;   xmm8  <- u = norm(cross(up, w))
    ;   xmm9  <- v = cross(w, u)
    ;   xmm10 <- w = norm(from - at)
    ; xmm10 must remain stable until the viewport origin has
    ; been calculated.
    movaps  xmm10, xmm15        ; xmm10: lookfrom
    movaps  xmm1, dqword [v4_lookat] ; xmm1: lookat
    subps   xmm10, xmm1         ; xmm0: from - to
    v3norm  xmm10               ; xmm10: basis w

    movaps  xmm8, dqword [v4_upvector] ; xmm0: upvector
    movaps  xmm1, xmm10         ; xmm1: basis w
    v3cross xmm8, xmm1
    v3norm  xmm8                ; xmm8: basis u

    movaps  xmm9, xmm10
    movaps  xmm1, xmm8
    v3cross xmm9, xmm1          ; xmm9: basis v

    ; viewport_u = scale(viewport_w, basis_u)
    ; viewport_v = scale(-viewport_h, basis_v)
    movaps  xmm1, dqword [v4_viewport_w]
    mulps   xmm8, xmm1          ; xmm8: viewport u

    movaps  xmm1, dqword [v4_viewport_h] ; viewport_h is negative because y coordinates
    mulps   xmm9, xmm1          ; xmm9: viewport v

    ; pixel_u = div(viewport_u, pixels_w)
    ; pixel_v = div(viewport_w, pixels_h)
    movaps  xmm12, xmm8
    movaps  xmm0, dqword [v4_pixels_w]
    divps   xmm12, xmm0         ; xmm12: pixel delta u

    movaps  xmm13, xmm9
    movaps  xmm0, dqword [v4_pixels_h]
    divps   xmm13, xmm0         ; xmm13: pixel delta v

    ; viewport_origin = lookfrom - (focal_length * basis_w) - div(viewport_u, 2,0) - div(viewport_v, 2.0)
    movaps  xmm14, dqword [v4_focal_len] ; using xmm14, we will eventually build pixel00
    mulps   xmm14, xmm10        ; xmm10 should be basis_w still, which means...
                                ; xmm14: focal_length * basis_w
                                ; xmm10 is now free for use
    subps   xmm14, xmm15        ; xmm14: lookfrom - (focal_length * basis_w)
    movaps  xmm0, dqword [v4_half] ; xmm0: v4(0.5) also used in pixel00 calculation
    mulps   xmm8, xmm0          ; xmm8: div(viewport_u, 2.0)
    mulps   xmm9, xmm0          ; xmm9: div(viewport_v, 2.0)
    subps   xmm14, xmm8
    subps   xmm14, xmm9         ; xmm14: viewport_origin

    ; TODO: don't use the registers at all or whatever
    movaps  dqword [v4_viewport_root], xmm14
    movaps  dqword [v4_pixel_delta_v], xmm13
    movaps  dqword [v4_pixel_delta_u], xmm12

    xor eax, eax
    xchg [pixel_regions_complete], eax
    xor eax, eax
    xchg [pixel_regions_started], eax
    ;mov    [pixel_regions_started], 0
    ;mov    [pixel_regions_complete], 0
    jmp     thread_idle

error:
    jmp     exit

exit:
    mov     [exit_program], 1
    call    glfwTerminate
exit_child:
    mov     rax, 60             ; exit
    xor     rdi, rdi
    syscall 

;= COMPILE SHADER ==========================================
; Compiles a shader for OpenGL.
;
; input
;   rdx: src address ptr
;   rsi: src len address
;   rdi: type
; output
;   rax: shader id
;===========================================================
compile_shader:
    sub     rsp, 40
    mov     [rsp+0x00], rsi     ; src len address
    mov     [rsp+0x08], rdx     ; src address ptr

    call    glCreateShader      ; type already in edi
    mov     [rsp+0x10], rax     ; shader id

    mov     rcx, [rsp+0x00]
    mov     rdx, [rsp+0x08]
    mov     rsi, 1
    mov     rdi, [rsp+0x10]
    call    glShaderSource

    mov     rdi, [rsp+0x10]
    call    glCompileShader

    lea     rdx, [rsp+0x18]     ; compilation success flag
    mov     rsi, 0x8B81         ; GL_COMPILE_STATUS
    mov     rdi, [rsp+0x10]
    call    glGetShaderiv

    cmp     qword [rsp+0x18], 0
    jne     compile_shader_success

    mov     rcx, msg            ; Log error if shader compilation failed
    mov     rdx, 0
    mov     rsi, msglen
    mov     rdi, [rsp+0x10]
    call    glGetShaderInfoLog

    mov     rax, 1              ; write syscall
    mov     rdi, 1              ; stdout
    mov     rsi, msg
    mov     rdx, msglen
    syscall

    jmp     exit

compile_shader_success:
    mov     esi, [rsp+0x10]
    mov     edi, [gl_program]
    call    glAttachShader

    mov     rax, [rsp+0x10]     ; return shader id
    add     rsp, 40
    ret

;===========================================================
section '.data' align 64
;===========================================================

; Symbols
output_render        = 0
debug_color          = 0
pixels_w             = 256
pixels_h             = 256
fpixels_w equ 256.0
fpixels_h equ 256.0
pixels_count         = pixels_w * pixels_h
pixel_buffer_size    = pixels_count * 4
pixel_regions_stride = pixels_w
pixel_regions_len    = pixels_count / pixel_regions_stride
thread_count         = 1
sample_count         = 8
fsample_count equ 8.0
bounce_max           = 32
cube_iterations      = 3

align 64
msglen       = 4096

img_header  db 'P3', 10, '270 480', 10, '255', 10, 0
img_line    db '%hhu %hhu %hhu', 10, 0

msg         db 'msg error', 10, 0
window_name db 'Empedocles Renderer', 0
debug_msg   db 'cam %f, %f, %f', 10, 0

;= SHARED MEMORY ===========================================
; The bounding volume hierarchy is laid out in memory with
; each level of the hierarchy contiguous, i.e.
;
;   |VOL_1     |VOL_2     |VOL_3   | ...
;   |VOL_1.1   |VOL_1.2   |VOL_2.1 |VOL_3.1 |VOL_3.2 | ...
;   |VOL_1.1.1 |VOL_1.1.2 | ...
;
; A volume can be either a parent or a leaf object. Though
; they include different data, each volume is the same
; static size for indexing.
;
;- Volume Data Layout --------------------------------------
; 48 Bytes |+0. ... ... ...|+16 ... ... ...|+32 +36 ... ...|
; Parent   |Box Origin  ...|Box Size    ...|pid psz lid lsz|
; Leaf     |Box Origin  ...|Box Size    ...|alb rfl ems ...|
;-----------------------------------------------------------
; Parent data:
;   pid: start index of parent nodes in bounded space
;   psz: number of parent nodes in bounded space
;   lid: start index of leaf nodes in bounded space
;   lsz: number of leaf nodes in bounded space
; Leaf data:
;   alb: albedo
;   rfl: reflect chance
;   ems: emit chance
;-----------------------------------------------------------
;===========================================================
;= THREAD LOCAL MEMORY =====================================
; Threads keep track of their own set of multiple operation
; lists. Elements in the list all represent both the state
; and next operation needed by a ray.
;
; The operations are as follows:
;
;   Intersect: Test for intersections against objects in a
;   given bounded space. If the intersection is against a
;   parent volume, queue another intersect operation against
;   its children. If against a leaf volume, queue a bounce
;   operation. If against the sky, queue a termination.
;
;   Bounce: Calculate the type of reaction based on the
;   material properties. If the reaction is emissive,
;   queue a termination, otherwise calculate the new ray
;   origin and direction and queue an intersect operation
;   against the root volume.
;
;   Terminate: Calculate and store the final color by
;   dividing the summed color by the number of bounces,
;   convert to RGBA, and write to the pixel buffer.
;
; Operations are laid out in memory to fit the register size
; relevant to the current code path. In AVX-512, for
; instance, we want to group all the vectors and values by
; type contiguously, i.e.:
;
; |ro,ro,ro,ro,ro|rd,rd,rd,rd,rd|col,col,col,col,col|
;
; Figure out the best way to go based on the actual
; operations.
;
;===========================================================
; render data
align 64
clear_r           dd 0.3
clear_g           dd 0.1
clear_b           dd 0.2
clear_a           dd 1.0
cam_theta_per_sec dd 0.01
cam_phi_per_sec dd 0.000
cam_dist          dd 1.5
i_pixels_w        dd pixels_w

align 64
rand_seeds:
repeat thread_count
    align 64
    dq % * 1000
end repeat

align 64
p1 equ -1.5
p2 equ 0.0
p3 equ 1.5
box_size dd 1.0, 1.0, 1.0, 1.0
box_offsets:
    dd p2, p2, p2, p2 ; dbg
    dd p1, p1, p1, p2
    dd p1, p2, p1, p2
    dd p1, p3, p1, p2
    dd p2, p1, p1, p2
    dd p2, p2, p1, p2
    dd p2, p3, p1, p2
    dd p3, p1, p1, p2
    dd p3, p2, p1, p2
    dd p3, p3, p1, p2

    dd p1, p1, p2, p2
    dd p1, p2, p2, p2
    dd p1, p3, p2, p2
    dd p2, p1, p2, p2
    dd p2, p2, p2, p2
    dd p2, p3, p2, p2
    dd p3, p1, p2, p2
    dd p3, p2, p2, p2
    dd p3, p3, p2, p2

    dd p1, p1, p3, p2
    dd p1, p2, p3, p2
    dd p1, p3, p3, p2
    dd p2, p1, p3, p2
    dd p2, p2, p3, p2
    dd p2, p3, p3, p2
    dd p3, p1, p3, p2
    dd p3, p2, p3, p2
    dd p3, p3, p3, p2

; useful numbers
align 64
v4_one          dd 1.0, 1.0, 1.0, 1.0
v4_red          dd 1.0, 0.0, 0.0, 1.0
v4_green        dd 0.0, 1.0, 0.0, 1.0
v4_blue         dd 0.0, 0.0, 1.0, 1.0
v4_sign_mask    dd 0x80000000, 0x80000000, 0x80000000, 0
abs_mask        dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0
v4_boxmax       dd 0.5, 0.5, 0.5, 0.0
v4_boxoff       dd 0.0, 1.25, 0.0, 0.0
v4_inf          dd 0x7F800000, 0x7F800000, 0x7F800000, 0
v4_negative_inf dd 0xFF800000, 0xFF800000, 0xFF800000, 0
v4_eps          dd 0.01, 0.01, 0.01, 0.00
v4_fuzz_factor  dd 0.01, 0.01, 0.01, 0.00
v4_refract_idx  dd 1.5, 1.5, 1.5, 0.0
v4_refract_idx_reciprocal dd 0.66, 0.66, 0.66, 0.0
v4_albedo       dd 0.9, 0.9, 0.9, 0.0
v4_two          dd 2.0, 2.0, 2.0, 0.0
v4_1p5          dd 1.5, 1.5, 1.5, 0.0
v4_flipy        dd 1.0, -1.0, 1.0, 0.0
v4_255          dd 255.0, 255.0, 255.0, 0.0
v4_zero         dd 0.0, 0.0, 0.0, 0.0
v4_half         dd 0.5, 0.5, 0.5, 0.0
v4_three        dd 3.0, 3.0, 3.0, 0.0
v4_four         dd 4.0, 4.0, 4.0, 0.0
v4_ten          dd 10.0, 10.0, 10.0, 0.0
v4_bg           dd 1.0, 1.0, 1.0, 0.0
v4_bg_bias      dd 0.1, 0.1, 0.1, 0.0
v4_near_one     dd 0.99, 0.99, 0.99, 0.0
v4_more_one     dd 1.10, 1.10, 1.10, 0.0
align 64
v4i_zero        dd 0, 0, 0, 0

; constants
align 64
v4_lookat       dd 0.0, 0.0, 0.0, 0.0
v4_sample_count dd fsample_count,fsample_count,fsample_count,0.0
v4_upvector     dd 0.0, 1.0, 0.0, 0.0
v4_focal_len    dd 2.0, 2.0, 2.0, 0.0
v4_viewport_h   dd -3.0, -3.0, -3.0, -0.0
v4_viewport_w   dd 3.0, 3.0, 3.0, 0.0
v4_pixels_w     dd fpixels_w, fpixels_w, fpixels_w, 0.0
v4_pixels_h     dd fpixels_h, fpixels_h, fpixels_h, 0.0
v4_boxmin       dd -0.5, -0.5, -0.5, -0.0

align 64
verts        dd 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0, 1.0
verts_len    dd 12

include 'generation/generated_data.asm'
vert_src_ptr dq vert_src
frag_src_ptr dq frag_src

;===========================================================
section '.bss' align 64
;===========================================================

align 64
cam_theta         dd -1.1
cam_phi           dd 1.7

align 64
pixels rb pixel_buffer_size

align 64
exit_program           dd 0
align 64
pixel_regions_started  dd 0
align 64
pixel_regions_complete dd 0

align 64
; pulled from registers at start. refactor
v4_pixel_delta_u dd 0.0, 0.0, 0.0, 0.0
v4_pixel_delta_v dd 0.0, 0.0, 0.0, 0.0
v4_look_from     dd 0.0, 0.0, 0.0, 0.0
v4_viewport_root dd 0.0, 0.0, 0.0, 0.0
v4_tmp_color     dd 1.0, 1.0, 1.0, 0.0

; gl data
align 64
glfw_window  rq 1
gl_texture   rd 1
gl_vao       rd 1
gl_program   rd 1
