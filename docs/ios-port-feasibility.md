# iOS port feasibility

Research date: 7 November 2026. Repository snapshot: `35a67c7eea706d0c0cbd6a48b98f7b352960d0a1` (app version 3.1.4).

## Assessment

**An iOS version is technically feasible. A useful first release with a small, tested selection of BLE scales is realistic; full Android scale compatibility cannot be assumed.** The difficult work is reproducing device protocols reliably on iPhones, migrating users' data, and validating behavior on actual scales. Tracking, charts, profiles, and manual entry have no apparent platform blocker.

Given willingness to build a complete native port, **SwiftUI + CoreBluetooth + local SQLite storage is a strong default for an iOS-focused project**. Kotlin Multiplatform (KMP), optionally with Compose Multiplatform, becomes preferable if maintaining one implementation of the algorithms and device drivers across Android and iOS is a long-term priority. These are engineering recommendations, not measured implementation results.

Two early gates apply to either approach:

1. Demonstrate a complete weigh-in on the actual target scale and an iPhone.
2. Establish a viable distribution/licensing route before budgeting for public App Store release.

This was source and documentation research. No iOS target was implemented, compiled, or tested against hardware.

## What exists in this checkout

Counts below are source inventory, including comments and blank lines, not estimates of portable code:

| Area | Finding and evidence |
| --- | --- |
| Build | One Android `:app` module; no iOS target or shared KMP module. [Settings](../android_app/settings.gradle.kts), [app build](../android_app/app/build.gradle.kts). |
| Language and UI | 225 production Kotlin files, approximately 74,246 lines. The `ui` subtree contains 56 files / 22,371 lines and uses Jetpack Compose. |
| Device support | `ScaleFactory.createHandlers()` registers 70 entries, including two configurations of `YunmaiHandler`. This is a driver-entry count, **not 70 independently verified scale models**. [Registry](../android_app/app/src/main/java/com/health/openscale/core/bluetooth/ScaleFactory.kt). |
| Protocol investment | `core/bluetooth/scales`: 77 Kotlin files / 28,623 lines; `core/bluetooth/libs`: 28 files / 7,807 lines. The libraries contain no direct Android/AndroidX imports, but seven import Java/JVM APIs. Transitive dependencies also need inspection. |
| Useful transport boundary | `ScaleDeviceHandler.Transport` already abstracts read, write, subscribe, disconnect, and characteristic lookup. It still exposes BLESSED's Android peripheral; handlers also receive Android `ScanResult`, Android resources, and configuration composables. [Handler base](../android_app/app/src/main/java/com/health/openscale/core/bluetooth/scales/ScaleDeviceHandler.kt). |
| Storage | Room schema version 18, including historical migrations using `SupportSQLiteDatabase`. Types, persistence annotations, and UI metadata are partly mixed together. [Database](../android_app/app/src/main/java/com/health/openscale/core/database/AppDatabase.kt), [measurement types](../android_app/app/src/main/java/com/health/openscale/core/data/MeasurementType.kt). |
| Platform services | Hilt, WorkManager, Glance widgets, Android file/URI APIs, and an external Android sync service require replacement or isolation. [Dependencies](../android_app/gradle/libs.versions.toml), [sync](../android_app/app/src/main/java/com/health/openscale/core/usecase/SyncUseCases.kt), [manifest](../android_app/app/src/main/AndroidManifest.xml). |
| Validation material | 107 files under `src/test`. Protocol tests and scale catalog fixtures can become a language-independent conformance suite. Catalog advertisements are explicitly synthetic; they do not establish hardware compatibility. [Tests](../android_app/app/src/test), [catalog](../android_app/app/src/test/java/com/health/openscale/core/bluetooth/ScaleCatalog.kt). |

For example, `RenphoBodyComposition.kt` and `S400BodyComposition.kt` are promising calculation extraction candidates. Conversely, `ScaleMeasurement` uses `java.util.Date`, measurement keys reference Android-aware types, and `DerivedValuesCalculator` orchestrates database writes: a package called `core` is not automatically portable.

## Bluetooth feasibility and device-specific risks

CoreBluetooth provides the central-role operations required for connected BLE scales: scanning, connection, service/characteristic discovery, reads, writes, and notifications. iOS also exposes manufacturer and service advertising data, making advertisement-only protocols viable in principle. The existing Android [BLESSED Kotlin dependency](https://github.com/weliem/blessed-kotlin) is an Android library, so its transport implementation cannot simply be compiled for iOS. Sources: [Apple central-role guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonCentralRoleTasks/PerformingCommonCentralRoleTasks.html), [advertisement keys](https://developer.apple.com/documentation/corebluetooth/advertisement-data-retrieval-keys).

| Driver / category | Assessment | Specific work or experiment |
| --- | --- | --- |
| Standard GATT (`PlainSigScaleHandler`) | Good first candidate if hardware is available | Confirm discovery, subscription, units, timestamps, stabilization, and reconnect on an iPhone. |
| Xiaomi Mi Scale v1/v2 (`MiScaleHandler`) | Plausible; medium risk | Port its actual GATT history/time/configuration behavior, not just a generic advertisement decoder. Replace peripheral service inspection and Java dates; validate firmware variants. |
| Yunmai X / other broadcast drivers | Plausible foreground support | Validate repeated advertisement delivery through stable weight and final impedance. Yunmai X reconstructs manufacturer bytes whose first two bytes Android treats as company ID; normalize the iOS representation deliberately. |
| Xiaomi S400 | Plausible with setup requirements | Existing driver already has manual MAC and bind-key settings. Supply an authentic hardware MAC independently of iOS identity; replace Java BouncyCastle AES-CCM and verify multi-frame aggregation. |
| Xiaomi S800 | Higher setup/crypto risk | `XiaomiS800Lib` says some measurement frames omit the MAC needed for its nonce. Prove an alternate MAC source or a reliable configuration flow; validate bind key and AES-CCM. |
| Eufy P2/P2 Pro | High risk until hardware trial | Current handshake derives its key from `getPeripheral().address`. Driver comments explicitly say handshake timing has not been hardware verified even on this implementation. Supply hardware MAC separately and test authentication end to end. |
| Huawei Hagrid | High risk | Root-key derivation uses the Bluetooth address, plus Java crypto. Resolve identity/credentials and reproduce the complete authentication session. |
| iHealth HS3 | Potential compatibility exclusion | Uses `CLASSIC_SPP` and Android RFCOMM sockets. Investigate a manufacturer-authorized iOS route; do not promise that the current serial transport ports. |

Driver evidence: [scale implementations](../android_app/app/src/main/java/com/health/openscale/core/bluetooth/scales), [crypto/protocol libraries](../android_app/app/src/main/java/com/health/openscale/core/bluetooth/libs), [RFCOMM adapter](../android_app/app/src/main/java/com/health/openscale/core/bluetooth/scales/SppScaleAdapter.kt).

### Identity and security

CoreBluetooth exposes a system-assigned peer UUID. It does not expose the Android-style hardware MAC API; a peer UUID cannot substitute for the six MAC bytes used in authentication. An accessory can advertise its own identifier, or the user can configure a known hardware MAC. Treat those as separate fields from iOS discovery identity. Apple also cautions that peer UUIDs can change. Sources: [CBPeer.identifier](https://developer.apple.com/documentation/corebluetooth/cbpeer/identifier), [Apple DTS discussion](https://developer.apple.com/forums/thread/851067).

Some parsers compare an embedded MAC against the discovered Android address. On iOS, use the embedded identity where available and preserve signature/checksum validation. Reconstruct manufacturer-data offsets rather than blindly reusing Android's split representation. Do not assume Android bonding or MTU/connection-priority tuning has equivalent iOS controls; use iOS write-size limits and asynchronous completion semantics. These are implementation implications of the source and platform differences, requiring hardware confirmation.

Classic Bluetooth needs a precise distinction: CoreBluetooth's BR/EDR support concerns **GATT over BR/EDR**, not a general RFCOMM/SPP socket. ExternalAccessory supports MFi accessories, with manufacturer-controlled protocols and authorization. That makes the HS3 route unproven, rather than proving all Classic Bluetooth is unavailable. Sources: [WWDC19 CoreBluetooth session](https://developer.apple.com/videos/play/wwdc2019/901/), [ExternalAccessory QA1657](https://developer.apple.com/library/archive/qa/qa1657/_index.html).

### Foreground and background capture

Start with an explicit foreground weigh-in session. Baseline background BLE behavior coalesces duplicate discoveries, can slow scanning, and requires state restoration for recovery. A broadcast scale may need several changing packets for a complete measurement. Sources: [Apple background-processing guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).

Current iOS 26 behavior adds options: Apple's CoreBluetooth documentation describes foreground-equivalent scanning during a Live Activity started before backgrounding. Relaunch rules also have AccessorySetupKit-specific exceptions. Evaluate these separately if background operation matters; do not base a broad compatibility claim on the historical background restrictions alone. Sources: [current CoreBluetooth documentation](https://developer.apple.com/documentation/corebluetooth), [TN3115 relaunch rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules).

## Native versus shared implementation

| Approach | Benefits for this repository | Main costs | Best fit |
| --- | --- | --- | --- |
| **SwiftUI + CoreBluetooth + SQLite** | Direct Apple integration; iOS UI and lifecycle can evolve independently; Android remains untouched | Reimplement domain logic and selected drivers in Swift; ongoing fixes must reach both implementations | An iOS-first product or small curated scale set |
| **KMP core + SwiftUI** | Share calculations, protocol state machines, and potentially persistence; native iOS interface | Extract Android/JVM dependencies, maintain Swift/Kotlin interoperability, and write a second UI | Both platforms matter and native iOS presentation is a priority |
| **KMP + Compose Multiplatform** | Potentially share business logic, driver logic, charts, and much of the existing Compose UI | Broad Android refactor: resources, DI, file access, entry points, platform services, and transport | One team maintaining both platforms with maximum shared behavior |

Compose Multiplatform for iOS is stable; it is a credible production option. The obstacle here is Android coupling, not an inherently experimental UI framework. JetBrains documents a staged Android-to-KMP migration, including replacing Android/JVM APIs and isolating Hilt. Sources: [platform stability](https://kotlinlang.org/docs/multiplatform/supported-platforms.html), [migration guide](https://kotlinlang.org/docs/multiplatform/migrate-from-android.html).

Room and Preferences DataStore have KMP support, so shared persistence need not be discarded. Builders/file paths and the existing Android SQLite migrations still need adaptation. Vico also supports Compose Multiplatform, making charts a reuse candidate pending compilation of this app's specific usage. Sources: [Room setup](https://developer.android.com/kotlin/multiplatform/room), [DataStore setup](https://developer.android.com/kotlin/multiplatform/datastore), [Vico introduction](https://guide.vico.patrykandpatrick.com/).

For a native port, retain SQLite and model the same user/measurement/type/value relationships initially. SwiftData is another possibility, but switching the persistence model at the same time adds migration work. Port calculations and parsers from defined inputs/outputs, backed by the existing fixtures and new cross-language golden vectors. Avoid mechanically translating Android orchestration.

For KMP, first extract models and algorithms; then introduce platform-neutral advertisement data, device identity, GATT metadata, and transport operations. Remove `ScanResult`, `BluetoothPeripheral`, `R` IDs, and device settings UI from protocol interfaces. Use platform implementations behind ordinary interfaces or `expect`/`actual`; no replacement BLE library is required to prove this architecture. Source: [Kotlin platform boundaries](https://kotlinlang.org/docs/multiplatform/multiplatform-expect-actual.html).

Flutter or React Native would retain little direct Kotlin source reuse while still needing iOS Bluetooth integrations and protocol work. Nothing in this checkout makes either an obvious advantage over the two main paths.

## Data migration and Apple integrations

- **Android history:** start by reproducing openScale CSV import/export, including timestamps, units, missing values, device/custom measurement keys, and duplicate handling. Test against files exported by this exact version. CSV is an interchange starting point, not a promise to preserve every setting or photo. Full ZIP/SQLite restore is a separate milestone. [CSV implementation](../android_app/app/src/main/java/com/health/openscale/core/usecase/ImportExportUseCases.kt), [backup implementation](../android_app/app/src/main/java/com/health/openscale/core/usecase/BackupRestoreUseCases.kt).
- **Local operation:** manual entry, profiles, charts, goals, and custom metrics should work without HealthKit or an account. iOS has no equivalent of Android's manifest prohibition on network access; preserve the offline promise through implementation and dependency review. [Current Android guarantee](../android_app/app/src/main/AndroidManifest.xml).
- **Apple Health:** optional HealthKit export can map weight, BMI, body-fat percentage, and lean body mass. Keep unsupported/vendor-specific metrics in the app. Do not equate skeletal muscle with lean body mass, or body-water percentage with water intake. Request permissions by type, handle denial, and use correct percentage units. Sources: [HealthKit types](https://developer.apple.com/documentation/healthkit/data-types), [HealthKit authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).
- **Multiple people:** explicitly select which local profile represents the iPhone owner's HealthKit store. Other people's, babies', and pets' readings must not automatically enter the owner's health record. Define stable sample identifiers and edit/delete reconciliation before enabling automatic export. This is a proposed product constraint.
- **Platform features:** rebuild Android reminders, Glance widgets, file pickers, backups, and external sync integration using iOS capabilities as needed. The Android companion sync service and exported content provider are not reusable iOS integrations.
- **Permissions/release:** ordinary CoreBluetooth access needs its Bluetooth usage description. HealthKit additionally needs capability configuration and appropriate purpose strings. Store review requires a privacy policy and constrains health-data use and accuracy claims. Sources: [Bluetooth purpose string](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription), [HealthKit setup](https://developer.apple.com/documentation/healthkit/setting-up-healthkit), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## Licensing and distribution gate

This repository declares **GPLv3-or-later**. GPL section 10 prohibits imposing further restrictions on recipients. Apple distribution terms and this obligation require review together before a copied or translated port is offered through the App Store. Merely publishing source, charging nothing, or translating Kotlin into Swift does not establish a compatible distribution route. Evidence: [repository notice](../README.md#license-page_facing_up), [GPL text, especially sections 7, 10, and 12](../LICENSE), [Apple standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/), [Apple Media Services terms](https://www.apple.com/legal/internet-services/itunes/us/terms.html).

The FSF has historically challenged GPL distribution through Apple's App Store; that history flags the issue but is not a determination about a future build under all current agreements. [FSF enforcement statement](https://www.fsf.org/news/2010-05-app-store-compliance/).

For planning, resolve rights-holder permissions/appropriate additional permissions or another reviewed distribution route. Check the rights to every reused contribution and dependency; this research did not establish that one maintainer can authorize all code. Treat a genuinely independent implementation and the use of protocol knowledge as a separate rights assessment, not an automatic exception. This report identifies an unresolved release dependency, not a final legal opinion.

A same-named [OpenScale App Store listing](https://apps.apple.com/us/app/openscale/id6759986422) exists under CAN ETHEM BELLIDO. The listing does not establish a relationship with this checkout or demonstrate compatibility with its scale drivers; it should not be mistaken for evidence that this port already exists.

## Proposed first milestone and scope

**Run a small native SwiftUI/CoreBluetooth feasibility spike before committing to the full port.** It can test the highest-risk assumptions even if KMP is chosen later.

1. Use the actual priority scale, plus a representative GATT scale and a broadcast scale if available. Record model, firmware, iPhone, and iOS version.
2. Discover and identify each scale; document every required advertisement field and external credential. Prove any MAC-dependent authentication rather than replacing the MAC with a UUID.
3. Acquire a complete stable measurement, including impedance/body composition where applicable. Verify paired frames, duplicate suppression, disconnect/reconnect, and repeat sessions.
4. Save locally and display one history list/chart. Compare results with Android and the existing parser/calculation vectors, using defined numeric tolerances.
5. Import a real Android CSV and check counts, timestamps, units, custom metrics, and duplicates. Keep background capture and HealthKit export separate experiments.

Acceptance should include repeated real weigh-ins and recovery after Bluetooth toggling, locked-screen/background transitions, interrupted sessions, and denied permissions. Label each device as verified, experimental, or unsupported; never infer iOS coverage from Android registry membership.

### Planning ranges

These are rough **engineering estimates**, not evidence-backed delivery commitments. Assume one experienced mobile developer, available test hardware, a foreground-first app, and timely product decisions. Licensing resolution, review delays, hardware acquisition, and waiting for external contributors are excluded.

| Deliverable | Indicative effort |
| --- | --- |
| Focused BLE + data feasibility spike | 1–2 engineer-weeks for a readily available uncomplicated target; authentication can extend this |
| Useful native MVP: manual entry, profiles, history/chart, CSV, 1–3 verified BLE families | Approximately 2–4 engineer-months total, including the spike |
| Broad Android feature and device coverage | Approximately 6–12+ engineer-months; full parity may remain impossible for specific transports/devices |

There is not enough evidence to claim KMP is faster overall: extraction has an upfront cost, and its benefit grows with shared features and ongoing maintenance. Re-estimate after the spike and one representative screen/data flow in the chosen architecture.

**Recommended decision:** choose native SwiftUI if the immediate objective is a useful iPhone app; choose KMP when shared Android/iOS maintenance justifies the refactor. In either case, make the first commitment about a named, hardware-verified scale set rather than the entire Android catalog.
