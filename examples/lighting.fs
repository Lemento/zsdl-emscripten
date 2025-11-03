precision mediump float;

in vec3 FragPos;
in vec3 Normal;

out vec4 FragColor;
vec3 objectColor = vec3(1.0, 0.5, 0.2);
vec3 lightColor = vec3(1.0, 1.0, 1.0);

vec3 lightPos = vec3(1.2, 1.0, 2.0);

void main()
{
    float ambientStrength = 0.1f;
    vec3 ambient = ambientStrength * lightColor;

    vec3 norm = normalize(Normal);
    vec3 lightDir = normalize(lightPos - FragPos);

    float diff = max(dot(norm, lightDir), 0.0);
    vec3 diffuse = diff * lightColor;

    vec3 result = (ambient + diffuse) * objectColor;
    FragColor = vec4(result, 1.0f);
}