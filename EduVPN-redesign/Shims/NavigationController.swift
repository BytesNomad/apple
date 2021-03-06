//
//  NavigationController.swift
//  EduVPN
//

protocol NavigationControllerAddButtonDelegate: class {
    func addButtonClicked(inNavigationController controller: NavigationController)
}

#if os(macOS)
import AppKit

class NavigationController: NSViewController {

    var environment: Environment?

    var isUserAllowedToGoBack: Bool = true {
        didSet {
            updateToolbarLeftButton()
        }
    }

    var isToolbarLeftButtonShowsAddServerUI: Bool { !canGoBack }

    weak var addButtonDelegate: NavigationControllerAddButtonDelegate?

    private var canGoBack: Bool { children.count > 1 }

    private var onCancelled: (() -> Void)?

    @IBOutlet weak var toolbarLeftButton: NSButton!
    @IBOutlet weak var authorizingMessageBox: NSBox!

    private var presentedPreferencesVC: PreferencesViewController?

    @IBAction func toolbarLeftButtonClicked(_ sender: Any) {
        if canGoBack {
            popViewController(animated: true)
        } else {
            addButtonDelegate?.addButtonClicked(inNavigationController: self)
        }
    }

    @IBAction func toolbarPreferencesClicked(_ sender: Any) {
        presentPreferences()
    }

    @IBAction func toolbarHelpClicked(_ sender: Any) {
        guard let url = Config.shared.supportURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @IBAction func cancelAuthorizationButtonClicked(_ sender: Any) {
        onCancelled?()
        hideAuthorizingMessage()
    }

    private func updateToolbarLeftButton() {
        let image = canGoBack ?
            NSImage(named: NSImage.goBackTemplateName)! : // swiftlint:disable:this force_unwrapping
            NSImage(named: NSImage.addTemplateName)! // swiftlint:disable:this force_unwrapping
        toolbarLeftButton.image = image
        toolbarLeftButton.isHidden = !authorizingMessageBox.isHidden ||
            (canGoBack && !isUserAllowedToGoBack)
    }
}

extension NavigationController: Navigating {

    func pushViewController(_ viewController: ViewController, animated: Bool) {
        guard let lastVC = children.last else { return }

        addChild(viewController)
        toolbarLeftButton.isEnabled = false
        transition(from: lastVC, to: viewController,
                   options: animated ? .slideForward : []) { [weak self] in
            guard let self = self else { return }
            self.updateToolbarLeftButton()
            self.toolbarLeftButton.isEnabled = true
        }
    }

    @discardableResult
    func popViewController(animated: Bool) -> ViewController? {
        precondition(children.count > 1)
        let lastVC = children[children.count - 1]
        let lastButOneVC = children[children.count - 2]

        toolbarLeftButton.isEnabled = false
        transition(from: lastVC, to: lastButOneVC,
                   options: animated ? .slideBackward : []) { [weak self] in
            guard let self = self else { return }
            lastVC.removeFromParent()
            self.isUserAllowedToGoBack = true
            self.updateToolbarLeftButton()
            self.toolbarLeftButton.isEnabled = true
        }

        return lastVC
    }

    func popToRoot() {
        while children.count > 1 {
            popViewController(animated: false)
        }
    }
}

extension NavigationController {
    func presentPreferences() {
        guard let environment = environment else { return }
        let preferencesVC = environment.instantiatePreferencesViewController()
        presentedPreferencesVC = preferencesVC
        presentAsSheet(preferencesVC)
    }
}

extension NavigationController {
    func showAuthorizingMessage(onCancelled: (() -> Void)?) {
        self.authorizingMessageBox.isHidden = false
        self.onCancelled = onCancelled
        self.updateToolbarLeftButton()
    }

    func hideAuthorizingMessage() {
        self.authorizingMessageBox.isHidden = true
        self.onCancelled = nil
        self.updateToolbarLeftButton()
    }
}

extension NavigationController {
    func showAlert(for error: Error) {
        let alert = NSAlert()
        alert.messageText = error.alertSummary
        alert.informativeText = error.alertDetail ?? ""
        NSApp.activate(ignoringOtherApps: true)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

#elseif os(iOS)

import UIKit
import SafariServices

class NavigationController: UINavigationController {
    // Override push and pop to set navigation items

    var environment: Environment?
    weak var addButtonDelegate: NavigationControllerAddButtonDelegate?

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    var isUserAllowedToGoBack: Bool = true {
        didSet {
            topViewController?.navigationItem.hidesBackButton = !isUserAllowedToGoBack
        }
    }

    private lazy var topBarLogoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "TopBarLogo")
        imageView.contentMode = .center
        return imageView
    }()

    override func viewDidLoad() {
        updateTopNavigationItem()
    }

    override func pushViewController(_ viewController: ViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)
        updateTopNavigationItem()
    }

    @discardableResult
    override func popViewController(animated: Bool) -> ViewController? {
        let poppedVC = super.popViewController(animated: animated)
        updateTopNavigationItem()
        return poppedVC
    }

    func popToRoot() {
        popToRootViewController(animated: false)
    }

    private func updateTopNavigationItem() {
        guard let navigationItem = topViewController?.navigationItem else { return }

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(named: "QuestionButton"),
                style: .plain, target: self,
                action: #selector(helpButtonTapped(_:))),
            UIBarButtonItem(
                image: UIImage(named: "SettingsButton"),
                style: .plain, target: self,
                action: #selector(settingsButtonTapped(_:)))
        ]

        if viewControllers.count == 1 {
            navigationItem.title = Config.shared.appName
            navigationItem.titleView =
                (traitCollection.verticalSizeClass == .regular) ? topBarLogoImageView : nil
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .add, target: self,
                action: #selector(addButtonTapped(_:)))
        } else {
            navigationItem.titleView = nil
            navigationItem.leftBarButtonItem = nil
            navigationItem.hidesBackButton = !isUserAllowedToGoBack
        }
    }

    @objc private func addButtonTapped(_ sender: Any) {
        addButtonDelegate?.addButtonClicked(inNavigationController: self)
    }

    @objc private func settingsButtonTapped(_ sender: Any) {
        guard let environment = environment else { return }
        let settingsVC = environment.instantiateSettingsViewController()
        let navigationVC = UINavigationController(rootViewController: settingsVC)
        navigationVC.modalPresentationStyle = .fullScreen
        present(navigationVC, animated: true, completion: nil)
    }

    @objc private func helpButtonTapped(_ sender: Any) {
        if let supportURL = Config.shared.supportURL {
            let safariVC = SFSafariViewController(url: supportURL)
            present(safariVC, animated: true, completion: nil)
        }
    }

    override func traitCollectionDidChange(_ prevTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(prevTraitCollection)
        if traitCollection.verticalSizeClass != prevTraitCollection?.verticalSizeClass {
            updateTopNavigationItem()
        }
    }
}

extension NavigationController {
    func showAlert(for error: Error) {
        let title = error.alertSummary
        var message = error.alertDetail
        let okAction = UIAlertAction(title: "OK", style: .default)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(okAction)
        present(alert, animated: true, completion: nil)
    }
}
#endif
