# Chipsea / OKOK iOS protocol findings

Static investigation on 7 November 2026 for the native iOS prototype. The user reports that their unbranded Chinese scale captures a measurement when they stand on it using the supplied app. No radio capture or physical scale was available in this investigation.

## Artifact identity

- Supplied IPA: `com.chipsea.btWeighEn-3.1.56-eeveedecrypter.ipa`.
- IPA SHA-256: `717e8b753109a42dc861f59ad6295574212cafc2e291e07c55f816fff72e11d7`.
- Parsed bundle: `com.chipsea.btWeighEn`; display name `OKOK·International`; version `3.1.56`; executable `OKOKEng`.
- Bundled native protocol library: `Payload/OKOKEng.app/Frameworks/CsBtUtil.framework/CsBtUtil`, arm64 Mach-O; SHA-256 `c248da4cbb990afbb14d838cdd1fb442724470cba866df2ad05cc493a9c00952`.
- REA extraction Evidence: `ev_91aaa4e5e6303b3cc02038819c64dc121908d4614d27f3943d3481414d7397ba`; plist Evidence: `ev_7ca34521bbdd24ea76aaafa5f40e63fa9d3d05f507a6bf972e8b36095e89e6ce`.

The IPA was extracted and inspected, not executed. Proprietary code, assets, credentials, and SDKs are not dependencies of the reconstruction. The observations below concern interfaces, wire-format offsets, and control-flow evidence; they are not recovered original source.

## Main finding

**The reference app supports multiple scale protocols, including advertisement-only scales and connected GATT scales. The IPA alone cannot identify which one the user's physical scale uses.**

The existing Android `OkOkHandler` is relevant alongside `ChipseaBleHandler`. Implementing only the latter risks missing an advertisement-only device. A foreground discovery screen should inspect manufacturer bytes and show protocol candidates, preserve unknown frames for an explicitly exported diagnostic, and let the user select their actual device before recording readings.

## Observed protocol families

| Library implementation | Static evidence | Implication |
| --- | --- | --- |
| `WeightProtocol_Cs` | Discovery at `0x37700` checks `ca20`, `c0`, `ca11`, and `12ffc3` prefixes. Its name checks include `Chipsea-BLE`, `Maginon BT-Scale`, and `zk_tz`. | Try existing OKOK broadcast decoders, with the offset corrections and exclusions below. Names alone are insufficient evidence. |
| `WeightProtocol_Cs` broadcast path | `0x37990` constructs `WeightFrame_Cs` from advertisement bytes and returns decoded broadcast readings. | No GATT connection is required for this path. |
| `WeightProtocol_CsYun` | `0x3833c` recognizes manufacturer prefix `fff0`; characteristic callback at `0x3859c` searches `FFF1`, `2A9C`, or `FA9C`. | Connected cloud-scale protocol; not necessarily the old CA10 user-sync protocol. |
| `WeightProtocol_CsYunV3` | `0x38d9c` recognizes `fff003`. | Separate variant, not covered merely by recognizing service FFF0. |
| `WeightProtocol_CsYunV4` | `0x397b0` recognizes `fff010` or `fff011`. | Separate variant needing its own implementation/hardware evidence. |

REA Evidence: discovery `ev_e877db4bf58bb1d660015f7d9bfb1069ab2df68654e0aef1351aa3fba1a91819`; broadcast `ev_6ba3fde8704f9c9736e87c6d89eebcbb949a84ce7ca967862cc3b4756d0f787a`; CsYun discovery `ev_b4360daa2131cd9f6e7e07896e87005e75c776ac2dc6e24741f1d6b07a180893`; characteristic search `ev_1c462cc3f9f3a374f10c487d51a3258712cfe19539499b615975841f86696d0a`; V3 `ev_67c7044c171cd79b43417d375afa6cec302129f83981757ef0bcd9fb494761b7`; V4 `ev_cf9f0fafbb4b36aee172f49268dfa5cd51756dfe088ceebdbc791dd614d94a98`.

## Manufacturer-data normalization and offsets

All offsets here are into the complete CoreBluetooth manufacturer data, including the first two bytes. Android's `manufacturerSpecificData` removes those bytes and exposes them as a little-endian company ID. Therefore Android payload offset `n` normally corresponds to full offset `n + 2`.

The vendor CA discovery code compares the full manufacturer-data length minus ten with byte 2. Its broadcast decoder normally strips the final six bytes before parsing a frame. The frame initializer treats byte 2 as its data-area length and starts that data area at offset 3. Thus an inferred complete CA layout is:

`CA | version | dataLength | dataArea | checkByte | embeddedMAC(6)`

The exact accepted lengths and checksum conventions still require real captures. The frame initializer permits extra data after its declared data area; do not infer one universal frame size from a single Android branch. Source Evidence: `ev_6801950420c4e0c52bb035b208f879fa12c9d900a663cca4212ca8a48a89cc77`, `ev_6ba3fde8704f9c9736e87c6d89eebcbb949a84ce7ca967862cc3b4756d0f787a`.

| Format | Property/stability | Weight | Impedance | Status |
| --- | --- | --- | --- | --- |
| CA20 | Full offset 8, bit 0 indicates locked | Full offsets 10–11, big-endian | Full offsets 12–13, divided by ten | Agrees with Android `OkOkHandler` offsets after adding two. Vendor uses property-based precision and units. |
| CA11 broadcast | **Full offset 3**, bit 0 indicates locked | Full offsets 5–6, big-endian | Not established in this bounded pass | Important discrepancy: Android currently reads property from payload offset 9 (full offset 11). Vendor assembly reads data-area byte 0, hence full offset 3. |
| Plain C0 | Full offset 8, bit 0 indicates locked | Full offsets 2–3, big-endian | Full offsets 4–5, divided by ten | Agrees with Android `OkOkHandler` offsets after adding two. |

Precision and unit bits are interpreted via vendor helper methods; Android's corresponding property convention uses bits 1–2 for resolution and bits 3–4 for kg/jin/lb/stone. Port the existing conversion tests, then verify against a real stable reading and the scale's own display.

The CA11 offset was corroborated against native instructions rather than trusting decompiler pointer notation: `0x2c4d8` loads a byte from the data-area start, `0x2c4e0` masks bit 0, and `0x2c514` selects two bytes at data-area offset 2 for weight. CA20 and C0 offsets were similarly checked in the same assembly. Evidence: decompilation `ev_11b957a9b81da1bf762c7cfc0a93b6f9eea8b91ac604ed580de0b0ec6e63b3fe`; assembly `ev_7cbf111d07deb3b106ae8068b81ae8a86b4e49bd734c2dbb3c8a2c7c5357572c`.

### Encrypted C0 exclusion

The vendor has an encrypted C0 path, including a 15-byte form. It passes the two impedance bytes at full offset 4 to `AESUtil.isEncryptedWithData:`. That helper tests bit 7 of the first byte (equivalent to the high bit of the big-endian 16-bit value). If that bit is set, weight and impedance need timestamp-dependent decryption; interpreting them as plain fields can produce plausible but incorrect measurements.

For the initial reconstruction, detect and explicitly reject this encrypted form unless its decryption is implemented and validated. Evidence: C0 branch in `ev_11b957a9b81da1bf762c7cfc0a93b6f9eea8b91ac604ed580de0b0ec6e63b3fe`; helper `ev_cde16c3f7f39ce0d260cb679e126b2d47d2786e3b3ae785dc5347528ff7f1fe2`; MAC/timestamp setup `ev_c28131f9469eb92a974f524d8031fb2c21d159f2e61dade57bdc6f8aa5e27d61`.

## Existing openScale protocol assets

- [ChipseaBleLib](../android_app/app/src/main/java/com/health/openscale/core/bluetooth/libs/ChipseaBleLib.kt) and [tests](../android_app/app/src/test/java/com/health/openscale/core/bluetooth/libs/ChipseaBleLibTest.kt): CA10 user/time sync and CA10/CA11 connected measurements, including multipart frames. The handler uses service FFF0, RX FFF1, TX FFF2. Reuse the documented synthetic vectors, not the bundled vendor framework.
- [OkOkHandler](../android_app/app/src/main/java/com/health/openscale/core/bluetooth/scales/OkOkHandler.kt): CA20, CA11, FF F0, and C0 advertising paths. Preserve checksum validation where established; correct the CA11 broadcast property/stability offset against the evidence above. The FF F0 branch lacks a strong settled-measurement check and should not silently become an automatic-save path.
- Distinguish CA11 **broadcast** and CA11 **GATT** layouts; their shared prefix does not make their fields identical.

## Remaining unknowns / first hardware trial

### Hardware diagnostic follow-up (7 November 2026)

A user-supplied diagnostic from a LiveContainer attempt contains a 15-byte plain
C0 manufacturer advertisement. Device names and identifiers are omitted here.
Bluetooth discovery therefore worked in that environment. The captured property
byte is `0x25`: locked, hundredths, kilograms, plus bit 5. The initial decoder's
`property & 0xE0 == 0` check rejected bit 5, leaving this device unselectable.
There is no selection event in the supplied log.

Version 0.1.1 accepts bit 5 (`property & 0xC0 == 0`), retaining the 15-byte format
check, encryption-marker rejection, and existing unit/precision/stability logic.
A regression test replays the packet with its embedded device identity removed;
live, encrypted, and unverified upper-bit variants are also checked. This
establishes recognition and decoding of the capture, not a completed on-device
save. The meaning of bit 5 remains unknown; it is ignored for measurement decoding.

### Successful LiveContainer capture (7 November 2026)

After installing version 0.1.1, the user reported that the scale worked. The
second diagnostic shows selection of the OKOK broadcast device, repeated plain
C0 live packets with property `0x24`, and a final locked packet with property
`0x25`. No errors are recorded. This corroborates the corrected recognition and
live-to-final capture path in LiveContainer on the user's physical device.
Device identifiers, nearby device names, and personal measurement values are
omitted from these notes. The log does not record a database save, so persistence
of this particular weigh-in is not established by the diagnostic alone.

The following unknowns describe the original static investigation; this follow-up
identifies the user's captured device as a plain C0 broadcast candidate.

1. Actual scale's local name, manufacturer bytes, advertised services, and connectability are unknown.
2. Whether its packets are plain C0, encrypted C0, CA11, CA20, a cloud variant, or another family is unknown.
3. Incoming frame checksums and packet lengths have not been validated from live radio captures. Existing Android checks supply a conservative starting point, not proof of all vendor variants.
4. Body-composition parity is not established. Preserve reported impedance separately and label any computed estimates with their algorithm; do not present the app's formulas as values transmitted by the scale.
5. No actual weigh-in, reconnect, background capture, or user-profile sync was observed in this investigation.

First trial: scan in foreground while stepping on the scale, select the matching device, verify live versus locked packets and displayed units, and compare several completed readings with the reference app. If the format is unsupported, export the selected device's bounded diagnostic frames rather than attempting arbitrary commands against every FFF0 peripheral.
