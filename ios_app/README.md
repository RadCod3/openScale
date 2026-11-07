# openScale for iPhone — native 0.2.0 prototype

Native SwiftUI / CoreBluetooth port, focused initially on the unknown scale used with **OKOK International** (`com.chipsea.btWeighEn`). Requires iOS 17 or later. No third-party runtime dependencies or vendor binaries are bundled.

## Run on an iPhone

1. Open [openScale.xcodeproj](openScale.xcodeproj) in Xcode.
2. Select the **openScale** scheme and your physical iPhone.
3. In **Signing & Capabilities**, choose your development team and change the prototype bundle identifier if necessary. Run the app.
4. For GATT scales, confirm age, height and the scale's sex setting in **Settings → Set up your profile**.
5. On the first visit to **Weigh in**, tap **Search for my scale**, wake the scale, and select the matching device once. Unnamed supported broadcasts appear as **OKOK scale**; the remembered device uses **Your OKOK scale**. A broadcast-only scale does not need profile setup.
6. Next time, open **Weigh in** to listen for your remembered scale automatically. Keep this screen visible and the app in the foreground, step on the scale, and stand still. The status moves through searching/waiting, measuring, captured, and saved. By default, review the captured final reading and tap **Save measurement**, or **Discard**.
7. To save final readings automatically, enable **Settings → Save settled readings automatically**. It is off by default. **Undo automatic save** removes the exact last automatic record; Undo lasts for the current app session until another automatic save replaces it. Moving readings are never saved.
8. Use **Stop** to stop listening or **Listen for your scale** to retry. **Change scale** forgets the selection and searches again; it is available when no captured reading is awaiting review. Listening stops when you leave the tab or the app enters the background. Opening Weigh in again resumes a remembered scale; it does not listen in the background.

The Simulator can verify the app interface but cannot verify communication with your scale. Public distribution is not configured; see the [licensing assessment](../docs/ios-port-feasibility.md#licensing-and-distribution-gate).

## Implemented

- Local SQLite history, weight chart, manual entry, comments, deletion, kg/lb/decimal-stone display, and one confirmed profile.
- Android CSV import with explicit source weight unit, local timezone interpretation, invalid-row reporting, custom-column retention, and timestamp duplicate protection. Export writes weight in kilograms. ZIP/photo backups and multiple users are outside this milestone.
- Foreground discovery, remembered-scale listening, and bounded diagnostic export. Selection persists by CoreBluetooth UUID and, where present, an exact recognized embedded broadcast identity; a friendly name alone never selects a device. The Bluetooth prompt appears when searching first needs access.
- Experimental Chipsea-BLE GATT: FFF0 service, FFF1 notifications, FFF2 user/time sync; CA10 and CA11 live/locked parsing and multipart live readings.
- Experimental OKOK manufacturer broadcast: checksummed CA20 and CA11, plus plain C0. The vendor IPA establishes that CA11 broadcast and GATT use different layouts.
- Live readings stay previews. Final readings use manual review by default, with optional automatic saving and an exact-record Undo. A pending captured reading blocks another search, device selection, or Change scale.
- A persisted receipt suppresses an identical repeated final reading from the same scale across sessions and restarts, including after Undo or Discard. A fresh moving-weight sequence or changed final weight permits a new capture; step off and back on for another weigh-in. Undo does not make stale final broadcasts eligible again.
- Explicit native status labels distinguish Ready to weigh, Searching, Waiting for your scale, Measuring, Captured, Saved, Stopped, and Needs attention.

**Weight capture confirmed by the user in LiveContainer with version 0.1.1.** The unbranded scale uses plain C0 broadcasts; its diagnostic shows device selection, moving property 0x24, then locked final property 0x25. This confirms the tested device and foreground capture flow, not every scale supported by OKOK International. Encrypted C0 and newer CsYun/cloud variants remain diagnostic-only; body-composition formulas for advertisement-only impedance have not been ported. Unsupported nearby devices are listed but receive no arbitrary sync writes. See [protocol evidence and unknowns](../docs/chipsea-ios-protocol.md).

Version 0.1.1 fixes recognition of the plain C0 variant found in the first
LiveContainer diagnostic. Its property byte sets bit 5, which the initial
prototype rejected. Recognition and final/live decoding pass replay tests;
the subsequent hardware diagnostic and user report confirm successful capture.
All 14 core tests and the unsigned iPhone Release build passed for that update. Native 0.2.0 adds remembered listening and optional automatic save; those additions have not yet been verified with the physical scale.

## Hardware checks

Close the vendor app while testing so it does not hold the connection. Take several readings and compare kilograms with the scale display and vendor app. Check that moving weight remains live and that a final reading saves only once. Retry after disconnecting and toggling Bluetooth. For 0.2.0, also verify remembered selection after reopening Weigh in and restarting the app, manual versus automatic save, Undo, stale final-packet suppression, and a fresh weigh-in at the same weight.

If the protocol is not identified or no final reading arrives, use **Share Bluetooth diagnostics** after a search/weigh-in. This report includes nearby device identifiers and raw Bluetooth payloads; review it before sharing. Diagnostics remain in memory until the user exports them. A failed attempt is useful evidence; it is not proof the scale is incompatible.

## Tests

From this directory:

```sh
swift test
xcodebuild -project openScale.xcodeproj -scheme openScale \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Choose an installed simulator with `xcrun simctl list devices available`. Core tests run on macOS and cover Android golden vectors, multipart recovery, broadcast checksums and stability, encrypted-packet rejection, units, CSV quoting/date handling/round trips, and SQLite persistence/atomic imports. UI tests use an isolated in-memory database and labeled synthetic fixtures; they never seed production history.

Earlier prototype validation on 7 November 2026: all 13 core tests passed; the iPhone 18 Pro Simulator UI workflow passed manual-entry validation, saving, profile setup and tab navigation. Final screenshots were reviewed in light appearance and dark appearance at the largest accessibility text size. Both simulator Debug and unsigned iPhone Release builds compiled with Xcode 27.1. These earlier simulator checks do not verify the new automation or radio communication. Current 0.2.0 validation: 18 core tests have passed, including remembered matching, final-packet suppression, and exact-record deletion for Undo. All three synthetic Simulator UI tests passed: baseline entry/navigation, remembered listening at dark accessibility-XXXL size, and automatic save/Undo/repeated-packet/manual-review flow. The scoped native finish review passed the inspected listening, saved, review, Settings and dark large-text captures. The unsigned iPhone Release build passed and the 0.2.0 IPA was packaged. Physical-device VoiceOver and 0.2.0 hardware automation testing remain pending.

The measurement database is excluded from automatic device backup. Export a CSV for a portable copy. HealthKit, background capture, multi-user routing, notifications, and App Store release are later milestones.

## License and provenance

GPL-3.0-or-later, as in the [repository license](../LICENSE). Chipsea GATT decoding and synthetic vectors are ported from the Android implementation. Broadcast layouts are reconstructed from that source and static protocol observations documented in the evidence report. No vendor framework, artwork, cloud endpoints or credentials are required by the app.
