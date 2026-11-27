// Looking down from high cliffs into a windy sea of clouds
// Godot 4 (2D / CanvasItem). Attach to a ColorRect via a ShaderMaterial.
// Place your cliff-top islands (sprites / tiles) on top of this.
shader_type canvas_item;

// --- Look & motion ---
uniform float tile_size = 600.0;               // pixels per pattern cell
uniform vec2 wind_direction = vec2(1.0, 0.25); // direction clouds are blown
uniform float wind_speed = 0.5;                // how fast everything moves
uniform float cloud_cover = 0.55;              // 0 = open abyss, 1 = thick clouds
uniform float streak_amount = 0.5;             // visibility of wind lines
uniform float gust_strength = 0.5;             // how much the wind lines pulse

// --- Colors ---
uniform vec4 abyss_deep : source_color = vec4(0.09, 0.13, 0.21, 1.0);
uniform vec4 abyss_mid : source_color = vec4(0.23, 0.32, 0.45, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.55, 0.62, 0.73, 1.0);
uniform vec4 cloud_light : source_color = vec4(0.93, 0.95, 0.98, 1.0);
uniform vec4 streak_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Noise detail: 5 = full, fewer is cheaper (set from the Graphics option).
uniform int octaves = 5;
// Parallax: the game slides the pattern (px) as the camera follows the action.
uniform vec2 scroll = vec2(0.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX + scroll;
}

// Integer hash of the cell containing p. Exact at any coordinate: the
// original fract()-based float hash lost precision once the fbm octaves
// pushed coordinates into the thousands, which showed up as big blocky
// shards across the backdrop.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)));
	uint h = q.x * 1664525u + q.y * 1013904223u;
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < octaves; i++) {
		v += amp * noise(p);
		p = rot * p * 2.0 + vec2(100.0);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = local_pos / tile_size * 4.0;
	vec2 wind = normalize(wind_direction);
	float t = TIME * wind_speed;

	// Deep hazy abyss far below
	vec3 col = mix(abyss_deep.rgb, abyss_mid.rgb, smoothstep(0.3, 0.7, fbm(p * 0.7 - wind * t * 0.05)));

	// Far cloud layer: slow and dim (parallax depth)
	float far_c = fbm(p * 1.2 - wind * t * 0.12);
	col = mix(col, cloud_shadow.rgb * 0.8, smoothstep(0.45, 0.75, far_c) * 0.6);

	// Near cloud layer: faster, slightly warped, lit on top
	float warp = fbm(p * 2.0 - wind * t * 0.3);
	float near_c = fbm(p * 1.8 + warp * 0.8 - wind * t * 0.25);
	float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.25, near_c);
	float light = smoothstep(0.5, 0.9, near_c + (fbm(p * 4.0 - wind * t * 0.3) - 0.5) * 0.3);
	col = mix(col, mix(cloud_shadow.rgb, cloud_light.rgb, light), cover);

	// Wind streaks: noise stretched hard along the wind, pulsing in gusts
	float gust = 1.0 + gust_strength * sin(TIME * 0.7) * sin(TIME * 0.23 + 1.0);
	vec2 side = vec2(-wind.y, wind.x);
	vec2 sp = vec2(dot(p, wind) * 0.5 - t * 1.2, dot(p, side) * 8.0);
	float streak = smoothstep(0.62, 0.8, fbm(sp)) * streak_amount * gust;
	col = mix(col, streak_color.rgb, clamp(streak * 0.5, 0.0, 1.0));

	COLOR = vec4(col, 1.0);
}
