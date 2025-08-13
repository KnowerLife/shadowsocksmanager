import SwiftUI

// MARK: - Представление второстепенных кнопок
struct SecondaryButtonsView: View {
    let onConfig: () -> Void
    let onLogs: () -> Void
    let onPrefs: () -> Void
    let onServers: () -> Void
    let onAbout: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            SecondaryButton(
                title: "Конфигурация",
                icon: "gearshape",
                action: onConfig
            )
            
            SecondaryButton(
                title: "Логи",
                icon: "doc.text",
                action: onLogs
            )
            
            SecondaryButton(
                title: "Настройки",
                icon: "slider.horizontal.3",
                action: onPrefs
            )
            
            SecondaryButton(
                title: "Серверы",
                icon: "server.rack",
                action: onServers
            )
            
            SecondaryButton(
                title: "О программе",
                icon: "info.circle",
                action: onAbout
            )
        }
    }
}

// MARK: - Второстепенная кнопка
struct SecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
