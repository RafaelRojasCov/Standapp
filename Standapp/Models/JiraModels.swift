import Foundation

enum JiraStatusCategory: String, Decodable {
    case new
    case indeterminate
    case done
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = JiraStatusCategory(rawValue: rawValue) ?? .unknown
    }
}

struct JiraTicket: Identifiable, Decodable, Hashable {
    let id: String
    let key: String
    let summary: String
    let statusName: String
    let statusCategory: JiraStatusCategory

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case fields
    }

    private enum FieldsCodingKeys: String, CodingKey {
        case summary
        case status
    }

    private enum StatusCodingKeys: String, CodingKey {
        case name
        case statusCategory
    }

    private enum StatusCategoryCodingKeys: String, CodingKey {
        case key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)

        let fieldsContainer = try container.nestedContainer(keyedBy: FieldsCodingKeys.self, forKey: .fields)
        summary = try fieldsContainer.decode(String.self, forKey: .summary)

        let statusContainer = try fieldsContainer.nestedContainer(keyedBy: StatusCodingKeys.self, forKey: .status)
        statusName = try statusContainer.decode(String.self, forKey: .name)

        let statusCategoryContainer = try statusContainer.nestedContainer(keyedBy: StatusCategoryCodingKeys.self, forKey: .statusCategory)
        statusCategory = try statusCategoryContainer.decode(JiraStatusCategory.self, forKey: .key)
    }
}

struct JiraSearchResponse: Decodable {
    let startAt: Int
    let maxResults: Int
    let total: Int
    let issues: [JiraTicket]
}

struct JiraCredentials {
    let email: String
    let apiToken: String
}
