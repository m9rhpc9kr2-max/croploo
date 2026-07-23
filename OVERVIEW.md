# Croploo — App-Übersicht

**AI-Powered Commodity Market Intelligence Terminal**
*"The basis for better trades."*

Flutter-App (Web + Desktop) mit Node.js/Express-Backend für ein
Handelsterminal rund um Agrarrohstoffe (Mais, Weizen, Sojabohnen).

---

## 1. Architektur

```
Flutter App (lib/)  ──HTTP──►  Express Backend (backend/)  ──►  MySQL (Cloud SQL)
                                        │
                                        ├─► Alpha Vantage (echte Futures-Kurse)
                                        ├─► USDA AMS AgTransport (echte Basis-Daten)
                                        ├─► USDA NASS Quick Stats (echte Crop-/Produktionsdaten)
                                        ├─► EIA (echte Diesel-Preise → Freight-Index)
                                        ├─► Anthropic Claude (CullyAI-Chat, Report-Analyse, Daily Brief)
                                        ├─► Stripe (Billing, Referral-Guthaben)
                                        └─► Mailgun SMTP (E-Mail-Verifizierung, Passwort-Reset, Morning Brief, Daily Brief)
```

- **Frontend:** Flutter, läuft als Web-App und Desktop-App (macOS/Windows/Linux)
- **Backend:** Node.js/Express, deployed auf **Google Cloud Run**
  (Service `croploo-backend`, Region `europe-west1`, Projekt `cultioo`)
- **Datenbank:** MySQL auf Cloud SQL, Verbindung über Cloud SQL Auth Proxy (Unix-Socket)
- **State Management:** Riverpod
- **Routing:** go_router
- **Charts:** fl_chart
- **Deploy-Skript:** `backend/deploy.sh` (`gcloud run deploy --source .`)
- **Secrets:** Google Secret Manager (`croploo-alphavantage-key`, `croploo-anthropic-api-key`,
  `croploo-eia-api-key`, `croploo-nass-api-key`, plus DB/JWT/Stripe/SMTP-Secrets, `CROPLOO_CRON_SECRET`),
  sowie einfache Env-Vars für `FRED_API_KEY` und `FMP_API_KEY`
- **Weitere externe Quellen (Session-Erweiterung):** FRED (St. Louis Fed, Wirtschaftsindikatoren),
  Financial Modeling Prep (Earnings-Kalender), Yahoo Finance keyless Chart-API (Forex, Crypto,
  Treasury-Yields, Sektor-Heatmap, Aktien, Intraday-Futures, Dollar-Index) — alle ohne
  zusätzliche Kosten, da entweder keyless oder im kostenlosen Tarif
- **Externer Cron (noch manuell einzurichten):** Google Cloud Scheduler muss `POST /v1/daily-brief/send-now`
  täglich um 7:30 ET mit Header `X-Cron-Secret: <CROPLOO_CRON_SECRET>` aufrufen, um den Morning-Brief-E-Mail-Versand
  auszulösen — Cloud Run selbst hat keinen eingebauten Scheduler. Cloud Run hat keinen `X-Frame-Options`-Header
  gesetzt, daher lässt sich das Basis-Widget (Abschnitt 3) problemlos per `<iframe>` einbetten.

---

## 2. Datenstand: echt vs. Mock

Die App läuft inzwischen **fast vollständig auf echten Daten**. Nur noch ein einziger
Rest-Mock existiert, und der ist bewusst so belassen (siehe unten).

| Bereich | Status | Quelle |
|---|---|---|
| Futures-Kurse (Snapshot + History) | ✅ echt | Alpha Vantage (ETF-Proxies CORN/WEAT/SOYB für ZC/ZW/ZS) |
| Basis Monitor (Chart, Karte, Liste, Ticker) | ✅ echt | USDA AMS AgTransport (Cash-Bid/Futures/Basis, **wöchentlich**, 5 Commodities: Corn, Soybeans, 3 Weizensorten, 13 Bundesstaaten live) |
| USDA-Reports: WASDE | ✅ echt | USDA NASS Quick Stats (Produktion/Ertrag/Bestände) + Claude-Analyse |
| USDA-Reports: Crop Progress | ✅ echt | USDA NASS Quick Stats (Aussaat-/Erntefortschritt, Zustand) + Claude-Analyse |
| USDA-Reports: Export Sales | ✅ echt | USDA-AgTransport-Spiegel des FAS-ESR-Reports (Dataset `wnn7-29tu`), **kein API-Key nötig** — Welt-Gesamtsumme (server-seitig über alle ~150 Zielländer aggregiert) + Top-10-Abnehmerländer der letzten Woche, siehe Abschnitt 7 |
| USDA-Kalender | ✅ echt | offizieller WASDE-/Crop-Progress-Veröffentlichungsplan |
| WASDE Surprise Tracker | ✅ echt (wächst ab jetzt) | jede WASDE-Stocks-Überraschung + reale 24h/48h/1w-Futures-Reaktion, siehe Abschnitt 7 |
| Alerts (Basis-Anomalie, Futures-Bewegung, USDA-Release) | ✅ echt | eigene Alert-Engine auf Basis der echten Daten oben |
| Alert Outcome / Audit Log | ✅ echt | live berechneter Vergleich Basis/Preis-bei-Alert vs. jetzt |
| Alert Rules | ✅ echt | spiegelt die tatsächlichen Live-Schwellenwerte der Alert-Engine |
| Freight Rates & Korrelation | ✅ echt | EIA Diesel-Preis-Index (Pro/Desk-Abo erforderlich) |
| Freight: Grain Rail Car Loadings | ✅ echt | USDA AgTransport / STB Rail Service Metrics (Dataset `27k8-utc2`), wöchentlich, je Bundesstaat, kein API-Key |
| Freight: Mississippi River Levels | ✅ echt | NOAA National Water Prediction Service (5 Pegel St. Louis→New Orleans), täglich, kein API-Key |
| Market Intel: COT | ✅ echt | CFTC Socrata-API + Claude-Übersetzung |
| Market Intel: Saisonalität | ✅ echt | Yahoo Finance (~10y Wochenschlusskurse) |
| Market Intel: US Drought Monitor (D0–D4) | ✅ echt | usdmdataservices.unl.edu (National Drought Mitigation Center), wöchentlich, kein API-Key, ergänzt die NOAA-Niederschlagsabweichung im Weather-Panel |
| Market Intel: Wetter | ✅ echt | NOAA NCEI + Claude-Markteinschätzung |
| Market Intel: Crop Tour | ✅ echt (Vergleichsbasis statisch) | Pro-Farmer-Jahresdaten (statisch, kein API) vs. echte USDA-NASS-Zahl |
| Market Intel: Crush Spread | ✅ echt | Yahoo Finance (ZS/ZL/ZM) |
| Market Intel: Forward Curve & Calendar Spread | ✅ echt | Yahoo Finance (Contract-Monat-Ticker) |
| Market Intel: Ethanol Margin | ✅ echt (1×/Tag-Snapshot) | Yahoo Finance (EH=F/ZC=F) |
| Market Intel: Dollar Index | ✅ echt | Yahoo Finance (UUP) vs. Corn-Futures |
| Market Intel: EIA Weekly Petroleum Inventory | ✅ echt (kein Konsens-Wert, siehe Abschnitt 7) | EIA Weekly Petroleum Status Report + Claude-Einschätzung |
| Market Intel: Natural Gas Storage | ✅ echt (kein Konsens-Wert, siehe Abschnitt 7) | EIA Weekly Natural Gas Storage Report + Claude-Einschätzung |
| Market Intel: Crack Spread (Raffineriemarge) | ✅ echt | Yahoo Finance (CL=F/RB=F/HO=F), Claude nur bei ungewöhnlicher Abweichung |
| Portfolio (Lagerbestand, P&L, Sell-Window, Hedge) | ✅ echt, live berechnet | Basis + Saisonalität + COT |
| Watchlist | ✅ echt | eigene Tabelle, fließt in personalisierten Daily Brief |
| Custom Alert Rules & Price Targets | ✅ echt | von der Alert-Engine stündlich mitgescannt |
| Daily Brief (In-App) | ✅ echt | Claude fasst echte Tagesdaten (Basis/Futures/Alerts) zusammen, 1×/Tag gecacht |
| Morning Brief (E-Mail) | ✅ echt (Versand) / ⏳ Trigger manuell einzurichten | gleicher Daily-Brief-Inhalt per Mailgun, ausgelöst durch Cloud Scheduler → `/daily-brief/send-now` |
| Push-Benachrichtigungen | ❌ nicht gebaut | bräuchte FCM/APNs-Projekt + Plattform-Setup, siehe Abschnitt 8 |
| Datenquellen-Transparenz (Tooltip) | ✅ echt | `source`/`as_of`-Felder aus `dataSources.js`, direkt aus den Original-Endpoints |
| Status-Seite | ✅ echt | Freshness-Check der echten Cache-Timestamps je Quelle, kein extra API-Call |
| Referral-System | ✅ echt | Stripe-Customer-Balance-Gutschrift, siehe Abschnitt 6 |
| 14-Tage-Testphase | ✅ echt | echter `subscription_tier`-Flip ohne Stripe, lazy Ablauf-Check |
| Einbettbares Basis-Widget | ✅ echt | öffentliche HTML-Route, direkt aus `usdaBasis.js` |
| CSV-Export (Basis/Alerts/WASDE) | ✅ echt | serverseitig generiertes CSV der jeweils echten Daten |
| Login per Email oder Username | ✅ echt | |
| Passwort vergessen | ✅ echt | 8-stelliger Code per Mailgun, wie E-Mail-Verifizierung |
| Auth (Login/Register/Verify) | ✅ echt | eigenes Backend + Mailgun |
| Billing (Stripe Checkout) | ✅ echt | Stripe |
| Ein Beispiel-Chat-Antworttext in `basis_detail_screen.dart` | ❌ Mock (bewusst) | `MockData.cullyReply()` — einzige verbliebene UI-Stelle, siehe Abschnitt 6 |
| Forex Terminal (Majors + Kreuz-Analyse) | ✅ echt | Yahoo Finance keyless Chart-API |
| Crypto (BTC/ETH/… als Risk-on-Proxy) | ✅ echt | Yahoo Finance keyless Chart-API |
| Treasury Yield Curve (2y/10y/30y + Inversion) | ✅ echt | Yahoo Finance keyless Chart-API |
| Sector Heatmap (S&P-Sektor-ETFs) | ✅ echt | Yahoo Finance keyless Chart-API |
| Stocks (Suche + Quote + Chart, beliebiges Ticker) | ✅ echt | Yahoo Finance keyless Chart-API |
| Intraday-Futures (15-Min-Bars, „Today"-Ansicht) | ✅ echt | Yahoo Finance keyless Chart-API (separat von `marketData.js`, um Alpha-Vantage-Kontingent zu schonen) |
| Relative Value Screener (Corn/Wheat/Soy-Ratios vs. eigene Historie) | ✅ echt | live berechnet aus vorhandenen Futures-/Historien-Daten |
| Intermarket Analysis (Lead-Lag zwischen Assets) | ✅ echt | rollierende Korrelation aus echten Zeitreihen |
| Volatility Monitor (realisierte Vol je Symbol) | ✅ echt | aus echter Preishistorie berechnet |
| Spread Trading Terminal (Calendar-/Crush-/Crack-Spreads gebündelt) | ✅ echt | kombiniert vorhandene Spread-Module in einer Handelsansicht |
| Economic Indicators (CPI, Fed Funds, Arbeitslosenquote etc.) | ✅ echt | FRED (St. Louis Fed) |
| Earnings Calendar | ✅ echt | Financial Modeling Prep `/stable/earnings-calendar` |
| Economic Calendar | ❌ blockiert (Paid-Tier) | FMP `/stable/economic-calendar` ist im kostenlosen Tarif nicht verfügbar (402), siehe Abschnitt 8 |
| News Terminal (Agrar-/Makro-Schlagzeilen mit Tags) | ✅ echt | FMP News-Endpoints |
| Cross-Asset Synthesis (Dollar+Öl+Zinskurve+WASDE → ein Netto-Signal je Rohstoff) | ✅ echt | kombiniert `forex.js`/`sectorHeatmap.js`/`yieldCurve.js`/`wasdeSurprises.js`, Claude fasst nur den Netto-Effekt zusammen |
| Proactive CullyAI Insights (3 unaufgeforderte Tages-Insights) | ✅ echt | Corn/Soy-Ratio-Perzentil, Zinskurven-Trend, NG-Storage vs. 5y-Schnitt — alles echte, vorher berechnete Zahlen, Claude formuliert nur |
| CullyAI-Gedächtnis (merkt sich frühere Chat-Themen je User) | ✅ echt | persistiert jede Chat-Runde, extrahiert Commodity-Erwähnungen für Kontext in Folgesessions |
| Decision Log / Audit Trail (Trade-Entscheidungen dokumentieren) | ✅ echt | eigene Tabelle, inkl. Compliance-CSV-Export |
| Custom Dashboards (eigene Widget-Layouts speichern) | ✅ echt | eigene Tabelle, Dialog zum Zusammenstellen/Speichern |
| Multi-Currency Portfolio-Ansicht (USD/EUR/…) | ✅ echt (Umrechnung) | nutzt echte Forex-Kurse aus `forex.js` |
| Community Insights (Trader-Beobachtungen, KI-faktengecheckt) | ✅ echt | Claude prüft jede Einreichung gegen echte Marktdaten, Verdict CONSISTENT/QUESTIONABLE |
| Croploo Learn (Erklärartikel) | ✅ echt | statische, redaktionell gepflegte Artikel-Bibliothek, kein KI-generierter Fülltext |
| Croploo Signals Newsletter (wöchentlich) | ✅ echt | Zusammenfassung aus echten Wochensignalen, Anmeldung/Abmeldung selbstständig |
| Öffentliche Trader-Profile | ✅ echt | opt-in, zeigt Username + öffentlich geteilte Insights |
| Teams & Sitzplätze (Team/Institutional-Tarif) | ✅ echt | Einladen/Entfernen von Mitgliedern, geteiltes Abo-Kontingent |
| API-Keys (programmatischer Zugriff, Desk-Tarif+) | ✅ echt | eigene Keys generieren/widerrufen, `requireApiKey`-Middleware |
| Public API (Basis/Futures/USDA etc. per API-Key) | ✅ echt | dieselben Daten wie die App, per `X-Api-Key`-Header abrufbar |

**Wichtige Einschränkung:** USDA-Basisdaten sind **wöchentlich**, nicht täglich — das ist
eine Grenze der kostenlosen Datenquelle (USDA AMS AgTransport), nicht des Codes. Für
echte tägliche Basis-Auflösung bräuchte es einen kostenpflichtigen Anbieter (DTN,
Barchart Cash Grain). Deshalb wurden die "1D"/"5D"-Zeiträume aus dem Basis-Chart entfernt
(würden 0–1 Punkte zeigen) und die Kurve zeichnet gerade Linien zwischen den echten
wöchentlichen Punkten statt einer geglätteten Kurve.

---

## 3. Features (`lib/features/`)

- **dashboard** — Startbildschirm: Begrüßung, echter Markt-Ticker (mit Quellen-Tooltip),
  echte Futures-Preistabelle, echter Tagesüberblick (Daily Brief). Zeigt bei Netzwerkausfall
  automatisch die zuletzt gecachten Werte (Offline-Banner im App-Shell, siehe unten).
- **basis** — Basis-Analyzer (echter Kassapreis minus Futures-Preis) mit vier Ansichten:
  **Grid** (stilisierte, netzwerkfreie Scatter-Projektion, jetzt auf ganz-USA-Koordinaten
  skaliert), **Map** (echte pan-/zoombare Karte via `flutter_map` + OpenStreetMap-kompatible
  Kacheln — CartoDB Positron/Dark Matter, theme-abhängig hell/dunkel, kein API-Key nötig),
  **List** und **Chart** pro Elevator. Commodity-Filter (Corn, Soybeans, 3 Weizensorten) und
  **Mehrfachauswahl-Bundesstaaten-Filter** (`MenuAnchor`-basiertes Multi-Select-Popup statt
  Single-Select-Dropdown). Jeder Wert zeigt per Hover Quelle + Aktualisierungszeitpunkt
  ("Datenquellen-Transparenz"). Chart-Ansicht hat einen "Export CSV"-Button. Detailseite hat
  einen "Embed Widget"-Button, der ein `<iframe>`-Snippet für das öffentliche Basis-Widget
  generiert (kopierbar).
  Elevator-Verzeichnis (116 real benannte Firmen/Standorte in 27 Bundesstaaten) ist statische
  Referenzdaten; Basiswerte sind je Bundesstaat/Rohstoff echt, sofern das jeweilige
  Bundesstaat/Commodity-Paar bei USDA AgTransport existiert (siehe Abschnitt 7). Elevatoren
  ohne Live-Basisdaten werden auf Grid **und** Map als eigener, gedämpfter "No data"-Pin
  angezeigt (`GET /elevators`, unabhängig von `/basis-overview`), statt unsichtbar zu sein.
- **usda** — USDA-Report-Browser (WASDE, Crop Progress — echt) mit echtem Release-Kalender
  und Claude-Analyse pro Report. **Export Sales** (echt, seit dieser Session) ist kein
  Claude-analysiertes Vergleichstabellen-Report wie WASDE/Crop Progress, sondern ein eigenes
  Panel mit echter wöchentlicher Welt-Gesamtsumme (Net Sales/Exports/Outstanding Sales/Total
  Commitments) plus Top-10-Abnehmerländer der letzten Woche — erscheint, sobald der
  "Export Sales"-Filter aktiv ist und kein WASDE/Crop-Progress-Report ausgewählt ist. Bei
  WASDE-Reports zusätzlich
  ein **WASDE Surprise Tracker**: Historie aller bisher beobachteten Stocks-Überraschungen
  mit realer 24h/48h/1-Woche-Futures-Reaktion, plus "diese Überraschung ähnelt X am meisten"
  (Vergleich gegen die eigene, wachsende Historie — kein 2015-Backfill möglich, siehe
  Abschnitt 8). Export-CSV-Button für die Surprise-Historie.
- **alerts** — Alert-Postfach mit echten, automatisch generierten Alerts (Gelesen/Ungelesen-
  Status wird ans Backend persistiert). Jeder Alert zeigt, sofern verfügbar, ein echtes
  **Outcome** ("3 Wochen später war Basis 12¢ enger"), live berechnet aus dem Wert bei
  Alert-Auslösung vs. dem aktuellen Wert. "Export CSV"-Button für den kompletten Alert-Log.
  "Manage Rules"-Dialog zeigt die System-Regeln **und** eigene **Custom Alert Rules**
  (Basis-Schwellenwert je Bundesstaat, oder Futures-Bewegungs-Schwelle), die die Alert-Engine
  stündlich zusätzlich zu den festen System-Regeln scannt.
- **status** — Neuer Screen: Live-Gesundheit jeder echten Datenquelle (USDA AMS, Alpha
  Vantage, NASS, EIA, Anthropic), spiegelt die öffentliche `/status`-Seite des Backends.
- **freight** — Echte Frachtraten pro Korridor (z. B. Midwest–Gulf) aus dem EIA-Diesel-Index,
  plus Korrelation Frachtrate vs. Corn-Basis über Zeit; nur für Pro/Desk-Abo (`hasProAccess`-Check).
- **intel — Market Intel** (Pro/Desk): acht echte Panels in einem Screen:
  - **COT (Commitments of Traders)** — CFTC-Positionierung (Managed Money vs.
    Producer/Merchant), Wochenveränderung, 3-Jahres-Perzentil, Claude-Übersetzung in
    Trader-Sprache.
  - **Saisonalität** — 5y/10y-Durchschnittsmuster (indexiert) aus echten Yahoo-Finance-
    Wochenschlusskursen, aktuelles Jahr darüber gelegt.
  - **Wetter** — NOAA-Corn-Belt-Niederschlagsabweichungen (1/3-Monats-Fenster) mit
    Claude-Markteinschätzung.
  - **Crop Tour** — Pro-Farmer-Ertragsschätzung vs. USDA-NASS-Zahl, Claude-Vergleich pro Jahr.
  - **Crush Spread** — Sojabohnen-Verarbeitungsmarge aus ZS/ZL/ZM-Frontmonat-Schlusskursen.
  - **Forward Curve** — echte Preise über die nächsten CME-Kontraktmonate (Yahoo Finance),
    Contango/Backwardation direkt ablesbar, plus Calendar-Spread-Historie (Near − Far).
  - **Ethanol Margin** — Corn-to-Ethanol-Marge aus EH=F/ZC=F.
  - **Dollar Index** — UUP-Proxy vs. Corn-Futures mit echter rollierender Korrelation.
  - **EIA Weekly Petroleum Inventory** — echte US-Rohöl-/Benzin-/Destillat-Lagerbestände
    (EIA Weekly Petroleum Status Report, jeden Mittwoch ~10:30 ET) + Wochenveränderung +
    Claude-Einschätzung (bullish/bearish/neutral für Rohöl, inkl. Freight-Kosten-Angle).
    **Zeigt bewusst keinen "Markt erwartete X"-Konsenswert** — EIA veröffentlicht keinen, und
    es gibt keine kostenlose Quelle für Analysten-Konsensschätzungen (das wäre ein
    kostenpflichtiger Bloomberg/Reuters-Analysten-Poll).
  - **Natural Gas Storage** — echte US-Erdgas-Lagerbestände (EIA Weekly Natural Gas Storage
    Report, jeden Donnerstag ~10:30 ET), Abweichung vs. Vorjahr **und** vs. 5-Jahres-
    Durchschnitt (aus der eigenen Historie berechnet), Injection-/Withdrawal-Season-Badge,
    Claude-Einschätzung. Ebenfalls bewusst ohne Konsenswert.
  - **Crack Spread (Raffineriemarge)** — echter 3:2:1 Crack Spread aus CL=F/RB=F/HO=F-
    Frontmonat-Schlusskursen (Yahoo Finance, gleiche Quelle wie Crush Spread). Claude wird
    nur zugeschaltet, wenn der aktuelle Wert ungewöhnlich weit von seinem eigenen
    1-Jahres-Durchschnitt abweicht (>20%) — spart API-Kosten, die meisten Aufrufe zeigen nur
    die reinen Zahlen ohne KI-Kommentar.
- **portfolio** — Echte Lagerbestands-Positionen (Commodity, Menge, Einlagerungsdatum,
  Break-Even-Preis); P&L, Sell-Window-Empfehlung (aus `seasonal.js`) und Hedge-Kontext (aus
  `cotData.js`) werden bei jedem Aufruf live berechnet, nicht gespeichert.
- **watchlist** (unter Settings erreichbar) — Commodity+State-Kombinationen, auf die ein User
  achten will; fließt in den personalisierten Daily Brief (`personalized_daily_briefs`) und
  priorisiert Signale im Morning Brief.
- **cullyai** — Einklappbares KI-Chat-Panel (rechte Seite), echtes SSE-Streaming von Claude,
  sendet volle Conversation-History, Tages-/Stundenlimit je nach Abo-Stufe. Per Tastatur
  (`B`) auf-/zuklappbar.
- **settings** — Konto-/Theme-Einstellungen, Abo-Karten (Basic/Pro/Desk) für Stripe-Checkout,
  **14-Tage-Pro-Testphase ohne Kreditkarte** (echter Tier-Flip, lazy Ablauf), **Referral-Karte**
  (eigener Code = Username, Liste geworbener Signups, gutgeschriebener Betrag), echter
  "Morning Brief E-Mail"-Schalter (7:30 ET täglich, unabhängig vom App-Öffnen), echte
  **Price Targets** ("Sell corn above $5.20" — von der Alert-Engine gegen echte Futures-Preise
  geprüft, feuert einmalig und deaktiviert sich selbst), Appearance- (Theme) und
  Regional-Einstellungen (Zahlenformat, Einheiten). "In-app alerts" ist weiterhin nur ein
  lokaler UI-Schalter ohne Backend-Anbindung (Altlast, nicht neu gebaut); "Desktop push" ist
  bewusst deaktiviert statt vorgetäuscht (siehe Abschnitt 8).
- **auth** — Login/Registrierung/E-Mail-Verifizierung; Login akzeptiert **E-Mail oder
  Username**; **Passwort-vergessen-Flow** (8-stelliger Code per Mailgun, dann neues Passwort
  setzen); optionales Referral-Code-Feld bei der Registrierung. Auf Desktop eigenes natives
  Login-Fenster, das nach Erfolg ein neues App-Fenster mit Session öffnet.
- **markets — Markets** (neuer Screen, fünf echte Panels): **Stocks** (Freitextsuche +
  Quote + Chart für beliebige Ticker), **Forex Terminal** (Major-Paare), **Crypto**
  (BTC/ETH/… als Risk-on-Proxy), **Treasury Yield Curve** (2y/10y/30y, Inversions-Badge,
  Kurven zeigen nur nicht-leere Serien, damit fehlende Vorjahresdaten den Chart nicht
  zum Absturz bringen), **Sector Heatmap** (S&P-Sektor-ETFs als Kachel-Raster). Alle über
  die keyless Yahoo-Finance-Chart-API.
- **analytics — Analytics** (neuer Screen, vier echte Panels): **Relative Value Screener**
  (Corn/Wheat/Soy-Preisverhältnisse vs. eigene Historie), **Intermarket Analysis** (Lead-Lag-
  Korrelation zwischen Assets), **Volatility Monitor** (realisierte Volatilität je Symbol),
  **Spread Trading Terminal** (Calendar-/Crush-/Crack-Spreads gebündelt in einer
  Handelsansicht).
- **energy — Energy** (aus Market Intel herausgelöster eigener Screen): **EIA Weekly
  Petroleum Inventory**, **Natural Gas Storage**, **Crack Spread (Refining Margin)** — exakt
  dieselben drei echten Panels, die vorher in Market Intel steckten, jetzt mit mehr Raum in
  einem eigenen Screen.
- **macro — Macro** (neuer Screen, vier echte Panels): **Economic Indicators** (CPI, Fed
  Funds Rate, Arbeitslosenquote u. a. von FRED), **Earnings Calendar** (Financial Modeling
  Prep), **Economic Calendar** (FMP — aktuell leer/blockiert, da der Endpoint im kostenlosen
  Tarif kostenpflichtig ist, siehe Abschnitt 8), **News Terminal** (Agrar-/Makro-Schlagzeilen
  mit Tag-Filter).
- **community — Community**: **Croploo Signals**-Newsletter-Vorschau (wöchentliche
  Zusammenfassung echter Wochensignale), **Community Insights** (Trader posten Beobachtungen,
  Claude faktencheckt sie live gegen echte Marktdaten und markiert
  CONSISTENT/QUESTIONABLE), **Croploo Learn** (redaktionell gepflegte Erklärartikel,
  Detail-Dialog mit Close-Button und scharfen Ecken wie der Rest der App).
- **audit — Audit Trail / Decision Log**: Trader dokumentieren eigene Handelsentscheidungen
  (Rationale, Commodity, Richtung) für spätere Selbstprüfung; **Compliance-CSV-Export**
  über einen separaten, per Header-oder-Query-Auth geschützten Endpoint (für Reporting-Tools,
  die keine Bearer-Header setzen können).
- **cullyai (erweitert)** — zusätzlich zum Chat-Panel jetzt mit **Gedächtnis** (merkt sich
  je User, welche Commodities/Themen in früheren Sessions besprochen wurden, referenziert sie
  in neuen Antworten), **Cross-Asset Synthesis** (kombiniert Dollar-Stärke, Öl-Richtung,
  Zinskurve und letzte WASDE-Überraschung zu einem Netto-Effekt je Rohstoff — Dashboard-Karte)
  und **Proactive Insights** (3 unaufgeforderte, einmal täglich generierte Insights auf dem
  Dashboard, basierend auf echten berechneten Kennzahlen statt erfundener Statistiken).
- **dashboard (erweitert)** — zusätzlich zu Ticker/Futures/Daily-Brief jetzt mit
  **Custom Dashboards** (eigene Widget-Auswahl als benanntes Layout speichern/laden, Dialog
  mit scharfen Ecken, Close-Button und eigener gestylter Checkbox-Zeile statt Material-
  `CheckboxListTile`), einer **Proactive-Insights-Karte** und einer
  **Cross-Asset-Synthesis-Karte** (beide von CullyAI, s. o.).
- **portfolio (erweitert)** — zusätzlich zu Lagerbestand/P&L jetzt mit einem
  **Multi-Currency-Umrechner** (USD/EUR/…, nutzt echte Forex-Kurse aus `forex.js`) für
  Nutzer, die in ihrer Heimatwährung denken statt in USD.
- **settings (erweitert) — Account Settings**: Name/E-Mail/Username sind jetzt direkt editierbar
  (Uniqueness-Check gegen bestehende Accounts vor dem Speichern), eigener
  Passwort-ändern-Dialog, sowie ein echter **Sign-Out**, der Session-Token
  (`SessionStorage.clear()`) **und** den gesamten Offline-Cache (`OfflineCache.clearAll()`)
  löscht, bevor das Fenster geschlossen wird — vorher blieb die Session beim Neustart
  fälschlich bestehen. Bei Team/Institutional-Tarif zusätzlich **Team-Verwaltung**
  (Mitglieder einladen/entfernen, geteiltes Sitzplatz-Kontingent) und **API-Keys**
  (generieren/widerrufen, für den programmatischen Zugriff über die Public API).

**App-weite Zusatzfunktionen (nicht an ein einzelnes Feature gebunden):**
- **Offline-Modus** — `OfflineCache` (SharedPreferences) merkt sich die letzte erfolgreiche
  Antwort jedes öffentlichen GET-Endpoints; schlägt ein Live-Request fehl, liefert das
  Repository automatisch den letzten Cache-Stand statt eines leeren Screens, und ein Banner
  im App-Shell zeigt "Offline — showing cached data as of …". Auth-gebundene Endpoints werden
  nicht gecacht (Datenschutz bei Geräten mit mehreren Accounts).
- **Tastaturkürzel (Desktop)** — `C`/`W`/`S` wählen Corn/Wheat/Soybeans (app-weiter
  Commodity-Filter), `1`–`4` wechseln zwischen Dashboard/Basis/USDA/Alerts, `B` klappt das
  CullyAI-Panel auf/zu. Über `CallbackShortcuts`, greift nicht in Texteingaben ein.

---

## 4. Backend (`backend/src/`)

**Routen:**
- `auth.js` — `/register`, `/verify-email`, `/resend-code`, `/login` (E-Mail **oder**
  Username), `/forgot-password`, `/reset-password`, `/me`, `/me/preferences`
  (Morning-Brief-E-Mail-Opt-out), `/referrals`
- `billing.js` — `/checkout` (Stripe Checkout Session), `/start-trial` (14 Tage Pro, kein
  Stripe nötig), Webhook-Handler, HTML-Erfolgs-/Abbruchseiten
- `market.js` — `/futures-prices`, `/futures-history/:symbol` (beide mit `source`/`as_of`)
- `basis.js` — `/elevators` (voller Elevator-Katalog, unabhängig von Live-Basisdaten, fürs
  Map-"No data"-Rendering), `/basis-overview`, `/basis-history`, `/ticker`,
  `/basis-history/export` (CSV)
- `cullyai.js` — `/cullyai/chat` (SSE-Streaming, Tages-/Stundenlimit)
- `alerts.js` — `/alerts` (inkl. live berechnetem `outcome`), `/alerts/export` (CSV),
  `/alerts/:id/read`, `/alerts/read-all`, `/alert-rules`
- `freight.js` — `/freight/rates`, `/freight/correlation`, `/freight/rail-carloadings`
  (echte STB-Rail-Service-Metrics je Bundesstaat), `/freight/river-gauges` (5 echte
  NOAA-Mississippi-Pegel) — alle Pro/Desk, `requireAuth`
- `usda.js` — `/usda/reports`, `/usda/reports/:id/analyze`, `/usda/calendar`,
  `/usda/export-sales` (echte FAS-Export-Sales-Weltsumme + Top-10-Abnehmerländer, kein
  API-Key), `/usda/wasde-surprises`, `/usda/wasde-surprises/export` (CSV)
- `dailyBrief.js` — `/daily-brief`, `/daily-brief/send-now` (Cron-Endpoint, geschützt durch
  `X-Cron-Secret`, fürs 7:30-ET-Morning-Brief-E-Mail)
- `status.js` — `/status` (JSON, für den In-App-Status-Screen); die öffentliche HTML-Seite
  `GET /status` wird direkt in `server.js` registriert (kein `/v1`-Prefix)
- `widget.js` — `GET /widget/basis?state=&commodity=` (öffentliche, einbettbare HTML-Seite,
  kein `/v1`-Prefix, kein Auth)
- `intel.js` — `/intel/cot`, `/intel/seasonal/:symbol`, `/intel/weather`, `/intel/drought`
  (echte US-Drought-Monitor-D0–D4-Statistik je Bundesstaat, kein API-Key), `/intel/crop-tour`,
  `/intel/crush`, `/intel/forward-curve/:symbol`, `/intel/calendar-spread/:symbol`,
  `/intel/ethanol-margin`, `/intel/dollar-index`, `/intel/eia-inventory`, `/intel/ng-storage`,
  `/intel/crack-spread` — alle Pro/Desk. Die letzten drei (`eia-inventory`/`ng-storage`/
  `crack-spread`) werden im Frontend inzwischen im eigenen `energy`-Screen statt in
  Market Intel angezeigt, die Backend-Route ist unverändert dieselbe.
- `portfolio.js` — `/portfolio` (GET/POST), `/portfolio/:id` (DELETE), `requireAuth`
- `watchlist.js` — `/watchlist` (GET/POST), `/watchlist/:id` (DELETE), `requireAuth`
- `customAlertRules.js` — `/custom-alert-rules` (GET/POST), `/custom-alert-rules/:id`
  (DELETE), `requireAuth`
- `priceTargets.js` — `/price-targets` (GET/POST), `/price-targets/:id` (DELETE), `requireAuth`
- `macro.js` — `/macro/forex`, `/macro/crypto`, `/macro/yield-curve`, `/macro/indicators`,
  `/macro/earnings-calendar`, `/macro/economic-calendar`, `/macro/news`, `/macro/sector-heatmap`
- `analytics.js` — `/analytics/intermarket`, `/analytics/volatility`,
  `/analytics/relative-value`, `/analytics/spreads`
- `stocks.js` — `/stocks/search`, `/stocks/quote/:symbol`
- `decisionLog.js` — `/decision-log` (GET/POST), `/decision-log/compliance-export`
  (eigene Auth-Variante `requireAuthViaHeaderOrQuery` für Reporting-Tools ohne Bearer-Header)
- `customDashboards.js` — `/dashboards` (GET/POST), `/dashboards/:id` (DELETE), `requireAuth`
- `growth.js` — `/community-insights` (GET/POST), `/learn`, `/learn/:slug`,
  `/newsletter/latest`, `/newsletter/subscribe`, `/newsletter/unsubscribe`,
  `/newsletter/send`, `/profile/me` (GET/PUT), `/profile/:username` (öffentlich)
- `teams.js` — Team anlegen, Mitglieder einladen/auflisten/entfernen, Sitzplatz-Verwaltung
  (7 Routen, POST/GET/DELETE gemischt, alle `requireAuth`)
- `apiKeys.js` — API-Key erzeugen/auflisten/widerrufen (Desk-Tarif+, `apiAccess`-Flag aus
  `config.js`)
- `publicApi.js` — 8 GET-Routen (Basis/Futures/USDA/Alerts etc.), authentifiziert per
  `X-Api-Key`-Header statt JWT (`requireApiKey.js`), für externe/programmatische Nutzung

**Datenmodule:**
- `marketData.js` — Alpha-Vantage-Anbindung, Caching der Futures-Kurse (parallel, fehlertolerant)
- `usdaBasis.js` — USDA AgTransport-Anbindung (kein API-Key nötig), Caching der Basis-Bars
  (parallel, fehlertolerant). 5 Commodity-Symbole: `ZC` (Corn), `ZS` (Soybeans), `ZW` (Soft
  Red Winter Wheat), `KE` (Hard Red Winter Wheat), `MWE` (Hard Red Spring Wheat) — Weizen ist
  bewusst nach realer USDA-Sorte statt eines einzigen generischen "Wheat"-Symbols aufgeteilt,
  da AgTransport die Sorten separat mit eigenen Cash-/Futures-/Basis-Werten führt und eine
  Kansas-Basis z. B. nie zu Soft-Red-Winter-Futures passt. 13 Bundesstaaten live verdrahtet
  (`STATE_MARKET_NAMES`): IL/IA/MN/IN/OH/KS/NE/SD/ND/NC (Corn+Soybeans) sowie MT/OK/WA
  (ausschließlich Weizen — diese drei haben laut Live-Check keine Corn/Soybean-Elevator-Bid-
  Daten). Alle State/Symbol-Zuordnungen wurden direkt gegen den echten
  `agtransport.usda.gov`-Endpoint verifiziert, nicht geschätzt.
- `nassData.js` — USDA NASS Quick Stats-Anbindung (Produktion/Ertrag/Bestände/Progress/Condition)
- `usdaReports.js` — baut Report-Vergleichstabellen deterministisch aus echten NASS-Zahlen,
  lässt Claude nur die Analyse schreiben, cached in `usda_reports`, stößt bei WASDE zusätzlich
  `wasdeSurprises.recordSurprise()` an
- `wasdeSurprises.js` — WASDE-Surprise-Tracker: Stocks-Abweichung vs. Vorperiode, reale
  24h/48h/1w-Futures-Reaktion (aus `futures_price_history` nachgetragen, sobald genug Zeit
  vergangen ist), Ähnlichkeitssuche gegen die eigene Historie
- `usdaCalendar.js` — echter, offiziell veröffentlichter WASDE-/Crop-Progress-Zeitplan
- `exportSales.js` — echte USDA-FAS-Export-Sales-Daten über den keylosen AgTransport-Socrata-
  Spiegel (Dataset `wnn7-29tu`) statt der schlüsselpflichtigen FAS-OpenData-API; Welt-
  Gesamtsumme wird server-seitig per SoQL `sum()` über alle Zielländer aggregiert, Top-10-
  Abnehmerländer separat pro Woche, cached in `export_sales_snapshots` /
  `export_sales_destinations`
- `eiaFreight.js` — EIA-Diesel-Preis-Anbindung, Freight-Index-Berechnung pro Korridor (parallel, fehlertolerant)
- `grainRailCars.js` — echte wöchentliche Getreide-Waggon-Verladungen je Bundesstaat (STB Rail
  Service Metrics via USDA AgTransport, Dataset `27k8-utc2`, kein API-Key), summiert über alle
  meldenden Class-I-Bahnen, cached in `rail_car_loadings`
- `mississippiGauges.js` — echte Pegel-/Durchfluss-Messwerte (Fuß / kcfs) an 5 verifizierten
  NOAA-Stationen entlang des Getreide-Exportkorridors St. Louis→New Orleans (NOAA National
  Water Prediction Service, kein API-Key), auf einen Messwert/Tag heruntergesampelt, cached in
  `mississippi_gauge_readings`
- `droughtMonitor.js` — echte wöchentliche US-Drought-Monitor-D0–D4-Flächenanteile je
  Bundesstaat (usdmdataservices.unl.edu, kein API-Key), Prozent selbst aus den gemeldeten
  Flächenwerten berechnet (kein Percent-Endpoint verfügbar), cached in
  `drought_monitor_snapshots`
- `alertsEngine.js` — scannt echte Basis-/Futures-/USDA-Kalenderdaten stündlich (lazy-refresh)
  und erzeugt Alerts; erfasst bei Futures-Move-Alerts zusätzlich den Preis zum Alert-Zeitpunkt
  (`metadata.priceAtAlert`) fürs spätere Outcome
- `dailyBrief.js` — sammelt echte Tagessignale und lässt Claude eine Zusammenfassung schreiben, 1×/Tag gecacht
- `dailyBriefEmail.js` — verschickt den Daily Brief per Mailgun an alle verifizierten,
  opted-in User (`sendToAllSubscribers()`, aufgerufen von `/daily-brief/send-now`)
- `dataSources.js` — zentrales Register der Upstream-Quellen (Label/Detail), von
  `basis.js`/`market.js`/`usdaReports.js` **und** `statusCheck.js` gemeinsam genutzt, damit
  Tooltip-Text und Status-Seite nie auseinanderlaufen
- `statusCheck.js` — leitet den Live-Status jeder Quelle aus der Freshness der bereits
  gecachten Daten ab (kein zusätzlicher API-Call, spart Alpha-Vantage/NASS-Kontingent)
- `csv.js` — minimaler, abhängigkeitsfreier CSV-Encoder für die Export-Endpoints
- `referrals.js` — Referral-Code = eigener Username (keine separate Spalte nötig);
  `creditReferrerIfEligible()` schreibt bei der ersten Konvertierung eines geworbenen Users
  eine echte Stripe-Customer-Balance-Gutschrift (`referral_credits`, unique je geworbenem User)
- `cotData.js` — echte CFTC-COT-Positionierung (Socrata-API, kein Key), Claude-Übersetzung,
  cached in `cot_reports`
- `seasonal.js` — ~10 Jahre echte wöchentliche Kontinuierlich-Futures-Schlusskurse (Yahoo
  Finance, kein Key) für das 5y/10y-Saisonmuster, cached in `seasonal_price_history`
- `weatherImpact.js` — echte NOAA-Corn-Belt-Niederschlagsabweichungen, Claude-Markteinschätzung,
  cached in `weather_impacts`
- `cropTour.js` — Pro-Farmer-Ertragsschätzung (statisches, versioniertes Jahres-Dataset) vs.
  echte USDA-NASS-Zahl, Claude-Vergleich, cached in `crop_tour_analyses`
- `crushSpread.js` — Sojabohnen-Board-Crush aus echten ZS/ZL/ZM-Frontmonat-Schlusskursen
  (Yahoo Finance), cached in `crush_history`
- `forwardCurve.js` — echte Forward-Curve-Preise je Kontraktmonat (Yahoo Finance,
  einzelne Contract-Ticker) plus Calendar-Spread-Historie, cached in `forward_curve` /
  `calendar_spread_history` / `forward_curve_analysis`
- `ethanolMargin.js` — Corn-to-Ethanol-Marge aus EH=F/ZC=F, cached in `ethanol_margin_history`
  (EH=F hat keine Yahoo-Tageshistorie, daher wächst die Kurve nur einen echten Snapshot pro Tag)
- `dollarIndex.js` — UUP-Dollar-Index-Proxy vs. Corn-Futures mit echter rollierender
  Korrelation, cached in `dollar_index_history`
- `eiaInventory.js` — echte wöchentliche EIA-Rohöl-/Benzin-/Destillat-Lagerbestände + reale
  Wochenveränderung + Claude-Einschätzung, cached in `eia_inventory_snapshots`; bewusst ohne
  Markt-Konsenswert (keine freie Quelle dafür vorhanden)
- `ngStorage.js` — echte wöchentliche EIA-Erdgas-Lagerbestände + Abweichung vs. Vorjahr und
  vs. 5-Jahres-Durchschnitt (aus der eigenen Historie berechnet) + Injection-/Withdrawal-
  Season + Claude-Einschätzung, cached in `ng_storage_snapshots`; ebenfalls bewusst ohne
  Markt-Konsenswert
- `crackSpread.js` — echter 3:2:1 Crack Spread aus CL=F/RB=F/HO=F-Frontmonat-Schlusskursen
  (Yahoo Finance), cached in `crack_spread_history`; Claude wird nur bei >20% Abweichung vom
  eigenen 1-Jahres-Durchschnitt zugeschaltet (spart API-Kosten für den Normalfall)
- `portfolio.js` — Lagerbestands-P&L/Sell-Window/Hedge-Kontext, live berechnet aus
  `usdaBasis.js` + `seasonal.js` + `cotData.js`, nie gespeichert
- `anthropicClient.js` — gemeinsamer Streaming-/Completion-Wrapper um die Claude Messages API
- `elevators.js` — statische Elevator-Referenzliste (Name/Ort/Bundesstaat, keine Preisdaten),
  116 Einträge über 27 Bundesstaaten (Corn Belt, Gulf-Coast- und Pacific-Northwest-
  Exportterminals, Mid-Atlantic), jeweils recherchiert (WebSearch/Live-API), nicht erfunden —
  siehe Kommentare im File für die Quellenlage pro Block
- `forex.js` — echte Major-Devisenpaare über Yahoo Finance keyless Chart-API, cached
- `crypto.js` — echte Krypto-Kurse (BTC/ETH/…) über dieselbe keyless Yahoo-API, cached
- `yieldCurve.js` — echte 2y/10y/30y-Treasury-Renditen (Yahoo), Inversions-Erkennung
- `sectorHeatmap.js` — echte S&P-Sektor-ETF-Tagesbewegungen (Yahoo), Basis auch für
  Cross-Asset Synthesis
- `stocks.js` — Freitext-Ticker-Suche + Quote/Chart für beliebige Aktien (Yahoo)
- `intradayFutures.js` — echte 15-Minuten-Bars für Futures-Symbole (Yahoo keyless
  Chart-API), bewusst getrennt von `marketData.js`, da Alpha Vantages 25-Requests/Tag-Limit
  kein 15-Minuten-Polling erlaubt
- `fredClient.js` / `economicIndicators.js` — Anbindung an FRED (St. Louis Fed) für echte
  Wirtschaftsindikatoren (CPI, Fed Funds Rate, Arbeitslosenquote etc.)
- `earningsCalendar.js` — Financial Modeling Prep `/stable/earnings-calendar`
- `economicCalendar.js` — FMP `/stable/economic-calendar`; Endpoint ist im kostenlosen
  FMP-Tarif kostenpflichtig (HTTP 402) — liefert bewusst eine leere Liste statt eines Mocks,
  siehe Abschnitt 8
- `newsTerminal.js` — Agrar-/Makro-Nachrichten mit Tag-Extraktion (FMP News-Endpoints)
- `relativeValueScreener.js` — Corn/Wheat/Soy-Preisverhältnisse gegen die eigene Historie,
  live berechnet
- `intermarketAnalysis.js` — rollierende Lead-Lag-Korrelation zwischen Assets
- `volatilityMonitor.js` — realisierte Volatilität je Symbol aus echter Preishistorie
- `spreadTerminal.js` — bündelt Calendar-/Crush-/Crack-Spread-Daten in einer
  Handelsansicht (kombiniert vorhandene Module, keine neue Datenquelle)
- `crossAssetSynthesis.js` — kombiniert `forex.js`/`sectorHeatmap.js`/`yieldCurve.js`/
  `wasdeSurprises.js` zu einem Netto-Effekt je Rohstoff, Claude reasoned nur über bereits
  echte, vorberechnete Zahlen
- `proactiveInsights.js` — einmal täglich generierte, unaufgeforderte CullyAI-Insights aus
  echten Kennzahlen (Corn/Soy-Ratio-Perzentil, Zinskurven-Trend, NG-Storage vs. 5y-Schnitt)
- `cullyaiMemory.js` — persistiert jede Chat-Runde je User, extrahiert erwähnte Commodities
  für Kontext in Folgesessions
- `decisionLog.js` — Trade-Entscheidungs-Log je User inkl. Compliance-CSV-Export
- `communityInsights.js` — Community-Postings, Claude faktencheckt live gegen echte
  Marktdaten (Verdict CONSISTENT/QUESTIONABLE)
- `croplooLearn.js` — redaktionell gepflegte Erklärartikel (statisch, nicht KI-generiert)
- `newsletter.js` — wöchentliche Croploo-Signals-Zusammenfassung aus echten Wochensignalen,
  Anmeldung/Abmeldung/Versand
- `publicProfiles.js` — opt-in öffentliche Trader-Profile (Username + geteilte Insights)
- `requireApiKey.js` — Auth-Middleware für die Public API (`X-Api-Key`-Header statt JWT)

**Sonstige Module:**
- `server.js` — Express-App, CORS, Routing, Healthcheck, Error-Handler; registriert auch die
  öffentlichen Top-Level-Seiten `/status` und `/widget/basis` (kein `/v1`-Prefix, kein Auth)
- `config.js` — sämtliche Env-Konfiguration (DB, JWT, Alpha Vantage, USDA NASS, EIA, Anthropic,
  SMTP, Stripe, Preispläne, `CROPLOO_CRON_SECRET`)
- `db.js` — MySQL-Connection-Pool; Schema wird beim Start idempotent angelegt. Enthält eine
  generische `patchLegacyTable()`-Hilfsfunktion, die alte, teils schon vorhandene Tabellen (aus
  einem früheren, nie fertig verdrahteten Backend-Versuch) automatisch auf das aktuelle Schema
  nachzieht (fehlende Spalten ergänzen, inkompatible NOT-NULL-Altspalten lockern, Unique-Keys
  nachziehen). Neuere Spalten/Tabellen (`referred_by`, `stripe_customer_id`, `trial_ends_at`,
  `has_used_trial`, `daily_brief_email`, `reset_code`/`reset_expires`, `referral_credits`,
  `wasde_surprises`) werden über einfache `ADD COLUMN IF NOT EXISTS`-artige Checks ergänzt.
- `security.js` — Passwort-Hashing (PBKDF2), JWT, Verifizierungscode-Generator (auch für
  Passwort-Reset-Codes wiederverwendet)
- `requireAuth.js` — Auth-Middleware; prüft bei jedem authentifizierten Request zusätzlich
  lazy, ob eine 14-Tage-Testphase abgelaufen ist, und stuft dann automatisch auf `free` zurück
  (ein echter Stripe-Kauf löscht `trial_ends_at` vorher, kann also nie versehentlich
  zurückgestuft werden)
- `mailer.js` — Mailgun-SMTP-Versand (Verifizierung, Passwort-Reset, Morning-Brief-E-Mail;
  Fallback: Konsolen-Log)
- `stripeClient.js` — Legt Stripe-Produkte/Preise je Abo-Stufe an

**Preispläne (aktuell):** Basic 19 $ (1 Sitzplatz), Pro 49 $ (1 Sitzplatz), Desk 99 $
(1 Sitzplatz, `apiAccess`), Team 399 $ (5 Sitzplätze, `apiAccess`), Institutional 799 $
(10 Sitzplätze, `apiAccess`) / Monat — plus 14-Tage-Pro-Testphase ohne Kreditkarte, siehe
Abschnitt 6. Die alten Preise (49/99/199 $) bleiben als `LEGACY_PLAN_PRICES` in `config.js`
erhalten, werden aber nirgends mehr angewendet, da sie inzwischen höher als die aktuellen
Preise sind (Grandfathering greift nur, wenn der alte Preis tatsächlich günstiger wäre).

**Resilienz-Prinzip:** Alle "ensureFresh"-Funktionen (Futures, Basis, Freight) fragen ihre
Datenquellen parallel statt sequenziell ab und fangen jeden Fehler einzeln ab — ein
langsamer oder ausgefallener Upstream-Call für ein einzelnes Symbol/Bundesstaat blockiert
nie die gesamte Anfrage; es wird einfach der zuletzt gecachte Wert für diesen einen Fall
weiterverwendet. Das gleiche "lazy, kein Cron nötig"-Prinzip trägt jetzt auch die
Testphasen-Ablaufprüfung in `requireAuth.js` und die Status-Seite (liest nur Cache-Timestamps).

---

## 5. Auth-Flow

1. Registrierung → 8-stelliger Code per Mail (Mailgun); optionales Referral-Code-Feld
   (= Username eines bestehenden Users) setzt `referred_by`
2. Code-Eingabe → `/verify-email` → JWT wird ausgestellt
3. Login erfordert verifizierten Account; **E-Mail oder Username** funktionieren gleichermaßen
4. **Passwort vergessen:** `/forgot-password` (E-Mail oder Username) → 8-stelliger Reset-Code
   per Mail, unabhängig davon ob der Account existiert (keine Rückschlüsse möglich) →
   `/reset-password` (Code + neues Passwort) → neues Passwort wird gesetzt, User ist sofort eingeloggt
5. Desktop: Login läuft in eigenem kleinen Fenster; nach Erfolg öffnet sich das volle
   App-Fenster mit Session, Login-Fenster schließt sich
6. Session wird lokal (`shared_preferences`) zwischengespeichert und beim Start via `/me`
   wiederhergestellt

---

## 6. Billing-Flow

1. Nutzer wählt Plan in den Settings → `POST /v1/billing/checkout`
2. Backend legt (falls nötig) Stripe-Produkt/Preis an, erstellt Checkout-Session, gibt Hosted-URL zurück
3. App öffnet die URL im Browser
4. Nach Zahlung: Stripe leitet auf `/billing/success` um — diese Route liest die Session direkt
   bei Stripe aus und setzt `subscription_tier` (zuverlässiger als der Webhook, da die
   Desktop-App keine öffentlich erreichbare Webhook-URL hat); löscht dabei auch ein eventuell
   noch laufendes `trial_ends_at` und speichert `stripe_customer_id`
5. Direkt danach: `referrals.creditReferrerIfEligible()` prüft, ob dieser User über einen
   Referral-Code geworben wurde und noch nie konvertiert ist — falls ja, bekommt der Werber
   eine echte Stripe-Customer-Balance-Gutschrift in Höhe eines Monatsbeitrags (automatisch auf
   der nächsten Rechnung verrechnet, oder gutgeschrieben sobald der Werber selbst abonniert)
6. Kündigung (`customer.subscription.deleted`) setzt den Nutzer zurück auf `free`

**14-Tage-Testphase (kein Checkout nötig):** `POST /v1/billing/start-trial` setzt
`subscription_tier='pro'` + `trial_ends_at` (einmal pro Account, `has_used_trial`-Flag
verhindert Wiederholung). Kein Kreditkarten-Schritt. Läuft die Frist ab, stuft
`requireAuth.js` beim nächsten authentifizierten Request lazy zurück auf `free`.

---

## 7. Datenmodell-Besonderheiten

- **Basis-Daten sind pro Bundesstaat, nicht pro einzelnem Elevator.** USDA AgTransport
  meldet einen Bid/Basis-Wert je Bundesstaat-Markt und Rohstoff pro Woche — alle Elevatoren
  im selben Bundesstaat teilen sich denselben Wert. Das Elevator-Verzeichnis selbst
  (116 real benannte Firmen/Standorte in 27 Bundesstaaten, von der Corn-Belt-Region bis zu
  Gulf-Coast- und Pacific-Northwest-Exportterminals) ist statische Referenzdaten. **Live
  USDA-Basispreise sind für 13 dieser Bundesstaaten verdrahtet** (IL, IA, MN, IN, OH, KS,
  NE, SD, ND, NC, MT, OK, WA — siehe `STATE_MARKET_NAMES` in `usdaBasis.js`, direkt gegen
  den echten `agtransport.usda.gov`-Endpoint verifiziert). Elevatoren in den übrigen 14
  Bundesstaaten erscheinen auf Grid/Map/Liste (über `GET /elevators`, unabhängig von
  `/basis-overview`), zeigen aber bewusst keinen Basiswert statt eines Fake-Werts, bis die
  passenden USDA-AgTransport-Marktnamen für diese Bundesstaaten verifiziert und ergänzt
  werden. Die USDA-Grain-Basis-Datenquelle selbst deckt nur 5 Commodities ab (Corn, Soybeans,
  Soft/Hard Red Winter, Hard Red Spring Wheat) — das ist die vollständige Obergrenze dieser
  Datenquelle, keine unvollständige Implementierung; eine zweite USDA-Quelle führt zusätzlich
  Durum und Soft White Winter Wheat, aber ohne Futures-Preis-Feld, weshalb daraus keine
  echte Basis (Cash − Futures) berechenbar ist, ohne einen Futures-Bezug zu erfinden.
  **Geprüft und verworfen:** eine weitere State-Coverage-Erweiterung um WI, MO, MI, AR, MS,
  LA, TN, KY, TX, CO, ID wurde live gegen beide USDA-AgTransport-Datensätze (`v85y-3hep`
  Grain Basis, `g92w-8cn7` Grain Prices) geprüft — keiner der elf Bundesstaaten hat dort
  einen eigenen `market_name` unter `market_type='Elevator Bid'`. Das ist eine harte Grenze
  der kostenlosen Datenquelle, keine offene Aufgabe; es gibt lediglich einen einzigen,
  keinem Bundesstaat eindeutig zuordenbaren Sammelpunkt namens "Southeast" (Koordinate an
  der MS/AR-Grenze).
- **USDA-Report-Vergleichstabellen werden deterministisch berechnet**, nicht von Claude
  generiert — nur die Überschrift/Zusammenfassung/Risikofaktoren kommen von der KI, basierend
  auf den echten, vorher berechneten Zahlen. So können keine Zahlen "halluziniert" werden.
- **Alerts sind nicht nutzerspezifisch** — es gibt noch keine Watchlist-/Personalisierungsfunktion
  für den globalen Alert-Feed, daher sehen alle Nutzer denselben Basis-Alert-Feed (entspricht
  dem bisherigen UI-Verhalten); nur `custom_alert_rules` und `price_targets` erzeugen
  User-spezifische Alerts (`user_id` gesetzt).
- **Alert-Outcome wird live berechnet, nicht gespeichert.** `GET /alerts` vergleicht bei jedem
  Request den in `metadata` gespeicherten Wert-zum-Zeitpunkt-des-Alerts mit dem aktuellen
  Basis-/Preis-Snapshot — dadurch bleibt der Vergleich immer aktuell, ohne einen separaten
  Hintergrund-Job zu brauchen.
- **Referral-Code = Username.** Kein separates Code-Feld nötig, da Usernames ohnehin
  eindeutig und schon Teil des Schemas sind — reduziert die Angriffs-/Kollisionsfläche auf null.
- **WASDE Surprise Tracker kann nicht rückwirkend bis 2015 befüllt werden** — Alpha Vantages
  kostenloser Tarif liefert nur ca. 100 Tage Historie, keine 10 Jahre. Der Tracker sammelt
  deshalb ab jetzt echte Daten und vergleicht neue Überraschungen nur gegen die eigene,
  wachsende Historie — bewusst kein Fake-Backfill.
- **Status-Seite und Datenquellen-Tooltips teilen sich eine einzige Quelle der Wahrheit**
  (`dataSources.js`), damit das Label, das der User im Tooltip sieht, nie von dem abweicht,
  was die Status-Seite über dieselbe Quelle sagt.

---

## 8. Offene Punkte / nächste Schritte

- **EIA-Regionaldaten (PADD)**: Der bestehende Energy-Screen (`eiaInventory.js`) fragt aktuell
  nur den US-Gesamtwert ab (`duoarea=NUS`). Live gegen die EIA-API verifiziert: echte
  PADD-1-5-Regionaldaten (inkl. Unterregionen 1A/1B/1C) sind verfügbar und ungenutzt — ein
  echter, noch nicht gehobener Präzisionsgewinn (z. B. Golfküste separat von Westküste).
- **Baltic Dry Index / Ocean Freight Rates**: noch nicht angebunden, ergänzt den bestehenden
  Freight-Screen (aktuell nur Inland-Trucking/Barge über EIA-Diesel-Index) um Übersee-Fracht,
  relevant für die bereits vorhandenen Gulf-/PNW-Exportterminals im Elevator-Verzeichnis.
- **Brasilien/Argentinien-Erntedaten** (CONAB, Buenos Aires Grain Exchange): noch nicht
  angebunden — größte Konkurrenz-Exporteure der USA, relevant für Weltmarktpreis-Kontext.
- **Mississippi River Barge Levels / Lock & Dam Status** (US Army Corps of Engineers): noch
  nicht angebunden — Niedrigwasser beeinflusst Basis-Preise direkt, sehr grain-spezifisches
  Signal ohne generisches Finanz-Terminal-Äquivalent.
- **Tägliche Basis-Auflösung**: aktuell nur wöchentlich möglich (USDA AgTransport-Limit). Für
  echte Tagesdaten wäre ein kostenpflichtiger Anbieter (DTN, Barchart Cash Grain) nötig —
  bisher nicht beauftragt.
- **Cloud Scheduler für Morning-Brief-E-Mail muss noch manuell eingerichtet werden**: ein Job,
  der täglich um 7:30 ET `POST /v1/daily-brief/send-now` mit Header `X-Cron-Secret` aufruft.
  Der Code ist fertig, die Infrastruktur (Scheduler-Job + `CROPLOO_CRON_SECRET`-Secret) fehlt noch.
- **Echte Push-Benachrichtigungen (Mobile/Desktop) sind nicht gebaut** — bräuchte ein
  FCM/APNs-Projekt und Plattform-spezifisches Client-Setup (Entitlements, Service Worker fürs
  Web), das dieses Repo noch nicht hat. Der "Desktop push"-Schalter in den Settings ist
  bewusst deaktiviert ("coming soon") statt eine Funktion vorzutäuschen, die nicht existiert.
- **Excel-Export (.xlsx)** ist nicht gebaut, nur CSV (öffnet sich problemlos in Excel) — ein
  echter `.xlsx`-Export bräuchte eine zusätzliche Dependency.
- Alpha Vantage Free-Tier-Limit (25 Requests/Tag) kann bei intensivem Testen zwischenzeitlich
  ausgeschöpft sein — Futures-Kurse fallen dann automatisch auf den letzten gecachten Stand
  zurück (jetzt zusätzlich über den Offline-Cache im Frontend abgefedert), kein Fehler.
- **Economic Calendar (Macro-Screen)**: FMP `/stable/economic-calendar` ist im kostenlosen
  FMP-Tarif kostenpflichtig (HTTP 402) — Endpoint liefert bis zu einem bezahlten FMP-Plan
  bewusst eine leere Liste statt Fake-Daten.
- **Barchart Cash Grain / DTN**: für echte tägliche (statt wöchentliche) Basisdaten weiterhin
  nicht angebunden — kostenpflichtiger Anbieter, bisher nicht beauftragt (siehe auch oben,
  „Tägliche Basis-Auflösung").
- **Native Mobile-Apps (iOS/Android)**: kein Plattform-Scaffolding in diesem Repo vorhanden
  (kein `ios/`/`android`-Runner-Setup für Push/Store-Distribution) — App läuft aktuell nur als
  Web- und Desktop-Build. Push-Benachrichtigungen (s. o.) hängen ebenfalls daran.
- **Croploo Learn-Artikel und Elevator-Verzeichnis** sind bewusst statische Redaktions-/
  Referenzdaten, kein API-Anschluss — das ist Absicht, kein offener Punkt, aber zur Klarheit
  hier vermerkt.
- **Downloads-Website (`website/`)**: Die Download-Seite verlinkt auf `website/downloads/
  croploo-{windows-setup.exe,macos.dmg,linux.AppImage}` — diese Installer-Dateien existieren noch
  nicht im Repo (nur Flutter-Build-Cache unter `build/`). Sobald Release-Builds für die drei
  Plattformen erzeugt werden (`flutter build windows|macos|linux`), müssen die Artefakte unter
  diesen Pfaden abgelegt werden (siehe Abschnitt 9).

---

## 9. Marketing-Website (`website/`)

Statische Marketing-/Download-Seite, unabhängig von der Flutter-App, im selben Design-System
gebaut (reines Schwarz, 1px-Haarlinien-Borders `#1F1F1F`, `BorderRadius.zero`, Poppins für UI-Text,
JetBrains Mono für Zahlen/Daten — dieselben Fonts wie `lib/core/theme/typography.dart`, als
lokale TTFs unter `website/assets/fonts/` eingebettet, kein Google-Fonts-CDN). Windows-Icon
ist ein generisches Vierfeld-Symbol, macOS ein Apfel-Umriss, **Linux ein selbst gezeichnetes,
erkennbares Tux-Pinguin-SVG** (Kopf/Augen/Schnabel/Körper/Füße) statt eines generischen Blobs.

- **Seiten:** `index.html` (Haupt-Landingpage), `about.html`, `contact.html` (Mailto-Formular,
  kein Backend-Versand, im Formularhinweis transparent gemacht), `privacy.html` — alle mit
  identischem Header/Footer/Nav-Markup und `.page-hero`/`.prose`-Klassen für den Inhaltsteil.
  Footer verlinkt auf allen Seiten konsistent zu About/Contact/Privacy statt Platzhalter-Ankern.
- **Struktur:** `website/{index,about,contact,privacy}.html`, `website/css/style.css`,
  `website/js/main.js`, `website/assets/{fonts,img}/`, `website/downloads/` (Ablageort für die
  eigentlichen Installer).
- **Kein Build-Schritt** — reines HTML/CSS/JS, direkt deploybar (z. B. als statischer Cloud-Run-
  Service oder Cloud-Storage-Bucket neben dem Backend), keine Abhängigkeiten/Frameworks.
- **Sektionen (index.html):** Ticker-Tape-Marquee (spiegelt `BasisTicker`-Optik), Hero mit
  echtem USDA-Analyzer-Screenshot (statt SVG-Mockup) und Zähler-Animation, Feature-Grid,
  **scroll-gepinnte Screenshot-Galerie** (siehe unten), Markets-Grid, Download-Karten für
  Windows/macOS/Linux (Web-App-Karte entfernt) mit automatischer Plattformerkennung
  (`navigator.platform`/`userAgent`, hebt die passende Karte hervor), Datenquellen-Chips
  (Label-Zeile "Real data, not simulated" entfernt — die Chips sprechen für sich), Pricing,
  Sicherheitshinweis zu SHA-256-Prüfsummen.
- **Scroll-gepinnte Screenshot-Galerie:** Jeder Screenshot sitzt in einer eigenen ~320vh
  hohen `.pin-track`; die `.pin-stage` bleibt per `position: sticky` mittig im Viewport
  "kleben", während Skalierung/Opacity/Blur **pro Frame direkt aus der Scroll-Position**
  berechnet werden (kein IntersectionObserver, kein einmaliger Trigger) — mit Lerp-Glättung
  (`main.js`, Faktor 0.07/Frame) für ein flüssiges, nicht rucken des Nachlaufen statt 1:1-
  Sprüngen. Timing: Bild ist nach 14% der Strecke voll da, hält bis 92%, Text erscheint erst
  ab 68%. Bilder nutzen `object-fit: contain` (kein Beschnitt).
- **Reveal-System (`main.js`):** IntersectionObserver-Elemente (`.reveal` + Richtungs-
  Modifier `reveal-left/right/scale/pop`) bekommen jetzt zusätzlich eine `.leaving`-Klasse,
  wenn sie oben aus dem Viewport scrollen (Blur+Fade-Out, reversibel beim Zurückscrollen) —
  nicht nur ein einmaliges Rein-Fade beim ersten Erscheinen. Section-Überschriften bauen sich
  zusätzlich Wort für Wort auf (Blur→scharf, gestaffelt 45ms/Wort).
- **Custom Cursor:** Punkt + Ring nutzen `mix-blend-mode: difference` mit fixem Weiß —
  invertiert sich dadurch automatisch pixelgenau zum Hintergrund (weiß auf dunkel, schwarz
  auf hell), ohne Theme-Tracking in JS.
- **Offener Punkt:** Die drei Download-Links zeigen auf `website/downloads/croploo-*` — dort
  liegen aktuell keine echten Installer, nur ein Platzhalter. Muss beim ersten Release-Build
  befüllt werden (siehe Abschnitt 8).
