// 主传心 / 鸵鸟传心室的核心 mutation + action。
// 入口：
//   - sendMessage (action) — 客户端发消息时调，会触发 Sonnet 4.7。
//   - _loadChatContext (internalQuery) — 给 claude.chat 内部用，加载鸵鸟+主人。
//   - _appendUserMessage / _appendOstrichReply (internalMutation) — action 内部写消息。
//
// 注: 这里直接用 *Generic + DataModelFromSchemaDefinition，
// 避免依赖 convex/_generated。

import {
  actionGeneric,
  internalMutationGeneric,
  internalQueryGeneric,
  makeFunctionReference,
  type DataModelFromSchemaDefinition,
  type GenericActionCtx,
  type GenericMutationCtx,
  type GenericQueryCtx,
} from "convex/server";
import { v } from "convex/values";
import schema from "./schema";
import type { ChatResult, ToolCall } from "./claude";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type QueryCtx = GenericQueryCtx<DataModel>;
type MutationCtx = GenericMutationCtx<DataModel>;
type ActionCtx = GenericActionCtx<DataModel>;

// pending_persons 默认 24h 超时
const PENDING_PERSON_TTL_MS = 24 * 60 * 60 * 1000;
// sendMessage 拉的历史长度
const HISTORY_LIMIT = 20;

// ─────────────────────────────────────────────────────────────
// internalQuery · _loadChatContext
//   给 claude.chat 读鸵鸟 + 主人，拼五层 prompt 用。
// ─────────────────────────────────────────────────────────────

export const _loadChatContext = internalQueryGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: QueryCtx, args) => {
    const ostrich = await ctx.db.get(args.ostrichId);
    if (!ostrich) throw new Error(`Ostrich not found: ${args.ostrichId}`);
    const user = await ctx.db.get(ostrich.ownerId);
    if (!user) throw new Error(`Owner user not found: ${ostrich.ownerId}`);
    return {
      ostrich: {
        eggType: ostrich.eggType,
        name: ostrich.name,
        awakenedAt: ostrich.awakenedAt,
      },
      user: {
        name: user.name,
        mbti: user.mbti ?? "",
        zodiac: user.zodiac ?? "",
      },
    };
  },
});

// ─────────────────────────────────────────────────────────────
// internalQuery · _loadRoomForSend
//   返回房间、鸵鸟 + 最近 history。
// ─────────────────────────────────────────────────────────────

export const _loadRoomForSend = internalQueryGeneric({
  args: { roomId: v.id("chat_rooms") },
  handler: async (ctx: QueryCtx, args) => {
    const room = await ctx.db.get(args.roomId);
    if (!room) throw new Error(`Room not found: ${args.roomId}`);

    // 找到房间对应的鸵鸟（主传心 = owner.ostrichId）
    const owner = await ctx.db.get(room.ownerId);
    if (!owner) throw new Error(`Room owner not found: ${room.ownerId}`);
    if (!owner.ostrichId) {
      throw new Error(`Owner has no ostrich yet: ${room.ownerId}`);
    }
    const ostrich = await ctx.db.get(owner.ostrichId);
    if (!ostrich) throw new Error(`Owner ostrich missing: ${owner.ostrichId}`);

    // 最近 HISTORY_LIMIT 条消息（按时间升序返回给 LLM）
    const recent = await ctx.db
      .query("messages")
      .withIndex("by_room_time", (q) => q.eq("roomId", args.roomId))
      .order("desc")
      .take(HISTORY_LIMIT);
    const history = recent.reverse().map((m) => ({
      role: (m.sender === "user" ? "user" : "assistant") as "user" | "assistant",
      content: m.content,
    }));

    return {
      roomOwnerId: room.ownerId,
      ostrichId: ostrich._id,
      history,
    };
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · _appendUserMessage
// ─────────────────────────────────────────────────────────────

export const _appendUserMessage = internalMutationGeneric({
  args: {
    roomId: v.id("chat_rooms"),
    userId: v.id("users"),
    content: v.string(),
  },
  handler: async (ctx: MutationCtx, args) => {
    const id = await ctx.db.insert("messages", {
      roomId: args.roomId,
      sender: "user",
      senderId: args.userId,
      content: args.content,
      metadata: {},
      createdAt: Date.now(),
    });
    return id;
  },
});

// ─────────────────────────────────────────────────────────────
// internalMutation · _appendOstrichReply
//   写鸵鸟消息 + 解析 toolCalls (note_person / remember)
// ─────────────────────────────────────────────────────────────

const toolCallValidator = v.object({
  toolName: v.string(),
  args: v.any(),
});

export const _appendOstrichReply = internalMutationGeneric({
  args: {
    roomId: v.id("chat_rooms"),
    ostrichId: v.id("ostriches"),
    ownerId: v.id("users"),
    content: v.string(),
    toolCalls: v.array(toolCallValidator),
  },
  handler: async (ctx: MutationCtx, args) => {
    const now = Date.now();
    const processedToolCalls: Array<{
      toolName: string;
      args: unknown;
      pendingPersonId?: import("convex/values").GenericId<"pending_persons">;
    }> = [];

    for (const tc of args.toolCalls) {
      if (tc.toolName === "note_person") {
        const tcArgs = (tc.args ?? {}) as {
          name?: string;
          hint?: string;
          suggestedCategory?: string;
          emotionalContext?: string;
        };
        const pendingPersonId = await ctx.db.insert("pending_persons", {
          ownerId: args.ownerId,
          ostrichId: args.ostrichId,
          name: tcArgs.name ?? "（未知）",
          aliases: [],
          categoryHint: tcArgs.suggestedCategory,
          notes: tcArgs.hint,
          createdAt: now,
          expiresAt: now + PENDING_PERSON_TTL_MS,
        });
        processedToolCalls.push({
          toolName: tc.toolName,
          args: tc.args,
          pendingPersonId,
        });
      } else if (tc.toolName === "remember") {
        const tcArgs = (tc.args ?? {}) as {
          content?: string;
          importance?: number;
          visibility?: "core" | "normal" | "redacted";
          relatedPersonIds?: string[];
        };
        await ctx.db.insert("memories", {
          ostrichId: args.ostrichId,
          type: "conversation",
          content: tcArgs.content ?? "",
          importance:
            typeof tcArgs.importance === "number"
              ? Math.max(0, Math.min(1, tcArgs.importance))
              : 0.5,
          visibility: tcArgs.visibility ?? "normal",
          relatedPersonIds: [],
          relatedOstrichIds: [],
          createdAt: now,
        });
        processedToolCalls.push({ toolName: tc.toolName, args: tc.args });
      } else {
        // 其他工具 Phase 1 仅记录到 message metadata，不实际执行
        processedToolCalls.push({ toolName: tc.toolName, args: tc.args });
      }
    }

    const messageId = await ctx.db.insert("messages", {
      roomId: args.roomId,
      sender: "ostrich",
      senderId: args.ostrichId,
      content: args.content,
      metadata: {
        toolCalls:
          processedToolCalls.length > 0
            ? processedToolCalls.map((tc) => ({
                toolName: tc.toolName,
                args: tc.args,
                pendingPersonId: tc.pendingPersonId,
              }))
            : undefined,
      },
      createdAt: now,
    });

    return { messageId, processedToolCalls };
  },
});

// ─────────────────────────────────────────────────────────────
// action · sendMessage
//   外部入口。INTERFACES §1.3 `/api/chat/send`。
// ─────────────────────────────────────────────────────────────

export type SendMessageResult = {
  messageId: string;
  ostrichReply: { id: string; content: string; createdAt: number };
  toolCalls: ToolCall[];
};

export const sendMessage = actionGeneric({
  args: {
    roomId: v.id("chat_rooms"),
    content: v.string(),
  },
  handler: async (ctx: ActionCtx, args): Promise<SendMessageResult> => {
    // 1. 加载房间 + 鸵鸟 + 历史
    const ctxData = (await ctx.runQuery(
      makeFunctionReference<"query">("chat:_loadRoomForSend") as never,
      { roomId: args.roomId } as never,
    )) as {
      roomOwnerId: string;
      ostrichId: string;
      history: Array<{ role: "user" | "assistant"; content: string }>;
    };

    // 2. 写 user message
    const userMessageId = (await ctx.runMutation(
      makeFunctionReference<"mutation">("chat:_appendUserMessage") as never,
      {
        roomId: args.roomId,
        userId: ctxData.roomOwnerId,
        content: args.content,
      } as never,
    )) as string;

    // 3. 调 claude.chat
    const chatResult = (await ctx.runAction(
      makeFunctionReference<"action">("claude:chat") as never,
      {
        ostrichId: ctxData.ostrichId,
        userMessage: args.content,
        history: ctxData.history,
      } as never,
    )) as ChatResult;

    // 4. 写 ostrich reply + 解析 toolCalls
    const appendResult = (await ctx.runMutation(
      makeFunctionReference<"mutation">("chat:_appendOstrichReply") as never,
      {
        roomId: args.roomId,
        ostrichId: ctxData.ostrichId,
        ownerId: ctxData.roomOwnerId,
        content: chatResult.text,
        toolCalls: chatResult.toolCalls,
      } as never,
    )) as { messageId: string; processedToolCalls: unknown };

    return {
      messageId: userMessageId,
      ostrichReply: {
        id: appendResult.messageId,
        content: chatResult.text,
        createdAt: Date.now(),
      },
      toolCalls: chatResult.toolCalls,
    };
  },
});
