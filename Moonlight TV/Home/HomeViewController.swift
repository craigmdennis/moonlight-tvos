//
//  HomeViewController.swift
//  Moonlight TV
//
//  The storyboard's root. It embeds the SwiftUI home screen and pushes the
//  unchanged StreamFrameViewController through the createStreamFrame segue.
//
//  The storyboard finds this class by name through the Objective-C runtime,
//  which can't look up subclasses of generic classes such as UIHostingController.
//  So this is a plain view controller that holds the hosting controller as a child.
//

import SwiftUI

@objc(HomeViewController)
final class HomeViewController: UIViewController {
    private let model = HomeModel()
    private var hosting: UIHostingController<HomeScreen>!
    private var pendingConfig: StreamConfiguration?
    private var pendingHostId: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        hosting = UIHostingController(rootView: HomeScreen(model: model))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        model.startStream = { [weak self] config, hostId in
            self?.pendingConfig = config
            self?.pendingHostId = hostId
            self?.performSegue(withIdentifier: "createStreamFrame", sender: nil)
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [hosting]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        model.appeared()
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resignedActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        model.disappeared()
    }

    @objc private func becameActive() {
        model.appeared()
    }

    @objc private func resignedActive() {
        model.disappeared()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let stream = segue.destination as? StreamFrameConfigurable, let hostId = pendingHostId else { return }
        stream.streamConfig = pendingConfig
        // Failures come back to the home screen instead of showing an alert
        stream.failureHandler = { [weak model] kind, message in
            model?.streamFailed(hostId, kind: kind ?? "", message: message)
        }
    }
}
