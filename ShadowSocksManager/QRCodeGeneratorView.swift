import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Представление для генерации QR-кода
struct QRCodeGeneratorView: View {
    let server: ShadowsocksServer
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Поделиться конфигурацией")
                .font(.title3.bold())
            
            if let image = generateQRCode() {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
                
                Text(server.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                Button("Копировать конфигурацию") {
                    Task { @MainActor in
                        copyConfigurationToClipboard()
                        ShadowsocksManager.shared.log(">> Конфигурация \(server.name) скопирована")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else {
                Text("Ошибка генерации QR-кода")
                    .foregroundStyle(.red)
            }
            
            Button("Закрыть") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.secondary)
        }
        .padding(24)
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
    
    private func generateQRCode() -> NSImage? {
        var configString = "\(server.method)@\(server.address):\(server.port)"
        if !server.password.isEmpty {
            configString = "\(server.method):\(server.password)@\(server.address):\(server.port)"
        }
        guard let configData = configString.data(using: .utf8) else {
            Task { @MainActor in
                ShadowsocksManager.shared.log(">> Ошибка кодирования QR-кода")
            }
            return nil
        }
        let base64String = configData.base64EncodedString()
        let qrString = "ss://\(base64String)"
        
        guard let filter = CIFilter(name: "CIQRCodeGenerator"),
              let data = qrString.data(using: .utf8) else {
            Task { @MainActor in
                ShadowsocksManager.shared.log(">> Ошибка создания QR-кода")
            }
            return nil
        }
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage,
              let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            Task { @MainActor in
                ShadowsocksManager.shared.log(">> Ошибка генерации изображения QR-кода")
            }
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
    
    private func copyConfigurationToClipboard() {
        var configString = "\(server.method)@\(server.address):\(server.port)"
        if !server.password.isEmpty {
            configString = "\(server.method):\(server.password)@\(server.address):\(server.port)"
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(configString, forType: .string)
    }
}
