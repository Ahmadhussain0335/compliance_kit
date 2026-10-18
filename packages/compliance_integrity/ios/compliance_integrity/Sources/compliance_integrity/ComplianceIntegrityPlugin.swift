import CryptoKit
import DeviceCheck
import Flutter
import Foundation

/// App Attest for compliance_integrity.
///
/// The first request generates a key, attests it and returns the attestation
/// object. Later requests return assertions signed with that key. The key id
/// and its attested flag are stored in the Keychain, available after first
/// unlock and never backed up or migrated, because App Attest keys do not
/// survive a restore or device migration.
public final class ComplianceIntegrityPlugin: NSObject, FlutterPlugin, IntegrityHostApi {
  private let attest = AppAttestCoordinator()

  public static func register(with registrar: FlutterPluginRegistrar) {
    IntegrityHostApiSetup.setUp(
      binaryMessenger: registrar.messenger(), api: ComplianceIntegrityPlugin())
  }

  func isSupported() async throws -> Bool {
    DCAppAttestService.shared.isSupported
  }

  func prepare(cloudProjectNumber: Int64?) async throws {
    try await attest.prepare()
  }

  func requestToken(requestHash: String, cloudProjectNumber: Int64?) async throws -> TokenMessage {
    try await attest.requestToken(requestHash: requestHash)
  }

  func reset() async throws {
    try await attest.reset()
  }
}

/// Error codes shared with the Dart layer (IntegrityErrorCodes).
enum IntegrityErrorCode {
  static let unsupported = "unsupported"
  static let network = "network"
  static let configuration = "configuration"
  static let transient = "transient"
  static let platform = "platform"
}

/// Serializes App Attest work so concurrent requests cannot create or attest
/// two keys at the same time.
actor AppAttestCoordinator {
  private let service = DCAppAttestService.shared
  private let keyStore = AttestKeyStore()
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func prepare() async throws {
    await lock()
    defer { unlock() }
    do {
      try requireSupported()
      if try keyStore.load() == nil {
        _ = try await newKey()
      }
    } catch {
      throw Self.flutterError(error)
    }
  }

  func requestToken(requestHash: String) async throws -> TokenMessage {
    await lock()
    defer { unlock() }
    do {
      try requireSupported()
      let clientDataHash = Data(SHA256.hash(data: Data(requestHash.utf8)))
      do {
        return try await token(clientDataHash: clientDataHash)
      } catch let error as DCError where error.code == .invalidKey {
        // The key was rejected (for example after switching between the
        // development and production environment). Start over once.
        try keyStore.delete()
        return try await token(clientDataHash: clientDataHash)
      }
    } catch {
      throw Self.flutterError(error)
    }
  }

  func reset() async throws {
    await lock()
    defer { unlock() }
    do {
      try keyStore.delete()
    } catch {
      throw Self.flutterError(error)
    }
  }

  private func token(clientDataHash: Data) async throws -> TokenMessage {
    var state: AttestKeyState
    if let stored = try keyStore.load() {
      state = stored
    } else {
      state = try await newKey()
    }
    if !state.attested {
      let attestation: Data
      do {
        attestation = try await service.attestKey(state.keyId, clientDataHash: clientDataHash)
      } catch let error as DCError where error.code == .serverUnavailable {
        // Retry later with the same key, as Apple recommends.
        throw error
      } catch {
        // For any other attestation error Apple recommends a new key.
        try keyStore.delete()
        throw error
      }
      state.attested = true
      try keyStore.save(state)
      return TokenMessage(
        token: attestation.base64EncodedString(), kind: .appAttestAttestation,
        keyId: state.keyId)
    }
    let assertion = try await service.generateAssertion(
      state.keyId, clientDataHash: clientDataHash)
    return TokenMessage(
      token: assertion.base64EncodedString(), kind: .appAttestAssertion, keyId: state.keyId)
  }

  private func newKey() async throws -> AttestKeyState {
    let keyId = try await service.generateKey()
    let state = AttestKeyState(keyId: keyId, attested: false)
    try keyStore.save(state)
    return state
  }

  private func requireSupported() throws {
    guard service.isSupported else {
      throw PigeonError(
        code: IntegrityErrorCode.unsupported,
        message: "App Attest is not supported on this device.", details: nil)
    }
  }

  private func lock() async {
    if busy {
      await withCheckedContinuation { waiters.append($0) }
    } else {
      busy = true
    }
  }

  /// Hands the lock to the next waiter, or releases it.
  private func unlock() {
    if waiters.isEmpty {
      busy = false
    } else {
      waiters.removeFirst().resume()
    }
  }

  static func flutterError(_ error: Error) -> Error {
    if error is PigeonError { return error }
    if let dcError = error as? DCError {
      let code: String
      switch dcError.code {
      case .featureUnsupported: code = IntegrityErrorCode.unsupported
      case .serverUnavailable: code = IntegrityErrorCode.network
      case .invalidInput: code = IntegrityErrorCode.configuration
      case .invalidKey, .unknownSystemFailure: code = IntegrityErrorCode.platform
      @unknown default: code = IntegrityErrorCode.platform
      }
      return PigeonError(
        code: code, message: dcError.localizedDescription,
        details: "DCError.\(dcError.code.rawValue)")
    }
    if error is AttestKeyStoreError {
      return PigeonError(
        code: IntegrityErrorCode.platform, message: "Keychain access failed.",
        details: String(describing: error))
    }
    return PigeonError(
      code: IntegrityErrorCode.platform, message: error.localizedDescription, details: nil)
  }
}

struct AttestKeyState: Codable, Sendable {
  var keyId: String
  var attested: Bool
}

enum AttestKeyStoreError: Error {
  case keychain(OSStatus)
  case decoding
}

/// Stores the App Attest key id in the Keychain.
struct AttestKeyStore: Sendable {
  private let service = "io.github.ahmadhussain0335.compliance_integrity"
  private let account = "app_attest_key"

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  func load() throws -> AttestKeyState? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw AttestKeyStoreError.keychain(status)
    }
    guard let state = try? JSONDecoder().decode(AttestKeyState.self, from: data) else {
      throw AttestKeyStoreError.decoding
    }
    return state
  }

  func save(_ state: AttestKeyState) throws {
    let data = try JSONEncoder().encode(state)
    let update: [String: Any] = [kSecValueData as String: data]
    var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var add = baseQuery
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(add as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw AttestKeyStoreError.keychain(status) }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AttestKeyStoreError.keychain(status)
    }
  }
}
