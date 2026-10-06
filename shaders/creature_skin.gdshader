shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, sss_mode_skin;
// Dead-flesh skin for sculpted creatures. Texturing uses the rest-pose
// position (UV.xy, UV2.x) so detail stays glued to the body while skinned.
// UV2.y = material region: 0 skin, 1 gums/mouth, 2 wet empty socket,
// 3 nail/claw, 4 teeth.

uniform vec3 base_color : source_color = vec3(0.55, 0.5, 0.47);
uniform vec3 bruise_color : source_color = vec3(0.3, 0.2, 0.22);
uniform vec3 vein_color : source_color = vec3(0.22, 0.24, 0.32);
uniform vec3 rot_color : source_color = vec3(0.26, 0.22, 0.13);
uniform float scale = 9.0;
uniform float vein_amount = 0.7;
uniform float bruise_amount = 0.55;
uniform float rot_amount = 0.3;
uniform float wetness = 0.55;
uniform float bump = 0.9;
uniform float sss = 0.35;
uniform float seed = 0.0;

varying vec3 rp;
varying float region;

// Precomputed seamless fractal noise (Creature builds these once):
// noise_lo: broad fbm; noise_hi: fine detail. Sampling replaces ~40 procedural
// noise evaluations per pixel with a handful of texture reads.
uniform sampler3D noise_lo : filter_linear_mipmap, repeat_enable;
uniform sampler3D noise_hi : filter_linear_mipmap, repeat_enable;

float fbm(vec3 p) {
	return texture(noise_lo, p * 0.11 + seed * 0.13).r;
}

float vnoise(vec3 p) {
	return texture(noise_hi, p * 0.05 + seed * 0.07).r;
}

float veins(vec3 p) {
	float n = fbm(p * 1.3);
	return pow(1.0 - abs(n - 0.5) * 2.0, 16.0);
}

void vertex() {
	rp = vec3(UV.x, UV.y, UV2.x) * scale;
	region = UV2.y;
	// faint shallow breathing swell
	VERTEX += NORMAL * sin(TIME * 1.3 + UV.y * 3.0) * 0.0015;
}

void fragment() {
	vec3 p = rp;
	float mott = fbm(p * 0.6);
	float bruise = smoothstep(0.55, 0.8, fbm(p * 0.35 + 4.0)) * bruise_amount;
	float rotm = smoothstep(0.6, 0.85, fbm(p * 0.5 + 11.0)) * rot_amount;
	float v = veins(p) * vein_amount;
	float pores = vnoise(p * 26.0);
	float wrinkle = fbm(vec3(p.x * 6.0, p.y * 1.5, p.z * 6.0));
	vec3 col = base_color * (0.5 + mott * 1.0);
	// ground-in filth: brown-grey patches, heavier toward the feet and hands
	float dirt = smoothstep(0.45, 0.75, fbm(p * 0.9 + 21.0)) * 0.7 + clamp(0.9 - UV.y, 0.0, 1.0) * 0.35;
	col = mix(col, vec3(0.13, 0.1, 0.07), clamp(dirt, 0.0, 0.8));
	col = mix(col, bruise_color, bruise);
	col = mix(col, rot_color, rotm);
	col = mix(col, vein_color, v * 0.85);
	// Wet/specular variation: broad wet patches broken up by fine slick
	// streaks, so the skin glints in places instead of reading as grey clay.
	float wet_patch = fbm(p * 0.8 + 7.0);
	float slick = smoothstep(0.35, 0.75, vnoise(p * 4.0 + 3.0));
	float wet = clamp(wetness * (0.3 + wet_patch * 0.9 + slick * 0.5) - rotm, 0.0, 1.0);
	float rough = mix(0.8, 0.25, wet);
	float spec = mix(0.35, 0.7, wet);
	// blood under thin skin: warm the albedo where it's wet and un-bruised
	col = mix(col, col * vec3(1.12, 0.9, 0.86), wet * (1.0 - bruise) * 0.5);
	float h = pores * 0.3 + v * 0.8 + wrinkle * 0.5;
	float bump_k = bump;
	float sss_k = sss;
	int r = int(round(region));
	if (r == 1) {        // gums / mouth flesh
		col = vec3(0.22, 0.03, 0.03) * (0.6 + mott * 0.6);
		rough = 0.15; spec = 0.7; sss_k = 0.8;
	} else if (r == 2) { // empty wet socket
		col = vec3(0.02, 0.008, 0.008);
		rough = 0.08; spec = 0.8; bump_k = 0.2;
	} else if (r == 3) { // claws: thick, cracked, yellow-grey
		col = vec3(0.3, 0.27, 0.19) * (0.7 + mott * 0.5);
		rough = 0.35; spec = 0.5; sss_k = 0.1;
		h = fbm(vec3(p.x * 20.0, p.y * 3.0, p.z * 20.0));
	} else if (r == 4) { // teeth: stained enamel
		col = mix(vec3(0.62, 0.57, 0.43), vec3(0.32, 0.25, 0.14), smoothstep(0.4, 0.8, fbm(p * 3.0)));
		rough = 0.28; spec = 0.6; sss_k = 0.3; bump_k = 0.3;
	}
	ALBEDO = col;
	// bump from procedural height via screen-space derivatives
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump_k * 0.012);
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (r == 0) {
		CLEARCOAT = wet * 0.5;
		CLEARCOAT_ROUGHNESS = 0.2;
	}
	SSS_STRENGTH = sss_k;
	SSS_TRANSMITTANCE_COLOR = vec4(0.85, 0.22, 0.14, 1.0);
	SSS_TRANSMITTANCE_DEPTH = 0.08;
	SSS_TRANSMITTANCE_BOOST = 0.15 * sss_k;
	// reddish light bleeding through thin flesh when backlit
	BACKLIGHT = vec3(0.6, 0.16, 0.1) * (0.25 + 0.5 * sss_k) * (0.4 + mott * 0.6);
}
