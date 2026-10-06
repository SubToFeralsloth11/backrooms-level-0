shader_type canvas_item;
// Subtle consumer-camera look: sensor grain, lens chromatic fringe, vignette,
// faint highlight bloom bleed. Kept restrained; realism comes from the lighting.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.045;
uniform float aberration = 0.0018;
uniform float vignette = 0.42;
uniform float fear = 0.0; // 0..1 pushed by nearby entities: more grain + fringe
uniform float fade = 0.0; // 0..1 to black
uniform vec3 fade_color = vec3(0.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	float ab = aberration * (1.0 + fear * 3.0) * r2 * 4.0;
	vec3 col;
	col.r = texture(screen_tex, uv + c * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - c * ab).b;
	// luminance-dependent sensor noise (shadows noisier, like real footage)
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float n = hash(uv * vec2(1920.0, 1080.0) + fract(TIME * 61.7) * 100.0) - 0.5;
	float g = grain * (1.0 + fear * 2.0) * mix(1.6, 0.5, clamp(lum * 2.0, 0.0, 1.0));
	col += n * g;
	col *= 1.0 - vignette * smoothstep(0.1, 0.75, r2 * 2.2);
	col = mix(col, fade_color, fade);
	COLOR = vec4(col, 1.0);
}
