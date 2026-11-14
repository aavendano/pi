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

    # Open WebUI (vendored module) requires Python 3.11+ with venv.
    if ! command -v python3.11 >/dev/null 2>&1 && ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,11) else 1)' 2>/dev/null; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq software-properties-common
      sudo add-apt-repository -y ppa:deadsnakes/ppa
      sudo apt-get update -qq
      sudo apt-get install -y -qq python3.11 python3.11-venv
    fi
  EOT

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

module "antigravity" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/antigravity/coder"
  version  = "1.0.2"
  agent_id = coder_agent.main.id
  order    = 2
  folder   = "/home/${local.linux_user}/${module.git-clone[count.index].folder_name}"
}

# https://registry.coder.com/modules/coder-labs/mcp-servers
# Multi-select MCP Servers field on Create Workspace (Coder >= 2.24).
module "mcp_servers" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/mcp-servers/coder"
  version  = "0.0.1"

  agent_id = coder_agent.main.id
  clients  = ["vscode", "gemini", "cursor"]
  default  = ["github", "playwright"]

  coder_parameter_order = 2

  # Sin credenciales inyectadas: los clientes pueden autenticar por su cuenta.
  github_auth = {
    mode = "none"
  }
}

# Vendored coder-labs/open-webui (path-based; registry hardcodes subdomain=true).
module "open-webui" {
  count    = data.coder_workspace.me.start_count
  source   = "./modules/open-webui"
  agent_id = coder_agent.main.id

  order     = 3
  share     = "owner"
  subdomain = false
  # openai_api_key vacío: configurar providers en la UI
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
