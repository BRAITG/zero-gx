shader_type canvas_item;
// A gravity field as thin rings that fall from `reach` to the surface, faster the closer they get.

uniform float radius = 64.0;
uniform float reach = 450.0;
uniform float surface_pull = 3200.0;
uniform float reference_pull = 4000.0;
uniform float max_alpha = 0.35;
uniform float period = 3.0;  // seconds for one ring to fall the whole way
uniform float rings = 6.0;
uniform float line_px = 2.0;  // screen pixels, whatever the zoom
uniform vec4 tint : source_color = vec4(0.62, 0.72, 0.9, 1.0);

void fragment() {
	float d = length((UV - 0.5) * 2.0 * reach);
	// Inverse of d = reach - (reach - radius) * u * u, with u the ring's progress.
	float u = sqrt(clamp((reach - d) / (reach - radius), 0.0, 1.0));
	float w = rings * (u - TIME / period);
	float x = abs(fract(w + 0.5) - 0.5);  // distance to the nearest ring, in rings
	float px = max(fwidth(w), 1e-5);
	float line = 1.0 - smoothstep(0.0, 1.0, x / px - 0.5 * line_px);
	float fade = smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u));
	float pull = surface_pull * pow(radius / max(d, radius), 2.0);
	float profile = max_alpha * sqrt(min(pull / reference_pull, 1.0));
	float inside = step(d, reach) * step(radius, d);
	COLOR = vec4(tint.rgb, line * fade * profile * inside);
}
