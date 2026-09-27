# Source

Two copies of BoringSSL are compiled into the app, under different licences: BoringSSL was
relicensed to Apache-2.0 between the two revisions.

| File | Vendored by | BoringSSL revision | Licence |
|---|---|---|---|
| `LICENSE` | swift-nio-ssl 2.37.4 | `817ab07ebb53da35afea409ab9328f578492832d` | OpenSSL and SSLeay licences, ISC for new code, MIT for `third_party/fiat` |
| `LICENSE-swift-crypto` | swift-crypto 4.5.2 | `0226f30467f540a3f62ef48d453f93927da199b6` | Apache-2.0, with the notices that follow it in the file |

Each was retrieved from `https://boringssl.googlesource.com/boringssl/+/<revision>/LICENSE`
(the first on 2026-09-08, the second on 2026-09-26). The revisions are the ones each package's
`Package.swift` records as `BoringSSL Commit`.
