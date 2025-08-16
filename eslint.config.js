export default [
  {
    ignores: ["build/**", "dist/**", "coverage/**", "logs/**", "node_modules/**", ".quarantine/**"],
  },
  {
    files: ["**/*.js", "**/*.mjs", "**/*.ts"],
    languageOptions: {
      ecmaVersion: 2021,
      sourceType: "module",
      globals: {
        console: "readonly",
        process: "readonly",
        Buffer: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        exports: "writable",
        module: "writable",
        require: "readonly",
        global: "readonly",
        URL: "readonly"
      }
    },
    rules: {
      "no-unused-vars": ["warn", { "argsIgnorePattern": "^_" }],
      "no-console": "off",
      "semi": ["error", "always", { "omitLastInOneLineBlock": true }]
    }
  }
];