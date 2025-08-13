import SwiftUI

// MARK: - Импорт подписки
struct SubscriptionImportView: View {
    @EnvironmentObject private var manager: ShadowsocksManager
    @Environment(\.dismiss) private var dismiss
    @Binding var subscriptionURL: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Импорт подписки")
                .font(.title3.bold())
            
            TextField("URL подписки", text: $subscriptionURL)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Импортировать") {
                    Task { await manager.importFromSubscription(urlString: subscriptionURL) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscriptionURL.isEmpty || !URL(string: subscriptionURL)!.isValidURL)
                
                Button("Отмена") { dismiss() }
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

extension URL {
    var isValidURL: Bool {
        let urlRegEx = "^(https?://)?([\\w-]+\\.)+[\\w-]+(/[\\w-./?%&=]*)?$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", urlRegEx)
        return predicate.evaluate(with: absoluteString)
    }
}
