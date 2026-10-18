shader_type spatial;
// 全息投影材质：加色混合 + 菲涅尔边缘发光 + 水平扫描线 + 轻微时间抖动。
// 所有物品模型都是程序化生成的图元，靠这个 shader 统一成「全息」质感。
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

uniform vec4 base_color : source_color = vec4(0.31, 0.76, 0.97, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.0;      // 整体亮度
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.2;  // 边缘发光锐度
uniform float scan_density : hint_range(1.0, 120.0) = 34.0;
uniform float scan_speed : hint_range(0.0, 8.0) = 1.6;
uniform float scan_strength : hint_range(0.0, 2.0) = 0.5;
uniform float flicker : hint_range(0.0, 1.0) = 0.06;       // 全息抖动强度
uniform float wire_amount : hint_range(0.0, 1.0) = 0.0;    // 线框化程度（0=实体 1=纯线框）
uniform float time_offset = 0.0;

void fragment() {
	// 菲涅尔：正对镜头处最淡，边缘最亮
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);

	// 水平扫描线
	float scan = 0.5 + 0.5 * sin(VERTEX.y * scan_density - (TIME + time_offset) * scan_speed * 6.2831);
	scan = smoothstep(0.55, 1.0, scan);

	// 全息抖闪
	float fl = 1.0 - flicker * fract(sin((TIME + time_offset) * 43.7) * 913.7);

	vec3 body = base_color.rgb * (0.18 + 0.55 * f);
	vec3 glow = base_color.rgb * scan * scan_strength * 1.6;
	vec3 col = (body + glow) * intensity * fl;

	// 线框：用 UV 生成网格线，叠加到底色上
	if (wire_amount > 0.001) {
		vec2 g = abs(fract(UV * 12.0) - 0.5) / max(fwidth(UV * 12.0), vec2(0.0001));
		float line = 1.0 - min(min(g.x, g.y), 1.0);
		col += base_color.rgb * line * wire_amount * 1.4;
	}

	ALBEDO = col;
	ALPHA = clamp(0.22 + 0.78 * f, 0.0, 1.0);
}
