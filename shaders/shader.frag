#version 450

layout(binding = 1) uniform sampler2D texSampler;

layout(push_constant) uniform PushConstants {
	uint msaaEnabled;
} pc;

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main()
{
	vec3 color = texture(texSampler, fragTexCoord).rgb;

	if (pc.msaaEnabled == 1) {
		// Correct Gamma if MSAA enabled AND we're on AMD GPU
		color = pow(color, vec3(1.0/2.2));
	}

	outColor = vec4(color, 1.0);
}