default rel

%include 'vec3.asm'
%include 'rand.asm'

;= Configuration Symbols ===================================
THREAD_COUNT            equ 7
SAMPLE_COUNT            equ 8
%define FSAMPLE_COUNT       8.0
BOUNCE_COUNT            equ 32
CUBES_COUNT             equ 8
HISTORY_FRAMES_PER_FRAME equ 200
HISTORY_FRAMES_COUNT    equ 800

PIXELS_W                equ 512
%define FPIXELS_W           512.0
PIXELS_H                equ 512
%define FPIXELS_H           512.0
PIXELS_COUNT            equ PIXELS_W * PIXELS_H
PIXEL_BUFFER_SIZE       equ PIXELS_COUNT * 4
REGION_STRIDE           equ PIXELS_W * 2
REGIONS_COUNT           equ PIXELS_COUNT / REGION_STRIDE

OUTPUT_FRAMES_TO_FILE   equ 0
OUTPUT_PROFILE          equ 1
UPDATE_GL               equ 1
PROFILE_START_FRAME     equ 100
PROFILE_END_FRAME       equ 600

CLONE_VM                equ 0x00000100
CLONE_FS                equ 0x00000200
CLONE_FILES	            equ 0x00000400
CLONE_SIGHAND           equ 0x00000800
CLONE_PARENT            equ 0x00008000
CLONE_THREAD            equ 0x00010000
CLONE_IO                equ 0x80000000
CLONE_FLAGS             equ CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_PARENT | CLONE_THREAD | CLONE_IO

;= Structs =================================================
struc Thread
    .color_sum          resq 2
    .color_attenuation  resq 2
    .host               resd 1
    .seed               resd 1
    .current_pixel      resd 1
    .end_pixel          resd 1
    .sample_index       resw 1
    .bounce_index       resb 1
    alignb 64
endstruc

struc HistoryFrame
    .v4_look_from       resq 2
    .v4_viewport_origin resq 2
    .v4_pixel_delta_x   resq 2
    .v4_pixel_delta_y   resq 2
endstruc

;= External Functions ======================================
extern printf
extern sinf
extern cosf
extern fflush
extern gl3wInit
extern gl3wIsSupported
extern glfwInit
extern glfwCreateWindow
extern glfwWindowHint
extern glfwMakeContextCurrent
extern glfwWindowShouldClose
extern glfwSwapBuffers
extern glfwPollEvents
extern glfwTerminate
extern glfwGetFramebufferSize
extern glfwSetInputMode
extern glfwGetCursorPos
extern glClearColor
extern glClear
extern glViewport
extern glGenTextures
extern glBindTexture
extern glTexParameteri
extern glTexImage2D
extern glGenVertexArrays
extern glBindVertexArray
extern glGenBuffers
extern glBindBuffer
extern glVertexAttribPointer
extern glEnableVertexAttribArray
extern glBufferData
extern glCreateProgram
extern glAttachShader
extern glLinkProgram
extern glDeleteShader
extern glCreateShader
extern glShaderSource
extern glCompileShader
extern glGetShaderiv
extern glGetShaderInfoLog
extern glUseProgram
extern glDrawArrays

;===========================================================
section .data align=64
;===========================================================

align 64
profile_start       dq 0
profile_end         dq 0
profile_res         dq 0
current_frame       dd 0

msglen equ 4096
msg                 db 'msg error', 10, 0
window_name         db 'Empedocles Renderer', 10, 0
debug_msg           db 'cam %f, %f, %f', 10, 0
profile_msg         db 'Start       %llu', 10, "End         %llu", 10, "Elapsed     %llu (~%llu ms)", 10, 0
img_header          db 'P3', 10, '640 640', 10, '255', 10, 0
img_line            db '%hhu %hhu %hhu', 10, 0

%include 'generation/generated_data.asm'

vert_src_ptr        dq vert_src
frag_src_ptr        dq frag_src
verts               dd 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0, 1.0
verts_len           dd 12

align 64
cam_phi             dd 2.15
cam_theta           dd 0.0
cam_phi_per_sec     dd 0.000
cam_theta_per_sec   dd 0.0000300
cam_phi_sensitivity dd 0.001
cam_theta_sensitivity dd 0.001
cam_distance        dd 3.0
reflectance_bias    dd 0.0
pi2                 dd 6.4

align 64
pixels_w            dd PIXELS_W

align 64
%define p2 0.0
%if 0
    %define p1 -1.5
    %define p3 1.5
    v4_box_offsets:
        dd p2, p2, p2, p2 ; dbg
        dd p3, p2, p2, p2 ; dbg
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
%else
    %define o1 -0.75
    %define o2 0.75
    v4_box_offsets:
        dd o1, o1, o1, p2
        dd o2, o1, o1, p2
        dd o1, o2, o1, p2
        dd o2, o2, o1, p2

        dd o1, o1, o2, p2
        dd o2, o1, o2, p2
        dd o1, o2, o2, p2
        dd o2, o2, o2, p2
%endif

align 64
v4_negative         dd -1.0, -1.0, -1.0, 0.0
v4_eps              dd 0.001, 0.001, 0.001, 0.00
v4_zero             dd 0.0, 0.0, 0.0, 0.0
v4_half             dd 0.5, 0.5, 0.5, 0.0
v4_one              dd 1.0, 1.0, 1.0, 0.0
v4_two              dd 2.0, 2.0, 2.0, 0.0
v4_three            dd 3.0, 3.0, 3.0, 0.0
v4_inf              dd 0x7F800000, 0x7F800000, 0x7F800000, 0
v4_negative_inf     dd 0xFF800000, 0xFF800000, 0xFF800000, 0
v4_abs_mask         dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0
v4_sign_mask        dd 0x80000000, 0x80000000, 0x80000000, 0
v4_red              dd 1.0, 0.0, 0.0, 0.0
v4_green            dd 0.0, 1.0, 0.0, 0.0
v4_blue             dd 0.0, 0.0, 1.0, 0.0
v4_255              dd 255.0, 255.0, 255.0, 0.0
v4_sample_count     dd FSAMPLE_COUNT,FSAMPLE_COUNT,FSAMPLE_COUNT,0.0
v4_pixels_w         dd FPIXELS_W,FPIXELS_W,FPIXELS_W,0.0
v4_pixels_h         dd FPIXELS_H,FPIXELS_H,FPIXELS_H,0.0
v4_up               dd 0.0, 1.0, 0.0, 0.0
v4_refract_index    dd 1.5, 1.5, 1.5, 0.0
v4_refract_index_reciprocal dd 0.66666, 0.66666, 0.66666, 0.0
;v4_refract_index    dd 1.2, 1.2, 1.2, 0.0
;v4_refract_index_reciprocal dd 0.83333, 0.83333, 0.83333, 0.0
;v4_refract_index    dd 1.0, 1.0, 1.0, 0.0
;v4_refract_index_reciprocal dd 1.0, 1.0, 1.0, 0.0
v4_fuzz_factor      dd 0.001, 0.001, 0.001, 0.0
v4_blur_factor      dd 0.0, 0.0, 0.0, 0.0
v4_viewport_w       dd 8.0, 8.0, 8.0, 0.0
v4_viewport_nh      dd -8.0, -8.0, -8.0, 0.0
v4_focal_len        dd 2.5, 2.5, 2.5, 0.0
v4_box_size         dd 0.5, 0.5, 0.5, 0.0
v4_color_attenuation dd 0.7, 0.7, 0.7, 0.0

;===========================================================
section .bss align=64
;===========================================================

history_frame_index resd 1
regions_started     resd 1
regions_completed   resd 1
host_terminated     resb 1

alignb 64
thread_memory_array resb Thread_size * THREAD_COUNT

alignb 64
pixels              resb PIXEL_BUFFER_SIZE * 2

align 64
history_frame_array resb HistoryFrame_size * HISTORY_FRAMES_COUNT

align 64
cos_theta           resd 1
sin_theta           resd 1
cos_phi             resd 1
sin_phi             resd 1

glfw_window         resq 1
gl_texture          resd 1
gl_vao              resd 1
gl_program          resd 1

cursor_position_x   resq 1
cursor_position_y   resq 1

;===========================================================
section .text
;===========================================================

global __dso_handle
__dso_handle:
    dd 0

exit_host:
    mov     [host_terminated], 1
    call    glfwTerminate
exit:
    mov     rax, 60                 ; exit
    xor     rdi, rdi
    syscall 

global _start
_start:
;= Platform Initialization =================================
; We create a window with glfw and initialize gl3w for
; OpenGL support. We create a texture to write pixels to
; every frame, a quad vbo to map it onto, and a shader
; program.
;===========================================================
    ; glfw
    call    glfwInit
    cmp     eax, 1
    jne     exit

    mov     esi, 4
    mov     edi, 0x00022002         ; GLFW_CONTEXT_VERSION_MAJOR
    call    glfwWindowHint
    mov     esi, 6
    mov     edi, 0x00022003         ; GLFW_CONTEXT_VERSION_MINOR
    call    glfwWindowHint
    mov     esi, 0x00022008         ; GLFW_OPENGL_CORE_PROFILE
    mov     edi, 0x00032001         ; GLFW_OPENGL_PROFILE
    call    glfwWindowHint

    mov     r8d, 0
    mov     ecx, 0
    mov     rdx, window_name
    mov     esi, 480
    mov     edi, 640
    call    glfwCreateWindow

    mov     [glfw_window], rax
    cmp     [glfw_window], 0
    je      exit
    mov     rdi, [glfw_window]
    call    glfwMakeContextCurrent

    mov     edx, 0x00034003         ; GLFW_CURSOR_DISABLED
    mov     esi, 0x00033001         ; GLFW_CURSOR
    mov     rdi, [glfw_window]
    call    glfwSetInputMode

    lea     edx, [cursor_position_y]
    lea     rsi, [cursor_position_x]
    mov     rdi, [glfw_window]
    call    glfwGetCursorPos

    ; gl3w
    call    gl3wInit
    cmp     eax, 0
    jne     exit

    mov     esi, 3
    mov     edi, 3
    call    gl3wIsSupported
    cmp     eax, 1
    jne     exit

    ; OpenGL
    mov     rsi, gl_texture         ; Screen texture
    mov     rdi, 1
    call    glGenTextures

    mov     esi, [gl_texture]
    mov     edi, 0x0DE1             ; GL_TEXTURE_2D
    call    glBindTexture

    mov     edx, 0x812F             ; GL_CLAMP_TO_EDGE
    mov     esi, 0x2802             ; GL_TEXTURE_WRAP_S
    mov     edi, 0x0DE1             ; GL_TEXTURE_2D
    call    glTexParameteri
    mov     edx, 0x812F             ; GL_CLAMP_TO_EDGE
    mov     esi, 0x2803             ; GL_TEXTURE_WRAP_T
    mov     edi, 0x0DE1             ; GL_TEXTURE_2D
    call    glTexParameteri
    mov     edx, 0x2600             ; GL_NEAREST
    mov     esi, 0x2801             ; GL_TEXTURE_MIN_FILTER
    mov     edi, 0x0DE1             ; GL_TEXTURE_2D
    call    glTexParameteri
    mov     edx, 0x2600             ; GL_NEAREST
    mov     esi, 0x2800             ; GL_TEXTURE_MAG_FILTER
    mov     edi, 0x0DE1             ; GL_TEXTURE_2D
    call    glTexParameteri

    mov     rsi, gl_vao             ; Quad mesh
    mov     edi, 1
    call    glGenVertexArrays

    mov     edi, [gl_vao]
    call    glBindVertexArray

    sub     rsp, 16                 ; make space for vbo pointer
    lea     rsi, [rsp]              ; [rsp] = vbo
    mov     edi, 1
    call    glGenBuffers

    mov     esi, [rsp]
    mov     edi, 0x8892             ; GL_ARRAY_BUFFER
    call    glBindBuffer
    add     rsp, 16                 ; don't need vbo anymore

    mov     ebx, [verts_len]
    mov     ebp, 4
    imul    ebp, ebx
    mov     ecx, 0x88E4             ; GL_STATIC_DRAW
    mov     rdx, verts
    mov     esi, ebp
    mov     edi, 0x8892             ; GL_ARRAY_BUFFER
    call    glBufferData

    mov     edi, 0
    call    glEnableVertexAttribArray

    mov     r9d, 0
    mov     r8d, 8
    mov     ecx, 0
    mov     edx, 0x1406             ; GL_FLOAT
    mov     esi, 2
    mov     edi, 0
    call    glVertexAttribPointer

    call    glCreateProgram
    mov     [gl_program], eax       ; program id

    mov     rdx, vert_src_ptr
    mov     rsi, vert_src_len
    mov     edi, 0x8B31             ; GL_VERTEX_SHADER
    call    compile_shader
    mov     r12d, eax               ; vert shader id

    mov     rdx, frag_src_ptr
    mov     rsi, frag_src_len
    mov     edi, 0x8B30             ; GL_FRAGMENT_SHADER
    call    compile_shader
    mov     r13d, eax               ; frag shader id

    mov     edi, [gl_program]
    call    glLinkProgram

    mov     edi, r12d               ; after deleting shaders, r12,
                                    ; r13 are free
    call    glDeleteShader
    mov     edi, r13d
    call    glDeleteShader

;= Thread Creation =========================================
; A number of threads are spawned and each given their own
; instance of a thread-local structure.
;===========================================================
    mov     dword [regions_completed], 0
    mov     dword [regions_started], REGIONS_COUNT ; otherwise the threads
                                                   ; will start before the
                                                   ; first frame is ready.
    lea     r15, [thread_memory_array] ; Define base values for host thread
    mov     dword [r15+Thread.host], 1 ; host = 1 for host thread
%if THREAD_COUNT > 1
    %assign i 1
    %rep THREAD_COUNT-1
        %push thread_ctx
        mov     rax, 56             ; sys_clone
        mov     rdi, CLONE_FLAGS    ; flags
        lea     rsi, [thread_memory_array + Thread_size * i] ; child stack ptr
        mov     rdx, 0              ; parent thread id
        mov     r10, 0              ; child thread id
        mov     r8, 0               ; child thread local storage
        syscall
        cmp     rax, 0              ; 0 if we are child
        jl      exit_host           ; error creating thread
        jne     %$end_thread_creation ; host skips to the next thread creation
        mov     r15, rsp            ; store thread memory ptr in r15
        mov     [r15+Thread.host], 0 ; store the fact that we aren't the host
        jmp     thread_idle         ; child threads jump straight to idle and
                                    ; wait for work...
        %$end_thread_creation:
        %pop
    %assign i i+1
    %endrep
%endif
    jmp     start_frame             ; ...while the host thread instead prepares
                                    ; the first frame

;= Thread Idle =============================================
; Each thread, including the host, returns here when it is
; looking for more work to do, i.e. regions of the screen to
; render.
;
; Each thread iterates regions_started, and if all the
; regions have been started, it continues to idle, unless it
; is the host thread, in which case it checks if all regions
; are complete and ends the frame if so, kicking off the
; next round of work.
;
; If there are still regions to render, the thread instead
; jumps to render region, where it performs its work,
; iterating regions started and regions complete in the
; process.
;===========================================================
thread_idle:
    cmp     [host_terminated], 1    ; host tips off the children to exit
    je      exit
    mov     eax, 1
    lock    xadd [regions_started], eax ; iterate regions_started, storing the
                                        ; last region index in eax
    cmp     eax, REGIONS_COUNT
    jge     all_regions_started
                                    ; We have a region to render:
    mov     r8d, REGION_STRIDE      ; calculate start pixel index
    mul     r8d                     ; store stride * index (eax) in eax
    mov     [r15+Thread.current_pixel], eax
    add     eax, REGION_STRIDE      ; add stride to get end pixel index
    mov     [r15+Thread.end_pixel], eax
    jmp     render_region
all_regions_started:
    cmp     [r15+Thread.host], 0    ; 0 if we are child
    je      thread_idle             ; child threads keep patiently waiting
check_regions_complete:
    cmp     dword [regions_completed], REGIONS_COUNT ; the host thread instead wants to
    jge     end_frame                                ; know if all the regions are
    jmp     thread_idle                              ; complete so it can end the frame

;= Start Frame =============================================
; The host executes this before every frame is rendered
; * Handle GLFW events, closing the program if requested
; * Update the logical state of the program, such as the
;   camera orientation
; * Calculate info which is needed for rendering and
;   invariant between regions, such as viewport geometry
; * Notify threads to start work by setting regions started
;   and regions complete to 0
;===========================================================
start_frame:
    mov     rdi, [glfw_window]      ; If GLFW has recieved a close request, we
    call    glfwWindowShouldClose   ; politely comply
    cmp     eax, 1
    je      exit_host

%if OUTPUT_FRAMES_TO_FILE           ; For rendering ppm frames
    mov     rdi, img_header
    call    printf
%endif

%if OUTPUT_PROFILE = 1
    add     dword [current_frame], 1
    cmp     dword [current_frame], PROFILE_START_FRAME
    je      start_profile
    cmp     dword [current_frame], PROFILE_END_FRAME
    je      end_profile
    jmp     skip_profile
start_profile:
    lfence
    rdtsc
    ; below shift shit wrong?
    shl     rax, 32
    shrd    rax, rdx, 32
    mov     qword [profile_start], rax
    jmp     skip_profile

end_profile:
    rdtscp
    lfence
    shl     rax, 32
    shrd    rax, rdx, 32
    mov     qword [profile_end], rax
    sub     qword rax, [profile_start]
    mov     qword [profile_res], rax

    xor     rax, rax
    xor     rdx, rdx
    mov     qword rax, [profile_res]
    mov     rdi, 4000000
    div     rdi

    mov     qword r8, rax
    mov     qword rcx, [profile_res]
    mov     qword rdx, [profile_end]
    mov     qword rsi, [profile_start]
    mov     rdi, profile_msg
    call    printf

    mov     rdi, 0
    call    fflush
    jmp     exit_host
skip_profile:
%endif

    xor     r11, r11
calculate_history_frame:

    movsd   xmm1, [cursor_position_x]
    movsd   xmm2, [cursor_position_y]
    lea     edx, [cursor_position_y]
    lea     rsi, [cursor_position_x]
    mov     rdi, [glfw_window]
    call    glfwGetCursorPos

    movsd  xmm3, [cursor_position_x]
    movsd  xmm4, [cursor_position_y]
    subsd   xmm1, xmm3
    subsd   xmm2, xmm4
    cvtsd2ss xmm1, xmm1
    cvtsd2ss xmm2, xmm2
    mulss   xmm1, [cam_theta_sensitivity]
    mulss   xmm2, [cam_phi_sensitivity]

    ; Update camera rotation (theta and phi), and find the
    ; position (look from) with the following:
    ;   x = distance * sin(phi) * cos(theta)
    ;   y = distance * cos(phi)
    ;   z = distance * sin(phi) * sin(theta)
    movss   xmm0, [cam_phi]
    ;addss   xmm0, xmm2
    addss   xmm0, [cam_phi_per_sec]
    movss   [cam_phi], xmm0         ; Add to phi for vertical orbit
    movss   xmm0, [cam_theta]       
    ;addss   xmm0, xmm1
    addss   xmm0, [cam_theta_per_sec]
    movss   [cam_theta], xmm0       ; Add to theta for horizontal orbit

    movss   xmm0, [cam_theta]       ; We calculate all the cos,sin/phi,theta
    call    cosf                    ; permutations:
    movss   [cos_theta], xmm0       ; cos(theta)
    movss   xmm0, [cam_theta]
    call    sinf                    
    movss   [sin_theta], xmm0       ; sin(theta)
    movss   xmm0, [cam_phi]
    call    cosf                    
    movss   [cos_phi], xmm0         ; cos(phi)
    movss   xmm0, [cam_phi]
    call    sinf                    
    movss   [sin_phi], xmm0         ; sin(phi)

    pxor    xmm0, xmm0              ; xmm0 will eventually be the packed
                                    ; position, and we want the last lane
                                    ; to end up being 0.0

    movss   xmm3, [cam_distance]    ; We store cam distance in
    movss   xmm0, xmm3              ;   xmm0, xmm1, and xmm2.
    movss   xmm1, xmm3              ; We will operate on them in place to get
    movss   xmm2, xmm3              ;   camera x, y, and z

    mulss   xmm0, [sin_phi]         ; x = distance * sin(phi)
    mulss   xmm0, [cos_theta]       ;   * cos(theta)
    mulss   xmm1, [cos_phi]         ; y = distance * cos(phi)
    mulss   xmm2, [sin_phi]         ; z = distance * sin(phi)
    mulss   xmm2, [sin_theta]       ;   * sin(theta)

    insertps xmm0, xmm1, 0x10       ; Move y to lane 1
    insertps xmm0, xmm2, 0x20       ;  and z to lane 2
                                    ; Now xmm0 is our "look from" position

    ; Having calculated the camera position, we now find
    ; three more key vectors. The first is the position of
    ; the top left corner of the viewport in world space.
    ; The other two are the u and v deltas between pixels
    ; in the viewport.
    ;
    ; Along the way, we calculate the camera basis vectors:
    ;   x = normalize(up X z), (where X is cross product)
    ;   y = z X x
    ;   z = normalize(look_from - look_at), (camera will look down -z)
    ; We calculate basis z, then x, they y
    movaps  xmm3, xmm0              ; basis z = look from
    v3norm  xmm3, xmm14, xmm15      ;   normalized
                                    ; We ignore look_at, since it's implicitly
                                    ; placed at the origin in our world.

    movaps  xmm1, [v4_up]           ; basis x = up
    movaps  xmm4, xmm3              ;           X
    v3cross xmm1, xmm4, xmm5, xmm6  ;           z
    v3norm  xmm1, xmm5, xmm6        ;   normalized

    movaps  xmm2, xmm3              ; basis y = z
    movaps  xmm4, xmm1              ;           X
    v3cross xmm2, xmm4, xmm5, xmm6  ;           x
                                    ; Now xmm 1,2,3 are basis x,y,z

    mulps   xmm1, [v4_viewport_w]   ; We multiply the basis vectors by the world
    mulps   xmm2, [v4_viewport_nh]  ; space viewport dimensions to get the vectors
                                    ; which span the world space viewport.
                                    ; The height is negative because y coordinates
                                    ; are flipped by convention.

    movaps  xmm4, xmm1              ; The pixel delta vectors are the same as
    divps   xmm4, [v4_pixels_w]     ; the viewport span vectors, but divided by
    movaps  xmm5, xmm2              ; the render pixel dimensions.
    divps   xmm5, [v4_pixels_h]     ; Now xmm 4,5 are pixel delta x,y

    ; We now calculate the viewport origin in world space.
    movaps  xmm6, [v4_focal_len]    ; We extend the camera basis z by a focal
    mulps   xmm6, xmm3              ; length and subtract the look from position
    subps   xmm6, xmm0              ; to get our point along the camera z basis.

    movaps  xmm7, [v4_half]         ; Then, we offset our position by half the
    mulps   xmm1, xmm7              ; distance of our viewport span vectors.
    mulps   xmm2, xmm7              
    subps   xmm6, xmm1              
    subps   xmm6, xmm2              ; Now xmm6 is our viewport origin.

    xor     rax, rax
    mov     eax, HistoryFrame_size
    mul     dword [history_frame_index]
    lea     r9, [history_frame_array+eax]
    movaps  [r9+HistoryFrame.v4_look_from], xmm0       ; Store these values into global memory
    movaps  [r9+HistoryFrame.v4_viewport_origin], xmm6 ; for use during rendering.
    movaps  [r9+HistoryFrame.v4_pixel_delta_x], xmm4
    movaps  [r9+HistoryFrame.v4_pixel_delta_y], xmm5   ; Hip, hip, hooray!

    inc     dword [history_frame_index]
    cmp     dword [history_frame_index], HISTORY_FRAMES_COUNT
    jl      skip_reset_history_frame
    mov     dword [history_frame_index], 0
skip_reset_history_frame:

    inc     r11
    cmp     r11, HISTORY_FRAMES_PER_FRAME
    jl      calculate_history_frame

    xor     eax, eax                ; Reset region counters to start next frame
    xchg    [regions_completed], eax
    xor     eax, eax
    xchg    [regions_started], eax
    ;mov    [regions_started], 0    ; Alternate way, want to profile to see
    ;mov    [regions_completed], 0  ; if it's faster or slower
    jmp     thread_idle             ; Back to thread idle to work on rendering

;= Render Region ===========================================
; Threads execute this repeatedly until all regions have
; been started. It runs in nested loops of the following
; structure:
;
;   pixel start: for each pixel {
;       sample start: for each sample {
;           calculate ray direction from camera
;           ray start: for each bounce {
;               intersection start: for each object {
;                   check intersection and track closest hit
;               }
;               if hit, get normal and calculate new ray
;               direction based on material properties, or
;               terminate
;           }
;           calculate sample color and add to sum
;       }
;       average the sum of sample colors and write to pixels
;   }
;
; After we finish rendering the region, we iterate
; regions complete and jump back to thread idle to wait for
; more work.
;===========================================================
render_region:

pixel_start:
    mov     word [r15+Thread.sample_index], 0 ; Zero the sample index
    pxor    xmm0, xmm0                        ; and color sum.
    movaps  [r15+Thread.color_sum], xmm0
   
sample_start:
    ;pxor    xmm12, xmm12            ; DEBUG: norm color
    xor     rax, rax                ; Calculate the x and y coordinates
    xor     rdx, rdx                ; from the current pixel index.
    mov     eax, [r15+Thread.current_pixel]
    div     dword [pixels_w]
    cvtsi2ss xmm0, edx              ; x = i % w
    cvtsi2ss xmm1, eax              ; y = i / w
    frand_unsigned xmm3             ; Get a random position between x and x+1
    frand_unsigned xmm4             ; and the same for y.
    addss   xmm0, xmm3              ; We will use these to index our viewport
    addss   xmm1, xmm4              ; position for a random sample ray.
    shufps  xmm0, xmm0, 0
    shufps  xmm1, xmm1, 0

    irand_unsigned r10d, HISTORY_FRAMES_COUNT
    ;xor     rax, rax
    ;xor     rdx, rdx
    ;mov     r10d, HISTORY_FRAMES_COUNT
    ;div     r10d
    xor     rax, rax
    mov     eax, HistoryFrame_size
    mul     r10d
    lea     r9, [history_frame_array+eax]
    movaps  xmm4, [r9+HistoryFrame.v4_viewport_origin]
    movaps  xmm5, [r9+HistoryFrame.v4_pixel_delta_x]
    movaps  xmm6, [r9+HistoryFrame.v4_pixel_delta_y]
    movaps  xmm7, [r9+HistoryFrame.v4_look_from]

    mulps   xmm0, xmm5              ; We scale the deltas by x and y and add
    mulps   xmm1, xmm6              ; them together along with the viewport
    addps   xmm1, xmm0              ; origin, giving us the corresponding
    addps   xmm1, xmm4              ; position on the viewport.

    frand_normal xmm2, xmm15
    shufps  xmm2, xmm2, 0
    mulps   xmm2, [v4_two]
    subps   xmm2, [v4_one]
    mulps   xmm2, xmm5
    mulps   xmm2, [v4_blur_factor]

    frand_normal xmm3, xmm15
    shufps  xmm3, xmm3, 0
    mulps   xmm3, [v4_two]
    subps   xmm3, [v4_one]
    mulps   xmm3, xmm6
    mulps   xmm3, [v4_blur_factor]

    addps   xmm2, xmm3
    addps   xmm7, xmm2
    subps   xmm1, xmm7                 ; gives us a ray direction through the
                                       ; viewport point.
    movaps  xmm0, xmm7

    mov     byte [r15+Thread.bounce_index], 0    ; Initialize bounce index and
    movaps  xmm2, [v4_one]                       ; start color attenuation at 1.
    movaps  [r15+Thread.color_attenuation], xmm2

ray_start:                          ; Keep intersection data in registers:
                                    ; xmm0: ray origin
                                    ; xmm1: ray direction
    movaps  xmm2, [v4_inf]          ; xmm2: closest t hit
                                    ; xmm3: closest t1/t2
    xor     r8, r8                  ;   r8: object index
                                    ;   r9: closest hit inside?

    movaps  xmm11, xmm0
    movaps  xmm10, xmm1


intersection_start:
    lea     rsi, [v4_box_offsets]   ; First, we index the box we will test
    mov     rax, r8                 ; our ray against.
    mov     rdi, 16                 ; Size is 16, we should probably make a
    mul     rdi                     ; struct for this eventually.
    add     rsi, rax                ; rsi now has address of the box position.

    movaps  xmm4, [v4_one]          ; Calculate the inverse of the ray direction
    divps   xmm4, xmm1              ; to be used to get both the ray origin and
                                    ; half the box extents in terms of t.

    movaps  xmm5, xmm4              ; Calculate -(ray origin / direction), which
    movaps  xmm6, xmm0              ; represents the world origin in t space, or
    subps   xmm6, [rsi]             ; the ray t distance per-axis. We offset the
    mulps   xmm5, xmm6              ; ray origin for this calculation so we can
    xorps   xmm5, [v4_sign_mask]    ; act like the box is at the world origin.

    movaps  xmm6, xmm4              ; Calculate box size / abs(ray direction),
    andps   xmm6, [v4_abs_mask]     ; which encodes the ray t distance from the
    mulps   xmm6, [v4_box_size]     ; center of the box to either slab boundary
                                    ; for each axis.

    movaps  xmm4, xmm5              ; Calculate both t1 and t2, which encode
    subps   xmm4, xmm6              ; the per-axis intersection times for the
    addps   xmm5, xmm6              ; near and far hits, respectively. They are
                                    ; calculated by subbing and adding the half
                                    ; extents to the ray origin in t space.
    insertps xmm4, [v4_negative_inf], 0x30 ; NOTE: The original code included
    insertps xmm5, [v4_inf], 0x30          ; this for the max and min logic
                                           ; below, but I'm not sure if this
                                           ; is needed or not.

    movaps  xmm6, xmm4              ; For t1, we calculate a value we call
    movshdup xmm7, xmm4             ; t entry, which is the max element of t1.
    maxps   xmm6, xmm7              ;
    movhlps xmm7, xmm6              ; This is the t distance where the ray is
    maxps   xmm6, xmm7              ; inside all three slabs, and therefore the
    shufps  xmm6, xmm6, 0           ; ray t of the near hit.

    movaps  xmm7, xmm5              ; We perform the same calculation for t2,
    movshdup xmm8, xmm5             ; but for the min element, garnering our
    minps   xmm7, xmm8              ; t exit value.
    movhlps xmm8, xmm7              ; If we are outside the box, t entry is the
    minps   xmm7, xmm8              ; point we care about, and if we are
    shufps  xmm7, xmm7, 0           ; outside, it's t exit.

    ; Having calculated t entry and t exit, we now have to
    ; determine if an intersection did in fact occur.

    ucomiss xmm6, xmm7              ; If t entry > t exit, there was no
    jae     intersection_continue   ; intersection.

    ucomiss xmm7, [v4_zero]         ; If t exit < 0.0, there was no
    jbe     intersection_continue   ; intersection.

    ucomiss xmm6, [v4_zero]         ; If t entry < 0 we hit from inside,
    jbe     intersection_inside     ; otherwise we hit from outside.

intersection_outside: ; Label only for clarity
    ucomiss xmm6, xmm2              ; When hitting from the outside, t entry is
    jae     intersection_continue   ; the relevant hit distance. If it doesn't
                                    ; beat the closest, we skip this hit.
    movaps  xmm2, xmm6              ; If we are the closest hit, we track our
    movaps  xmm3, xmm4              ; t entry value as the closest t hit and
    mov     r9, 0                   ; our t1 value. We also track that we hit
                                    ; from the outside with r9 = 0.
    jmp     intersection_continue

intersection_inside:
    ucomiss xmm7, xmm2              ; When hitting from the inside, perform the
    ja      intersection_continue   ; same logic, but using t exit, t2, and
                                    ; r9 = 1.
    movaps  xmm2, xmm7              ; NOTE: is ja the right condition up there?
    movaps  xmm3, xmm5
    mov     r9, 1

intersection_continue:
    inc     r8                      ; We keep testing intersections until we
    cmp     r8, CUBES_COUNT         ; have exceeded CUBES COUNT.
    jl      intersection_start

    ucomiss xmm2, [v4_inf]          ; If no intersections were ever found, xmm2
    je      calculate_sample_color  ; should still be infinity, so we skip to
                                    ; final color calculation.


    inc     byte [r15+Thread.bounce_index]               ; If we have exceeded
    cmp     byte [r15+Thread.bounce_index], BOUNCE_COUNT ; BOUNCE MAX, we also
    jg      calculate_sample_color                       ; skip to final color
                                                         ; calculation.

    cmp     r9, 0                   ; The logic for calculating the normal is
    jne     normal_inside           ; sort of flipped depending on if we are
                                    ; hitting from inside of outside.
normal_outside: ; Label only for clarity
    movaps  xmm4, xmm3              ; In the outside case, we do a step function
    cmpps   xmm4, xmm2, 0           ; with step(v3(t entry), t1)
    andps   xmm4, [v4_one]

    movaps  xmm5, xmm1              ; To get the hit normal, we multiply the
    andps   xmm5, [v4_sign_mask]    ; above calculation by the negative sign
    xorps   xmm5, [v4_sign_mask]    ; of the ray direction...
    xorps   xmm4, xmm5
    v3norm  xmm4, xmm14, xmm15      ; ...and normalize.

    jmp     normal_post_inside_check

normal_inside:
    movaps  xmm4, xmm2              ; And in the inside case:
    cmpps   xmm4, xmm3, 0           ; step(t2, v3(t exit))
    andps   xmm4, [v4_one]

    movaps  xmm5, xmm1              ; To get the hit normal, we multiply the
    andps   xmm5, [v4_sign_mask]    ; above calculation by the negative sign
    xorps   xmm5, [v4_sign_mask]    ; of the ray direction...
    xorps   xmm4, xmm5
    ;xorps   xmm4, [v4_sign_mask]
    v3norm  xmm4, xmm14, xmm15      ; ...and normalize.

normal_post_inside_check:
    movaps  xmm12, xmm4
    ;movaps  xmm5, xmm1              ; To get the hit normal, we multiply the
    ;andps   xmm5, [v4_sign_mask]    ; above calculation by the negative sign
    ;xorps   xmm5, [v4_sign_mask]    ; of the ray direction...
    ;xorps   xmm4, xmm5
    ;v3norm  xmm4, xmm14, xmm15      ; ...and normalize.

    mulps   xmm2, xmm1              ; To get the hit position, we scale the ray
    addps   xmm0, xmm2              ; direction by our t hit value.

    ;movaps  xmm5, xmm4              ; Due to floating point imprecision, this
    ;mulps   xmm5, [v4_eps]          ; might result in a position which, for
    ;cmp     r9, 0
    ;jne     add_eps_inside
    ;addps   xmm0, xmm5
    ;jmp     add_eps_over
;add_eps_inside:
;    subps   xmm0, xmm5
;add_eps_over:
    ;addps   xmm0, xmm5              ; instance, causes a hit from the outside to
                                    ; land inside the cube, which would cause
                                    ; a reflected bounce to immediately collide.
                                    ; There are multiple ways to fix this, but
                                    ; we've opted to add a small amount (v4_eps)
                                    ; of the normal to nudge it out of that
                                    ; danger zone.

    movaps  xmm8, xmm1              ; Calculate cos of the angle from the normal
    v3norm  xmm8, xmm14, xmm15      ; on the refracted side with the following:
    movaps  xmm5, xmm8              ;   min(dot(-unit_ray_dir, normal), 1.0)
    xorps   xmm5, [v4_sign_mask]    
    dpps    xmm5, xmm4, 01110111b
    minps   xmm5, [v4_one]
    
    movaps  xmm6, xmm5              ; Calculate the sin of the same angle by:
    mulps   xmm6, xmm6              ;   sqrt(1.0 - cos(theta) * cos(theta))
    xorps   xmm6, [v4_sign_mask]
    addps   xmm6, [v4_one]
    sqrtps  xmm6, xmm6

    cmp     r9, 0                   ; If we are refracting from outside, we use
    jne     refract_inside          ; the reciprocal of the refractive index of
                                    ; our material in the below calculations.
    movaps  xmm7, [v4_refract_index_reciprocal]
    jmp     refract_post_inside_check
refract_inside:                     ; Otherwise, we use the refractive index
    movaps  xmm7, [v4_refract_index]; itself. We'll call this value "refract".
refract_post_inside_check:

    mulps   xmm6, xmm7              ; If (refract * sin(theta) > 1.0), which
    ucomiss xmm6, [v4_one]          ; corresponds to a ray entering a medium at
    ja      bounce_reflect          ; a glancing angle, which causes the
                                    ; relevant refraction equation to have no
                                    ; solution. In this case, the ray must be
                                    ; reflected.

    ; r0 = (1 - refraction_index) / (1 + refraction_index)
    movss   xmm6, [v4_one]
    movss   xmm9, xmm6
    movss   xmm10, [v4_refract_index]
    subss   xmm6, xmm10
    addss   xmm9, xmm10
    divss   xmm6, xmm9
    
    ; r1 = r0 * r0
    mulss   xmm6, xmm6
    
    ; r2 = r1 + (1 - r1) * pow(1 - cos(theta), 5)
    movss   xmm9, [v4_one]
    movss   xmm10, xmm9
    subss   xmm9, xmm6
    subss   xmm10, xmm5
    movss   xmm11, xmm10
    mulss   xmm10, xmm11
    mulss   xmm10, xmm11
    mulss   xmm10, xmm11
    mulss   xmm10, xmm11
    mulss   xmm10, xmm11
    mulss   xmm10, xmm9
    addss   xmm6, xmm10

    frand_unsigned xmm9
    subss   xmm9, [reflectance_bias]
    ucomiss xmm6, xmm9
    ja      bounce_reflect

bounce_refract: ; Label only for clarity
    movaps  xmm6, xmm5              ; Calculate the part of the outgoing ray
    mulps   xmm6, xmm4              ; which is perpendicular to the normal by:
    addps   xmm6, xmm8              ;   refract *
    mulps   xmm6, xmm7              ;   (unit_ray_dir + cos(theta) * normal)

    movaps  xmm7, xmm6              ; And the part which is parallel by:
    dpps    xmm7, xmm7, 01110111b   ;   -sqrt(abs(
    xorps   xmm7, [v4_sign_mask]    ;   1.0 - perpendicular.length_squared))
    addps   xmm7, [v4_one]          ;   * normal
    andps   xmm7, [v4_abs_mask]
    sqrtps  xmm7, xmm7
    xorps   xmm7, [v4_sign_mask]
    mulps   xmm7, xmm4

    addps   xmm6, xmm7              ; And the final refracted vector is the
    movaps  xmm1, xmm6              ; perpendicular and parallel parts added
    v3norm  xmm1, xmm14, xmm15

    movaps  xmm5, xmm4              ; Due to floating point imprecision, this
    mulps   xmm5, [v4_eps]          ; might result in a position which, for
    cmp     r9, 0
    subps   xmm0, xmm5              ; instance, causes a hit from the outside to

    ;movaps  xmm5, [r15+Thread.color_attenuation]
    ;mulps   xmm5, [v4_color_attenuation]
    ;movaps  [r15+Thread.color_attenuation], xmm5

    jmp     bounce_over             ; together.

bounce_reflect:
    movaps  xmm5, [r15+Thread.color_attenuation]
    mulps   xmm5, [v4_color_attenuation]
    movaps  [r15+Thread.color_attenuation], xmm5

    ; reflected vector = v - 2.0 * dot(v,n) * n
    movaps  xmm5, xmm4          ; xmm7: normal
    dpps    xmm5, xmm1, 01110111b ; xmm7: dot(v,n)
    mulps   xmm5, xmm4          ; xmm7: dot(v,n) * n
    mulps   xmm5, [v4_two] ; xmm7: 2.0 * dot(v,n) * n
    subps   xmm1, xmm5        ; xmm11: reflected vector
    v3norm  xmm1, xmm14, xmm15

    movaps  xmm5, xmm4              ; Due to floating point imprecision, this
    mulps   xmm5, [v4_eps]          ; might result in a position which, for
    cmp     r9, 0
    addps   xmm0, xmm5              ; instance, causes a hit from the outside to

bounce_over:

    frand_normal xmm5, xmm15
    frand_normal xmm6, xmm15
    shufps  xmm6, xmm6, 0
    frand_normal xmm7, xmm15
    shufps  xmm7, xmm7, 0
    blendps xmm8, xmm6, 0010b
    blendps xmm8, xmm7, 0100b
    v3norm  xmm8, xmm14, xmm15
    mulps   xmm8, [v4_fuzz_factor]
    addps   xmm1, xmm8

    jmp     ray_start

calculate_sample_color:
    ;movaps  xmm1, xmm10
    v3norm  xmm1, xmm3, xmm4
    addps   xmm1, [v4_half]         ; TODO: is this fucking with anything?
    ;shufps  xmm1, xmm1, 01010101b
    maxps   xmm1, [v4_zero]
    mulps   xmm1, [r15+Thread.color_attenuation]
    movaps  xmm2, [r15+Thread.color_sum]
    addps   xmm1, xmm2
    movaps  [r15+Thread.color_sum], xmm1

    inc     word [r15+Thread.sample_index]
    cmp     word [r15+Thread.sample_index], SAMPLE_COUNT
    jl      sample_start

write_to_pixel:
    movaps  xmm0, [r15+Thread.color_sum]
    divps   xmm0, [v4_sample_count]
    sqrtps  xmm0, xmm0              ; correct gamma
    mulps   xmm0, [v4_255]
    cvtps2dq xmm0, xmm0             ; convert to dword integers
    packusdw xmm0, xmm0             ; pack into 16bit words
    packuswb xmm0, xmm0             ; pack into bytes
    mov     r8d, [r15+Thread.current_pixel]
    movd    dword [pixels+r8d*4], xmm0 ; move to pixel location

%if OUTPUT_FRAMES_TO_FILE
    push    r9
    push    r10
    push    r11
    push    r12
    lea     rax, [pixels+r8d*4]
    mov     rcx, [rax+2]
    mov     rdx, [rax+1]
    mov     rsi, [rax+0]
    mov     rdi, img_line
    call    printf
    pop     r12
    pop     r11
    pop     r10
    pop     r9
%endif

    inc     dword [r15+Thread.current_pixel]
    mov     r8d, [r15+Thread.end_pixel]
    cmp     dword [r15+Thread.current_pixel], r8d
    jl      pixel_start

    ; Return to thread idle to wait for more work
    lock add [regions_completed], 1
    jmp     thread_idle

;= End Frame ===============================================
; This is executed by the host thread once all pixel regions
; are finished rendering.
;
; We push our pixels to the OpenGL texture, update our
; viewport, draw the texture across the screen, then jump
; back to start frame.
;===========================================================
end_frame:
%if UPDATE_GL = 1
    push    0
    push    pixels
    push    0x1401                  ; GL_UNSIGNED_BYTE
    push    0x1908                  ; GL_RGBA
    mov     r9d, 0
    mov     r8d, PIXELS_H
    mov     ecx, PIXELS_W
    mov     edx, 0x1908             ; GL_RGBA
    mov     esi, 0
    mov     edi, 0x0DE1             ; GL_TEXTURE_2D
    call    glTexImage2D
    add     rsp, 32

    sub     rsp, 16                 ; make space for framebuffer dimensions
    lea     rdx, [rsp+0x00]         ; width
    lea     rsi, [rsp+0x08]         ; height
    mov     rdi, [glfw_window]
    call    glfwGetFramebufferSize

    mov     rcx, [rsp+0x00]
    mov     rdx, [rsp+0x08]
    mov     rsi, 0
    mov     rdi, 0
    call    glViewport
    add     rsp, 16

    movss   xmm3, [v4_zero]
    movss   xmm2, [v4_zero]
    movss   xmm1, [v4_zero]
    movss   xmm0, [v4_zero]
    call    glClearColor
    mov     edi, 0x00004000         ; GL_COLOR_BUFFER_BIT
    call    glClear

    mov     edi, [gl_program]
    call    glUseProgram

    mov     esi, [gl_texture]
    mov     edi, 0x0DE1             ; GL_TEXTURE_2D
    call    glBindTexture

    mov     edi, [gl_vao]
    call    glBindVertexArray

    mov     edx, [verts_len]
    mov     esi, 0
    mov     edi, 0x0004             ; GL_TRIANGLES
    call    glDrawArrays

    mov     rdi, [glfw_window]      ; Main loop end
    call    glfwSwapBuffers
    call    glfwPollEvents
%endif

%if OUTPUT_FRAMES_TO_FILE            ; Flush stdout, otherwise if we exit the
    mov     rdi, 0                  ; program at the start of the next frame it
    call    fflush                  ; might have insufficient time to finish
%endif                              ; writing data

    movss   xmm0, [cam_theta]
    ucomiss xmm0, [pi2]
    ja      exit_host

    jmp start_frame                 ; And off we go again

;= Compile Shader ==========================================
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
    mov     [rsp+0x00], rsi         ; src len address
    mov     [rsp+0x08], rdx         ; src address ptr

    call    glCreateShader          ; type already in edi
    mov     [rsp+0x10], rax         ; shader id

    mov     rcx, [rsp+0x00]
    mov     rdx, [rsp+0x08]
    mov     rsi, 1
    mov     rdi, [rsp+0x10]
    call    glShaderSource

    mov     rdi, [rsp+0x10]
    call    glCompileShader

    lea     rdx, [rsp+0x18]         ; compilation success flag
    mov     rsi, 0x8B81             ; GL_COMPILE_STATUS
    mov     rdi, [rsp+0x10]
    call    glGetShaderiv

    cmp     qword [rsp+0x18], 0
    jne     compile_shader_success

    mov     rcx, msg                ; Log error if compilation failed
    mov     rdx, 0
    mov     rsi, msglen
    mov     rdi, [rsp+0x10]
    call    glGetShaderInfoLog

    mov     rax, 1                  ; write syscall
    mov     rdi, 1                  ; stdout
    mov     rsi, msg
    mov     rdx, msglen
    syscall

compile_shader_success:
    mov     esi, [rsp+0x10]
    mov     edi, [gl_program]
    call    glAttachShader

    mov     rax, [rsp+0x10]         ; return shader id
    add     rsp, 40
    ret

