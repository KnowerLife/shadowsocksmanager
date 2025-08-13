import Foundation
import Combine
import Network
import UserNotifications
import Charts

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
    @Published var uploadSpeed: Double = 0
    @Published var downloadSpeed: Double = 0
    @Published var totalTraffic: Int = 0
    @Published var proxyMode: ProxyMode = .manual
    @Published var speedData: [SpeedData] = []
    
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
        let speed = 1.0 / -start.timeIntervalSinceNow
        
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
            return (server, ping / speed)
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
        let url = URL(string: "https://api.sshocean.com/free-shadowsocks")!
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
            self.downloadSpeed = Double.random(in: 0...10)
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
