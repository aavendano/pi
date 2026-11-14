# Coder template (Pi)

Source of truth for the Coder Docker template used at `coder.avendano.site`.

- On Create / Update Workspace, the UI asks for **Git repository** (`git_repo`).
- Default: `git@github.com:aavendano/pi.git`.
- Clones that URL into `~/<repo-name>` on workspace start (HTTPS fallback if no SSH key).
- Opens that checkout in code-server so project config (`.pi/`, `AGENTS.md`) loads from the clone.
- **Antigravity IDE** app opens the same cloned folder (deep-link; requires Antigravity / Coder Remote on the client).
- **MCP Servers** multi-select (`github`, `playwright`) configures vscode / gemini / cursor clients (selection is immutable until rebuild).
- **Full Name for Git config** (`username`) sets `user.name` / `GIT_*_NAME` (mutable; empty = Coder user's full name). Email comes from the Coder user (no UI override).
- **Open WebUI** app (vendored `modules/open-webui`, path-based `subdomain=false`). Startup installs Python 3.11+ if missing; configure LLM providers in the UI (no API key in Terraform).

Push to Coder:

```bash
coder templates push docker -d . --yes --activate
```
