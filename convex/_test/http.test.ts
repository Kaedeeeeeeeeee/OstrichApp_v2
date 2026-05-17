// http.ts vitest 用例。
// 用 convex-test 的 t.fetch 触发 httpRouter，断言：
//   - 鉴权 header 缺失 / 错误 → 401
//   - happy paths: /api/awaken, /api/chat/send, /api/ostrich/self
//   - 错误码 → 对应 HTTP status (404 / 409 / etc.)

import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import type { GenericId as Id } from "convex/values";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import schema from "../schema";

declare global {
  interface ImportMeta {
    glob: (pattern: string) => Record<string, () => Promise<unknown>>;
  }
}

type AwakenResult = {
  ostrichId: Id<"ostriches">;
  mainRoomId: Id<"chat_rooms">;
  firstMessageId: Id<"messages">;
  ownerId: Id<"users">;
};

const MOCK_TOKEN = "demo-session-token";
const AUTH_HEADER = `Bearer ${MOCK_TOKEN}`;

const mockCreate = vi.fn();

vi.mock("@anthropic-ai/sdk", () => {
  return {
    default: class Anthropic {
      messages = { create: mockCreate };
      constructor(_opts?: unknown) {}
    },
  };
});

const modules = import.meta.glob("../**/*.{ts,js}");

function makeT() {
  return convexTest(schema, modules);
}

async function jsonOk<T = unknown>(resp: Response): Promise<{ ok: true; data: T }> {
  const body = (await resp.json()) as { ok: true; data: T };
  return body;
}

async function jsonErr(
  resp: Response,
): Promise<{ ok: false; error: { code: string; message: string } }> {
  return (await resp.json()) as { ok: false; error: { code: string; message: string } };
}

beforeEach(() => {
  process.env.ANTHROPIC_API_KEY = "sk-test-key";
});

afterEach(() => {
  mockCreate.mockReset();
  delete process.env.ANTHROPIC_API_KEY;
});

// ─────────────────────────────────────────────────────────────
// 鉴权
// ─────────────────────────────────────────────────────────────

describe("auth", () => {
  it("无 Authorization header → 401 AUTH_REQUIRED", async () => {
    const t = makeT();
    const resp = await t.fetch("/api/ostrich/self", { method: "GET" });
    expect(resp.status).toBe(401);
    const body = await jsonErr(resp);
    expect(body.ok).toBe(false);
    expect(body.error.code).toBe("AUTH_REQUIRED");
  });

  it("错误 token → 401 AUTH_INVALID", async () => {
    const t = makeT();
    const resp = await t.fetch("/api/ostrich/self", {
      method: "GET",
      headers: { Authorization: "Bearer wrong-token" },
    });
    expect(resp.status).toBe(401);
    const body = await jsonErr(resp);
    expect(body.error.code).toBe("AUTH_INVALID");
  });

  it("signInWithApple 返回 mock session token", async () => {
    const t = makeT();
    const resp = await t.fetch("/api/auth/signInWithApple", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ identityToken: "x", nonce: "y" }),
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{ sessionToken: string; isNewUser: boolean }>(resp);
    expect(body.data.sessionToken).toBe(MOCK_TOKEN);
    expect(body.data.isNewUser).toBe(true);
  });

  it("signOut 需要鉴权", async () => {
    const t = makeT();
    const noAuth = await t.fetch("/api/auth/signOut", { method: "POST" });
    expect(noAuth.status).toBe(401);
    const ok = await t.fetch("/api/auth/signOut", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER },
    });
    expect(ok.status).toBe(200);
  });
});

// ─────────────────────────────────────────────────────────────
// awaken happy path + ostrich/self
// ─────────────────────────────────────────────────────────────

describe("/api/awaken + /api/ostrich/self", () => {
  it("awaken 返回 OstrichDTO", async () => {
    const t = makeT();
    const resp = await t.fetch("/api/awaken", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({
        eggType: 1,
        name: "柱子",
        userMbti: "INFP",
        userZodiac: "巨蟹座",
        userName: "诗枫",
      }),
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{
      id: string;
      name: string;
      eggType: number;
      archetype: string;
      awakenedAt: string;
      state: string;
      currentLocation: { friendlyName: string };
      daysTogether: number;
    }>(resp);
    expect(body.data.name).toBe("柱子");
    expect(body.data.eggType).toBe(1);
    expect(body.data.archetype).toBe("STEADFAST");
    expect(body.data.state).toBe("awake");
    expect(body.data.currentLocation.friendlyName).toBe("涩谷");
    expect(body.data.daysTogether).toBeGreaterThanOrEqual(0);
    // ISO8601
    expect(() => new Date(body.data.awakenedAt).toISOString()).not.toThrow();
  });

  it("awaken 非法 eggType → 400 BAD_REQUEST", async () => {
    const t = makeT();
    const resp = await t.fetch("/api/awaken", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({
        eggType: 17,
        name: "x",
        userMbti: "x",
        userZodiac: "x",
      }),
    });
    expect(resp.status).toBe(400);
    const body = await jsonErr(resp);
    expect(body.error.code).toBe("BAD_REQUEST");
  });

  it("/api/ostrich/self 没鸵鸟 → 404", async () => {
    const t = makeT();
    const resp = await t.fetch("/api/ostrich/self", {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    expect(resp.status).toBe(404);
    const body = await jsonErr(resp);
    expect(body.error.code).toBe("OSTRICH_NOT_FOUND");
  });

  it("/api/ostrich/self happy path", async () => {
    const t = makeT();
    await t.fetch("/api/awaken", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({
        eggType: 2,
        name: "豆豆",
        userMbti: "ENFP",
        userZodiac: "射手座",
      }),
    });
    const resp = await t.fetch("/api/ostrich/self", {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{ name: string; eggType: number }>(resp);
    expect(body.data.name).toBe("豆豆");
    expect(body.data.eggType).toBe(2);
  });
});

// ─────────────────────────────────────────────────────────────
// callHome 状态机
// ─────────────────────────────────────────────────────────────

describe("/api/ostrich/callHome", () => {
  it("happy path → accepted=true 且鸵鸟 state=called_home", async () => {
    const t = makeT();
    const awakenResp = await t.fetch("/api/awaken", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({
        eggType: 1,
        name: "柱子",
        userMbti: "INFP",
        userZodiac: "巨蟹座",
      }),
    });
    const awakenBody = await jsonOk<{ id: string }>(awakenResp);

    const resp = await t.fetch("/api/ostrich/callHome", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({}),
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{ accepted: boolean }>(resp);
    expect(body.data.accepted).toBe(true);

    await t.run(async (ctx) => {
      const o = (await ctx.db.get(awakenBody.data.id as Id<"ostriches">)) as {
        state: string;
      } | null;
      expect(o?.state).toBe("called_home");
    });
  });

  it("鸵鸟 sleeping_in_egg → 409 OSTRICH_SLEEPING", async () => {
    const t = makeT();
    const awakenResp = await t.fetch("/api/awaken", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({
        eggType: 3,
        name: "x",
        userMbti: "x",
        userZodiac: "x",
      }),
    });
    const awakenBody = await jsonOk<{ id: string }>(awakenResp);

    // 手动把鸵鸟扔回蛋里
    await t.run(async (ctx) => {
      await ctx.db.patch(awakenBody.data.id as Id<"ostriches">, {
        state: "sleeping_in_egg",
      });
    });

    const resp = await t.fetch("/api/ostrich/callHome", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({}),
    });
    expect(resp.status).toBe(409);
    const body = await jsonErr(resp);
    expect(body.error.code).toBe("OSTRICH_SLEEPING");
  });
});

// ─────────────────────────────────────────────────────────────
// chat/send + chat/room/:roomId
// ─────────────────────────────────────────────────────────────

describe("/api/chat/send + /api/chat/room/:roomId", () => {
  it("happy path", async () => {
    mockCreate.mockResolvedValueOnce({
      content: [{ type: "text", text: "嗯。" }],
      usage: { input_tokens: 10, output_tokens: 5 },
    });

    const t = makeT();
    // 1) awaken
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
      userName: "诗枫",
    })) as AwakenResult;

    // 2) send
    const resp = await t.fetch("/api/chat/send", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({ roomId: awaken.mainRoomId, content: "hi" }),
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{
      messageId: string;
      ostrichReply: { content: string; createdAt: string };
      toolCalls: unknown[];
    }>(resp);
    expect(body.data.ostrichReply.content).toBe("嗯。");
    expect(body.data.toolCalls).toEqual([]);
    expect(() => new Date(body.data.ostrichReply.createdAt).toISOString()).not.toThrow();
  });

  it("鸵鸟 wandering → 409 OSTRICH_WANDERING", async () => {
    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    await t.run(async (ctx) => {
      await ctx.db.patch(awaken.ostrichId, { state: "wandering" });
    });

    const resp = await t.fetch("/api/chat/send", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({ roomId: awaken.mainRoomId, content: "hi" }),
    });
    expect(resp.status).toBe(409);
    const body = await jsonErr(resp);
    expect(body.error.code).toBe("OSTRICH_WANDERING");
  });

  it("/api/chat/room/:roomId 返回房间消息", async () => {
    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    const resp = await t.fetch(`/api/chat/room/${awaken.mainRoomId}`, {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{
      messages: Array<{ sender: string; content: string }>;
      hasMore: boolean;
    }>(resp);
    expect(body.data.messages.length).toBe(1);
    expect(body.data.messages[0].sender).toBe("ostrich");
    expect(body.data.messages[0].content).toBe("你为什么给我起这个名字？");
    expect(body.data.hasMore).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────
// graph / diary / map / settings
// ─────────────────────────────────────────────────────────────

describe("/api/graph", () => {
  it("空图谱返回 people/edges 空数组", async () => {
    const t = makeT();
    await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    });

    const resp = await t.fetch("/api/graph", {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{ people: unknown[]; edges: unknown[] }>(resp);
    expect(body.data.people).toEqual([]);
    expect(body.data.edges).toEqual([]);
  });

  it("有 person 时返回 PersonDTO + 自连 edge", async () => {
    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    let personId: Id<"people"> | null = null;
    await t.run(async (ctx) => {
      personId = await ctx.db.insert("people", {
        ownerId: awaken.ownerId,
        name: "妈妈",
        aliases: [],
        category: "family",
        closeness: 0.7,
        recentInteractionCount: 3,
        notes: "",
        hasOstrich: false,
        createdAt: Date.now(),
        lastMentionedAt: Date.now(),
      });
    });

    const resp = await t.fetch("/api/graph", {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    const body = await jsonOk<{
      people: Array<{ id: string; name: string; category: string; closeness: number }>;
      edges: Array<{ fromPersonId: string; toPersonId: string; weight: number }>;
    }>(resp);
    expect(body.data.people).toHaveLength(1);
    expect(body.data.people[0].name).toBe("妈妈");
    expect(body.data.edges[0].fromPersonId).toBe("self");
    expect(body.data.edges[0].toPersonId).toBe(personId);
    expect(body.data.edges[0].weight).toBeCloseTo(0.7, 5);
  });
});

describe("/api/diary", () => {
  it("返回鸵鸟日记列表", async () => {
    const t = makeT();
    const awaken = (await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    })) as AwakenResult;

    await t.run(async (ctx) => {
      await ctx.db.insert("diary_entries", {
        ostrichId: awaken.ostrichId,
        timestamp: Date.now(),
        content: "今天在涩谷遇到一只鸵鸟。",
        visibility: "visible",
        location: { lat: 35.659, lng: 139.7, friendlyName: "涩谷" },
      });
    });

    const resp = await t.fetch("/api/diary", {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    const body = await jsonOk<{
      entries: Array<{ content: string; visibility: string; location?: { friendlyName: string } }>;
    }>(resp);
    expect(body.data.entries).toHaveLength(1);
    expect(body.data.entries[0].content).toBe("今天在涩谷遇到一只鸵鸟。");
    expect(body.data.entries[0].location?.friendlyName).toBe("涩谷");
  });
});

describe("/api/map/godView + localView", () => {
  it("godView 返回 cells", async () => {
    const t = makeT();
    await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    });
    await t.run(async (ctx) => {
      await ctx.db.insert("map_cells", {
        cellId: "cell-1",
        ostrichIds: [],
        poiIds: [],
        updatedAt: Date.now(),
      });
    });
    const resp = await t.fetch("/api/map/godView?lat=35.6&lng=139.7&radius_m=1000", {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    const body = await jsonOk<{ cells: Array<{ cellId: string; ostrichCount: number }> }>(resp);
    expect(body.data.cells).toHaveLength(1);
    expect(body.data.cells[0].cellId).toBe("cell-1");
    expect(body.data.cells[0].ostrichCount).toBe(0);
  });

  it("localView 返回自己鸵鸟位置", async () => {
    const t = makeT();
    await t.mutation(makeFunctionReference<"mutation">("ostriches:awakenOstrich"), {
      eggType: 1,
      name: "柱子",
      userMbti: "INFP",
      userZodiac: "巨蟹座",
    });
    const resp = await t.fetch("/api/map/localView", {
      method: "GET",
      headers: { Authorization: AUTH_HEADER },
    });
    const body = await jsonOk<{
      ostrich: { lat: number; lng: number; activity: string };
      nearby: unknown[];
    }>(resp);
    expect(body.data.ostrich.activity).toBe("resting");
    expect(body.data.ostrich.lat).toBeCloseTo(35.6595, 4);
    expect(body.data.nearby).toEqual([]);
  });
});

describe("/api/settings/* 占位", () => {
  it("sealOstrichInEgg 返回 ok=true", async () => {
    const t = makeT();
    const resp = await t.fetch("/api/settings/sealOstrichInEgg", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({ password: "pw" }),
    });
    expect(resp.status).toBe(200);
    const body = await jsonOk<{ ok: boolean }>(resp);
    expect(body.data.ok).toBe(true);
  });

  it("release / transfer 同样返回 ok", async () => {
    const t = makeT();
    const r1 = await t.fetch("/api/settings/release", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({ memoryEraseScope: "core" }),
    });
    expect(r1.status).toBe(200);
    const r2 = await t.fetch("/api/settings/transfer", {
      method: "POST",
      headers: { Authorization: AUTH_HEADER, "content-type": "application/json" },
      body: JSON.stringify({ targetUserId: "x", memoryEraseScope: "all_keep" }),
    });
    expect(r2.status).toBe(200);
  });
});
