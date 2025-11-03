precision mediump float;

layout (location = 0) in vec3 vPos;
layout (location = 1) in vec3 vNormal;

out vec3 FragPos;
out vec3 Normal;

uniform mat4 u_Model;
uniform mat4 u_MVP;

void main()
{
    gl_Position = vec4(vPos, 1.0) * u_MVP;
    FragPos = vec3(u_Model * vec4(vPos, 1.0));
    Normal = vNormal;
}
