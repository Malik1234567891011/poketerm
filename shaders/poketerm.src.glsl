// poketerm — a living Pokémon world inside the terminal (Ghostty custom shader)
//
//  * a pixel Pikachu follows your cursor: runs while you type, hops to new
//    lines leaving a lightning trail, idles, blinks, and falls asleep (Zzz)
//  * "living ink": text printed in a few magic colours becomes an animated
//    material on the GPU (electric, shiny holo, fire, ghost wobble)
//  * night sky with twinkling stars + shooting stars, swaying tall grass that
//    rustles when a wild Pokémon is hiding, battle-intro wipe on new windows
//
// Edit shaders/poketerm.src.glsl, then run `python3 tools/build.py`.

#define PX          3.0    // device pixels per sprite pixel
#define SLEEP_AFTER 30.0   // seconds without cursor movement before Pikachu naps
#define HOP_T       0.32   // seconds for a hop to a new line
#define GRASS_H     46.0   // device px of grass along the bottom edge
#define INTRO_T     1.05   // seconds of the battle-intro wipe on a new window
#define SHOW_STARS  1
#define SHOW_GRASS  1
#define SHOW_INTRO  1
#define SHOW_PIKA   1
#define SHOW_INK    1

// Magic ink colours (exact 24-bit values printed by the shell / Claude Code).
#define INK_ELEC  vec3(255.0, 209.0,   5.0) / 255.0
#define INK_SHINY vec3(240.0, 183.0, 253.0) / 255.0
#define INK_FIRE  vec3(255.0, 106.0,  19.0) / 255.0
#define INK_GHOST vec3(156.0, 124.0, 243.0) / 255.0

#define PI 3.14159265

//@PARTY

float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Ghostty on macOS (Metal) uses y-down pixel coordinates for fragCoord, the
// screen texture and the cursor rects. Everything below works in y-up pixels.
vec2 SHAKE = vec2(0.0);   // Snorlax's landing shakes the text
vec2 toTex(vec2 fc) { fc += SHAKE; return vec2(fc.x, iResolution.y - fc.y) / iResolution.xy; }
vec4 tex(vec2 fc) { return texture(iChannel0, toTex(fc)); }
// cursor rect -> (left, bottom, width, height) in y-up pixels
vec4 cursorUp(vec4 c) { return vec4(c.x, iResolution.y - c.y, c.z, c.w); }

// Is the screen texture linear or sRGB-encoded? It depends on the renderer and
// its settings, so look at the top-left padding pixel (always background).
bool G_LINEAR = false;

// What Claude Code is doing, sent by claude/state.zsh through palette slot 255:
// #eeeeee with blue nudged up 1-13 steps, which no one can see in text.
//   1-4  working (<20s, <1m, <3m, longer)   5  waiting for you   6-13  just finished
int PK_STATE = 0;
void readClaudeState() {
    vec3 c = iPalette[255] * 255.0;
    if (abs(c.r - 238.0) > 0.5 || abs(c.g - 238.0) > 0.5) return;
    int b = int(c.b + 0.5) - 238;
    if (b >= 1 && b <= 13) PK_STATE = b;
}

// ---------------------------------------------------------------- sprites
// p: sprite pixels relative to the species anchor (cell centre), y up
vec4 spriteFrame(int fr, int k, vec2 p) {
    vec2 q = p - vec2(float(FR_X0[fr]), float(FR_Y0[fr]));
    int w = FR_W[fr], h = FR_H[fr];
    if (q.x < 0.0 || q.y < 0.0 || q.x >= float(w) || q.y >= float(h)) return vec4(0.0);
    int x = int(q.x), y = h - 1 - int(q.y);
    uint word = SPR[FR_OFF[fr] + y * ((w + 7) >> 3) + (x >> 3)];
    int c = int((word >> uint((x & 7) * 4)) & 15u);
    if (c == 0) return vec4(0.0);
    return vec4(PAL[k * 16 + c], 1.0);
}

int pickFrame(int id, float at, bool loop) {
    int s = AN_START[id], n = AN_N[id];
    float L = AN_LEN[id];
    float x = loop ? mod(at, L) : clamp(at, 0.0, L - 0.001);
    for (int i = 0; i < 24; i++) {
        if (i >= n - 1) break;
        if (x < FR_T[s + i]) return s + i;
    }
    return s + n - 1;
}

vec3 typeCol(int sp) {
    if (sp == SP_PIKACHU) return vec3(1.0, 0.85, 0.2);
    if (sp == SP_CHARMANDER) return vec3(1.0, 0.5, 0.15);
    if (sp == SP_SQUIRTLE || sp == SP_PSYDUCK) return vec3(0.4, 0.72, 1.0);
    if (sp == SP_BULBASAUR) return vec3(0.4, 0.9, 0.45);
    if (sp == SP_JIGGLYPUFF || sp == SP_MEW) return vec3(1.0, 0.6, 0.85);
    if (sp == SP_EEVEE) return vec3(0.95, 0.75, 0.45);
    if (sp == SP_SNORLAX) return vec3(0.5, 0.8, 0.85);
    if (sp == SP_DARKRAI) return vec3(0.85, 0.18, 0.3);
    if (sp == SP_ZORO) return vec3(0.35, 0.85, 0.45);
    if (sp == SP_SASUKE) return vec3(0.55, 0.75, 1.0);
    if (sp == SP_GOKU) return vec3(0.78, 0.85, 1.0);
    if (sp == SP_LUFFY) return vec3(1.0, 0.35, 0.3);
    if (sp == SP_NARUTO) return vec3(1.0, 0.6, 0.15);
    if (sp == SP_KILLUA) return vec3(0.55, 0.8, 1.0);
    if (sp == SP_ICHIGO) return vec3(0.85, 0.15, 0.2);
    if (sp == SP_KAKASHI) return vec3(0.75, 0.85, 1.0);
    return vec3(0.62, 0.38, 0.95);  // the ghosts
}

// an n x n block of sprite pixels with its corner at p
float pdot(vec2 fc, vec2 p, float n) {
    vec2 d = floor(fc / PX) - floor(p / PX);
    return (d.x >= 0.0 && d.y >= 0.0 && d.x < n && d.y < n) ? 1.0 : 0.0;
}
vec2 pcentre(vec2 fc) { return floor(fc / PX) * PX + PX * 0.5; }
// translucent things are drawn as a pixel-art checkerboard
float dither(vec2 fc, float a) {
    vec2 g = mod(floor(fc / PX), 2.0);
    return (a > 0.66) ? 1.0 : (a > 0.25) ? ((g.x == g.y) ? 1.0 : 0.0) : 0.0;
}
mat2 rot(float a) { return mat2(cos(a), sin(a), -sin(a), cos(a)); }

// 4x6 music note for Jigglypuff's song
float noteGlyph(vec2 local, float s) {
    vec2 p = floor(local / s);
    if (p.x < 0.0 || p.y < 0.0 || p.x > 3.0 || p.y > 5.0) return 0.0;
    if (p.y <= 1.0) return (p.x <= 1.0) ? 1.0 : 0.0;
    if (p.x == 1.0) return 1.0;
    return (p.y >= 4.0 && p.x >= 2.0 && !(p.y == 4.0 && p.x == 3.0)) ? 1.0 : 0.0;
}

// 4x4 "z" glyph for the sleep bubbles
float zGlyph(vec2 local, float s) {
    vec2 p = floor(local / s);
    if (p.x < 0.0 || p.y < 0.0 || p.x > 3.0 || p.y > 3.0) return 0.0;
    if (p.y == 3.0 || p.y == 0.0) return 1.0;
    return (p.x == p.y) ? 1.0 : 0.0;
}

float sdSeg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

// jagged lightning between a and b; returns distance to the bolt
float boltDist(vec2 p, vec2 a, vec2 b, float seed) {
    vec2 d = b - a;
    float L = max(length(d), 1.0);
    vec2 n = vec2(-d.y, d.x) / L;
    float amp = min(L * 0.10, 26.0);
    float md = 1e9;
    vec2 prev = a;
    for (int i = 1; i <= 9; i++) {
        float t = float(i) / 9.0;
        float off = (i < 9) ? (hash11(seed + float(i) * 7.13) * 2.0 - 1.0) * amp : 0.0;
        vec2 q = a + d * t + n * off;
        md = min(md, sdSeg(p, prev, q));
        prev = q;
    }
    return md;
}

vec3 hsv(float h, float s, float v) {
    vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return v * mix(vec3(1.0), k, s);
}

// Ghostty samples/writes linear colour; uniforms and our palette are sRGB.
vec3 toLinear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 toSRGB(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

float segAmount(vec3 c, vec3 bg, vec3 m) {
    vec3 dm = m - bg;
    float a = dot(c - bg, dm) / dot(dm, dm);
    vec3 r = c - (bg + a * dm);
    return (a > 0.12 && a < 1.04 && dot(r, r) < 0.0007) ? clamp(a, 0.0, 1.0) : 0.0;
}

// how much of magic colour m is in pixel c (sRGB). Antialiased glyph edges are
// a blend of bg and m — in sRGB or in linear space depending on the renderer,
// so accept either.
float inkAmount(vec3 c, vec3 bg, vec3 m) {
    float a = segAmount(c, bg, m);
    if (a > 0.0) return a;
    return segAmount(toLinear(c), toLinear(bg), toLinear(m));
}

vec3 texS(vec2 fc) {
    vec3 c = texture(iChannel0, toTex(fc)).rgb;
    return G_LINEAR ? toSRGB(c) : c;
}

// ink is text: thin strokes with background close by. Solid pixel art
// (half-block portraits, colour fills) never counts, even in an ink colour.
bool isStroke(vec2 fc, vec3 bg) {
    float r = 5.0;
    return distance(texS(fc + vec2(r, 0.0)), bg) < 0.06 || distance(texS(fc - vec2(r, 0.0)), bg) < 0.06
        || distance(texS(fc + vec2(0.0, r)), bg) < 0.06 || distance(texS(fc - vec2(0.0, r)), bg) < 0.06;
}

// ---------------------------------------------------------------- signature moves
// Each species' move, zt seconds after it lands. feet: ground point under it,
// b: middle of its body, dir: +1 facing right, -1 facing left.
vec3 signature(vec3 col, int sp, vec2 fc, vec2 feet, vec2 b, float zt, float seed, float dir) {
    if (zt < 0.0 || zt > 1.0) return col;
    vec2 q = pcentre(fc);
    float life = 1.0 - zt;
    if (sp == SP_PIKACHU) {
        // short arcs crackling out of the cheeks
        if (zt < 0.6) for (int i = 0; i < 3; i++) {
            float ang = hash11(floor(iTime * 16.0) + float(i) * 3.7 + seed) * 6.283;
            vec2 tip = b + vec2(cos(ang), sin(ang) * 0.7 + 0.3) * (36.0 + 20.0 * hash11(float(i) + floor(iTime * 16.0)));
            float md = boltDist(q, b, tip, floor(iTime * 30.0) + float(i) * 9.1);
            float f = 1.0 - zt / 0.6;
            col = mix(col, vec3(1.0, 0.9, 0.3), exp(-md / 6.0) * 0.5 * f);
            col = mix(col, vec3(1.0, 1.0, 0.9), (1.0 - smoothstep(PX * 0.4, PX * 1.2, md)) * f);
        }
    } else if (sp == SP_CHARMANDER) {
        // Ember: sparks burst out and float up while a ring of flame licks the ground
        for (int i = 0; i < 12; i++) {
            float h1 = hash11(seed + float(i) * 1.73), h2 = hash11(seed + float(i) * 5.11);
            vec2 v = vec2((h1 - 0.5) * 300.0, 120.0 + h2 * 220.0);
            vec2 p = feet + vec2(sin(iTime * 20.0 + float(i)) * 3.0, 6.0) + v * zt - vec2(0.0, 260.0) * zt * zt;
            float l = 1.0 - zt / (0.55 + 0.45 * h2);
            if (l > 0.0) col = mix(col, mix(vec3(1.0, 0.25, 0.05), vec3(1.0, 0.95, 0.5), l), pdot(fc, p, h1 > 0.7 ? 2.0 : 1.0) * min(l * 2.0, 1.0));
        }
        float R = 12.0 + zt * 80.0, dx = abs(q.x - feet.x), dy = q.y - feet.y;
        if (zt < 0.6 && dy > -PX && abs(dx - R) < 22.0) {
            float n = hash21(vec2(floor(q.x / PX), floor(iTime * 14.0)));
            float hgt = (10.0 + 18.0 * n) * (1.0 - zt / 0.6) * (1.0 - abs(dx - R) / 22.0);
            if (dy < hgt) col = mix(col, mix(vec3(1.0, 0.85, 0.3), vec3(1.0, 0.3, 0.05), dy / max(hgt, 1.0)), 0.9);
        }
    } else if (sp == SP_SQUIRTLE) {
        // a splash: drops thrown up that fall back, and a ripple
        for (int i = 0; i < 14; i++) {
            float h1 = hash11(seed + float(i) * 2.31), h2 = hash11(seed + float(i) * 7.03);
            vec2 v = vec2((h1 - 0.5) * 280.0, 150.0 + h2 * 200.0);
            vec2 p = feet + vec2(0.0, 4.0) + v * zt - vec2(0.0, 650.0) * zt * zt;
            if (p.y < feet.y - PX || zt > 0.9) continue;
            col = mix(col, mix(vec3(0.45, 0.75, 1.0), vec3(0.9, 0.97, 1.0), h2), pdot(fc, p, h1 > 0.75 ? 2.0 : 1.0));
        }
        if (zt < 0.8) {
            float rx = 16.0 + zt * 150.0;
            float ring = 1.0 - smoothstep(0.0, PX * 1.2, abs(length((q - feet) * vec2(1.0, 4.0)) - rx));
            col = mix(col, vec3(0.55, 0.82, 1.0), ring * (1.0 - zt / 0.8) * 0.8);
        }
    } else if (sp == SP_BULBASAUR) {
        // Razor Leaf: six leaves spin outward
        for (int i = 0; i < 6; i++) {
            float ang = float(i) * 1.047 + seed;
            vec2 c = b + 130.0 * (1.0 - life * life) * vec2(cos(ang), sin(ang) * 0.6);
            vec2 l = rot(iTime * 14.0 + float(i)) * (q - c);
            float leaf = step(abs(l.x) / 13.0 + abs(l.y) / 5.0, 1.0);
            vec3 g = (abs(l.y) < 1.6) ? vec3(0.22, 0.55, 0.22) : vec3(0.45, 0.88, 0.32);
            col = mix(col, g, leaf * min(life * 3.0, 1.0));
        }
    } else if (sp == SP_EEVEE) {
        // Swift: golden stars spiral out
        for (int i = 0; i < 5; i++) {
            float ang = float(i) * 1.2566 + zt * 4.0 + seed;
            vec2 d = q - (b + (20.0 + zt * 120.0) * vec2(cos(ang), sin(ang) * 0.7));
            float a = atan(d.y, d.x) + iTime * 6.0;
            float rr = length(d);
            float star = step(rr, 9.0 * (0.45 + 0.55 * pow(0.5 + 0.5 * cos(5.0 * a), 2.0)));
            col = mix(col, (rr < 3.5) ? vec3(1.0) : vec3(1.0, 0.88, 0.3), star * min(life * 3.0, 1.0));
        }
    } else if (sp == SP_MEW) {
        // a psychic bubble swells and pops, with twinkles inside
        float R = 10.0 + 90.0 * sqrt(zt);
        vec2 d = q - b;
        float edge = 1.0 - smoothstep(0.0, PX * 1.5, abs(length(d) - R));
        vec3 sh = hsv(fract(atan(d.y, d.x) / 6.283 + iTime * 0.6), 0.35, 1.0);
        col = mix(col, mix(vec3(1.0, 0.6, 0.85), sh, 0.5), edge * life);
        col = mix(col, vec3(1.0, 0.7, 0.9), step(length(d), R) * 0.12 * life * dither(fc, 0.5));
        for (int i = 0; i < 6; i++) {
            float h = hash11(seed + float(i) * 4.4);
            vec2 c = b + rot(h * 6.283) * vec2(R * (0.4 + 0.5 * h), 0.0);
            vec2 e = abs(floor((fc - c) / PX));
            float tw = step(0.5, sin(iTime * 18.0 + h * 40.0));
            col = mix(col, vec3(1.0), ((e.x == 0.0 && e.y <= 1.0) || (e.y == 0.0 && e.x <= 1.0) ? 1.0 : 0.0) * tw * life);
        }
    } else if (sp == SP_SNORLAX) {
        // dust kicked up on both sides (the text shake happens in mainImage)
        for (int i = 0; i < 6; i++) {
            float side = (i < 3) ? -1.0 : 1.0, h = hash11(seed + float(i) * 3.3);
            vec2 c = feet + vec2(side * (20.0 + zt * 110.0 * (0.6 + 0.4 * h)), 6.0 + zt * 30.0 * h);
            float r = 9.0 + zt * 22.0 * (0.7 + 0.3 * h);
            float a = max(1.0 - zt / 0.9, 0.0);
            col = mix(col, mix(vec3(0.62, 0.56, 0.5), vec3(0.85, 0.8, 0.72), step(c.y + r * 0.3, q.y)), step(length(q - c), r) * dither(fc, a));
        }
        // impact lines on the ground
        if (zt < 0.25) for (int i = 0; i < 4; i++) {
            float side = (i < 2) ? -1.0 : 1.0, x0 = feet.x + side * (14.0 + float(i % 2) * 10.0 + zt * 80.0);
            float d = sdSeg(q, vec2(x0, feet.y + 2.0), vec2(x0 + side * 16.0, feet.y + 14.0 + float(i % 2) * 8.0));
            col = mix(col, vec3(1.0, 0.97, 0.9), (1.0 - smoothstep(0.0, PX, d)) * (1.0 - zt / 0.25));
        }
    } else if (sp == SP_PSYDUCK) {
        // Confusion: rings pulse out of its aching head
        vec2 head = b + vec2(0.0, 10.0);
        for (int i = 0; i < 3; i++) {
            float tz = zt - float(i) * 0.15;
            if (tz < 0.0 || tz > 0.6) continue;
            float ring = 1.0 - smoothstep(PX * 0.5, PX * 1.5, abs(length(q - head) - (8.0 + tz * 110.0)));
            col = mix(col, mix(vec3(0.45, 0.78, 1.0), vec3(0.85, 0.95, 1.0), 1.0 - tz / 0.6), ring * step(0.15, hash21(floor(fc / PX))) * (1.0 - tz / 0.6));
        }
    } else if (sp == SP_JIGGLYPUFF) {
        // Sing: a burst of notes
        for (int i = 0; i < 6; i++) {
            float ang = float(i) * 1.047 + seed;
            vec2 c = b + vec2(cos(ang), sin(ang) * 0.6 + 0.4) * zt * 110.0 + vec2(0.0, sin(zt * 12.0 + float(i)) * 5.0);
            float g = noteGlyph(fc - c, floor(PX * 1.4));
            col = mix(col, hsv(fract(float(i) * 0.17 + zt), 0.4, 1.0), g * min(life * 3.0, 1.0));
        }
    } else if (sp == SP_GENGAR) {
        // Shadow Ball: a dark orb swells in front of it, then bursts
        vec2 c = b + vec2(dir * 26.0, 4.0);
        vec2 d = q - c;
        if (zt < 0.55) {
            float R = 4.0 + 34.0 * smoothstep(0.0, 0.55, zt);
            float sw = sin(atan(d.y, d.x) * 3.0 + length(d) * 0.25 - iTime * 10.0);
            if (length(d) < R) col = mix(vec3(0.16, 0.04, 0.25), vec3(0.55, 0.25, 0.85), 0.5 + 0.5 * sw);
            col = mix(col, vec3(0.85, 0.6, 1.0), 1.0 - smoothstep(0.0, PX * 1.2, abs(length(d) - R)));
        } else {
            float z = (zt - 0.55) / 0.45;
            col = mix(col, vec3(0.6, 0.3, 0.9), (1.0 - smoothstep(0.0, PX * 1.5, abs(length(d) - 38.0 - z * 120.0))) * (1.0 - z));
        }
    } else if (sp == SP_GASTLY) {
        // Smog: puffs of poison gas roll out
        for (int i = 0; i < 7; i++) {
            float h = hash11(seed + float(i) * 2.9), ang = float(i) * 0.9 + h;
            vec2 c = b + vec2(cos(ang) * zt * 80.0, sin(ang) * zt * 40.0 + zt * 20.0);
            col = mix(col, mix(vec3(0.5, 0.3, 0.7), vec3(0.75, 0.55, 0.9), h), step(length(q - c), 7.0 + zt * 16.0) * dither(fc, life * 0.9));
        }
    } else if (sp == SP_DARKRAI) {
        // Dark Void: a black hole opens in front of it, drinks in the light, then collapses
        vec2 c = b + vec2(dir * 30.0, 2.0);
        vec2 d = q - c;
        float r = length(d);
        float R = 30.0 * smoothstep(0.0, 0.3, zt) * (1.0 - smoothstep(0.6, 0.85, zt));
        if (r < R + 14.0) {
            float arm = 0.5 + 0.5 * sin((atan(d.y, d.x) + 6.0 / (r * 0.08 + 1.0) - iTime * 5.0) * 3.0);
            col = mix(col, mix(vec3(0.35, 0.05, 0.12), vec3(0.85, 0.15, 0.25), arm), (1.0 - smoothstep(R, R + 14.0, r)) * 0.8 * arm);
            if (r < R) col = vec3(0.02, 0.0, 0.03);
            col = mix(col, vec3(1.0, 0.3, 0.35), (1.0 - smoothstep(0.0, PX, abs(r - R))) * step(1.0, R));
        }
        if (zt < 0.8) for (int i = 0; i < 8; i++) {   // light pulled into the void
            float h = hash11(seed + float(i) * 3.7);
            float ph = fract(zt * 1.6 + h);
            vec2 mp = c + rot(h * 6.283 + ph * 3.0) * vec2(70.0 * (1.0 - ph), 0.0);
            col = mix(col, (i % 2 == 0) ? vec3(0.4, 0.9, 1.0) : vec3(0.9, 0.2, 0.3), pdot(fc, mp, 1.0));
        }
        if (zt > 0.8) {
            float z = (zt - 0.8) / 0.2;
            col = mix(col, vec3(0.6, 0.1, 0.25), (1.0 - smoothstep(0.0, PX * 1.5, abs(r - z * 90.0))) * (1.0 - z));
        }
    } else if (sp == SP_GOKU) {
        // Kamehameha: a ball of ki gathers at his hip, then a beam blasts out of his hands
        vec2 hip = b + vec2(-dir * 6.0, -6.0);
        vec2 hand = b + vec2(dir * 26.0, 0.0);
        if (zt < 0.48) {
            float R = 3.0 + 9.0 * smoothstep(0.0, 0.45, zt);
            float d = length(q - hip);
            col += vec3(0.3, 0.6, 1.0) * exp(-d / (R * 1.6)) * 0.9;
            col = mix(col, vec3(0.85, 0.95, 1.0), step(d, R * 0.6));
            float ring = 1.0 - smoothstep(0.0, PX, abs(d - R * 1.4 - sin(iTime * 40.0) * 2.0));
            col = mix(col, vec3(0.6, 0.85, 1.0), ring * step(0.5, hash21(floor(fc / PX) + floor(iTime * 20.0))));
        } else {
            float L = min((zt - 0.48) * 1500.0, 320.0);
            float fade = 1.0 - smoothstep(0.85, 1.0, zt);
            float along = (q.x - hand.x) * dir;
            float cw = 7.0 + 2.0 * sin(iTime * 50.0 + along * 0.15) + min(max(along, 0.0) * 0.02, 5.0);   // core half-width
            float across = abs(q.y - hand.y);
            if (along > -4.0 && along < L) {
                col = mix(col, vec3(0.25, 0.55, 1.0), exp(-max(across - cw, 0.0) / 9.0) * 0.95 * fade);
                col = mix(col, vec3(0.55, 0.85, 1.0), step(across, cw * 1.35) * fade);
                float band = step(0.5, fract(along / 26.0 - iTime * 9.0));   // energy streaming outward
                col = mix(col, vec3(0.95, 0.99, 1.0), step(across, cw * (0.55 + 0.25 * band)) * fade);
            }
            float dh = length(q - (hand + vec2(dir * L, 0.0)));
            col += vec3(0.3, 0.6, 1.0) * exp(-dh / 16.0) * 0.8 * fade;
            col = mix(col, vec3(0.55, 0.85, 1.0), step(dh, cw * 2.4) * fade);
            col = mix(col, vec3(0.95, 0.99, 1.0), step(dh, cw * 1.5) * fade);
        }
    } else if (sp == SP_LUFFY) {
        // Gear Second: steam pours off him, then the Gatling's fists land in a flurry of impacts
        for (int i = 0; i < 6; i++) {
            float h = hash11(float(i) * 3.7 + seed);
            float ph = fract(zt * 1.8 + h);
            vec2 sp2 = b + vec2(-dir * 14.0 + (h - 0.5) * 22.0, 6.0 + ph * 50.0);
            col = mix(col, vec3(1.0, 0.93, 0.95), step(length(q - sp2), 4.0 + ph * 9.0) * (1.0 - ph * ph) * 0.8);
        }
        if (zt > 0.25 && zt < 0.95) for (int i = 0; i < 4; i++) {
            float k = floor(iTime * 14.0 + float(i) * 0.25);
            float lt = fract(iTime * 14.0 + float(i) * 0.25);
            vec2 c = b + vec2(dir * (34.0 + hash11(k + float(i)) * 55.0), (hash11(k * 1.3 + float(i)) - 0.5) * 34.0);
            vec2 d = q - c;
            float star = (12.0 + 14.0 * (1.0 - lt)) * (0.3 + 0.7 * pow(abs(cos(2.0 * atan(d.y, d.x))), 8.0));
            col = mix(col, (length(d) < star * 0.4) ? vec3(1.0) : vec3(1.0, 0.85, 0.35), step(length(d), star) * (1.0 - lt));
        }
    } else if (sp == SP_NARUTO) {
        // Rasengan: a spinning blue sphere in his palm that bursts on impact (the clones are in mainImage)
        vec2 c = b + vec2(dir * 20.0, -1.0);
        vec2 d = q - c;
        float r = length(d);
        if (zt > 0.25 && zt < 0.8) {
            float R = 7.0 + 7.0 * smoothstep(0.25, 0.6, zt);
            float sw = sin(atan(d.y, d.x) * 3.0 - r * 0.6 + iTime * 30.0);
            col += vec3(0.35, 0.7, 1.0) * exp(-r / (R * 1.5)) * 0.8;
            if (r < R) col = mix(vec3(0.45, 0.8, 1.0), vec3(0.95, 1.0, 1.0), 0.5 + 0.5 * sw);
            float dash = step(0.5, fract(atan(d.y, d.x) / 6.283 * 6.0 + iTime * 4.0));
            col = mix(col, vec3(0.8, 0.95, 1.0), (1.0 - smoothstep(0.0, PX, abs(r - R * 1.6))) * dash);
        }
        if (zt > 0.62) {
            float z = (zt - 0.62) / 0.38;
            for (int i = 0; i < 2; i++) {
                float ring = 1.0 - smoothstep(0.0, PX * 1.4, abs(r - (14.0 + z * (70.0 + float(i) * 40.0))));
                col = mix(col, vec3(0.75, 0.92, 1.0), ring * (1.0 - z));
            }
        }
    } else if (sp == SP_KILLUA) {
        // Godspeed: lightning crawls over him, then his claw rakes the air in three lines
        for (int i = 0; i < 6; i++) {
            float k = floor(iTime * 20.0) + float(i) * 5.3 + seed;
            vec2 a0 = b + (vec2(hash11(k), hash11(k + 1.7)) - 0.5) * vec2(30.0, 50.0);
            vec2 a1 = a0 + (vec2(hash11(k + 3.1), hash11(k + 4.4)) - 0.5) * 40.0;
            float md = boltDist(q, a0, a1, k);
            col = mix(col, vec3(0.45, 0.78, 1.0), exp(-md / 7.0) * 0.9 * life);
            col = mix(col, vec3(0.97, 0.99, 1.0), (1.0 - smoothstep(PX * 0.6, PX * 1.6, md)) * life);
        }
        for (int i = 0; i < 3; i++) {
            float ts = zt - 0.38 - float(i) * 0.04;
            if (ts < 0.0 || ts > 0.35) continue;
            float x0 = b.x + dir * (16.0 + float(i) * 7.0);
            vec2 s0 = vec2(x0 - dir * 14.0, b.y + 24.0), s1 = vec2(x0 + dir * 10.0, b.y - 20.0);
            float d = sdSeg(q, s0, mix(s0, s1, min(ts / 0.06, 1.0)));
            float f = 1.0 - ts / 0.35;
            col = mix(col, vec3(0.45, 0.78, 1.0), exp(-d / 8.0) * 0.9 * f);
            col = mix(col, vec3(1.0), (1.0 - smoothstep(PX * 0.8, PX * 1.8, d)) * f);
        }
    } else if (sp == SP_ICHIGO) {
        // the mask forms in black reiatsu, then Getsuga Tensho: a black crescent with a red edge flies off the blade
        if (zt > 0.45) {
            float z = (zt - 0.45) / 0.55;
            vec2 c = b + vec2(dir * (30.0 + z * 380.0), 4.0);
            vec2 l = (q - c) * vec2(dir, 1.0);
            float outer = length(l * vec2(1.0, 0.8)), inner = length((l - vec2(-20.0, 0.0)) * vec2(1.0, 0.8));
            float a = (1.0 - z * z);
            if (outer < 46.0 && inner > 40.0 && l.x > -16.0) {
                float edgeT = smoothstep(40.0, 46.0, outer);   // black inner edge -> crimson body -> red rim
                vec3 g = mix(vec3(0.55, 0.03, 0.1), vec3(0.85, 0.08, 0.15), edgeT);
                if (inner < 42.5) g = vec3(0.04, 0.0, 0.02);
                if (outer > 43.0) g = vec3(1.0, 0.35, 0.35);
                col = mix(col, g, a);
            }
            // smoke peeling off the back of it
            float sm = step(0.82, hash21(floor(q / PX) + floor(iTime * 12.0))) * step(outer, 52.0) * step(46.0, outer + 14.0) * step(l.x, -6.0);
            col = mix(col, vec3(0.2, 0.02, 0.06), sm * a * 0.8);
        }
    } else if (sp == SP_ZORO) {
        // Onigiri: three crescent slashes, one per sword, then the cut line he dashes through
        for (int i = 0; i < 3; i++) {
            float ts = zt - 0.18 - float(i) * 0.07;
            if (ts < 0.0 || ts > 0.35) continue;
            vec2 c = b + vec2(dir * (10.0 + float(i) * 8.0), 4.0 - float(i) * 6.0);
            vec2 d = q - c;
            float ang = atan(d.y, d.x * dir);                  // 0 = straight ahead
            float reach = mix(1.3, -1.3, min(ts / 0.1, 1.0));   // the blade travels top to bottom
            float on = step(reach, ang) * step(ang, 1.3);
            float R = 30.0 + float(i) * 6.0;
            float edge = abs(length(d) - R);
            float f = 1.0 - ts / 0.35;
            col = mix(col, vec3(0.55, 1.0, 0.65), exp(-edge / 4.0) * 0.5 * f * on);
            col = mix(col, vec3(1.0), (1.0 - smoothstep(PX * 0.5, PX * 1.5, edge)) * f * on);
        }
        float tl = zt - 0.55;   // the dash: a thin white cut, then it splits
        if (tl > 0.0 && tl < 0.4) {
            float y = b.y + 2.0;
            float x0 = b.x - dir * 90.0, x1 = b.x + dir * 30.0;
            float inside = step(min(x0, x1), q.x) * step(q.x, max(x0, x1));
            // one line, then it splits into two that drift apart, like the air was cut
            float spread = max(tl - 0.12, 0.0) * 40.0;
            float d = min(abs(q.y - y - spread), abs(q.y - y + spread));
            float f = 1.0 - tl / 0.4;
            col = mix(col, vec3(1.0), (1.0 - smoothstep(PX * 0.5, PX * 1.2, d)) * inside * f);
        }
    } else if (sp == SP_SASUKE || sp == SP_KAKASHI) {
        // Chidori (Sasuke) / Raikiri (Kakashi): lightning roars in the hand and bursts on the strike
        bool rai = sp == SP_KAKASHI;
        vec2 hand = rai ? b + ((zt < 0.55) ? vec2(-dir * 18.0, -4.0) : vec2(dir * 28.0, 6.0)) : b + vec2(dir * 18.0, -4.0);
        float charge = smoothstep(0.0, 0.3, zt) * (1.0 - smoothstep(0.75, 1.0, zt));
        float burst = (zt > 0.4 && zt < 0.6) ? 1.0 - (zt - 0.4) / 0.2 : 0.0;
        if (rai) { charge *= 1.4; burst *= 1.3; }
        float gd = length(q - hand);
        col += vec3(0.45, 0.7, 1.0) * exp(-gd / (8.0 + 18.0 * burst)) * (0.5 * charge + 0.5 * burst);
        for (int i = 0; i < 8; i++) {
            if (!rai && i >= 5) break;
            float ang = hash11(floor(iTime * 24.0) + float(i) * 4.1 + seed) * 6.283;
            if (rai && i >= 5) ang = (dir > 0.0 ? 0.0 : PI) + (hash11(float(i) + floor(iTime * 30.0)) - 0.5) * 0.9;   // Raikiri tears forward
            float len = (10.0 + 14.0 * hash11(float(i) + floor(iTime * 24.0))) * (1.0 + 2.5 * burst) * (rai ? 1.5 : 1.0);
            vec2 tip = hand + vec2(cos(ang), sin(ang)) * len;
            float md = boltDist(q, hand, tip, floor(iTime * 40.0) + float(i) * 7.7);
            float a = charge + burst;
            col = mix(col, vec3(0.5, 0.75, 1.0), exp(-md / 4.0) * 0.6 * min(a, 1.0));
            col = mix(col, vec3(0.92, 0.97, 1.0), (1.0 - smoothstep(PX * 0.3, PX, md)) * min(a, 1.0));
        }
    }
    return col;
}

// particles shed along the hop arc from a to b (sprite-body height already added)
vec3 hopTrail(vec3 col, int sp, vec2 fc, vec2 a, vec2 b, float arcH, float tk, float seed) {
    vec3 tc = typeCol(sp);
    for (int j = 0; j < 10; j++) {
        float s = (float(j) + 0.5) / 10.0;
        float age = tk - s * HOP_T;
        if (age < 0.0 || age > 0.4) continue;
        float h = hash11(seed + float(j) * 3.1);
        vec2 p = mix(a, b, s) + vec2(0.0, sin(s * PI) * arcH) + (vec2(h, hash11(h * 91.0)) - 0.5) * 10.0;
        if (sp == SP_CHARMANDER) p += vec2((h - 0.5) * 20.0, 60.0) * age;
        else if (sp == SP_SQUIRTLE) p += vec2((h - 0.5) * 20.0, -120.0 * age) * age;
        else if (sp == SP_BULBASAUR) p += vec2(sin(age * 12.0 + h * 6.0) * 14.0, -40.0) * age;
        else p += (vec2(h, 1.0 - h) - 0.4) * 30.0 * age;
        float l = 1.0 - age / 0.4;
        vec3 c = (sp == SP_CHARMANDER) ? mix(vec3(1.0, 0.3, 0.05), vec3(1.0, 0.9, 0.4), l) : mix(tc, vec3(1.0), 0.35 * l);
        col = mix(col, c, pdot(fc, p, 1.0) * l);
    }
    return col;
}

// Ultra Instinct: silver flames lick up around Goku, drawn behind the sprite
vec3 uiAura(vec3 col, vec2 fc, vec2 c, float hw, float h, float t) {
    vec2 q = pcentre(fc);
    vec2 d = (q - c) / vec2(hw * 0.62 + 4.0, h * 0.56);
    float r = length(d);
    if (r > 1.8) return col;
    float n = hash21(vec2(floor(q.x / (PX * 2.0)), floor((q.y - t * 120.0) / (PX * 4.0))));
    float edge = 1.0 + 0.2 * n + 0.55 * n * smoothstep(0.0, 1.0, d.y);   // tongues lick upward
    float rim = step(r, edge) * smoothstep(edge - 0.5, edge, r);
    col = mix(col, mix(vec3(0.55, 0.68, 1.0), vec3(0.95, 0.97, 1.0), n), rim * 0.6);
    for (int i = 0; i < 6; i++) {
        float h1 = hash11(float(i) * 3.3 + 1.0);
        float ph = fract(t * 0.8 + h1);
        vec2 p = c + vec2((h1 - 0.5) * hw * 1.6, (ph - 0.35) * h * 1.3);
        col = mix(col, vec3(0.95, 0.97, 1.0), pdot(fc, p, 1.0) * (1.0 - ph));
    }
    return col;
}

// one frame of party member k drawn with its feet at `anchor` (for afterimages and clones)
vec4 spriteAt(int fr, int k, vec2 fc, vec2 anchor, float spx, bool flip) {
    vec2 p = floor((fc - anchor) / spx);
    if (flip) p.x = -p.x - 1.0;
    return spriteFrame(fr, k, p);
}

// effects along a hop from a to b (body height), tk seconds in
vec3 hopFx(vec3 col, int sp, vec2 fc, vec2 a, vec2 b, float arcH, float tk, float seed) {
    vec2 q = pcentre(fc);
    if (sp == SP_LUFFY) {   // Gear Second steam
        for (int j = 0; j < 8; j++) {
            float s = (float(j) + 0.5) / 8.0, age = tk - s * HOP_T;
            if (age < 0.0 || age > 0.5) continue;
            vec2 p = mix(a, b, s) + vec2(0.0, sin(s * PI) * arcH + age * 40.0);
            col = mix(col, vec3(1.0, 0.9, 0.92), step(length(q - p), 3.0 + age * 18.0) * (1.0 - age / 0.5) * 0.5);
        }
    } else if (sp == SP_NARUTO) {   // chakra wisps
        for (int j = 0; j < 10; j++) {
            float s = (float(j) + 0.5) / 10.0, age = tk - s * HOP_T;
            if (age < 0.0 || age > 0.35) continue;
            float h = hash11(seed + float(j));
            vec2 p = mix(a, b, s) + vec2((h - 0.5) * 12.0, sin(s * PI) * arcH + age * 60.0);
            col = mix(col, mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.85, 0.4), h), pdot(fc, p, 2.0) * (1.0 - age / 0.35));
        }
    } else if (sp == SP_KILLUA) {   // Godspeed: three bolts braided along the path
        float fade = 1.0 - smoothstep(HOP_T * 0.6, HOP_T + 0.25, tk);
        for (int i = 0; i < 3; i++) {
            float md = boltDist(q, a, b, seed * 13.1 + floor(iTime * 26.0) + float(i) * 5.0);
            col = mix(col, vec3(0.45, 0.75, 1.0), exp(-md / 7.0) * 0.4 * fade);
            col = mix(col, vec3(0.92, 0.97, 1.0), (1.0 - smoothstep(PX * 0.3, PX * 1.1, md)) * fade);
        }
    } else if (sp == SP_KAKASHI) {   // Body Flicker: a swirl of leaves where he vanishes and where he lands
        for (int e = 0; e < 2; e++) {
            float te = (e == 0) ? tk : tk - HOP_T * 0.85;
            if (te < 0.0 || te > 0.4) continue;
            vec2 c = (e == 0) ? a : b;
            for (int i = 0; i < 10; i++) {
                float ang = float(i) * 0.628 + te * 9.0 + seed;
                vec2 lc = c + vec2(cos(ang), sin(ang) * 0.8) * (10.0 + te * 110.0);
                vec2 l = rot(iTime * 12.0 + float(i)) * (q - lc);
                col = mix(col, (i % 2 == 0) ? vec3(0.35, 0.75, 0.3) : vec3(0.55, 0.85, 0.35), step(abs(l.x) / 11.0 + abs(l.y) / 4.5, 1.0) * (1.0 - te / 0.4));
            }
            col = mix(col, vec3(0.9, 0.9, 0.85), step(length(q - c), 4.0 + te * 30.0) * (1.0 - te / 0.4) * 0.5);
        }
    } else if (sp == SP_ICHIGO) {   // shunpo: speed lines along the path
        float fade = 1.0 - smoothstep(HOP_T * 0.8, HOP_T + 0.2, tk);
        vec2 dv = normalize(b - a + vec2(0.001));
        vec2 nv = vec2(-dv.y, dv.x);
        float along = dot(q - a, dv), across = dot(q - a, nv);
        float L = length(b - a);
        float lane = floor(across / (PX * 3.0));
        float on = step(0.6, hash11(lane * 7.1 + seed)) * step(abs(across), 26.0);
        float seg = step(0.0, along) * step(along, L * min(tk / HOP_T, 1.0));
        col = mix(col, (hash11(lane) > 0.5) ? vec3(0.85, 0.12, 0.18) : vec3(0.05, 0.0, 0.03), on * seg * fade * step(fract(along / 40.0 + hash11(lane * 3.3)), 0.7));
    }
    return col;
}

// the "!" a Pokémon shows when it spots you: 9x11 sprite pixels, origin bottom-left
vec4 alertBubble(vec2 p) {
    if (p.x < 0.0 || p.y < 0.0 || p.x > 8.0 || p.y > 10.0) return vec4(0.0);
    vec3 K = vec3(0.07, 0.06, 0.08);
    if (p.y == 0.0) return (p.x == 3.0 || p.x == 4.0) ? vec4(K, 1.0) : vec4(0.0);  // tail
    bool corner = (p.x == 0.0 || p.x == 8.0) && (p.y == 1.0 || p.y == 10.0);
    if (corner) return vec4(0.0);
    if (p.x == 0.0 || p.x == 8.0 || p.y == 1.0 || p.y == 10.0) return vec4(K, 1.0);
    if (p.x == 4.0 && ((p.y >= 5.0 && p.y <= 8.0) || p.y == 3.0)) return vec4(0.92, 0.2, 0.18, 1.0);
    return vec4(0.97, 0.96, 0.92, 1.0);
}

// ---------------------------------------------------------------- main
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 fc = vec2(fragCoord.x, iResolution.y - fragCoord.y);
    vec4 CUR = cursorUp(iCurrentCursor), PREV = cursorUp(iPreviousCursor);
    readClaudeState();
#if SHOW_PIKA
    // Snorlax lands hard enough to shake the text
    if (PARTY_HAS_SNORLAX && iCursorVisible != 0) {
        vec2 dd = CUR.xy - PREV.xy;
        bool hop0 = abs(dd.y) > 1.0 || abs(dd.x) > max(CUR.z, 8.0) * 6.0;
        for (int k = 0; k < PARTY_N; k++) {
            float z = iTime - iTimeCursorChange - float(k) * 0.07 - HOP_T;
            if (S_SPECIES[k] == SP_SNORLAX && hop0 && z > 0.0 && z < 0.35)
                SHAKE = vec2(0.0, floor(sin(z * 70.0) * 5.0 * (1.0 - z / 0.35)));
        }
    }
#endif
    vec3 corner = texture(iChannel0, vec2(1.5, 1.5) / iResolution.xy).rgb;
    G_LINEAR = distance(toSRGB(corner), iBackgroundColor) < distance(corner, iBackgroundColor);
    vec4 base = tex(fc);
    if (G_LINEAR) base.rgb = toSRGB(base.rgb);
    vec3 bg = iBackgroundColor;
    vec3 col = base.rgb;
    float t = iTime;

#if SHOW_INK
    // ---- living ink ------------------------------------------------------
    {
        float a;
        bool stroke = false, strokeKnown = false;
        a = inkAmount(base.rgb, bg, INK_ELEC);
        if (a > 0.0) { stroke = isStroke(fc, bg); strokeKnown = true; if (!stroke) a = 0.0; }
        if (a > 0.0) {
            float flow = sin(fc.x * 0.045 - t * 9.0 + sin(fc.y * 0.3) * 0.6);
            float crackle = step(0.93, hash21(floor(fc / 4.0) + floor(t * 18.0)));
            vec3 m = mix(vec3(1.0, 0.78, 0.05), vec3(1.0, 1.0, 0.85), smoothstep(0.55, 1.0, flow));
            m = mix(m, vec3(1.0), crackle * 0.8);
            col = mix(bg, m, a);
        }
        a = inkAmount(base.rgb, bg, INK_SHINY);
        if (a > 0.0) { if (!strokeKnown) { stroke = isStroke(fc, bg); strokeKnown = true; } if (!stroke) a = 0.0; }
        if (a > 0.0) {
            float h = fc.x * 0.0035 - fc.y * 0.006 + t * 0.35;
            vec3 m = hsv(fract(h), 0.45, 1.0);
            vec2 cell = floor(fc / 6.0);
            float tw = hash21(cell);
            float glint = step(0.985, tw) * pow(0.5 + 0.5 * sin(t * 5.0 + tw * 60.0), 6.0);
            col = mix(bg, mix(m, vec3(1.0), glint), a);
        }
        a = inkAmount(base.rgb, bg, INK_FIRE);
        if (a > 0.0) { if (!strokeKnown) { stroke = isStroke(fc, bg); strokeKnown = true; } if (!stroke) a = 0.0; }
        if (a > 0.0) {
            float n = hash21(floor(vec2(fc.x / 3.0, fc.y / 3.0 - t * 14.0)));
            float hgt = fract(fc.y / 34.0);
            vec3 m = mix(vec3(1.0, 0.85, 0.25), vec3(1.0, 0.25, 0.05), hgt + n * 0.35);
            col = mix(bg, m, a * (0.8 + 0.2 * n));
        }
        // ghost ink wobbles: erase it here, redraw it displaced
        float ga = inkAmount(base.rgb, bg, INK_GHOST);
        if (ga > 0.0 && isStroke(fc, bg)) col = bg;
        float wob = sin(fc.y * 0.11 + t * 4.0) * 3.0 + sin(t * 1.7) * 1.5;
        vec4 gs = vec4(texS(fc - vec2(wob, 0.0)), 1.0);
        float gb = inkAmount(gs.rgb, bg, INK_GHOST);
        if (gb > 0.0 && !isStroke(fc - vec2(wob, 0.0), bg)) gb = 0.0;
        if (gb > 0.0) {
            float pulse = 0.65 + 0.35 * sin(t * 2.2 + fc.x * 0.01);
            vec3 m = mix(INK_GHOST, vec3(0.55, 0.95, 1.0), 0.5 + 0.5 * sin(fc.y * 0.2 - t * 3.0));
            col = mix(col, m, gb * pulse);
        }
    }
#endif

    // background mask: 1 where the pixel is plain background (no text)
    float bgMask = 1.0 - smoothstep(0.02, 0.07, distance(base.rgb, bg));

#if SHOW_STARS
    // ---- night sky ------------------------------------------------------
    {
        vec2 cell = floor(fc / 54.0);
        float h = hash21(cell + 17.0);
        if (h < 0.05) {
            vec2 sp = cell * 54.0 + floor(vec2(hash21(cell + 3.1), hash21(cell + 9.7)) * 48.0 / PX) * PX;
            vec2 d = floor((fc - sp) / PX);
            float tw = 0.5 + 0.5 * sin(t * (1.0 + h * 30.0) + h * 400.0);
            float star = (d == vec2(0.0)) ? 1.0 : 0.0;
            if (h < 0.012) star = max(star, (abs(d.x) + abs(d.y) == 1.0) ? tw * 0.6 : 0.0);
            col = mix(col, vec3(0.80, 0.86, 1.0), star * tw * 0.42 * bgMask);
        }
        // shooting star every ~19s
        float period = (PK_STATE == 4) ? 2.2 : 19.0;   // meteor shower after 3 min of Claude work
        float k = floor(t / period);
        float st = t - k * period;
        if (st < 0.9 && t > INTRO_T) {
            vec2 a0 = vec2(iResolution.x * (0.35 + 0.6 * hash11(k + 1.3)), iResolution.y * (0.75 + 0.2 * hash11(k + 5.1)));
            vec2 dir = normalize(vec2(-1.0, -0.45));
            vec2 head = a0 + dir * st * 900.0;
            vec2 q = floor(fc / PX) * PX;
            float along = dot(q - head, -dir);
            float across = abs(dot(q - head, vec2(-dir.y, dir.x)));
            if (along > 0.0 && along < 180.0 && across < PX) {
                float f = (1.0 - along / 180.0) * (1.0 - st / 0.9);
                col = mix(col, vec3(1.0, 0.97, 0.85), f * 0.85 * bgMask);
            }
        }
        // an aurora once Claude has been working for over a minute
        if (PK_STATE == 3 || PK_STATE == 4) {
            float B = PX * 2.0;
            vec2 qa = floor(fc / B) * B;
            float x = qa.x / iResolution.x, y = qa.y / iResolution.y;
            float d = y - (0.78 + 0.07 * sin(x * 5.0 + t * 0.25) + 0.03 * sin(x * 13.0 - t * 0.6));
            float curtain = (d < 0.0) ? exp(-d * d * 1500.0) : exp(-d * d * 120.0);
            float rays = 0.55 + 0.45 * sin(qa.x * 0.09 + sin(t * 0.7 + qa.x * 0.013) * 3.0);
            vec3 ac = mix(vec3(0.25, 0.95, 0.6), typeCol(S_SPECIES[0]), clamp(d * 4.0 + 0.3, 0.0, 1.0));
            float inten = ((PK_STATE == 4) ? 0.42 : 0.28) * (0.8 + 0.2 * sin(t * 0.9));
            col = mix(col, ac, curtain * rays * inten * bgMask);
        }
    }
#endif

#if SHOW_GRASS
    // ---- tall grass -----------------------------------------------------
    if (fc.y < GRASS_H) {
        float wind = sin(t * 1.3 + fc.x * 0.004) * 0.6 + sin(t * 0.7 + fc.x * 0.011) * 0.4;
        if (PK_STATE >= 2 && PK_STATE <= 4) wind *= 1.8;   // the wind picks up while Claude charges
        // a patch that rustles: a wild Pokémon is hiding in it
        float rk = floor(t / 13.0);
        float rx = iResolution.x * (0.1 + 0.8 * hash11(rk * 3.7 + 0.5));
        float rt = t - rk * 13.0;
        float rustle = (rt < 1.4) ? exp(-pow((fc.x - rx) / 70.0, 2.0)) * sin(t * 38.0) * 3.0 : 0.0;
        float yy = fc.y / GRASS_H;
        float xs = fc.x - (wind * 7.0 + rustle * 4.0) * yy * yy;
        float bx = floor(xs / PX);
        float hb = 0.35 + 0.65 * hash11(bx * 1.37);
        hb *= 0.75 + 0.25 * sin(bx * 0.9);
        float clump = 0.6 + 0.4 * sin(bx * 0.21) * sin(bx * 0.057 + 1.0);
        float bladeH = hb * clump * GRASS_H;
        float yq = floor(fc.y / PX) * PX;
        if (yq < bladeH) {
            float shade = (mod(bx, 2.0) == 0.0) ? 1.0 : 0.78;
            vec3 g = mix(vec3(0.10, 0.36, 0.20), vec3(0.32, 0.72, 0.30), yq / GRASS_H) * shade;
            col = mix(col, g, 0.72 * bgMask);
        }
    }
#endif

#if SHOW_PIKA
    // ---- the party: up to 3 Pokémon follow the cursor ----------------------
    {
        float tc = max(t - iTimeCursorChange, 0.0);
        float cellW = max(CUR.z, 8.0);
        bool visible = iCursorVisible != 0;
        float gap = PX * 3.0;
        float partyW = 0.0;
        float maxTop = 0.0;
        for (int k = 0; k < PARTY_N; k++) {
            partyW += float(S_HALFW[k]) * 2.0 * S_PX[k] + gap;
            maxTop = max(maxTop, float(S_TOP[k]) * S_PX[k]);
        }
        vec2 A = vec2(PREV.x + max(PREV.z, 8.0), PREV.y);
        vec2 B = vec2(CUR.x + cellW, CUR.y);
        if (!visible) A = B = vec2(iResolution.x - partyW - 18.0, 4.0);
        A.x = min(A.x + gap, iResolution.x - partyW - 4.0);
        B.x = min(B.x + gap, iResolution.x - partyW - 4.0);
        bool working = PK_STATE >= 1 && PK_STATE <= 4;
        bool needYou = PK_STATE == 5;
        bool done = PK_STATE >= 6;
        vec2 leadC = B + vec2(gap + float(S_HALFW[0]) * S_PX[0], float(S_TOP[0]) * S_PX[0] * 0.5);
        vec2 d = B - A;
        float dist = length(d);
        bool moved = dist > 0.5;
        bool hop = abs(d.y) > 1.0 || abs(d.x) > cellW * 6.0;

        // wide enough for the beams (Kamehameha, Getsuga Tensho) to fly
        vec2 lo = min(A, B) - vec2(420.0, 40.0);
        vec2 hi = max(A, B) + vec2(partyW + 420.0, maxTop + 170.0 + 0.12 * dist);
        bool near = all(greaterThan(fc, lo)) && all(lessThan(fc, hi));
        if (near) {
            bool sleeping = (tc > SLEEP_AFTER || (!visible && tc > 4.0)) && PK_STATE == 0;
            bool singing = PARTY_HAS_JIGGLY && !sleeping && tc > SLEEP_AFTER - 5.0;

            // did the last command faint? the prompt prints "fainted N" in ghost ink
            bool hurt = false;
            if (visible && tc < 2.5 && !moved) {
                float y = CUR.y + CUR.w * 0.5;
                for (int i = 0; i < 64; i++) {
                    float x = CUR.x - float(i) * cellW * 0.5;
                    if (x < 0.0) break;
                    vec3 s = texS(vec2(x, y));
                    if (inkAmount(s, bg, INK_GHOST) > 0.5) { hurt = true; break; }
                }
            }

            float slotX = 0.0;
            for (int k = 0; k < PARTY_N; k++) {
                float fk = float(k);
                float hw = float(S_HALFW[k]) * S_PX[k];
                float spx = S_PX[k];   // device px per sprite pixel (fighters are drawn finer)
                float spriteH = float(S_TOP[k]) * spx;
                float cx = slotX + hw;
                slotX += hw * 2.0 + gap;
                float tk = tc - fk * 0.07;
                vec2 pos;
                float lift = 0.0;
                float hk = 1.0;
                if (hop) {
                    hk = clamp(tk / HOP_T, 0.0, 1.0);
                    pos = mix(A, B, hk);
                    lift = sin(hk * PI) * (28.0 + 0.12 * dist);
                } else {
                    pos = mix(A, B, smoothstep(0.0, 0.06 + fk * 0.05, tk));
                }
                pos.x += cx;
                bool running = moved && !hop && tk < 0.42 && tk > -0.05;
                int sp = S_SPECIES[k];
                // Claude working: each takes a turn using its move every 4s.
                // Claude done: everyone jumps for joy.
                float zc = mod(t - fk * 1.33, 4.0);
                float jp = fract(t / 0.8 + fk * 0.23);
                if (done && jp < 0.45) lift += sin(jp / 0.45 * PI) * 24.0;
                bool hopping = hop && tk < HOP_T;
                int a;
                float at;            // time into the anim
                bool loop = true;
                bool flip = true;    // idle: face left, toward the cursor
                if (hopping) {
                    a = A_HOP; at = hk * AN_LEN[k * 6 + A_HOP]; loop = false; flip = d.x < 0.0;
                } else if (hop && tk < HOP_T + min(AN_LEN[k * 6 + A_SPECIAL], 1.2)) {
                    a = A_SPECIAL; at = tk - HOP_T; loop = false; flip = d.x < 0.0;
                } else if (running) {
                    a = A_WALK; at = t + fk * 0.13; flip = d.x < 0.0;
                } else if (hurt && tk < AN_LEN[k * 6 + A_HURT] * 2.0) {
                    a = A_HURT; at = tk; loop = false;
                } else if (done && jp < 0.45) {
                    a = A_HOP; at = jp / 0.45 * AN_LEN[k * 6 + A_HOP]; loop = false;
                } else if (working && zc < min(AN_LEN[k * 6 + A_SPECIAL], 1.2)) {
                    a = A_SPECIAL; at = zc; loop = false;
                } else if (sleeping) {
                    a = A_SLEEP; at = t + fk * 0.4;
                } else {
                    a = A_IDLE; at = t + fk * 0.37;
                }
                int id = k * 6 + a;
                int fr = pickFrame(id, at, loop);

                float alpha = 1.0;
                if (S_GHOST[k]) {
                    if (!sleeping) lift += 6.0 + sin(t * 2.2 + fk) * 4.0;
                    if (running) alpha = 0.6 + 0.25 * sin(t * 40.0);
                    if (hopping) { alpha = abs(1.0 - 2.0 * hk); lift = 6.0; pos = (hk < 0.5) ? vec2(A.x + cx, A.y) : vec2(B.x + cx, B.y); }
                    else alpha *= 0.94;
                }
                pos = floor(pos / PX) * PX;
                lift = floor(lift / PX) * PX;
                vec2 anchor = pos - vec2(0.0, float(S_GROUND[k]) * spx - lift);

                // soft shadow on the ground
                vec2 sq = (floor((fc - pos) / PX) * PX) / vec2(hw * max(0.75 - lift * 0.004, 0.3), PX * 1.5);
                if (dot(sq, sq) < 1.0)
                    col = mix(col, vec3(0.0), 0.30 * alpha);

                // seconds since the move started: after a hop, on Claude's beat, or each joyful landing
                float zt = -1.0;
                if (hop && visible) zt = tk - HOP_T;
                else if (working) zt = zc - 0.15;
                else if (done && jp >= 0.45) zt = (jp - 0.45) * 0.8;

                // ---- behind the sprite
                float arcH = 28.0 + 0.12 * dist;
                vec2 bodyC = pos + vec2(0.0, lift + spriteH * 0.45);
                // flash steps: Kakashi (Body Flicker) and Ichigo (shunpo) vanish mid-hop
                if ((sp == SP_KAKASHI || sp == SP_ICHIGO) && hopping && hk > 0.15 && hk < 0.85) alpha = 0.0;
                // Ultra Instinct: a silver aura burns around Goku all the time
                if (sp == SP_GOKU && !sleeping && !hopping && !running) col = uiAura(col, fc, bodyC, hw, spriteH, t);
                // afterimages along the hop: Goku silver, Killua blue, Ichigo black
                if ((sp == SP_GOKU || sp == SP_KILLUA || sp == SP_ICHIGO) && hop && visible && tk < HOP_T + 0.2) {
                    vec3 tint = (sp == SP_GOKU) ? vec3(0.8, 0.88, 1.0) : (sp == SP_KILLUA) ? vec3(0.45, 0.75, 1.0) : vec3(0.12, 0.0, 0.04);
                    float fadeE = 1.0 - smoothstep(HOP_T, HOP_T + 0.2, tk);
                    for (int e = 1; e <= 3; e++) {
                        float he = clamp(tk / HOP_T, 0.0, 1.0) - float(e) * 0.14;
                        if (he < 0.0) continue;
                        vec2 pe = floor((mix(A, B, he) + vec2(cx, 0.0)) / PX) * PX;
                        float le = floor(sin(he * PI) * arcH / PX) * PX;
                        vec4 se = spriteAt(fr, k, fc, pe - vec2(0.0, float(S_GROUND[k]) * spx - le), spx, flip);
                        col = mix(col, mix(se.rgb, tint, 0.65), se.a * (0.5 - float(e) * 0.13) * fadeE);
                    }
                }
                // Ichigo: black reiatsu flames with red tips rise behind him as the mask forms
                if (sp == SP_ICHIGO && zt > 0.0 && zt < 0.6) {
                    vec2 q2 = pcentre(fc);
                    float dx = (q2.x - bodyC.x) / (spriteH * 0.42);
                    float nf = hash21(vec2(floor(q2.x / (PX * 2.0)), floor(t * 16.0)));
                    float top = bodyC.y + spriteH * (0.1 + 0.45 * (1.0 - dx * dx)) * (0.55 + 0.9 * nf);
                    float env = smoothstep(0.0, 0.15, zt) * (1.0 - smoothstep(0.45, 0.6, zt));
                    float bot = bodyC.y - spriteH * 0.45;
                    if (abs(dx) < 1.0 && q2.y > bot && q2.y < top) {
                        float hgt = (q2.y - bot) / max(top - bot, 1.0);   // 0 at the feet, 1 at the tip
                        vec3 fcol = mix(vec3(0.05, 0.0, 0.03), vec3(0.55, 0.03, 0.1), smoothstep(0.35, 0.9, hgt));
                        if (q2.y > top - PX * 3.0) fcol = vec3(1.0, 0.2, 0.25);
                        col = mix(col, fcol, 0.9 * env);
                    }
                }
                // Naruto: two shadow clones pop out in smoke beside him for the Rasengan
                if (sp == SP_NARUTO && zt > 0.03 && zt < 0.62) {
                    for (int e = 1; e <= 2; e++) {
                        vec2 off = vec2(((e == 1) ? -1.0 : 1.0) * (spriteH * 0.5 + 10.0), 0.0);
                        if (zt > 0.06 && zt < 0.42) {
                            vec4 se = spriteAt(fr, k, fc, anchor + off, spx, flip);
                            col = mix(col, se.rgb * 0.9, se.a);
                        }
                        for (int w2 = 0; w2 < 2; w2++) {
                            float tp = (w2 == 0) ? zt - 0.03 : zt - 0.38;
                            if (tp < 0.0 || tp > 0.25) continue;
                            for (int i = 0; i < 5; i++) {
                                float ang = float(i) * 1.256 + float(e);
                                vec2 pp = bodyC + off + vec2(cos(ang), sin(ang)) * (6.0 + tp * 60.0);
                                col = mix(col, vec3(0.93, 0.93, 0.9), step(length(pcentre(fc) - pp), 6.0 + tp * 14.0) * (1.0 - tp / 0.25) * 0.85);
                            }
                        }
                    }
                }

                vec2 p = floor((fc - anchor) / spx);
                if (flip) p.x = -p.x - 1.0;
                vec4 s = spriteFrame(fr, k, p);
                if (S_GHOST[k] && s.a > 0.0) s.rgb = mix(s.rgb, vec3(0.75, 0.6, 1.0), 0.12 + 0.08 * sin(t * 3.0 + p.y * 0.6));
                if (hurt && a == A_HURT && s.a > 0.0) s.rgb = mix(s.rgb, vec3(1.0, 0.3, 0.3), 0.35 * step(0.5, fract(t * 8.0)));
                col = mix(col, s.rgb, s.a * alpha);

                // ghosts leave a ring of shadow where they vanish / appear
                if (S_GHOST[k] && hop && tk < HOP_T + 0.3) {
                    for (int e = 0; e < 2; e++) {
                        vec2 cpt = ((e == 0) ? A : B) + vec2(cx, spriteH * 0.45);
                        float te = (e == 0) ? tk : tk - HOP_T * 0.5;
                        if (te > 0.0 && te < 0.45) {
                            float rr = length(floor((fc - cpt) / PX) * PX);
                            float ring = 1.0 - smoothstep(PX, PX * 2.0, abs(rr - te * 160.0));
                            col = mix(col, vec3(0.55, 0.35, 0.85), ring * (1.0 - te / 0.45) * 0.8);
                        }
                    }
                }

                // sleep bubbles / song notes
                if (sleeping || (singing && IS_JIGGLY(k))) {
                    for (int i = 0; i < 3; i++) {
                        float ph = fract(t * 0.35 + float(i) / 3.0 + fk * 0.21);
                        vec2 zp = pos + vec2(hw * 0.2 + ph * 30.0 + float(i) * 4.0, spriteH * 0.8 + ph * 60.0 + lift);
                        float zs = floor(PX * (sleeping ? 0.9 + ph * 0.9 : 1.4));
                        float g = sleeping ? zGlyph(fc - zp, zs) : noteGlyph(fc - zp - vec2(hw * 0.5, 0.0), zs);
                        // with Darkrai around, everyone else has nightmares
                        vec3 gc = sleeping ? ((PARTY_HAS_DARKRAI && sp != SP_DARKRAI) ? vec3(0.9, 0.25, 0.32) : vec3(0.88, 0.94, 1.0)) : hsv(fract(ph + float(i) * 0.3), 0.4, 1.0);
                        col = mix(col, gc, g * min((1.0 - ph) * 1.6, 1.0));
                    }
                }

                vec2 feetP = pos + vec2(0.0, lift);
                vec2 bodyP = pos + vec2(0.0, lift + spriteH * 0.45);
                float face = flip ? -1.0 : 1.0;
                col = signature(col, sp, fc, feetP, bodyP, zt, fk * 17.0 + floor(t / 4.0) + iTimeCursorChange, face);
                if (hop && visible && tk < HOP_T + 0.5 && sp >= 100)
                    col = hopFx(col, sp, fc, A + vec2(cx, spriteH * 0.45), B + vec2(cx, spriteH * 0.45), 28.0 + 0.12 * dist, tk, iTimeCursorChange + fk);
                if (hop && visible && tk < HOP_T + 0.4 && !S_GHOST[k] && sp < 100 && sp != SP_PIKACHU && sp != SP_SNORLAX)
                    col = hopTrail(col, sp, fc, A + vec2(cx, spriteH * 0.45), B + vec2(cx, spriteH * 0.45), 28.0 + 0.12 * dist, tk, iTimeCursorChange + fk);

                // the "!" when Claude needs you
                if (needYou && k == 0) {
                    float bob = floor(abs(sin(t * 5.0)) * 2.0) * PX;
                    vec4 eb = alertBubble(floor((fc - pos - vec2(-9.0 * PX, spriteH + lift + 4.0 + bob)) / (PX * 2.0)));
                    col = mix(col, eb.rgb, eb.a);
                }

                // Claude working a while: energy gathers into the lead Pokémon
                if (PK_STATE >= 2 && PK_STATE <= 4 && k == 0) {
                    vec3 tcol = typeCol(sp);
                    for (int i = 0; i < 14; i++) {
                        if (PK_STATE == 2 && i >= 8) break;
                        float h = hash11(float(i) * 7.7 + 1.0);
                        float ph = fract(t * (0.35 + 0.25 * h) + h);
                        vec2 mp = bodyP + rot(h * 6.283 + ph * 2.0) * vec2(110.0 * (1.0 - ph), 0.0) * vec2(1.0, 0.6);
                        col = mix(col, mix(tcol, vec3(1.0), ph * 0.5), pdot(fc, mp, 1.0) * smoothstep(0.0, 0.3, ph) * 0.9);
                    }
                    float gd = length((pcentre(fc) - bodyP) * vec2(1.0, 1.3));
                    col += tcol * exp(-gd / 26.0) * 0.18 * (0.75 + 0.25 * sin(t * 5.0)) * bgMask;
                }

                // Pikachu (yellow) and Sasuke (Chidori blue): lightning tears along the hop
                if ((sp == SP_PIKACHU || sp == SP_SASUKE) && hop && visible && tk < HOP_T + 0.25) {
                    bool chidori = sp == SP_SASUKE;
                    vec2 a0 = A + vec2(cx, spriteH * 0.45);
                    vec2 b0 = pos + vec2(0.0, lift + spriteH * 0.45);
                    float fade = 1.0 - smoothstep(HOP_T * 0.6, HOP_T + 0.25, tk);
                    vec2 q = floor(fc / PX) * PX + PX * 0.5;
                    if (fade > 0.0) {
                        float md = boltDist(q, a0, b0, iTimeCursorChange * 13.1 + floor(t * 24.0));
                        col = mix(col, chidori ? vec3(0.45, 0.7, 1.0) : vec3(1.0, 0.86, 0.25), exp(-md / 9.0) * 0.55 * fade);
                        col = mix(col, chidori ? vec3(0.9, 0.96, 1.0) : vec3(1.0, 1.0, 0.92), (1.0 - smoothstep(PX * 0.6, PX * 1.4, md)) * fade);
                        if (chidori) {   // a second, thinner bolt braided around the first
                            float m2 = boltDist(q, a0, b0, iTimeCursorChange * 7.7 + floor(t * 30.0) + 3.0);
                            col = mix(col, vec3(0.75, 0.88, 1.0), (1.0 - smoothstep(PX * 0.3, PX, m2)) * fade * 0.8);
                        }
                    }
                }
                // Zoro: a sword-wind slash traces his jump arc, white edge over green
                if (sp == SP_ZORO && hop && visible && tk < HOP_T + 0.3) {
                    float arcH = 28.0 + 0.12 * dist;
                    float head = clamp(tk / HOP_T, 0.0, 1.0);            // where Zoro is along the arc
                    float tail = max(head - 0.6, 0.0) + max(tk - HOP_T, 0.0) / 0.3;   // the slash shortens after landing
                    vec2 q = floor(fc / PX) * PX + PX * 0.5;
                    float md = 1e9;
                    vec2 prev = mix(A, B, tail) + vec2(cx, sin(tail * PI) * arcH + spriteH * 0.5);
                    for (int j = 1; j <= 10; j++) {
                        float sj = mix(tail, head, float(j) / 10.0);
                        vec2 cur = mix(A, B, sj) + vec2(cx, sin(sj * PI) * arcH + spriteH * 0.5);
                        md = min(md, sdSeg(q, prev, cur));
                        prev = cur;
                    }
                    if (head > tail) {
                        col = mix(col, vec3(0.35, 0.85, 0.45), exp(-md / 7.0) * 0.45);
                        col = mix(col, vec3(1.0), 1.0 - smoothstep(PX * 0.4, PX * 1.2, md));
                    }
                }
            }
        }

        // sparks flying off the cursor while typing
        if (moved && !hop && tc < 0.28 && visible) {
            vec2 o = vec2(CUR.x, CUR.y + CUR.w * 0.5);
            for (int i = 0; i < 5; i++) {
                float sd = iTimeCursorChange * 3.3 + float(i) * 1.91;
                vec2 v = vec2(hash11(sd) - 0.25, hash11(sd + 4.2) * 1.4 - 0.2) * 260.0;
                vec2 p = o + v * tc + vec2(0.0, -900.0) * tc * tc;
                vec2 dd = floor((fc - floor(p / PX) * PX) / PX);
                if (dd == vec2(0.0)) {
                    float life = 1.0 - tc / 0.28;
                    col = mix(col, mix(vec3(1.0, 0.75, 0.1), vec3(1.0, 1.0, 0.8), hash11(sd + 9.0)), life);
                }
            }
        }
    }
#endif

#if SHOW_PIKA
    // ---- Claude finished: a beam of light comes down on the party -----------
    if (PK_STATE >= 6) {
        float pr = float(PK_STATE - 6) / 7.0;   // steps 0..1 over ~1.6s
        float env = (1.0 - smoothstep(0.55, 1.0, pr)) * (0.85 + 0.15 * sin(t * 40.0));
        float gap = PX * 3.0;
        vec2 B = (iCursorVisible != 0) ? vec2(CUR.x + max(CUR.z, 8.0), CUR.y) : vec2(iResolution.x - 18.0, 4.0);
        float partyW = 0.0;
        for (int k = 0; k < PARTY_N; k++) partyW += float(S_HALFW[k]) * 2.0 * S_PX[k] + gap;
        if (iCursorVisible == 0) B.x -= partyW;
        B.x = min(B.x + gap, iResolution.x - partyW - 4.0);
        vec2 c = B + vec2(partyW * 0.5, float(S_TOP[0]) * S_PX[0] * 0.5);
        vec3 tc = typeCol(S_SPECIES[0]);
        float w = max(partyW * 0.35, 24.0);
        float dx = abs(pcentre(fc).x - c.x);
        if (fc.y > c.y - 6.0) {
            col = mix(col, mix(tc, vec3(1.0), 0.65), (1.0 - smoothstep(w * 0.25, w, dx)) * env * 0.5);
            float sp = step(0.988, hash21(floor(vec2(fc.x / PX, (fc.y - t * 320.0) / PX))));
            col = mix(col, vec3(1.0), sp * step(dx, w * 1.4) * env);
        }
        if (PARTY_ELECTRIC && pr < 0.75) {
            vec2 q = pcentre(fc);
            for (int i = 0; i < 2; i++) {
                vec2 top = vec2(c.x + (hash11(floor(t * 8.0) + float(i) * 5.0) - 0.5) * 160.0, iResolution.y);
                float md = boltDist(q, top, c, floor(t * 12.0) * 3.3 + float(i) * 7.0);
                col = mix(col, vec3(1.0, 0.9, 0.35), exp(-md / 10.0) * 0.5);
                col = mix(col, vec3(1.0, 1.0, 0.92), 1.0 - smoothstep(PX * 0.6, PX * 1.6, md));
            }
        }
        if (pr < 0.15) col = mix(col, vec3(1.0), 0.06 * bgMask);
    }
#endif

#if SHOW_INTRO
    // ---- battle intro: a Poké Ball spins in, fills the screen, splits open --
    if (t < INTRO_T) {
        float blk = 6.0;
        vec2 q = (floor(fc / blk) + 0.5) * blk;
        vec2 c = iResolution.xy * 0.5;
        vec3 RED = vec3(0.91, 0.22, 0.19), WHITE = vec3(0.95, 0.95, 0.92), INK = vec3(0.07, 0.06, 0.08);
        vec3 ov = vec3(0.03, 0.03, 0.06);
        float cover = 1.0;
        if (t < 0.55) {
            // spin in, then zoom until the ball fills the window
            float grow = smoothstep(0.0, 0.25, t) * 60.0 + pow(smoothstep(0.30, 0.55, t), 3.0) * length(iResolution.xy);
            float ang = (1.0 - smoothstep(0.0, 0.32, t)) * 9.0;
            vec2 p = mat2(cos(ang), -sin(ang), sin(ang), cos(ang)) * (q - c);
            float r = length(p);
            float R = max(grow, 1.0);
            if (r < R) {
                ov = (p.y > 0.0) ? RED : WHITE;
                if (p.y > 0.0 && p.x > R * 0.35 && p.y > R * 0.2) ov *= 0.82;
                if (abs(p.y) < R * 0.08) ov = INK;
                if (r < R * 0.24) ov = INK;
                if (r < R * 0.16) ov = WHITE;
                if (r > R * 0.93) ov = INK;
            }
        } else {
            // the two halves slide apart; a white flash at the seam
            float k = smoothstep(0.55, INTRO_T, t);
            float gap = k * k * iResolution.y * 0.62;
            float y = q.y - c.y;
            if (abs(y) < gap) cover = 0.0;
            ov = (y > 0.0) ? RED : WHITE;
            float edge = abs(abs(y) - gap);
            if (edge < iResolution.y * 0.045) ov = INK;
            vec2 btn = q - c - vec2(0.0, sign(y) * gap);
            float br = length(btn);
            if (br < iResolution.y * 0.13) ov = INK;
            if (br < iResolution.y * 0.09) ov = WHITE;
            float flash = (1.0 - smoothstep(0.0, 0.25, t - 0.55)) * exp(-abs(y) / (gap + 30.0));
            col = mix(col, vec3(1.0), flash * (1.0 - cover));
        }
        col = mix(col, ov, cover);
    }
#endif

    if (G_LINEAR) col = toLinear(col);
    fragColor = vec4(col, base.a);
}
