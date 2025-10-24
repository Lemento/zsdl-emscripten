
layout (location = 0) in vec3 vPos;
layout (location = 1) in vec2 vTexCoord;
out vec2 texCoord;
uniform mat4 u_MVP;

void main(){ gl_Position = vec4(vPos, 1.0) * u_MVP; texCoord = vTexCoord; }