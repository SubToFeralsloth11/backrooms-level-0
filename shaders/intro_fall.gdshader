shader_type canvas_item;
// Intro post pass: concussed blur, double vision, vignette, eyelids, black fade.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 0.0;
uniform float double_vision = 0.0;
uniform float vignette = 0.6;
uniform float lid = 0.0;   // 0 open, 1 shut
uniform float black = 1.0; // fade to black
uniform float flash = 0.0; // impact white-out

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, blur).rgb;
	if (double_vision > 0.0) {
		vec3 g = textureLod(screen_tex, uv + vec2(double_vision, double_vision * 0.3), blur + 0.5).rgb;
		c = mix(c, g, 0.45);
	}
	float v = smoothstep(0.3, 0.95, length((uv - 0.5) * vec2(1.25, 1.0)) * 1.25);
	c *= 1.0 - v * vignette;
	// eyelids close from top and bottom with a soft curved edge
	float edge = abs(uv.y - 0.5) * 2.0 + pow(abs(uv.x - 0.5) * 1.6, 2.0) * 0.35;
	float open = 1.3 - lid * 1.5;
	c *= smoothstep(open, open - 0.18, edge);
	c = mix(c, vec3(1.0, 0.97, 0.9), flash);
	COLOR = vec4(c * (1.0 - black), 1.0);
}
