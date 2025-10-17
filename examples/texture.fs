
precision mediump float;
layout (location = 0) out vec4 fragColor;
in vec2 texCoord;

uniform sampler2D diffuse;

void main(){ fragColor = texture(diffuse, texCoord); }