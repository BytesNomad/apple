//
//  AppCoordinator.swift
//  EduVPN
//
//  Created by Jeroen Leenarts on 08-08-17.
//  Copyright © 2017 SURFNet. All rights reserved.
//

import UIKit
import UserNotifications

import Moya
import Disk
import PromiseKit

import CoreData
import BNRCoreDataStack

enum AppCoordinatorError: Swift.Error {
    case openVpnSchemeNotAvailable
}

class AppCoordinator: RootViewCoordinator {

    let persistentContainer = NSPersistentContainer(name: "EduVPN")
    let storyboard = UIStoryboard(name: "Main", bundle: nil)

    // MARK: - Properties

    let accessTokenPlugin =  CredentialStorePlugin()

    private var dynamicApiProviders = Set<DynamicApiProvider>()

    private var currentDocumentInteractionController: UIDocumentInteractionController?

    private var authorizingDynamicApiProvider: DynamicApiProvider?

    var childCoordinators: [Coordinator] = []

    var rootViewController: UIViewController {
        return self.connectionsTableViewController
    }

    var connectionsTableViewController: ConnectionsTableViewController!

    /// Window to manage
    let window: UIWindow

    let navigationController: UINavigationController = {
        let navController = UINavigationController()
        return navController
    }()

    // MARK: - Init
    public init(window: UIWindow) {
        self.window = window

        self.window.rootViewController = self.navigationController
        self.window.makeKeyAndVisible()
    }

    // MARK: - Functions

    /// Starts the coordinator
    public func start() {
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.loadPersistentStores { [weak self] (persistentStoreDescription, error) in
            if let error = error {
                print("Unable to Load Persistent Store")
                print("\(error), \(error.localizedDescription)")

            } else {
                DispatchQueue.main.async {
                    //start
                    if let connectionsTableViewController = self?.storyboard.instantiateViewController(type: ConnectionsTableViewController.self) {
                        self?.connectionsTableViewController = connectionsTableViewController
                        self?.connectionsTableViewController.viewContext = self?.persistentContainer.viewContext
                        self?.connectionsTableViewController.delegate = self
                        self?.navigationController.viewControllers = [connectionsTableViewController]
                        do {
                            if let context = self?.persistentContainer.viewContext, try Profile.countInContext(context) == 0 {
                                self?.showProfilesViewController()
                            }
                        } catch {
                            self?.showError(error)
                        }
                    }

                    self?.detectPresenceOpenVPN().catch { (_) in
                        self?.showNoOpenVPNAlert()
                    }
                }
            }
        }
    }

    public func showError(_ error: Error) {
        let alert = UIAlertController(title: NSLocalizedString("Error", comment: "Error alert title"), message: error.localizedDescription, preferredStyle: .alert)
        let dismissAction = UIAlertAction(title: "OK", style: .default)
        alert.addAction(dismissAction)
        self.navigationController.present(alert, animated: true)
    }

    func detectPresenceOpenVPN() -> Promise<Void> {
        return Promise(resolvers: { fulfill, reject in
            guard let url = URL(string: "openvpn://") else {
                reject(AppCoordinatorError.openVpnSchemeNotAvailable)
                return
            }
            if UIApplication.shared.canOpenURL(url) {
                fulfill(())
            } else {
                reject(AppCoordinatorError.openVpnSchemeNotAvailable)
            }
        })
    }

    func fetchKeyPair(with dynamicApiProvider: DynamicApiProvider, for displayName: String) -> Promise<Void> {
        return dynamicApiProvider.request(apiService: ApiService.createKeypair(displayName: displayName)).then { response -> Promise<CertificateModel> in
            return response.mapResponse()
            }.then(execute: { (model) -> Void in
                print(model)
                self.scheduleCertificateExpirationNotification(certificate: model)
            })

//        return Promise(resolvers: { fulfill, reject in
//            //Fetch current keypair
//            // If non-existent or expired, fetch fresh
//            // Otherwise return keypair
//        })
    }

    func showNoOpenVPNAlert() {
        let alertController = UIAlertController(title: NSLocalizedString("OpenVPN Connect app", comment: "No OpenVPN available title"), message: NSLocalizedString("The OpenVPN Connect app is required to use EduVPN.", comment: "No OpenVPN available message"), preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "No OpenVPN available ok button"), style: .default) { _ in
        })
        self.navigationController.present(alertController, animated: true, completion: nil)
    }

    func showSettingsTableViewController() {
        let settingsTableViewController = storyboard.instantiateViewController(type: SettingsTableViewController.self)
        self.navigationController.pushViewController(settingsTableViewController, animated: true)
        settingsTableViewController.delegate = self
    }

    fileprivate func scheduleCertificateExpirationNotification(certificate: CertificateModel) {
        UNUserNotificationCenter.current().getNotificationSettings { (settings) in
            guard settings.authorizationStatus == UNAuthorizationStatus.authorized else {
                print("Not Authorised")
                return
            }

            //        //TODO do this more fine grained
            //        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

            guard let expirationDate = certificate.x509Certificate?.notAfter else { return }

            let content = UNMutableNotificationContent()
            content.title = NSString.localizedUserNotificationString(forKey: "VPN certificate is expiring!", arguments: nil)
            content.body = NSString.localizedUserNotificationString(forKey: "Rise and shine! It's morning time!",
                                                                    arguments: nil)

            #if DEBUG
                guard let expirationWarningDate = NSCalendar.current.date(byAdding: .second, value: 10, to: Date()) else { return }
                let expirationWarningDateComponents = NSCalendar.current.dateComponents(in: NSTimeZone.default, from: expirationWarningDate)
            #else
                guard let expirationWarningDate = NSCalendar.current.date(byAdding: .day, value: -7, to: expirationDate) else { return }
                var expirationWarningDateComponents = NSCalendar.current.dateComponents(in: NSTimeZone.default, from: expirationWarningDate)

                // Configure the trigger for 10am.
                expirationWarningDateComponents.hour = 10
                expirationWarningDateComponents.minute = 0
                expirationWarningDateComponents.second = 0
            #endif

            let trigger = UNCalendarNotificationTrigger(dateMatching: expirationWarningDateComponents, repeats: false)

            // Create the request object.
            let request = UNNotificationRequest(identifier: "MorningAlarm", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { (error) in
                if let error = error {
                    print("Error occured when scheduling a cert expiration reminder \(error)")
                }
            }
        }
    }

    fileprivate func refresh(instance: Instance) -> Promise<Void> {
        //        let provider = DynamicInstanceProvider(baseURL: instance.baseUri)
        let provider = MoyaProvider<DynamicInstanceService>()

        return provider.request(target: DynamicInstanceService(baseURL: URL(string: instance.baseUri!)!)).then { response -> Promise<InstanceInfoModel> in
            return response.mapResponse()
            }.then { instanceInfoModel -> Void in
                return Promise<Api>(resolvers: { fulfill, reject in
                    self.persistentContainer.performBackgroundTask({ (context) in
                        let api: Api
                        let instance = context.object(with: instance.objectID) as? Instance
                        if let instance = instance {
                            api = try! Api.findFirstInContext(context, predicate: NSPredicate(format: "instance.baseUri == %@ AND apiBaseUri == %@", instance.baseUri!, instanceInfoModel.apiBaseUrl.absoluteString)) ?? Api(context: context)//swiftlint:disable:this force_try
                        } else {
                            api = Api(context: context)
                        }
                        api.instance = instance
                        api.apiBaseUri = instanceInfoModel.apiBaseUrl.absoluteString
                        api.authorizationEndpoint = instanceInfoModel.authorizationEndpoint.absoluteString
                        api.tokenEndpoint = instanceInfoModel.tokenEndpoint.absoluteString
                        do {
                            try context.save()
                        } catch {
                            reject(error)
                        }

                        fulfill(api)
                    })
                }).then(execute: { (api) -> Promise<Void> in
                    let api = self.persistentContainer.viewContext.object(with: api.objectID) as! Api //swiftlint:disable:this force_cast
                    let authorizingDynamicApiProvider = DynamicApiProvider(api: api)
                    self.authorizingDynamicApiProvider = authorizingDynamicApiProvider
                    return authorizingDynamicApiProvider.authorize(presentingViewController: self.navigationController).then {_ in
                        self.navigationController.popToRootViewController(animated: true)
                    }.then { _ in
                        return self.refreshProfiles(for: authorizingDynamicApiProvider)
                }
            })
        }
    }

    fileprivate func showSettings() {
        let settingsTableViewController = storyboard.instantiateViewController(type: SettingsTableViewController.self)
        settingsTableViewController.delegate = self
        self.navigationController.pushViewController(settingsTableViewController, animated: true)
    }

    fileprivate func showProfilesViewController() {
        let profilesViewController = storyboard.instantiateViewController(type: ProfilesViewController.self)
        profilesViewController.delegate = self
        do {
            try profilesViewController.navigationItem.hidesBackButton = Profile.countInContext(persistentContainer.viewContext) == 0
            self.navigationController.pushViewController(profilesViewController, animated: true)
        } catch {
            self.showError(error)
        }
    }

    fileprivate func showCustomProviderInPutViewController(for providerType: ProviderType) {
        let customProviderInputViewController = storyboard.instantiateViewController(type: CustomProviderInPutViewController.self)
        customProviderInputViewController.delegate = self
        self.navigationController.pushViewController(customProviderInputViewController, animated: true)
    }

    fileprivate func showChooseProviderTableViewController(for providerType: ProviderType) {
        let chooseProviderTableViewController = storyboard.instantiateViewController(type: ChooseProviderTableViewController.self)
        chooseProviderTableViewController.providerType = providerType
        chooseProviderTableViewController.viewContext = persistentContainer.viewContext
        chooseProviderTableViewController.delegate = self
        self.navigationController.pushViewController(chooseProviderTableViewController, animated: true)

        chooseProviderTableViewController.providerType = providerType

        let target: StaticService
        switch providerType {
        case .instituteAccess:
            target = StaticService.instituteAccess
        case .secureInternet:
            target = StaticService.secureInternet
        case .unknown, .other:
            return
        }

        let provider = MoyaProvider<StaticService>()
        _ = provider.request(target: target).then { response -> Promise<InstancesModel> in

            return response.mapResponse()
        }.then { (instances) -> Promise<Void> in
            //TODO verify response with libsodium
            var instances = instances
            instances.providerType = providerType
            instances.instances = instances.instances.map({ (instanceModel) -> InstanceModel in
                var instanceModel = instanceModel
                instanceModel.providerType = providerType
                return instanceModel
            })

            let instanceIdentifiers = instances.instances.map { $0.baseUri.absoluteString }

            return Promise(resolvers: { (fulfill, reject) in
                self.persistentContainer.performBackgroundTask({ (context) in
                    let instanceGroupIdentifier = "\(target.baseURL.absoluteString)\(target.path)"
                    let group = try! InstanceGroup.findFirstInContext(context, predicate: NSPredicate(format: "providerType == %@", providerType.rawValue)) ?? InstanceGroup(context: context)//swiftlint:disable:this force_try

                    group.discoveryIdentifier = instanceGroupIdentifier
                    group.providerType = providerType.rawValue

                    func update(instance: Instance, with model: InstanceModel) {
                        instance.baseUri = model.baseUri.absoluteString
                        instance.providerType = providerType.rawValue
                        instance.displayNames?.forEach { context.delete($0) }
                        instance.logos?.forEach { context.delete($0) }

                        if let logoUrls = model.logoUrls {
                            instance.logos = Set(logoUrls.flatMap({ (logoData) -> Logo? in
                                let newLogo = Logo(context: context)
                                newLogo.locale = logoData.key
                                newLogo.logo = logoData.value.absoluteString
                                newLogo.instance = instance
                                return newLogo
                            }))
                        } else if let logoUrl = model.logoUrl {
                            let newLogo = Logo(context: context)
                            newLogo.logo = logoUrl.absoluteString
                            instance.logos = Set([newLogo])
                            newLogo.instance = instance
                        } else {
                            instance.logos = []
                        }

                        if let displayNames = model.displayNames {
                            instance.displayNames = Set(displayNames.flatMap({ (displayData) -> DisplayName? in
                                let displayName = DisplayName(context: context)
                                displayName.locale = displayData.key
                                displayName.displayName = displayData.value
                                displayName.instance = instance
                                return displayName
                            }))
                        } else if let displayNameString = model.displayName {
                            let displayName = DisplayName(context: context)
                            displayName.displayName = displayNameString
                            displayName.instance = instance
                        } else {
                            instance.displayNames = []
                        }
                    }

                    let updatedInstances = group.instances.filter {
                        guard let baseUri = $0.baseUri else { return false }
                        return instanceIdentifiers.contains(baseUri)
                    }

                    updatedInstances.forEach {
                        if let baseUri = $0.baseUri {
                            if let updatedModel = instances.instances.first(where: { (model) -> Bool in
                                return model.baseUri.absoluteString == baseUri
                            }) {
                                update(instance: $0, with: updatedModel)
                            }
                        }
                    }

                    let updatedInstanceIdentifiers = updatedInstances.flatMap { $0.baseUri}

                    let deletedInstances = group.instances.subtracting(updatedInstances)
                    deletedInstances.forEach {
                        context.delete($0)
                    }

                    let insertedInstancesModels = instances.instances.filter {
                        return !updatedInstanceIdentifiers.contains($0.baseUri.absoluteString)
                    }
                    insertedInstancesModels.forEach { (instanceModel: InstanceModel) in
                        let newInstance = Instance(context: context)
                        group.addToInstances(newInstance)
                        newInstance.group = group
                        update(instance: newInstance, with: instanceModel)
                    }

                    context.saveContextToStore({ (result) in
                        switch result {
                        case .success:
                            fulfill(())
                        case .failure(let error):
                            reject(error)
                        }
                    })

                })
            })
        }
    }

    func fetchAndTransferProfileToConnectApp(for profile: Profile) {
        print(profile)
        guard let api = profile.api else {
            precondition(false, "This shold never happen")
            return
        }

        let dynamicApiProvider = DynamicApiProvider(api: api)
        _ = detectPresenceOpenVPN()
            .then { _ -> Promise<Response> in
                return dynamicApiProvider.request(apiService: .createConfig(displayName: "iOS Created Profile", profileId: profile.profileId!))
            }.then { response -> Void in
                // TODO validate response
                let filename = "\(profile.displayNames?.localizedValue ?? "")-\(api.instance?.displayNames?.localizedValue ?? "") \(String(describing: profile.profileId)).ovpn"
                try Disk.save(response.data, to: .documents, as: filename)
                let url = try Disk.getURL(for: filename, in: .documents)

                let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let currentViewController = self.navigationController.visibleViewController {
                    currentViewController.present(activity, animated: true, completion: {
                        print("Done")
                    })
                }
                return ()
            }.catch { (error) in
                switch error {
                case AppCoordinatorError.openVpnSchemeNotAvailable:
                    self.showNoOpenVPNAlert()
                default:
                    print("Errror: \(error)")
                }
            }
    }

    func showConnectionViewController(for profile: InstanceProfileModel, on instance: InstanceModel) {
        let connectionViewController = storyboard.instantiateViewController(type: VPNConnectionViewController.self)
        connectionViewController.delegate = self
        self.navigationController.pushViewController(connectionViewController, animated: true)
    }

    func resumeAuthorizationFlow(url: URL) -> Bool {
        if let authorizingDynamicApiProvider = authorizingDynamicApiProvider {
            if authorizingDynamicApiProvider.currentAuthorizationFlow?.resumeAuthorizationFlow(with: url) == true {
                self.dynamicApiProviders.insert(authorizingDynamicApiProvider)
                authorizingDynamicApiProvider.currentAuthorizationFlow = nil
                return true
            }
        }

        return false
    }

    @discardableResult private func refreshProfiles() -> Promise<Void> {
        // TODO Should this be based on instance info objects?
        let promises = dynamicApiProviders.map({self.refreshProfiles(for: $0)})
        return when(fulfilled: promises)
    }

    @discardableResult private func refreshProfiles(for dynamicApiProvider: DynamicApiProvider) -> Promise<Void> {
        return dynamicApiProvider.request(apiService: .profileList).then { response -> Promise<ProfilesModel> in
            return response.mapResponse()
        }.then { profiles -> Promise<Void> in
            self.persistentContainer.performBackgroundTask({ (context) in
                let api = context.object(with: dynamicApiProvider.api.objectID) as? Api
                api?.profiles.forEach({ (profile) in
                    context.delete(profile)
                })

                profiles.profiles.forEach {
                    let profile = Profile(context: context)
                    profile.api = api
                    profile.profileId = $0.profileId
                    profile.twoFactor = $0.twoFactor
                    if let displayNames = $0.displayNames {
                        profile.displayNames = Set(displayNames.flatMap({ (displayData) -> DisplayName? in
                            let displayName = DisplayName(context: context)
                            displayName.locale = displayData.key
                            displayName.displayName = displayData.value
                            displayName.profile = profile
                            return displayName
                        }))
                    }
                }
                context.saveContext()
            })
            return Promise(value: ())
        }
    }
}

extension AppCoordinator: SettingsTableViewControllerDelegate {

}

extension AppCoordinator: ConnectionsTableViewControllerDelegate {
    func settings(connectionsTableViewController: ConnectionsTableViewController) {
        showSettings()
    }

    func addProvider(connectionsTableViewController: ConnectionsTableViewController) {
        showProfilesViewController()
    }

    func connect(profile: Profile) {
// TODO implement OpenVPN3 client lib        showConnectionViewController(for:profile)
        fetchAndTransferProfileToConnectApp(for: profile)
    }

    func delete(profile: Profile) {
        persistentContainer.performBackgroundTask { (context) in
            context.delete(profile)
        }
    }
}

extension AppCoordinator: ProfilesViewControllerDelegate {
    func profilesViewControllerDidSelectProviderType(profilesViewController: ProfilesViewController, providerType: ProviderType) {
        switch providerType {
        case .instituteAccess, .secureInternet:
            showChooseProviderTableViewController(for: providerType)
        case .other:
            showCustomProviderInPutViewController(for: providerType)
        case .unknown:
            print("Unknown provider type chosen")
        }
    }
}

extension AppCoordinator: ChooseProviderTableViewControllerDelegate {
    func didSelectOther(providerType: ProviderType) {
        showCustomProviderInPutViewController(for: providerType)
    }

    func didSelect(instance: Instance, chooseProviderTableViewController: ChooseProviderTableViewController) {
        self.refresh(instance: instance).catch { (error) in
            self.showError(error)
        }
    }
}

extension AppCoordinator: CustomProviderInPutViewControllerDelegate {
    private func createLocalUrl(forImageNamed name: String) throws -> URL {
        let filename = "\(name).png"
        if Disk.exists(filename, in: .applicationSupport) {
            return try Disk.getURL(for: filename, in: .applicationSupport)
        }

        let image = UIImage(named: name)!
        try Disk.save(image, to: .applicationSupport, as: filename)

        return try Disk.getURL(for: filename, in: .applicationSupport)
    }

    func connect(url: URL) -> Promise<Void> {
        return Promise<Instance>(resolvers: { fulfill, reject in
            persistentContainer.performBackgroundTask { (context) in
                let group = try! InstanceGroup.findFirstInContext(context, predicate: NSPredicate(format: "providerType == %@", ProviderType.other.rawValue)) ?? InstanceGroup(context: context)//swiftlint:disable:this force_try

                group.providerType = ProviderType.other.rawValue

                let instance = Instance(context: context)
                instance.providerType = ProviderType.other.rawValue
                instance.baseUri = url.absoluteString
                instance.group = group

                do {
                    try context.save()
                } catch {
                    reject(error)
                }
                fulfill(instance)
            }
        }).then { (instance) -> Promise<Void> in
            let instance = self.persistentContainer.viewContext.object(with: instance.objectID) as! Instance //swiftlint:disable:this force_cast
            return self.refresh(instance: instance)
        }
    }
}

extension AppCoordinator: VPNConnectionViewControllerDelegate {

}
