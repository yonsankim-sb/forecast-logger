import Foundation

/// A scheduled allocation from Forecast (`GET/POST /assignments`). A person is
/// booked on a project from `startDate` to `endDate` at `allocation` **seconds
/// per day**. For a single-day booking `startDate == endDate`.
struct ForecastAssignment: Codable, Identifiable, Hashable {
    let id: Int
    let projectId: Int?
    let personId: Int?
    let startDate: String?
    let endDate: String?
    /// Seconds per day (Forecast's unit). 28800 = 8h.
    let allocation: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case personId = "person_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case allocation
        case notes
    }

    init(id: Int, projectId: Int?, personId: Int?, startDate: String?, endDate: String?, allocation: Int?, notes: String?) {
        self.id = id
        self.projectId = projectId
        self.personId = personId
        self.startDate = startDate
        self.endDate = endDate
        self.allocation = allocation
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        projectId = try c.decodeIfPresent(Int.self, forKey: .projectId)
        personId = try c.decodeIfPresent(Int.self, forKey: .personId)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate)
        allocation = try c.decodeIfPresent(Int.self, forKey: .allocation)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    /// Allocated hours per day.
    var hoursPerDay: Double {
        Double(allocation ?? 0) / 3600.0
    }

    /// True when the booking covers only a single day.
    var isSingleDay: Bool {
        guard let startDate, let endDate else { return true }
        return startDate == endDate
    }
}

/// `GET /assignments`.
struct AssignmentsResponse: Codable {
    let assignments: [ForecastAssignment]
}

/// `POST /assignments` response wrapper.
struct AssignmentResponse: Codable {
    let assignment: ForecastAssignment
}
