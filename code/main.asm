default rel

%include 'vec3.asm'
%include 'rand.asm'

;= Configuration Symbols ===================================
THREAD_COUNT            equ 8
SAMPLE_COUNT            equ 8
%define FSAMPLE_COUNT       8.0
BOUNCE_COUNT            equ 32
CUBES_COUNT             equ 1

PIXELS_W                equ 256
%define FPIXELS_W           256.0
PIXELS_H                equ 256
%define FPIXELS_H           256.0
PIXELS_COUNT            equ PIXELS_W * PIXELS_H
PIXEL_BUFFER_SIZE       equ PIXELS_COUNT * 4
REGION_STRIDE           equ PIXELS_W
REGIONS_COUNT           equ PIXELS_COUNT / REGION_STRIDE

OUTPUT_FRAMES_TO_FILE   equ 0

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
    .color_sum      resq 2
    .host            resd 1
    .seed           resd 1
    .current_pixel  resd 1
    .end_pixel      resd 1
    .sample_index   resb 1
    .bounce_index   resb 1
    .object_index   resb 1
    alignb 64
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
msglen equ 4096
msg             db 'msg error', 10, 0
window_name     db 'Empedocles Renderer', 10, 0
debug_msg       db 'cam %f, %f, %f', 10, 0
img_header      db 'P3', 10, '270 480', 10, '255', 10, 0
img_line        db '%hhu %hhu %hhu', 10, 0

%include 'generation/generated_data.asm'

vert_src_ptr    dq vert_src
frag_src_ptr    dq frag_src
verts           dd 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0, 1.0
verts_len       dd 12

align 64
pixels_w        dd PIXELS_W

align 64
v4_zero         dd 0.0, 0.0, 0.0, 0.0
v4_half         dd 0.5, 0.5, 0.5, 0.0
v4_one          dd 1.0, 1.0, 1.0, 0.0
v4_red          dd 1.0, 0.0, 0.0, 0.0
v4_green        dd 0.0, 1.0, 0.0, 0.0
v4_blue         dd 0.0, 0.0, 1.0, 0.0
v4_255          dd 255.0, 255.0, 255.0, 0.0
v4_sample_count dd FSAMPLE_COUNT,FSAMPLE_COUNT,FSAMPLE_COUNT,0.0
v4_pixels_w     dd FPIXELS_W,FPIXELS_W,FPIXELS_W,0.0
v4_pixels_h     dd FPIXELS_H,FPIXELS_H,FPIXELS_H,0.0

;===========================================================
section .bss align=64
;===========================================================

regions_started     resd 1
regions_completed   resd 1
host_terminated  resb 1

alignb 64
thread_memory_array resb Thread_size * THREAD_COUNT

alignb 64
pixels              resb PIXEL_BUFFER_SIZE * 2

glfw_window         resq 1
gl_texture          resd 1
gl_vao              resd 1
gl_program          resd 1

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
        lea     rsi, [thread_memory_array + Thread_size * i] ; child stack pointer
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
; jumps to render_region, where it performs its work,
; iterating regions_started and regions_complete in the
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
; * Notify threads to start work by setting regions_started
;   and regions_complete to 0
;===========================================================
start_frame:
    mov     rdi, [glfw_window]      ; If GLFW has recieved a close request, we
    call    glfwWindowShouldClose   ; politely comply
    cmp     eax, 1
    je      exit_host

%if OUTPUT_FRAMES_TO_FILE            ; For rendering ppm frames
    mov     rdi, img_header
    call    printf
%endif

    ; TODO: update logical camera, calculate viewport values

    xor     eax, eax                ; Reset region counters to start next frame
    xchg    [regions_completed], eax
    xor     eax, eax
    xchg    [regions_started], eax
    ;mov    [regions_started], 0    ; Alternate way, want to profile to see
    ;mov    [regions_completed], 0  ; if it's faster or slower
    jmp     thread_idle             ; Back to thread_idle to work on rendering

;= Render Region ===========================================
; Threads execute this repeatedly until all regions have
; been started. It runs in nested loops of the following
; structure:
;
;   pixel_start: for each pixel {
;       sample_start: for each sample {
;           calculate ray direction from camera
;           ray_start: for each bounce {
;               intersection_start: for each object {
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
    mov     byte [r15+Thread.sample_index], 0
    pxor    xmm0, xmm0
    movaps  [r15+Thread.color_sum], xmm0
sample_start:
    xor     rax, rax
    xor     rdx, rdx
    mov     eax, [r15+Thread.current_pixel]
    div     dword [pixels_w]
    cvtsi2ss xmm0, edx              ; x (i % w)
    cvtsi2ss xmm1, eax              ; y (i / w)

    ; For now, we are rendering a gradient
    shufps  xmm0, xmm0, 0
    shufps  xmm1, xmm1, 0
    divps   xmm0, [v4_pixels_w]
    divps   xmm1, [v4_pixels_h]
    mulps   xmm0, [v4_red]
    mulps   xmm1, [v4_green]
    addps   xmm0, xmm1
    movaps  xmm1, [r15+Thread.color_sum]
    addps   xmm0, xmm1
    movaps  [r15+Thread.color_sum], xmm0

    inc     byte [r15+Thread.sample_index]
    cmp     byte [r15+Thread.sample_index], SAMPLE_COUNT
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
; back to start_frame.
;===========================================================
end_frame:
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

%if OUTPUT_FRAMES_TO_FILE            ; Flush stdout, otherwise if we exit the
    mov     rdi, 0                  ; program at the start of the next frame it
    call    fflush                  ; might have insufficient time to finish
%endif                              ; writing data

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

