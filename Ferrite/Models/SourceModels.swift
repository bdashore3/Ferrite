//
//  SourceModels.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/24/22.
//

import Foundation

public enum ApiCredentialResponseType: String, Codable, Hashable, Sendable {
    case json
    case text
}

public struct SourceListJson: Codable, Sendable {
    let name: String
    let author: String
    var sources: [SourceJson]
}

public struct SourceJson: Codable, Hashable, Sendable {
    let name: String
    let version: Int16
    let minVersion: String?
    let baseUrl: String?
    let fallbackUrls: [String]?
    var dynamicBaseUrl: Bool?
    var author: String?
    var listId: UUID?
    let trackers: [String]?
    let api: SourceApiJson?
    let jsonParser: SourceJsonParserJson?
    let rssParser: SourceRssParserJson?
    let htmlParser: SourceHtmlParserJson?
}

public enum SourcePreferredParser: Int16, CaseIterable, Sendable {
    // case none = 0
    case scraping = 1
    case rss = 2
    case siteApi = 3
}

public struct SourceApiJson: Codable, Hashable, Sendable {
    let apiUrl: String?
    let clientId: SourceApiCredentialJson?
    let clientSecret: SourceApiCredentialJson?
}

public struct SourceApiCredentialJson: Codable, Hashable, Sendable {
    let query: String?
    let value: String?
    let dynamic: Bool?
    let url: String?
    let responseType: ApiCredentialResponseType?
    let expiryLength: Double?
}

public struct SourceJsonParserJson: Codable, Hashable, Sendable {
    let searchUrl: String
    let results: String?
    let subResults: String?
    let magnetHash: SouceComplexQueryJson?
    let magnetLink: SouceComplexQueryJson?
    let title: SouceComplexQueryJson?
    let size: SouceComplexQueryJson?
    let sl: SourceSLJson?
}

public struct SourceRssParserJson: Codable, Hashable, Sendable {
    let rssUrl: String?
    let searchUrl: String
    let items: String
    let magnetHash: SouceComplexQueryJson?
    let magnetLink: SouceComplexQueryJson?
    let title: SouceComplexQueryJson?
    let size: SouceComplexQueryJson?
    let sl: SourceSLJson?
}

public struct SourceHtmlParserJson: Codable, Hashable, Sendable {
    let searchUrl: String
    let rows: String
    let magnet: SourceMagnetJson
    let title: SouceComplexQueryJson?
    let size: SouceComplexQueryJson?
    let sl: SourceSLJson?
}

public struct SouceComplexQueryJson: Codable, Hashable, Sendable {
    let query: String
    let discriminator: String?
    let attribute: String?
    let regex: String?
}

public struct SourceMagnetJson: Codable, Hashable, Sendable {
    let query: String
    let attribute: String
    let regex: String?
    let externalLinkQuery: String?
}

public struct SourceSLJson: Codable, Hashable, Sendable {
    let seeders: String?
    let leechers: String?
    let combined: String?
    let attribute: String?
    let discriminator: String?
    let seederRegex: String?
    let leecherRegex: String?
}
