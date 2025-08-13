import SwiftUI

// MARK: - Представление логов
struct LogView: View {
    @EnvironmentObject private var manager: ShadowsocksManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Логи приложения")
                    .font(.title3.bold())
                Spacer()
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(manager.logMessages, forType: .string)
                    manager.log(">> Логи скопированы в буфер обмена")
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
            }
            
            ScrollView {
                Text(manager.logMessages)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button("Закрыть") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}
