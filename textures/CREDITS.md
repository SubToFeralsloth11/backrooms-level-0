# Texture Credits

All maps are seamless (tile in X and Y). Normal maps use the **OpenGL (Y+)** convention, which Godot expects.
Roughness/metallic maps are single-channel grayscale PNGs.

| Set | Files | Source | Author | License | Resolution | One repeat covers |
|---|---|---|---|---|---|---|
| Carpet | `carpet_albedo.png`, `carpet_normal.png`, `carpet_roughness.png` | ambientCG **Carpet011** (2K-PNG) — https://ambientcg.com/view?id=Carpet011 | Lennart Demes (ambientCG) | CC0 1.0 | 2048² | **1.0 m × 1.0 m** (estimated; ambientCG publishes no physical size for this asset — based on ~5 mm pile tufts) |
| Wallpaper | `wallpaper_albedo.png`, `wallpaper_normal.png`, `wallpaper_roughness.png` | Procedurally generated for this project (numpy/PIL) | BACKROOMS project | CC0 1.0 (original work) | 1024² | **1.0 m × 1.0 m** |
| Ceiling | `ceiling_albedo.png`, `ceiling_normal.png`, `ceiling_roughness.png` | ambientCG **OfficeCeiling001** (2K-PNG) — https://ambientcg.com/view?id=OfficeCeiling001 | Lennart Demes (ambientCG) | CC0 1.0 | 2048² | **6 × 6 drop-ceiling tiles per repeat → 3.6 m × 3.6 m** with 0.6 m tiles (source's native scale is 3.85 m ≈ 0.64 m tiles) |
| Concrete | `concrete_albedo.png`, `concrete_normal.png`, `concrete_roughness.png` | Poly Haven **dirty_concrete** (2k) — https://polyhaven.com/a/dirty_concrete | Rob Tuytel | CC0 1.0 | 2048² | **3.0 m × 3.0 m** |
| Metal (painted worn steel, door) | `metal_albedo.png`, `metal_normal.png`, `metal_roughness.png`, `metal_metallic.png` | Poly Haven **green_metal_rust** (2k) — https://polyhaven.com/a/green_metal_rust | Rob Tuytel | CC0 1.0 | 2048² | **1.0 m × 1.0 m** |

## UV scaling

`uv1_scale = surface_size_in_meters / meters_per_repeat`. For example, a 2.4 m-high wall segment 4 m long with wallpaper → `uv1_scale = Vector3(4.0, 2.4, 1)`.
Ceiling: one repeat holds exactly 6 × 6 tiles, so to align with a 0.6 m grid use `meters_per_repeat = 3.6`, and offset the UVs so a T-bar line falls on a grid line. The grid lines sit at the texture's edges (u, v = 0).

## Modifications

- **Carpet albedo**: recolored to the Backrooms damp mustard/tan (mean ≈ `#b1985d`, close to the target `#b59a5a`). The source's per-pixel luminance detail is kept, with slight desaturation, faint low-frequency periodic grime, and hue drift so it reads as slightly dirty. The normal and roughness maps are unmodified from the source.
- **Wallpaper**: original procedural texture. It has a pale-yellow base (mean ≈ `#c8b769`), vertical two-tone stripes with pinstripes (6.4 cm pitch), a faint repeating diamond motif in each stripe, anisotropic paper-fiber noise, and faint low-frequency discoloration and tide-mark water stains. The normal map is derived from the height field with wrap-around gradients. Roughness is 0.74–0.88. All noise is FFT-periodic, so the texture tiles seamlessly.
- **Ceiling albedo**: the grayscale source is tinted to a slightly yellowed off-white (mean ≈ `#ded6ba`), with faint periodic aging blotches. The normal and roughness maps are unmodified.
- **Concrete**: Poly Haven 2k maps re-saved as PNG. The colour is unmodified.
- **Metal**: Poly Haven 2k maps re-saved as PNG. `metal_metallic.png` is the blue channel of Poly Haven's ARM map. It is near-zero everywhere (max 21/255) because paint and rust are dielectric, so you can also just set `metallic = 0`.
