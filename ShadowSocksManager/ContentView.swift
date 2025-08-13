import SwiftUI

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
