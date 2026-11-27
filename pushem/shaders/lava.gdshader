// Animated swirling lava background for Godot 4 (2D / CanvasItem)
// Attach to a ColorRect, Sprite2D or TextureRect via a ShaderMaterial.
shader_type canvas_item;

// --- Look & motion ---
uniform float tile_size = 600.0;                 // pixels per noise "cell" (bigger = larger swirls)
uniform float flow_speed = 0.04;                 // overall flow speed
uniform vec2 flow_direction = vec2(1.0, 0.35);   // main drift direction
uniform float swirl_strength = 2.2;              // how twisty the flow is
uniform float vein_density = 9.0;                // number of bright vein bands
uniform float vein_sharpness = 10.0;             // thinner veins = higher value
uniform float crust_amount = 0.45;               // dark cooled patches (0 = none)
uniform float glow_boost = 0.6;                  // >0 pushes veins above 1.0 for HDR glow
uniform float pulse_amount = 0.08;               // gentle brightness breathing

// --- Colors ---
uniform vec4 color_crust : source_color = vec4(0.22, 0.02, 0.0, 1.0);
uniform vec4 color_dark : source_color = vec4(0.55, 0.06, 0.0, 1.0);
uniform vec4 color_mid : source_color = vec4(0.92, 0.25, 0.02, 1.0);
uniform vec4 color_bright : source_color = vec4(1.0, 0.55, 0.06, 1.0);
uniform vec4 color_hot : source_color = vec4(1.0, 0.93, 0.5, 1.0);

// Noise detail: 5 = full, fewer is cheaper (set from the Graphics option).
uniform int octaves = 5;
// Parallax: the game slides the pattern (px) as the camera follows the action.
uniform vec2 scroll = vec2(0.0);

varying vec2 local_pos;

void vertex() {
	// Local pixel position: keeps the pattern square regardless of rect size
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
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
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
	float t = TIME * flow_speed;
	vec2 dir = normalize(flow_direction);

	// Domain warping -> swirly, marbled flow
	vec2 q = vec2(
		fbm(p + dir * t * 3.0),
		fbm(p + vec2(5.2, 1.3) - dir * t * 2.0)
	);
	vec2 r = vec2(
		fbm(p + swirl_strength * q + vec2(1.7, 9.2) + t * 1.5),
		fbm(p + swirl_strength * q + vec2(8.3, 2.8) - t * 1.2)
	);
	float f = fbm(p + swirl_strength * r);

	// Base molten color
	vec3 col = mix(color_dark.rgb, color_mid.rgb, smoothstep(0.25, 0.6, f));
	col = mix(col, color_bright.rgb, smoothstep(0.55, 0.95, length(r)) * 0.8);

	// Thin bright veins following the swirl contours
	float bands = abs(sin(f * vein_density + t * 4.0));
	float vein = pow(1.0 - bands, vein_sharpness);
	vein *= smoothstep(0.3, 0.55, f); // fewer veins in the darkest areas
	col = mix(col, color_hot.rgb, vein);

	// Dark cooled crust patches drifting slowly
	float crust = smoothstep(0.52, 0.72, fbm(p * 0.6 + vec2(20.0) - dir * t));
	col = mix(col, color_crust.rgb, crust * crust_amount * (1.0 - vein));

	// Subtle heat pulse + HDR boost on the veins
	col *= 1.0 + sin(TIME * 1.3 + f * 6.0) * pulse_amount;
	col += color_hot.rgb * vein * glow_boost;

	COLOR = vec4(col, 1.0);
}
