#!/usr/bin/env python3
"""Build the bundled countries.json for the Globle app from Natural Earth data.

Source: Natural Earth 1:50m Admin 0 – Countries (public domain).
We keep every country/territory so the game works as a learning tool, mark which
entries are real sovereign countries (eligible to be the daily mystery country),
expand abbreviated names, fix ISO-code quirks, and emit compact rounded geometry.

Usage:  python3 tools/build_countries.py
Output: Globle/Resources/countries.json
"""
import json, os, urllib.request

NE_URL = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
          "master/geojson/ne_50m_admin_0_countries.geojson")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Globle", "Resources", "countries.json")
CACHE = "/tmp/ne_50m.json"
COORD_DECIMALS = 3  # ~110 m precision — plenty for a globe, keeps microstates intact

# Friendlier display names than Natural Earth's NAME field.
NAME_OVERRIDE = {
    "USA": "United States", "GBR": "United Kingdom",
    "COD": "Democratic Republic of the Congo", "COG": "Republic of the Congo",
    "CAF": "Central African Republic", "DOM": "Dominican Republic",
    "GNQ": "Equatorial Guinea", "SSD": "South Sudan", "ESH": "Western Sahara",
    "SLB": "Solomon Islands", "BIH": "Bosnia and Herzegovina", "FLK": "Falkland Islands",
    "ATF": "French Southern Territories", "CYN": "Northern Cyprus", "SWZ": "Eswatini",
    "CZE": "Czechia", "CIV": "Ivory Coast", "MMR": "Myanmar", "CPV": "Cape Verde",
    "TLS": "Timor-Leste", "MKD": "North Macedonia", "FSM": "Micronesia",
    "VCT": "Saint Vincent and the Grenadines", "KNA": "Saint Kitts and Nevis",
    "ATG": "Antigua and Barbuda", "STP": "Sao Tome and Principe",
    "VAT": "Vatican City", "BRN": "Brunei", "LAO": "Laos", "SYR": "Syria",
    "HMD": "Heard and McDonald Islands",
}
# Extra lowercase search aliases by ISO A3 id.
ALIAS_EXTRA = {
    "USA": ["usa", "us", "america", "united states of america", "the states"],
    "GBR": ["uk", "britain", "great britain", "england", "u k"],
    "ARE": ["uae", "emirates", "u a e"], "RUS": ["russian federation"],
    "KOR": ["south korea", "korea", "republic of korea"],
    "PRK": ["north korea", "dprk"], "NLD": ["holland", "the netherlands"],
    "CZE": ["czech republic"], "MMR": ["burma"], "SWZ": ["swaziland"],
    "CPV": ["cape verde"], "CIV": ["ivory coast", "cote divoire"],
    "TUR": ["turkey", "turkiye"], "MKD": ["macedonia"], "TLS": ["east timor"],
    "COD": ["congo", "drc", "dr congo", "democratic republic of congo"],
    "COG": ["congo", "congo brazzaville", "republic of congo"],
    "FSM": ["federated states of micronesia"], "LAO": ["laos"],
    "VAT": ["vatican", "holy see"], "VCT": ["st vincent", "saint vincent"],
    "KNA": ["st kitts", "saint kitts"], "STP": ["sao tome"],
}


def load_features():
    path = CACHE if os.path.exists(CACHE) else None
    if path is None:
        print("Downloading", NE_URL)
        data = urllib.request.urlopen(NE_URL, timeout=120).read()
        with open(CACHE, "wb") as f:
            f.write(data)
        path = CACHE
    return json.load(open(path))["features"]


def iso2_for(p):
    for k in ("ISO_A2", "ISO_A2_EH", "WB_A2"):
        v = p.get(k)
        if v and v != "-99" and len(str(v)) == 2 and str(v).isalpha():
            return str(v).upper()
    return ""


def norm_token(s):
    if not s:
        return None
    s = str(s).strip().lower()
    return s if s and s != "-99" else None


def round_ring(ring):
    out, last = [], None
    for pt in ring:
        c = [round(pt[0], COORD_DECIMALS), round(pt[1], COORD_DECIMALS)]
        if c != last:
            out.append(c)
            last = c
    return out if len(out) >= 4 else None


def to_multipolygon(geom):
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    out = []
    for poly in polys:
        rings = [r for r in (round_ring(ring) for ring in poly) if r]
        if rings:
            out.append(rings)
    return out


def main():
    feats = load_features()
    records = []
    for f in feats:
        p = f["properties"]
        adm = p.get("ADM0_A3") or p.get("ISO_A3") or p.get("NAME")
        name = NAME_OVERRIDE.get(adm) or p.get("NAME")
        if "." in (name or ""):
            name = p.get("NAME_LONG") or name
        geom = to_multipolygon(f["geometry"])
        lon, lat = p.get("LABEL_X"), p.get("LABEL_Y")
        if lon is None or lat is None:
            biggest = max((r for poly in geom for r in poly), key=len, default=None)
            if biggest:
                lon = sum(x for x, _ in biggest) / len(biggest)
                lat = sum(y for _, y in biggest) / len(biggest)
            else:
                lon, lat = 0.0, 0.0
        pop = int(p.get("POP_EST") or 0)
        # A real sovereign country governs itself (its sovereign is itself).
        sovereign = (p.get("SOVEREIGNT") == p.get("ADMIN"))
        is_target = sovereign and pop > 0 and name != "Antarctica"
        toks = set()
        for k in ("NAME", "NAME_LONG", "NAME_EN", "ADMIN", "BRK_NAME",
                  "FORMAL_EN", "ABBREV", "SOVEREIGNT", "GEOUNIT"):
            t = norm_token(p.get(k))
            if t:
                toks.add(t)
                toks.add(t.replace(".", ""))
        toks.add(name.lower())
        toks.update(ALIAS_EXTRA.get(adm, []))
        if iso2_for(p):
            toks.add(iso2_for(p).lower())
        toks.discard("")
        records.append({
            "id": adm, "name": name, "iso2": iso2_for(p),
            "lon": round(float(lon), 3), "lat": round(float(lat), 3),
            "pop": pop, "continent": p.get("CONTINENT") or "",
            "sovereign": sovereign, "target": is_target,
            "aliases": sorted(toks), "geometry": geom,
        })

    # De-duplicate ids defensively (Natural Earth occasionally repeats -99 codes).
    seen, unique = set(), []
    for r in sorted(records, key=lambda r: r["name"]):
        rid = r["id"]
        if rid in seen or rid in ("-99", None):
            rid = r["id"] = (rid or "X") + "_" + r["name"][:3].upper()
        seen.add(rid)
        unique.append(r)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(unique, open(OUT, "w"), separators=(",", ":"), ensure_ascii=False)
    sz = os.path.getsize(OUT)
    targets = sum(1 for r in unique if r["target"])
    print(f"Wrote {len(unique)} entries ({targets} daily-target countries) -> {OUT}")
    print(f"File size: {sz/1024:.0f} KB")
    leftover_dots = [r["name"] for r in unique if "." in r["name"]]
    if leftover_dots:
        print("Names still containing '.':", leftover_dots)


if __name__ == "__main__":
    main()
