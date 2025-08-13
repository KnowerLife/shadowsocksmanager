import SwiftUI

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
