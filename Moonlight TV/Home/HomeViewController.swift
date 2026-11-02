//
//  HomeViewController.swift
//  Moonlight TV
//
//  Hosts the SwiftUI home screen as the storyboard's root, and pushes the
//  unchanged StreamFrameViewController through the createStreamFrame segue.
//

import SwiftUI

@objc(HomeViewController)
final class HomeViewController: UIHostingController<HomeScreen> {
    private let model: HomeModel
    private var pendingConfig: StreamConfiguration?
    private var pendingHostId: String?

    required init?(coder: NSCoder) {
        let model = HomeModel()
        self.model = model
        super.init(coder: coder, rootView: HomeScreen(model: model))
        model.startStream = { [weak self] config, hostId in
            self?.pendingConfig = config
            self?.pendingHostId = hostId
            self?.performSegue(withIdentifier: "createStreamFrame", sender: nil)
        }
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
