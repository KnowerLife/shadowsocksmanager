import SwiftUI

// MARK: - Представление "О программе"
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Менеджер Shadowsocks")
                .font(.title2.bold())
            
            Text("Версия 1.1")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("© 2025 KNOWER LIFE")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Простое приложение для управления Shadowsocks-серверами с поддержкой импорта/экспорта, тестирования скорости и автоматического выбора лучшего сервера.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Закрыть") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}
