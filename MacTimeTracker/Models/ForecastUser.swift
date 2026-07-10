import Foundation

/// The authenticated Forecast person, from `GET /whoami`
/// (`{ "current_user": { … } }`). The `id` is the `person_id` used when
/// creating assignments.
struct ForecastUser: Codable, Identifiable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        if !name.isEmpty { return name }
        return email ?? "Person #\(id)"
    }
}

/// Wrapper for `GET /whoami`.
struct WhoAmIResponse: Codable {
    let currentUser: ForecastUser

    enum CodingKeys: String, CodingKey {
        case currentUser = "current_user"
    }
}
