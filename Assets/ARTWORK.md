# Artwork

The mascot illustrations were generated with the built-in `image_gen` tool. Runtime assets are stored here and copied into the app. External reference images are not redistributed. See [NOTICE](../NOTICE) for the distinction between the project license and third-party names and character designs.

The current library has 279 illustrated poses across 31 collections. Procedural movement brings each pose to life; this is not a claim of 279 independently drawn multi-frame animations. Provenance manifests record project-relative asset paths and SHA-256 checksums, without machine-local generator paths.

- `deepseek-chan-soft-atlas.png`: softer four-pose character.
- `deepseek-chan-dance-atlas.png`: four dance poses.
- `deepseek-chan-daily-atlas.png`: nine daily actions.
- `companion-icon-dark.png`: full-bleed dark mascot icon, converted to ICNS during packaging.

The initial character reference and original prompt are in `CHARACTER-PROMPT.txt`.

## Soft character prompt

Edit this transparent 2x2 sprite atlas into a MUCH cuter, softer, rounder super-deformed DeepSeek-chan desktop mascot. Keep exactly four equal square cells with the same actions and same consistent identity/outfit. Identity: human anime girl with blue hair fading to cyan, whale fin ears and tail, white frilly maid headband, blue and white fully modest maid outfit. Make head very large, plush round cheeks, small mouth, huge sparkling eyes, pink blush, tiny compact body with short round arms and legs, approx 2 heads tall, fluffy rounded hair shapes, gentle painterly cel shading, indigo linework, softer blue palette. This is the cute Chinese meme DeepSeek-chan whale-maid, not an animal. Top-left happy idle clasped hands; top-right playful puffed cheeks with little wooden mallet raised to ring the same blue desk bell; bottom-left mallet tapping bell, tiny gold sparkle; bottom-right eyes closed with cheek resting on hands. Each character centered inside their quadrant with 7% safety padding, same scale and head/feet anchoring. Do not put any part across the quadrant boundary. No text, no background, no white blocks, genuine alpha transparency. Preserve the exact quadrant order for runtime animation.

## Dance prompt

Create a transparent 2x2 four-frame DANCE sprite atlas of the exact same super-cute DeepSeek-chan from this reference atlas. Use the same round face, blue-to-cyan hair, whale-fin ears, white frilly headband, fully clothed navy and white maid outfit and blue tail. No mallet, bell, text, borders or background. This atlas is for a looping cheerful little dance, not idle: frame 0 top-left both hands raised beside her cheeks, feet together, joyful open eyes; frame 1 top-right arms swaying to viewer left and right leg lifted, little wink; frame 2 bottom-left both hands overhead making a little heart, feet together, happy smile; frame 3 bottom-right arms swaying to viewer right and left leg lifted, closed-eye smile. Every figure must stay fully within its own exact square quadrant with at least 10 percent empty padding all around. Identical character size, matching head center and foot baseline, approximately two-heads-tall proportions, same framing as the reference. Friendly playful movements, fluffy rounded silhouette, pink cheeks, glossy blue eyes, polished clean anime cel shading. Genuine alpha transparency; no white background or baked checkerboard.

## Daily action prompt

Create one transparent 3-by-3 sprite atlas, exactly NINE equal square cells, of the same adorable DeepSeek-chan whale-maid from the reference. This is a desktop pet with varied everyday cute actions. Use consistent exact same round head, huge sparkling blue eyes, blue-to-cyan fluffy hair, whale fin ears, white frilly headband, fully clothed navy-white maid outfit, short legs, blue whale tail. Super-deformed two-head-tall proportions. Each character MUST remain within its own cell with 8 percent clear safety padding, identical scale and foot baseline, clean separated quadrants. Read row-major:
0 top-left: calm happy standing, hands clasped in front, open eyes.
1 top-middle: cheerful wave with one hand, one eye winking.
2 top-right: tiny cat-paw pose with both fists near cheeks, tilted head, puffed cheeks.
3 middle-left: stretching both arms overhead, eyes closed, little yawning mouth.
4 middle-center: sitting happily with a bowl of white rice and spoon, round cheeks chewing.
5 middle-right: curled up asleep hugging her blue whale tail, peaceful face.
6 bottom-left: shy peek with both hands hiding mouth and large eyes looking sideways.
7 bottom-middle: twirling 3/4 body pose with skirt and tail gently flared, joyful eyes.
8 bottom-right: ecstatic happy pose with both hands near face, blush and three tiny pink hearts.
No writing, no labels, no borders, no scene, no large cast shadows. Soft clean anime cel shading, rounded squishy silhouette, cozy lively expressions. Genuine transparent alpha background, no white or checkerboard. Preserve the character design from reference, do not turn her into an animal.

## Icon prompt

Create a polished macOS app icon for DeepSeek-chan eye-break desktop companion. A simple incredibly cute soft 3D toy mascot head, inspired by the minimal tactile friendliness of Grok Bot's app icon, not its actual logo. Square composition. A deep midnight-navy rounded-square tile fills the entire canvas right to every edge, transparent only outside the rounded corners; absolutely no white border, no white background, no outer padding or inset frame. Center one large rounded blue whale-maid GIRL head with simplified soft blue hair, tiny fin ear tufts, a small white scalloped maid headband, huge two glossy dark navy oval eyes with a subtle highlight, pink blush cheeks, tiny happy mouth. The face is a rounded pale periwinkle sphere. Minimal bold silhouette readable at 32px, no full body, no detailed anime drawing, no text or letters, no logos, no tiny accessories. Plush sculpted vinyl material, soft studio shading, hair gradients from royal blue to cyan at the lower edges, a slightly tilted friendly head filling 82 percent of the tile. Premium playful modern Mac app icon, cute restrained expression, strong contrast, no visual clutter. Do not add an external drop shadow or a white outline.


## v1.4 — complete 108-pose library

Generated with the built-in `image_gen` tool on 2026-10-17, using the existing `deepseek-chan-daily-atlas.png` as the character/style reference. Eleven new transparent 3×3 atlases provide 99 different illustrated actions, plus the original nine = 108. The outputs were copied unchanged into `Assets/actions/`; generated alpha is preserved. Asset checksums, generator, references and destinations are in `Assets/actions/provenance.json`; the full exact prompt for every atlas is in `Assets/actions/prompts.json`.

Collections: Greetings, Playtime, Snack time, Sleepy time, Little stretches, Little feelings, Music & dance, Desk buddy, Tiny adventures, Care & comfort, Happy occasions. Each has nine separately illustrated poses. The existing Everyday collection adds nine.

`atlas-layout.json` specifies each sprite's display bounds. `atlas-cutouts.json` contains nine small display crop notches where adjacent silhouettes interleave across row boundaries (for example a preceding character's shoe above the balloon pose). These are runtime clipping metadata; the source PNGs are untouched. All 108 production crops were rendered by `Tests/RenderActions.swift` and visually inspected. Visual acceptance renders are local under `.build/qa-actions-*.png`.

Each pose has a procedural motion loop; the ten reusable profiles are not counted as additional actions. Multi-frame dance and bell-tapping sequences remain separate. The library is not a claim of 108 independently drawn multi-frame animations.


## v1.7 — 252-pose library

Generated 144 new poses with built-in `image_gen`, using the original daily atlas as the identity/style reference. Sixteen 3×3 transparent PNG atlases are saved unchanged as `Assets/actions/actions-extra-*.png`. Total: 252 illustrated poses in 28 collections. Exact prompts and row-major pose/name/dialogue/motion definitions: `Assets/actions/expansion-252.json`. Asset checksums, generator, references and final destinations: `Assets/actions/provenance-252.json`.

Display regions are computed from transparent separation paths between figures in `scripts/derive-expansion-crops.py`, with reviewed ownership corrections for the café/cozy curls and science/game props. This updates only `atlas-layout.json` and `atlas-regions.json`; it does not resave or edit image pixels. The original twelve collections retain their existing clipping. Each of the sixteen added category sheets was rendered through the production SwiftUI view and visually reviewed, with the four corrected sheets rerendered and reviewed again.

These are 144 new illustrations with procedural motion, not 144 newly drawn multi-frame animations. The same images also form 48 authored three-beat proactive stories.

## Halloween set · v1.8

27 new full-body witch poses in three transparent 3×3 atlases: `actions/actions-halloween-tricks.png`, `actions/actions-halloween-treats.png`, `actions/actions-halloween-moonlight.png`. Generated with the built-in image_gen tool using `actions-extra-silly.png` for character identity; treats and moonlight additionally reference the approved tricks costume. Purple witch hat with pumpkin bow, bat cape, orange waist bow, original blue hair/whale tail and white frills.

Exact final prompts and pose/line plans: [halloween-prompts.json](actions/halloween-prompts.json). Asset checksums, generator and references: [halloween-provenance.json](actions/halloween-provenance.json). All files copied unchanged from generator output, 1254×1254 RGBA with actual transparency. The crop helper reads alpha and writes display-region JSON only. All 27 production sprite crops reviewed in `.build/qa-actions-halloween-*.png`; no ownership correction was needed for these atlases.

## v1.8.1 · Native macOS icon packaging

Original mascot portrait `companion-icon-dark.png` is unchanged. The release uses `CompanionNative.icon/icon.json` and its `Assets/mascot.png` (1024px format conversion), exported with [Apple Icon Composer](https://developer.apple.com/icon-composer/) 1.2, macOS / Default, 1024×1024 at scale 1. Export is `companion-icon-macos.png`. `scripts/PackageIcon.swift` places that native contour in a 100/1024 transparent inset at each ICNS resolution. The installed system icon was read through NSWorkspace and visually compared against the old icon: the thick gray enclosing tile is gone. No new AI artwork was generated for this packaging fix.
