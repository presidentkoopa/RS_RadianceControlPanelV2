//===========================================================================
//
// [BB] Death-Ping -- a direct transcription of GITD's radar ring.
//
// This is not "inspired by" it and not a reconstruction of how it looked.
// The maths below is the original's, line for line, out of
// GlowInTheDark.pk3:shaders/glsl/main.fp lines 1026-1031 -- the wgType 3
// branch, the shortest in the family:
//
//     float ringR = wgMask.y * wgSp.w;
//     float thick = wgSp.w * 0.10;
//     wgAdd = wgCol * (1.0 - smoothstep(0.0, thick, abs(wgDist - ringR)));
//
// WHAT CHANGED AND WHY IT IS ONLY THIS. The original works in world space,
// measuring wgDist = length(pixelpos.xz - wgSp.xy) from a glow spot's
// centre. Here the same fragment is already in the quad's own space, -1..1
// on both axes, so on a SQUARE quad whose half-extent is the ring's full
// reach, wgDist / wgSp.w IS length(p), ringR / wgSp.w IS progress, and
// thick / wgSp.w IS 0.10. Dividing all three arguments of a smoothstep by
// the same positive radius changes nothing. Every constant is untouched.
//
// SQUARE DIMENSIONS ARE THE CALLER'S CONTRACT. A rectangular quad draws an
// elliptical ping, which the original could not draw -- the exact inverse
// of WG13's lozenge, where circular was the caller error.
//
// THE OUTER GATE IS PART OF THE LOOK. The original's whole dispatch sits
// inside `if (wgDist < wgSp.w)`, so the ring's leading skirt is cut DEAD at
// the full radius as progress approaches 1 -- the ring dies at the edge,
// not politely beyond it. `nR >= 1.0` below is that same cut in quad units,
// not tidiness.
//
// ONE SYMMETRIC FALLOFF. Brightness peaks exactly on the circle and falls
// over a tenth of the reach on BOTH sides. No separate core and halo terms,
// no hard edges. The band does not thin as it expands: thickness is a
// fraction of the REACH, not of the current radius. That is the original's
// choice and it is what makes a big ping read heavy.
//
// THE FADE IS NOT HERE, because it was never in the shader. The original's
// script dimmed the emitted colour by (1 - t) each tic
// (GITD_FX_DeathPing.Tick01, gitd3_deathfx.zs line 461); the driver dims
// uObjectColor the same way. A shader-side fade would be an approximation
// wearing a convenience's clothes.
//
// PROGRESS RIDES uAddColor.r, exactly as WG13's does. The original packed
// it into its glow spot's wgMask.y; the billboard path packs bb->progress
// into bbGlow's red byte in hw_sprites.cpp. The .gba channels carried the
// original's packed colour and here carry nothing -- colour arrives as
// uObjectColor. No max() floor on progress: the original used wgMask.y raw
// in this branch (unlike wgType 13's max(., 0.05)), so progress 0 is a lit
// dot at the centre, which is the first frame of a detonation.
//
//===========================================================================

vec4 ProcessTexel()
{
	// Quad space, y up -- the original's (pixelpos.xz - wgSp.xy) / wgSp.w.
	vec2 p = vec2(vTexCoord.s * 2.0 - 1.0, 1.0 - vTexCoord.t * 2.0);

	// uAddColor.r is progress, raw. wgMask.y.
	float nProg = uAddColor.r;

	// The original, divided through by wgSp.w:
	//   wgDist          -> nR
	//   ringR           -> nProg
	//   thick           -> 0.10
	float nR = length(p);
	float nband = 1.0 - smoothstep(0.0, 0.10, abs(nR - nProg));

	// The outer gate: `if (wgDist < wgSp.w)` wrapped the whole effect, so
	// everything at or past the full reach is nothing. Same cut, same place.
	if (nR >= 1.0) nband = 0.0;

	vec3 col = uObjectColor.rgb * nband;

	// Alpha follows the band, so the ping is a ring rather than a square.
	return vec4(col, nband * uObjectColor.a);
}
