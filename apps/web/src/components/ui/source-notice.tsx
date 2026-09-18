// AGPL-3.0 section 13: a modified version run over a network must offer its
// users a way to get that version's source, not just whatever is on main. So
// the commit here is the one actually running (see vite.config.ts's
// `define`), and the link points at this build's own history, not the
// repository root.
const REPO_URL = "https://github.com/Pawansingh3889/vega";

export function SourceNotice() {
  const commit = __VEGA_BUILD_COMMIT__;

  return (
    <p className="text-xs text-muted-foreground text-center py-2">
      Vega, AGPL-3.0.{" "}
      <a
        href={
          commit === "unknown" ? REPO_URL : `${REPO_URL}/tree/${commit}`
        }
        className="underline hover:text-foreground transition-colors"
      >
        Source
      </a>
      {commit !== "unknown" && ` (build ${commit})`}
    </p>
  );
}
