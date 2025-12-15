shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D texture_albedo : source_color;
uniform vec4 coat_color : source_color = vec4(0.8, 0.9, 1.0, 1.0); // target coat colour
uniform float coat_tint_strength : hint_range(0.0, 1.0) = 1.0;
uniform float coat_threshold : hint_range(0.0, 1.0) = 0.75; // how bright to count as "coat"
uniform float coat_softness : hint_range(0.0, 0.5) = 0.15;  // smooth edge of mask

void fragment() {
    vec4 tex = texture(texture_albedo, UV);
    vec3 base = tex.rgb;

    // Luminance (brightness)
    float lum = dot(base, vec3(0.299, 0.587, 0.114));

    // Saturation (difference between max and min channel)
    float cmax = max(base.r, max(base.g, base.b));
    float cmin = min(base.r, min(base.g, base.b));
    float sat = cmax - cmin;

    // Bright, low-saturation areas -> likely the lab coat
    float bright_mask = smoothstep(coat_threshold, coat_threshold - coat_softness, lum);
    float desat_mask = 1.0 - clamp(sat * 4.0, 0.0, 1.0); // boost effect of saturation

    float coat_mask = clamp(bright_mask * desat_mask, 0.0, 1.0);

    // Keep original shading by scaling tint with luminance
    vec3 coat_tinted = coat_color.rgb * lum;

    // Blend: original -> tinted where coat_mask is 1
    vec3 tinted = mix(base, mix(base, coat_tinted, coat_tint_strength), coat_mask);

    ALBEDO = tinted;
    ALPHA = tex.a;
}
