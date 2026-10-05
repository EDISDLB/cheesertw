"""Fixed 3/4 'quarter view' camera used for every physical-object icon (currencies, consumables...).

Camera: yaw 22 deg (object turned so its front-right corner faces the viewer), elevation 38 deg,
orthographic. Light: from the top-left-front. Object faces are flat-shaded into the three tones of
their material (top = highlight-leaning base gradient, lit side = base, unlit side = shade).
"""

from __future__ import annotations

import math

from shapely import affinity
from shapely.geometry import Polygon

YAW = math.radians(22.0)
ELEV = math.radians(38.0)
LIGHT = (-0.55, 0.75, 0.37)  # world-space direction towards the light


def _rot(p):
    x, y, z = p
    c, s = math.cos(YAW), math.sin(YAW)
    return (x * c + z * s, y, -x * s + z * c)


def project(p):
    x, y, z = _rot(p)
    return (x, -(y * math.cos(ELEV) - z * math.sin(ELEV)))


def facing(normal) -> float:
    """>0 when a face with this world normal is visible."""
    nx, ny, nz = _rot(normal)
    return ny * math.sin(ELEV) + nz * math.cos(ELEV)


def lambert(normal) -> float:
    l = math.sqrt(sum(v * v for v in LIGHT))
    return sum(n * li / l for n, li in zip(normal, LIGHT))


def face_poly(points3d) -> Polygon:
    return Polygon([project(p) for p in points3d]).buffer(0)


def plane_affine(y: float):
    """Affine (shapely order a,b,d,e,xoff,yoff) mapping (u, v) on the horizontal plane at height y
    (u = world x, v = world z, i.e. v grows toward the viewer) to screen coordinates."""
    c, s = math.cos(YAW), math.sin(YAW)
    se, ce = math.sin(ELEV), math.cos(ELEV)
    # screen x = u*c + v*s ; screen y = -(y*ce - (-u*s + v*c)*se) = -u*s*se + v*c*se - y*ce
    return [c, s, -s * se, c * se, 0.0, -y * ce]


def on_plane(geom2d, y: float):
    return affinity.affine_transform(geom2d, plane_affine(y))


def prism(base_pts_xz, y0: float, y1: float, top_scale=None):
    """Extrude a CCW-in-xz polygon from y0 to y1. top_scale optionally shrinks the top face
    (sx, sz) around the origin for tapered solids like ingots. Returns list of
    (kind, world_normal, screen_polygon, depth) for visible faces, back to front."""
    n = len(base_pts_xz)
    tsx, tsz = top_scale or (1.0, 1.0)
    bot = [(x, y0, z) for x, z in base_pts_xz]
    top = [(x * tsx, y1, z * tsz) for x, z in base_pts_xz]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        quad = [bot[i], bot[j], top[j], top[i]]
        # normal from cross product of edges
        ax, ay, az = (quad[1][k] - quad[0][k] for k in range(3))
        bx, by, bz = (quad[3][k] - quad[0][k] for k in range(3))
        nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1
        nrm = (nx / ln, ny / ln, nz / ln)
        # make sure the normal points outward (away from the centroid)
        cx = sum(p[0] for p in quad) / 4
        cz = sum(p[2] for p in quad) / 4
        if nrm[0] * cx + nrm[2] * cz < 0:
            nrm = (-nrm[0], -nrm[1], -nrm[2])
        if facing(nrm) > 1e-3:
            depth = _rot((cx, 0, cz))[2]
            faces.append(("side", nrm, face_poly(quad), depth))
    faces.sort(key=lambda f: f[3])
    faces.append(("top", (0, 1, 0), face_poly(top), 1e9))
    return faces
