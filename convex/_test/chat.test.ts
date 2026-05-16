// chat + awakenOstrich vitest 用例。
// - mock @anthropic-ai/sdk，所以测试不会发真请求。
// - 用 convex-test 在 in-memory backend 上 exercise mutation/action。

import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import type { GenericId as Id } from "convex/values";
import { afterEach, describe, expect, it, vi } from "vitest";
import schema from "../schema";

// vite's import.meta.glob 类型本地最小声明，避免引入 @types/vite 依赖。
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

type SendResult = {
  messageId: string;
  ostrichReply: { id: string; content: string; createdAt: number };
  toolCalls: Array<{ toolName: string; args: Record<string, unknown> }>;
};

// convex-test 的 ctx.db.get 在没法从 Id<TableName> 自动 narrow 时返回所有表的 union，
// 这里用一个最小 helper 把返回 cast 成对应表的 document 形状。
// 仅用于测试断言，不影响生产代码。
type DocOf<T extends string> = T extends "ostriches"
  ? {
      _id: Id<"ostriches">;
      ownerId: Id<"users">;
      eggType: number;
      name: string;
      state: string;
      personality: { eggId: number; archetype: string; traits: string[]; speakingStyle: string; skill: string };
      currentLocation: { lat: number; lng: number; friendlyName: string };
    }
  : T extends "users"
    ? {
        _id: Id<"users">;
        name: string;
        appleId: string;
        mbti?: string;
        zodiac?: string;
        ostrichId?: Id<"ostriches">;
      }
    : T extends "chat_rooms"
      ? { _id: Id<"chat_rooms">; type: string; ownerId: Id<"users"> }
      : T extends "messages"
        ? {
            _id: Id<"messages">;
            roomId: Id<"chat_rooms">;
            sender: string;
            senderId: string;
            content: string;
            metadata: {
              toolCalls?: Array<{
                toolName: string;
                args: unknown;
                pendingPersonId?: Id<"pending_persons">;
              }>;
            };
          }
        : T extends "pending_persons"
          ? {
              _id: Id<"pending_persons">;
              ownerId: Id<"users">;
              ostrichId: Id<"ostriches">;
              name: string;
              aliases: string[];
              categoryHint?: string;
              notes?: string;
              createdAt: number;
              expiresAt: number;
            }
          : T extends "memories"
            ? {
                _id: Id<"memories">;
                ostrichId: Id<"ostriches">;
                content: string;
                importance: number;
                visibility: string;
              }
            : never;

async function getAs<T extends "ostriches" | "users" | "chat_rooms" | "messages" | "pending_persons" | "memories">(
  ctx: { db: { get: (id: Id<T>) => Promise<unknown> } },
  id: Id<T>,
): Promise<DocOf<T> | null> {
  return (await ctx.db.get(id)) as DocOf<T> | null;
}

// ─────────────────────────────────────────────────────────────
// mock @anthropic-ai/sdk
// 通过 mockCreate 闭包变量切换不同响应（普通文本 / 包含 tool_use）
// ─────────────────────────────────────────────────────────────

const mockCreate = vi.fn();

vi.mock("@anthropic-ai/sdk", () => {
  return {
    default: class Anthropic {
      messages = { create: mockCreate };
      constructor(_opts?: unknown) {}
    },
  };
});

// convex-test 需要拿到所有 convex/ 函数模块 + 至少一个 _generated/ 下的文件以定位 modules root。
// 用 import.meta.glob 抓 .ts (生产函数) + .js (_generated stub) 两种扩展。
const modules = import.meta.glob("../**/*.{ts,js}");

function makeT() {
  return convexTest(schema, modules);
}

afterEach(() => {
  mockCreate.mockReset();
  delete process.env.ANTHROPIC_API_KEY;
});

// ─────────────────────────────────────────────────────────────
// awakenOstrich
// ─────────────────────────────────────────────────────────────

describe("awakenOstrich", () => {
  it("创建 user / ostrich / 主传心室 / 第一条 hardcoded 鸵鸟消息", async () => {
    const t = makeT();
    const result = (await t.mutation(
      makeFunctionReference<"mutation">("ostriches:awakenOstrich"),
      {
        eggType: 1,
        name: "柱子",
        userMbti: "INFP",
        userZodiac: "巨蟹座",
        userName: "诗枫",
      },
    )) as AwakenResult;

    expect(result.ostrichId).toBeTruthy();
    expect(result.mainRoomId).toBeTruthy();
    expect(result.firstMessageId).toBeTruthy();

    // 直接拨数据库做断言
    await t.run(async (ctx) => {
      const ostrich = await getAs(ctx, result.ostrichId);
      expect(ostrich?.name).toBe("柱子");
      expect(ostrich?.eggType).toBe(1);
      expect(ostrich?.state).toBe("awake");
      expect(ostrich?.personality.archetype).toBe("STEADFAST");
      expect(ostrich?.currentLocation.friendlyName).toBe("涩谷");

      const owner = await getAs(ctx, ostrich!.ownerId);
      expect(owner?.ostrichId).toBe(result.ostrichId);
      expect(owner?.mbti).toBe("INFP");
      expect(owner?.zodiac).toBe("巨蟹座");
      expect(owner?.name).toBe("诗枫");

      const room = await getAs(ctx, result.mainRoomId);
      expect(room?.type).toBe("main");

      const firstMessage = await getAs(ctx, result.firstMessageId);
      expect(firstMessage?.sender).toBe("ostrich");
      expect(firstMessage?.content).toBe("你为什么给我起这个名字？");
      expect(firstMessage?.roomId).toBe(result.mainRoomId);
    });
  });

  it("拒绝非法 eggType", async () => {
    const t = makeT();
    await expect(
      t.mutation(
        makeFunctionReference<"mutation">("ostriches:awakenOstrich"),
        {
          eggType: 17,
          name: "柱子",
          userMbti: "INFP",
          userZodiac: "巨蟹座",
        },
      ),
    ).rejects.toThrow(/Invalid eggType/);
  });
});

// ─────────────────────────────────────────────────────────────
// sendMessage · happy path
// ─────────────────────────────────────────────────────────────

describe("sendMessage", () => {
  it("happy path: 写 user message + 调 claude + 写 ostrich reply", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";

    mockCreate.mockResolvedValueOnce({
      content: [
        {
          type: "text",
          text: "嗯。我记得你说过这个名字。",
        },
      ],
      usage: { input_tokens: 120, output_tokens: 30 },
    });

    const t = makeT();
    const awaken = (await t.mutation(
      makeFunctionReference<"mutation">("ostriches:awakenOstrich"),
      {
        eggType: 1,
        name: "柱子",
        userMbti: "INFP",
        userZodiac: "巨蟹座",
        userName: "诗枫",
      },
    )) as AwakenResult;

    const result = (await t.action(
      makeFunctionReference<"action">("chat:sendMessage"),
      {
        roomId: awaken.mainRoomId,
        content: "因为我喜欢柱子的稳。",
      },
    )) as SendResult;

    expect(result.messageId).toBeTruthy();
    expect(result.ostrichReply.content).toBe("嗯。我记得你说过这个名字。");
    expect(result.toolCalls).toEqual([]);

    // mock 被调用，且 system prompt 含五层标记
    expect(mockCreate).toHaveBeenCalledTimes(1);
    const callArgs = mockCreate.mock.calls[0][0];
    expect(callArgs.model).toBe("claude-sonnet-4-7");
    expect(typeof callArgs.system).toBe("string");
    expect(callArgs.system).toContain("Layer 3");
    expect(callArgs.system).toContain("柱子");
    expect(callArgs.system).toContain("INFP");
    // history 包含先前 hardcoded 的鸵鸟 first message + 当前 user message
    expect(callArgs.messages.length).toBeGreaterThanOrEqual(2);
    expect(callArgs.messages.at(-1)).toEqual({
      role: "user",
      content: "因为我喜欢柱子的稳。",
    });

    // 房间里现在应该有 3 条消息：首句 + user + ostrich
    await t.run(async (ctx) => {
      const all = await ctx.db
        .query("messages")
        .withIndex("by_room_time", (q) => q.eq("roomId", awaken.mainRoomId))
        .collect();
      expect(all.length).toBe(3);
      expect(all[0].sender).toBe("ostrich");
      expect(all[0].content).toBe("你为什么给我起这个名字？");
      expect(all[1].sender).toBe("user");
      expect(all[2].sender).toBe("ostrich");
      expect(all[2].content).toBe("嗯。我记得你说过这个名字。");
    });
  });

  it("note_person 工具触发 → 写入 pending_persons", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";

    mockCreate.mockResolvedValueOnce({
      content: [
        { type: "text", text: "你妈妈。我想把她记下来，可以吗？" },
        {
          type: "tool_use",
          id: "tu_1",
          name: "note_person",
          input: {
            name: "妈妈",
            hint: "用户提到母亲让他窒息",
            suggestedCategory: "family",
            emotionalContext: "矛盾",
          },
        },
      ],
      usage: { input_tokens: 200, output_tokens: 50 },
    });

    const t = makeT();
    const awaken = (await t.mutation(
      makeFunctionReference<"mutation">("ostriches:awakenOstrich"),
      {
        eggType: 1,
        name: "柱子",
        userMbti: "INFP",
        userZodiac: "巨蟹座",
        userName: "诗枫",
      },
    )) as AwakenResult;

    const result = (await t.action(
      makeFunctionReference<"action">("chat:sendMessage"),
      {
        roomId: awaken.mainRoomId,
        content: "我妈又开始了……",
      },
    )) as SendResult;

    expect(result.toolCalls).toHaveLength(1);
    expect(result.toolCalls[0].toolName).toBe("note_person");

    await t.run(async (ctx) => {
      const pending = await ctx.db
        .query("pending_persons")
        .withIndex("by_owner", (q) => q.eq("ownerId", awaken.ownerId))
        .collect();
      expect(pending.length).toBe(1);
      expect(pending[0].name).toBe("妈妈");
      expect(pending[0].categoryHint).toBe("family");
      expect(pending[0].notes).toBe("用户提到母亲让他窒息");
      expect(pending[0].expiresAt).toBeGreaterThan(pending[0].createdAt);

      // ostrich message metadata 里也带 toolCall + pendingPersonId
      const messages = await ctx.db
        .query("messages")
        .withIndex("by_room_time", (q) => q.eq("roomId", awaken.mainRoomId))
        .collect();
      const ostrichMessage = messages[messages.length - 1];
      expect(ostrichMessage.metadata.toolCalls?.[0].toolName).toBe(
        "note_person",
      );
      expect(ostrichMessage.metadata.toolCalls?.[0].pendingPersonId).toBe(
        pending[0]._id,
      );
    });
  });

  it("remember 工具触发 → 写入 memories", async () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";

    mockCreate.mockResolvedValueOnce({
      content: [
        { type: "text", text: "我记下了。" },
        {
          type: "tool_use",
          id: "tu_1",
          name: "remember",
          input: {
            content: "用户喜欢黑咖啡。",
            importance: 0.7,
            visibility: "normal",
            relatedPersonIds: [],
          },
        },
      ],
      usage: { input_tokens: 50, output_tokens: 20 },
    });

    const t = makeT();
    const awaken = (await t.mutation(
      makeFunctionReference<"mutation">("ostriches:awakenOstrich"),
      {
        eggType: 1,
        name: "柱子",
        userMbti: "INFP",
        userZodiac: "巨蟹座",
      },
    )) as AwakenResult;

    await t.action(
      makeFunctionReference<"action">("chat:sendMessage"),
      { roomId: awaken.mainRoomId, content: "我只喝黑咖啡。" },
    );

    await t.run(async (ctx) => {
      const memories = await ctx.db
        .query("memories")
        .withIndex("by_ostrich", (q) => q.eq("ostrichId", awaken.ostrichId))
        .collect();
      expect(memories.length).toBe(1);
      expect(memories[0].content).toBe("用户喜欢黑咖啡。");
      expect(memories[0].importance).toBeCloseTo(0.7, 5);
      expect(memories[0].visibility).toBe("normal");
    });
  });
});
