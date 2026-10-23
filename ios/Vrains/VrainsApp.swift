import SwiftUI

@main
struct VrainsApp: App {
    @UIApplicationDelegateAdaptor(JHSMatchAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
