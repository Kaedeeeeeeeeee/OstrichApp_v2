import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "edge-runtime",
    server: { deps: { inline: ["convex-test"] } },
    include: ["tests/convex/**/*.test.ts"],
    globalSetup: ["./tests/convex/global-setup.ts"],
  },
});
