# Coder template (Pi)

Source of truth for the Coder Docker template used at `coder.avendano.site`.

- On Create / Update Workspace, the UI asks for **Git repository** (`git_repo`).
- Default: `git@github.com:aavendano/pi.git`.
- Clones that URL into `~/<repo-name>` on workspace start (HTTPS fallback if no SSH key).
- Opens that checkout in code-server so project config (`.pi/`, `AGENTS.md`) loads from the clone.
- **Antigravity IDE** app opens the same cloned folder (deep-link; requires Antigravity / Coder Remote on the client).

Push to Coder:

```bash
coder templates push docker -d . --yes --activate
```
