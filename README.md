# Tallystitch — iOS (SwiftUI)

Native iOS client for Tallystitch, sharing the same Supabase backend as the
web app and the (React Native) `tallystitch-mobile` app. iOS-only by design;
built for best-in-class native feel.

**In a hurry? [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md)** is the five-minute
tour. **[ARCHITECTURE.md](ARCHITECTURE.md)** has the design rationale, the
single-source-of-truth stock model, the security model, and the known
trade-offs. **[docs/INTERNALS.md](docs/INTERNALS.md)** goes one level deeper:
the mechanics of every moving part (triggers, RLS, PKCE, SwiftUI state,
concurrency) plus two end-to-end traces.

> **Status:** Builds and runs on **Xcode 16 / iOS 16+**. The core domain logic
> (`TallystitchCore`) is covered by XCTest; auth (password, magic link, and
> password reset), the materials/products/sales CRUD, the dashboard, and
> subscription gating are functional against the shared Supabase backend. Not
> shipped to the App Store — CSV import and StoreKit billing are still on the
> roadmap.

## What's here

```
Packages/TallystitchCore/        Pure-Swift domain logic (no UIKit/SwiftUI)
  Sources/.../Models.swift        Codable models mirroring the Postgres schema
  Sources/.../StockMath.swift     Stock deduction + margin (mirror of web stock.ts)
  Sources/.../Formatting.swift    Currency / qty / percent
  Tests/                          XCTest suites (run under full Xcode)
  Scripts/verify.{swift,sh}       Plain-assert runner for CLT-only machines
Tallystitch/
  App/                            App entry, Info.plist
  Config/                         Secrets.xcconfig (gitignored) + example
  Services/                       Supabase client, auth/profile stores, CRUD,
                                  account deletion, sample data
  Theme/                          Warm clay/cream/sage palette + reusable views
  Views/                          Auth, tab shell, dashboard, materials,
                                  products, sales, settings, onboarding
project.yml                       XcodeGen project definition
```

## Architecture

- **TallystitchCore** is a standalone Swift package with zero UI dependencies,
  so the correctness-critical stock math compiles and tests without Xcode and
  stays out of the views — the same separation the web gets from `src/lib`.
- **Services** are thin async wrappers over `supabase-swift`. Sale creation
  goes through the same `create_order_with_items` RPC the web/RN apps use, so
  stock deduction is one atomic transaction across all three clients.
- **Stores** (`AuthStore`, `ProfileStore`) are `@MainActor ObservableObject`s
  injected at the root — the SwiftUI analogue of the RN context providers.
- Account deletion calls the shared `delete-account` Edge Function (a mobile
  client can't hold the service-role key).

## Verifying the core (works on any Mac, no Xcode)

The Command Line Tools can't run `swift test` (no XCTest bundled), so a plain
runner is provided:

```bash
cd Packages/TallystitchCore
./Scripts/verify.sh
```

This compiles the real `StockMath.swift` / `Formatting.swift` and runs the
same checks as the web's test suite. Expected output ends with
`ALL CHECKS PASSED`. On a Mac with full Xcode, prefer `swift test` (runs the
complete XCTest suites in `Tests/`).

## Build requirements (important)

Building the iOS app needs **full Xcode 16+ on macOS 14 (Sonoma) or 15
(Sequoia)** — Apple requires the iOS 18 SDK for App Store submissions. It
**cannot** be built with Command Line Tools alone, and not on macOS 12
Monterey (which caps at Xcode 14.2 / iOS 16 SDK — rejected at submission).

On a capable Mac:

```bash
# 1. Install the project generator
brew install xcodegen

# 2. Configure secrets
cp Tallystitch/Config/Secrets.example.xcconfig Tallystitch/Config/Secrets.xcconfig
#    then edit it with your Supabase URL + publishable key

# 3. Generate and open the Xcode project
xcodegen generate
open Tallystitch.xcodeproj

# 4. Select an iOS Simulator and Run (⌘R)
```

### Supabase dashboard setup (for magic links)
Add to **Authentication → URL Configuration → Redirect URLs**:
- `tallystitch://auth/callback`

## Not yet built (parity roadmap)

- CSV import (web/RN have it)
- Billing — StoreKit 2 / RevenueCat (native SDK is more mature than RN's)
- Launch-screen polish and haptics
- TestFlight distribution via Xcode Cloud or a Mac CI runner
