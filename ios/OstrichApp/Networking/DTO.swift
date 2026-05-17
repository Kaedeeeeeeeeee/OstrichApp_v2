// DTO.swift
// iOS Codable 镜像 — 字段严格对齐 INTERFACES.md §2 / §3 的 TypeScript DTO。
// 日期字段统一用 String (ISO-8601)，由调用方按需用 ISO8601DateFormatter 解。
// CI 由 scripts/check-dto-alignment.sh 警告字段名漂移。

import Foundation

// MARK: - 通用响应包装

/// `{ "ok": true, "data": ... }` 或 `{ "ok": false, "error": { code, message } }`
public struct ConvexEnvelope<T: Decodable>: Decodable {
    public let ok: Bool
    public let data: T?
    public let error: ConvexErrorPayload?
}

public struct ConvexErrorPayload: Decodable {
    public let code: String
    public let message: String
}

/// 空响应 (`{ ok: true }` 时 data 可能是空对象或缺省)
public struct EmptyResponse: Decodable {
    public init() {}
}

// MARK: - Ostrich

public struct OstrichDTO: Codable, Equatable {
    public let id: String
    public let ownerId: String
    public let name: String
    public let eggType: Int
    public let archetype: String
    public let awakenedAt: String
    public let state: String
    public let currentLocation: LocationDTO
    public let currentActivity: String
    public let daysTogether: Int
    /// 仅 /api/awaken 返回 — 主传心室 id。其他 endpoint 返回 OstrichDTO 时为 nil。
    public let mainRoomId: String?

    public init(
        id: String,
        ownerId: String,
        name: String,
        eggType: Int,
        archetype: String,
        awakenedAt: String,
        state: String,
        currentLocation: LocationDTO,
        currentActivity: String,
        daysTogether: Int,
        mainRoomId: String? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.eggType = eggType
        self.archetype = archetype
        self.awakenedAt = awakenedAt
        self.state = state
        self.currentLocation = currentLocation
        self.currentActivity = currentActivity
        self.daysTogether = daysTogether
        self.mainRoomId = mainRoomId
    }
}

public struct LocationDTO: Codable, Equatable {
    public let lat: Double
    public let lng: Double
    public let friendlyName: String

    public init(lat: Double, lng: Double, friendlyName: String) {
        self.lat = lat
        self.lng = lng
        self.friendlyName = friendlyName
    }
}

// MARK: - Thoughts (头顶气泡)

/// `/api/ostrich/thought/:id` 返回。流式期间 status="streaming"，content 在每次轮询时逐步增长；
/// status="done" 后停止轮询、启动 10s 淡出。
public struct ThoughtDTO: Codable, Equatable {
    public let id: String
    public let content: String
    public let status: String            // "streaming" | "done" | "error"
    public let activityContext: String
    public let locationName: String
    public let createdAt: String

    public init(
        id: String,
        content: String,
        status: String,
        activityContext: String,
        locationName: String,
        createdAt: String
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.activityContext = activityContext
        self.locationName = locationName
        self.createdAt = createdAt
    }
}

/// `/api/ostrich/think` POST 返回。
public struct ThoughtCreateResponseDTO: Codable, Equatable {
    public let thoughtId: String

    public init(thoughtId: String) {
        self.thoughtId = thoughtId
    }
}

// MARK: - Chat / Messages

public struct MessageDTO: Codable, Equatable {
    public let id: String
    public let roomId: String
    public let sender: String           // "user" | "ostrich" | "other_user" | "other_ostrich"
    public let senderId: String
    public let content: String
    public let createdAt: String
    public let metadata: MessageMetadataDTO?

    public init(
        id: String,
        roomId: String,
        sender: String,
        senderId: String,
        content: String,
        createdAt: String,
        metadata: MessageMetadataDTO? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.sender = sender
        self.senderId = senderId
        self.content = content
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct MessageMetadataDTO: Codable, Equatable {
    public let softened: Bool?
    public let nameCardGenerated: Bool?

    public init(softened: Bool? = nil, nameCardGenerated: Bool? = nil) {
        self.softened = softened
        self.nameCardGenerated = nameCardGenerated
    }
}

public struct ToolCallDTO: Codable, Equatable {
    /// "note_person" | "update_person" | "remember" | "suggest_reach_out" |
    /// "generate_name_card" | "request_to_stay_wandering"
    public let toolName: String
    public let args: JSONValue
    public let pendingPersonId: String?

    public init(toolName: String, args: JSONValue, pendingPersonId: String? = nil) {
        self.toolName = toolName
        self.args = args
        self.pendingPersonId = pendingPersonId
    }
}

// MARK: - Graph

public struct PersonDTO: Codable, Equatable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let category: String
    public let closeness: Double
    public let recentInteractionCount: Int
    public let notes: String
    public let hasOstrich: Bool
    public let lastMentionedAt: String
    /// 该人物被多少字符的记忆引用。关系图谱光球生成频率的输入。
    /// 老版本后端 / 缺省时取 0。INTERFACES.md §1.4。
    public let memoryWeight: Double?

    public init(
        id: String,
        name: String,
        aliases: [String],
        category: String,
        closeness: Double,
        recentInteractionCount: Int,
        notes: String,
        hasOstrich: Bool,
        lastMentionedAt: String,
        memoryWeight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.closeness = closeness
        self.recentInteractionCount = recentInteractionCount
        self.notes = notes
        self.hasOstrich = hasOstrich
        self.lastMentionedAt = lastMentionedAt
        self.memoryWeight = memoryWeight
    }
}

public struct EdgeDTO: Codable, Equatable {
    public let fromPersonId: String
    public let toPersonId: String
    public let weight: Double

    public init(fromPersonId: String, toPersonId: String, weight: Double) {
        self.fromPersonId = fromPersonId
        self.toPersonId = toPersonId
        self.weight = weight
    }
}

// MARK: - Diary

public struct DiaryEntryDTO: Codable, Equatable {
    public let id: String
    public let timestamp: String
    public let content: String
    public let visibility: String        // "visible" | "redacted"
    public let redactionReason: String?
    public let location: DiaryLocationDTO?
    public let encounteredOstrichOwnerName: String?

    public init(
        id: String,
        timestamp: String,
        content: String,
        visibility: String,
        redactionReason: String? = nil,
        location: DiaryLocationDTO? = nil,
        encounteredOstrichOwnerName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.visibility = visibility
        self.redactionReason = redactionReason
        self.location = location
        self.encounteredOstrichOwnerName = encounteredOstrichOwnerName
    }
}

public struct DiaryLocationDTO: Codable, Equatable {
    public let lat: Double
    public let lng: Double
    public let friendlyName: String
    public let lookAroundAvailable: Bool

    public init(lat: Double, lng: Double, friendlyName: String, lookAroundAvailable: Bool) {
        self.lat = lat
        self.lng = lng
        self.friendlyName = friendlyName
        self.lookAroundAvailable = lookAroundAvailable
    }
}

// MARK: - Map

public struct MapPointDTO: Codable, Equatable {
    public let ostrichId: String?
    public let lat: Double
    public let lng: Double
    public let activity: String

    public init(ostrichId: String? = nil, lat: Double, lng: Double, activity: String) {
        self.ostrichId = ostrichId
        self.lat = lat
        self.lng = lng
        self.activity = activity
    }
}

public struct PolylineDTO: Codable, Equatable {
    public let coords: [[Double]]        // [[lat, lng], ...]
    public let expectedDurationSec: Int
    public let startedAt: String

    public init(coords: [[Double]], expectedDurationSec: Int, startedAt: String) {
        self.coords = coords
        self.expectedDurationSec = expectedDurationSec
        self.startedAt = startedAt
    }
}

public struct MapCellSummaryDTO: Codable, Equatable {
    public let cellId: String
    public let centerLat: Double
    public let centerLng: Double
    public let ostrichCount: Int

    public init(cellId: String, centerLat: Double, centerLng: Double, ostrichCount: Int) {
        self.cellId = cellId
        self.centerLat = centerLat
        self.centerLng = centerLng
        self.ostrichCount = ostrichCount
    }
}

// MARK: - 复合响应

public struct ChatSendResponseDTO: Codable, Equatable {
    public let messageId: String
    public let ostrichReply: MessageDTO
    public let toolCalls: [ToolCallDTO]

    public init(messageId: String, ostrichReply: MessageDTO, toolCalls: [ToolCallDTO]) {
        self.messageId = messageId
        self.ostrichReply = ostrichReply
        self.toolCalls = toolCalls
    }
}

public struct ChatRoomMessagesResponseDTO: Codable, Equatable {
    public let messages: [MessageDTO]
    public let hasMore: Bool

    public init(messages: [MessageDTO], hasMore: Bool) {
        self.messages = messages
        self.hasMore = hasMore
    }
}

public struct GraphResponseDTO: Codable, Equatable {
    public let people: [PersonDTO]
    public let edges: [EdgeDTO]

    public init(people: [PersonDTO], edges: [EdgeDTO]) {
        self.people = people
        self.edges = edges
    }
}

public struct DiaryListResponseDTO: Codable, Equatable {
    public let entries: [DiaryEntryDTO]

    public init(entries: [DiaryEntryDTO]) {
        self.entries = entries
    }
}

public struct MapGodViewResponseDTO: Codable, Equatable {
    public let cells: [MapCellSummaryDTO]

    public init(cells: [MapCellSummaryDTO]) {
        self.cells = cells
    }
}

public struct MapLocalViewResponseDTO: Codable, Equatable {
    public let ostrich: MapPointDTO
    public let nearby: [MapPointDTO]
    public let route: PolylineDTO?
    /// 鸵鸟当前 POI 友好名。
    /// - walking 时：还在路上想去的目的地
    /// - resting/exploring/socializing 时：到了，正在这家店里
    /// 同一份数据双重语义（INTERFACES.md §1.6）。
    public let destinationName: String?
    /// Apple Maps POI category（如 "Cafe" / "Park" / "Bookstore"）。
    /// iOS 端按它推动词："在 X [喝咖啡 / 歇会儿 / 翻翻书]..."。
    /// fallback POI（极端"附近"分支）无此字段。
    public let destinationCategory: String?
    /// LLM 给出的"为什么想去"（fallback 时是 "想随便走走"）。
    public let reason: String?

    public init(
        ostrich: MapPointDTO,
        nearby: [MapPointDTO],
        route: PolylineDTO? = nil,
        destinationName: String? = nil,
        destinationCategory: String? = nil,
        reason: String? = nil
    ) {
        self.ostrich = ostrich
        self.nearby = nearby
        self.route = route
        self.destinationName = destinationName
        self.destinationCategory = destinationCategory
        self.reason = reason
    }
}

public struct CallHomeResponseDTO: Codable, Equatable {
    public let accepted: Bool
    public let refusal: String?

    public init(accepted: Bool, refusal: String? = nil) {
        self.accepted = accepted
        self.refusal = refusal
    }
}

public struct SignInResponseDTO: Codable, Equatable {
    public let userId: String
    public let sessionToken: String
    public let isNewUser: Bool

    public init(userId: String, sessionToken: String, isNewUser: Bool) {
        self.userId = userId
        self.sessionToken = sessionToken
        self.isNewUser = isNewUser
    }
}

public struct ConfirmAddPersonResponseDTO: Codable, Equatable {
    public let personId: String?

    public init(personId: String? = nil) {
        self.personId = personId
    }
}

public struct PersonRoomResponseDTO: Codable, Equatable {
    public let roomId: String
    public let person: PersonDTO

    public init(roomId: String, person: PersonDTO) {
        self.roomId = roomId
        self.person = person
    }
}

public struct DiaryUnlockResponseDTO: Codable, Equatable {
    public let status: String            // "pending" | "denied" | "auto_visible"

    public init(status: String) {
        self.status = status
    }
}

public struct OkResponseDTO: Codable, Equatable {
    public let ok: Bool

    public init(ok: Bool = true) {
        self.ok = ok
    }
}

// MARK: - 自由 JSON 值 (用于 ToolCallDTO.args)

/// 通用 JSON value，承载 Sonnet 工具入参的任意结构。
public enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .number(let n):
            try container.encode(n)
        case .string(let s):
            try container.encode(s)
        case .array(let a):
            try container.encode(a)
        case .object(let o):
            try container.encode(o)
        }
    }
}
