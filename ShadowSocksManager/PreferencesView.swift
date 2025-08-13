import SwiftUI

// MARK: - Представление настроек
struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var manager: ShadowsocksManager
    @AppStorage("theme") private var theme = "system"
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("autoUpdate") private var autoUpdate = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Настройки")
                .font(.title3.bold())
            
            Form {
                Section {
                    Picker("Тема приложения", selection: $theme) {
                        Text("Системная").tag("system")
                        Text("Светлая").tag("light")
                        Text("Темная").tag("dark")
                    }
                    
                    Picker("Режим прокси", selection: $manager.proxyMode) {
                        ForEach(ShadowsocksManager.ProxyMode.allCases, id: \.self) { mode in
                            Text(mode.description).tag(mode)
                        }
                    }
                    
                    Toggle("Автоматическое подключение", isOn: $autoConnect)
                    Toggle("Автоматическое обновление серверов", isOn: $autoUpdate)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Сбросить настройки") {
                    theme = "system"
                    autoConnect = false
                    autoUpdate = false
                    manager.proxyMode = .manual
                    manager.log(">> Настройки сброшены")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Spacer()
                
                Button("Закрыть") { dismiss() }
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
