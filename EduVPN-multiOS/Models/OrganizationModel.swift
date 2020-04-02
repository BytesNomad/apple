//
//  OrganizationModel.swift
//  eduVPN
//

import Foundation

struct OrganizationsModel: Decodable {
    var organizations: [OrganizationModel]
}

extension OrganizationsModel {
    
    enum OrganizationsModelKeys: String, CodingKey {
        case organizations = "organization_list"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OrganizationsModelKeys.self)
        let organizations = try container.decode([OrganizationModel].self, forKey: .organizations)

        self.init(organizations: organizations)
    }
}

struct OrganizationModel: Decodable {
    
    let providerType: ProviderType = .organization
    var identifier: String
    var serverList: URL
    
    var displayNames: [String: String]?
    var displayName: String?
      
    var keywordLists: [String: String]?
    var keywordList: String?

}

enum OrganizationModelError: Error {
    case invalidServerListURL
}

extension OrganizationModel {
    
    enum OrganizationModelKeys: String, CodingKey {
        case identifier = "org_id"
        case serverList = "server_list"
        case displayName = "display_name"
        case keywordList = "keyword_list"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OrganizationModelKeys.self)
        
        let identifier = try container.decode(String.self, forKey: .identifier)
        
        let serverList = try container.decode(String.self, forKey: .serverList)
        guard let baseURLString = Config.shared.discovery?.pathOrganizationList, let baseURL = URL(string: baseURLString), let serverListURL = URL(string: serverList, relativeTo: baseURL) else {
            throw OrganizationModelError.invalidServerListURL
        }
        
        var displayName: String?
        let displayNames = try? container.decode(Dictionary<String, String>.self, forKey: .displayName)
        
        if let displayNames = displayNames {
            let preferedLocalization = Bundle.preferredLocalizations(from: Array(displayNames.keys))
            for localeIdentifier in preferedLocalization {
                if let displayNameCandidate = displayNames[localeIdentifier] {
                    displayName = displayNameCandidate
                    break
                }
            }
        } else {
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        }
        
        var keywordList: String?
        let keywordLists = try? container.decode(Dictionary<String, String>.self, forKey: .keywordList)
        
        if let keywordLists = keywordLists {
            let preferedLocalization = Bundle.preferredLocalizations(from: Array(keywordLists.keys))
            for localeIdentifier in preferedLocalization {
                if let keywordListCandidate = keywordLists[localeIdentifier] {
                    keywordList = keywordListCandidate
                    break
                }
            }
        } else {
            keywordList = try? container.decodeIfPresent(String.self, forKey: .keywordList)
        }

        self.init(identifier: identifier,
                  serverList: serverListURL,
                  displayNames: displayNames,
                  displayName: displayName,
                  keywordLists: keywordLists,
                  keywordList: keywordList)
    }
}