#version 330 core
  
in vec4 vert_color;
in vec2 vert_uv;
out vec4 frag_color;

uniform sampler2D tex;

void main()
{
	vec2 uv = (vert_uv + 1.0) / 2.0;
    frag_color = texture(tex, uv);
}
