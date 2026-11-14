terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  # Linux user inside codercom/example-base:ubuntu
  linux_user = "coder"
}

provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Shown on Create / Update Workspace in the Coder UI.
data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository"
  description  = "URL del repo a clonar (HTTPS o SSH). Soporta /tree/branch."
  type         = "string"
  form_type    = "input"
  mutable      = true
  default      = "git@github.com:aavendano/pi.git"
  icon         = "/icon/git.svg"
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  startup_script = <<-EOT
    set -e

    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Prefer HTTPS for the public repo when SSH keys are not present in the workspace.
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    if [ ! -f ~/.ssh/known_hosts ] || ! grep -q github.com ~/.ssh/known_hosts; then
      ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts 2>/dev/null || true
    fi

    # Open WebUI needs CPython 3.11 or 3.12 (not 3.13+/system 3.14).
    if ! command -v python3.12 >/dev/null 2>&1 && ! command -v python3.11 >/dev/null 2>&1; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq software-properties-common
      sudo add-apt-repository -y ppa:deadsnakes/ppa
      sudo apt-get update -qq
      sudo apt-get install -y -qq python3.12 python3.12-venv
    fi
  EOT

  # Keep code-server; hide VS Code Desktop / Insiders.
  display_apps {
    vscode                 = false
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = true
    port_forwarding_helper = true
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

# https://registry.coder.com/modules/coder/git-config
# Sets GIT_* env + git config --global from Coder user (optional UI override for name).
module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "1.0.35"
  agent_id = coder_agent.main.id

  # Defaults del módulo: override de nombre sí; email no.
  allow_username_change = true
  allow_email_change    = false

  # Tras git_repo y mcp_servers (order 2).
  coder_parameter_order = 3
}

# https://registry.coder.com/modules/coder/git-clone
# Clones the URL from the git_repo workspace parameter (falls back to HTTPS if SSH is unavailable).
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.5"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value

  pre_clone_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    # Public repo: if the workspace has no SSH key, rewrite SSH GitHub URLs to HTTPS.
    if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ] && [ -z "$${SSH_AUTH_SOCK:-}" ]; then
      git config --global url."https://github.com/".insteadOf "git@github.com:"
      echo "No SSH key in workspace; git@github.com -> https://github.com"
    fi
  EOT
}

# https://registry.coder.com/modules/coder/code-server
# Opens the cloned repo folder so project config (e.g. AGENTS.md / .pi) loads from that checkout.
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.6.0"
  agent_id = coder_agent.main.id

  order        = 1
  folder       = "/home/${local.linux_user}/${module.git-clone[count.index].folder_name}"
  subdomain    = false
  display_name = "code-server"
  slug         = "code-server"
}

# https://registry.coder.com/modules/coder-labs/pi
# Pi CLI with Mistral as default inference provider (reads MISTRAL_API_KEY from workspace env).
module "pi" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/pi/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/${local.linux_user}/${module.git-clone[count.index].folder_name}"

  # Node 22 + jq (requisitos del módulo) antes del npm install.
  pre_install_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v node >/dev/null || [ "$(node -v | sed 's/v//' | cut -d. -f1)" -lt 22 ]; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
    fi
    command -v jq >/dev/null || sudo apt-get install -y -qq jq
  EOT

  # Tras el install del módulo (escribe defaultProjectTrust), fijar Mistral.
  post_install_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    SETTINGS="$HOME/.pi/agent/settings.json"
    mkdir -p "$(dirname "$SETTINGS")"
    if [ -f "$SETTINGS" ]; then
      jq '.defaultProvider="mistral" | .defaultModel="mistral-medium-3.5"' \
        "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    else
      jq -n '{defaultProvider:"mistral",defaultModel:"mistral-medium-3.5",defaultProjectTrust:"always"}' \
        > "$SETTINGS"
    fi
  EOT
}

resource "coder_app" "pi" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "pi"
  display_name = "Pi"
  icon         = "/icon/pi.svg"
  open_in      = "slim-window"
  order        = 2
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "/home/${local.linux_user}/${module.git-clone[count.index].folder_name}"
    pi --continue
  EOT
}

# https://registry.coder.com/modules/coder-labs/mcp-servers
# Multi-select MCP Servers field on Create Workspace (Coder >= 2.24).
module "mcp_servers" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/mcp-servers/coder"
  version  = "0.0.1"

  agent_id = coder_agent.main.id
  clients  = ["vscode", "cursor"]
  default  = ["github", "playwright"]

  coder_parameter_order = 2

  # Sin credenciales inyectadas: los clientes pueden autenticar por su cuenta.
  github_auth = {
    mode = "none"
  }
}

# Vendored from coder-labs/open-webui v1.0.0 (see modules/open-webui).
# Inlined at template root so Coder MCP tar upload works (no nested dirs).
# Path-based: subdomain=false (registry hardcodes true).
resource "coder_script" "open_webui" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "open-webui"
  icon         = "/icon/openwebui.svg"
  run_on_start = true
  script = templatefile("${path.module}/open-webui-run.sh", {
    HTTP_SERVER_LOG_PATH = "/tmp/open-webui.log"
    HTTP_SERVER_PORT     = 7800
    VERSION              = "latest"
    DATA_DIR             = ".open-webui"
    OPENAI_API_KEY       = ""
  })
}

resource "coder_app" "open_webui" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  slug         = "open-webui"
  display_name = "Open WebUI"
  url          = "http://localhost:7800"
  icon         = "/icon/openwebui.svg"
  subdomain    = false
  share        = "owner"
  order        = 3
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = "codercom/example-base:ubuntu"
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
