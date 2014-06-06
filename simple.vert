#version 130

in vec2 position;
in vec2 uv;
out vec2 uv_out;

void main()
{
    uv_out 		= uv;
    gl_Position = vec4(position, 0.0, 1.0);
}
