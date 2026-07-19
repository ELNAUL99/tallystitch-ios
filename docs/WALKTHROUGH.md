# Code walkthrough — every file, line by line

A guided read of the entire codebase, written so you can open any file in
Xcode and understand every line in it. [ARCHITECTURE.md](../ARCHITECTURE.md)
says *why* the design is what it is; [INTERNALS.md](INTERNALS.md) explains the
mechanisms; this document walks the actual code.

**How to read it:** Part 0 explains each recurring Swift construct once.
The per-file sections then walk the code top-to-bottom and only stop on
lines that do something beyond those idioms. Line numbers refer to the
`feat/targeted-injection` branch.

---

## Part 0 — the Swift idioms this codebase uses everywhere

**`enum SomeService { static func … }` (case-less enum).** An enum with no
cases can never be instantiated — Swift's idiom for a pure namespace of
functions. All services (`MaterialsService`, `StockMath`, `Formatting`, …)
use this: they hold no state, so nothing should be able to create one.

**`struct` for views and models, `class` for stores.** Structs are value
types — copied on assignment, no identity. SwiftUI views are throwaway
descriptions recreated constantly, so they're structs. Stores
(`AuthStore`, `ProfileStore`) must be the *same object* everywhere (every
screen must see the same session), so they're classes — reference types.

**Property wrappers** (the `@Something` before a property):
- `@State` — view-local storage that survives the view struct being
  recreated. Used for form fields, `busy` flags, fetched lists.
- `@StateObject` — the view *creates and owns* an `ObservableObject`,
  exactly once for the view's lifetime. (`@ObservedObject` would recreate
  it on every parent re-render and wipe its state — the classic bug.)
- `@EnvironmentObject` — receives an object an ancestor injected with
  `.environmentObject(...)`. How `AuthStore`/`ProfileStore` reach every view.
- `@Published` — a property on an `ObservableObject` whose changes trigger
  view updates in any observing view.
- `@Binding` — a read-write reference to state owned by someone else
  (`$row` passes a binding; the child edits the parent's value).
- `@Environment(\.dismiss)` — grabs a system value; calling `dismiss()`
  pops/closes the current screen.
- `@MainActor` — everything in this type runs on the main thread; touching
  it from a background thread is a *compile error*, not a runtime crash.
- `@ViewBuilder` — lets a closure contain multiple views / if-else and be
  assembled into one; how `Card { … }` accepts arbitrary content.

**Concurrency:**
- `func f() async throws` — asynchronous and can fail; called with
  `try await f()`.
- `Task { await … }` — bridge from a synchronous place (a button tap) into
  async work.
- `async let a = …; async let b = …; try await (a, b)` — start two async
  jobs *in parallel*, then wait for both.
- `[weak self]` in a closure — capture self without keeping it alive, so a
  long-running task doesn't create a retain cycle.

**Optionals:**
- `String?` — a value or `nil`. `??` provides a fallback; `?.` chains
  safely; `if let x { }` / `guard let x else { return }` unwrap.
- `optional.map { transform($0) }` — transform *if present*, else nil:
  `salePrice.map { String($0) } ?? ""`.

**Codable:** `struct X: Codable` + `enum CodingKeys: String, CodingKey`
maps JSON keys to properties. Every model maps Postgres `snake_case`
(`"cost_per_unit"`) to Swift `camelCase` (`costPerUnit`). One-off
`struct Row: Encodable` types inside service functions define exactly the
JSON a request sends — nothing more.

**Closures:** `{ $0.value < 0 }` — `$0` is the first argument. Trailing
closure syntax drops the parentheses: `list.filter { … }`. A key path
`\.isLowStock` is shorthand for `{ $0.isLowStock }`.

---

## Part 1 — build & configuration

### project.yml (the XcodeGen definition)

- **Header comment** — the `.xcodeproj` is generated, never edited; this
  YAML is the source of truth (`xcodegen generate`).
- **`options`** — bundle-id prefix, iOS 16 deployment floor.
- **`packages`** — two SwiftPM dependencies: the local
  `Packages/TallystitchCore` and `supabase-swift` from GitHub.
- **`targets.Tallystitch`** — the app: sources folder, both package
  dependencies, then `settings.base`: bundle id, versions,
  `SWIFT_VERSION 5.7` (Swift-5 language mode on the Swift 6 compiler),
  iPhone-only, `GENERATE_INFOPLIST_FILE: NO` because the plist is
  regenerated from the `info:` block below.
- **`configFiles`** — points Debug and Release at `Secrets.xcconfig`, which
  injects `SUPABASE_URL` / `SUPABASE_ANON_KEY` as build settings.
- **`info.properties`** — the custom Info.plist keys. They MUST live here:
  XcodeGen rewrites the plist on every generate, and keys present only in
  the file get wiped (learned by losing them). Includes the two Supabase
  keys as `$(VAR)` substitutions and `CFBundleURLTypes` registering the
  `tallystitch://` scheme for deep links.
- **`scheme.testTargets` + `TallystitchTests` target** — the app-level unit
  test bundle (new on this branch), with `GENERATE_INFOPLIST_FILE: YES`
  so the test bundle gets a plist automatically.

### Packages/TallystitchCore/Package.swift

Standard SwiftPM manifest. The important line is
`platforms: [.iOS(.v16), .macOS(.v12)]` — the macOS floor is what lets the
core compile and verify on a Mac with no Xcode at all. One library target,
one test target; **zero dependencies** — the whole point of the package.

### Tallystitch/Config/Secrets.example.xcconfig

Template for the gitignored `Secrets.xcconfig`. The odd
`https:/$()/…` form exists because `//` starts a comment in xcconfig —
`$()` (empty substitution) splits the slashes. Publishable key only; the
service-role key must never appear here.

---

## Part 2 — TallystitchCore (the pure domain package)

### Models.swift

Line-by-line it is one pattern repeated per table, so learn it once:

```swift
public struct Material: Codable, Identifiable, Sendable {
    public let id: String            // immutable identity
    public var name: String          // `var`: editable fields
    …
    enum CodingKeys: String, CodingKey {
        case costPerUnit = "cost_per_unit"   // JSON key mapping
    }
}
```

- `Identifiable` (needs an `id`) is what lets SwiftUI's `ForEach` iterate
  it without an explicit `id:` argument.
- `Sendable` marks it safe to cross concurrency boundaries (it's a value
  type — always true — but stating it prepares for strict checking).
- `SubscriptionStatus` / `OrderSource` are `String`-raw-value enums whose
  raw strings (`"past_due"`, `"etsy_csv"`) are the exact Postgres enum
  labels — all three clients must read them identically.
- `Material.isLowStock` (a computed property): `guard let threshold`
  returns `false` when no threshold is set; otherwise
  `stockOnHand <= threshold` — note `<=`: stock exactly *at* the threshold
  counts as low (pinned by a test).
- `Material` has a hand-written `public init` because adding `CodingKeys`
  suppresses the auto-generated memberwise init for other modules — tests
  need to construct one directly.
- `Access` (bottom of file): the whole subscription gate.
  `hasAppAccess` — `active` always true; `trialing` true only while
  `trialEndsAt > Date()` (strict: expiring *now* means locked); every
  other status false. `trialDaysRemaining` — seconds remaining / 86 400,
  `ceil`ed (half a day left reads "1"), clamped to ≥ 0 with `max`.

### StockMath.swift

Pure mirror of the DB trigger math (header comment pins it to
`tg_order_items_stock`). Never *writes* anything — it predicts.

- `RecipeRef` / `ProductRef` / `OrderLine` — tiny value types carrying
  exactly the fields the math needs; nothing decodes these from JSON.
- `StockMap` is `[String: Double]` — materialId → stock on hand.
  `buildStockMap` folds tuples into that dictionary.
- `applyOrderLine(stock, product, orderQty)` — the core rule. Copies the
  map (`var next = stock` — value semantics make this a real copy), then
  for each recipe item subtracts `recipeQty × orderQty`. Returns the new
  map; the input is untouched (a test pins that). A *negative*
  `orderQty` therefore reverses a sale — one function is both directions.
- `applyOrderLines` — folds many lines; unknown product ids are skipped
  (`guard let product … else { continue }`).
- `computeUnitCost` — Σ(recipe qty × material cost); missing materials
  count 0. Mirrors the DB's `recompute_product_unit_cost`.
- `wouldOversell` — after applying, which materials went below zero?
  `filter { $0.value < 0 }.map { $0.key }`.
- `marginPct` — `(price − cost) / price`; `nil` unless price is positive
  (margin of a free item is meaningless, and it avoids ÷0).

### DashboardMath.swift (new on this branch)

The dashboard aggregation, extracted from the ViewModel so it is testable
with just a compiler — the same reasoning that put StockMath here.

- `Line` — one order line reduced to the three fields aggregation needs:
  optional product name, qty, unit price.
- `ProductAgg` — name / units / revenue; `Equatable` so tests can compare.
- `Summary` — total revenue + `byProduct` (documented: sorted by revenue
  descending).
- `aggregate(_:)` — one pass over the lines: accumulate `revenue`; group
  into a `byName` dictionary (`byName[name] ?? ProductAgg(…)` reads the
  existing bucket or starts one). A `nil` product name buckets under
  `"Unknown"` — a deleted product must not silently drop its revenue from
  the total (a test pins that). Finally sort buckets by revenue.

### Formatting.swift

- `currency` — locale-aware via `NumberFormatter` with a currency code;
  `nil`/NaN → `"—"` (an em-dash reads better than "0" for "no data").
- `qty` — rounds to 2 dp, then: if the rounded value is a whole number,
  print it as an integer (`"3"` not `"3.00"`); otherwise fixed decimals
  (`"2.50"`). Pure string math, so it's testable without locale
  assumptions.
- `percent` — `value × 100` with one decimal and a `%`.

### Tests/ (5 files, 39 tests) and Scripts/

- `StockMathTests` (13) — the deduction rule: unit cost, per-material
  deduction, immutability, shared materials, reversal round-trip, edit
  semantics, oversell flags, margin.
- `FormattingTests` (6) — the string rules above.
- `AccessTests` (6) — the gate: `active` passes even with an expired
  trial, `trialing` is strictly `> now` (boundary test), the other three
  statuses stay locked, `trialDaysRemaining` ceils and clamps.
- `ModelsDecodingTests` (8) — every model decoded from PostgREST-shaped
  JSON (snake_case, ISO-8601 dates with/without fractional seconds,
  nulls). The decoder in the test mirrors supabase-swift's. This is the
  boundary that is runtime-checked only — a renamed column fails here
  instead of in the running app.
- `DashboardMathTests` (6, new) — empty input, revenue summing, grouping +
  sort order, units accumulation, the `"Unknown"` bucket, single-pass
  precision.
- `Scripts/verify.swift` + `verify.sh` — the same high-value checks as
  plain `assert`s, compiled with bare `swiftc` for machines with no
  XCTest (CLT-only). `verify.sh` copies the script to `main.swift`
  (swiftc requires top-level code there) and compiles it together with
  the real source files — so it tests the actual code, not a copy.

---

## Part 3 — the app's service layer (`Tallystitch/Services/`)

### SupabaseManager.swift

- `SupabaseConfig.url / .anonKey` — read `SUPABASE_URL` /
  `SUPABASE_ANON_KEY` from the bundle's Info.plist (where the xcconfig
  placed them at build time). `fatalError` on absence — misconfiguration
  should fail loudly at launch, not mysteriously later.
- `SupabaseManager` — a classic singleton (`static let shared`, `private
  init`) wrapping one `SupabaseClient`. The SDK defaults do the heavy
  lifting: PKCE auth flow, keychain-backed session storage.
- `var supabase: SupabaseClient { SupabaseManager.shared.client }` — a
  global accessor so services read `supabase.from(…)`. This global is
  exactly the "DI problem": anything that calls it directly cannot be
  tested without the network. `DashboardData.swift` is the first seam
  around it (see below).

### AuthStore.swift

The single source of truth for "who is signed in".

- Four `@Published` properties: `session`, `loading` (drives the launch
  spinner), `passwordRecovery` (a recovery link landed; RootView presents
  the set-new-password screen), `linkError` (an incoming link failed;
  RootView shows an alert).
- `init` starts one long-lived `Task` (retained in `authTask`, cancelled
  in `deinit`):
  1. `try? await supabase.auth.session` — seed from the keychain-persisted
     session (cold start); `try?` maps "no stored session" to `nil`.
  2. `for await change in supabase.auth.authStateChanges` — an unbounded
     async stream; every sign-in/out/refresh updates `session`. If the
     event is `.passwordRecovery`, also raise that flag.
  - `[weak self]` because the stream never ends: a strong capture would
    keep the store alive forever (task ↔ store retain cycle) and `deinit`
    would never run.
- `signIn` / `signUp` — email+password. `signUp` passes
  `redirectTo: DeepLink.authCallbackURL` and returns whether a session
  came back — with email confirmation on, it doesn't, and the UI tells
  the user to check their inbox.
- `sendMagicLink` — `signInWithOTP` with the same redirect.
- `resetPassword` — `resetPasswordForEmail`; the emailed link reopens the
  app, the state stream emits `.passwordRecovery`.
- `updatePassword` — `auth.update(user: UserAttributes(password:))` using
  the recovery session (no old password needed), then clears the flag.
- `handleDeepLink` — `supabase.auth.session(from: url)` performs the PKCE
  code-for-session exchange. On failure sets a friendly `linkError`
  instead of failing silently.

### DeepLink.swift

Two constants: the custom scheme (`tallystitch`) and the callback URL
built from it. The handling logic deliberately lives in `AuthStore` so
failures can reach the UI.

### ProfileStore.swift

- One `@Published var profile: Profile?` + `loading`. `currency` is a
  convenience with `"USD"` fallback — every formatter call site reads it.
- `refresh()` — get the user id from the session (if none: clear and
  stop), then select the single `profiles` row (`.single()` returns an
  object, not an array). Errors leave `profile = nil` — RootView then
  falls through to the tab shell rather than locking the user out on a
  transient fetch failure.
- `updateBusiness` / `markOnboardingComplete` — tiny `Encodable` patch
  structs, `update … eq("id", userId)`, then `refresh()` so every screen
  reflows at once.

### MaterialsService.swift

- `Input` — the form's payload; field names are already snake_case so the
  struct encodes directly as the request body.
- `list` / `get` — straightforward PostgREST selects. RLS scopes rows to
  the signed-in user; no client-side filter needed.
- `create` — reads the user id and inserts an explicit `Row`; RLS's
  insert policy requires `user_id = auth.uid()`.
- `delete` — try; if `isForeignKeyViolation(error)` (the material is in a
  recipe → RESTRICT), rethrow as `AppError.message("used in a recipe…")`.
  Everything else rethrows untouched.
- Bottom of file: `AppError` (an error that *is* a user-facing message;
  `LocalizedError` makes `error.localizedDescription` return it) and
  `isForeignKeyViolation` — best-effort string match for `23503` /
  `"foreign key"` (the SDK doesn't surface a typed SQLSTATE here).

### ProductsService.swift

Same skeleton as materials, plus recipes:

- `create` — insert the product, `.select()` echoes the created row back
  (to get its id), then `replaceRecipe`.
- `replaceRecipe` — delete-all-then-insert. Why not diff: the DB trigger
  recomputes `unit_cost_cached` on any recipe change, so the simplest
  correct write wins. First collapses duplicate material rows
  (`byMaterial[r.materialId, default: 0] += r.quantity`) because the
  schema's unique `(product_id, material_id)` index would reject a
  duplicate insert.
- `delete` — same FK translation, message about recorded sales.

### SalesService.swift

- `SaleRow` — a *view-shaped* decodable: the order plus nested
  `order_items(quantity, unit_sale_price, products(name))` exactly as the
  PostgREST projection returns them. Nested `Item` and `ProductName`
  structs mirror the JSON nesting.
- `list` — that projection, newest first, limit 200.
- `create` — the important one. Builds a `Params` struct whose field
  names (`p_user`, `p_items`, …) are the RPC's argument names, then
  `supabase.rpc("create_order_with_items", params:)`. The RPC computes
  gross server-side and runs everything in one transaction (see
  INTERNALS §1). The client never writes order rows directly.
- `delete` — deletes only the parent order; the FK cascade removes items
  and each removal fires the stock-restore trigger. One line of client
  code, real inventory reversal.

### DashboardData.swift (new on this branch — the injected seam)

- `protocol DashboardDataProviding: Sendable` — the *data boundary* the
  dashboard needs: `fetchOrders(since:)` and `fetchMaterials()`. Owned by
  the consumer (the ViewModel needs it, so the app target declares it) —
  the dependency-inversion move.
- `LiveDashboardData` — the production implementation; the same two
  PostgREST queries the ViewModel used to make inline.
- The header comment states the philosophy: one seam where a mock is
  actually needed, not a protocol for every service as doctrine —
  "targeted injection".

### AccountService.swift + SampleDataset.swift

- `deleteAccount` — invoke the `delete-account` Edge Function (the
  service-role key lives server-side; the function re-derives the caller
  from their JWT), then best-effort sign-out.
- `SampleData.load` — three phases with explicit `Encodable` row types:
  materials (insert, `.select("id, name")` to map name → id), products +
  their recipes (per product: insert, keep id, insert recipe rows), then
  backdated orders + items. Every row `is_sample: true`. The item inserts
  fire the real stock triggers — the demo runs through the production
  pipeline.
- `SampleData.clear` — three deletes filtered on `is_sample`, ordered
  orders → products → materials. The order is forced by the RESTRICT FKs,
  and deleting orders first restores stock via the reversal trigger.
- `Sample` (SampleDataset.swift) — the static demo dataset (a candle +
  soap maker), plain nested value types, identical to the web/RN demo.

---

## Part 4 — app entry and views

### TallystitchApp.swift

`@main` marks the entry point. Creates the two stores as `@StateObject`
(owned once for the app's life), injects them with
`.environmentObject(…)`, sets the global accent `tint`, and routes every
incoming URL (`.onOpenURL`) into `auth.handleDeepLink` inside a `Task`
(the handler is async; the callback is not).

### RootView.swift

The app's state machine, written as a chain of `if/else` over store
state — the order *is* the logic:

1. `auth.loading || (signed-in && profile.loading)` → spinner.
2. Not signed in → `AuthFlowView`.
3. Profile says no access (`Access.hasAppAccess` false) → `LockedView`.
4. Profile has no business name and onboarding not completed →
   `OnboardingView`.
5. Otherwise → `MainTabView`.

Modifiers below the `Group`:
- `.fullScreenCover(isPresented: $auth.passwordRecovery)` — the
  set-new-password screen over everything when a recovery link lands.
- `.alert(…)` for `auth.linkError` — the binding is constructed manually
  (`get:` non-nil, `set:` clears) because `.alert` wants a Bool.
- `.task(id: auth.session?.user.id)` — re-runs whenever the signed-in
  user *changes* (not just on appear): refresh the profile, or clear it
  on sign-out.

`LockedView` (same file) — static "trial ended" screen; no purchase path
in-app yet (App Store compliance — see ARCHITECTURE).

### AuthFlowView.swift

Four screens in one file, all built from the same parts:

- `LoginView` — email + password `LabeledField`s, error/message lines,
  three actions: `signIn` (validates both fields non-empty), `magicLink`
  (validates email, sends OTP link, tells the user to check email), and
  navigation to `ForgotPasswordView` (pre-filled with the typed email)
  and `SignupView`.
- `SignupView` — email + password (≥ 8 chars), calls `auth.signUp`; if no
  session came back (email confirmation on), shows "check your email to
  confirm".
- `ForgotPasswordView` — one email field; `auth.resetPassword`; its
  `init(prefillEmail:)` seeds `@State` via `State(initialValue:)` — the
  one legitimate way to initialize view-local state from a parameter.
- `SetNewPasswordView` — new + confirm fields, ≥ 8 chars and equality
  checks, `auth.updatePassword`; on success the store clears
  `passwordRecovery`, which dismisses the cover automatically.
- `LabeledField` — label + bordered `TextField`/`SecureField`; email
  fields disable autocapitalization/autocorrect.

### MainTabView.swift

Five tabs; **each tab wraps its root view in its own `NavigationStack`**
so push/pop state is per-tab (switching tabs doesn't lose your place).

### DashboardView.swift (reworked on this branch)

- `DashboardViewModel` (`@MainActor`, `ObservableObject`): published
  `revenue`, `cogs` (stays 0 — the lean query doesn't fetch cost
  snapshots; commented honestly), `byProduct` (now
  `[DashboardMath.ProductAgg]`), `lowStock`, `loaded`, `error`.
- `init(data: DashboardDataProviding = LiveDashboardData())` — the
  injection point. Production call sites stay `DashboardViewModel()`;
  tests pass a mock. Constructor injection with a default: no DI
  framework, no call-site churn.
- `load()` — `async let` fetches orders and materials in parallel through
  the boundary; flattens SDK rows into `DashboardMath.Line`s
  (`flatMap` over orders → `map` over items); calls
  `DashboardMath.aggregate`; assigns the summary to published state;
  filters `lowStock` with the model's own `isLowStock`. All failure paths
  still set `loaded = true` so the UI never hangs on the spinner.
- `DashboardView` — `@StateObject` owns the ViewModel. Body: business
  name, two `StatCard`s (profit tone: green > 0, red < 0), a "By product"
  `SectionCard` (`ForEach(…, id: \.name)` — grouping guarantees unique
  names), a "Low stock" section with amber `Low` capsules.
  `.refreshable` (pull) and `.task { if !vm.loaded … }` (first appear
  only) both call `load`.
- `StatCard` / `SectionCard` — small styled wrappers over `Card`;
  `SectionCard<Content: View>` is generic over its `@ViewBuilder` body.

### MaterialsView.swift

- `MaterialsListView` — `@State` list + `loaded` + `error`. Empty state
  card with a call-to-action; otherwise rows inside one `Card`, each a
  `NavigationLink` to the edit form, separated by `Divider`s (skipped
  after the last row). `.task` loads on appear; `.refreshable` on pull;
  toolbar `+` pushes the blank form.
- `MaterialRow` — name + cost/unit on the left; stock + amber "Low"
  capsule (driven by `isLowStock`) on the right. `.contentShape(Rectangle())`
  makes the whole row tappable, not just the text.
- `MaterialFormView` — `existing: TallystitchCore.Material?` decides
  add-vs-edit (title, delete button, `seed()` prefill on appear). Numeric
  fields are strings edited with `.decimalPad` and parsed on save
  (`Double(cost) ?? 0`); `save()` trims the name, requires it non-empty,
  builds `MaterialsService.Input`, calls create or update, `dismiss()`es
  on success. `remove()` deletes with the FK-friendly error surfaced.

### ProductsView.swift

Same list pattern. `ProductRow` computes economics inline from the model:
`cost = product.unitCostCached` (the DB-maintained cache), `profit =
price.map { $0 - cost }`, `margin = StockMath.marginPct(…)` — display
logic only; nothing here writes.

### ProductFormView.swift

The most interesting form — live economics:

- State: name/sku/price strings, `rows: [RecipeRowState]` (each a picked
  material id + quantity string), the materials list for the picker,
  `ready`/`busy`/`error`.
- `unitCost`, `priceValue`, `profit`, `margin` are **computed
  properties** — not `@State`. They re-derive from the form state on
  every keystroke; SwiftUI recomputes `body`, so the numbers update live
  with no explicit "recalculate" step. That live feedback is the screen's
  whole point (the file comment says so).
- Body: not-ready → spinner; no materials → "add a material first" card
  (a recipe needs ingredients); else the form: fields, a Recipe section
  with `+ Add material` appending a blank `RecipeRowState`,
  `RecipeRowEditor` per row (bound with `$row`), the live-numbers card
  (`liveRow` helper; profit turns red when negative), Save / Delete.
- `save()` — compactMap the rows into valid `RecipeInput`s (skip empty
  material ids, non-positive quantities), then create or update; the
  service handles the delete-and-reinsert recipe write.
- `RecipeRowEditor` — a `Picker` over materials (tag `""` = "pick a
  material"), a quantity field, a per-unit cost hint, and a Remove
  button that calls the parent's closure.

### SalesView.swift

- `SalesListView` — list of `SaleRow`s. Swipe-to-delete calls
  `SalesService.delete`; the comment explains this is a real inventory
  reversal (DB trigger), not just removing a row; a caption under the
  list says so to the user too.
- `SaleRowView` — date, then each line (`ForEach` over
  `enumerated()` with `id: \.offset` — the nested projection has no ids;
  the index is stable within one row), and revenue on the right:
  `grossAmount ?? Σ(qty × price)` — prefer the stored gross, fall back
  for orders that predate it.
- `SaleFormView` — date picker capped at today (`in: ...Date()` — an
  open-ended range ending now), line editors (product picker + qty +
  price, Remove appears when > 1 line), shipping/fees/notes.
  `prepare()` loads products and seeds the first line with the first
  product's price. `save()` validates lines (positive qty, non-negative
  price), then `SalesService.create` → the atomic RPC → `dismiss()`.

### SettingsView.swift

A `Form` with four sections: workshop (name + currency picker → 
`profile.updateBusiness`), subscription (status label + trial-days via
`Access.trialDaysRemaining`; a caption noting billing is web-only for
now), getting-started (re-open onboarding as a sheet, load/clear sample
data), account (log out, delete account). `onAppear` seeds fields from
the profile. Each async action follows the same busy/message pattern.

### OnboardingView.swift

Four-step wizard mirroring the RN app:

- `counts` (materials/products/orders) drive step completion; loaded by
  three parallel `async let` **head-count queries**
  (`select("*", head: true, count: .exact)` — returns a count, ships no
  rows).
- Steps gate on the previous one (`disabled:` props): basics → material →
  product → sale. Step forms are the *same* form views the tabs use,
  pushed via `NavigationLink`.
- The sample-data card offers the demo shop instead of manual setup.
- `finish()` — `markOnboardingComplete` (sets the timestamp; RootView's
  gate #4 stops matching) and dismiss.
- `StepCard` — numbered circle that turns into a green ✓; content dimmed
  when disabled.

### Theme.swift

- `Palette` — the clay/cream/sage/ink colors as a case-less-enum
  namespace, defined from web hex values via the `Color(hex:)` extension
  (bit-shifts the RGB bytes out of a `UInt`).
- `Card` — the universal container: white, 16 pt rounded corners
  (`.continuous` = squircle), warm 1 px border via `.overlay`.
- `PrimaryButton` — a `ButtonStyle`: clay background dimmed while
  pressed (`configuration.isPressed`), white medium text, full width.

---

## Part 5 — the app-target tests (new on this branch)

### TallystitchTests/DashboardViewModelTests.swift

The first test above the core package — possible *only* because of the
injected seam.

- `MockData: DashboardDataProviding` — returns canned orders/materials,
  or throws `thrown` if set. Eight lines; no mocking framework.
- `material(…)` / `order(…)` helpers build fixtures via the internal
  memberwise inits (`@testable import Tallystitch` grants access).
- `testLoadAggregatesOrdersAndFiltersLowStock` — two orders, three
  materials (one below threshold, one fine, one without threshold);
  `DashboardViewModel(data: mock)`; `await vm.load()`; asserts revenue,
  top product (Candle, 3 units), and that exactly `["Wax"]` is low.
  This exercises the ViewModel's real `load()` — fetch → flatten →
  aggregate → publish — with zero network.
- `testLoadSurfacesErrorsAndStillFinishesLoading` — the mock throws;
  asserts `loaded` still became true (spinner can't hang), `error` is
  set, and state stayed empty.

---

## Appendix — the architecture in one sentence per layer

- **TallystitchCore** — pure rules and shapes; compiles anywhere; owns
  the tests that matter most.
- **Services** — thin async translators between Swift and PostgREST/RPCs;
  no business decisions (those live in the DB or core).
- **Stores** — the two shared truths (session, profile), observable,
  main-actor.
- **ViewModel (dashboard)** — orchestration: fetch through an injected
  boundary, delegate math to core, publish results.
- **Views** — declarative rendering of store/state + user intent; no
  rule lives here.
