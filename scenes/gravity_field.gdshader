shader_type canvas_item;
// A gravity field as thin rings that fall from `reach` to the surface. Rings are evenly spaced in
// log(distance), so they crowd, slow and thicken where the pull is strong, and spread toward the edge.

uniform float radius = 64.0;
uniform float reach = 450.0;
uniform float surface_pull = 3200.0;
uniform float reference_pull = 4000.0;
uniform float max_alpha = 0.35;
uniform float period = 3.0;  // seconds for one ring to fall from the edge to the surface
uniform float phase = 0.0;  // 0-1, so neighbouring bodies do not ripple in sync
uniform float rings = 6.0;
uniform vec2 line_px = vec2(1.5, 3.0);  // screen pixels at the edge and at full pull
uniform vec4 tint : source_color = vec4(0.62, 0.72, 0.9, 1.0);

void fragment() {
	float d = length((UV - 0.5) * 2.0 * reach);
	float t = log(max(d, radius) / radius) / log(reach / radius);  // 0 at the surface, 1 at the edge
	float w = rings * (t + phase + TIME / period);  // rings sit at integer w, so they fall as time passes
	float x = abs(fract(w + 0.5) - 0.5);  // distance to the nearest ring, in rings
	float px = max(fwidth(w), 1e-5);
	float pull = surface_pull * pow(radius / max(d, radius), 2.0);
	float strength = sqrt(min(pull / reference_pull, 1.0));
	float line = 1.0 - smoothstep(0.0, 1.0, x / px - 0.5 * mix(line_px.x, line_px.y, strength));
	float fade = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.9, 1.0, t));
	float inside = step(d, reach) * step(radius, d);
	COLOR = vec4(tint.rgb, line * fade * max_alpha * strength * inside);
}
