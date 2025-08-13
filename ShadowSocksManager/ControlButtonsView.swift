import SwiftUI

// MARK: - Представление управляющих кнопок
struct ControlButtonsView: View {
    let isRunning: Bool
    let installationState: ShadowsocksManager.InstallationState
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onInstall: () -> Void
    let onPing: () -> Void
    let onSpeedTest: () -> Void
    let onAutoSelect: () -> Void
    let onTestAll: () -> Void
    let isTestingAll: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActionButton(
                    title: isRunning ? "Отключить" : "Подключить",
                    icon: isRunning ? "stop.circle" : "play.circle",
                    color: isRunning ? .red : .green,
                    action: isRunning ? onStop : onStart,
                    isDisabled: !installationState.isInstalled
                )
                
                ActionButton(
                    title: "Перезапуск",
                    icon: "arrow.clockwise.circle",
                    color: .orange,
                    action: onRestart,
                    isDisabled: !isRunning
                )
            }
            
            HStack(spacing: 12) {
                ActionButton(
                    title: "Пинг",
                    icon: "wave.3.right",
                    color: .blue,
                    action: onPing,
                    isDisabled: isTestingAll
                )
                
                ActionButton(
                    title: "Тест скорости",
                    icon: "speedometer",
                    color: .purple,
                    action: onSpeedTest,
                    isDisabled: isTestingAll
                )
                
                ActionButton(
                    title: "Автовыбор",
                    icon: "star.circle",
                    color: .yellow,
                    action: onAutoSelect,
                    isDisabled: isTestingAll
                )
                
                ActionButton(
                    title: "Тест всех",
                    icon: "list.bullet",
                    color: .indigo,
                    action: onTestAll,
                    isDisabled: isTestingAll
                )
            }
            
            if !installationState.isInstalled {
                ActionButton(
                    title: "Установить Shadowsocks",
                    icon: "gearshape",
                    color: .blue,
                    action: onInstall,
                    isDisabled: false
                )
            }
        }
    }
}

// MARK: - Кнопка действия
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    let isDisabled: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .tint(color)
        .disabled(isDisabled)
    }
}
