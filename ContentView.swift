import SwiftUI
import Combine
import Network
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins
import Security
import ServiceManagement
import UserNotifications
import Charts

// MARK: - Ошибки Keychain
enum KeychainError: Error {
    case duplicateItem
    case itemNotFound
    case invalidItemFormat
    case unexpectedStatus(OSStatus)
    
    var localizedDescription: String {
        switch self {
        case .duplicateItem: return "Элемент уже существует в Keychain."
        case .itemNotFound: return "Элемент не найден в Keychain."
        case .invalidItemFormat: return "Недействительный формат данных в Keychain."
        case .unexpectedStatus(let status): return "Неожиданная ошибка Keychain: код \(status)."
        }
    }
}

// MARK: - Помощник для работы с Keychain
class Keychain {
    @MainActor
    static func save(password: Data?, service: String, account: String) async throws {
        guard let passwordData = password else { return }
        
        let query: [String: AnyObject] = [
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword,
            kSecValueData as String: passwordData as AnyObject
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            throw KeychainError.duplicateItem
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    @MainActor
    static func readPassword(service: String, account: String) async throws -> Data {
        let query: [String: AnyObject] = [
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: kCFBooleanTrue
        ]
        
        var itemCopy: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &itemCopy)
        
        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let password = itemCopy as? Data else {
            throw KeychainError.invalidItemFormat
        }
        
        return password
    }
    
    @MainActor
    static func update(password: Data?, service: String, account: String) async throws {
        let query: [String: AnyObject] = [
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword
        ]
        
        if let passwordData = password {
            let attributes: [String: AnyObject] = [
                kSecValueData as String: passwordData as AnyObject
            ]
            
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            
            guard status != errSecItemNotFound else {
                throw KeychainError.itemNotFound
            }
            
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
        } else {
            let status = SecItemDelete(query as CFDictionary)
            
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }
    
    @MainActor
    static func deletePassword(service: String, account: String) async throws {
        let query: [String: AnyObject] = [
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

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
    var lastSpeed: Double? // Новое: скорость в MB/s
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

// MARK: - Менеджер Shadowsocks
@MainActor
class ShadowsocksManager: ObservableObject {
    static let shared = ShadowsocksManager()
    static let supportedMethods = [
        "aes-256-gcm", "aes-192-gcm", "aes-128-gcm",
        "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
        "rc4-md5", "salsa20", "chacha20"
    ]
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var pingTasks: [UUID: Process] = [:]
    private var connectionMonitorTimer: Timer?
    private var trafficTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var retryCount = 0
    private let maxRetries = 3
    
    @Published var isRunning = false
    @Published var logMessages = ""
    @Published var servers: [ShadowsocksServer] = []
    @Published var currentServerId: UUID?
    @Published var installationState: InstallationState = .checking
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isTestingAllServers = false
    @Published var uploadSpeed: Double = 0 // MB/s
    @Published var downloadSpeed: Double = 0 // MB/s
    @Published var totalTraffic: Int = 0 // MB
    @Published var proxyMode: ProxyMode = .manual
    @Published var speedData: [SpeedData] = [] // For chart
    
    struct SpeedData: Identifiable {
        let id = UUID()
        let date: Date
        let download: Double
        let upload: Double
    }
    
    enum ProxyMode: String, Codable, CaseIterable {
        case global, pac, manual
        var description: String {
            switch self {
            case .global: return "Глобальный"
            case .pac: return "PAC"
            case .manual: return "Ручной"
            }
        }
    }
    
    var currentServer: ShadowsocksServer? {
        servers.first { $0.id == currentServerId }
    }
    
    enum InstallationState {
        case checking
        case installed
        case notInstalled
        case installing(progress: Double)
        case error(message: String)
        
        var isInstalled: Bool {
            if case .installed = self { return true }
            return false
        }
    }
    
    enum ConnectionStatus: String {
        case connected = "Подключено"
        case connecting = "Подключение..."
        case disconnected = "Отключено"
        case error = "Ошибка подключения"
    }
    
    private var configPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowSocksManager")
            .appendingPathComponent("config.json")
    }
    
    private var serversPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowSocksManager")
            .appendingPathComponent("servers.json")
    }
    
    private var pacPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShadowSocksManager")
            .appendingPathComponent("proxy.pac")
    }
    
    private func findSSLocalPath() -> String? {
        let possibleCommands = ["ss-local", "sslocal"]
        let environmentPath = isAppleSilicon() ?
            "/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/opt/shadowsocks-libev/bin:/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin:/usr/local/bin:/usr/bin:/bin:/sbin" :
            "/usr/local/bin:/usr/bin:/bin:/sbin:/opt/homebrew/opt/shadowsocks-libev/bin:/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin"
        
        for command in possibleCommands {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [command]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = environmentPath
            process.environment = environment
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                log(">> Выполнение команды: /usr/bin/which \(command)")
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                    if FileManager.default.isExecutableFile(atPath: output) {
                        return output
                    }
                }
            } catch {
                log(">> Ошибка выполнения which: \(error)")
            }
        }
        
        let brewPath = isAppleSilicon() ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"
        if FileManager.default.isExecutableFile(atPath: brewPath) {
            let brewResult = executeShellCommand("\(brewPath) list shadowsocks-libev 2>/dev/null")
            if brewResult.success, !brewResult.output.isEmpty {
                let lines = brewResult.output.split(separator: "\n")
                for line in lines {
                    if line.hasSuffix("/ss-local") || line.hasSuffix("/sslocal") {
                        let path = String(line)
                        if FileManager.default.isExecutableFile(atPath: path) {
                            return path
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private func isAppleSilicon() -> Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
        }
        return machine.contains("arm64")
    }
    
    private func findBrewPath() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["brew"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = isAppleSilicon() ?
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/sbin" :
            "/usr/local/bin:/usr/bin:/bin:/sbin"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output.isEmpty ? nil : output
            }
        } catch {
            log(">> Ошибка при поиске brew: \(error)")
        }
        return nil
    }
    
    init() {
        checkInstallation()
        loadServers()
        setupLogMonitoring()
        setupNotificationAuthorization()
        logMessagesPublisher()
    }
    
    deinit {
        Task { @MainActor in
            stop()
        }
    }
    private func setupLogMonitoring() {
        logMessages = ""
    }
    
    private func logMessagesPublisher() {
        $logMessages
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { _ in }
            .store(in: &cancellables)
    }
    
    private func setupNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                self.log(">> Ошибка настройки уведомлений: \(error)")
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func loadServers() {
        do {
            let data = try Data(contentsOf: serversPath)
            var decodedServers = try JSONDecoder().decode([ShadowsocksServer].self, from: data)
            for i in decodedServers.indices {
                Task {
                    do {
                        decodedServers[i].password = try await decodedServers[i].loadPassword()
                    } catch {
                        log(">> Ошибка загрузки пароля для сервера \(decodedServers[i].name): \(error)")
                        decodedServers[i].password = ""
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.servers = decodedServers
                        if let activeServer = decodedServers.first(where: { $0.isActive }) {
                            self?.currentServerId = activeServer.id
                        } else if let firstServer = decodedServers.first {
                            self?.currentServerId = firstServer.id
                        }
                    }
                }
            }
        } catch {
            log(">> Серверы не найдены, создание сервера по умолчанию: \(error)")
            createDefaultServer()
        }
    }
    
    private func createDefaultServer() {
        let defaultServer = ShadowsocksServer(
            name: "Сервер по умолчанию",
            address: "your_server.com",
            port: 8388,
            password: "your_password",
            method: "aes-256-gcm"
        )
        Task { [weak self] in
            do {
                try await defaultServer.savePassword()
                DispatchQueue.main.async {
                    self?.servers = [defaultServer]
                    self?.currentServerId = self?.servers.first?.id
                    self?.saveServers()
                }
            } catch {
                self?.log(">> Ошибка сохранения пароля по умолчанию: \(error)")
            }
        }
    }
    
    func saveServers() {
        do {
            try FileManager.default.createDirectory(
                at: serversPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            servers = servers.map {
                var server = $0
                server.isActive = (server.id == currentServerId)
                return server
            }
            let data = try JSONEncoder().encode(servers)
            try data.write(to: serversPath)
            log(">> Серверы сохранены в \(serversPath.path)")
        } catch {
            log(">> Ошибка сохранения серверов: \(error)")
        }
    }
    
    func addServer(_ server: ShadowsocksServer) {
        Task {
            do {
                try await server.savePassword()
                servers.append(server)
                saveServers()
                log(">> Сервер \(server.name) добавлен")
            } catch {
                log(">> Ошибка добавления пароля для \(server.name): \(error)")
            }
        }
    }
    
    func updateServer(_ server: ShadowsocksServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            Task {
                do {
                    try await server.updatePassword()
                    servers[index] = server
                    saveServers()
                    log(">> Сервер \(server.name) обновлен")
                } catch {
                    do {
                        try await server.savePassword()
                        servers[index] = server
                        saveServers()
                        log(">> Сервер \(server.name) сохранен как новый в Keychain")
                    } catch {
                        log(">> Ошибка обновления пароля для \(server.name): \(error)")
                    }
                }
            }
        }
    }
    
    func removeServer(at index: Int) {
        let server = servers[index]
        cancelPing(for: server.id)
        Task {
            do {
                try await server.deletePassword()
                if server.id == currentServerId {
                    currentServerId = servers.first?.id
                }
                servers.remove(at: index)
                saveServers()
                log(">> Сервер \(server.name) удален")
            } catch {
                log(">> Ошибка удаления пароля для \(server.name): \(error)")
            }
        }
    }
    
    func selectServer(_ id: UUID) {
        currentServerId = id
        saveServers()
        log(">> Выбран сервер с ID: \(id)")
    }
    
    func pingServer(_ server: ShadowsocksServer) {
        cancelPing(for: server.id)
        
        let task = Process()
        pingTasks[server.id] = task
        task.launchPath = "/sbin/ping"
        task.arguments = ["-c", "3", "-t", "2", server.address]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.terminationHandler = { [weak self] _ in
            guard let self = self else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let pattern = "min/avg/max/stddev = [\\d.]+/([\\d.]+)/[\\d.]+/[\\d.]+"
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            
            var pingValue: Double? = 9999
            if let match = regex?.firstMatch(in: output, range: range) {
                if let pingRange = Range(match.range(at: 1), in: output) {
                    pingValue = Double(output[pingRange])
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let index = self.servers.firstIndex(where: { $0.id == server.id }) {
                    self.servers[index].lastPing = pingValue
                    self.servers[index].lastUpdate = Date()
                    self.saveServers()
                    self.log(">> Пинг сервера \(server.name): \(pingValue != nil ? "\(pingValue!) мс" : "Не удалось измерить")")
                }
                self.pingTasks.removeValue(forKey: server.id)
            }
        }
        
        do {
            try task.run()
            log(">> Запущен пинг для \(server.name)")
        } catch {
            pingTasks.removeValue(forKey: server.id)
            log(">> Ошибка пинга для \(server.name): \(error)")
        }
    }
    
    func speedTest(server: ShadowsocksServer) async throws {
        let url = URL(string: "https://speedtest.net/1MB.test")!
        let start = Date()
        let (_, _) = try await URLSession.shared.data(from: url)
        let speed = 1.0 / -start.timeIntervalSinceNow // MB/s
        
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].lastSpeed = speed
            servers[index].lastUpdate = Date()
            saveServers()
            log(">> Скорость сервера \(server.name): \(speed) MB/s")
        }
    }
    
    func cancelPing(for serverId: UUID) {
        if let task = pingTasks[serverId] {
            task.terminate()
            pingTasks.removeValue(forKey: serverId)
            log(">> Пинг для сервера \(serverId) отменен")
        }
    }
    
    func pingCurrentServer() {
        guard let server = currentServer else {
            log(">> Ошибка: Текущий сервер не выбран")
            return
        }
        pingServer(server)
    }
    
    func speedTestCurrentServer() {
        guard let server = currentServer else {
            log(">> Ошибка: Текущий сервер не выбран")
            return
        }
        Task {
            do {
                try await speedTest(server: server)
            } catch {
                log(">> Ошибка теста скорости: \(error)")
            }
        }
    }
    
    func testAllServers() {
        isTestingAllServers = true
        let group = DispatchGroup()
        
        for server in servers {
            group.enter()
            Task { [weak self] in
                guard let self = self else {
                    group.leave()
                    return
                }
                self.pingServer(server)
                do {
                    try await self.speedTest(server: server)
                } catch {
                    self.log(">> Ошибка теста скорости в testAll: \(error)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isTestingAllServers = false
            self?.log(">> Тестирование всех серверов завершено")
        }
        log(">> Запущено тестирование всех серверов")
    }
    
    func autoSelectBestServer() {
        guard !servers.isEmpty else {
            log(">> Ошибка: Список серверов пуст")
            return
        }
        
        let validServers = servers.compactMap { server -> (ShadowsocksServer, Double)? in
            guard let ping = server.lastPing, let speed = server.lastSpeed else { return nil }
            return (server, ping / speed) // Приоритет: низкий пинг, высокая скорость
        }
        
        if let bestServer = validServers.min(by: { $0.1 < $1.1 })?.0 {
            selectServer(bestServer.id)
            log(">> Автоматически выбран сервер: \(bestServer.name) (пинг: \(bestServer.lastPing ?? 0) мс, скорость: \(bestServer.lastSpeed ?? 0) MB/s)")
        } else if !servers.isEmpty {
            selectServer(servers[0].id)
            log(">> Выбран первый сервер по умолчанию: \(servers[0].name)")
        }
    }
    
    func importFromSubscription(urlString: String) async {
        guard let url = URL(string: urlString) else {
            log(">> Ошибка: Неверный URL подписки")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let base64 = String(data: data, encoding: .utf8),
                  let decoded = Data(base64Encoded: base64) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат подписки"])
            }
            var newServers = try JSONDecoder().decode([ShadowsocksServer].self, from: decoded)
            for i in newServers.indices {
                newServers[i].password = ""
                await addServer(newServers[i])
            }
            log(">> Импортировано \(newServers.count) серверов из подписки")
        } catch {
            log(">> Ошибка импорта подписки: \(error)")
        }
    }
    
    func fetchFreeNodes() async {
        let url = URL(string: "https://api.sshocean.com/free-shadowsocks")! // Пример
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let servers = try JSONDecoder().decode([ShadowsocksServer].self, from: data)
            for server in servers {
                await addServer(server)
            }
            log(">> Импортировано \(servers.count) бесплатных нод")
            sendNotification(title: "Бесплатные ноды", body: "Внимание: Бесплатные серверы могут быть небезопасны.")
        } catch {
            log(">> Ошибка импорта бесплатных нод: \(error)")
        }
    }
    
    func checkInstallation() {
        installationState = .checking
        log(">> Проверка установки Shadowsocks...")
        
        let possiblePaths = isAppleSilicon() ? [
            "/opt/homebrew/bin/ss-local",
            "/opt/homebrew/opt/shadowsocks-libev/bin/ss-local",
            "/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin/ss-local",
            "/opt/homebrew/bin/sslocal",
            "/opt/homebrew/opt/shadowsocks-libev/bin/sslocal",
            "/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin/sslocal",
            "/usr/local/bin/ss-local",
            "/usr/local/bin/sslocal",
            "/usr/bin/ss-local",
            "/usr/bin/sslocal"
        ] : [
            "/usr/local/bin/ss-local",
            "/usr/local/bin/sslocal",
            "/usr/bin/ss-local",
            "/usr/bin/sslocal",
            "/opt/homebrew/bin/ss-local",
            "/opt/homebrew/opt/shadowsocks-libev/bin/ss-local",
            "/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin/ss-local"
        ]
        var foundPath: String?
        
        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                foundPath = path
                break
            }
        }
        
        if foundPath == nil, let pathFromWhich = findSSLocalPath() {
            if FileManager.default.isExecutableFile(atPath: pathFromWhich) {
                foundPath = pathFromWhich
            }
        }
        
        if let path = foundPath {
            let versionResult = executeShellCommand("\(path) --version")
            if versionResult.success, versionResult.output.lowercased().contains("shadowsocks") {
                DispatchQueue.main.async {
                    self.installationState = .installed
                    self.log(">> Shadowsocks найден: \(path)")
                }
                return
            }
        }
        
        DispatchQueue.main.async {
            self.installationState = .notInstalled
            self.log(">> Shadowsocks не найден. Установите через кнопку.")
        }
    }
    
    func installShadowsocks() {
        installationState = .installing(progress: 0.0)
        log(">> Запуск установки Shadowsocks...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let brewPath = self.findBrewPath() ?? (self.isAppleSilicon() ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew")
            
            let commands = [
                ("Проверка Homebrew", "/usr/bin/which brew", 0.1),
                ("Установка Homebrew", "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", 0.3),
                ("Обновление Homebrew", "\(brewPath) update", 0.5),
                ("Установка Shadowsocks", "\(brewPath) install shadowsocks-libev", 0.9),
                ("Проверка установки", "\(brewPath) which ss-local", 1.0)
            ]
            
            for (step, command, progress) in commands {
                DispatchQueue.main.async {
                    self.log(">> [УСТАНОВКА] \(step)...")
                    self.installationState = .installing(progress: progress)
                }
                
                let result = self.executeShellCommand(command)
                if !result.success {
                    DispatchQueue.main.async {
                        self.installationState = .error(message: "Ошибка на этапе '\(step)': \(result.output)")
                        self.log(">> [ОШИБКА] \(result.output)")
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                self.installationState = .installed
                self.log(">> Установка Shadowsocks завершена")
                self.checkInstallation()
            }
        }
    }
    
    private func executeShellCommand(_ command: String) -> (success: Bool, output: String) {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            log(">> Выполнение команды: \(command)")
            try task.run()
            task.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            let fullOutput = output + errorOutput
            return (task.terminationStatus == 0, fullOutput)
        } catch {
            return (false, error.localizedDescription)
        }
    }
    
    private func getActiveInterface() -> String {
        let result = executeShellCommand("networksetup -listallnetworkservices")
        if result.success {
            let services = result.output.split(separator: "\n")
            return services.first { !$0.contains("disabled") }?.description ?? "Wi-Fi"
        }
        return "Wi-Fi"
    }
    
    func setSystemProxy(enabled: Bool) {
        guard proxyMode != .manual else { return }
        let interface = getActiveInterface()
        let port = currentServer?.localPort ?? 1080
        let command = enabled ?
            "networksetup -setsocksfirewallproxy \(interface) 127.0.0.1 \(port)" :
            "networksetup -setsocksfirewallproxystate \(interface) off"
        let result = executeShellCommand(command)
        if result.success {
            log(">> Системный прокси \(enabled ? "включен" : "выключен") для \(interface)")
        } else {
            log(">> Ошибка настройки прокси: \(result.output)")
        }
    }
    
    func generatePACFile() {
        let pacContent = """
        function FindProxyForURL(url, host) {
            return "SOCKS5 127.0.0.1:\(currentServer?.localPort ?? 1080); DIRECT";
        }
        """
        do {
            try pacContent.write(to: pacPath, atomically: true, encoding: .utf8)
            let pacCommand = "networksetup -setautoproxyurl \(getActiveInterface()) file://\(pacPath.path)"
            let result = executeShellCommand(pacCommand)
            if result.success {
                log(">> PAC файл установлен: \(pacPath.path)")
            } else {
                log(">> Ошибка установки PAC: \(result.output)")
            }
        } catch {
            log(">> Ошибка создания PAC файла: \(error)")
        }
    }
    
    func start() {
            guard case .installed = installationState else {
                log(">> Ошибка: Shadowsocks не установлен")
                return
            }
            
            guard var server = currentServer else {
                log(">> Ошибка: Сервер не выбран")
                return
            }
            
            Task { [weak self] in
                do {
                    server.password = try await server.loadPassword()
                } catch KeychainError.itemNotFound {
                    server.password = ""
                } catch {
                    self?.log(">> Ошибка загрузки пароля для \(server.name): \(error)")
                    return
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    guard !self.isRunning else {
                        self.log(">> Shadowsocks уже запущен")
                        return
                    }
                    
                    self.connectionStatus = .connecting
                    self.log(">> Подключение к \(server.name)...")
                    
                    let tempConfigPath = FileManager.default.temporaryDirectory
                        .appendingPathComponent("shadowsocks_temp_config_\(server.id.uuidString).json")
                    
                    var config: [String: Any] = [
                        "server": server.address,
                        "server_port": server.port,
                        "local_port": server.localPort,
                        "method": server.method,
                        "timeout": server.timeout
                    ]
                    
                    if !server.password.isEmpty {
                        config["password"] = server.password
                    }
                    
                    do {
                        let configData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
                        try configData.write(to: tempConfigPath)
                        self.log(">> Конфигурация создана: \(tempConfigPath.path)")
                    } catch {
                        self.connectionStatus = .error
                        self.log(">> Ошибка создания конфигурации: \(error)")
                        return
                    }
                    
                    self.process = Process()
                    let possiblePaths = self.isAppleSilicon() ? [
                        "/opt/homebrew/bin/ss-local",
                        "/opt/homebrew/opt/shadowsocks-libev/bin/ss-local",
                        "/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin/ss-local",
                        "/opt/homebrew/bin/sslocal",
                        "/opt/homebrew/opt/shadowsocks-libev/bin/sslocal",
                        "/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin/sslocal",
                        "/usr/local/bin/ss-local",
                        "/usr/local/bin/sslocal",
                        "/usr/bin/ss-local",
                        "/usr/bin/sslocal"
                    ] : [
                        "/usr/local/bin/ss-local",
                        "/usr/local/bin/sslocal",
                        "/usr/bin/ss-local",
                        "/usr/bin/sslocal",
                        "/opt/homebrew/bin/ss-local",
                        "/opt/homebrew/opt/shadowsocks-libev/bin/ss-local",
                        "/opt/homebrew/Cellar/shadowsocks-libev/3.3.5_5/bin/ss-local"
                    ]
                    var executablePath: String?
                    
                    for path in possiblePaths {
                        if FileManager.default.isExecutableFile(atPath: path) {
                            executablePath = path
                            break
                        }
                    }
                    
                    if executablePath == nil, let pathFromWhich = self.findSSLocalPath() {
                        if FileManager.default.isExecutableFile(atPath: pathFromWhich) {
                            executablePath = pathFromWhich
                        }
                    }
                    
                    guard let path = executablePath else {
                        self.connectionStatus = .error
                        self.log(">> Ошибка: ss-local не найден")
                        return
                    }
                    
                    self.process?.executableURL = URL(fileURLWithPath: path)
                    self.process?.arguments = ["-c", tempConfigPath.path, "-v"]
                    
                    self.outputPipe = Pipe()
                    self.errorPipe = Pipe()
                    self.process?.standardOutput = self.outputPipe
                    self.process?.standardError = self.errorPipe
                    
                    self.outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
                        guard let self = self else { return }
                        let data = handle.availableData
                        if let line = String(data: data, encoding: .utf8) {
                            DispatchQueue.main.async {
                                self.logMessages += line
                                if line.contains("listening at") {
                                    self.connectionStatus = .connected
                                    self.isRunning = true
                                    self.sendNotification(title: "Подключение", body: "Shadowsocks подключен к \(server.name)")
                                    if self.proxyMode == .global {
                                        self.setSystemProxy(enabled: true)
                                    } else if self.proxyMode == .pac {
                                        self.generatePACFile()
                                    }
                                    self.startTrafficMonitor()
                                }
                                if line.contains("error") || line.contains("failed") {
                                    self.connectionStatus = .error
                                    self.sendNotification(title: "Ошибка", body: "Ошибка подключения: \(line)")
                                }
                            }
                        }
                    }
                    
                    self.errorPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
                        guard let self = self else { return }
                        let data = handle.availableData
                        if let line = String(data: data, encoding: .utf8) {
                            DispatchQueue.main.async {
                                self.log(">> ОШИБКА: \(line)")
                                self.connectionStatus = .error
                                self.sendNotification(title: "Ошибка", body: "Ошибка Shadowsocks: \(line)")
                            }
                        }
                    }
                    
                    self.process?.terminationHandler = { [weak self] process in
                        guard let self = self else { return }
                        DispatchQueue.main.async {
                            self.isRunning = false
                            self.connectionStatus = .disconnected
                            self.setSystemProxy(enabled: false)
                            self.log(">> Процесс завершен со статусом: \(process.terminationStatus)")
                            if process.terminationStatus != 0 {
                                self.connectionStatus = .error
                                self.sendNotification(title: "Ошибка", body: "Shadowsocks завершился с ошибкой")
                            }
                        }
                    }
                    
                    do {
                        try self.process?.run()
                        self.log(">> Shadowsocks запущен: \(tempConfigPath.path)")
                        self.startConnectionMonitor()
                    } catch {
                        self.connectionStatus = .error
                        self.log(">> Ошибка запуска Shadowsocks: \(error)")
                    }
                }
            }
        }
    
    func stop() {
        guard isRunning, let process = process else {
            log(">> Shadowsocks не запущен")
            return
        }

        process.interrupt()

        DispatchQueue.global().async { [weak self] in
            let timeout: TimeInterval = 2.0
            if process.isRunning {
                Thread.sleep(forTimeInterval: timeout)
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.main.async {
                        self?.log(">> Shadowsocks принудительно завершен")
                    }
                }
            }
        }

        stopConnectionMonitor()
        stopTrafficMonitor()
        setSystemProxy(enabled: false)
        log(">> Shadowsocks остановлен")
        sendNotification(title: "Отключение", body: "Shadowsocks отключен")
    }
    
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
            self?.log(">> Перезапуск Shadowsocks")
        }
    }
    
    func startConnectionMonitor() {
        connectionMonitorTimer?.invalidate()
        connectionMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: 10,
            repeats: true
        ) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            if let server = self.currentServer {
                self.pingServer(server)
                if let ping = server.lastPing, ping > 1000 || server.lastPing == nil {
                    self.retryCount += 1
                    if self.retryCount <= self.maxRetries {
                        self.log(">> Нестабильное подключение (\(self.retryCount)/\(self.maxRetries)), перезапуск...")
                        self.restart()
                    } else {
                        self.log(">> Достигнуто максимальное количество попыток")
                        self.stop()
                        self.retryCount = 0
                    }
                } else {
                    self.retryCount = 0
                }
            }
        }
        log(">> Мониторинг подключения запущен")
    }
    
    func stopConnectionMonitor() {
        connectionMonitorTimer?.invalidate()
        connectionMonitorTimer = nil
        log(">> Мониторинг подключения остановлен")
    }
    
    func startTrafficMonitor() {
        trafficTimer?.invalidate()
        trafficTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            // Пример: парсинг логов ss-local или netstat
            self.downloadSpeed = Double.random(in: 0...10) // Заглушка
            self.uploadSpeed = Double.random(in: 0...5)
            self.totalTraffic += Int(self.downloadSpeed + self.uploadSpeed)
            self.speedData.append(SpeedData(date: Date(), download: self.downloadSpeed, upload: self.uploadSpeed))
            if self.speedData.count > 60 {
                self.speedData.removeFirst()
            }
        }
        log(">> Мониторинг трафика запущен")
    }
    
    func stopTrafficMonitor() {
        trafficTimer?.invalidate()
        trafficTimer = nil
        log(">> Мониторинг трафика остановлен")
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = Date().formatted(date: .omitted, time: .standard)
            self.logMessages += "[\(timestamp)] \(message)\n"
            if self.logMessages.count > 5000 {
                self.logMessages = String(self.logMessages.suffix(4000))
            }
        }
    }
}

// MARK: - Представление для генерации QR-кода
struct QRCodeGeneratorView: View {
    let server: ShadowsocksServer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Поделиться конфигурацией")
                .font(.title3.bold())

            if let image = generateQRCode() {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)

                Text(server.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)

                Button("Копировать конфигурацию") {
                    Task { @MainActor in
                        copyConfigurationToClipboard()
                        ShadowsocksManager.shared.log(">> Конфигурация \(server.name) скопирована")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else {
                Text("Ошибка генерации QR-кода")
                    .foregroundStyle(.red)
            }

            Button("Закрыть") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.secondary)
        }
        .padding(24)
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }

    private func generateQRCode() -> NSImage? {
        var configString = "\(server.method)@\(server.address):\(server.port)"
        if !server.password.isEmpty {
            configString = "\(server.method):\(server.password)@\(server.address):\(server.port)"
        }
        guard let configData = configString.data(using: .utf8) else {
            Task { @MainActor in
                ShadowsocksManager.shared.log(">> Ошибка кодирования QR-кода")
            }
            return nil
        }
        let base64String = configData.base64EncodedString()
        let qrString = "ss://\(base64String)"

        guard let filter = CIFilter(name: "CIQRCodeGenerator"),
              let data = qrString.data(using: .utf8) else {
            Task { @MainActor in
                ShadowsocksManager.shared.log(">> Ошибка создания QR-кода")
            }
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage,
              let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            Task { @MainActor in
                ShadowsocksManager.shared.log(">> Ошибка генерации изображения QR-кода")
            }
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }

    private func copyConfigurationToClipboard() {
        var configString = "\(server.method)@\(server.address):\(server.port)"
        if !server.password.isEmpty {
            configString = "\(server.method):\(server.password)@\(server.address):\(server.port)"
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configString, forType: .string)
    }
}
// MARK: - Главное представление
struct ContentView: View {
    @StateObject private var manager = ShadowsocksManager.shared
    @State private var showingConfig = false
    @State private var showingLog = false
    @State private var showingPrefs = false
    @State private var showingServers = false
    @State private var showingAbout = false
    @AppStorage("theme") private var theme: String = "system"
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("МЕНЕДЖЕР SHADOWSOCKS")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.top, 32)
            
            StatusView(
                isRunning: manager.isRunning,
                installationState: manager.installationState,
                connectionStatus: manager.connectionStatus,
                currentServer: manager.currentServer,
                uploadSpeed: manager.uploadSpeed,
                downloadSpeed: manager.downloadSpeed,
                totalTraffic: manager.totalTraffic,
                speedData: manager.speedData
            )
            
            ControlButtonsView(
                isRunning: manager.isRunning,
                installationState: manager.installationState,
                onStart: { manager.start() },
                onStop: { manager.stop() },
                onRestart: { manager.restart() },
                onInstall: { manager.installShadowsocks() },
                onPing: { manager.pingCurrentServer() },
                onSpeedTest: { manager.speedTestCurrentServer() },
                onAutoSelect: { manager.autoSelectBestServer() },
                onTestAll: { manager.testAllServers() },
                isTestingAll: manager.isTestingAllServers
            )
            
            SecondaryButtonsView(
                onConfig: { showingConfig = true },
                onLogs: { showingLog = true },
                onPrefs: { showingPrefs = true },
                onServers: { showingServers = true },
                onAbout: { showingAbout = true }
            )
            
            Spacer()
            
            VStack(spacing: 4) {
                Divider()
                Text("© 2025 KNOWER LIFE МЕНЕДЖЕР SHADOWSOCKS")
                    .font(.system(size: 10, weight: .light))
                    .foregroundColor(.secondary)
                Text("Версия 1.1 | Все права защищены")
                    .font(.system(size: 8, weight: .light))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 32)
        .frame(minWidth: 480, minHeight: 600)
        .background(.regularMaterial)
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        .sheet(isPresented: $showingConfig) {
            Group {
                if let currentServer = manager.currentServer {
                    ServerEditView(server: currentServer) { updatedServer in
                        manager.updateServer(updatedServer)
                        if manager.isRunning {
                            manager.restart()
                        }
                    } onCancel: { manager.log(">> Редактирование сервера отменено") }
                        .environmentObject(manager)
                } else {
                    Text("Сервер не выбран")
                        .font(.title)
                        .padding()
                }
            }
        }
        .sheet(isPresented: $showingLog) {
            LogView()
                .environmentObject(manager)
        }
        .sheet(isPresented: $showingPrefs) {
            PreferencesView()
        }
        .sheet(isPresented: $showingServers) {
            ServerManagementView()
                .environmentObject(manager)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
}

// MARK: - Стили кнопок
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.blue)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 1)
            )
            .shadow(color: .blue.opacity(0.1), radius: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

// MARK: - Представление управления серверами
struct ServerManagementView: View {
    @EnvironmentObject private var manager: ShadowsocksManager
    @Environment(\.dismiss) private var dismiss
    @State private var newServer = ShadowsocksServer(
        name: "Новый сервер",
        address: "new_server.com",
        port: 8388,
        password: "password",
        method: "aes-256-gcm"
    )
    @State private var editingServer: ShadowsocksServer?
    @State private var showingEditSheet = false
    @State private var showingImportExport = false
    @State private var showingSubscriptionImport = false
    @State private var subscriptionURL = ""
    @State private var serverToDelete: Int?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Управление серверами")
                    .font(.title3.bold())
                Spacer()
                Button(action: { showingImportExport = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                Button(action: { showingSubscriptionImport = true }) {
                    Image(systemName: "link")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
            }
            .padding()

            List {
                ForEach(manager.servers.indices, id: \.self) { index in
                    ServerRowView(
                        server: manager.servers[index],
                        isActive: manager.currentServerId == manager.servers[index].id,
                        onSelect: {
                            Task { @MainActor in
                                manager.selectServer(manager.servers[index].id)
                            }
                        },
                        onPing: {
                            Task { @MainActor in
                                manager.pingServer(manager.servers[index])
                            }
                        },
                        onSpeedTest: {
                            Task {
                                do {
                                    try await manager.speedTest(server: manager.servers[index])
                                } catch {
                                    await manager.log(">> Ошибка теста скорости: \(error)")
                                }
                            }
                        },
                        onEdit: {
                            Task {
                                var editServer = manager.servers[index]
                                if editServer.password.isEmpty {
                                    do {
                                        editServer.password = try await editServer.loadPassword()
                                    } catch {
                                        await manager.log(">> Ошибка загрузки пароля: \(error)")
                                    }
                                }
                                editingServer = editServer
                                showingEditSheet = true
                            }
                        }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible)
                    .contextMenu {
                        Button("Установить как активный") {
                            Task { @MainActor in
                                manager.selectServer(manager.servers[index].id)
                            }
                        }
                        Button("Дублировать") {
                            Task { @MainActor in
                                var newServer = manager.servers[index]
                                newServer.id = UUID()
                                newServer.name += " Копия"
                                manager.addServer(newServer)
                            }
                        }
                        Button("Генерировать QR-код") { showQRCode(for: manager.servers[index]) }
                        Button("Копировать конфигурацию") { copyServerConfiguration(manager.servers[index]) }
                        Divider()
                        Button("Удалить", role: .destructive) { serverToDelete = index }
                    }
                }
                .onMove { indices, newOffset in
                    manager.servers.move(fromOffsets: indices, toOffset: newOffset)
                    manager.saveServers()
                }
            }
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)

            HStack {
                Button("Добавить сервер") {
                    editingServer = newServer
                    showingEditSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Бесплатные ноды") {
                    Task { await manager.fetchFreeNodes() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Spacer()

                Button("Закрыть") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .sheet(isPresented: $showingEditSheet) {
            if editingServer != nil {
                ServerEditView(
                    server: editingServer!,
                    onSave: { updatedServer in
                        Task { @MainActor in
                            if manager.servers.firstIndex(where: { $0.id == updatedServer.id }) != nil {
                                manager.updateServer(updatedServer)
                            } else {
                                manager.addServer(updatedServer)
                            }
                            editingServer = nil
                        }
                    },
                    onCancel: { editingServer = nil }
                )
                .environmentObject(manager)
            }
        }
        .sheet(isPresented: $showingImportExport) {
            ImportExportView()
                .environmentObject(manager)
        }
        .sheet(isPresented: $showingSubscriptionImport) {
            SubscriptionImportView(subscriptionURL: $subscriptionURL)
                .environmentObject(manager)
        }
        .alert("Подтвердить удаление", isPresented: Binding(
            get: { serverToDelete != nil },
            set: { if !$0 { serverToDelete = nil } }
        )) {
            Button("Удалить", role: .destructive) {
                if let index = serverToDelete {
                    Task { @MainActor in
                        manager.removeServer(at: index)
                        serverToDelete = nil
                    }
                }
            }
            Button("Отмена", role: .cancel) { serverToDelete = nil }
        } message: {
            if let index = serverToDelete {
                Text("Вы уверены, что хотите удалить сервер '\(manager.servers[index].name)'?")
            }
        }
    }

    private func showQRCode(for server: ShadowsocksServer) {
        let qrView = QRCodeGeneratorView(server: server)
        let controller = NSHostingController(rootView: qrView)
        let window = NSWindow(contentViewController: controller)
        window.makeKeyAndOrderFront(nil)
    }

    private func copyServerConfiguration(_ server: ShadowsocksServer) {
        var config = "\(server.method)@\(server.address):\(server.port)"
        if !server.password.isEmpty {
            config = "\(server.method):\(server.password)@\(server.address):\(server.port)"
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(config, forType: .string)
    }
}

// MARK: - Импорт подписки
struct SubscriptionImportView: View {
    @EnvironmentObject private var manager: ShadowsocksManager
    @Environment(\.dismiss) private var dismiss
    @Binding var subscriptionURL: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Импорт подписки")
                .font(.title3.bold())
            
            TextField("URL подписки", text: $subscriptionURL)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Импортировать") {
                    Task { await manager.importFromSubscription(urlString: subscriptionURL) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscriptionURL.isEmpty || !URL(string: subscriptionURL)!.isValidURL)
                
                Button("Отмена") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}

extension URL {
    var isValidURL: Bool {
        let urlRegEx = "^(https?://)?([\\w-]+\\.)+[\\w-]+(/[\\w-./?%&=]*)?$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", urlRegEx)
        return predicate.evaluate(with: absoluteString)
    }
}

// MARK: - Представление редактирования сервера
struct ServerEditView: View {
    @EnvironmentObject private var manager: ShadowsocksManager
    @Environment(\.dismiss) private var dismiss
    @State var server: ShadowsocksServer
    var onSave: (ShadowsocksServer) -> Void
    var onCancel: () -> Void
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(server.id == manager.currentServer?.id ? "Редактировать сервер" : "Добавить новый сервер")
                .font(.title3.bold())

            Form {
                Section {
                    TextField("Имя сервера", text: $server.name)
                        .focused($focusedField, equals: "name")
                    TextField("Адрес сервера", text: $server.address)
                        .focused($focusedField, equals: "address")
                    TextField("Порт сервера", value: $server.port, formatter: NumberFormatter())
                        .focused($focusedField, equals: "port")
                        .onChange(of: server.port) { _, newValue in
                            if newValue < 1 || newValue > 65535 {
                                server.port = 8388
                            }
                        }
                    SecureField("Пароль", text: $server.password)
                        .focused($focusedField, equals: "password")
                }

                Section {
                    Picker("Метод шифрования", selection: $server.method) {
                        ForEach(ShadowsocksManager.supportedMethods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }
                    TextField("Локальный порт", value: $server.localPort, formatter: NumberFormatter())
                        .focused($focusedField, equals: "localPort")
                        .onChange(of: server.localPort) { _, newValue in
                            if newValue < 1024 || newValue > 65535 {
                                server.localPort = 1080
                            }
                        }
                }
            }
            .formStyle(.grouped)

            if server.password.isEmpty {
                Text("Пароль пустой. Его можно установить позже.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 16) {
                Button("Отмена") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Сохранить") {
                    Task {
                        if server.isValid {
                            try await server.updatePassword()
                            onSave(server)
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!server.isValid)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}

// MARK: - Представление импорта/экспорта
struct ImportExportView: View {
    @EnvironmentObject private var manager: ShadowsocksManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingExporter = false
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Импорт и экспорт серверов")
                .font(.title3.bold())

            VStack(spacing: 12) {
                Button {
                    showingImporter = true
                } label: {
                    Label("Импорт из файла", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    showingExporter = true
                } label: {
                    Label("Экспорт в файл", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            Spacer()

            Button("Закрыть") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 320, height: 240)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .fileExporter(
            isPresented: $showingExporter,
            document: ServersDocument(servers: manager.servers),
            contentType: UTType.json,
            defaultFilename: "shadowsocks_servers.json"
        ) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    manager.log(">> Серверы экспортированы")
                case .failure(let error):
                    manager.log(">> Ошибка экспорта: \(error)")
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        manager.log(">> Ошибка: Файл не выбран")
                        return
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        let servers = try JSONDecoder().decode([ShadowsocksServer].self, from: data)
                        for server in servers {
                            manager.addServer(server)
                        }
                        manager.log(">> Импортировано \(servers.count) серверов")
                    } catch {
                        manager.log(">> Ошибка импорта: \(error)")
                    }
                case .failure(let error):
                    manager.log(">> Ошибка импорта: \(error)")
                }
            }
        }
    }
}

// MARK: - Остальные компоненты интерфейса
struct ServerRowView: View {
    let server: ShadowsocksServer
    let isActive: Bool
    let onSelect: () -> Void
    let onPing: () -> Void
    let onSpeedTest: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isActive ? .blue : .gray.opacity(0.5))
                    .font(.system(size: 20))
            }
            .buttonStyle(.borderless)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                    .foregroundColor(isActive ? .blue : .primary)
                    .lineLimit(1)
                
                Text("\(server.address):\(server.port)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let lastUpdate = server.lastUpdate {
                Text("Обновлено: \(lastUpdate, style: .relative) назад")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if let ping = server.lastPing {
                PingIndicator(ping: ping)
            } else {
                Text("Пинг не тестирован")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            if let speed = server.lastSpeed {
                Text("\(String(format: "%.2f", speed)) MB/s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            Button(action: onPing) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            
            Button(action: onSpeedTest) {
                Image(systemName: "speedometer")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

struct PingIndicator: View {
    let ping: Double
    
    var statusColor: Color {
        if ping < 100 { return .green }
        if ping < 300 { return .blue }
        if ping < 500 { return .orange }
        return .red
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text("\(String(format: "%.0f", ping)) мс")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct StatusView: View {
    let isRunning: Bool
    let installationState: ShadowsocksManager.InstallationState
    let connectionStatus: ShadowsocksManager.ConnectionStatus
    let currentServer: ShadowsocksServer?
    let uploadSpeed: Double
    let downloadSpeed: Double
    let totalTraffic: Int
    let speedData: [ShadowsocksManager.SpeedData]
    
    var statusText: String {
        switch installationState {
        case .checking: return "Проверка установки..."
        case .installed: return connectionStatus.rawValue
        case .notInstalled: return "SHADOWSOCKS НЕ УСТАНОВЛЕН"
        case .installing(let progress): return "УСТАНОВКА... (\(Int(progress * 100))%)"
        case .error(let message): return "ОШИБКА: \(message)"
        }
    }
    
    var statusColor: Color {
        switch installationState {
        case .checking: return .gray
        case .installed:
            switch connectionStatus {
            case .connected: return .green
            case .connecting: return .orange
            case .disconnected: return .blue
            case .error: return .red
            }
        case .notInstalled: return .red
        case .installing: return .orange
        case .error: return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(statusText)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(statusColor)
                .lineLimit(1)
            
            if let server = currentServer {
                Text(server.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                HStack(spacing: 8) {
                    if let ping = server.lastPing {
                        PingIndicator(ping: ping)
                    } else {
                        Text("Пинг не тестирован")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastUpdate = server.lastUpdate {
                        Text("(\(lastUpdate, style: .relative) назад)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    Text("↓ \(String(format: "%.2f", downloadSpeed)) MB/s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("↑ \(String(format: "%.2f", uploadSpeed)) MB/s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Трафик: \(totalTraffic) MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if case .installing(let progress) = installationState {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(height: 4)
            }
            
            if isRunning, (currentServer != nil) {
                Chart(speedData) { data in
                    LineMark(
                        x: .value("Time", data.date),
                        y: .value("Download", data.download)
                    )
                    .foregroundStyle(.blue)
                    
                    LineMark(
                        x: .value("Time", data.date),
                        y: .value("Upload", data.upload)
                    )
                    .foregroundStyle(.purple)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(format: Decimal.FormatStyle().precision(.fractionLength(2)))
                }
                .frame(height: 100)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

struct ControlButtonsView: View {
    let isRunning: Bool
    let installationState: ShadowsocksManager.InstallationState
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onInstall: () -> Void
    let onPing: () -> Void
    let onSpeedTest: () -> Void
    let onAutoSelect: () -> Void
    let onTestAll: () -> Void
    let isTestingAll: Bool

    @State private var isInstalling = false

    var body: some View {
        if case .notInstalled = installationState {
            Button(action: {
                isInstalling = true
                Task { @MainActor in
                    onInstall()
                }
            }) {
                if isInstalling {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Text("Установить Shadowsocks")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(isInstalling)
        } else {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ActionButton(
                        title: "Запустить",
                        icon: "play.fill",
                        action: { Task { @MainActor in onStart() } },
                        disabled: isRunning || !installationState.isInstalled
                    )
                    ActionButton(
                        title: "Остановить",
                        icon: "stop.fill",
                        action: { Task { @MainActor in onStop() } },
                        disabled: !isRunning
                    )
                    ActionButton(
                        title: "Перезапустить",
                        icon: "arrow.clockwise",
                        action: { Task { @MainActor in onRestart() } },
                        disabled: !isRunning
                    )
                    ActionButton(
                        title: "Пинг",
                        icon: "network",
                        action: { Task { @MainActor in onPing() } },
                        disabled: !installationState.isInstalled
                    )
                }
                HStack(spacing: 12) {
                    ActionButton(
                        title: "Тест скорости",
                        icon: "speedometer",
                        action: { Task { @MainActor in onSpeedTest() } },
                        disabled: !installationState.isInstalled
                    )
                    ActionButton(
                        title: "Автовыбор",
                        icon: "bolt.fill",
                        action: { Task { @MainActor in onAutoSelect() } },
                        disabled: !installationState.isInstalled
                    )
                    ActionButton(
                        title: "Тест всех",
                        icon: "wand.and.stars",
                        action: { Task { @MainActor in onTestAll() } },
                        disabled: isTestingAll || !installationState.isInstalled
                    )
                    .overlay(
                        isTestingAll ? ProgressView().controlSize(.small) : nil
                    )
                }
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var disabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(disabled ? .secondary : .primary)
            .padding(12)
            .frame(width: 100, height: 80)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(disabled ? 0.1 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct SecondaryButtonsView: View {
    let onConfig: () -> Void
    let onLogs: () -> Void
    let onPrefs: () -> Void
    let onServers: () -> Void
    let onAbout: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            SecondaryButton(title: "Конфигурация", icon: "gearshape.fill", action: onConfig)
            SecondaryButton(title: "Логи", icon: "text.bubble.fill", action: onLogs)
            SecondaryButton(title: "Настройки", icon: "slider.horizontal.3", action: onPrefs)
            SecondaryButton(title: "Серверы", icon: "server.rack", action: onServers)
            SecondaryButton(title: "О программе", icon: "info.circle", action: onAbout)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct LogView: View {
    @EnvironmentObject private var manager: ShadowsocksManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Логи Shadowsocks")
                    .font(.title3.bold())
                
                Spacer()
                
                Button(action: {
                    manager.logMessages = ""
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(manager.logMessages)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("logContent")
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .onChange(of: manager.logMessages) {
                    withAnimation {
                        proxy.scrollTo("logContent", anchor: .bottom)
                    }
                }
            }
            
            Button("Закрыть") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}

struct PreferencesView: View {
    @AppStorage("autoConnect") var autoConnect = false
    @AppStorage("autoTestOnStart") var autoTestOnStart = false
    @AppStorage("logLevel") var logLevel = 1
    @State private var launchAtLogin = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Настройки")
                .font(.title3.bold())
            
            Form {
                Toggle("Запуск при входе", isOn: $launchAtLogin)
                Toggle("Автоподключение при запуске", isOn: $autoConnect)
                Toggle("Тестировать все серверы при запуске", isOn: $autoTestOnStart)
                
                Picker("Уровень логов", selection: $logLevel) {
                    Text("Базовый").tag(0)
                    Text("Подробный").tag(1)
                    Text("Расширенный").tag(2)
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Информация о приложении")
                    .font(.headline)
                
                HStack {
                    Text("Версия:")
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Сборка:")
                    Text("2025.08")
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("Закрыть") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 400, height: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Ошибка установки запуска при входе: \(error)")
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("KNOWER LIFE Менеджер Shadowsocks")
                .font(.title.bold())
            
            Text("Версия 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Расширенный клиент Shadowsocks для macOS с поддержкой нескольких серверов, тестированием задержки и управлением подключением.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Функции:")
                    .font(.headline)
                
                Text("• Несколько конфигураций серверов")
                Text("• Тестирование пинга в реальном времени")
                Text("• Мониторинг статуса подключения")
                Text("• Автоматический выбор лучшего сервера")
            }
            .font(.body)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Закрыть") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(width: 400, height: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}

struct ServersDocument: FileDocument {
    var servers: [ShadowsocksServer]
    
    static var readableContentTypes: [UTType] { [UTType.json] }
    
    init(servers: [ShadowsocksServer]) {
        self.servers = servers
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        servers = try JSONDecoder().decode([ShadowsocksServer].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(servers)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Точка входа приложения
@main
struct ShadowSocksManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Shadowsocks") {
                Button("Запустить") {
                    Task { @MainActor in
                        ShadowsocksManager.shared.start()
                    }
                }
                .disabled(!ShadowsocksManager.shared.installationState.isInstalled)

                Button("Остановить") {
                    Task { @MainActor in
                        ShadowsocksManager.shared.stop()
                    }
                }

                Button("Перезапустить") {
                    Task { @MainActor in
                        ShadowsocksManager.shared.restart()
                    }
                }

                Divider()

                Button("Пинг текущего сервера") {
                    Task { @MainActor in
                        ShadowsocksManager.shared.pingCurrentServer()
                    }
                }

                Button("Тест всех серверов") {
                    Task { @MainActor in
                        ShadowsocksManager.shared.testAllServers()
                    }
                }

                Button("Автовыбор лучшего сервера") {
                    Task { @MainActor in
                        ShadowsocksManager.shared.autoSelectBestServer()
                    }
                }

                Divider()

                Button("Установить Shadowsocks") {
                    Task { @MainActor in
                        ShadowsocksManager.shared.installShadowsocks()
                    }
                }
                .disabled(ShadowsocksManager.shared.installationState.isInstalled)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    @ObservedObject var manager = ShadowsocksManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Shadowsocks")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть", action: #selector(openMainWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Запустить", action: #selector(startConnection), keyEquivalent: "")
        menu.addItem(withTitle: "Остановить", action: #selector(stopConnection), keyEquivalent: "")
        menu.addItem(withTitle: "Перезапустить", action: #selector(restartConnection), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Пинг текущего сервера", action: #selector(pingCurrentServer), keyEquivalent: "")
        menu.addItem(withTitle: "Тест всех серверов", action: #selector(testAllServers), keyEquivalent: "")
        menu.addItem(withTitle: "Автовыбор лучшего сервера", action: #selector(autoSelectServer), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(terminate), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    @objc func openMainWindow() {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func startConnection() {
        Task { @MainActor in
            manager.start()
        }
    }

    @objc func stopConnection() {
        Task { @MainActor in
            manager.stop()
        }
    }

    @objc func restartConnection() {
        Task { @MainActor in
            manager.restart()
        }
    }

    @objc func pingCurrentServer() {
        Task { @MainActor in
            manager.pingCurrentServer()
        }
    }

    @objc func testAllServers() {
        Task { @MainActor in
            manager.testAllServers()
        }
    }

    @objc func autoSelectServer() {
        Task { @MainActor in
            manager.autoSelectBestServer()
        }
    }

    @objc func terminate() {
        Task { @MainActor in
            manager.stop()
            NSApp.terminate(nil)
        }
    }
}
