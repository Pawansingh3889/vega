import js from "@eslint/js";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist"] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    plugins: {
      "react-hooks": reactHooks,
      "react-refresh": reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-refresh/only-export-components": [
        "warn",
        { allowConstantExport: true },
      ],
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],

      // Inherited debt, not a standard we chose. The fork carries explicit `any`
      // in the auth stack and a few UI components, mostly `catch (error: any)`.
      // Typing them properly needs an error-narrowing helper across roughly 40
      // call sites in auth code that cannot be exercised until Phase 1 stands up
      // a database, so it travels with the auth work rather than blocking the
      // toolchain.
      //
      // It is a warning, not an exemption. `pnpm lint` runs with --max-warnings
      // pinned to today's count so the total can only go down, and
      // `make debt` prints the breakdown by rule so the debt cannot quietly
      // change shape under a fixed ceiling.
      //
      // Scheduled: ROADMAP Phase 2, with the auth restructure. Once FastAPI owns
      // auth, the generated OpenAPI client types the error envelope, so these
      // handlers get typed as a side effect instead of by hand.
      "@typescript-eslint/no-explicit-any": "warn",
    },
  }
);
