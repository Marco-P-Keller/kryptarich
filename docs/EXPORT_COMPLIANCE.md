# Krypta ECC — Encryption Documentation

Prepared for Apple's *App Encryption Documentation* upload in App Store Connect
and as the technical basis for a U.S. export self-classification.

| | |
|---|---|
| **App name** | Krypta ECC |
| **Bundle identifier** | `com.calcchat.ww` |
| **Apple Team ID** | `B97SQSQBMR` |
| **Version** | 4.2.0 (build 101) |
| **Document date** | 2026-09-06 |
| **Platform** | iOS (Flutter/Dart application, native crypto backends) |

---

## 1. Summary

Krypta ECC is a one-to-one messenger. Its purpose is end-to-end encrypted
messaging: messages are encrypted on the sending device and can only be
decrypted on the receiving device. The relay server stores ciphertext only and
holds no key material.

The app therefore **uses non-exempt encryption**:

* It implements encryption **in addition to** the encryption provided by iOS
  (Apple's second criterion).
* It uses **only published, standard algorithms** from recognised standards
  bodies (IETF, NIST, IRTF). It contains **no proprietary encryption
  algorithm**, and none of the standard algorithms has been modified
  (Apple's first criterion does **not** apply).

All cryptographic primitives are implemented by widely used open-source
libraries, backed on iOS by Apple CryptoKit and BoringSSL. The app does not
implement its own primitives; it composes standard primitives into the
published X3DH and Double Ratchet protocols.

---

## 2. Where encryption is used

| Purpose | Description |
|---|---|
| **End-to-end message encryption** | Every message is encrypted for one recipient. Keys are agreed between the two devices; the server never sees plaintext or keys. |
| **Key agreement** | X3DH (Extended Triple Diffie-Hellman) on first contact, Double Ratchet for every subsequent message (a fresh message key per message, forward secrecy and post-compromise security). |
| **Authenticity / integrity** | AEAD tags on every message; Ed25519 signatures on published prekeys and on key-transparency log entries; a safety number both users can compare out of band. |
| **Data at rest** | The local message store on the device is encrypted with the same AEAD cipher. The database key is held in the iOS Keychain and, where the hardware supports it, additionally wrapped by a non-extractable Secure Enclave key. |
| **Password-protected messages** | An optional per-message password derives a key via Argon2id; the ciphertext is bound to its context via AEAD associated data. |
| **Transport** | TLS to the relay (Firebase/Firestore), provided by the platform TLS stack through the Firebase SDK, with SPKI certificate pinning configured in `Info.plist`. |

---

## 3. Algorithms used

All key lengths are given in bits. No algorithm is proprietary; no algorithm
has been modified.

| Algorithm | Purpose | Key / parameters | Standard |
|---|---|---|---|
| **X25519 (ECDH, Curve25519)** | Key agreement: X3DH (3 × DH) and every Double Ratchet step | 256-bit keys (≈128-bit security) | RFC 7748 |
| **Ed25519 (EdDSA)** | Signatures: signed prekeys, key-transparency entries | 256-bit keys | RFC 8032 |
| **XChaCha20-Poly1305** | AEAD encryption of messages and of the local store | 256-bit key, 192-bit nonce, 128-bit tag | RFC 8439 (ChaCha20-Poly1305); XChaCha20 extended nonce per IRTF CFRG draft |
| **HKDF-SHA256** | Key derivation in X3DH, the ratchet chains and session setup | 256-bit output (512-bit where two keys are derived) | RFC 5869 |
| **HMAC-SHA256** | Ratchet chain keys, control-message authentication | 256-bit key | RFC 2104, FIPS 198-1 |
| **SHA-256 / SHA-512** | Hashing; safety-number derivation (SHA-512, 5200 iterations) | — | FIPS 180-4 |
| **Argon2id** | Password-based key derivation for password-protected messages and the vault password | 19 MiB memory, 2 iterations, parallelism 1, 32-byte output | RFC 9106 |
| **P-256 ECIES (ECDH + X9.63 KDF + AES-GCM)** | Wrapping the local database key inside the Apple Secure Enclave | 256-bit curve, AES-256-GCM | FIPS 186-4, SP 800-56A, FIPS 197, SP 800-38D — **provided by Apple iOS** |
| **TLS 1.2 / 1.3** | Transport to the relay server | Platform defaults | RFC 8446 — **provided by the operating system** |

**Protocols** (composition of the above, both published specifications of the
Signal Foundation, implemented independently in this app):

* **X3DH** — Extended Triple Diffie-Hellman key agreement.
* **Double Ratchet** — per-message key ratcheting with DH ratchet steps.

---

## 4. Third-party cryptographic libraries

| Library | Version | Role |
|---|---|---|
| `cryptography` (Dart) | 2.9.0 | X25519, Ed25519, XChaCha20-Poly1305, HKDF, HMAC, Argon2id |
| `cryptography_flutter` | 2.3.4 | Native backends: Apple CryptoKit on iOS, BoringSSL on Android |
| `crypto` (Dart) | 3.0.7 | SHA-256 / SHA-512 |
| `flutter_secure_storage` | 10.0.0 | Access to the iOS Keychain (key storage, no algorithms of its own) |
| Apple Security framework / CryptoKit | iOS | Secure Enclave key generation and ECIES wrapping |

All are publicly available open-source components, unmodified.

---

## 5. Key management

* Key pairs are generated **on the device** and never leave it.
* The relay server stores only public keys and ciphertext. It has no private
  key material and no ability to decrypt any message.
* There is **no key escrow, no backdoor, and no recovery mechanism**. A lost
  device means lost message history by design.
* Users can verify each other's identity out of band via a safety number
  (SHA-512, 5200 iterations, displayed as digits and as a QR code).

---

## 6. Classification (to be confirmed by the account holder)

The app is a **mass-market product** distributed through the App Store, using
only published standard algorithms, with no cryptanalytic functionality and no
custom cryptography.

For products of this kind the customary U.S. classification is
**ECCN 5D992.c** under License Exception ENC, which normally requires an
**annual self-classification report** to BIS and the ENC Encryption Request
Coordinator rather than a CCATS ruling.

> This section is a technical assessment, not legal advice. Whether a
> self-classification report is sufficient, or whether a CCATS is required, is
> a decision for the Apple Developer account holder, if necessary with legal
> counsel. The same applies to national requirements outside the U.S. — France,
> for example, has its own declaration regime for apps distributed there.

---

## 7. Info.plist status

`ITSAppUsesNonExemptEncryption` is deliberately **absent** from
`ios/Runner/Info.plist`. Setting it to `<true/>` without an accompanying
`ITSEncryptionExportComplianceCode` causes `altool` to reject the upload
(ITMS-90592), so builds never reach the questionnaire. With the key absent,
App Store Connect asks per build, which is answerable there.

Once Apple issues a compliance code in response to this documentation, the
final state should be:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
<key>ITSEncryptionExportComplianceCode</key>
<string><!-- code issued by Apple --></string>
```

Uploads then pass without the per-build question.

**Never** set the key to `<false/>` merely to make an upload succeed. That is a
declaration under export regulations, and it would be untrue for this app.
