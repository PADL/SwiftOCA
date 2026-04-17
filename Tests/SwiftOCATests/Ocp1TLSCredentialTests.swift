//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

@testable import SwiftOCA
import XCTest

final class Ocp1TLSCredentialTests: XCTestCase {
  func testCertificateFileCredential() {
    let credential = Ocp1TLSCredential.certificateFile(
      certPath: "/tmp/server.crt",
      keyPath: "/tmp/server.key"
    )
    if case .certificateFile(let certPath, let keyPath) = credential {
      XCTAssertEqual(certPath, "/tmp/server.crt")
      XCTAssertEqual(keyPath, "/tmp/server.key")
    } else {
      XCTFail("expected certificateFile case")
    }
  }

  func testCertificatePEMCredential() {
    let certData = Data("-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----".utf8)
    let keyData = Data("-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----".utf8)
    let credential = Ocp1TLSCredential.certificatePEM(certificate: certData, privateKey: keyData)
    if case .certificatePEM(let cert, let key) = credential {
      XCTAssertEqual(cert, certData)
      XCTAssertEqual(key, keyData)
    } else {
      XCTFail("expected certificatePEM case")
    }
  }

  func testPkcs12Credential() {
    let p12Data = Data([0x30, 0x82, 0x00, 0x00])
    let credential = Ocp1TLSCredential.pkcs12(data: p12Data, password: "secret")
    if case .pkcs12(let data, let password) = credential {
      XCTAssertEqual(data, p12Data)
      XCTAssertEqual(password, "secret")
    } else {
      XCTFail("expected pkcs12 case")
    }
  }

  func testPkcs12CredentialNoPassword() {
    let p12Data = Data([0x30, 0x82, 0x00, 0x00])
    let credential = Ocp1TLSCredential.pkcs12(data: p12Data, password: nil)
    if case .pkcs12(_, let password) = credential {
      XCTAssertNil(password)
    } else {
      XCTFail("expected pkcs12 case")
    }
  }

  #if canImport(Security)
  func testIdentityCredential() {
    // SecIdentity can't be easily constructed in tests without a keychain,
    // so just verify the enum case exists and compiles
    let _: (SecIdentity) -> Ocp1TLSCredential = { .identity($0) }
  }
  #endif
}
