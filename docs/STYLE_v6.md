# v6 style study: "Wired to Fish" (demo, @ForkedPush) → our island

The two reference frames are from a vertical phone capture of the *Wired to Fish* demo:
a girl walking along a beach with a fishing rod, seen from a high camera. This note is what
I read off those frames before building v6, and how each point maps onto our Godot scene.
Image 3 (our v5 boy) is the counter-example.

## 1. What the reference is made of

### Camera and framing
- **High three-quarter top-down camera**, pitch roughly **55–65°** below the horizon, slightly
  telephoto (little perspective convergence: palm trunks and the character's legs stay almost
  parallel). The character occupies ~1/6–1/5 of the frame height on a portrait screen, so the
  ground plane dominates the image; the horizon is never visible.
- The camera trails the character from behind/above and stays level (no roll), with slow,
  damped follow.

### Character (proportions, modeling, rig)
- **Proportions are realistic and slender**: ~6.5 heads tall. Head is small relative to the
  shoulders, neck visible, narrow waist, **long thin legs** (crotch at ~0.48 of the height),
  arms reaching mid-thigh, small hands and feet. Nothing is "chibi": there is no oversized
  head, no stubby limbs and no rounded toy torso.
- It is a **properly modeled, skinned low/mid-poly mesh** (continuous surface, smooth normals,
  deformation at shoulders/hips/knees), driven by a **skeleton** with authored clips — not
  rigid primitives. Silhouettes bend smoothly at joints; the shorts hem and tank top follow
  the body.
- **Clothes are simple but well-shaped shells** over the body: a fitted tank top with
  narrow straps, loose teal shorts ending mid-thigh with a slightly flared hem, flip-flops
  (thin sole + thong strap), and a **woven basket backpack** (a cylinder with a weave texture
  and two straps). Every garment has a readable edge (hem, armhole, strap), which is what
  makes it look modeled rather than painted on.
- **Hair has volume**: a separate, chunky mesh that sits above the scalp (bun/strands),
  reading as a mass with its own light and shadow side.
- **Shading is soft and smooth**: gentle wrap-around diffuse, low contrast between lit and
  shadow sides, a faint warm bounce from the sand on the underside, no hard toon bands and no
  outlines. Colors are flat albedo per material (skin, cloth, hair) with very little texture
  detail — detail comes from shape and lighting.
- **Animation**: a natural human gait — heel strike, rolling over the foot, knee bend on
  contact, pelvis drop and rotation, counter-rotating shoulders, arms swinging opposite to the
  legs with relaxed elbows, a light vertical bob. Feet stay planted while in contact.

### Light and atmosphere
- **One warm, low-ish sun** (elevation ~35–45°) from the upper-left of the frame, casting
  **long, soft-edged shadows** toward the lower-right. Shadow color is a cool, desaturated
  blue-grey, never black; contact shadows under feet are darker.
- **Ambient is bright and cool** (sky fill), so shadow sides stay readable.
- **Slight haze / softness** over everything: the image has lifted blacks, compressed contrast
  and a light bloom — partly the phone capture, partly a deliberate muted grade.
- **Muted, desaturated pastel palette**: beige sand, sage/jade water, pale skin, teal and
  off-white cloth. Saturation stays low; the brightest values are the foam.

### Sand
- Muted warm beige with **fine grain** (tiny light/dark speckles) and very low-frequency
  tonal variation.
- **Footprints**: small, soft, slightly darker dents trailing the character.
- **Wet band**: a darker, slightly cooler and smoother strip of sand just above the waterline,
  a few decimetres wide, following the shore curve.

### Water and shoreline
- **Milky jade-green water**, opaque-looking (you don't see a detailed seabed), **lighter and
  more turquoise at the shore**, gradating to a deeper sage/teal further out. Very little
  specular; the surface reads through color and soft gradients rather than reflections.
- **A single crisp, thin, wavy white foam line** on the shore — thin (a few cm on screen),
  bright, irregular in width, slowly sliding up and down the sand. Behind it a faint second
  line, and **scattered foam flecks/dots** drifting on the water near the shore.
- The water edge has a slightly translucent rim where it meets the wet sand.

### Props
- **Palm trunks with ringed segments**: each segment is a slightly flared ring with a darker
  groove between rings, warm grey-brown, smooth shading; leaves are simple dark-green fronds.
- Props are low-poly but cleanly shaded; nothing has outlines.

## 2. Why v5 looked off

- v5 used a chibi boy (~3 heads) built from rigid primitives with procedural IK — the
  opposite of the reference's slender skinned character.
- The v5 sea was a saturated tropical turquoise with several foam bands, lace and caustics;
  the reference is milky, muted and graphic, with one crisp foam line.
- The v5 camera was lower and more cinematic; the reference is high and calm.

## 3. How v6 implements it

| Reference trait | v6 implementation |
| --- | --- |
| Slender ~6.5-head teen, skinned mesh | MakeHuman/MPFB2 CC0 base (male, ~13 y), low-poly proxy + one subdivision, ~12k tris, scaled to 1.25 m |
| Real skeleton + clips | MPFB "game_engine" skeleton (53 bones); clips authored in Blender by script (`art/boy/`), exported as GLB; Godot `AnimationTree` mixes them |
| Natural gait, no sliding | Walk/run cycles with contact–down–passing–up keys, heel strike, toe-off, pelvis drop/rotation and counter-rotating shoulders; playback is phase-driven from the real ground speed (stride-matched) |
| Simple modeled clothes | Shell meshes offset from the body: white tank top, open red vest, yellow shorts with flared hem, flip-flops; separate volumetric hair and a woven straw hat |
| Soft smooth shading | Custom character shader: wrap diffuse, soft terminator, cool ambient, warm ground bounce, faint rim; procedural face drawn in shader (blink / sleep / smile) |
| High camera | Explore camera pitch ~58°, longer focal length |
| Low sun, long soft shadows, haze | Lower sun, soft PCF shadows, cool shadow tint, light fog and a muted grade |
| Sand grain, footprints, wet band | Terrain shader: grain noise, darker wet band driven by the wash, footprint decals stamped where the feet plant |
| Milky jade water, crisp foam line, flecks | Water shader rewritten: opaque-ish jade gradient by depth, one thin wavy foam line + faint secondary line, scattered flecks |
| Ringed palm trunks | Palm trunks rebuilt as stacked flared rings with dark grooves |
