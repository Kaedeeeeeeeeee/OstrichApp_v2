import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "edge-runtime",
    server: { deps: { inline: ["convex-test"] } },
    include: ["convex/_test/**/*.test.ts"],
    globalSetup: ["./convex/_test/global-setup.ts"],
  },
});
