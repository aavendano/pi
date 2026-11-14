# Coder template (Pi)

Source of truth for the Coder Docker template used at `coder.avendano.site`.

- On Create / Update Workspace, the UI asks for **Git repository** (`git_repo`).
- Default: `git@github.com:aavendano/pi.git`.
- Clones that URL into `~/<repo-name>` on workspace start (HTTPS fallback if no SSH key).
- Opens that checkout in code-server so project config (`.pi/`, `AGENTS.md`) loads from the clone.
- **Pi** app launches the Pi coding agent CLI in the cloned folder with `defaultProvider=mistral` / `defaultModel=mistral-medium-3.5`. Requires `MISTRAL_API_KEY` already set as a workspace environment variable (not injected by Terraform). VS Code Desktop is hidden; use code-server.
- **MCP Servers** multi-select (`github`, `playwright`) configures vscode / cursor clients (selection is immutable until rebuild).
- **Full Name for Git config** (`username`) sets `user.name` / `GIT_*_NAME` (mutable; empty = Coder user's full name). Email comes from the Coder user (no UI override).
- **Open WebUI** app (path-based `subdomain=false`). Vendor mirror in `modules/open-webui`; wired via root `open-webui-run.sh` + inlined `coder_app`/`coder_script` for flat template upload. Startup installs Python 3.12; Open WebUI waits for it (avoids apt lock races) then recreates a wrong-version venv; configure LLM providers in the UI (no API key in Terraform).

Push to Coder:

```bash
coder templates push docker -d . --yes --activate
```
