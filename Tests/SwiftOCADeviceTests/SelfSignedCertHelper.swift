//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//

// Shells out to the `openssl` CLI. Available on Linux (where it backs the
// OpenSSL-engine TLS tests) and macOS (where it backs the
// Network.framework-engine regression tests).
#if (os(Linux) || os(macOS)) && NonEmbeddedBuild

import Foundation

/// Locate the system `openssl` CLI, or return `nil` so callers can
/// `XCTSkip` rather than fail spuriously on minimal CI images.
func locateOpenSSLBinary() -> String? {
  let candidates = ["/usr/bin/openssl", "/usr/local/bin/openssl", "/opt/homebrew/bin/openssl"]
  return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
}

/// Shell out to the `openssl` CLI to mint a short-lived self-signed cert
/// and matching private key. Returns `nil` when `openssl` isn't on PATH.
/// Default produces `CN=ocp1-test` with SAN `DNS:ocp1-test,IP:127.0.0.1`,
/// valid for one day — the parameters cover negative-path variants.
///
/// - Parameters:
///   - commonName: subject CN.
///   - subjectAltNames: SANs in `openssl -addext` form, e.g. `"DNS:foo,IP:1.2.3.4"`.
///   - daysValid: validity window in days from "now". Ignored when an
///     explicit validity window is supplied via `notBefore`/`notAfter`.
///   - notBefore: explicit ASN.1 `notBefore` time in `YYYYMMDDHHMMSSZ` form
///     (e.g. `"20200101000000Z"`). Pair with `notAfter` to mint an already-
///     expired cert.
///   - notAfter: explicit ASN.1 `notAfter` time in the same form.
func generateSelfSignedCert(
  commonName: String = "ocp1-test",
  subjectAltNames: String = "DNS:ocp1-test,IP:127.0.0.1",
  daysValid: Int = 1,
  notBefore: String? = nil,
  notAfter: String? = nil
) throws -> (certPath: String, keyPath: String)? {
  guard let opensslPath = locateOpenSSLBinary() else { return nil }

  let tempDir = NSTemporaryDirectory() + "ocp1-tls-\(UUID().uuidString)"
  try FileManager.default.createDirectory(
    atPath: tempDir,
    withIntermediateDirectories: true
  )
  let certPath = tempDir + "/cert.pem"
  let keyPath = tempDir + "/key.pem"

  var args: [String] = [
    "req", "-x509", "-newkey", "rsa:2048", "-nodes",
    "-keyout", keyPath, "-out", certPath,
    "-subj", "/CN=\(commonName)",
    "-addext", "subjectAltName=\(subjectAltNames)",
  ]
  if let notBefore, let notAfter {
    // OpenSSL 3 accepts explicit validity windows; format is the ASN.1
    // GeneralizedTime form. Used by the expired-cert tests so the cert
    // is unambiguously past its validity at the moment of minting.
    args.append(contentsOf: ["-not_before", notBefore, "-not_after", notAfter])
  } else {
    args.append(contentsOf: ["-days", String(daysValid)])
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: opensslPath)
  process.arguments = args
  process.standardOutput = Pipe()
  let errPipe = Pipe()
  process.standardError = errPipe
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    let stderr = (try? errPipe.fileHandleForReading.readToEnd())
      .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    throw NSError(
      domain: "SelfSignedCertHelper",
      code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: "openssl req failed: \(stderr)"]
    )
  }
  return (certPath, keyPath)
}

/// Mint a private CA and a leaf certificate signed by it. The two are
/// returned in distinct sub-directories so the caller can hand the leaf
/// to one role and the CA cert to another (e.g. "server cert signed by
/// CA-A; client trustRoots = CA-B" by minting two of these).
///
/// Returns `nil` when `openssl` isn't on PATH.
func generateCASignedCert(
  caCommonName: String = "ocp1-test-ca",
  leafCommonName: String = "ocp1-test",
  leafSubjectAltNames: String = "DNS:ocp1-test,IP:127.0.0.1",
  daysValid: Int = 1
) throws -> (caCertPath: String, leafCertPath: String, leafKeyPath: String)? {
  guard let opensslPath = locateOpenSSLBinary() else { return nil }

  let tempDir = NSTemporaryDirectory() + "ocp1-tls-ca-\(UUID().uuidString)"
  try FileManager.default.createDirectory(
    atPath: tempDir,
    withIntermediateDirectories: true
  )
  let caKey = tempDir + "/ca.key"
  let caCert = tempDir + "/ca.crt"
  let leafKey = tempDir + "/leaf.key"
  let leafCSR = tempDir + "/leaf.csr"
  let leafCert = tempDir + "/leaf.crt"
  let extFile = tempDir + "/ext.cnf"

  // Step 1: mint a self-signed CA.
  try runOpenSSL(at: opensslPath, args: [
    "req", "-x509", "-newkey", "rsa:2048", "-nodes",
    "-keyout", caKey, "-out", caCert,
    "-days", String(daysValid),
    "-subj", "/CN=\(caCommonName)",
  ])

  // Step 2: leaf key + CSR.
  try runOpenSSL(at: opensslPath, args: [
    "req", "-newkey", "rsa:2048", "-nodes",
    "-keyout", leafKey, "-out", leafCSR,
    "-subj", "/CN=\(leafCommonName)",
  ])

  // Step 3: write a v3 ext file carrying the leaf SAN (the CLI doesn't
  // accept -addext when signing, only when minting a self-signed cert).
  let ext = """
  subjectAltName=\(leafSubjectAltNames)
  basicConstraints=CA:FALSE
  keyUsage=digitalSignature,keyEncipherment
  extendedKeyUsage=serverAuth
  """
  try ext.write(toFile: extFile, atomically: true, encoding: .utf8)

  // Step 4: sign the leaf with the CA.
  try runOpenSSL(at: opensslPath, args: [
    "x509", "-req", "-in", leafCSR,
    "-CA", caCert, "-CAkey", caKey, "-CAcreateserial",
    "-out", leafCert,
    "-days", String(daysValid),
    "-extfile", extFile,
  ])

  return (caCert, leafCert, leafKey)
}

/// Mint a CA, a leaf cert signed by it, and a CRL signed by the CA that
/// lists the leaf as revoked. Used by revocation-enforcement regression
/// tests — a strict client given (caCert, crl) must reject a handshake
/// presenting the leaf.
///
/// Returns `nil` when `openssl` isn't on PATH.
func generateCASignedCertWithCRL(
  caCommonName: String = "ocp1-test-ca",
  leafCommonName: String = "ocp1-test",
  leafSubjectAltNames: String = "DNS:ocp1-test,IP:127.0.0.1",
  daysValid: Int = 1
) throws -> (caCertPath: String, leafCertPath: String, leafKeyPath: String, crlPath: String)? {
  guard let opensslPath = locateOpenSSLBinary() else { return nil }

  let tempDir = NSTemporaryDirectory() + "ocp1-tls-crl-\(UUID().uuidString)"
  try FileManager.default.createDirectory(
    atPath: tempDir,
    withIntermediateDirectories: true
  )
  let caKey = tempDir + "/ca.key"
  let caCert = tempDir + "/ca.crt"
  let leafKey = tempDir + "/leaf.key"
  let leafCSR = tempDir + "/leaf.csr"
  let leafCert = tempDir + "/leaf.crt"
  let leafExt = tempDir + "/leaf.ext"
  let crlPath = tempDir + "/crl.pem"
  let caCfg = tempDir + "/ca.cnf"
  let indexFile = tempDir + "/index.txt"
  let attrFile = tempDir + "/index.txt.attr"
  let serialFile = tempDir + "/serial"
  let crlNumberFile = tempDir + "/crlnumber"
  let newCertsDir = tempDir + "/newcerts"
  try FileManager.default.createDirectory(atPath: newCertsDir, withIntermediateDirectories: true)

  // CA-signing config — `openssl ca` needs this layout regardless of how
  // little of it we actually populate.
  let caCfgContent = """
  [ ca ]
  default_ca = CA_default

  [ CA_default ]
  dir              = \(tempDir)
  database         = \(indexFile)
  new_certs_dir    = \(newCertsDir)
  serial           = \(serialFile)
  crlnumber        = \(crlNumberFile)
  certificate      = \(caCert)
  private_key      = \(caKey)
  default_md       = sha256
  default_crl_days = 30
  default_days     = \(daysValid)
  policy           = policy_any
  email_in_dn      = no
  unique_subject   = no
  copy_extensions  = none

  [ policy_any ]
  commonName              = supplied
  """
  try caCfgContent.write(toFile: caCfg, atomically: true, encoding: .utf8)
  try "".write(toFile: indexFile, atomically: true, encoding: .utf8)
  try "unique_subject = no\n".write(toFile: attrFile, atomically: true, encoding: .utf8)
  try "1000\n".write(toFile: serialFile, atomically: true, encoding: .utf8)
  try "1000\n".write(toFile: crlNumberFile, atomically: true, encoding: .utf8)

  // Step 1: self-signed CA.
  try runOpenSSL(at: opensslPath, args: [
    "req", "-x509", "-newkey", "rsa:2048", "-nodes",
    "-keyout", caKey, "-out", caCert,
    "-days", String(daysValid),
    "-subj", "/CN=\(caCommonName)",
  ])

  // Step 2: leaf key + CSR.
  try runOpenSSL(at: opensslPath, args: [
    "req", "-newkey", "rsa:2048", "-nodes",
    "-keyout", leafKey, "-out", leafCSR,
    "-subj", "/CN=\(leafCommonName)",
  ])

  // Step 3: leaf extensions.
  let leafExtContent = """
  subjectAltName=\(leafSubjectAltNames)
  basicConstraints=CA:FALSE
  keyUsage=digitalSignature,keyEncipherment
  extendedKeyUsage=serverAuth
  """
  try leafExtContent.write(toFile: leafExt, atomically: true, encoding: .utf8)

  // Step 4: sign leaf via `openssl ca` so the index.txt records the
  // issuance — required for the subsequent `-revoke` step.
  try runOpenSSL(at: opensslPath, args: [
    "ca", "-batch", "-config", caCfg,
    "-in", leafCSR, "-out", leafCert,
    "-extfile", leafExt,
    "-days", String(daysValid),
  ])

  // Step 5: revoke the freshly-issued leaf and emit a CRL covering it.
  try runOpenSSL(at: opensslPath, args: [
    "ca", "-batch", "-config", caCfg, "-revoke", leafCert,
  ])
  try runOpenSSL(at: opensslPath, args: [
    "ca", "-batch", "-config", caCfg, "-gencrl", "-out", crlPath,
  ])

  return (caCert, leafCert, leafKey, crlPath)
}

/// Passphrase used by `pemToPKCS12` and the matching `SecPKCS12Import`
/// call. macOS's `SecPKCS12Import` reliably refuses empty-passphrase P12s,
/// so we pick a fixed short one. Test-only — these P12s never leave the
/// process.
let testPKCS12Password = "ocp1-test"

/// Bundle a PEM cert + key into a PKCS#12 file encrypted with
/// `testPKCS12Password`. macOS's `SecItemImport` PEM-aggregate path is
/// finicky with OpenSSL 3's PKCS8-PEM keys; PKCS#12 imports cleanly via
/// `SecPKCS12Import`. Returns `nil` when `openssl` isn't on PATH.
func pemToPKCS12(certPath: String, keyPath: String) throws -> String? {
  guard let opensslPath = locateOpenSSLBinary() else { return nil }
  let dir = (certPath as NSString).deletingLastPathComponent
  let p12Path = dir + "/bundle.p12"
  // Pin PBE-SHA1-3DES + SHA1 MAC. macOS's `SecPKCS12Import` accepts modern
  // PBES2/AES output in current releases but historic builds and the
  // bundled LibreSSL writer interact badly — the legacy algorithms are
  // bulletproof across the matrix.
  try runOpenSSL(at: opensslPath, args: [
    "pkcs12", "-export",
    "-keypbe", "PBE-SHA1-3DES",
    "-certpbe", "PBE-SHA1-3DES",
    "-macalg", "sha1",
    "-inkey", keyPath,
    "-in", certPath,
    "-out", p12Path,
    "-passout", "pass:\(testPKCS12Password)",
  ])
  return p12Path
}

private func runOpenSSL(at path: String, args: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: path)
  process.arguments = args
  process.standardOutput = Pipe()
  let errPipe = Pipe()
  process.standardError = errPipe
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    let stderr = (try? errPipe.fileHandleForReading.readToEnd())
      .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    throw NSError(
      domain: "SelfSignedCertHelper",
      code: Int(process.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey:
        "openssl \(args.first ?? "") failed (\(process.terminationStatus)): \(stderr)"]
    )
  }
}

#endif
