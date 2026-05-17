// ChatModels.swift
// 传心 tab 用的本地模型：confirmAddPerson 请求 + note_person 自然提示。
// INTERFACES.md §1.3。

import Foundation

/// `/api/chat/confirmAddPerson` body（INTERFACES.md §1.3）。
public struct ConfirmAddPersonRequest: Encodable {
    public let pendingPersonId: String
    public let accept: Bool
    public let categoryHint: String?

    public init(pendingPersonId: String, accept: Bool, categoryHint: String? = nil) {
        self.pendingPersonId = pendingPersonId
        self.accept = accept
        self.categoryHint = categoryHint
    }
}

/// 鸵鸟自然涌现的「note_person」提示状态。
/// ToolCallDTO.toolName == "note_person" 时由 ChatViewModel 解析为该结构。
public struct NotePersonPrompt: Identifiable, Equatable, Hashable {
    public let id: String          // pendingPersonId（INTERFACES §1.3 由后端给）
    public let personName: String  // tool args.name
    public let hint: String        // tool args.hint
    public let suggestedCategory: String?

    public init(
        id: String,
        personName: String,
        hint: String,
        suggestedCategory: String? = nil
    ) {
        self.id = id
        self.personName = personName
        self.hint = hint
        self.suggestedCategory = suggestedCategory
    }

    /// 从 ToolCallDTO 解析。toolName != "note_person" 或缺 pendingPersonId 时返回 nil。
    public static func fromToolCall(_ call: ToolCallDTO) -> NotePersonPrompt? {
        guard call.toolName == "note_person",
              let pid = call.pendingPersonId,
              case .object(let dict) = call.args else {
            return nil
        }
        let name = stringValue(dict["name"]) ?? "这位"
        let hint = stringValue(dict["hint"]) ?? ""
        let category = stringValue(dict["suggestedCategory"])
        return NotePersonPrompt(
            id: pid,
            personName: name,
            hint: hint,
            suggestedCategory: category
        )
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        guard let value = value else { return nil }
        if case .string(let s) = value { return s }
        return nil
    }
}
