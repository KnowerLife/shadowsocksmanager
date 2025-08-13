import Foundation

// MARK: - Ошибки Keychain
enum KeychainError: Error {
    case duplicateItem
    case itemNotFound
    case invalidItemFormat
    case unexpectedStatus(OSStatus)
    
    var localizedDescription: String {
        switch self {
        case .duplicateItem: return "Элемент уже существует в Keychain."
        case .itemNotFound: return "Элемент не найден в Keychain."
        case .invalidItemFormat: return "Недействительный формат данных в Keychain."
        case .unexpectedStatus(let status): return "Неожиданная ошибка Keychain: код \(status)."
        }
    }
}
