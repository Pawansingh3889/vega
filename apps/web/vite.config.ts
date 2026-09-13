import { defineConfig, loadEnv, type Plugin } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

import { devOrigins, widenConnectSrc } from "./src/lib/devCsp";

// index.html carries its own <meta http-equiv="Content-Security-Policy">,
// the shipped production policy, SEPARATE from the response header this file
// sets on the dev server below. A page with both gets the INTERSECTION of the
// two: the browser enforces whichever list is narrower for each directive. So
// widening the header alone (#135) does nothing while the meta tag stays
// narrow: every local API call died as a bare "TypeError: Failed to fetch"
// with no CSP violation logged anywhere the app's own code could see, because
// the browser refuses the connection before fetch() gets an event to report.
//
// The widening logic itself lives in src/lib/devCsp.ts, as plain functions
// rather than inline here, because vite.config.ts is not covered by
// vitest.config.ts's include globs and a regex bug in an untestable file is
// exactly what caused this: the previous version's pattern matched an HTML
// COMMENT above the tag instead of the tag itself, and nothing here could
// have caught that short of running the dev server and reading the response.
// See devCsp.ts for the full account of both bugs.
function widenDevCspMeta(supabaseUrl: string, apiUrl: string | undefined): Plugin {
  return {
    name: "dev-csp-allow-local-origins",
    transformIndexHtml(html) {
      return widenConnectSrc(html, devOrigins(supabaseUrl, apiUrl));
    },
  };
}

// The dev server's Content-Security-Policy.
//
// Only the API origin varies, and only its ORIGIN is taken: a full URL with a
// path in it is not a valid connect-src source and would silently invalidate
// the directive it sits in.
function devCsp(apiUrl: string | undefined): string {
  const sources = [
    "'self'",
    "https://kscgvfzzzbmqohuuiiab.supabase.co",
    "wss://kscgvfzzzbmqohuuiiab.supabase.co",
  ];
  if (apiUrl) {
    try {
      sources.push(new URL(apiUrl).origin);
    } catch {
      // An unparseable VITE_API_URL is the deployment's problem to fix, and
      // the app's own `required()` check reports it far better than a mangled
      // header would. Leaving it out keeps the policy valid meanwhile.
    }
  }
  return [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "font-src 'self' data:",
    `connect-src ${sources.join(" ")}`,
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "object-src 'none'",
  ].join("; ");
}

export default defineConfig(({ mode }) => {
  // The repository root, because that is where the documented .env lives.
  //
  // CONTRIBUTING tells you to copy .env.example to .env, and .env.example sits
  // at the root. Vite loads env from its own root, apps/web, so the file the
  // docs tell you to write was never read: `pnpm dev` served a blank white
  // page whose only explanation was a console line nobody thinks to open.
  // Following the setup instructions exactly is the case that has to work.
  const envDir = path.resolve(__dirname, "../..");
  const env = loadEnv(mode, envDir, "");

  return {
    // Not only for loadEnv above. This is what makes vite EXPOSE the vars to
    // the client as import.meta.env; without it the config could read .env
    // while the app still saw nothing, which is exactly the blank page this
    // change is fixing.
    envDir,
    server: {
      host: "::",
      port: 8080,
      headers: {
        // connect-src carries the configured API origin rather than a fixed
        // localhost:8000. The port is configuration, so hardcoding one meant
        // any other value was blocked by this policy before the request left
        // the browser, which reads as the API being down rather than as a
        // policy refusal. This header is the DEV server's only; the shipped
        // policy is in index.html and is untouched.
        "Content-Security-Policy": devCsp(env.VITE_API_URL),
      },
    },
    plugins: [
      react(),
      mode === "development" && widenDevCspMeta(env.VITE_SUPABASE_URL ?? "", env.VITE_API_URL),
    ].filter(Boolean),
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
      },
    },
  };
});

