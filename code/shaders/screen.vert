#version 330 core
layout (location = 0) in vec2 vert; 
  
out vec4 vert_color; 
out vec2 vert_uv;

void main()
{
    gl_Position = vec4(vert, 0.0, 1.0); 
    vert_color = vec4(0.5, 0.0, 1.0, 1.0); 
    vert_uv = vert;
}
