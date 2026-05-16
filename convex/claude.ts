// Sonnet 4.7 调用包装 + 6 个工具 schema。
// 调用入口：`chat`（internalAction），由 `chat.ts::sendMessage` 触发。
//
// 注: 这里直接用 internalActionGeneric + DataModelFromSchemaDefinition，
// 避免依赖 convex/_generated。当 _generated 生成后可以平滑切换到 `from "./_generated/server"`。

import Anthropic from "@anthropic-ai/sdk";
import {
  internalActionGeneric,
  makeFunctionReference,
  type DataModelFromSchemaDefinition,
  type GenericActionCtx,
} from "convex/server";
import { v, type Infer } from "convex/values";
import schema from "./schema";
import { buildSystemPrompt } from "./lib/prompts";

type DataModel = DataModelFromSchemaDefinition<typeof schema>;
type ActionCtx = GenericActionCtx<DataModel>;

// model id 严格按 BLUEPRINT §1
const SONNET_MODEL = "claude-sonnet-4-7";

// ─────────────────────────────────────────────────────────────
// 工具 schema（INTERFACES §4，命名严格对齐）
// ─────────────────────────────────────────────────────────────

export const ostrichTools = [
  {
    name: "note_person",
    description:
      "当用户在对话中第一次提到一个人物时调用。写入 pending_persons 表，等待用户在下一轮自然语言确认后落 people。不要在用户已经在主题里反复提到同一个人时重复调用。",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: '用户提到的称呼，如 "妈妈"' },
        hint: { type: "string", description: "关于此人的一句话上下文" },
        suggestedCategory: {
          type: "string",
          enum: ["family", "friend", "colleague", "x_person"],
        },
        emotionalContext: { type: "string" },
      },
      required: ["name", "hint", "suggestedCategory"],
    },
  },
  {
    name: "update_person",
    description: "已存在的人物有新动态时更新，或亲密度有显著变化时调用",
    input_schema: {
      type: "object",
      properties: {
        personId: { type: "string" },
        noteToAdd: { type: "string" },
        closenessDelta: { type: "number", description: "范围 -0.2..+0.2" },
      },
      required: ["personId"],
    },
  },
  {
    name: "remember",
    description: "记住一个重要事实。importance 0-1，visibility 决定「如果我不在了」擦除范围",
    input_schema: {
      type: "object",
      properties: {
        content: { type: "string" },
        importance: { type: "number" },
        visibility: { type: "string", enum: ["core", "normal", "redacted"] },
        relatedPersonIds: { type: "array", items: { type: "string" } },
      },
      required: ["content", "importance", "visibility"],
    },
  },
  {
    name: "suggest_reach_out",
    description: "建议用户主动联系关系图谱里的某人。仅在用户表达类似动机时调用，不主动推销",
    input_schema: {
      type: "object",
      properties: {
        personId: { type: "string" },
        suggestedMessage: { type: "string" },
        reason: { type: "string" },
      },
      required: ["personId", "suggestedMessage", "reason"],
    },
  },
  {
    name: "generate_name_card",
    description: "用户在 person_room 想分享给非 App 用户时生成名片图片",
    input_schema: {
      type: "object",
      properties: {
        toPersonId: { type: "string" },
        content: { type: "string" },
      },
      required: ["toPersonId", "content"],
    },
  },
  {
    name: "request_to_stay_wandering",
    description: "仅在用户召回鸵鸟且鸵鸟当前活动有趣时调用，让鸵鸟撒娇请求继续遛弯",
    input_schema: {
      type: "object",
      properties: {
        reason: { type: "string" },
        teaseContent: {
          type: "string",
          description: "勾引用户允许继续的话",
        },
      },
      required: ["reason", "teaseContent"],
    },
  },
] as const;

export type ToolCall = {
  toolName: string;
  args: Record<string, unknown>;
};

// ─────────────────────────────────────────────────────────────
// Anthropic client 创建（每次新建，方便 vi.mock 替换）
// ─────────────────────────────────────────────────────────────

function createClient(): Anthropic {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    throw new Error("ANTHROPIC_API_KEY missing in env");
  }
  return new Anthropic({ apiKey });
}

// ─────────────────────────────────────────────────────────────
// internalAction · chat
// ─────────────────────────────────────────────────────────────

const historyMessageValidator = v.object({
  role: v.union(v.literal("user"), v.literal("assistant")),
  content: v.string(),
});

const chatArgsValidator = {
  ostrichId: v.id("ostriches"),
  userMessage: v.string(),
  history: v.optional(v.array(historyMessageValidator)),
};

export type ChatArgs = {
  ostrichId: string;
  userMessage: string;
  history?: Array<Infer<typeof historyMessageValidator>>;
};

export type ChatResult = {
  text: string;
  toolCalls: ToolCall[];
  usage: { inputTokens: number; outputTokens: number };
};

export const chat = internalActionGeneric({
  args: chatArgsValidator,
  handler: async (ctx: ActionCtx, args): Promise<ChatResult> => {
    // 1. 拉鸵鸟 + owner 用户。Action 不能直接读 db，只能通过 runQuery。
    //    在没有 _generated 的情况下，我们用 makeFunctionReference 引用一个内部 query。
    const profile = (await ctx.runQuery(
      makeFunctionReference<"query">("chat:_loadChatContext") as never,
      { ostrichId: args.ostrichId } as never,
    )) as {
      ostrich: {
        eggType: number;
        name: string;
        awakenedAt: number;
      };
      user: {
        name: string;
        mbti: string;
        zodiac: string;
      };
    };

    const daysTogether = Math.max(
      0,
      Math.floor((Date.now() - profile.ostrich.awakenedAt) / (24 * 60 * 60 * 1000)),
    );

    // 2. 五层 system prompt
    const systemPrompt = buildSystemPrompt({
      eggType: profile.ostrich.eggType,
      userName: profile.user.name,
      userMbti: profile.user.mbti,
      userZodiac: profile.user.zodiac,
      ostrichName: profile.ostrich.name,
      daysTogether,
      graphSummary: undefined, // Phase 1: 关系图谱摘要后续接入
      memories: undefined, // Phase 1: 记忆向量检索后续接入
    });

    // 3. 拼装 messages（按 Anthropic Messages API）
    const messages: Array<{ role: "user" | "assistant"; content: string }> = [];
    for (const h of args.history ?? []) {
      messages.push({ role: h.role, content: h.content });
    }
    messages.push({ role: "user", content: args.userMessage });

    // 4. 调 Sonnet 4.7
    const client = createClient();
    const response = await client.messages.create({
      model: SONNET_MODEL,
      max_tokens: 1024,
      system: systemPrompt,
      tools: ostrichTools as unknown as Anthropic.Tool[],
      messages,
    });

    // 5. 解析回复：text + tool_use blocks
    let text = "";
    const toolCalls: ToolCall[] = [];
    for (const block of response.content) {
      if (block.type === "text") {
        text += block.text;
      } else if (block.type === "tool_use") {
        toolCalls.push({
          toolName: block.name,
          args: (block.input ?? {}) as Record<string, unknown>,
        });
      }
    }

    return {
      text,
      toolCalls,
      usage: {
        inputTokens: response.usage.input_tokens,
        outputTokens: response.usage.output_tokens,
      },
    };
  },
});
