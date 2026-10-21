"""Shared render resolution. RENDER_SCALE (default 1) multiplies the base 1200x675
frame; 1 reproduces the shipped v1 pipeline exactly. RENDER_OUT (default "v1") is the
folder under public/carRenders that publish.py/check.py use, so a higher-resolution
set lives beside v1 (frames are cached forever by URL, never overwrite them)."""
import os
SCALE = float(os.environ.get("RENDER_SCALE", "1"))
OUT = os.environ.get("RENDER_OUT", "v1")
W, H = round(1200 * SCALE), round(675 * SCALE)
RES = f"{W}x{H}"
RES_ARG = f"res={RES}"
PX_PER_M = 208.5 * SCALE
PAD = round(12 * SCALE)
# Main color frames get extra samples when larger (the rest are masks/layers).
MAIN_SAMPLES = 48 if SCALE <= 1 else round(48 * (1 + SCALE) / 2 * 1.0 + 16)
