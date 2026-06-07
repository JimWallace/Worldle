import Foundation

// Build Globle/Resources/countries.json from Natural Earth 1:50m Admin 0 – Countries
// (public domain). Keeps every country/territory, marks sovereign states (eligible
// daily targets), expands abbreviated names, fixes ISO-code quirks, and emits compact
// rounded geometry. Swift port of the original build_countries.py.

let neURL = URL(string: "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
                + "master/geojson/ne_50m_admin_0_countries.geojson")!
let coordDecimals = 3.0

// Friendlier display names than Natural Earth's NAME field.
let nameOverride: [String: String] = [
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
]
// Extra lowercase search aliases by ISO A3 id.
let aliasExtra: [String: [String]] = [
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
]

struct OutCountry: Encodable {
    let id, name, iso2: String
    let lon, lat: Double
    let pop: Int
    let continent: String
    let sovereign, target: Bool
    let aliases: [String]
    let geometry: [[[[Double]]]]
}

func projectDir() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // build-countries
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // GlobleTools
        .deletingLastPathComponent()  // Globle (project dir)
}

func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

func normToken(_ s: Any?) -> String? {
    guard let s = s as? String else { return nil }
    let t = s.trimmingCharacters(in: .whitespaces).lowercased()
    return (t.isEmpty || t == "-99") ? nil : t
}

func iso2(_ p: [String: Any]) -> String {
    for key in ["ISO_A2", "ISO_A2_EH", "WB_A2"] {
        if let v = p[key] as? String, v != "-99", v.count == 2,
           v.allSatisfy({ $0.isLetter }) {
            return v.uppercased()
        }
    }
    return ""
}

func roundRing(_ pts: [Any]) -> [[Double]]? {
    var out: [[Double]] = []
    var last: [Double]?
    for pt in pts {
        guard let pair = pt as? [Any], pair.count >= 2,
              let x = (pair[0] as? NSNumber)?.doubleValue,
              let y = (pair[1] as? NSNumber)?.doubleValue else { continue }
        let c = [round3(x), round3(y)]
        if c != last { out.append(c); last = c }
    }
    return out.count >= 4 ? out : nil
}

func toMultiPolygon(_ geom: [String: Any]) -> [[[[Double]]]] {
    let type = geom["type"] as? String ?? ""
    let polys: [Any] = (type == "MultiPolygon")
        ? (geom["coordinates"] as? [Any] ?? [])
        : [geom["coordinates"] as Any]
    var out: [[[[Double]]]] = []
    for poly in polys {
        guard let rings = poly as? [Any] else { continue }
        let ringsOut = rings.compactMap { ($0 as? [Any]).flatMap(roundRing) }
        if !ringsOut.isEmpty { out.append(ringsOut) }
    }
    return out
}

// MARK: - Run

print("Downloading \(neURL.lastPathComponent) …")
let data = try Data(contentsOf: neURL)
let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let features = root["features"] as! [[String: Any]]

var records: [OutCountry] = []
for f in features {
    let p = f["properties"] as! [String: Any]
    let adm = (p["ADM0_A3"] as? String) ?? (p["ISO_A3"] as? String) ?? (p["NAME"] as? String) ?? "X"
    var name = nameOverride[adm] ?? (p["NAME"] as? String) ?? adm
    if name.contains(".") { name = (p["NAME_LONG"] as? String) ?? name }

    let geom = toMultiPolygon(f["geometry"] as! [String: Any])
    var lon = (p["LABEL_X"] as? NSNumber)?.doubleValue
    var lat = (p["LABEL_Y"] as? NSNumber)?.doubleValue
    if lon == nil || lat == nil {
        let biggest = geom.flatMap { $0 }.max(by: { $0.count < $1.count })
        if let biggest, !biggest.isEmpty {
            lon = biggest.map { $0[0] }.reduce(0, +) / Double(biggest.count)
            lat = biggest.map { $0[1] }.reduce(0, +) / Double(biggest.count)
        } else { lon = 0; lat = 0 }
    }

    let pop = (p["POP_EST"] as? NSNumber)?.intValue ?? 0
    let sovereign = (p["SOVEREIGNT"] as? String) == (p["ADMIN"] as? String)
    let isTarget = sovereign && pop > 0 && name != "Antarctica"

    var tokens = Set<String>()
    for key in ["NAME", "NAME_LONG", "NAME_EN", "ADMIN", "BRK_NAME", "FORMAL_EN", "ABBREV", "SOVEREIGNT", "GEOUNIT"] {
        if let t = normToken(p[key]) {
            tokens.insert(t)
            tokens.insert(t.replacingOccurrences(of: ".", with: ""))
        }
    }
    tokens.insert(name.lowercased())
    aliasExtra[adm]?.forEach { tokens.insert($0) }
    let code = iso2(p)
    if !code.isEmpty { tokens.insert(code.lowercased()) }
    tokens.remove("")

    records.append(OutCountry(id: adm, name: name, iso2: code,
                              lon: round3(lon!), lat: round3(lat!), pop: pop,
                              continent: (p["CONTINENT"] as? String) ?? "",
                              sovereign: sovereign, target: isTarget,
                              aliases: tokens.sorted(), geometry: geom))
}

// Defensive de-duplication of ids, then sort by name.
var seen = Set<String>()
records = records.sorted { $0.name < $1.name }.map { rec in
    var rec = rec
    if seen.contains(rec.id) || rec.id == "-99" {
        rec = OutCountry(id: rec.id + "_" + String(rec.name.prefix(3)).uppercased(),
                         name: rec.name, iso2: rec.iso2, lon: rec.lon, lat: rec.lat,
                         pop: rec.pop, continent: rec.continent, sovereign: rec.sovereign,
                         target: rec.target, aliases: rec.aliases, geometry: rec.geometry)
    }
    seen.insert(rec.id)
    return rec
}

let out = projectDir().appendingPathComponent("Globle/Resources/countries.json")
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try encoder.encode(records).write(to: out)

let targets = records.filter { $0.target }.count
let sizeKB = (try Data(contentsOf: out)).count / 1024
print("Wrote \(records.count) entries (\(targets) daily-target countries) -> \(out.path)")
print("File size: \(sizeKB) KB")
let leftoverDots = records.filter { $0.name.contains(".") }.map(\.name)
if !leftoverDots.isEmpty { print("Names still containing '.':", leftoverDots) }
