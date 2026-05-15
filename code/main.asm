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
	mov     edi, 0x00022002 ; GLFW_CONTEXT_VERSION_MAJOR
	call    glfwWindowHint
	mov     esi, 6
	mov     edi, 0x00022003 ; GLFW_CONTEXT_VERSION_MINOR
	call    glfwWindowHint
	mov     esi, 0x00022008 ; GLFW_OPENGL_CORE_PROFILE
	mov     edi, 0x00032001 ; GLFW_OPENGL_PROFILE
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

	; Screen texture
	mov     rsi, gl_texture
	mov     rdi, 1
	call    glGenTextures

	mov     esi, [gl_texture]
	mov     edi, 0x0DE1 ; GL_TEXTURE_2D
	call    glBindTexture

	mov     edx, 0x812F ; GL_CLAMP_TO_EDGE
	mov     esi, 0x2802 ; GL_TEXTURE_WRAP_S
	mov     edi, 0x0DE1 ; 0x0DE1 ; GL_TEXTURE_2D
	call    glTexParameteri
	mov     edx, 0x812F ; GL_CLAMP_TO_EDGE
	mov     esi, 0x2803 ; GL_TEXTURE_WRAP_T
	mov     edi, 0x0DE1 ; 0x0DE1 ; GL_TEXTURE_2D
	call    glTexParameteri
	mov     edx, 0x2600 ; GL_NEAREST
	mov     esi, 0x2801 ; GL_TEXTURE_MIN_FILTER
	mov     edi, 0x0DE1 ; GL_TEXTURE_2D
	call    glTexParameteri
	mov     edx, 0x2600 ; GL_NEAREST
	mov     esi, 0x2800 ; GL_TEXTURE_MAG_FILTER
	mov     edi, 0x0DE1 ; GL_TEXTURE_2D
	call    glTexParameteri

	; debug color texture
	mov     rdi, 0
pixel_loop:
	mov     rax, rdi
	mov     rdx, 0
	mov     rcx, 256
	div     rcx

	lea     rsi, [screen+rdi]
	mov     byte [rsi], dl
	inc     rdi
	cmp     rdi, logical_w * logical_h * 4
	jne     pixel_loop

	;push    0
	;push    screen
	;push    0x1401 ; GL_UNSIGNED_BYTE
	;push    0x1908 ; GL_RGBA
	;mov     r9d, 0
	;mov     r8d, logical_h
	;mov     ecx, logical_w
	;mov     edx, 0x1908 ; GL_RGBA
	;mov     esi, 0
	;mov     edi, 0x0DE1 ; GL_TEXTURE_2D
	;call    glTexImage2D
	;add     rsp, 32

	; Quad mesh
	mov     rsi, gl_vao
	mov     edi, 1
	call    glGenVertexArrays

	mov     edi, [gl_vao]
	call    glBindVertexArray

	sub     rsp, 16 ; make space for vbo pointer
	lea     rsi, [rsp] ; [rsp] = vbo
	mov     edi, 1
	call    glGenBuffers

	mov     esi, [rsp]
	mov     edi, 0x8892 ; GL_ARRAY_BUFFER
	call    glBindBuffer
	add     rsp, 16 ; don't need vbo anymore

	mov     ebx, [verts_len]
	mov     ebp, 4
	; TODO: learn about mul and imul. something something lower bits
	imul    ebp, ebx
	mov     ecx, 0x88E4 ; GL_STATIC_DRAW
	mov     rdx, verts
	mov     esi, ebp
	mov     edi, 0x8892 ; GL_ARRAY_BUFFER
	call    glBufferData


	mov     edi, 0
	call    glEnableVertexAttribArray

	mov     r9d, 0
	mov     r8d, 8
	mov     ecx, 0
	mov     edx, 0x1406 ; GL_FLOAT
	mov     esi, 2
	mov     edi, 0
	call    glVertexAttribPointer

	; Shader program
	call    glCreateProgram
	mov     [gl_program], eax ; program id

	mov     rdx, vert_src_ptr
	mov     rsi, vert_src_len
	mov     edi, 0x8B31 ; GL_VERTEX_SHADER
	call    compile_shader
	mov     r12d, eax ; vert shader id

	mov     rdx, frag_src_ptr
	mov     rsi, frag_src_len
	mov     edi, 0x8B30 ; GL_FRAGMENT_SHADER
	call    compile_shader
	mov     r13d, eax ; frag shader id

	mov     edi, [gl_program]
	call    glLinkProgram

	mov     edi, r12d
	call    glDeleteShader
	mov     edi, r13d
	call    glDeleteShader
	; r12, r13 are free for use

;===========================================================
; MAIN LOOP:
; This runs repeatedly until the program wants to exit
loop_begin:
	mov     rdi, [glfw_window]
	call    glfwWindowShouldClose
	cmp     eax, 1
	je      exit

	; Update pixels
	mov     edx, 0xff0044ff
	mov     rsi, 50
	mov     rdi, [player_x]
	call    put_color
	add     [player_x], 3

;==========================================================
; RENDER PROCEDURE
; At a high level, our goal is such:
; for each pixel {
;    map pixel to a viewport position
;    cast ray from origin through viewport
;    for each cube {
;        determine if cube intersects
;        store cube color
;    } (summing colors per transparency)
;    write pixel to buffer
; }

;===========================================================
; UPDATE GL DATA

	push    0
	push    screen
	push    0x1401 ; GL_UNSIGNED_BYTE
	push    0x1908 ; GL_RGBA
	mov     r9d, 0
	mov     r8d, logical_h
	mov     ecx, logical_w
	mov     edx, 0x1908 ; GL_RGBA
	mov     esi, 0
	mov     edi, 0x0DE1 ; GL_TEXTURE_2D
	call    glTexImage2D
	add     rsp, 32

	sub     rsp, 16 ; make space for framebuffer dimensions
	lea     rdx, [rsp+0x00] ; width
	lea     rsi, [rsp+0x08] ; height
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
	mov     edi, 0x00004000 ; GL_COLOR_BUFFER_BIT
	call    glClear

	mov     edi, [gl_program]
	call    glUseProgram

	mov     esi, [gl_texture]
	mov     edi, 0x0DE1 ; GL_TEXTURE_2D
	call    glBindTexture

	mov     edi, [gl_vao]
	call    glBindVertexArray

	mov     edx, [verts_len]
	mov     esi, 0
	mov     edi, 0x0004 ; GL_TRIANGLES
	call    glDrawArrays

;===========================================================
; LOOP END

	mov     rdi, [glfw_window]
	call    glfwSwapBuffers
	call    glfwPollEvents
	jmp     loop_begin

; TODO: Implement error messages
error:
	jmp     exit

exit:
	call    glfwTerminate
	mov     rax, 60 ; exit
	xor     rdi, rdi
    syscall 

; ==========================================================
; Compiles a shader for OpenGL.
;
; input
;   rdx: src address ptr
;   rsi: src len address
;   rdi: type
; output
;   rax: shader id
compile_shader:
	sub     rsp, 40
	mov     [rsp+0x00], rsi ; src len address
	mov     [rsp+0x08], rdx ; src address ptr

	call    glCreateShader ; type already in edi
	mov     [rsp+0x10], rax ; shader id

	mov     rcx, [rsp+0x00]
	mov     rdx, [rsp+0x08]
	mov     rsi, 1
	mov     rdi, [rsp+0x10]
	call    glShaderSource

	mov     rdi, [rsp+0x10]
	call    glCompileShader

	lea     rdx, [rsp+0x18] ; compilation success flag
	mov     rsi, 0x8B81 ; GL_COMPILE_STATUS
	mov     rdi, [rsp+0x10]
	call    glGetShaderiv

	cmp     qword [rsp+0x18], 0
	jne     compile_shader_success

	; Log error if shader compilation failed
	mov     rcx, msg
	mov     rdx, 0
	mov     rsi, msglen
	mov     rdi, [rsp+0x10]
	call    glGetShaderInfoLog

	mov     rax, 1 ; write syscall
	mov     rdi, 1 ; stdout
	mov     rsi, msg 
	mov     rdx, msglen 
	syscall

	jmp     exit

compile_shader_success:
	mov     esi, [rsp+0x10]
	mov     edi, [gl_program]
	call    glAttachShader

	mov     rax, [rsp+0x10] ; return shader id
	add     rsp, 40
	ret

;===========================================================
; Writes an rgb value to the screen buffer.
;
; NOTE: This will likely be inlined as part of the render
; loop, obvs
;
; input:
;   edx: color
;   rsi: y
;   rdi: x
; output: none
put_color:
	add     rsp, 8
	mov     [rsp], edx
	mov     r10, rsi
	xor     rax, rax
	mov     eax, logical_w
	mul     r10
	mov     r10, rax
	add     r10, rdi ; r10 is now (y * width + x)
	mov     rax, 4
	mul     r10 ; multiply r10 by color channels (4)
	lea     r9, [screen+rax] ; r9 now pointing to screen pixel
	mov     r11, [rsp]
	mov     dword [r9], r11d ; Write pixel
	sub     rsp, 8

;===========================================================
section '.data' writeable
;===========================================================

msglen = 4096
msg         rd msglen; general purpose string buffer
window_name db 'Cube Games', 0

; game state
player_x     dq 0

; render data
glfw_window  rq 1
gl_texture   rd 1
gl_vao       rd 1
gl_program   rd 1
logical_w = 128
logical_h = 128
screen       rb logical_w * logical_h * 4
clear_r      dd 0.3
clear_g      dd 0.1
clear_b      dd 0.2
clear_a      dd 1.0
verts        dd 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0, 1.0
verts_len    dd 12

include 'generation/generated_data.asm'
vert_src_ptr dq vert_src
frag_src_ptr dq frag_src
