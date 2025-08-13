import SwiftUI

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
