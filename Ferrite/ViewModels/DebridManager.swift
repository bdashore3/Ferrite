//
//  DebridManager.swift
//  Ferrite
//
//  Created by Brian Dashore on 7/20/22.
//

import Foundation
import SwiftUI

@MainActor
public class DebridManager: ObservableObject {
    // Linked classes
    var toastModel: ToastViewModel?
    let realDebrid: RealDebrid = .init()
    let allDebrid: AllDebrid = .init()
    let premiumize: Premiumize = .init()

    // UI Variables
    @Published var showWebView: Bool = false
    @Published var showAuthSession: Bool = false
    @Published var showLoadingProgress: Bool = false

    // Service agnostic variables
    @Published var enabledDebrids: Set<DebridType> = [] {
        didSet {
            UserDefaults.standard.set(enabledDebrids.rawValue, forKey: "Debrid.EnabledArray")
        }
    }

    @Published var selectedDebridType: DebridType? {
        didSet {
            UserDefaults.standard.set(selectedDebridType?.rawValue ?? 0, forKey: "Debrid.PreferredService")
        }
    }

    var currentDebridTask: Task<Void, Never>?
    var downloadUrl: String = ""
    var authUrl: URL?

    // RealDebrid auth variables
    @Published var realDebridAuthProcessing: Bool = false

    // RealDebrid fetch variables
    @Published var realDebridIAValues: [RealDebrid.IA] = []

    @Published var showDeleteAlert: Bool = false

    var selectedRealDebridItem: RealDebrid.IA?
    var selectedRealDebridFile: RealDebrid.IAFile?
    var selectedRealDebridID: String?

    // AllDebrid auth variables
    @Published var allDebridAuthProcessing: Bool = false

    // AllDebrid fetch variables
    @Published var allDebridIAValues: [AllDebrid.IA] = []

    var selectedAllDebridItem: AllDebrid.IA?
    var selectedAllDebridFile: AllDebrid.IAFile?

    // Premiumize auth variables
    @Published var premiumizeAuthProcessing: Bool = false

    // Premiumize fetch variables
    @Published var premiumizeIAValues: [Premiumize.IA] = []

    var selectedPremiumizeItem: Premiumize.IA?
    var selectedPremiumizeFile: Premiumize.IAFile?

    init() {
        if let rawDebridList = UserDefaults.standard.string(forKey: "Debrid.EnabledArray"),
           let serializedDebridList = Set<DebridType>(rawValue: rawDebridList)
        {
            enabledDebrids = serializedDebridList
        }

        // If a UserDefaults integer isn't set, it's usually 0
        let rawPreferredService = UserDefaults.standard.integer(forKey: "Debrid.PreferredService")
        selectedDebridType = DebridType(rawValue: rawPreferredService)

        // If a user has one logged in service, automatically set the preferred service to that one
        if enabledDebrids.count == 1 {
            selectedDebridType = enabledDebrids.first
        }
    }

    // TODO: Remove this after v0.6.0
    // Login cleanup function that's automatically run to switch to the new login system
    public func cleanupOldLogins() async {
        let realDebridEnabled = UserDefaults.standard.bool(forKey: "RealDebrid.Enabled")
        if realDebridEnabled {
            enabledDebrids.insert(.realDebrid)
            UserDefaults.standard.set(false, forKey: "RealDebrid.Enabled")
        }

        let allDebridEnabled = UserDefaults.standard.bool(forKey: "AllDebrid.Enabled")
        if allDebridEnabled {
            enabledDebrids.insert(.allDebrid)
            UserDefaults.standard.set(false, forKey: "AllDebrid.Enabled")
        }

        let premiumizeEnabled = UserDefaults.standard.bool(forKey: "Premiumize.Enabled")
        if premiumizeEnabled {
            enabledDebrids.insert(.premiumize)
            UserDefaults.standard.set(false, forKey: "Premiumize.Enabled")
        }
    }

    // Common function to populate hashes for debrid services
    public func populateDebridIA(_ resultMagnets: [Magnet]) async {
        do {
            let now = Date()

            // If a hash isn't found in the IA, update it
            // If the hash is expired, remove it and update it
            let sendMagnets = resultMagnets.filter { magnet in
                if let IAIndex = realDebridIAValues.firstIndex(where: { $0.hash == magnet.hash }), enabledDebrids.contains(.realDebrid) {
                    if now.timeIntervalSince1970 > realDebridIAValues[IAIndex].expiryTimeStamp {
                        realDebridIAValues.remove(at: IAIndex)
                        return true
                    } else {
                        return false
                    }
                } else if let IAIndex = allDebridIAValues.firstIndex(where: { $0.hash == magnet.hash }), enabledDebrids.contains(.allDebrid) {
                    if now.timeIntervalSince1970 > allDebridIAValues[IAIndex].expiryTimeStamp {
                        allDebridIAValues.remove(at: IAIndex)
                        return true
                    } else {
                        return false
                    }
                } else if let IAIndex = premiumizeIAValues.firstIndex(where: { $0.hash == magnet.hash }), enabledDebrids.contains(.premiumize) {
                    if now.timeIntervalSince1970 > premiumizeIAValues[IAIndex].expiryTimeStamp {
                        premiumizeIAValues.remove(at: IAIndex)
                        return true
                    } else {
                        return false
                    }
                } else {
                    return true
                }
            }

            if !sendMagnets.isEmpty {
                if enabledDebrids.contains(.realDebrid) {
                    let fetchedRealDebridIA = try await realDebrid.instantAvailability(magnets: sendMagnets)
                    realDebridIAValues += fetchedRealDebridIA
                }

                if enabledDebrids.contains(.allDebrid) {
                    let fetchedAllDebridIA = try await allDebrid.instantAvailability(magnets: sendMagnets)
                    allDebridIAValues += fetchedAllDebridIA
                }

                if enabledDebrids.contains(.premiumize) {
                    let availableMagnets = try await premiumize.divideCacheRequests(magnets: sendMagnets)

                    // Split DDL requests into chunks of 10
                    for chunk in availableMagnets.chunked(into: 10) {
                        let tempIA = try await premiumize.divideDDLRequests(magnetChunk: chunk)

                        premiumizeIAValues += tempIA
                    }
                }
            }
        } catch {
            let error = error as NSError

            if error.code != -999 {
                toastModel?.updateToastDescription("Hash population error: \(error)")
            }

            print("Hash population error: \(error)")
        }
    }

    // Common function to match search results with a provided debrid service
    public func matchSearchResult(result: SearchResult?) -> IAStatus {
        guard let result else {
            return .none
        }

        switch selectedDebridType {
        case .realDebrid:
            guard let realDebridMatch = realDebridIAValues.first(where: { result.magnetHash == $0.hash }) else {
                return .none
            }

            if realDebridMatch.batches.isEmpty {
                return .full
            } else {
                return .partial
            }
        case .allDebrid:
            guard let allDebridMatch = allDebridIAValues.first(where: { result.magnetHash == $0.hash }) else {
                return .none
            }

            if allDebridMatch.files.count > 1 {
                return .partial
            } else {
                return .full
            }
        case .premiumize:
            guard let premiumizeMatch = premiumizeIAValues.first(where: { result.magnetHash == $0.hash }) else {
                return .none
            }

            if premiumizeMatch.files.count > 1 {
                return .partial
            } else {
                return .full
            }
        case .none:
            return .none
        }
    }

    public func selectDebridResult(result: SearchResult) -> Bool {
        guard let magnetHash = result.magnetHash else {
            toastModel?.updateToastDescription("Could not find the torrent magnet hash")
            return false
        }

        switch selectedDebridType {
        case .realDebrid:
            if let realDebridItem = realDebridIAValues.first(where: { magnetHash == $0.hash }) {
                selectedRealDebridItem = realDebridItem
                return true
            } else {
                toastModel?.updateToastDescription("Could not find the associated RealDebrid entry for magnet hash \(magnetHash)")
                return false
            }
        case .allDebrid:
            if let allDebridItem = allDebridIAValues.first(where: { magnetHash == $0.hash }) {
                selectedAllDebridItem = allDebridItem
                return true
            } else {
                toastModel?.updateToastDescription("Could not find the associated AllDebrid entry for magnet hash \(magnetHash)")
                return false
            }
        case .premiumize:
            if let premiumizeItem = premiumizeIAValues.first(where: { magnetHash == $0.hash }) {
                selectedPremiumizeItem = premiumizeItem
                return true
            } else {
                toastModel?.updateToastDescription("Could not find the associated Premiumize entry for magnet hash \(magnetHash)")
                return false
            }
        case .none:
            return false
        }
    }

    // MARK: - Authentication UI linked functions

    // Common function to delegate what debrid service to authenticate with
    public func authenticateDebrid(debridType: DebridType) async {
        switch debridType {
        case .realDebrid:
            let success = await authenticateRd()
            completeDebridAuth(debridType, success: success)
        case .allDebrid:
            let success = await authenticateAd()
            completeDebridAuth(debridType, success: success)
        case .premiumize:
            await authenticatePm()
        }
    }

    // Callback to finish debrid auth since functions can be split
    func completeDebridAuth(_ debridType: DebridType, success: Bool = true) {
        if enabledDebrids.count == 1, success {
            print("Enabled debrids is 1!")
            selectedDebridType = enabledDebrids.first
        }

        switch debridType {
        case .realDebrid:
            realDebridAuthProcessing = false
        case .allDebrid:
            allDebridAuthProcessing = false
        case .premiumize:
            premiumizeAuthProcessing = false
        }
    }

    // Wrapper function to validate and present an auth URL to the user
    @discardableResult func validateAuthUrl(_ url: URL?, useAuthSession: Bool = false) -> Bool {
        guard let url else {
            toastModel?.updateToastDescription("Authentication Error: Invalid URL created: \(String(describing: url))")
            return false
        }

        authUrl = url
        if useAuthSession {
            showAuthSession.toggle()
        } else {
            showWebView.toggle()
        }

        return true
    }

    private func authenticateRd() async -> Bool {
        do {
            realDebridAuthProcessing = true
            let verificationResponse = try await realDebrid.getVerificationInfo()

            if validateAuthUrl(URL(string: verificationResponse.directVerificationURL)) {
                try await realDebrid.getDeviceCredentials(deviceCode: verificationResponse.deviceCode)
                enabledDebrids.insert(.realDebrid)
            } else {
                throw RealDebrid.RDError.AuthQuery(description: "The verification URL was invalid")
            }

            return true
        } catch {
            toastModel?.updateToastDescription("RealDebrid authentication error: \(error)")
            realDebrid.authTask?.cancel()

            print("RealDebrid authentication error: \(error)")

            return false
        }
    }

    private func authenticateAd() async -> Bool {
        do {
            allDebridAuthProcessing = true
            let pinResponse = try await allDebrid.getPinInfo()

            if validateAuthUrl(URL(string: pinResponse.userURL)) {
                try await allDebrid.getApiKey(checkID: pinResponse.check, pin: pinResponse.pin)
                enabledDebrids.insert(.allDebrid)
            } else {
                throw AllDebrid.ADError.AuthQuery(description: "The PIN URL was invalid")
            }

            return true
        } catch {
            toastModel?.updateToastDescription("AllDebrid authentication error: \(error)")
            allDebrid.authTask?.cancel()

            print("AllDebrid authentication error: \(error)")

            return false
        }
    }

    private func authenticatePm() async {
        do {
            premiumizeAuthProcessing = true
            let tempAuthUrl = try premiumize.buildAuthUrl()

            validateAuthUrl(tempAuthUrl, useAuthSession: true)
        } catch {
            toastModel?.updateToastDescription("Premiumize authentication error: \(error)")
            completeDebridAuth(.premiumize, success: false)

            print("Premiumize authentication error (auth): \(error)")
        }
    }

    // Currently handles Premiumize callback
    public func handleCallback(url: URL?, error: Error?) {
        do {
            if let error {
                throw Premiumize.PMError.AuthQuery(description: "OAuth callback Error: \(error)")
            }

            if let callbackUrl = url {
                try premiumize.handleAuthCallback(url: callbackUrl)
                enabledDebrids.insert(.premiumize)
                completeDebridAuth(.premiumize)
            } else {
                throw Premiumize.PMError.AuthQuery(description: "The callback URL was invalid")
            }
        } catch {
            toastModel?.updateToastDescription("Premiumize authentication error: \(error)")
            completeDebridAuth(.premiumize, success: false)

            print("Premiumize authentication error (callback): \(error)")
        }
    }

    // MARK: - Logout UI linked functions

    // Common function to delegate what debrid service to logout of
    public func logoutDebrid(debridType: DebridType) async {
        switch debridType {
        case .realDebrid:
            await logoutRd()
        case .allDebrid:
            logoutAd()
        case .premiumize:
            logoutPm()
        }

        // Automatically resets the preferred debrid service if it was set to the logged out service
        if selectedDebridType == debridType {
            selectedDebridType = nil
        }
    }

    private func logoutRd() async {
        do {
            try await realDebrid.deleteTokens()
            enabledDebrids.remove(.realDebrid)
        } catch {
            toastModel?.updateToastDescription("RealDebrid logout error: \(error)")

            print("RealDebrid logout error: \(error)")
        }
    }

    private func logoutAd() {
        allDebrid.deleteTokens()
        enabledDebrids.remove(.allDebrid)

        toastModel?.updateToastDescription("Please manually delete the AllDebrid API key", newToastType: .info)
    }

    private func logoutPm() {
        premiumize.deleteTokens()
        enabledDebrids.remove(.premiumize)
    }

    // MARK: - Debrid fetch UI linked functions

    // Common function to delegate what debrid service to fetch from
    public func fetchDebridDownload(searchResult: SearchResult) async {
        defer {
            currentDebridTask = nil
            showLoadingProgress = false
        }

        showLoadingProgress = true

        // Premiumize doesn't need a magnet link
        guard searchResult.magnetLink != nil || selectedDebridType == .premiumize else {
            toastModel?.updateToastDescription("Could not run your action because the magnet link is invalid.")
            print("Debrid error: Invalid magnet link")

            return
        }

        // Force unwrap is OK for debrid types that aren't ignored since the magnet link was already checked
        // Do not force unwrap for Premiumize!
        switch selectedDebridType {
        case .realDebrid:
            await fetchRdDownload(magnetLink: searchResult.magnetLink!)
        case .allDebrid:
            await fetchAdDownload(magnetLink: searchResult.magnetLink!)
        case .premiumize:
            fetchPmDownload()
        case .none:
            break
        }
    }

    func fetchRdDownload(magnetLink: String) async {
        do {
            var fileIds: [Int] = []

            if let iaFile = selectedRealDebridFile {
                guard let iaBatchFromFile = selectedRealDebridItem?.batches[safe: iaFile.batchIndex] else {
                    return
                }

                fileIds = iaBatchFromFile.files.map(\.id)
            }

            // If there's an existing torrent, check for a download link. Otherwise check for an unrestrict link
            let existingTorrents = try await realDebrid.userTorrents().filter { $0.hash == selectedRealDebridItem?.hash }

            // If the links match from a user's downloads, no need to re-run a download
            if let existingTorrent = existingTorrents[safe: 0],
               let torrentLink = existingTorrent.links[safe: selectedRealDebridFile?.batchFileIndex ?? 0]
            {
                let existingLinks = try await realDebrid.userDownloads().filter { $0.link == torrentLink }
                if let existingLink = existingLinks[safe: 0]?.download {
                    downloadUrl = existingLink
                } else {
                    let downloadLink = try await realDebrid.unrestrictLink(debridDownloadLink: torrentLink)

                    downloadUrl = downloadLink
                }

            } else {
                // Add a magnet after all the cache checks fail
                selectedRealDebridID = try await realDebrid.addMagnet(magnetLink: magnetLink)

                if let realDebridId = selectedRealDebridID {
                    try await realDebrid.selectFiles(debridID: realDebridId, fileIds: fileIds)

                    let torrentLink = try await realDebrid.torrentInfo(
                        debridID: realDebridId,
                        selectedIndex: selectedRealDebridFile?.batchFileIndex ?? 0
                    )
                    let downloadLink = try await realDebrid.unrestrictLink(debridDownloadLink: torrentLink)

                    downloadUrl = downloadLink
                } else {
                    toastModel?.updateToastDescription("Could not cache this torrent. Aborting.")
                }
            }
        } catch {
            switch error {
            case RealDebrid.RDError.EmptyTorrents:
                showDeleteAlert.toggle()
            default:
                let error = error as NSError

                switch error.code {
                case -999:
                    toastModel?.updateToastDescription("Download cancelled", newToastType: .info)
                default:
                    toastModel?.updateToastDescription("RealDebrid download error: \(error)")
                }

                await deleteRdTorrent()
            }

            showLoadingProgress = false

            print("RealDebrid download error: \(error)")
        }
    }

    func deleteRdTorrent() async {
        if let realDebridId = selectedRealDebridID {
            try? await realDebrid.deleteTorrent(debridID: realDebridId)
        }

        selectedRealDebridID = nil
    }

    func fetchAdDownload(magnetLink: String) async {
        do {
            let magnetID = try await allDebrid.addMagnet(magnetLink: magnetLink)
            let lockedLink = try await allDebrid.fetchMagnetStatus(
                magnetId: magnetID,
                selectedIndex: selectedAllDebridFile?.id ?? 0
            )
            let unlockedLink = try await allDebrid.unlockLink(lockedLink: lockedLink)

            downloadUrl = unlockedLink
        } catch {
            let error = error as NSError
            switch error.code {
            case -999:
                toastModel?.updateToastDescription("Download cancelled", newToastType: .info)
            default:
                toastModel?.updateToastDescription("AllDebrid download error: \(error)")
            }
        }
    }

    func fetchPmDownload() {
        guard let premiumizeItem = selectedPremiumizeItem else {
            toastModel?.updateToastDescription("Could not run your action because the result is invalid")
            print("Premiumize download error: Invalid selected Premiumize item")

            return
        }

        if let premiumizeFile = selectedPremiumizeFile {
            downloadUrl = premiumizeFile.streamUrlString
        } else if let firstFile = premiumizeItem.files[safe: 0] {
            downloadUrl = firstFile.streamUrlString
        } else {
            toastModel?.updateToastDescription("Could not run your action because the result could not be found")
            print("Premiumize download error: Could not find the selected Premiumize file")
        }
    }
}
