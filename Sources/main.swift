// Entry point. Uses the explicit UIApplicationMain call (rather than
// @UIApplicationMain / @main) because it is unambiguous across Swift and
// Xcode versions, and top-level code is only legal in main.swift.
import UIKit

UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(AppDelegate.self)
)
