// Frozen lake with drifting snow, blowing powder and falling snowflakes
// Godot 4 (2D / CanvasItem). Attach to a ColorRect via a ShaderMaterial.
shader_type canvas_item;

// --- Look & motion ---
uniform float tile_size = 600.0;                // pixels per pattern cell
uniform vec2 wind_direction = vec2(1.0, 0.4);   // direction snow is blown
uniform float wind_speed = 0.6;                 // flake + powder speed
uniform float snow_cover = 0.45;                // 0 = clear ice, 1 = fully snowed over
uniform float crack_amount = 0.8;               // visibility of ice cracks
uniform float powder_amount = 0.35;             // blowing snow streaks over the ground
uniform float snowfall_density = 0.35;          // fraction of cells that hold a flake
uniform float flake_size = 0.12;                // flake radius relative to its cell
uniform float sparkle_amount = 0.7;             // glints on the snow

// --- Colors ---
uniform vec4 ice_deep : source_color = vec4(0.22, 0.42, 0.6, 1.0);
uniform vec4 ice_light : source_color = vec4(0.6, 0.8, 0.9, 1.0);
uniform vec4 crack_color : source_color = vec4(0.1, 0.22, 0.36, 1.0);
uniform vec4 snow_color : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform vec4 snow_shadow : source_color = vec4(0.7, 0.8, 0.92, 1.0);

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

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(57.0, 113.0)));
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

// Distance to the nearest Voronoi cell border (0 on the crack line)
float crack_edge(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			float d = length(g + hash2(n + g) - f);
			if (d < d1) { d2 = d1; d1 = d; }
			else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

// One layer of drifting flakes. Lower scale = bigger, closer, faster flakes.
float flakes(vec2 p, float scale, float speed, vec2 wind) {
	vec2 q = p * scale - wind * TIME * wind_speed * speed * 3.0;
	q += vec2(sin(q.y * 0.5 + TIME), cos(q.x * 0.5 + TIME * 1.3)) * 0.15;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec2 offset = (vec2(hash(id), hash(id + 17.0)) - 0.5) * 0.7;
	float d = length(f - offset);
	float present = step(1.0 - snowfall_density, hash(id + 3.1));
	return smoothstep(flake_size, flake_size * 0.3, d) * present;
}

void fragment() {
	vec2 p = local_pos / tile_size * 4.0;
	vec2 wind = normalize(wind_direction);

	// Ice base with subtle depth variation
	vec3 col = mix(ice_deep.rgb, ice_light.rgb, smoothstep(0.3, 0.7, fbm(p * 0.8)));
	col += (fbm(p * 6.0) - 0.5) * 0.06;

	// Big cracks plus finer hairline cracks in patches
	float crack = 1.0 - smoothstep(0.0, 0.06, crack_edge(p * 1.5));
	float fine = 1.0 - smoothstep(0.0, 0.03, crack_edge(p * 4.0 + 7.0));
	fine *= smoothstep(0.45, 0.6, fbm(p * 2.0));
	col = mix(col, crack_color.rgb, clamp(crack * 0.8 + fine * 0.5, 0.0, 1.0) * crack_amount);

	// Snow drifts that creep very slowly with the wind
	float s = fbm(p * 1.2 - wind * TIME * 0.005);
	float snow = smoothstep(1.0 - snow_cover - 0.08, 1.0 - snow_cover + 0.08, s);
	vec3 snow_col = mix(snow_shadow.rgb, snow_color.rgb, smoothstep(0.4, 0.8, fbm(p * 3.0)));
	col = mix(col, snow_col, snow);

	// Twinkling glints on the snow
	float sparkle = step(0.985, hash(floor(p * 40.0) + floor(TIME * 4.0)));
	col += sparkle * snow * sparkle_amount * 0.5;

	// Blowing powder: noise stretched along the wind direction
	vec2 side = vec2(-wind.y, wind.x);
	vec2 wp = vec2(dot(p, wind) * 0.6 - TIME * wind_speed * 2.0, dot(p, side) * 3.0);
	col = mix(col, snow_color.rgb, smoothstep(0.5, 0.85, fbm(wp)) * powder_amount);

	// Three parallax layers of falling snow
	float fl = flakes(p, 6.0, 1.0, wind)
			 + flakes(p, 10.0, 0.7, wind) * 0.7
			 + flakes(p, 16.0, 0.45, wind) * 0.45;
	col = mix(col, vec3(1.0), clamp(fl, 0.0, 1.0));

	COLOR = vec4(col, 1.0);
}
