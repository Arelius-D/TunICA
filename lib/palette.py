#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - the diagram palette, in OKLCH."""
import math

FILL_L, FILL_C = 0.94, 0.045
STROKE_L, STROKE_C = 0.58, 0.140

STROKE_WIDTH = 1.5

TONE_HUES = (
    ("toneBlue", 250),
    ("toneAmber", 75),
    ("toneMint", 150),
    ("toneRose", 20),
    ("toneIndigo", 290),
    ("toneTeal", 195),
)

NEUTRAL_NAME = "toneNeutral"
NEUTRAL_HUE = 250
NEUTRAL_C = 0.004
NEUTRAL_STROKE_C = 0.016


def _oklch(lightness: float, chroma: float, hue: int) -> str:
    """One OKLCH colour, converted to sRGB hex. Oklab conversion after Björn Ottosson."""
    hue_rad = math.radians(hue)
    a = chroma * math.cos(hue_rad)
    b = chroma * math.sin(hue_rad)

    l_ = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3

    linear = (
        4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
        -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
        -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_,
    )

    channels = []
    for value in linear:
        encoded = 12.92 * value if value <= 0.0031308 else 1.055 * (value ** (1 / 2.4)) - 0.055
        channels.append(round(max(0.0, min(1.0, encoded)) * 255))
    return "#{:02x}{:02x}{:02x}".format(*channels)


def tone_names() -> list[str]:
    return [name for name, _ in TONE_HUES]


def classdefs() -> list[str]:
    lines = [
        f"    classDef {NEUTRAL_NAME} "
        f"fill:{_oklch(FILL_L, NEUTRAL_C, NEUTRAL_HUE)},"
        f"stroke:{_oklch(STROKE_L, NEUTRAL_STROKE_C, NEUTRAL_HUE)},"
        f"stroke-width:{STROKE_WIDTH}"
    ]
    for name, hue in TONE_HUES:
        lines.append(
            f"    classDef {name} "
            f"fill:{_oklch(FILL_L, FILL_C, hue)},"
            f"stroke:{_oklch(STROKE_L, STROKE_C, hue)},"
            f"stroke-width:{STROKE_WIDTH}"
        )
    return lines