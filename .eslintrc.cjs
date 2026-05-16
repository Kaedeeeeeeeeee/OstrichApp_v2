// ESLint 配置 —— Convex TS 风格 lint。
// 用 @typescript-eslint/recommended 兜底，prettier 兼容关闭格式冲突。
// 注意：强类型规则（no-explicit-any / explicit-function-return-type 等）刻意 off，
// 避免影响 Convex codegen / generic helpers 的写法。

module.exports = {
  root: true,
  parser: "@typescript-eslint/parser",
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: "module",
  },
  plugins: ["@typescript-eslint"],
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "prettier",
  ],
  env: {
    node: true,
    es2022: true,
  },
  ignorePatterns: [
    "node_modules/",
    "**/_generated/**",
    "ios/**",
    "*.lock",
    "pnpm-lock.yaml",
    ".github/**",
  ],
  rules: {
    // Convex 经常需要 any / generic 占位
    "@typescript-eslint/no-explicit-any": "off",
    "@typescript-eslint/explicit-function-return-type": "off",
    "@typescript-eslint/explicit-module-boundary-types": "off",
    "@typescript-eslint/no-unused-vars": [
      "warn",
      { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
    ],
    "no-console": "off",
  },
};
