// Apple Maps Server API · JWT + access token 管理
//
// 流程（BLUEPRINT §16.1 #2 + Apple 官方文档）：
//   1. 用 .p8 私钥 + Key ID + Team ID 生成 ES256 JWT（30 分钟 TTL）
//   2. GET https://maps-api.apple.com/v1/token  Authorization: Bearer <JWT>
//      → 返回 { accessToken, expiresInSeconds }
//   3. 后续 /v1/* 调用带 Authorization: Bearer <access_token>
//
// access token 在模块作用域内缓存，到期前 1 分钟才主动刷新；
// 这样多次连续调用 Apple Maps 不会反复换 token，节省配额。

import { SignJWT, importPKCS8 } from "jose";

interface CachedToken {
  token: string;
  expiresAt: number; // ms epoch
}

let cachedToken: CachedToken | null = null;

/**
 * 解码 env 中的私钥。
 *
 * 支持两种填写格式（自动判断）：
 *   - 原始 PEM：包含 `-----BEGIN PRIVATE KEY-----` 头
 *   - base64 编码的 PEM：把整段 PEM 用 base64 包了一层（便于单行写入 env）
 *
 * 兼容两种是因为 Convex env UI 在某些 case 下对多行字符串不友好，
 * 让运维侧可以二选一。
 */
export function decodePrivateKey(raw: string): string {
  if (raw.includes("BEGIN PRIVATE KEY")) {
    return raw;
  }
  // 假设是 base64(PEM)
  try {
    const decoded = Buffer.from(raw, "base64").toString("utf-8");
    if (decoded.includes("BEGIN PRIVATE KEY")) {
      return decoded;
    }
  } catch {
    // fallthrough
  }
  throw new Error(
    "APPLE_MAPS_PRIVATE_KEY: expected PEM (contains '-----BEGIN PRIVATE KEY-----') " +
      "or base64-encoded PEM, got neither.",
  );
}

/**
 * 生成 ES256 JWT，用于换 Apple Maps access token。
 *
 * Apple 要求 header `{ alg: "ES256", kid: <KeyID>, typ: "JWT" }`
 * 和 payload `{ iss: <TeamID>, iat, exp }`，exp ≤ iat + 30min。
 */
async function makeAuthToken(): Promise<string> {
  const keyId = process.env.APPLE_MAPS_KEY_ID;
  const teamId = process.env.APPLE_MAPS_TEAM_ID;
  const pemRaw = process.env.APPLE_MAPS_PRIVATE_KEY;
  if (!keyId || !teamId || !pemRaw) {
    throw new Error(
      "APPLE_MAPS_KEY_ID / APPLE_MAPS_TEAM_ID / APPLE_MAPS_PRIVATE_KEY env not configured",
    );
  }
  const pem = decodePrivateKey(pemRaw);
  const privateKey = await importPKCS8(pem, "ES256");
  const now = Math.floor(Date.now() / 1000);

  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId, typ: "JWT" })
    .setIssuer(teamId)
    .setIssuedAt(now)
    .setExpirationTime(now + 30 * 60) // 30 min
    .sign(privateKey);
}

/**
 * 拿到当前可用的 Apple Maps access token。
 *
 * 缓存策略：到过期前 60 秒之内才会主动换新；同进程并发调用复用同一个 token。
 */
export async function getAccessToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) {
    return cachedToken.token;
  }
  const authToken = await makeAuthToken();
  const res = await fetch("https://maps-api.apple.com/v1/token", {
    headers: { Authorization: `Bearer ${authToken}` },
  });
  if (!res.ok) {
    throw new Error(`Apple Maps token exchange failed: ${res.status} ${res.statusText}`);
  }
  const data = (await res.json()) as {
    accessToken: string;
    expiresInSeconds: number;
  };
  cachedToken = {
    token: data.accessToken,
    expiresAt: now + data.expiresInSeconds * 1000,
  };
  return data.accessToken;
}

/** 仅供单测重置缓存使用。 */
export function _resetAccessTokenCacheForTest(): void {
  cachedToken = null;
}

/** 仅供单测窥探缓存状态。 */
export function _peekAccessTokenCacheForTest(): CachedToken | null {
  return cachedToken;
}
