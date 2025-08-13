import SwiftUI

// MARK: - Главное приложение
@main
struct ShadowSocksManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ShadowsocksManager.shared)
        }
    }
}

// MARK: - Делегат приложения
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        if let window = NSApplication.shared.windows.first {
            window.title = "Менеджер Shadowsocks"
            window.setContentSize(NSSize(width: 480, height: 600))
            window.center()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
