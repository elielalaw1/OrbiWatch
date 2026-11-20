import SwiftUI
import WatchConnectivity
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
 @Published var status = "Checking Apple Watch…"
 override init() { super.init(); if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() } }
 func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { update(session) }
 func sessionDidBecomeInactive(_ session: WCSession) {}
 func sessionDidDeactivate(_ session: WCSession) { session.activate() }
 func sessionWatchStateDidChange(_ session: WCSession) { update(session) }
 func update(_ session: WCSession) { DispatchQueue.main.async { self.status = session.isPaired ? (session.isWatchAppInstalled ? "Orbi is installed on your Apple Watch." : "Open the Watch app on your iPhone and install Orbi under Available Apps.") : "No paired Apple Watch found." } }
}
@main struct OrbiPhoneApp: App {
 @StateObject var link = WatchLink()
 var body: some Scene { WindowGroup { VStack(spacing: 24) { Image(systemName: "moon.zzz.fill").font(.system(size: 64)); Text("Orbi").font(.largeTitle.bold()); Text(link.status).multilineTextAlignment(.center) }.padding(32).preferredColorScheme(.dark) } }
}
