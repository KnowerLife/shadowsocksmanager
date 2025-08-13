import SwiftUI
import UniformTypeIdentifiers

// MARK: - Документ для импорта/экспорта серверов
struct ServersDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var servers: [ShadowsocksServer]
    
    init(servers: [ShadowsocksServer]) {
        self.servers = servers.map {
            var server = $0
            server.password = ""
            return server
        }
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.servers = try JSONDecoder().decode([ShadowsocksServer].self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(servers)
        return FileWrapper(regularFileWithContents: data)
    }
}
