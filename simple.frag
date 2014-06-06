#version 130

uniform sampler2D fullscreenTex;
in vec2 uv_out;
out vec4 colour_output;


void main()
{
      colour_output = texture(fullscreenTex, uv_out);
}
