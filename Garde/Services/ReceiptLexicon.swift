import Foundation

/// Grocery receipt shorthand → plain words. Used two ways:
///  1. The offline reader expands lines itself ("BNLS SKNLS CHKN THGH" → "Boneless Skinless Chicken Thigh").
///  2. The on-device model gets the expansions as hints, which makes its guesses far more accurate.
/// Covers the common chains on Long Island and online grocers. Add to it freely.
enum ReceiptLexicon {
    static let words: [String: String] = [
        // prep / descriptors
        "BNLS": "boneless", "BNL": "boneless", "SKNLS": "skinless", "SKLS": "skinless", "SKNL": "skinless", "BI": "bone-in",
        "ORG": "organic", "ORGNC": "organic", "NAT": "natural", "FRSH": "fresh", "FRZ": "frozen", "FRZN": "frozen",
        "LG": "large", "LRG": "large", "XL": "extra large", "JMBO": "jumbo", "JMB": "jumbo", "MED": "medium", "SM": "small",
        "WHL": "whole", "WHLE": "whole", "SLCD": "sliced", "SLC": "sliced", "SHRD": "shredded", "SHRED": "shredded",
        "GRTD": "grated", "GRND": "ground", "GRD": "ground", "CHPD": "chopped", "DCD": "diced", "MNCD": "minced",
        "UNSLTD": "unsalted", "UNSLT": "unsalted", "SLTD": "salted", "RDC": "reduced", "RF": "reduced fat", "LF": "low fat",
        "FF": "fat free", "NF": "nonfat", "SF": "sugar free", "GF": "gluten free", "WG": "whole grain", "WW": "whole wheat",
        "VAR": "variety", "ASST": "assorted", "ASSTD": "assorted", "PK": "pack", "PKG": "package", "CT": "count",
        "EA": "each", "DZ": "dozen", "GAL": "gallon", "HG": "half gallon", "QT": "quart", "PT": "pint",
        "FAM": "family pack", "VP": "value pack", "BTL": "bottle", "CN": "can", "JR": "jar", "BX": "box", "BG": "bag",
        "RTE": "ready to eat", "RTC": "ready to cook", "HMSTYL": "homestyle", "TRAD": "traditional", "SWT": "sweet",
        "SPCY": "spicy", "MLD": "mild", "XTRA": "extra", "VIRG": "virgin", "XVRG": "extra virgin", "EVOO": "extra virgin olive oil",
        // proteins
        "CHKN": "chicken", "CHK": "chicken", "CKN": "chicken", "CHIX": "chicken", "BRST": "breast", "BRS": "breast",
        "THGH": "thigh", "THGHS": "thighs", "THG": "thigh", "DRMSTK": "drumstick", "DRUMS": "drumsticks", "WNGS": "wings", "TNDR": "tender", "TNDRS": "tenders",
        "GRND BF": "ground beef", "BF": "beef", "STK": "steak", "RIBEYE": "ribeye", "RBEYE": "ribeye", "SRLN": "sirloin",
        "TNDRLN": "tenderloin", "FLNK": "flank", "CHK RST": "chuck roast", "PRK": "pork", "CHP": "chop", "CHPS": "chops",
        "BCN": "bacon", "SAUS": "sausage", "SSG": "sausage", "TRKY": "turkey", "TKY": "turkey", "HM": "ham", "LMB": "lamb",
        "SLMN": "salmon", "SALM": "salmon", "ATL": "atlantic", "SHRMP": "shrimp", "SHRP": "shrimp", "SCLP": "scallops",
        "TLPIA": "tilapia", "CD": "cod", "FLT": "fillet", "FLLT": "fillet", "FLTS": "fillets",
        // dairy & eggs
        "MLK": "milk", "WHL MLK": "whole milk", "2%": "2% milk", "BTR": "butter", "BUTR": "butter", "CHS": "cheese", "CHSE": "cheese",
        "CHDR": "cheddar", "CHED": "cheddar", "SHRP CHDR": "sharp cheddar", "MOZZ": "mozzarella", "MOZ": "mozzarella",
        "PARM": "parmesan", "PRMSN": "parmesan", "RCTA": "ricotta", "CRM": "cream", "HVY": "heavy", "HVY CRM": "heavy cream",
        "HLF&HLF": "half and half", "HLF HLF": "half and half", "SR CRM": "sour cream", "CRM CHS": "cream cheese",
        "YGRT": "yogurt", "YOG": "yogurt", "GRK": "greek", "EGG": "eggs", "EGGS": "eggs", "BRWN": "brown",
        // produce
        "BNNA": "bananas", "BAN": "bananas", "APPL": "apples", "APL": "apple", "STRWB": "strawberries", "STRWBRY": "strawberries",
        "BLUBRY": "blueberries", "BLBRY": "blueberries", "RSPB": "raspberries", "AVOC": "avocado", "AVO": "avocado",
        "LMN": "lemon", "LMNS": "lemons", "LIM": "lime", "ORNG": "orange", "GRPS": "grapes", "TOM": "tomato", "TOMS": "tomatoes",
        "TMTO": "tomato", "ONIN": "onion", "ONN": "onion", "YLW": "yellow", "RD": "red", "GRN": "green", "WHT": "white",
        "GRLC": "garlic", "GRLIC": "garlic", "SPNCH": "spinach", "SPIN": "spinach", "BBY": "baby", "LTTC": "lettuce", "LETT": "lettuce",
        "ROM": "romaine", "ROMN": "romaine", "ARUG": "arugula", "BRCLI": "broccoli", "BROC": "broccoli", "CRT": "carrots",
        "CRRT": "carrots", "CELRY": "celery", "CUC": "cucumber", "CUKE": "cucumber", "ZUC": "zucchini", "ZUCC": "zucchini",
        "PEPR": "pepper", "PPR": "pepper", "BELL": "bell", "MSHRM": "mushrooms", "MUSH": "mushrooms", "PTTO": "potatoes",
        "POT": "potatoes", "SWT POT": "sweet potato", "SCLN": "scallions", "SHLT": "shallot", "GNGR": "ginger", "CILN": "cilantro",
        "PRSLY": "parsley", "BSL": "basil", "ASPRG": "asparagus", "ASPAR": "asparagus", "KALE": "kale", "BRSL": "brussels sprouts",
        // bakery & dry goods
        "BRD": "bread", "SRDGH": "sourdough", "BGL": "bagels", "BGLS": "bagels", "TORT": "tortillas", "TRTLA": "tortillas",
        "RL": "rolls", "RLS": "rolls", "BUNS": "buns", "PSTA": "pasta", "SPGTI": "spaghetti", "SPAG": "spaghetti", "PENN": "penne",
        "RCE": "rice", "JSMN": "jasmine", "BSMTI": "basmati", "FLR": "flour", "AP FLR": "all-purpose flour", "SGR": "sugar",
        "BRN SGR": "brown sugar", "OAT": "oats", "CRL": "cereal", "BRTH": "broth", "STCK": "stock", "CHKN BRTH": "chicken broth",
        "TOM SCE": "tomato sauce", "SCE": "sauce", "MAR": "marinara", "OLV OIL": "olive oil", "OLV": "olive", "VNGR": "vinegar",
        "BLSMC": "balsamic", "MYO": "mayonnaise", "MAYO": "mayonnaise", "KTCHP": "ketchup", "MSTRD": "mustard", "PB": "peanut butter",
        "HNY": "honey", "SYRP": "syrup", "CHC": "chocolate", "CHOC": "chocolate", "CHIPS": "chips", "CRKR": "crackers",
        "SPRKLNG": "sparkling", "WTR": "water", "JCE": "juice", "OJ": "orange juice", "COF": "coffee", "CFE": "coffee",
        // store brands
        "SS": "Stop & Shop", "STP&SHP": "Stop & Shop", "KK": "King Kullen", "TJ": "Trader Joe's", "TJS": "Trader Joe's",
        "KS": "Kirkland Signature", "KRKLD": "Kirkland", "WF": "Whole Foods", "365": "365", "WGMNS": "Wegmans", "GG": "Good & Gather",
        "PLN": "plain", "CRNCHY": "crunchy", "CRMY": "creamy", "UNSWT": "unsweetened", "UNSWTND": "unsweetened",
        "VAN": "vanilla", "STRW": "strawberry", "HNYCRSP": "honeycrisp", "GALA": "gala", "RSST": "russet", "YKN": "yukon gold",
        "NB": "", "STR BRND": "",
    ]

    /// Expands a receipt line's name. Two-word abbreviations are tried before single words.
    static func expand(_ raw: String) -> String {
        var tokens = raw.uppercased()
            .replacing(/\b\d+(\.\d+)?\s?(OZ|LB|LBS|CT|PK|FL)\b/, with: "")     // drop sizes
            .replacing(/\b\d{5,}\b/, with: "")                               // drop item codes
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            if i + 1 < tokens.count, let two = words["\(tokens[i]) \(tokens[i + 1])"] {
                if !two.isEmpty { out.append(two) }
                i += 2; continue
            }
            let t = tokens[i]
            if let one = words[t] { if !one.isEmpty { out.append(one) } } else { out.append(t.lowercased()) }
            i += 1
        }
        tokens = out
        let joined = tokens.joined(separator: " ").replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
        return joined.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Hints for the AI: every abbreviation on the receipt that we recognize.
    static func hints(for text: String) -> String {
        let tokens = Set(text.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "%" && $0 != "&" }).map(String.init))
        let found = tokens.compactMap { t -> String? in
            guard let w = words[t], !w.isEmpty, w.lowercased() != t.lowercased() else { return nil }
            return "\(t)=\(w)"
        }.sorted()
        return found.prefix(80).joined(separator: ", ")
    }
}
