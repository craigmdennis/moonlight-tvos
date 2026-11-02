//
//  SceneDelegate.swift
//  Moonlight TV
//
//  Apps built with the tvOS 27 SDK must start through a scene. UIKit loads
//  Main.storyboard into this scene's window (UISceneStoryboardFile in Info.plist).
//

import UIKit

@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // StreamFrameViewController reads the app delegate's window to switch the TV's display mode
        (UIApplication.shared.delegate as? AppDelegate)?.window = window
    }
}
