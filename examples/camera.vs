
layout (location = 0) in vec3 aPos;

out vec3 color;
uniform mat4 u_MVP;

void main(){ gl_Position = vec4(aPos, 1.0) * u_MVP; }