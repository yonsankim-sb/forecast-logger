import Foundation

/// An account reachable by a personal access token, from
/// `GET https://id.getharvest.com/api/v2/accounts`. The token can see both
/// Harvest and Forecast accounts; `product` distinguishes them.
struct HarvestAccount: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let product: String?

    /// True for Harvest (time-tracking) accounts.
    var isHarvest: Bool {
        (product ?? "").lowercased() == "harvest"
    }

    /// True for Forecast (scheduling) accounts — the ones this app uses.
    var isForecast: Bool {
        (product ?? "").lowercased() == "forecast"
    }

    var displayName: String {
        let base = (name?.isEmpty == false ? name! : "Account")
        return "\(base) (#\(id))"
    }
}

/// The `accounts` list from the Harvest ID service.
struct AccountsResponse: Codable {
    let accounts: [HarvestAccount]
}
