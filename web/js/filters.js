// The lens catalogue.
//
// Each lens is a fragment-shader body: one function `vec3 snappy(vec2 uv)` that
// gets the prelude below prepended. Keeping them as data rather than files means
// the whole catalogue is one network request and the carousel can compile a
// shader the first time you swipe onto it.
//
// Chip glyphs are monochrome geometric shapes for the shader lenses and emoji
// for the face lenses, so the two kinds read as different things in the
// carousel. The label under each chip carries the meaning either way.
//
// Lenses with `faces: true` need landmarks and are hidden when the face tracker
// is unavailable. `overlay` names vector art drawn on top in 2D (see overlays.js);
// those lenses can still carry a shader of their own.

export const PRELUDE = `
precision highp float;
varying vec2 v_uv;
uniform sampler2D u_tex;
uniform vec2 u_res;
uniform float u_time;
uniform float u_aspect;
uniform float u_hasFace;
uniform vec2 u_eyeL;
uniform vec2 u_eyeR;
uniform vec2 u_faceC;
uniform float u_faceR;

vec3 tex(vec2 uv) { return texture2D(u_tex, clamp(uv, 0.0, 1.0)).rgb; }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec2 toAspect(vec2 d) { return vec2(d.x * u_aspect, d.y); }
float distA(vec2 a, vec2 b) { return length(toAspect(a - b)); }

vec2 hash2(vec2 p) {
  return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Pull pixels toward a point (scale < 1 magnifies, > 1 shrinks).
vec2 warp(vec2 uv, vec2 centre, float radius, float strength) {
  vec2 d = toAspect(uv - centre);
  float dist = length(d);
  if (dist >= radius || radius <= 0.0) return uv;
  float t = smoothstep(0.0, 1.0, dist / radius);
  d *= mix(strength, 1.0, t);
  return centre + vec2(d.x / u_aspect, d.y);
}

float sobel(vec2 uv) {
  vec2 px = 1.0 / u_res;
  float tl = luma(tex(uv + px * vec2(-1.0, -1.0)));
  float tc = luma(tex(uv + px * vec2( 0.0, -1.0)));
  float tr = luma(tex(uv + px * vec2( 1.0, -1.0)));
  float ml = luma(tex(uv + px * vec2(-1.0,  0.0)));
  float mr = luma(tex(uv + px * vec2( 1.0,  0.0)));
  float bl = luma(tex(uv + px * vec2(-1.0,  1.0)));
  float bc = luma(tex(uv + px * vec2( 0.0,  1.0)));
  float br = luma(tex(uv + px * vec2( 1.0,  1.0)));
  float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
  float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
  return length(vec2(gx, gy));
}
`;

export const FILTERS = [
  {
    id: 'none',
    name: 'None',
    glyph: '○',
    body: `vec3 snappy(vec2 uv) { return tex(uv); }`
  },
  {
    id: 'noir',
    name: 'Noir',
    glyph: '◐',
    body: `vec3 snappy(vec2 uv) {
      float l = luma(tex(uv));
      l = clamp((l - 0.5) * 1.45 + 0.46, 0.0, 1.0);
      return vec3(l);
    }`
  },
  {
    id: 'sepia',
    name: 'Sepia',
    glyph: '◑',
    body: `vec3 snappy(vec2 uv) {
      vec3 c = tex(uv);
      float l = luma(c);
      return mix(vec3(l), vec3(l * 1.07 + 0.09, l * 0.95 + 0.04, l * 0.72), 0.85);
    }`
  },
  {
    id: 'instant',
    name: 'Instant',
    glyph: '▣',
    body: `vec3 snappy(vec2 uv) {
      vec3 c = tex(uv);
      c = pow(c, vec3(0.88, 0.92, 1.04));
      c = mix(c, vec3(0.42, 0.40, 0.46), 0.14);
      return clamp(c * 1.06, 0.0, 1.0);
    }`
  },
  {
    id: 'process',
    name: 'Process',
    glyph: '◍',
    body: `vec3 snappy(vec2 uv) {
      vec3 c = tex(uv);
      return clamp(vec3(
        c.r * 1.25 - 0.08 + c.b * 0.10,
        c.g * 1.08 - 0.02,
        c.b * 0.88 + c.r * 0.14
      ), 0.0, 1.0);
    }`
  },
  {
    id: 'thermal',
    name: 'Thermal',
    glyph: '▲',
    body: `vec3 snappy(vec2 uv) {
      float l = luma(tex(uv));
      vec3 cold = vec3(0.0, 0.0, 0.35);
      vec3 mid  = vec3(0.75, 0.0, 0.55);
      vec3 hot  = vec3(1.0, 0.72, 0.0);
      vec3 peak = vec3(1.0, 1.0, 0.85);
      vec3 c = mix(cold, mid, smoothstep(0.0, 0.38, l));
      c = mix(c, hot, smoothstep(0.35, 0.72, l));
      c = mix(c, peak, smoothstep(0.72, 1.0, l));
      return c;
    }`
  },
  {
    id: 'xray',
    name: 'X-Ray',
    glyph: '◆',
    body: `vec3 snappy(vec2 uv) {
      float l = 1.0 - luma(tex(uv));
      l = clamp((l - 0.42) * 1.6 + 0.5, 0.0, 1.0);
      return vec3(l * 0.86, l * 0.95, l);
    }`
  },
  {
    id: 'comic',
    name: 'Comic',
    glyph: '▨',
    body: `vec3 snappy(vec2 uv) {
      vec3 c = tex(uv);
      vec3 flat3 = floor(c * 5.0) / 5.0;
      float e = 1.0 - smoothstep(0.35, 0.95, sobel(uv));
      return flat3 * e;
    }`
  },
  {
    id: 'edges',
    name: 'Edges',
    glyph: '▧',
    body: `vec3 snappy(vec2 uv) {
      float e = clamp(sobel(uv) * 1.3, 0.0, 1.0);
      return vec3(e);
    }`
  },
  {
    id: 'posterize',
    name: 'Poster',
    glyph: '▤',
    body: `vec3 snappy(vec2 uv) { return floor(tex(uv) * 4.0 + 0.5) / 4.0; }`
  },
  {
    id: 'pixellate',
    name: 'Pixel',
    glyph: '▦',
    body: `vec3 snappy(vec2 uv) {
      float n = 46.0;
      vec2 cell = vec2(n, n / u_aspect);
      return tex((floor(uv * cell) + 0.5) / cell);
    }`
  },
  {
    id: 'hex',
    name: 'Hex',
    glyph: '⬡',
    body: `vec3 snappy(vec2 uv) {
      float s = 0.034;
      vec2 p = vec2(uv.x * u_aspect, uv.y) / s;
      vec2 a = vec2(1.0, 1.7320508);
      vec2 h = a * 0.5;
      vec2 a1 = mod(p, a) - h;
      vec2 a2 = mod(p - h, a) - h;
      vec2 g = dot(a1, a1) < dot(a2, a2) ? p - a1 : p - a2;
      vec2 c = g * s;
      return tex(vec2(c.x / u_aspect, c.y));
    }`
  },
  {
    id: 'crystal',
    name: 'Crystal',
    glyph: '◈',
    body: `vec3 snappy(vec2 uv) {
      float s = 28.0;
      vec2 p = vec2(uv.x * u_aspect, uv.y) * s;
      vec2 base = floor(p);
      vec2 best = base;
      float bestD = 9.0;
      for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
          vec2 cell = base + vec2(float(x), float(y));
          vec2 site = cell + hash2(cell);
          float d = distance(p, site);
          if (d < bestD) { bestD = d; best = site; }
        }
      }
      vec2 c = best / s;
      return tex(vec2(c.x / u_aspect, c.y));
    }`
  },
  {
    id: 'halftone',
    name: 'Dots',
    glyph: '▩',
    body: `vec3 snappy(vec2 uv) {
      float s = 150.0;
      vec2 p = vec2(uv.x * u_aspect, uv.y) * s;
      vec2 cell = floor(p) + 0.5;
      vec2 c = cell / s;
      float l = luma(tex(vec2(c.x / u_aspect, c.y)));
      float r = sqrt(1.0 - l) * 0.72;
      float d = distance(p, cell);
      return vec3(smoothstep(r - 0.12, r + 0.12, d));
    }`
  },
  {
    id: 'bloom',
    name: 'Bloom',
    glyph: '◉',
    body: `vec3 snappy(vec2 uv) {
      vec3 c = tex(uv);
      vec3 glow = vec3(0.0);
      vec2 px = 2.6 / u_res;
      for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
          vec3 s = tex(uv + px * vec2(float(x), float(y)));
          glow += max(s - 0.62, 0.0);
        }
      }
      return clamp(c + glow * 0.13, 0.0, 1.0);
    }`
  },
  {
    id: 'vignette',
    name: 'Vignette',
    glyph: '◌',
    body: `vec3 snappy(vec2 uv) {
      float d = distA(uv, vec2(0.5));
      return tex(uv) * smoothstep(0.78, 0.26, d);
    }`
  },
  {
    id: 'kaleido',
    name: 'Kaleido',
    glyph: '◇',
    body: `vec3 snappy(vec2 uv) {
      vec2 d = toAspect(uv - 0.5);
      float a = atan(d.y, d.x);
      float r = length(d);
      float seg = 3.14159265 / 3.0;
      a = abs(mod(a + seg * 0.5, seg) - seg * 0.5);
      vec2 p = vec2(cos(a), sin(a)) * r;
      return tex(vec2(p.x / u_aspect, p.y) + 0.5);
    }`
  },
  {
    id: 'twirl',
    name: 'Twirl',
    glyph: '◓',
    body: `vec3 snappy(vec2 uv) {
      vec2 d = toAspect(uv - 0.5);
      float r = length(d);
      float a = atan(d.y, d.x) + (0.42 - min(r, 0.42)) * 6.0;
      vec2 p = vec2(cos(a), sin(a)) * r;
      return tex(vec2(p.x / u_aspect, p.y) + 0.5);
    }`
  },
  {
    id: 'bulge',
    name: 'Bulge',
    glyph: '●',
    body: `vec3 snappy(vec2 uv) { return tex(warp(uv, vec2(0.5), 0.42, 0.42)); }`
  },
  {
    id: 'pinch',
    name: 'Pinch',
    glyph: '◎',
    body: `vec3 snappy(vec2 uv) { return tex(warp(uv, vec2(0.5), 0.46, 1.9)); }`
  },
  {
    id: 'glitch',
    name: 'Glitch',
    glyph: '▚',
    body: `vec3 snappy(vec2 uv) {
      float band = floor(uv.y * 26.0);
      float jump = (hash2(vec2(band, floor(u_time * 7.0))).x - 0.5);
      jump *= step(0.82, hash2(vec2(band, floor(u_time * 7.0) + 11.0)).y) * 0.09;
      vec2 p = vec2(uv.x + jump, uv.y);
      float shift = 0.006 + jump * 0.4;
      vec3 c = vec3(tex(p + vec2(shift, 0.0)).r, tex(p).g, tex(p - vec2(shift, 0.0)).b);
      c *= 0.86 + 0.14 * step(0.5, fract(uv.y * u_res.y * 0.25));
      return c;
    }`
  },
  {
    id: 'duotone',
    name: 'Duotone',
    glyph: '◒',
    body: `vec3 snappy(vec2 uv) {
      float l = luma(tex(uv));
      return mix(vec3(0.09, 0.05, 0.32), vec3(1.0, 0.78, 0.26), smoothstep(0.05, 0.95, l));
    }`
  },
  {
    id: 'chrome',
    name: 'Chrome',
    glyph: '◧',
    body: `vec3 snappy(vec2 uv) {
      float l = luma(tex(uv));
      vec3 a = vec3(0.05, 0.02, 0.22);
      vec3 b = vec3(0.92, 0.21, 0.56);
      vec3 c = vec3(0.19, 0.86, 0.90);
      vec3 col = mix(a, b, smoothstep(0.0, 0.55, l));
      return mix(col, c, smoothstep(0.55, 1.0, l));
    }`
  },

  // ----------------------------------------------------- face lenses --
  {
    id: 'bigeyes',
    name: 'Big Eyes',
    glyph: '👀',
    faces: true,
    body: `vec3 snappy(vec2 uv) {
      if (u_hasFace < 0.5) return tex(uv);
      float r = u_faceR * 0.30;
      vec2 p = warp(uv, u_eyeL, r, 0.45);
      p = warp(p, u_eyeR, r, 0.45);
      return tex(p);
    }`
  },
  {
    id: 'alien',
    name: 'Alien',
    glyph: '👽',
    faces: true,
    body: `vec3 snappy(vec2 uv) {
      vec2 p = uv;
      if (u_hasFace > 0.5) {
        float r = u_faceR * 0.34;
        p = warp(p, u_eyeL, r, 0.3);
        p = warp(p, u_eyeR, r, 0.3);
      }
      vec3 c = tex(p);
      return clamp(vec3(
        c.r * 0.5 + c.g * 0.2,
        c.r * 0.15 + c.g * 1.0 + c.b * 0.25,
        c.g * 0.25 + c.b * 0.55
      ), 0.0, 1.0);
    }`
  },
  {
    id: 'squish',
    name: 'Squish',
    glyph: '🫠',
    faces: true,
    body: `vec3 snappy(vec2 uv) {
      if (u_hasFace < 0.5) return tex(uv);
      return tex(warp(uv, u_faceC, u_faceR * 1.1, 1.7));
    }`
  },
  { id: 'shades', name: 'Shades', glyph: '🕶', faces: true, overlay: 'shades',
    body: `vec3 snappy(vec2 uv) { return tex(uv); }` },
  { id: 'puppy', name: 'Puppy', glyph: '🐶', faces: true, overlay: 'puppy',
    body: `vec3 snappy(vec2 uv) { return tex(uv); }` },
  { id: 'crown', name: 'Royalty', glyph: '👑', faces: true, overlay: 'crown',
    body: `vec3 snappy(vec2 uv) { return tex(uv); }` },
  { id: 'hearts', name: 'Smitten', glyph: '😍', faces: true, overlay: 'hearts',
    body: `vec3 snappy(vec2 uv) { return tex(uv); }` }
];

export const FACE_LENS_IDS = FILTERS.filter((f) => f.faces).map((f) => f.id);
