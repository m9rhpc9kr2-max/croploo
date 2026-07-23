# CROPLOO

**AI-Powered Commodity Market Intelligence Terminal**
*"The basis for better trades."*

Flutter Web + Desktop frontend for the Croploo terminal. Currently runs
fully on realistic mock data with an API-swappable repository layer.

## Run

```bash
flutter pub get
flutter run -d chrome        # web
flutter run -d macos         # desktop
```

## Structure

```
lib/
├── core/
│   ├── theme/          # CroplooTheme, CroplooText, buildCroplooTheme()
│   └── utils/          # Fmt — price/basis/date formatting
├── data/
│   ├── mock_data.dart  # Deterministic mock market data (30 elevators)
│   ├── repository.dart # CroplooRepository interface + mock impl
│   └── providers.dart  # Riverpod providers
├── features/
│   ├── dashboard/      # Daily brief, futures, top deviations, alerts
│   ├── basis/          # Basis Monitor (map/list/chart) + detail
│   ├── usda/           # USDA Analyzer + CullyAI analysis
│   ├── alerts/         # Alert feed + rules
│   ├── freight/        # Corridor rates + freight-basis correlation
│   ├── cullyai/        # Chat panel (mock streaming)
│   └── settings/       # Billing plans, notifications, watchlist
└── shared/
    ├── models/         # Data models with fromJson (API contract)
    └── widgets/        # CroplooScaffold, BasisTicker, SidebarNav, ...
```

## Backend integration

The UI depends only on the `CroplooRepository` interface
(`lib/data/repository.dart`). To go live, implement it with Dio against
`https://api.croploo.app/v1` and swap the binding in
`lib/data/providers.dart` (`repositoryProvider`).

## Design system

- Background `#0A0A0A`, surfaces `#111111`, single accent `#F5C842` (wheat)
- Space Grotesk (headlines) · JetBrains Mono (all numbers) · Inter (body)
- No shadows — 1px borders only, 4px radius
