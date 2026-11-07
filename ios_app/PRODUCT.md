# openScale for iPhone

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Native SwiftUI, Swift Charts, CoreBluetooth, SQLite; Swift Package for testable domain code. User accepted native port following feasibility research.

## Users and purpose

An iPhone owner tracking weight locally with an unknown Chinese scale that works with OKOK International (`com.chipsea.btWeighEn`). The core task is a foreground weigh-in: select the scale once, then open Weigh in to listen for that remembered scale, stand still, and save the final reading. Review before saving is the default; an optional setting saves settled readings automatically with Undo.

## Constraints

Preserve openScale's local operation, no required account, CSV migration and GPLv3-or-later licensing. This first prototype has one profile. The user confirmed plain C0 foreground capture in LiveContainer with native version 0.1.1. Remembered-scale listening and optional automatic saving in native 0.2.0 remain unverified on hardware. Listening is restricted to the visible Weigh in screen while the app is in the foreground. Profile confirmation is required before GATT user synchronization, not for broadcast-only capture. No vendor binary, artwork, or private service credentials are distributed.

## Evidence

Existing Android implementation and screenshots in `../android_app` and `../docs/screens`. Static wire-format observations are recorded in `../docs/chipsea-ios-protocol.md`. The user's 0.1.1 LiveContainer diagnostic records plain C0 moving (property 0x24) and final (0x25) readings. Synthetic protocol and workflow vectors supplement that device-specific evidence; they do not establish hardware behavior for the new automation. Selected scales are remembered by CoreBluetooth UUID and, when present, exact recognized embedded broadcast identity. Repeated final packets are suppressed across listening sessions and restarts; a fresh moving sequence or changed weight permits a new capture. Undo removes the exact last automatically saved record without clearing that suppression.

## Open decisions

Public distribution and licensing route; hardware validation of native 0.2.0 remembered listening and automatic save; support for additional scale variants; later multi-user, Apple Health and background requirements.
