"""Minimal SVG document builder used by every generator. Paths only, no text, no rasters."""

from __future__ import annotations

import os
from xml.sax.saxutils import quoteattr

from . import geom
from .tokens import INK, MATERIALS


class Doc:
    def __init__(self, w: float, h: float, title: str, x0: float = 0, y0: float = 0):
        self.w, self.h, self.x0, self.y0 = w, h, x0, y0
        self.title = title
        self.defs: list[str] = []
        self.body: list[str] = []
        self._ids = 0
        self._grad_cache: dict[tuple, str] = {}

    # -- defs -------------------------------------------------------------
    def _id(self, prefix: str) -> str:
        self._ids += 1
        return f"{prefix}{self._ids}"

    def linear(self, stops, x1, y1, x2, y2) -> str:
        """stops: list of (offset 0..1, '#rrggbb', opacity). Returns 'url(#id)'."""
        key = ("lin", tuple(stops), round(x1, 2), round(y1, 2), round(x2, 2), round(y2, 2))
        if key in self._grad_cache:
            return self._grad_cache[key]
        gid = self._id("g")
        st = "".join(
            f'<stop offset="{o:.3f}" stop-color="{c}"' + (f' stop-opacity="{a:.3f}"' if a < 1 else "") + "/>"
            for o, c, a in stops
        )
        self.defs.append(
            f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{x1:.2f}" y1="{y1:.2f}" '
            f'x2="{x2:.2f}" y2="{y2:.2f}">{st}</linearGradient>'
        )
        url = f"url(#{gid})"
        self._grad_cache[key] = url
        return url

    def radial(self, stops, cx, cy, r, fx=None, fy=None, ellipse=None) -> str:
        """Radial gradient. ellipse=(rx, ry) makes an elliptical gradient centred at (cx, cy) (r ignored)."""
        key = ("rad", tuple(stops), round(cx, 2), round(cy, 2), round(r, 2), fx, fy, ellipse)
        if key in self._grad_cache:
            return self._grad_cache[key]
        gid = self._id("r")
        st = "".join(
            f'<stop offset="{o:.3f}" stop-color="{c}"' + (f' stop-opacity="{a:.3f}"' if a < 1 else "") + "/>"
            for o, c, a in stops
        )
        extra = ""
        if fx is not None:
            extra = f' fx="{fx:.2f}" fy="{fy:.2f}"'
        if ellipse:
            extra += f' gradientTransform="translate({cx:.2f} {cy:.2f}) scale({ellipse[0]:.2f} {ellipse[1]:.2f})"'
            cx, cy, r = 0.0, 0.0, 1.0
        self.defs.append(
            f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{cx:.2f}" cy="{cy:.2f}" '
            f'r="{r:.2f}"{extra}>{st}</radialGradient>'
        )
        url = f"url(#{gid})"
        self._grad_cache[key] = url
        return url

    # -- drawing ----------------------------------------------------------
    def path(self, g, fill: str, opacity: float = 1.0, simplify: float = 0.02):
        d = geom.to_d(g, simplify=simplify)
        if not d:
            return
        op = f' fill-opacity="{opacity:.3f}"' if opacity < 1 else ""
        self.body.append(f'<path fill={quoteattr(fill)}{op} fill-rule="evenodd" d="{d}"/>')

    def comment(self, text: str):
        self.body.append(f"<!-- {text} -->")

    # -- composite styles ---------------------------------------------------
    def keyline(self, g, width: float = 2.0, color: str = INK, opacity: float = 1.0):
        self.path(geom.grow(g, width), color, opacity)

    def plate(self, g, material: str, bevel: float = 2.0, face_grad: bool = True, lit_thr: float = 0.30,
              face_override: str | None = None):
        """Draw a bevelled metal/enamel plate: highlight facets, base facets, shade facets, face."""
        hi, base, lo = MATERIALS[material]
        if bevel > 0:
            f = geom.bevel(g, bevel, lit_thr=lit_thr)
            self.path(f["hi"], hi)
            self.path(f["mid"], base)
            self.path(f["lo"], lo)
            face = f["face"]
        else:
            face = g
        if face_override:
            self.path(face, face_override)
        elif face_grad:
            x0, y0, x1, y1 = g.bounds
            fill = self.linear([(0, _mix(base, hi, 0.22), 1), (1, _mix(base, lo, 0.18), 1)], 0, y0, 0, y1)
            self.path(face, fill)
        else:
            self.path(face, base)
        return face

    def flat(self, g, material: str, tone: int = 1):
        self.path(g, MATERIALS[material][tone])

    def cast_shadow(self, motif, clip, dx=1.2, dy=1.4, color: str = INK, opacity: float = 0.55):
        sh = geom.diff(geom.inter(geom.T(motif, dx, dy), clip), motif)
        self.path(sh, color, opacity)

    def inlay(self, motif, material: str, clip, bevel: float = 1.2, shadow=(1.2, 1.4), shadow_opacity=0.55,
              face_grad=True):
        """Raised motif on a plate face: drop shade then bevelled motif."""
        if shadow:
            self.cast_shadow(motif, clip, shadow[0], shadow[1], opacity=shadow_opacity)
        return self.plate(motif, material, bevel=bevel, face_grad=face_grad)

    def engrave(self, motif, plate_material: str, clip, depth=1.0, recess: str = INK):
        """Recessed motif cut into a plate: dark recess floor plus a lit lip on the lower-right edge
        (light comes from the top-left, so the far wall of the cut catches it)."""
        hi = MATERIALS[plate_material][0]
        lip = geom.diff(geom.inter(geom.T(motif, depth, depth), clip), motif)
        self.path(lip, hi)
        self.path(motif, recess)

    # -- output -------------------------------------------------------------
    def svg(self) -> str:
        head = (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{_n(self.x0)} {_n(self.y0)} {_n(self.w)} {_n(self.h)}" '
            f'width="{_n(self.w)}" height="{_n(self.h)}">'
        )
        parts = [head, f"<title>{self.title}</title>"]
        if self.defs:
            parts.append("<defs>" + "".join(self.defs) + "</defs>")
        parts.extend(self.body)
        parts.append("</svg>")
        return "\n".join(parts) + "\n"

    def save(self, path: str):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = self.svg()
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(data)
        return len(data.encode("utf-8"))


def _n(v: float) -> str:
    return f"{v:g}"


def _mix(a: str, b: str, t: float) -> str:
    a = a.lstrip("#")
    b = b.lstrip("#")
    ca = [int(a[i : i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i : i + 2], 16) for i in (0, 2, 4)]
    c = [round(ca[i] + (cb[i] - ca[i]) * t) for i in range(3)]
    return "#" + "".join(f"{v:02X}" for v in c)


mix = _mix
