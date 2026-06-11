import Foundation
import CryptoKit

// Emits a short-lived ES256 JWT for the App Store Connect API.
// Reads ASC_KEY_PATH (.p8), ASC_KEY_ID, ASC_ISSUER from the environment.

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-asc-jwt: \(message)\n".utf8))
    exit(1)
}

let env = ProcessInfo.processInfo.environment
guard
    let keyPath = env["ASC_KEY_PATH"],
    let keyID = env["ASC_KEY_ID"]
else {
    fail("missing ASC_KEY_PATH / ASC_KEY_ID")
}

// Team keys authenticate with `iss` (issuer id); individual keys use `sub: "user"`.
let issuer = env["ASC_ISSUER"].flatMap { $0.isEmpty ? nil : $0 }
let subject = env["ASC_SUB"].flatMap { $0.isEmpty ? nil : $0 }
if issuer == nil && subject == nil {
    fail("provide ASC_ISSUER (team key) or ASC_SUB (individual key)")
}

let pem: String
do {
    pem = try String(contentsOfFile: keyPath, encoding: .utf8)
} catch {
    fail("cannot read key at \(keyPath): \(error)")
}

let key: P256.Signing.PrivateKey
do {
    key = try P256.Signing.PrivateKey(pemRepresentation: pem)
} catch {
    fail("invalid EC private key: \(error)")
}

let now = Int(Date().timeIntervalSince1970)
let header: [String: String] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
var payload: [String: Any] = [
    "iat": now,
    "exp": now + 600,
    "aud": "appstoreconnect-v1"
]
if let subject {
    payload["sub"] = subject
} else if let issuer {
    payload["iss"] = issuer
}

do {
    let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
    let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let signingInput = base64URL(headerData) + "." + base64URL(payloadData)
    let signature = try key.signature(for: Data(signingInput.utf8))
    print(signingInput + "." + base64URL(signature.rawRepresentation))
} catch {
    fail("signing failed: \(error)")
}
