import SwiftUI
import Charts

// MARK: - Представление статуса
struct StatusView: View {
    let isRunning: Bool
    let installationState: ShadowsocksManager.InstallationState
    let connectionStatus: ShadowsocksManager.ConnectionStatus
    let currentServer: ShadowsocksServer?
    let uploadSpeed: Double
    let downloadSpeed: Double
    let totalTraffic: Int
    let speedData: [ShadowsocksManager.SpeedData]
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(connectionStatus.rawValue)
                    .font(.title2.bold())
                    .foregroundColor(statusColor)
                
                if let server = currentServer {
                    Text("\(server.name) (\(server.address):\(server.port))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Сервер не выбран")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if case .installing(let progress) = installationState {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            } else if case .error(let message) = installationState {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Скорость загрузки: \(String(format: "%.2f", downloadSpeed)) MB/s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Скорость отдачи: \(String(format: "%.2f", uploadSpeed)) MB/s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Общий трафик: \(totalTraffic) MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                if !speedData.isEmpty {
                    Chart {
                        ForEach(speedData) { data in
                            LineMark(
                                x: .value("Time", data.date),
                                y: .value("Download", data.download)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            
                            LineMark(
                                x: .value("Time", data.date),
                                y: .value("Upload", data.upload)
                            )
                            .foregroundStyle(.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        }
                    }
                    .chartYScale(domain: 0...10)
                    .chartXAxis(.hidden)
                    .chartLegend(.visible)
                    .frame(width: 200, height: 80)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var statusColor: Color {
        switch connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
