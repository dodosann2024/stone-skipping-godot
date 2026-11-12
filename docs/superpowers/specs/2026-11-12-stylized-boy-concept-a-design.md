# v22 Full Stylized Boy — Concept A (approved)

## Intent
Rebuild the **whole** boy (head, body, hands, legs, clothes) as one Nintendo / Animal-Crossing soft stylized 3D character matching `art/boy/concept_A.jpg`. No MakeHuman body + bolted cartoon head.

## Targets
- ~4 heads tall; big round head; short natural neck; small rounded torso; short soft limbs; chubby hands; small feet
- Warm peach skin, soft light-pink blush; big dark-brown eyes with white sclera + highlights; thin brows; tiny button nose; small closed smile
- Soft dark-brown chunky bangs; straw hat + red band tipped back (face readable); red vest + 3 gold buttons; yellow shorts with cream flower pattern; brown strap sandals
- Soft PBR / smooth surfaces; same game_engine bone names; rebake clips; hat physics kept; game cam 390×844 shows eyes+smile day/night

## Approach (chosen)
1. Keep **game_engine bone name hierarchy** (create via MPFB rig, then **retarget bone lengths** to chibi proportions) so `boy.gd` / hat IK / clips stay compatible.
2. **Delete** the MH body/eyes meshes; build a **new unified stylized mesh** (body + limbs + hands + feet) + dedicated stylized head/hair/eyes sized to the same head unit.
3. Build clothes as soft stylized shells/props for the new body (vest+buttons, patterned shorts, brown sandals), not MH offset clothes.
4. Rebake all clips; shorten gait strides for short legs; tip hat + lower `ex_pitch` so the default camera reads the face.

## Out of scope
Merging PR #18; realistic pores/skin detail; changing gameplay systems beyond character art / camera defaults.
