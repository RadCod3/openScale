# openScale for iPhone

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Native SwiftUI, Swift Charts, CoreBluetooth, SQLite; Swift Package for testable domain code. User accepted native port following feasibility research.

## Users and purpose

An iPhone owner tracking weight locally with an unknown Chinese scale that works with OKOK International (`com.chipsea.btWeighEn`). The core task is a foreground weigh-in: wake the scale, select it, stand still, review the final reading, and save to history.

## Constraints

Preserve openScale's local operation, no required account, CSV migration and GPLv3-or-later licensing. This first prototype has one profile. The actual scale protocol and hardware compatibility remain unverified. Profile values are confirmed before GATT user synchronization. No vendor binary, artwork, or private service credentials are distributed.

## Evidence

Existing Android implementation and screenshots in `../android_app` and `../docs/screens`. Static wire-format observations are recorded in `../docs/chipsea-ios-protocol.md`. Synthetic protocol vectors verify decoding; they are not hardware captures.

## Open decisions

Public distribution and licensing route; target scale's actual protocol; later multi-user, Apple Health and background requirements.
