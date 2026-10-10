# yomado image assets

Generated with the built-in `image_gen` tool. These are original AI-generated concept illustrations, not screenshots of a local desktop or evidence of tested monitor-off operation.

- `yomado-logo.png`: transparent primary logo, using a window-and-crescent symbol and a lowercase wordmark.
- `yomado-usage.png`: usage illustration with the final lowercase logo.

## Logo prompt

```text
Use case: logo-brand
Asset type: reusable primary logo lockup for an open-source macOS utility; horizontal 3:1 composition with a truly transparent background.
Primary request: Design a considered, distinctive logo for "yomado", a virtual workspace for graphical agents. The Japanese-inspired name evokes a window lit at night. Create ONE finished logo, not a presentation of alternatives.
Design: At the left, a compact geometric symbol combining a softly rounded window frame with a crescent-shaped negative-space aperture, suggesting a night window that remains available. The symbol must read at small app-icon scale, using a bold continuous silhouette and one clear cutout, with balanced optical weight. Subtly echo the branching rhythm of a lowercase y in the negative space only if it improves the simple mark. No monitor stand. At the right, a bespoke lowercase wordmark with humanist geometric letterforms, refined spacing, distinctive rounded y descender, open counters and calm proportions. It should feel like a crafted developer-tool identity, not plain text typed in a default font.
Text (verbatim): "yomado". ALL SIX LETTERS LOWERCASE. Never capitalize the initial y.
Color: very dark ink navy wordmark with a restrained cyan-blue window symbol. Flat colors, minimal, crisp solid vector-like edges. No gradients, glow, shadows or 3D.
Composition: single horizontal icon + wordmark lockup, icon height balanced with lowercase letterforms and descender, generous transparent margin, polished optical alignment. The brand name is the main visual element.
Constraints: transparent alpha background, no background rectangle, no tagline, no extra words or captions, no watermark, no robot, no stars/sparkles, no generic AI brain or circuit icon, no stock-looking monitor icon. Clean and reproducible, original visual identity.
```

## Usage illustration prompt

The initial composition was generated with this prompt. The title was subsequently replaced with the lowercase logo using the edit prompt below.

```text
Use case: illustration-story
Asset type: wide GitHub README usage-example hero image, approximately 16:9 landscape.
Primary request: Create a polished, easy-to-understand conceptual illustration for Yomado, a native macOS virtual display for graphical AI agents. Explain the intended scenario: a Mac remains awake and a graphical agent can use a virtual desktop while the physical monitors are switched off.
Scene and composition: clean editorial technology illustration on a deep midnight navy background, restrained warm moonlight and soft cyan accents, generous margins, crisp shapes, subtle grain, sophisticated luminous depth. Two real physical monitors sit together on the LEFT with completely dark matte screens, switched off, no lit content. A small silver desktop Mac-like computer below them has a tiny active status light. On the RIGHT, spatially separate and clearly beyond both physical monitors, a large FLOATING virtual-desktop panel has no stand or physical bezel, just a thin softly glowing cyan dotted outline. A subtle dotted link connects the awake computer to this virtual panel. Do not position the virtual panel between the physical monitors.
The virtual desktop contains TWO elegant simplified illustrative application windows: one labeled "Blender" with an orange low-poly garment mannequin and 3D mesh viewport, the other labeled "Garment design" with a pale fabric jacket on a mannequin and simple flat 2D sewing patterns. Use readable illustrative content, not a detailed or supposedly authentic screenshot. Include one clear agent cursor in the virtual desktop. Keep UI chrome abstract and minimal, no fabricated operational metrics.
Typography: refined modern sans serif, strong visual hierarchy, large readable text, few labels only.
Text (verbatim): top-left headline "Yomado", subtitle below "A virtual workspace for graphical agents". Label below the two dark monitors "Physical displays off". Label near computer "Mac stays awake". Label above floating panel "Virtual display". Small label within floating panel "Agent workspace". Window labels "Blender" and "Garment design". Tiny restrained bottom-right footer "Concept illustration".
Constraints: This is a usage CONCEPT, not proof of a successful test. No separate OS or security sandbox imagery, no shield, no isolated mouse/keyboard implication. No people, robot mascot, phone, clouds, extra hardware, watermarks, power savings percentages, fake app status badges or claims. No real screenshots, usernames, email, local file paths, project names or machine identifiers. Do not add a third physical monitor. Make the picture visually appealing and the main physical-versus-virtual relationship instantly legible.
```

## Final usage illustration edit prompt

Reference 1: the initial concept illustration. Reference 2: `yomado-logo.png`.

```text
Use case: compositing
Asset type: final GitHub README usage illustration.
Input images: Image 1 is the edit target, the full Yomado usage concept illustration. Image 2 is the exact approved-design reference for the newly designed lowercase yomado window-and-crescent logo.
Primary request: Replace ONLY the large top-left "Yomado" headline in Image 1 with the logo lockup from Image 2. Preserve the custom window-and-crescent symbol, wordmark letter shapes, lowercase y and all six letters exactly "yomado". For contrast on the dark scene, make the wordmark soft white and keep the symbol cyan-blue. Size it elegantly into the existing upper-left brand area, aligned with the subtitle, without crowding the subtitle or touching the physical monitors. Do not make the logo taller than the original title area.
Invariants: keep Image 1's original wide aspect ratio, scene, two switched-off physical monitors together on the left, awake silver Mac, floating virtual workspace on the right, garment images, cursor, lighting, labels, readable subtitle and tiny "Concept illustration" footer. Keep the virtual display to the right of both physical monitors. Do not add more devices or change the scene.
Text: brand logo must read "yomado" all lowercase. Existing subtitle remains "A virtual workspace for graphical agents". Retain all other existing labels as in Image 1.
Constraints: This remains a concept illustration, not an operational screenshot. No uppercase brand name, no added captions or watermark, no added independent OS/sandbox symbols. The logo should look intentionally typeset and naturally integrated, not like a dark rectangle pasted over the original. Remove the old title cleanly.
```
