import Foundation
import SwiftUI

// MARK: - Модели данных
struct ShadowsocksServer: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var address: String
    var port: Int
    private var _password: String?
    var method: String
    var localPort: Int = 1080
    var timeout: Int = 300
    var lastPing: Double?
    var lastSpeed: Double?
    var isActive: Bool = false
    var lastUpdate: Date?
    
    var password: String {
        get { _password ?? "" }
        set { _password = newValue.isEmpty ? nil : newValue }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, address, port, method, localPort, timeout, lastPing, lastSpeed, isActive, lastUpdate
    }
    
    init(name: String, address: String, port: Int, password: String, method: String) {
        self.name = name
        self.address = address
        self.port = port
        self._password = password.isEmpty ? nil : password
        self.method = method
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        port = try container.decode(Int.self, forKey: .port)
        method = try container.decode(String.self, forKey: .method)
        localPort = try container.decodeIfPresent(Int.self, forKey: .localPort) ?? 1080
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 300
        lastPing = try container.decodeIfPresent(Double.self, forKey: .lastPing)
        lastSpeed = try container.decodeIfPresent(Double.self, forKey: .lastSpeed)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        lastUpdate = try container.decodeIfPresent(Date.self, forKey: .lastUpdate)
        _password = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(port, forKey: .port)
        try container.encode(method, forKey: .method)
        try container.encode(localPort, forKey: .localPort)
        try container.encode(timeout, forKey: .timeout)
        try container.encodeIfPresent(lastPing, forKey: .lastPing)
        try container.encodeIfPresent(lastSpeed, forKey: .lastSpeed)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(lastUpdate, forKey: .lastUpdate)
    }
    
    var pingStatus: PingStatus {
        guard let ping = lastPing else { return .unknown }
        if ping < 100 { return .excellent }
        if ping < 300 { return .good }
        if ping < 500 { return .fair }
        return .poor
    }
    
    var statusDescription: String {
        guard let ping = lastPing else { return "Не тестировано" }
        return "\(String(format: "%.1f", ping)) мс"
    }
    
    var speedDescription: String {
        guard let speed = lastSpeed else { return "Не тестировано" }
        return "\(String(format: "%.2f", speed)) MB/s"
    }
    
    var isValid: Bool {
        !name.isEmpty && !address.isEmpty &&
        (1...65535).contains(port) && ShadowsocksManager.supportedMethods.contains(method) &&
        (1024...65535).contains(localPort)
    }
    
    enum PingStatus: String, Codable {
        case excellent, good, fair, poor, unknown
        
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .orange
            case .poor: return .red
            case .unknown: return .gray
            }
        }
        
        var description: String {
            switch self {
            case .excellent: return "Отличный"
            case .good: return "Хороший"
            case .fair: return "Средний"
            case .poor: return "Плохой"
            case .unknown: return "Не тестировано"
            }
        }
    }
    
    func loadPassword() async throws -> String {
        let data = try await Keychain.readPassword(service: "ShadowsocksManager", account: id.uuidString)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func savePassword() async throws {
        guard let data = _password?.data(using: .utf8) else { return }
        try await Keychain.save(password: data, service: "ShadowsocksManager", account: id.uuidString)
    }
    
    func updatePassword() async throws {
        try await Keychain.update(password: _password?.data(using: .utf8), service: "ShadowsocksManager", account: id.uuidString)
    }
    
    func deletePassword() async throws {
        try await Keychain.deletePassword(service: "ShadowsocksManager", account: id.uuidString)
    }
}
