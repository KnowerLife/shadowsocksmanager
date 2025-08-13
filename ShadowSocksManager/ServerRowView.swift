import SwiftUI

// MARK: - Представление строки сервера
struct ServerRowView: View {
    let server: ShadowsocksServer
    let isActive: Bool
    let onSelect: () -> Void
    let onPing: () -> Void
    let onSpeedTest: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isActive ? .blue : .gray.opacity(0.5))
                    .font(.system(size: 20))
            }
            .buttonStyle(.borderless)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                    .foregroundColor(isActive ? .blue : .primary)
                    .lineLimit(1)
                
                Text("\(server.address):\(server.port)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let lastUpdate = server.lastUpdate {
                Text("Обновлено: \(lastUpdate, style: .relative) назад")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            PingIndicator(status: server.pingStatus)
            
            if let speed = server.lastSpeed {
                Text("\(String(format: "%.2f", speed)) MB/s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Скорость не тестирована")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            Button(action: onPing) {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            
            Button(action: onSpeedTest) {
                Image(systemName: "speedometer")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// MARK: - Индикатор пинга
struct PingIndicator: View {
    let status: ShadowsocksServer.PingStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 8, height: 8)
                .foregroundColor(status.color)
            Text(status.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .background(status.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
