// Entry point. Explicit UIApplicationMain (top-level code is only legal in
// main.swift) -- unambiguous across Swift and Xcode versions.
import UIKit

UIApplicationMain(
    CommandLine.argc,
    CommandLine.unsafeArgv,
    nil,
    NSStringFromClass(AppDelegate.self)
)
