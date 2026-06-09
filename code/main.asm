format ELF64

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

extrn gl3wInit
extrn gl3wIsSupported
extrn glfwInit
extrn glfwCreateWindow
extrn glfwWindowHint
extrn glfwMakeContextCurrent
extrn glfwWindowShouldClose
extrn glfwSwapBuffers
extrn glfwPollEvents
extrn glfwTerminate
extrn glfwGetFramebufferSize
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

;= Configuration Symbols ===================================
thread_count         = 1
sample_count         = 4
fsample_count      equ 4.0
bounce_count         = 32
cubes_count          = 1

pixels_w             = 256
pixels_h             = 256
pixels_count         = pixels_w * pixels_h
pixel_buffer_size    = pixels_count * 4
region_stride        = pixels_w
regions_len          = pixels_count / pixel_regions_stride

output_frame_to_file = 1

;= Structs =================================================
struc ThreadMemory seed {
    .seed         dd seed
    .pid          dd 0
    .start_pixel  dd 0
    .end_pixel    dd 0
    .sample_index db 0
    .bounce_index db 0
    .object_index db 0
}

;===========================================================
section '.text' executable
;===========================================================

public __dso_handle
__dso_handle:
    dd 0

exit_host:
    mov     [program_terminated], 1
    call    glfwTerminate
exit:
    mov     rax, 60                 ; exit
    xor     rdi, rdi
    syscall 

public _start
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
    mov     edi, 0x0DE1             ; 0x0DE1 ; GL_TEXTURE_2D
    call    glTexParameteri
    mov     edx, 0x812F             ; GL_CLAMP_TO_EDGE
    mov     esi, 0x2803             ; GL_TEXTURE_WRAP_T
    mov     edi, 0x0DE1             ; 0x0DE1 ; GL_TEXTURE_2D
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
    mov     [regions_completed], 0
    mov     [regions_started], regions_count ; otherwise the threads
                                             ; will start before the
                                             ; first frame is ready.
    lea     r15, [thread_memory_array] ; Define base values for host thread
    mov     [r15+ThreadMemory+pid], 0  ; pid = 0 for host thread
if thread_count > 1
    repeat thread_count-1
        local not_child_thread
        mov     rax, 56             ; sys_clone
        mov     rdi, CLONE_FLAGS    ; flags
        lea     rsi, [thread_memory_array + ThreadMemory.sizeof * %] ; child stack pointer
        mov     rdx, 0              ; parent thread id
        mov     r10, %              ; child thread id
        mov     r8, 0               ; child thread local storage
        syscall
        cmp     rax, 0
        jl      exit                ; error creating thread
        je      not_child_thread
        mov     r15, rsp            ; store thread memory ptr in r15
        mov     [r15+pid], rax      ; store pid
        jmp     thread_idle         ; child threads jump straight to idle and
                                    ; wait for work...
not_child_thread:
    end repeat
end if
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
    cmp     [program_terminated], 1 ; the host tips off the children to exit
    je      exit                    ; with program_terminated
    mov     eax, 1
    lock    xadd [regions_started], eax ; iterate regions_started, storing the
                                        ; next region index in eax
    cmp     eax, regions_len
    jge     all_regions_started
                                    ; We have a region to render:
    mov     r8, region_stride       ; calculate start pixel index
    mul     r8                      ; store stride * index (eax) in r8
    mov     [r15+ThreadMemory.start_pixel], r8
    add     r8, region_stride       ; add stride to get end pixel index
    mov     [r15+ThreadMemory.end_pixel], r8
    jmp     render_region
all_regions_started:
    cmp     [r15+ThreadMemory.pid], 0
    je      thread_idle             ; child threads keep patiently waiting
check_regions_complete:
    cmp     [regions_completed], regions_len ; the host thread instead wants to
    jge     end_frame                        ; know if all the regions are
    jmp     thread_idle                      ; complete so it can end the frame

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
    je      host_exit

if output_frames_to_file            ; For rendering ppm frames
    mov     rdi, img_header
    call    printf
end if

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
; regions_complete and jump back to thread_idle to wait for
; more work.
;===========================================================
render_region:
    ; Return to thread_idle to wait for more work
    lock add [regions_complete], 1
    jmp thread_idle

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
    mov     r8d, pixels_h
    mov     ecx, pixels_w
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

    movss   xmm3, [clear_a]
    movss   xmm2, [clear_b]
    movss   xmm1, [clear_g]
    movss   xmm0, [clear_r]
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

if output_render                    ; Flush stdout, otherwise if we exit the
    mov     rdi, 0                  ; program at the start of the next frame it
    call    fflush                  ; might have insufficient time to finish
end if                              ; writing data

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

    jmp     exit

compile_shader_success:
    mov     esi, [rsp+0x10]
    mov     edi, [gl_program]
    call    glAttachShader

    mov     rax, [rsp+0x10]         ; return shader id
    add     rsp, 40
    ret

;===========================================================
section '.data' writable align 64
;===========================================================

msglen       = 4096
msg         db 'msg error', 10, 0
window_name db 'Empedocles Renderer', 10, 0
debug_msg   db 'cam %f, %f, %f', 10, 0

include 'generation/generated_data.asm'
vert_src_ptr dq vert_src
frag_src_ptr dq frag_src
verts        dd 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0, 1.0
verts_len    dd 12

;===========================================================
section '.bss' align 64
;===========================================================

virtual at 0
    ThreadMemory ThreadMemory ?
end virtual

thread_regions_started   rd
thread_regions_completed rd
program_terminated       rb

align 64
thread_memory_array ThreadMemory thread_count dup % * 1000 ; array of thread local memory
                                                           ; % * 1000 is rand seed calculation
glfw_window rq 1
gl_texture  rd 1
gl_vao      rd 1
gl_program  rd 1
