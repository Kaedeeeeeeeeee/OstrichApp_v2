// HTTP router for OstrichApp_v2.
//
// 暴露 INTERFACES §1 列出的全部 REST endpoints，供 iOS ConvexClient 调用。
// 所有响应统一 envelope：
//   { ok: true, data: ... }
//   { ok: false, error: { code, message } }
//
// 注: 这里直接用 *Generic + DataModelFromSchemaDefinition，避免依赖 convex/_generated。
//
// Phase 1 说明：
//   - 鉴权使用固定 mock session token "demo-session-token"。
//     /api/auth/signInWithApple 返回该 token；其余 endpoint 校验 Authorization header。
//     Apple Sign In 真实集成留给 Phase 2。
//   - /api/settings/* 为占位实现：接受请求，返回 { ok: true }，不实做。
//   - path 参数（如 :roomId）通过 pathPrefix + URL parsing 手动解析，Convex httpRouter
//     原生不支持 :param。

import {
  httpActionGeneric,
  httpRouter,
  internalMutationGeneric,
  internalQueryGeneric,
  makeFunctionReference,
  type DataModelFromSchemaDefinition,
  type GenericMutationCtx,
  type GenericQueryCtx,
} from "convex/server";
import { v, type GenericId as Id } from "convex/values";
import schema from "./schema";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type QueryCtx = GenericQueryCtx<DataModel>;
type MutationCtx = GenericMutationCtx<DataModel>;

// ─────────────────────────────────────────────────────────────
// 鉴权 / envelope / 错误码
// ─────────────────────────────────────────────────────────────

const MOCK_SESSION_TOKEN = "demo-session-token";

type ErrorCode =
  | "AUTH_REQUIRED"
  | "AUTH_INVALID"
  | "OSTRICH_NOT_FOUND"
  | "OSTRICH_SLEEPING"
  | "OSTRICH_WANDERING"
  | "RATE_LIMITED"
  | "CLAUDE_UNAVAILABLE"
  | "MAPS_UNAVAILABLE"
  | "INTERNAL"
  | "BAD_REQUEST";

const ERROR_STATUS: Record<ErrorCode, number> = {
  AUTH_REQUIRED: 401,
  AUTH_INVALID: 401,
  OSTRICH_NOT_FOUND: 404,
  OSTRICH_SLEEPING: 409,
  OSTRICH_WANDERING: 409,
  RATE_LIMITED: 429,
  CLAUDE_UNAVAILABLE: 503,
  MAPS_UNAVAILABLE: 503,
  INTERNAL: 500,
  BAD_REQUEST: 400,
};

class HttpError extends Error {
  constructor(
    public code: ErrorCode,
    message: string,
  ) {
    super(message);
  }
}

function okResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify({ ok: true, data }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function errorResponse(code: ErrorCode, message: string): Response {
  const status = ERROR_STATUS[code];
  return new Response(JSON.stringify({ ok: false, error: { code, message } }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function getSessionToken(request: Request): string | null {
  const header = request.headers.get("authorization") ?? request.headers.get("Authorization");
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) return null;
  return match[1].trim();
}

function requireAuth(request: Request): void {
  const token = getSessionToken(request);
  if (!token) {
    throw new HttpError("AUTH_REQUIRED", "Authorization header missing or malformed");
  }
  if (token !== MOCK_SESSION_TOKEN) {
    throw new HttpError("AUTH_INVALID", "Session token invalid");
  }
}

async function parseJsonBody<T = Record<string, unknown>>(request: Request): Promise<T> {
  try {
    const text = await request.text();
    if (!text) return {} as T;
    return JSON.parse(text) as T;
  } catch {
    throw new HttpError("BAD_REQUEST", "Invalid JSON body");
  }
}

async function withErrorEnvelope(fn: () => Promise<Response>): Promise<Response> {
  try {
    return await fn();
  } catch (err) {
    if (err instanceof HttpError) {
      return errorResponse(err.code, err.message);
    }
    const message = err instanceof Error ? err.message : String(err);
    console.error("[http] unhandled error", message);
    // 已知文案映射 → 翻译
    if (/Ostrich not found/i.test(message)) {
      return errorResponse("OSTRICH_NOT_FOUND", message);
    }
    if (/ANTHROPIC_API_KEY/i.test(message)) {
      return errorResponse("CLAUDE_UNAVAILABLE", message);
    }
    return errorResponse("INTERNAL", message || "Internal server error");
  }
}

// ─────────────────────────────────────────────────────────────
// DTO 转换 helpers
// ─────────────────────────────────────────────────────────────

const DAY_MS = 24 * 60 * 60 * 1000;

type OstrichRow = {
  _id: Id<"ostriches">;
  ownerId: Id<"users">;
  name: string;
  eggType: number;
  personality: { archetype: string };
  awakenedAt: number;
  state: string;
  currentLocation: { lat: number; lng: number; friendlyName: string };
  currentActivity: string;
};

function toOstrichDTO(o: OstrichRow): Record<string, unknown> {
  return {
    id: o._id,
    ownerId: o.ownerId,
    name: o.name,
    eggType: o.eggType,
    archetype: o.personality.archetype,
    awakenedAt: new Date(o.awakenedAt).toISOString(),
    state: o.state,
    currentLocation: {
      lat: o.currentLocation.lat,
      lng: o.currentLocation.lng,
      friendlyName: o.currentLocation.friendlyName,
    },
    currentActivity: o.currentActivity,
    daysTogether: Math.max(0, Math.floor((Date.now() - o.awakenedAt) / DAY_MS)),
  };
}

type PersonRow = {
  _id: Id<"people">;
  name: string;
  aliases: string[];
  category: string;
  closeness: number;
  recentInteractionCount: number;
  notes: string;
  hasOstrich: boolean;
  lastMentionedAt: number;
};

function toPersonDTO(p: PersonRow): Record<string, unknown> {
  return {
    id: p._id,
    name: p.name,
    aliases: p.aliases,
    category: p.category,
    closeness: p.closeness,
    recentInteractionCount: p.recentInteractionCount,
    notes: p.notes,
    hasOstrich: p.hasOstrich,
    lastMentionedAt: new Date(p.lastMentionedAt).toISOString(),
  };
}

type MessageRow = {
  _id: Id<"messages">;
  roomId: Id<"chat_rooms">;
  sender: string;
  senderId: string;
  content: string;
  createdAt: number;
  metadata: {
    softened?: boolean;
    nameCardGenerated?: boolean;
    toolCalls?: Array<{ toolName: string; args: unknown; pendingPersonId?: string }>;
  };
};

function toMessageDTO(m: MessageRow): Record<string, unknown> {
  const meta: Record<string, unknown> = {};
  if (m.metadata.softened !== undefined) meta.softened = m.metadata.softened;
  if (m.metadata.nameCardGenerated !== undefined)
    meta.nameCardGenerated = m.metadata.nameCardGenerated;
  return {
    id: m._id,
    roomId: m.roomId,
    sender: m.sender,
    senderId: m.senderId,
    content: m.content,
    createdAt: new Date(m.createdAt).toISOString(),
    metadata: Object.keys(meta).length > 0 ? meta : undefined,
  };
}

type DiaryRow = {
  _id: Id<"diary_entries">;
  timestamp: number;
  content: string;
  visibility: string;
  redactionReason?: string;
  location?: { lat: number; lng: number; friendlyName?: string };
  encounteredOstrichId?: Id<"ostriches">;
  imagery?: { lookAroundAvailable: boolean };
};

function toDiaryDTO(d: DiaryRow): Record<string, unknown> {
  const dto: Record<string, unknown> = {
    id: d._id,
    timestamp: new Date(d.timestamp).toISOString(),
    content: d.content,
    visibility: d.visibility,
  };
  if (d.redactionReason) dto.redactionReason = d.redactionReason;
  if (d.location) {
    dto.location = {
      lat: d.location.lat,
      lng: d.location.lng,
      friendlyName: d.location.friendlyName ?? "",
      lookAroundAvailable: d.imagery?.lookAroundAvailable ?? false,
    };
  }
  return dto;
}

// ─────────────────────────────────────────────────────────────
// internal queries / mutations — http actions 内部用
// (action 不能直读 db；这里给 http action 用的桥)
// ─────────────────────────────────────────────────────────────

export const _getOstrichByOwner = internalQueryGeneric({
  args: { ownerId: v.id("users") },
  handler: async (ctx: QueryCtx, args) => {
    const ostrich = await ctx.db
      .query("ostriches")
      .withIndex("by_owner", (q) => q.eq("ownerId", args.ownerId))
      .first();
    return ostrich ?? null;
  },
});

export const _getOstrichById = internalQueryGeneric({
  args: { ostrichId: v.id("ostriches") },
  handler: async (ctx: QueryCtx, args) => {
    return (await ctx.db.get(args.ostrichId)) ?? null;
  },
});

export const _getDefaultOstrich = internalQueryGeneric({
  args: {},
  handler: async (ctx: QueryCtx) => {
    // Phase 1 mock auth：取最近创建的 ostrich
    const list = await ctx.db.query("ostriches").collect();
    if (list.length === 0) return null;
    return list.sort((a, b) => b._creationTime - a._creationTime)[0];
  },
});

export const _setOstrichState = internalMutationGeneric({
  args: {
    ostrichId: v.id("ostriches"),
    state: v.union(
      v.literal("awake"),
      v.literal("wandering"),
      v.literal("called_home"),
      v.literal("sleeping_in_egg"),
      v.literal("released"),
    ),
  },
  handler: async (ctx: MutationCtx, args) => {
    const ostrich = await ctx.db.get(args.ostrichId);
    if (!ostrich) throw new Error(`Ostrich not found: ${args.ostrichId}`);
    await ctx.db.patch(args.ostrichId, { state: args.state });
  },
});

export const _listMessagesByRoom = internalQueryGeneric({
  args: {
    roomId: v.id("chat_rooms"),
    sinceMs: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx: QueryCtx, args) => {
    const limit = Math.min(args.limit ?? 50, 200);
    let q = ctx.db
      .query("messages")
      .withIndex("by_room_time", (idx) => idx.eq("roomId", args.roomId));
    if (args.sinceMs !== undefined) {
      const since = args.sinceMs;
      q = ctx.db
        .query("messages")
        .withIndex("by_room_time", (idx) => idx.eq("roomId", args.roomId).gt("createdAt", since));
    }
    const rows = await q.order("desc").take(limit + 1);
    const hasMore = rows.length > limit;
    const truncated = hasMore ? rows.slice(0, limit) : rows;
    // 升序返回（更适合 UI）
    return { messages: truncated.reverse(), hasMore };
  },
});

export const _listPeopleByOwner = internalQueryGeneric({
  args: { ownerId: v.id("users") },
  handler: async (ctx: QueryCtx, args) => {
    return await ctx.db
      .query("people")
      .withIndex("by_owner", (q) => q.eq("ownerId", args.ownerId))
      .collect();
  },
});

export const _getPersonRoom = internalQueryGeneric({
  args: { ownerId: v.id("users"), personId: v.id("people") },
  handler: async (ctx: QueryCtx, args) => {
    const person = await ctx.db.get(args.personId);
    if (!person || person.ownerId !== args.ownerId) return null;
    const room = await ctx.db
      .query("chat_rooms")
      .withIndex("by_person", (q) => q.eq("personId", args.personId))
      .first();
    return { person, room: room ?? null };
  },
});

export const _ensurePersonRoom = internalMutationGeneric({
  args: { ownerId: v.id("users"), personId: v.id("people") },
  handler: async (ctx: MutationCtx, args) => {
    const existing = await ctx.db
      .query("chat_rooms")
      .withIndex("by_person", (q) => q.eq("personId", args.personId))
      .first();
    if (existing) return existing._id;
    return await ctx.db.insert("chat_rooms", {
      ownerId: args.ownerId,
      type: "person_room",
      personId: args.personId,
      createdAt: Date.now(),
    });
  },
});

export const _categorizePerson = internalMutationGeneric({
  args: { ownerId: v.id("users"), personId: v.id("people"), category: v.string() },
  handler: async (ctx: MutationCtx, args) => {
    const person = await ctx.db.get(args.personId);
    if (!person || person.ownerId !== args.ownerId) {
      throw new Error("Person not found");
    }
    await ctx.db.patch(args.personId, { category: args.category });
  },
});

export const _listDiaryByOstrich = internalQueryGeneric({
  args: {
    ostrichId: v.id("ostriches"),
    sinceMs: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx: QueryCtx, args) => {
    const limit = Math.min(args.limit ?? 20, 100);
    const rows = await ctx.db
      .query("diary_entries")
      .withIndex("by_ostrich_timestamp", (q) => q.eq("ostrichId", args.ostrichId))
      .order("desc")
      .take(limit);
    const filtered =
      args.sinceMs !== undefined ? rows.filter((r) => r.timestamp >= args.sinceMs!) : rows;
    return filtered;
  },
});

export const _confirmAddPerson = internalMutationGeneric({
  args: {
    ownerId: v.id("users"),
    pendingPersonId: v.id("pending_persons"),
    accept: v.boolean(),
    categoryHint: v.optional(v.string()),
  },
  handler: async (ctx: MutationCtx, args) => {
    const pending = await ctx.db.get(args.pendingPersonId);
    if (!pending || pending.ownerId !== args.ownerId) {
      throw new Error("Pending person not found");
    }
    if (!args.accept) {
      await ctx.db.delete(args.pendingPersonId);
      return { personId: null };
    }
    const now = Date.now();
    const personId = await ctx.db.insert("people", {
      ownerId: args.ownerId,
      name: pending.name,
      aliases: pending.aliases,
      category: args.categoryHint ?? pending.categoryHint ?? "friend",
      closeness: 0.3,
      recentInteractionCount: 1,
      notes: pending.notes ?? "",
      hasOstrich: false,
      createdAt: now,
      lastMentionedAt: now,
    });
    await ctx.db.delete(args.pendingPersonId);
    return { personId };
  },
});

export const _listMapCells = internalQueryGeneric({
  args: {},
  handler: async (ctx: QueryCtx) => {
    return await ctx.db.query("map_cells").collect();
  },
});

// ─────────────────────────────────────────────────────────────
// HTTP router
// ─────────────────────────────────────────────────────────────

const http = httpRouter();

// 共享 helper：解析鉴权 + 拿"当前用户的鸵鸟" (Phase 1 mock：取最近一只)
async function loadCurrentOstrich(
  ctx: { runQuery: (ref: never, args: never) => Promise<unknown> },
  request: Request,
): Promise<OstrichRow> {
  requireAuth(request);
  const ostrich = (await ctx.runQuery(
    makeFunctionReference<"query">("http:_getDefaultOstrich") as never,
    {} as never,
  )) as OstrichRow | null;
  if (!ostrich) {
    throw new HttpError("OSTRICH_NOT_FOUND", "No ostrich for current session");
  }
  return ostrich;
}

// ────────────── 1.1 鉴权 ──────────────

http.route({
  path: "/api/auth/signInWithApple",
  method: "POST",
  handler: httpActionGeneric(async (_ctx, request) => {
    return withErrorEnvelope(async () => {
      await parseJsonBody(request); // 仅校验 JSON 合法
      // Phase 1 mock：固定返回
      return okResponse({
        userId: "mock-user-id",
        sessionToken: MOCK_SESSION_TOKEN,
        isNewUser: true,
      });
    });
  }),
});

http.route({
  path: "/api/auth/signOut",
  method: "POST",
  handler: httpActionGeneric(async (_ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      return okResponse({ ok: true });
    });
  }),
});

// ────────────── 1.2 鸵鸟唤醒 + 状态 ──────────────

http.route({
  path: "/api/awaken",
  method: "POST",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      const body = await parseJsonBody<{
        eggType?: number;
        name?: string;
        userMbti?: string;
        userZodiac?: string;
        userName?: string;
      }>(request);
      if (
        typeof body.eggType !== "number" ||
        typeof body.name !== "string" ||
        typeof body.userMbti !== "string" ||
        typeof body.userZodiac !== "string"
      ) {
        throw new HttpError(
          "BAD_REQUEST",
          "Missing fields: eggType / name / userMbti / userZodiac",
        );
      }
      try {
        const result = (await ctx.runMutation(
          makeFunctionReference<"mutation">("ostriches:awakenOstrich") as never,
          {
            eggType: body.eggType,
            name: body.name,
            userMbti: body.userMbti,
            userZodiac: body.userZodiac,
            userName: body.userName,
          } as never,
        )) as { ostrichId: Id<"ostriches"> };
        const ostrich = (await ctx.runQuery(
          makeFunctionReference<"query">("http:_getOstrichById") as never,
          { ostrichId: result.ostrichId } as never,
        )) as OstrichRow | null;
        if (!ostrich) throw new HttpError("INTERNAL", "Ostrich missing after awaken");
        return okResponse(toOstrichDTO(ostrich));
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        if (/Invalid eggType/i.test(message)) {
          throw new HttpError("BAD_REQUEST", message);
        }
        throw err;
      }
    });
  }),
});

http.route({
  path: "/api/ostrich/self",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      return okResponse(toOstrichDTO(ostrich));
    });
  }),
});

http.route({
  path: "/api/ostrich/callHome",
  method: "POST",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      if (ostrich.state === "sleeping_in_egg") {
        throw new HttpError("OSTRICH_SLEEPING", "Ostrich is sealed in the egg");
      }
      if (ostrich.state === "released") {
        throw new HttpError("OSTRICH_NOT_FOUND", "Ostrich has been released");
      }
      // demo 简化：直接置为 called_home，不调 Sonnet 协商
      await ctx.runMutation(
        makeFunctionReference<"mutation">("http:_setOstrichState") as never,
        { ostrichId: ostrich._id, state: "called_home" } as never,
      );
      return okResponse({ accepted: true });
    });
  }),
});

http.route({
  path: "/api/ostrich/allowToStay",
  method: "POST",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      await ctx.runMutation(
        makeFunctionReference<"mutation">("http:_setOstrichState") as never,
        { ostrichId: ostrich._id, state: "wandering" } as never,
      );
      return okResponse({ ok: true });
    });
  }),
});

// ────────────── 1.3 传心 ──────────────

http.route({
  path: "/api/chat/send",
  method: "POST",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      const body = await parseJsonBody<{ roomId?: string; content?: string }>(request);
      if (typeof body.roomId !== "string" || typeof body.content !== "string") {
        throw new HttpError("BAD_REQUEST", "Missing roomId / content");
      }
      // 在送进 sendMessage 之前先校验主鸵鸟状态
      const ostrich = (await ctx.runQuery(
        makeFunctionReference<"query">("http:_getDefaultOstrich") as never,
        {} as never,
      )) as OstrichRow | null;
      if (!ostrich) throw new HttpError("OSTRICH_NOT_FOUND", "No ostrich for current session");
      if (ostrich.state === "wandering") {
        throw new HttpError("OSTRICH_WANDERING", "Ostrich is wandering, cannot chat right now");
      }
      if (ostrich.state === "sleeping_in_egg") {
        throw new HttpError("OSTRICH_SLEEPING", "Ostrich is sealed in the egg");
      }
      try {
        const result = (await ctx.runAction(
          makeFunctionReference<"action">("chat:sendMessage") as never,
          { roomId: body.roomId, content: body.content } as never,
        )) as {
          messageId: string;
          ostrichReply: { id: string; content: string; createdAt: number };
          toolCalls: Array<{ toolName: string; args: Record<string, unknown> }>;
        };
        return okResponse({
          messageId: result.messageId,
          ostrichReply: {
            id: result.ostrichReply.id,
            roomId: body.roomId,
            sender: "ostrich",
            senderId: ostrich._id,
            content: result.ostrichReply.content,
            createdAt: new Date(result.ostrichReply.createdAt).toISOString(),
          },
          toolCalls: result.toolCalls,
        });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        if (/ANTHROPIC_API_KEY/i.test(message)) {
          throw new HttpError("CLAUDE_UNAVAILABLE", message);
        }
        throw err;
      }
    });
  }),
});

// path 参数：/api/chat/room/:roomId
http.route({
  pathPrefix: "/api/chat/room/",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      const url = new URL(request.url);
      const roomId = url.pathname.replace("/api/chat/room/", "").replace(/\/$/, "");
      if (!roomId) throw new HttpError("BAD_REQUEST", "roomId missing in path");
      const sinceParam = url.searchParams.get("since");
      const limitParam = url.searchParams.get("limit");
      const sinceMs = sinceParam ? Date.parse(sinceParam) : undefined;
      const limit = limitParam ? Math.max(1, parseInt(limitParam, 10) || 50) : 50;
      const result = (await ctx.runQuery(
        makeFunctionReference<"query">("http:_listMessagesByRoom") as never,
        {
          roomId,
          sinceMs: Number.isFinite(sinceMs) ? sinceMs : undefined,
          limit,
        } as never,
      )) as { messages: MessageRow[]; hasMore: boolean };
      return okResponse({
        messages: result.messages.map(toMessageDTO),
        hasMore: result.hasMore,
      });
    });
  }),
});

http.route({
  path: "/api/chat/confirmAddPerson",
  method: "POST",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      const body = await parseJsonBody<{
        pendingPersonId?: string;
        accept?: boolean;
        categoryHint?: string;
      }>(request);
      if (typeof body.pendingPersonId !== "string" || typeof body.accept !== "boolean") {
        throw new HttpError("BAD_REQUEST", "Missing pendingPersonId / accept");
      }
      const result = (await ctx.runMutation(
        makeFunctionReference<"mutation">("http:_confirmAddPerson") as never,
        {
          ownerId: ostrich.ownerId,
          pendingPersonId: body.pendingPersonId,
          accept: body.accept,
          categoryHint: body.categoryHint,
        } as never,
      )) as { personId: string | null };
      return okResponse({ personId: result.personId ?? undefined });
    });
  }),
});

// ────────────── 1.4 关系图谱 ──────────────

http.route({
  path: "/api/graph",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      const people = (await ctx.runQuery(
        makeFunctionReference<"query">("http:_listPeopleByOwner") as never,
        { ownerId: ostrich.ownerId } as never,
      )) as PersonRow[];
      const edges = people.map((p) => ({
        fromPersonId: "self",
        toPersonId: p._id,
        weight: p.closeness,
      }));
      return okResponse({
        people: people.map(toPersonDTO),
        edges,
      });
    });
  }),
});

http.route({
  path: "/api/graph/categorize",
  method: "POST",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      const body = await parseJsonBody<{ personId?: string; category?: string }>(request);
      if (typeof body.personId !== "string" || typeof body.category !== "string") {
        throw new HttpError("BAD_REQUEST", "Missing personId / category");
      }
      await ctx.runMutation(
        makeFunctionReference<"mutation">("http:_categorizePerson") as never,
        {
          ownerId: ostrich.ownerId,
          personId: body.personId,
          category: body.category,
        } as never,
      );
      return okResponse({ ok: true });
    });
  }),
});

http.route({
  pathPrefix: "/api/graph/personRoom/",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      const url = new URL(request.url);
      const personId = url.pathname.replace("/api/graph/personRoom/", "").replace(/\/$/, "");
      if (!personId) throw new HttpError("BAD_REQUEST", "personId missing in path");
      const data = (await ctx.runQuery(
        makeFunctionReference<"query">("http:_getPersonRoom") as never,
        { ownerId: ostrich.ownerId, personId } as never,
      )) as { person: PersonRow; room: { _id: Id<"chat_rooms"> } | null } | null;
      if (!data) throw new HttpError("BAD_REQUEST", "Person not found");
      let roomId = data.room?._id;
      if (!roomId) {
        roomId = (await ctx.runMutation(
          makeFunctionReference<"mutation">("http:_ensurePersonRoom") as never,
          { ownerId: ostrich.ownerId, personId } as never,
        )) as Id<"chat_rooms">;
      }
      return okResponse({ roomId, person: toPersonDTO(data.person) });
    });
  }),
});

// ────────────── 1.5 日记 ──────────────

http.route({
  path: "/api/diary",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      const url = new URL(request.url);
      const sinceParam = url.searchParams.get("since");
      const limitParam = url.searchParams.get("limit");
      const sinceMs = sinceParam ? Date.parse(sinceParam) : undefined;
      const limit = limitParam ? Math.max(1, parseInt(limitParam, 10) || 20) : 20;
      const entries = (await ctx.runQuery(
        makeFunctionReference<"query">("http:_listDiaryByOstrich") as never,
        {
          ostrichId: ostrich._id,
          sinceMs: Number.isFinite(sinceMs) ? sinceMs : undefined,
          limit,
        } as never,
      )) as DiaryRow[];
      return okResponse({ entries: entries.map(toDiaryDTO) });
    });
  }),
});

http.route({
  path: "/api/diary/requestUnlock",
  method: "POST",
  handler: httpActionGeneric(async (_ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      const body = await parseJsonBody<{ diaryEntryId?: string }>(request);
      if (typeof body.diaryEntryId !== "string") {
        throw new HttpError("BAD_REQUEST", "Missing diaryEntryId");
      }
      // Phase 1：固定 pending（真实策略留 Phase 2）
      return okResponse({ status: "pending" });
    });
  }),
});

// ────────────── 1.6 地图 ──────────────

http.route({
  path: "/api/map/godView",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      const cells = (await ctx.runQuery(
        makeFunctionReference<"query">("http:_listMapCells") as never,
        {} as never,
      )) as Array<{
        cellId: string;
        ostrichIds: string[];
      }>;
      // 解析 query 参数（可选过滤；demo 阶段不实际地理过滤）
      const url = new URL(request.url);
      const latStr = url.searchParams.get("lat");
      const lngStr = url.searchParams.get("lng");
      const lat = latStr ? parseFloat(latStr) : 0;
      const lng = lngStr ? parseFloat(lngStr) : 0;
      return okResponse({
        cells: cells.map((c) => ({
          cellId: c.cellId,
          centerLat: lat,
          centerLng: lng,
          ostrichCount: c.ostrichIds.length,
        })),
      });
    });
  }),
});

http.route({
  path: "/api/map/localView",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    return withErrorEnvelope(async () => {
      const ostrich = await loadCurrentOstrich(ctx, request);
      const ostrichPoint = {
        ostrichId: ostrich._id,
        lat: ostrich.currentLocation.lat,
        lng: ostrich.currentLocation.lng,
        activity: ostrich.currentActivity,
      };
      return okResponse({
        ostrich: ostrichPoint,
        nearby: [],
        route: undefined,
      });
    });
  }),
});

// ────────────── 1.7 设置 / 「如果有一天我不在了」 ──────────────
// Phase 1：占位返回 { ok: true }，不实做。

http.route({
  path: "/api/settings/sealOstrichInEgg",
  method: "POST",
  handler: httpActionGeneric(async (_ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      await parseJsonBody(request);
      return okResponse({ ok: true });
    });
  }),
});

http.route({
  path: "/api/settings/release",
  method: "POST",
  handler: httpActionGeneric(async (_ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      await parseJsonBody(request);
      return okResponse({ ok: true });
    });
  }),
});

http.route({
  path: "/api/settings/transfer",
  method: "POST",
  handler: httpActionGeneric(async (_ctx, request) => {
    return withErrorEnvelope(async () => {
      requireAuth(request);
      await parseJsonBody(request);
      return okResponse({ ok: true });
    });
  }),
});

export default http;
