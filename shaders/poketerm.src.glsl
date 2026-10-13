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
vec2 toTex(vec2 fc) { return vec2(fc.x, iResolution.y - fc.y) / iResolution.xy; }
vec4 tex(vec2 fc) { return texture(iChannel0, toTex(fc)); }
// cursor rect -> (left, bottom, width, height) in y-up pixels
vec4 cursorUp(vec4 c) { return vec4(c.x, iResolution.y - c.y, c.z, c.w); }

// Is the screen texture linear or sRGB-encoded? It depends on the renderer and
// its settings, so look at the top-left padding pixel (always background).
bool G_LINEAR = false;

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

// ---------------------------------------------------------------- main
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 fc = vec2(fragCoord.x, iResolution.y - fragCoord.y);
    vec4 CUR = cursorUp(iCurrentCursor), PREV = cursorUp(iPreviousCursor);
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
        float period = 19.0;
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
    }
#endif

#if SHOW_GRASS
    // ---- tall grass -----------------------------------------------------
    if (fc.y < GRASS_H) {
        float wind = sin(t * 1.3 + fc.x * 0.004) * 0.6 + sin(t * 0.7 + fc.x * 0.011) * 0.4;
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
            partyW += float(S_HALFW[k]) * 2.0 * PX + gap;
            maxTop = max(maxTop, float(S_TOP[k]) * PX);
        }
        vec2 A = vec2(PREV.x + max(PREV.z, 8.0), PREV.y);
        vec2 B = vec2(CUR.x + cellW, CUR.y);
        if (!visible) A = B = vec2(iResolution.x - partyW - 18.0, 4.0);
        A.x = min(A.x + gap, iResolution.x - partyW - 4.0);
        B.x = min(B.x + gap, iResolution.x - partyW - 4.0);
        vec2 d = B - A;
        float dist = length(d);
        bool moved = dist > 0.5;
        bool hop = abs(d.y) > 1.0 || abs(d.x) > cellW * 6.0;

        vec2 lo = min(A, B) - vec2(60.0, 40.0);
        vec2 hi = max(A, B) + vec2(partyW + 60.0, maxTop + 140.0 + 0.12 * dist);
        bool near = all(greaterThan(fc, lo)) && all(lessThan(fc, hi));
        if (near) {
            bool sleeping = tc > SLEEP_AFTER || (!visible && tc > 4.0);
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
                float hw = float(S_HALFW[k]) * PX;
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
                vec2 anchor = pos - vec2(0.0, float(S_GROUND[k]) * PX - lift);

                // soft shadow on the ground
                vec2 sq = (floor((fc - pos) / PX) * PX) / vec2(hw * max(0.75 - lift * 0.004, 0.3), PX * 1.5);
                if (dot(sq, sq) < 1.0)
                    col = mix(col, vec3(0.0), 0.30 * alpha);

                vec2 p = floor((fc - anchor) / PX);
                if (flip) p.x = -p.x - 1.0;
                vec4 s = spriteFrame(fr, k, p);
                if (S_GHOST[k] && s.a > 0.0) s.rgb = mix(s.rgb, vec3(0.75, 0.6, 1.0), 0.12 + 0.08 * sin(t * 3.0 + p.y * 0.6));
                if (hurt && a == A_HURT && s.a > 0.0) s.rgb = mix(s.rgb, vec3(1.0, 0.3, 0.3), 0.35 * step(0.5, fract(t * 8.0)));
                col = mix(col, s.rgb, s.a * alpha);

                float spriteH = float(S_TOP[k]) * PX;
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
                        vec3 gc = sleeping ? vec3(0.88, 0.94, 1.0) : hsv(fract(ph + float(i) * 0.3), 0.4, 1.0);
                        col = mix(col, gc, g * min((1.0 - ph) * 1.6, 1.0));
                    }
                }

                // Pikachu: lightning along the hop, then a Thunderbolt crackle on landing
                if (IS_PIKACHU(k) && hop && visible && tk < HOP_T + 0.6) {
                    vec2 a0 = A + vec2(cx, spriteH * 0.45);
                    vec2 b0 = pos + vec2(0.0, lift + spriteH * 0.45);
                    float fade = 1.0 - smoothstep(HOP_T * 0.6, HOP_T + 0.25, tk);
                    vec2 q = floor(fc / PX) * PX + PX * 0.5;
                    if (fade > 0.0) {
                        float md = boltDist(q, a0, b0, iTimeCursorChange * 13.1 + floor(t * 24.0));
                        col = mix(col, vec3(1.0, 0.86, 0.25), exp(-md / 9.0) * 0.55 * fade);
                        col = mix(col, vec3(1.0, 1.0, 0.92), (1.0 - smoothstep(PX * 0.6, PX * 1.4, md)) * fade);
                    }
                    float zt = tk - HOP_T;
                    if (zt > 0.0 && zt < 0.6) {
                        // short arcs crackling out of the cheeks
                        for (int i = 0; i < 3; i++) {
                            float ang = hash11(floor(t * 16.0) + float(i) * 3.7 + iTimeCursorChange) * 6.283;
                            vec2 tip = b0 + vec2(cos(ang), sin(ang) * 0.7 + 0.3) * (36.0 + 20.0 * hash11(float(i) + floor(t * 16.0)));
                            float md = boltDist(q, b0, tip, floor(t * 30.0) + float(i) * 9.1);
                            float f = (1.0 - zt / 0.6);
                            col = mix(col, vec3(1.0, 0.9, 0.3), exp(-md / 6.0) * 0.5 * f);
                            col = mix(col, vec3(1.0, 1.0, 0.9), (1.0 - smoothstep(PX * 0.4, PX * 1.2, md)) * f);
                        }
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
