# Generated web material textures

Three material base-color images created on 2026-09-07 with the built-in image generation tool, following the user's image2 request. They are material images for the existing 3D geometry. No external downloaded images were used as generation references. Each image was requested independently; the armor received one targeted refinement.

| File | Use |
| --- | --- |
| `armor-painted-v1.webp` | Neutral painted-steel wear, tinted by the tank's existing paint color |
| `asphalt-v1.webp` | Road surfaces and asphalt roof felt; lane markings remain geometry |
| `brick-wall-v1.webp` | Warehouse and industrial masonry walls |

The files use sRGB base color. They deliberately do not reuse normal or roughness maps from unrelated photographed materials. Existing material roughness and actual scene lighting remain responsible for the surface response. Other terrain, roofs and props retain their photographed materials. Images are requested as tileable surfaces; generated seams are visually checked in the game, rather than claimed mathematically seamless.

Original PNG outputs are retained in the local workspace under `outputs/image2-texture-originals/` and the tool's generated-image directory. The committed WebP files preserve the generated dimensions and composition; packaging only converts to WebP at quality 90, with no resizing, repainting or color adjustments. `provenance.json` records sizes, hashes and full prompts. Assets are imported only by the web renderer.

## Generation prompts

### armor

Use case: photorealistic-natural. Asset type: a production-ready square seamless base-color texture for the existing 3D armored tank models in Iron Embers, a realistic industrial tank battle browser game. Generate ONE image, 1024x1024. Orthographic straight-on macro photograph / material scan of weathered military painted steel. Desaturated light warm grey paint, subtle cast-steel micrograin, tiny paint chips revealing darker gunmetal, sparse fine directional scuffs, restrained dried dust and very small dark oil stains. This neutral texture will be multiplied by olive, sand or red vehicle paint in the shader, so keep its average brightness medium-light and saturation very low. Surface detail at approximately a 1 metre physical scale, readable but understated. Uniform flat diffuse lighting, no directional highlights, no cast shadows, no vignette. The entire image is material edge-to-edge and must tile seamlessly on all four edges. No tank illustration, no panels, no seams or weld lines, no bolts, no labels, no text, no numbers, no logo, no watermark, no border, no perspective, no collage. It must work as a reusable albedo texture on many separately modeled curved and angled armor plates.

### asphalt

Use case: photorealistic-natural. Asset type: production-ready seamless base-color ground texture for a realistic industrial tank battle browser game, coordinated with desaturated weathered armor and old factory masonry. Generate ONE square 1024x1024 image. True top-down orthographic scanned asphalt surface, approximately 5 metres across: aged medium-dark charcoal asphalt, densely packed fine grey aggregate, a few irregular narrow repaired cracks, scattered very subtle dusty patches and a small amount of worn aggregate exposed by heavy vehicles. A believable drivable military industrial road. Keep large-scale brightness even, natural fine-grain detail, restrained contrast, broad areas suitable for vehicle silhouettes to remain legible. Flat diffuse overcast scan lighting; no highlights, no baked shadows, no vignette. Seamless edge-to-edge tiling horizontally and vertically. No lane markings or painted lines, no curbs, no potholes, no craters, no vehicles, no buildings, no grass, no discrete props, no text, no symbols, no perspective, no grid, no border, no collage. Pure color/albedo map, not a rendered scene.

### brick

Use case: photorealistic-natural. Asset type: a square seamless base-color brick-wall texture for realistic industrial warehouse and factory buildings in a tank battle browser game. Generate ONE 1024x1024 image. Straight-on orthographic photogrammetry-style texture of old muted russet-brown industrial fired-clay bricks laid in a believable staggered running bond, 12 brick courses vertically, with aged grey-beige recessed mortar, subtle varied brick colors, fine chips and worn porous surfaces, light dusty grime and very sparse pale lime deposits. Restrained saturation, medium-light exposure so the game's colored wall materials remain readable. Credible factory masonry, not ruins. All four image edges tile seamlessly, with continuous courses and the half-brick pattern aligned at the boundaries. Flat neutral diffuse scan illumination, no directional shading, no cast shadows, no highlights, no vignette. The entire image is wall material. No windows, no doors, no cracks wider than mortar, no ivy, no bullet holes, no signage, no text, no logos, no perspective, no border, no collage. Pure albedo/base color usable on modeled 3D walls, not a photograph of a whole building.

### Armor refinement

Use case: precise-object-edit. Edit this material texture to read unmistakably as painted military rolled steel. Keep its square format, neutral light warm-grey overall color, even illumination and seamless edge-to-edge tiling. Replace the porous, sandy mineral appearance with a mostly smooth matte enamel paint film over hard steel, very fine straight abrasion scratches and sparse small angular flakes of chipped paint revealing dark bluish-grey steel beneath. Weathering must stay understated and cover less than 12 percent of the area; long hairline scratches should be more characteristic than pitting. Keep medium-light values so the game can tint the material olive or sand. No rust-orange washes, no deep holes, no concrete pores, no bolts, no panel borders, no welded seams, no logos or text, no shadows or specular lighting. Pure reusable base-color texture covering the whole image, not a rendered tank.

