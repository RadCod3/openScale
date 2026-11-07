---
name: openScale for iPhone
description: Native, measurement-first adaptation of openScale for local weight tracking.
---

# Design System: openScale for iPhone

## Overview

Preserve openScale's measurement-first purpose and blue interactive tint while adapting its Android flows to native iPhone conventions. This is an operating interface built with SwiftUI and Swift Charts. The established product and Android screenshots are the reference; no new visual identity or approved raster composition is implied.

This document records the current implementation in `OpenScale/RootView.swift` and `OpenScale/OpenScaleApp.swift`. Native semantic colors and text styles are the token source of truth. They are described below rather than converted into fixed CSS colors, font sizes, or corner radii. Product scope remains in `PRODUCT.md` and `README.md`.

## Colors

- **Interactive blue:** the app applies SwiftUI `.tint(.blue)` at its root. Native actions and default chart styling inherit this tint.
- **Primary foreground:** system primary text, explicitly used for nearby-device names and otherwise inherited by standard controls.
- **Secondary foreground:** `.foregroundStyle(.secondary)` for dates, sources, protocol descriptions, notices, explanatory text, and additional service details.
- **Surfaces and separators:** system List/Form backgrounds, row backgrounds, and separators. The empty-journal row explicitly uses `Color.clear`.
- **Destructive actions:** semantic `.destructive` button roles for deleting and discarding; retain platform appearance.

**The Semantic Color Rule.** Preserve system appearance adaptation; do not replace these roles with fixed light-theme samples. Production follows system light/dark appearance. A debug launch flag can select dark appearance for UI tests.

## Typography

Use the SF system family through SwiftUI's semantic text styles. No bundled font, custom font size, custom line height, or tracking scale is defined.

- **Navigation:** default large titles at tab roots; inline titles for measurement detail and editing sheets.
- **Journal weight:** `.title2.weight(.semibold)` with `.monospacedDigit()` and vertical expansion via `.fixedSize(horizontal: false, vertical: true)`.
- **Supporting text:** `.subheadline` for measurement dates and device protocol descriptions; `.caption` for measurement sources, advertised services, and invalid CSV row details.
- **Controls and values:** inherited system text styles for Form, List, LabeledContent, buttons, pickers, and field editors. Weight values in live/detail rows currently use standard LabeledContent styling; monospaced digits are explicit only in journal weight labels.

**The Readable Value Rule.** Keep weight units visible beside every weight value and in manual-input labels. Do not depend on tint alone to distinguish live and final readings.

## Layout

Three system tabs provide **Journal**, **Weigh in**, and **Settings**, each with its own NavigationStack. Journal and weigh-in use List; settings and editors use Form. System safe areas, margins, section headers, footers, and standard row sizing establish the layout. Focused entry and profile editing appear in native sheets.

The few local measurements are points: journal content stacks use 6-point spacing; device stacks use 4-point spacing; both add 4 points of vertical row padding. Bluetooth status adds 8 points of vertical padding. The history chart is 200 points tall. These are local implementation values, not a global spacing scale.

Dynamic Type uses semantic styles. At accessibility text sizes, journal rows stack the source below the weight instead of placing it at the trailing edge; chart axes are hidden to reduce crowding while the history list remains available. Other controls retain their native layout behavior. No custom size-class breakpoint, iPad split layout, or orientation-specific composition is implemented.

## Elevation & Depth

The app adds no bespoke shadows. Native grouped surfaces, separators, navigation bars, sheets, and system alerts supply structure and presentation depth. Preserve this system hierarchy when adding screens.

## Shapes

Grouped rows, native controls, and sheets use platform-provided shapes. There is no app-owned corner-radius, border, or custom container scale. SF Symbols identify tabs and familiar actions; pair them with text labels.

## Components

- **Journal:** an empty ContentUnavailableView explains the first measurement and offers a bordered prominent Add measurement action. Populated history uses navigable rows with dates, sources, explicit weight units, and swipe-to-delete. No sample records appear in production history.
- **Weight chart:** native LineMark and PointMark show persisted measurements in chronological order when more than one record exists. The Y domain does not force zero. The chart has an accessibility label naming weight history and the current unit.
- **Weigh-in:** textual status and a search/stop action lead the screen. Distinct section labels identify Live weight and Measurement captured. Save measurement and Discard appear only for a locked reading; a pending locked reading disables another search or device selection.
- **Nearby devices:** names, protocol descriptions, and available services form a vertical row. Unsupported or unavailable choices use native disabled states.
- **Editors:** grouped forms, labeled native inputs, date picker, steppers, and pickers. Cancel and Save use standard toolbar positions. Invalid manual weight and a blank profile name disable Save. Manual weight input has an explicit accessibility label that includes the selected unit.
- **Settings and transfer:** profile and unit settings precede CSV actions. Import exposes a review section with the source unit, ready/invalid counts, and a first-weight sample before confirmation. Native file pickers, file export, and ShareLink handle transfer.
- **Feedback:** model errors use a system alert. Notices and field explanations use text within sections. Diagnostics sharing includes a visible explanation that identifiers and packets are included.

## Do's and Don'ts

- Do retain native tabs, grouped forms, semantic styles, explicit unit labels, and textual live/final status.
- Do keep real history available alongside the chart and use the current accessibility-size row adaptation when extending journal content.
- Do label estimates and imported values consistently with their actual provenance; keep experimental hardware status visible.
- Don't introduce decorative cards, custom shadows, a fixed light palette, or a separate typography system.
- Don't fabricate history, hardware compatibility, or verification evidence.

Verification status: this documentation was extracted from source. The final iPhone Simulator UI test run passed. The finish review inspected five final screenshots: empty journal, saved journal, Settings, Weigh in, and a dark accessibility-XXXL chart/history view. Its scoped verdict was ship, with no material issues in those captures or the two corrected data-preservation findings. Simulator results do not verify Bluetooth hardware behavior. A physical iPhone/scale session and physical-device VoiceOver testing remain unperformed; Dynamic Type adaptations and accessibility labels described above are implementation facts, not a complete accessibility certification. Protocol and hardware unknowns remain documented in `../docs/chipsea-ios-protocol.md`.
