import { resolve } from "node:path";

import { defineConfig } from "vitest/config";

export default defineConfig({
  // The same "@/" alias vite.config.ts defines. Repeated rather than imported
  // because vite.config.ts pulls in plugins that have no business running in a
  // test process, and a test that cannot resolve the app's own imports is a
  // test suite that can only ever cover leaf modules.
  resolve: {
    alias: { "@": resolve(__dirname, "./src") },
  },
  test: {
    // jsdom, not node: the collector reads window, navigator and localStorage,
    // and stubbing all three by hand would be testing the stubs.
    environment: "jsdom",
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
  },
});
