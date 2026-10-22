"""Ink-coverage regression test for background-clip:text letterform clipping.

control.png : the same page with extra horizontal padding on <em> (nothing can be clipped)
test.png    : the page as shipped
Only the <em> glyphs are painted in either image, so any ink present in the control and
absent from the test is glyph paint that the shipped CSS never draws.

usage: python inkdiff.py control.png test.png geometry.json dsf
"""
import json
import sys

from PIL import Image


def lum(px):
    return (0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2]) / 255.0


def ink_mask(img, thresh):
    w, h = img.size
    px = img.convert("RGB").load()
    return [[lum(px[x, y]) > thresh for x in range(w)] for y in range(h)]


def auto_thresh(img):
    """Background here is the navy hero (~0.18) while the cyan/white glyphs are > 0.4,
    so calibrate from the crop median instead of a magic constant."""
    px = list(img.convert("RGB").get_flattened_data() if hasattr(img, "get_flattened_data") else img.convert("RGB").getdata())
    vals = sorted(lum(p) for p in px)
    med = vals[len(vals) // 2]
    return max(0.30, med + 0.11), med


def edge(prof, w, min_run=2):
    l = next((x for x in range(w) if prof[x] >= min_run), None)
    r = next((x for x in range(w - 1, -1, -1) if prof[x] >= min_run), None)
    return l, r


def main():
    ctrl_path, test_path, geom_path, dsf = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    geom = json.load(open(geom_path, encoding="utf-8"))
    em = geom["em"]
    pad = 34  # css px of margin around the box
    x0 = max(0, int((em["l"] - pad) * dsf))
    y0 = max(0, int((em["t"] - pad) * dsf))
    x1 = int((em["r"] + pad) * dsf)
    y1 = int((em["b"] + pad) * dsf)

    c = Image.open(ctrl_path).crop((x0, y0, x1, y1))
    t = Image.open(test_path).crop((x0, y0, x1, y1))
    if c.size != t.size:
        print(f"SIZE MISMATCH {c.size} vs {t.size}")
        return 1
    w, h = c.size
    thresh, med = auto_thresh(c)
    print(f"auto threshold        {thresh:.3f}  (crop background median luminance {med:.3f})")
    mc, mt = ink_mask(c, thresh), ink_mask(t, thresh)
    prof_c = [sum(1 for y in range(h) if mc[y][x]) for x in range(w)]
    prof_t = [sum(1 for y in range(h) if mt[y][x]) for x in range(w)]
    cl, cr = edge(prof_c, w)
    tl, tr = edge(prof_t, w)

    css = lambda col: x0 / dsf + col / dsf
    box_l, box_r = em["l"], em["r"]

    missing_in = missing_out = 0
    out_cols = []
    for x in range(w):
        outside = css(x) < box_l - 0.6 or css(x) > box_r + 0.6
        for y in range(h):
            if mc[y][x] and not mt[y][x]:
                if outside:
                    missing_out += 1
                    if x not in out_cols:
                        out_cols.append(x)
                else:
                    missing_in += 1

    print(f"em content box        x {box_l:.1f} .. {box_r:.1f} css  (padL={geom['padL']} padR={geom['padR']} "
          f"marL={geom['marL']} marR={geom['marR']})")
    print(f"letter-spacing        {geom['ls']}   font-size {geom['fs']}")
    print(f"clip / fill           {geom['clip']} / {geom['fill']}")
    print(f"control bg            {geom['bg']}")
    print(f"ink span control      {css(cl):.2f} .. {css(cr):.2f} css   ({prof_c.count(0)} empty columns of {w})")
    print(f"ink span test         {css(tl):.2f} .. {css(tr):.2f} css")
    print(f"overhang left         control {box_l - css(cl):+.2f} css   test {box_l - css(tl):+.2f} css")
    print(f"overhang right        control {css(cr) - box_r:+.2f} css   test {css(tr) - box_r:+.2f} css")
    print(f"MISSING ink inside    {missing_in}")
    print(f"MISSING ink OUTSIDE   {missing_out}   <-- real glyph paint lost past the padding box")
    if out_cols:
        print(f"missing columns css   {[round(css(x), 2) for x in out_cols[:20]]}")
    verdict = "CLIPPED" if missing_out > 40 else "OK"
    print(f"VERDICT               {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())