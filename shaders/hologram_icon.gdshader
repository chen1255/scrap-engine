shader_type spatial;
// 图标专用材质：正常混合 + 实心不透明 + 不依赖场景灯光的假光照。
// 与 hologram.gdshader 的区别：那个用于大尺寸实时全息检视（加色、半透明、扫描线），
// 这个用于把模型烘焙成小尺寸图标——必须实心、轮廓清晰、有体积感，否则缩到 48px 就糊了。
render_mode blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec4 base_color : source_color = vec4(0.31, 0.76, 0.97, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float edge_power : hint_range(0.5, 6.0) = 1.5;   // 边缘光锐度
uniform float edge_gain : hint_range(0.0, 3.0) = 1.15;   // 边缘光强度
uniform float fill : hint_range(0.0, 1.0) = 0.45;        // 暗部填充，避免死黑
uniform float alpha_base : hint_range(0.0, 1.0) = 1.0;   // 基础不透明度

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);

	// 左上前方的主光（视图空间，烘焙时相机固定，所以方向稳定）
	float diff = clamp(dot(n, normalize(vec3(-0.45, 0.72, 0.52))), 0.0, 1.0);
	float lam = fill + (1.0 - fill) * diff;

	// 菲涅尔边缘光，让轮廓在深色背景上也能立住
	float f = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), edge_power);

	// 顶部补一点高光，增强体积感
	float top = pow(clamp(n.y, 0.0, 1.0), 3.0);

	vec3 col = base_color.rgb * lam;
	col += base_color.rgb * f * edge_gain;
	col += vec3(1.0) * top * 0.10;
	col *= intensity;

	ALBEDO = col;
	ALPHA = alpha_base;
}
