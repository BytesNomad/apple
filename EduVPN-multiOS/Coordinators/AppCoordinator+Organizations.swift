//
//  OrganizationsViewControllerDelegate.swift
//  eduVPN
//

import Foundation
import PromiseKit
import os.log

extension OrganizationsViewController: Identifiable {}

extension AppCoordinator: OrganizationsViewControllerDelegate {
    
    func organizationsViewControllerNoProfiles(_ controller: OrganizationsViewController) {
        addProfilesWhenNoneAvailable()
    }

    func organizationsViewController(_ controller: OrganizationsViewController, addProviderAnimated animated: Bool) {
//        #if os(iOS)
//        addOrganization(animated: animated)
//        #elseif os(macOS)
//        if config.apiDiscoveryEnabled ?? false {
//            addOrganization(animated: animated)
//        } else {
//            showCustomOrganizationInputViewController(for: .other, animated: animated)
//        }
//        #endif
    }
    
    func organizationsViewControllerAddPredefinedProvider(_ controller: OrganizationsViewController) {
        if let organizationUrl = config.predefinedProvider {
            _ = connect(url: organizationUrl)
        }
    }
    
    #if os(iOS)
    func organizationsViewControllerShowSettings(_ controller: OrganizationsViewController) {
        showSettings()
    }
    #endif
    
//    func didSelectOther(organizationType: OrganizationType) {
//        showCustomOrganizationInputViewController(for: organizationType, animated: true)
//    }
    
    func organizationsViewController(_ controller: OrganizationsViewController, didSelect organization: Organization) {
        os_log("Did select organization: %{public}@", log: Log.general, type: .info, "\(organization.displayName)")

//        if controller.configuredForInstancesDisplay {
//            do {
//                persistentContainer.performBackgroundTask { (context) in
//                    if let backgroundInstance = context.object(with: instance.objectID) as? Instance {
//                        let now = Date().timeIntervalSince1970
//                        backgroundInstance.lastAccessedTimeInterval = now
//                        context.saveContext()
//                    }
//                }
//                let count = try Profile.countInContext(persistentContainer.viewContext,
//                                                       predicate: NSPredicate(format: "api.instance == %@", instance))
//                
//                if count > 1 {
//                    showConnectionsTableViewController(for: instance)
//                } else if let profile = instance.apis?.first?.profiles.first {
//                    connect(profile: profile)
//                }
//            } catch {
//                showError(error)
//            }
//        } else {
//            // Move this to pull to refresh?
//            refresh(instance: instance).then { _ -> Promise<Void> in
//                #if os(iOS)
//                self.popToRootViewController()
//                #elseif os(macOS)
//                // TODO: It is unclear to me why iOS pops to root here. For macOS dismiss seems wrong.
//                // self.dismissViewController()
//                #endif
//                return .value(())
//            }.recover { error in
//                let error = error as NSError
//                self.showError(error)
//            }
//        }
    }
    
    func organizationsViewController(_ controller: OrganizationsViewController, didDelete instance: Organization) {
//        // Check current profile UUID against profile UUIDs.
//        if let configuredProfileId = UserDefaults.standard.configuredProfileId {
//            let profiles = instance.apis?.flatMap { $0.profiles } ?? []
//            if (profiles.compactMap { $0.uuid?.uuidString}.contains(configuredProfileId)) {
//                _ = tunnelProviderManagerCoordinator.deleteConfiguration()
//            }
//        }
//
//        var forced = false
//        if let totalProfileCount = try? Profile.countInContext(persistentContainer.viewContext), let instanceProfileCount = instance.apis?.reduce(0, { (partial, api) -> Int in
//            return partial + api.profiles.count
//        }) {
//            forced = totalProfileCount == instanceProfileCount
//        }
//
//        _ = Promise<Void>(resolver: { seal in
//            persistentContainer.performBackgroundTask { context in
//                if let backgroundInstance = context.object(with: instance.objectID) as? Instance {
//                    backgroundInstance.apis?.forEach {
//                        $0.certificateModel = nil
//                        $0.authState = nil
//                    }
//
//                    context.delete(backgroundInstance)
//                }
//                
//                context.saveContext()
//            }
//            
//            seal.fulfill(())
//        }).ensure {
//            self.addProfilesWhenNoneAvailable(forced: forced)
//        }
    }

    private func addProfilesWhenNoneAvailable(forced: Bool = false) {
        do {
            if try Profile.countInContext(persistentContainer.viewContext) == 0 || forced {
//                if let predefinedOrganization = config.predefinedOrganization {
//                    _ = connect(url: predefinedOrganization)
//                } else {
                    addProvider()
//                }
            }
        } catch {
            os_log("Failed to count Profile objects: %{public}@", log: Log.general, type: .error, error.localizedDescription)
        }
    }
    
    #if os(macOS)
    func organizationsViewControllerShouldClose(_ controller: OrganizationsViewController) {
        mainWindowController.pop()
    }
    
    func organizationsViewController(_ controller: OrganizationsViewController, addCustomProviderWithUrl url: URL) {
        
    }
    #endif
}
