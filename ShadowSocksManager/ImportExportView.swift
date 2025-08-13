import SwiftUI
import UniformTypeIdentifiers

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
