import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Visual novels expect the screen to stay on.
        application.isIdleTimerDisabled = true

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = .black
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    // Landscape only: the game is 1350x900 (3:2), so a landscape window uses
    // ~69% of the screen width instead of ~31% of the height in portrait.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}
