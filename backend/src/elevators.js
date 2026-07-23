/**
 * Static elevator directory (company name, city, state, coordinates).
 * This is real reference data, not a price feed — actual cash/futures/
 * basis prices for each elevator's state come from usdaBasis.js.
 */
export const ELEVATORS = [
  { id: 1, name: "ADM Decatur", city: "Decatur", state: "IL", lat: 39.84, lng: -88.95 },
  { id: 2, name: "Bunge Channahon", city: "Channahon", state: "IL", lat: 41.43, lng: -88.23 },
  { id: 3, name: "Cargill Havana", city: "Havana", state: "IL", lat: 40.30, lng: -90.06 },
  { id: 4, name: "Topflight Grain Monticello", city: "Monticello", state: "IL", lat: 40.03, lng: -88.57 },
  { id: 5, name: "GROWMARK Bloomington", city: "Bloomington", state: "IL", lat: 40.48, lng: -88.99 },
  { id: 6, name: "ADM Cedar Rapids", city: "Cedar Rapids", state: "IA", lat: 41.98, lng: -91.67 },
  { id: 7, name: "Cargill Eddyville", city: "Eddyville", state: "IA", lat: 41.16, lng: -92.63 },
  { id: 8, name: "Landus Ames", city: "Ames", state: "IA", lat: 42.03, lng: -93.62 },
  { id: 9, name: "Key Cooperative Grinnell", city: "Grinnell", state: "IA", lat: 41.74, lng: -92.72 },
  { id: 10, name: "Heartland Co-op Des Moines", city: "Des Moines", state: "IA", lat: 41.59, lng: -93.62 },
  { id: 11, name: "CHS Mankato", city: "Mankato", state: "MN", lat: 44.16, lng: -94.00 },
  { id: 12, name: "CHS Savage", city: "Savage", state: "MN", lat: 44.78, lng: -93.34 },
  { id: 13, name: "ADM Marshall", city: "Marshall", state: "MN", lat: 44.45, lng: -95.79 },
  { id: 14, name: "Central Farm Service Fairmont", city: "Fairmont", state: "MN", lat: 43.65, lng: -94.46 },
  { id: 15, name: "Cargill Lafayette", city: "Lafayette", state: "IN", lat: 40.42, lng: -86.88 },
  { id: 16, name: "Bunge Morristown", city: "Morristown", state: "IN", lat: 39.67, lng: -85.70 },
  { id: 17, name: "The Andersons Waterloo", city: "Waterloo", state: "IN", lat: 41.43, lng: -85.02 },
  { id: 18, name: "Co-Alliance Frankfort", city: "Frankfort", state: "IN", lat: 40.28, lng: -86.51 },
  { id: 19, name: "The Andersons Maumee", city: "Maumee", state: "OH", lat: 41.56, lng: -83.65 },
  { id: 20, name: "Cargill Sidney", city: "Sidney", state: "OH", lat: 40.28, lng: -84.16 },
  { id: 21, name: "Heritage Cooperative Marysville", city: "Marysville", state: "OH", lat: 40.24, lng: -83.37 },
  { id: 22, name: "ADM Columbus", city: "Columbus", state: "OH", lat: 39.96, lng: -82.99 },
  { id: 23, name: "Scoular Salina", city: "Salina", state: "KS", lat: 38.84, lng: -97.61 },
  { id: 24, name: "Cargill Wichita", city: "Wichita", state: "KS", lat: 37.69, lng: -97.34 },
  { id: 25, name: "ADM Abilene", city: "Abilene", state: "KS", lat: 38.92, lng: -97.21 },
  { id: 26, name: "CoMark Equity Alliance Cheney", city: "Cheney", state: "KS", lat: 37.63, lng: -97.78 },
  { id: 27, name: "Ursa Farmers Co-op Quincy", city: "Quincy", state: "IL", lat: 39.94, lng: -91.41 },
  { id: 28, name: "AGP Sergeant Bluff", city: "Sergeant Bluff", state: "IA", lat: 42.40, lng: -96.36 },
  { id: 29, name: "Gavilon Council Bluffs", city: "Council Bluffs", state: "IA", lat: 41.26, lng: -95.85 },
  { id: 30, name: "CHS Winona", city: "Winona", state: "MN", lat: 44.05, lng: -91.64 },

  // Added to extend coverage beyond the original 6-state/30-elevator set
  // toward the rest of the Corn Belt. These are real company + city
  // pairings (all five companies have long-documented major Midwest
  // grain/processing operations in these cities), but — unlike the
  // original 30 — the exact facility names and coordinates below are
  // approximate (city-center lat/lng, not verified against a specific
  // street address). Treat this block as a starting point, not a
  // survey-grade directory: a genuine "all 50 states, 200+ elevators"
  // expansion needs sourcing from USDA AMS's market location lists
  // rather than being written from general knowledge.
  { id: 31, name: "ADM Lincoln", city: "Lincoln", state: "NE", lat: 40.81, lng: -96.68 },
  { id: 32, name: "Cargill Blair", city: "Blair", state: "NE", lat: 41.55, lng: -96.13 },
  { id: 33, name: "CHS Grand Island", city: "Grand Island", state: "NE", lat: 40.93, lng: -98.34 },
  { id: 34, name: "CHS Sioux Falls", city: "Sioux Falls", state: "SD", lat: 43.55, lng: -96.70 },
  { id: 35, name: "Gavilon Aberdeen", city: "Aberdeen", state: "SD", lat: 45.46, lng: -98.49 },
  { id: 36, name: "ADM Bismarck", city: "Bismarck", state: "ND", lat: 46.81, lng: -100.78 },
  { id: 37, name: "CHS Fargo", city: "Fargo", state: "ND", lat: 46.88, lng: -96.79 },
  { id: 38, name: "Bunge Council Bluffs", city: "Council Bluffs", state: "MO", lat: 39.10, lng: -94.58 },
  { id: 39, name: "Cargill Kansas City", city: "Kansas City", state: "MO", lat: 39.10, lng: -94.58 },
  { id: 40, name: "ADM Marshall MO", city: "Marshall", state: "MO", lat: 39.12, lng: -93.20 },
  { id: 41, name: "Land O'Lakes/Winfield Manitowoc", city: "Manitowoc", state: "WI", lat: 44.10, lng: -87.65 },
  { id: 42, name: "CHS Milwaukee", city: "Milwaukee", state: "WI", lat: 43.04, lng: -87.91 },
  { id: 43, name: "ADM Michigan City", city: "Michigan City", state: "MI", lat: 41.71, lng: -86.90 },
  { id: 44, name: "Cargill Kentucky", city: "Louisville", state: "KY", lat: 38.25, lng: -85.76 },
  { id: 45, name: "Louis Dreyfus Claypool", city: "Claypool", state: "IN", lat: 41.05, lng: -85.88 },

  // ---- Further expansion toward genuine nationwide coverage. Same rules
  // as the block above: real companies, real cities they are documented
  // to operate in, city-center coordinates (not a verified street
  // address). Basis pricing (usdaBasis.js) is wired for IL/IA/MN/IN/OH/KS
  // plus NE/SD/ND/NC (all verified live against the real USDA AgTransport
  // feed, Jul 2026) — elevators in any other state below will show on
  // the map/list but without a live basis figure until that state's
  // USDA AgTransport market name is confirmed and added there too.
  { id: 46, name: "Scoular Kansas City", city: "Kansas City", state: "MO", lat: 39.10, lng: -94.58 },
  { id: 47, name: "AGP St. Joseph", city: "St. Joseph", state: "MO", lat: 39.77, lng: -94.85 },
  { id: 48, name: "AGP Dawson", city: "Dawson", state: "MN", lat: 44.93, lng: -96.06 },
  { id: 49, name: "AGP Hastings", city: "Hastings", state: "NE", lat: 40.59, lng: -98.39 },
  { id: 50, name: "AGP Emmetsburg", city: "Emmetsburg", state: "IA", lat: 43.11, lng: -94.68 },
  { id: 51, name: "Gavilon Omaha", city: "Omaha", state: "NE", lat: 41.26, lng: -95.94 },
  { id: 52, name: "Scoular Omaha", city: "Omaha", state: "NE", lat: 41.26, lng: -95.94 },
  { id: 53, name: "CHS Inver Grove Heights", city: "Inver Grove Heights", state: "MN", lat: 44.85, lng: -93.04 },
  { id: 54, name: "CHS Superior", city: "Superior", state: "WI", lat: 46.72, lng: -92.10 },
  { id: 55, name: "CHS Jamestown", city: "Jamestown", state: "ND", lat: 46.91, lng: -98.71 },
  { id: 56, name: "CHS Great Falls", city: "Great Falls", state: "MT", lat: 47.51, lng: -111.28 },
  { id: 57, name: "CHS Primeland Lewiston", city: "Lewiston", state: "ID", lat: 46.42, lng: -117.02 },
  { id: 58, name: "Consolidated Grain and Barge Mount Vernon", city: "Mount Vernon", state: "IN", lat: 37.93, lng: -87.90 },
  { id: 59, name: "Bunge Cairo", city: "Cairo", state: "IL", lat: 37.00, lng: -89.18 },
  { id: 60, name: "Bunge St. Louis", city: "St. Louis", state: "MO", lat: 38.63, lng: -90.20 },
  { id: 61, name: "Bunge Decatur", city: "Decatur", state: "AL", lat: 34.61, lng: -86.98 },
  { id: 62, name: "ADM Toledo", city: "Toledo", state: "OH", lat: 41.66, lng: -83.56 },
  { id: 63, name: "ADM Clinton", city: "Clinton", state: "IA", lat: 41.84, lng: -90.19 },
  { id: 64, name: "ADM Enid", city: "Enid", state: "OK", lat: 36.40, lng: -97.88 },
  { id: 65, name: "Scoular Perryton", city: "Perryton", state: "TX", lat: 36.40, lng: -100.80 },
  { id: 66, name: "Gavilon Amarillo", city: "Amarillo", state: "TX", lat: 35.22, lng: -101.83 },
  { id: 67, name: "ADM Corpus Christi", city: "Corpus Christi", state: "TX", lat: 27.80, lng: -97.40 },
  { id: 68, name: "ADM Destrehan", city: "Destrehan", state: "LA", lat: 29.94, lng: -90.36 },
  { id: 69, name: "Bunge Destrehan", city: "Destrehan", state: "LA", lat: 29.94, lng: -90.36 },
  { id: 70, name: "Cargill Westwego", city: "Westwego", state: "LA", lat: 29.90, lng: -90.14 },
  { id: 71, name: "Zen-Noh Grain Convent", city: "Convent", state: "LA", lat: 30.02, lng: -90.83 },
  { id: 72, name: "CGB Enterprises Baton Rouge", city: "Baton Rouge", state: "LA", lat: 30.45, lng: -91.15 },
  { id: 73, name: "Cargill Helena", city: "Helena", state: "AR", lat: 34.53, lng: -90.59 },
  { id: 74, name: "Cargill Memphis", city: "Memphis", state: "TN", lat: 35.15, lng: -90.05 },
  { id: 75, name: "Bunge Memphis", city: "Memphis", state: "TN", lat: 35.15, lng: -90.05 },
  { id: 76, name: "TEMCO Kalama", city: "Kalama", state: "WA", lat: 46.01, lng: -122.85 },
  { id: 77, name: "TEMCO Tacoma", city: "Tacoma", state: "WA", lat: 47.25, lng: -122.44 },
  { id: 78, name: "United Grain Vancouver", city: "Vancouver", state: "WA", lat: 45.62, lng: -122.67 },
  { id: 79, name: "EGT Longview", city: "Longview", state: "WA", lat: 46.14, lng: -122.94 },
  { id: 80, name: "Columbia Grain Portland", city: "Portland", state: "OR", lat: 45.52, lng: -122.68 },
  { id: 81, name: "Gavilon Kalama", city: "Kalama", state: "WA", lat: 46.01, lng: -122.85 },
  { id: 82, name: "Perdue AgriBusiness Salisbury", city: "Salisbury", state: "MD", lat: 38.37, lng: -75.60 },
  { id: 83, name: "Perdue AgriBusiness Chesapeake", city: "Chesapeake", state: "VA", lat: 36.77, lng: -76.29 },
  { id: 84, name: "Southern States Cooperative Richmond", city: "Richmond", state: "VA", lat: 37.54, lng: -77.44 },
  { id: 85, name: "The Andersons Champaign", city: "Champaign", state: "IL", lat: 40.12, lng: -88.24 },
  { id: 86, name: "The Andersons Delphi", city: "Delphi", state: "IN", lat: 40.59, lng: -86.68 },
  { id: 87, name: "GROWMARK Decatur", city: "Decatur", state: "IL", lat: 39.84, lng: -88.95 },
  { id: 88, name: "Land O'Lakes/Winfield Shoreview", city: "Shoreview", state: "MN", lat: 45.08, lng: -93.15 },
  { id: 89, name: "Louis Dreyfus Davenport", city: "Davenport", state: "IA", lat: 41.52, lng: -90.58 },
  { id: 90, name: "Louis Dreyfus Council Bluffs", city: "Council Bluffs", state: "IA", lat: 41.26, lng: -95.85 },
  { id: 91, name: "Cargill Cedar Rapids", city: "Cedar Rapids", state: "IA", lat: 41.98, lng: -91.67 },
  { id: 92, name: "Frontier Cooperative Waverly", city: "Waverly", state: "NE", lat: 40.88, lng: -96.53 },
  { id: 93, name: "CHS Grand Forks", city: "Grand Forks", state: "ND", lat: 47.93, lng: -97.03 },
  { id: 94, name: "CHS Aberdeen", city: "Aberdeen", state: "SD", lat: 45.46, lng: -98.49 },
  { id: 95, name: "Scoular Colby", city: "Colby", state: "KS", lat: 39.40, lng: -101.05 },
  { id: 96, name: "Cargill Dodge City", city: "Dodge City", state: "KS", lat: 37.75, lng: -100.02 },

  // North Carolina — verified directly (WebSearch, Jul 2026): Perdue
  // AgriBusiness operates real, currently-listed grain elevators in both
  // of these towns. NC was also just confirmed live against USDA
  // AgTransport's actual Elevator Bid dataset (see usdaBasis.js), so
  // these two are backed by real basis pricing, not just a map pin.
  { id: 97, name: "Perdue AgriBusiness Belhaven", city: "Belhaven", state: "NC", lat: 35.545, lng: -76.623 },
  { id: 98, name: "Perdue AgriBusiness Greenville", city: "Greenville", state: "NC", lat: 35.613, lng: -77.366 },

  // Texas — verified via WebSearch (Jul 2026). Attebury Grain is a real,
  // Amarillo-headquartered grain company confirmed operating in Amarillo,
  // Wichita Falls and Saginaw; Plainview, Dalhart and Friona are real,
  // photo-documented Texas High Plains elevator towns (Wikimedia Commons
  // "Grain elevators in Texas") within Attebury's home region, listed
  // here as a good-faith regional pairing rather than an address-level
  // confirmation for those last three. Beaumont is Louis Dreyfus's
  // documented Gulf export presence in Texas.
  { id: 99, name: "Attebury Grain Amarillo", city: "Amarillo", state: "TX", lat: 35.22, lng: -101.83 },
  { id: 100, name: "Attebury Grain Wichita Falls", city: "Wichita Falls", state: "TX", lat: 33.91, lng: -98.49 },
  { id: 101, name: "Attebury Grain Saginaw", city: "Saginaw", state: "TX", lat: 32.86, lng: -97.36 },
  { id: 102, name: "Attebury Grain Plainview", city: "Plainview", state: "TX", lat: 34.18, lng: -101.71 },
  { id: 103, name: "Attebury Grain Dalhart", city: "Dalhart", state: "TX", lat: 36.06, lng: -102.51 },
  { id: 104, name: "Attebury Grain Friona", city: "Friona", state: "TX", lat: 34.64, lng: -102.72 },
  { id: 105, name: "Louis Dreyfus Beaumont", city: "Beaumont", state: "TX", lat: 30.08, lng: -94.10 },

  // Colorado — verified via WebSearch (Jul 2026): CHS High Plains
  // operates a real, currently-listed grain location in Yuma, CO.
  { id: 106, name: "CHS High Plains Yuma", city: "Yuma", state: "CO", lat: 40.12, lng: -102.72 },

  // Additional depth in already-covered Corn Belt / Great Plains states —
  // same real-company-plus-documented-city standard as the rest of this
  // file.
  { id: 107, name: "ADM Peoria", city: "Peoria", state: "IL", lat: 40.69, lng: -89.59 },
  { id: 108, name: "Cargill Fort Dodge", city: "Fort Dodge", state: "IA", lat: 42.50, lng: -94.17 },
  { id: 109, name: "Cargill Sioux City", city: "Sioux City", state: "IA", lat: 42.50, lng: -96.40 },
  { id: 110, name: "South Dakota Soybean Processors Volga", city: "Volga", state: "SD", lat: 44.33, lng: -96.92 },
  { id: 111, name: "Zeeland Farm Services", city: "Zeeland", state: "MI", lat: 42.81, lng: -86.02 },
  { id: 112, name: "Michigan Agricultural Commodities Blissfield", city: "Blissfield", state: "MI", lat: 41.83, lng: -83.87 },
  { id: 113, name: "Didion Milling Cambria", city: "Cambria", state: "WI", lat: 43.55, lng: -89.13 },
  { id: 114, name: "Scoular Norfolk", city: "Norfolk", state: "NE", lat: 42.03, lng: -97.42 },
  { id: 115, name: "CHS McCook", city: "McCook", state: "NE", lat: 40.20, lng: -100.63 },
  { id: 116, name: "Cargill Hutchinson", city: "Hutchinson", state: "KS", lat: 38.06, lng: -97.93 },
];
