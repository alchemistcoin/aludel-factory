module.exports = {
  env: { node: true },
  extends: ["eslint:recommended", "plugin:@typescript-eslint/recommended"],
  parser: "@typescript-eslint/parser",
  plugins: ["@typescript-eslint", "prettier", "mocha"],
  rules: {
    "prettier/prettier": "error",
    "mocha/no-skipped-tests": "error",
    "mocha/no-exclusive-tests": "error",
  },
  root: true,
};
