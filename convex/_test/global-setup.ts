// vitest globalSetup hook · 在所有测试前确保 convex/_generated 目录存在。
//
// convex-test 需要 import.meta.glob 能匹配到 `**/_generated/**` 的文件来定位 modules root。
// 仓库不提交 convex/_generated/（依赖真实 codegen），所以我们在 CI / 本地测试前生成一个
// 最小 stub，让 convex-test 能正常工作。
//
// 我们用 makeFunctionReference 而非 _generated/api 来引用函数，所以 stub 内容是空对象就够。

import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

export default function setup(): void {
  const here = dirname(fileURLToPath(import.meta.url));
  const generatedDir = join(here, "..", "_generated");
  if (!existsSync(generatedDir)) {
    mkdirSync(generatedDir, { recursive: true });
  }
  const apiStub = join(generatedDir, "api.js");
  if (!existsSync(apiStub)) {
    writeFileSync(
      apiStub,
      `// Auto-generated stub for convex-test (see convex/_test/global-setup.ts).
// Real _generated/api.js is created by \`npx convex codegen\`.
export const api = {};
export const internal = {};
`,
    );
  }
}
