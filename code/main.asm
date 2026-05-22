;===========================================================
; TODOS
; - Tracing against AABBs
; - Arbitary voxel grid roation (cam/viewport transform)
; - Multithreading with sys_clone call
; - SIMD instructions
;===========================================================

format ELF64

;===========================================================
section '.text' executable
;===========================================================

include 'vec3.asm'

; When linking with gl3w, we ge an undefined reference to
; __dso_handle. This shit is a little too esoteric for my
; paygrade, but defining it here like this seems to work.
public __dso_handle
__dso_handle:
    dd 0

; libc
extrn sinf
extrn cosf
extrn printf
; glfw
extrn glfwInit
extrn glfwCreateWindow
extrn glfwWindowHint
extrn glfwMakeContextCurrent
extrn glfwWindowShouldClose
extrn glfwSwapBuffers
extrn glfwPollEvents
extrn glfwTerminate
extrn glfwGetFramebufferSize
; gl
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
; gl3w
extrn gl3wInit
extrn gl3wIsSupported

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
    imul    ebp, ebx            ; TODO: learn about mul and imul. something
                                ; something lower bits
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

;===========================================================
; MAIN LOOP:
; This runs repeatedly until the program wants to exit
;===========================================================
loop_begin:
    mov     rdi, [glfw_window]
    call    glfwWindowShouldClose
    cmp     eax, 1
    je      exit

    ; Orbit camera around the origin
    ;   x = dist * sin(phi) * cos(theta);
    ;   y = dist * cos(phi);
    ;   z = dist * sin(phi) * sin(theta);
    ; theta being left/right and phi being up/down
    movss   xmm0, [cam_theta]   ; xmm0, cam_theta
    addss   xmm0, [cam_theta_per_sec]
    movss   [cam_theta], xmm0   ; cam_theta += cam_theta_per_second

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

    movss   [v4_lookfrom+0x00], xmm9
    movss   [v4_lookfrom+0x04], xmm10
    movss   [v4_lookfrom+0x08], xmm11

    ;mov     rax, 3
    ;cvtss2sd xmm2, xmm9
    ;cvtss2sd xmm1, xmm10
    ;cvtss2sd xmm0, xmm11
    ;mov     rdi, debug_msg
    ;call    printf

;===========================================================
; RENDER PROCEDURE
;
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
    ; Initialization is dedicated to getting these values,
    ; and these registers will be stable throughout the
    ; inner pixel loop:
    ;   xmm12: pixel delta u
    ;   xmm13: pixel delta v
    ;   xmm14: pixel center at uv (0,0)
    ;   xmm15: look from, camera origin
    movaps  xmm15, dqword [v4_lookfrom]        ; xmm15 has lookfrom

    ; Calculate camera basis vectors:
    ;   xmm8  <- u = norm(cross(up, w))
    ;   xmm9  <- v = cross(w, u)
    ;   xmm10 <- = norm(from - at)
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

    ; pixel00 = viewport_origin + (0.5 * (pixel_delta_u + pixel_delta_v));
    movaps  xmm1, xmm12         ; xmm1: pixel_delta_u
    addps   xmm1, xmm13         ; xmm1: pd_u + pd_v
    mulps   xmm1, xmm0          ; xmm1: 0.5 * (pd_u + pd_v)
    addps   xmm14, xmm1         ; xmm14: pixel00

; We've gathered the values listed above in xmm12-15 and
; now it's time to do the tight pixel loop.
;
; For now, we assume SSE 4.2 suppport. Once we get to deeper
; optimizations, we should make versions of this loop for
; sse 4.2, avx, avx2, and avx512
;
; Here's a good scheme which is nicely scaleable to
; different instruction sets:
;
; Cube mins/maxes are packed into stack memory, and the
; blah blah you get the picture. Let's try to do shitty
; first then work with simd shit.
;
; NOTE: when we multithread/simd, doing square chunks of the
; screen makes no sense both for cache locality and perhaps
; more importantly, for distributing work equally. The
; corners of the screen, for instance, will have less
; intersections than the center. So, we should instead have
; each execution unit process a row of pixels at a time,
; skipping rows equalling the number of threads so that each
; thread hypothetically touches the cuby bits a roughly
; equal number of times. This might mean a cache miss every
; time a row is done, but I feel like we still win over the
; stalling that would obviously happen if we chunked it up
; differently. Maybe try to find the right balance. Not
; rows perhaps, but some number of pixels processed before
; skipping. Could graph it!

    xor     edi, edi             ; edi: pixel counter
pixel_loop_begin:
    xor     edx, edx
    mov     eax, edi
    div     dword [i_pixels_w]
    mov     esi, edx            ; esi: x = (i % w)
    mov     ecx, eax            ; ecx: y = (i / w)

    ; First we deterine the ray direction by finding the
    ; point on the viewport which correlates with the
    ; current pixel coordinates, then taking the delta
    ; between that position and the camera origin and
    ; normalizing it.
    ;
    ; TODO: sample a random point within the viewport pixel
    cvtsi2ss xmm11, esi         ; xmm11 will become ray direction
    cvtsi2ss xmm1, ecx
    shufps  xmm11, xmm11, 0     ; xmm11: x
    shufps  xmm1, xmm1, 0       ; xmm1: y
    mulps   xmm11, xmm12        ; xmm11: y * pixel_delta_u
    mulps   xmm1, xmm13         ; xmm1: x * pixel_delta_v
    addps   xmm11, xmm1
    addps   xmm11, xmm14        ; xmm11: pixel center
    subps   xmm11, xmm15        ; xmm11: ray direction
    v3norm  xmm11               ; normalize ray direction

    ; Next, we determine whether the ray intersects with an
    ; axis aligned box centered at the origin.
    ;
    ; Branchless ray/bounding box intersection:
    ;   (https://tavianator.com/2022/ray_box_boundary.html)
    ;
    ; tmin/tmax will describe the distance along the ray
    ; which intersects the box. We will shrink the distance
    ; between these by clipping them with each plane of the
    ; box.
    ;
    ; At the start, tmin=0 and tmax=infinity. If tmin > tmax
    ; after clipping, the ray does not intersect.

    ; TODO: We are going to try adapting the ray/box 
    ; intersection algorithm in section 5 of the following
    ; paper:
    ;   (https://jcgt.org/published/0007/03/04/paper-lowres.pdf)
    ; We won't need to reorient the ray or determine the
    ; winding, as the box is axis aligned and we won't cull
    ; any faces because it is transparent.
    
    movaps  xmm0, xmm11         ; calculate inverse of ray direction
    movaps  xmm10, dqword [v4_one]
    divps   xmm10, xmm0         ; xmm10 = 1.0 / dir. apparently, the divide by
                                ; 0 (=infinity) still works here
    xorps   xmm9, xmm9          ; xmm9: tmin = 0.0
    movss   xmm8, [v4_inf]      ; xmm8: tmax = infinity
    movaps  xmm7, dqword [v4_boxmin] ; xmm7: boxmin
    movaps  xmm6, dqword [v4_boxmax] ; xmm6: boxmax

macro clip_ray dim {
    ; available registers: xmm0-xmm5
    ; t1 = (bmin[d] - origin[d]) * dir_inv[d]
    extractps esi, xmm7, dim
    extractps ecx, xmm15, dim
    extractps edx, xmm10, dim
    movd    xmm0, esi       ; xmm0: bmin[d]
    movd    xmm1, ecx       ; xmm1: origin[d]
    movd    xmm2, edx       ; xmm2: dir inverse[d]
    subss   xmm0, xmm1      ; xmm0: bmin[d] - origin[d]
    mulss   xmm0, xmm2
    movss   xmm3, xmm0      ; xmm3: t1

    ; t2 = (bmin[d] - origin[d]) * dir_inv[d]
    extractps esi, xmm6, dim
    movd    xmm0, esi       ; xmm0: bmax[d]
    subss   xmm0, xmm1      ; xmm0: bmin[d] - origin[d]
    mulss   xmm0, xmm2      ; xmm0: t2

    ; available registers: xmm1, xmm2, xmm4, xmm5
    ; tmin = max(tmin, min(min(t1, t2), tmax))
    movss   xmm5, xmm3      ; xmm5: t1
    minss   xmm5, xmm0      ; xmm5: min(t1, t2)
    movss   xmm1, xmm8      ; xmm1: tmax
    minss   xmm1, xmm5      ; xmm1: min(min(t1, t2), tmax)
    maxss   xmm9, xmm1      ; xmm9: updated tmin
    ; tmax = min(tmax, max(max(t1, t2), tmin))
    movss   xmm5, xmm3      ; xmm5: t1
    maxss   xmm5, xmm0      ; xmm5: max(t1, t2)
    movss   xmm1, xmm9      ; xmm1: tmin
    maxss   xmm1, xmm5      ; xmm1: max(max(t1, t2), tmin)
    minss   xmm8, xmm1      ; xmm8: updated tmax
}
    clip_ray 0
    clip_ray 1
    clip_ray 2

    ; If we didn't intersect, get color from ray direction
    andps   xmm11, dqword [abs_mask] ; xmm11: absolute value for color
    mulps   xmm11, dqword [v4_255] ; xmm11 scaled by 255 for rgb space
    ucomiss xmm9, xmm8
    jb      intersect
    jmp     pixel_loop_end
intersect:
    mulps   xmm11, dqword [v4_viewport_w] ; causing an overflow makes for a
                                          ; really cool pattern
pixel_loop_end:
    cvtps2dq xmm11, xmm11       ; convert to dword integers
    packusdw xmm11, xmm11       ; pack into 16bit words
    packuswb xmm11, xmm11       ; pack into bytes
    movd     dword [pixels+rdi*4], xmm11 ; move to pixel location
    inc     edi
    cmp     edi, pixels_len
    jl      pixel_loop_begin

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
    jmp     loop_begin

error:                          ; TODO: Implement error messages
    jmp     exit

exit:
    call    glfwTerminate
    mov     rax, 60             ; exit
    xor     rdi, rdi
    syscall 

;===========================================================
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
; Writes an rgb value to the pixels buffer.
;
; NOTE: This will likely be inlined as part of the render
; loop, obvs
;
; input:
;   edx: color
;   rsi: y
;   rdi: x
; output: none
;===========================================================
put_color:
    add     rsp, 8
    mov     [rsp], edx
    mov     r10, rsi
    xor     rax, rax
    mov     eax, pixels_w
    mul     r10
    mov     r10, rax
    add     r10, rdi            ; r10 is now (y * width + x)
    mov     rax, 4
    mul     r10                 ; multiply r10 by color channels (4)
    lea     r9, [pixels+rax]    ; r9 now pointing to screen pixel
    mov     r11, [rsp]
    mov     dword [r9], r11d    ; Write pixel
    sub     rsp, 8

;===========================================================
section '.data' writeable align 16
;===========================================================

msglen     = 4096
; WARNING: v4_pixels__ below needs to match these
pixels_w   = 256
pixels_h   = 256
pixels_len = pixels_w * pixels_h

msg         rd msglen           ; general purpose string buffer
window_name db 'Empedocles Renderer', 0

debug_msg   db 'cam %f, %f, %f', 10, 0

; render data
align 16
pixels            rb pixels_len * 4
clear_r           dd 0.3
clear_g           dd 0.1
clear_b           dd 0.2
clear_a           dd 1.0
i_pixels_w        dd pixels_w
cam_theta         dd 1.1
cam_phi           dd -2.1
cam_theta_per_sec dd 0.01
cam_dist          dd 2.0
; Aligned and quadrupled for use in xmm registers
align 16
; useful numbers
v4_inf        dd 0x7F800000, 0x7F800000, 0x7F800000, 0x7F800000
;v4_inf        dd 100000.0, 100000.0, 100000.0, 100000.0
v4_half       dd 0.5, 0.5, 0.5, 0.5
v4_one        dd 1.0, 1.0, 1.0, 1.0
v4_four       dd 4.0, 4.0, 4.0, 4.0
v4_255        dd 255.0, 255.0, 255.0, 255.0
abs_mask      dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
; constants
v4_lookfrom   dd 0.0, 0.0, 0.0, 0.0
v4_lookat     dd 0.0, 0.0, 0.0, 0.0
v4_upvector   dd 0.0, 1.0, 0.0, 0.0
v4_focal_len  dd 2.0, 2.0, 2.0, 2.0
v4_viewport_h dd -2.5, -2.5, -2.5, -2.5
v4_viewport_w dd 2.5, 2.5, 2.5, 2.5
v4_pixels_w   dd 256.0, 256.0, 256.0, 256.0
v4_pixels_h   dd 256.0, 256.0, 256.0, 256.0
v4_boxmin     dd -0.5, -0.5, -0.5, -0.5
v4_boxmax     dd 0.5, 0.5, 0.5, 0.5

; gl data
glfw_window  rq 1
gl_texture   rd 1
gl_vao       rd 1
gl_program   rd 1
verts        dd 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0, 1.0
verts_len    dd 12

include 'generation/generated_data.asm'
vert_src_ptr dq vert_src
frag_src_ptr dq frag_src
