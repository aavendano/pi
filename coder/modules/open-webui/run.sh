#!/usr/bin/env sh

set -eu

printf '\033[0;1mInstalling Open WebUI %s...\n\n' "${VERSION}"

# coder_script runs in parallel with startup_script (which installs Python).
# Wait for that install; only apt ourselves after locks are free if still missing.
if ! command -v python3.12 >/dev/null 2>&1 && ! command -v python3.11 >/dev/null 2>&1; then
  echo "Waiting for Python 3.11/3.12 from agent startup_script..."
  i=0
  while [ "$i" -lt 180 ]; do
    if command -v python3.12 >/dev/null 2>&1 || command -v python3.11 >/dev/null 2>&1; then
      break
    fi
    sleep 2
    i=$((i + 1))
  done
fi
if ! command -v python3.12 >/dev/null 2>&1 && ! command -v python3.11 >/dev/null 2>&1; then
  echo "Installing Python 3.12 (required by Open WebUI)..."
  while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
    || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 \
    || sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    sleep 2
  done
  sudo apt-get update -qq
  sudo apt-get install -y -qq software-properties-common
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3.12 python3.12-venv
fi

check_python_version() {
  python_cmd="$1"
  if command -v "$python_cmd" > /dev/null 2>&1; then
    version=$("$python_cmd" --version 2>&1 | awk '{print $2}')
    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    # open-webui publishes wheels for 3.11–3.12 only.
    if [ "$major" -eq 3 ] && [ "$minor" -ge 11 ] && [ "$minor" -le 12 ]; then
      echo "$python_cmd"
      return 0
    fi
  fi
  return 1
}

PYTHON_CMD=""
for cmd in python3.12 python3.11; do
  if result=$(check_python_version "$cmd"); then
    PYTHON_CMD="$result"
    echo "✅ Found suitable Python: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1))"
    break
  fi
done

if [ -z "$PYTHON_CMD" ]; then
  echo "❌ Python 3.11 or 3.12 is required but not found."
  echo ""
  echo "Please install Python 3.12 in your image. For example on Ubuntu/Debian:"
  echo "  sudo add-apt-repository -y ppa:deadsnakes/ppa"
  echo "  sudo apt-get update"
  echo "  sudo apt-get install -y python3.12 python3.12-venv"
  exit 1
fi

VENV_DIR="$HOME/.open-webui-venv"
if [ -d "$VENV_DIR" ] && ! "$VENV_DIR/bin/python" -c 'import sys; raise SystemExit(0 if (3, 11) <= sys.version_info[:2] <= (3, 12) else 1)' 2>/dev/null; then
  echo "Removing incompatible virtual environment..."
  rm -rf "$VENV_DIR"
fi
if [ ! -d "$VENV_DIR" ]; then
  echo "📦 Creating virtual environment..."
  "$PYTHON_CMD" -m venv "$VENV_DIR"
fi
. "$VENV_DIR/bin/activate"

if ! pip show open-webui > /dev/null 2>&1; then
  echo "📦 Installing Open WebUI version ${VERSION}..."
  if [ "${VERSION}" = "latest" ]; then
    pip install open-webui
  else
    pip install "open-webui==${VERSION}"
  fi
  echo "🥳 Open WebUI has been installed"
else
  echo "✅ Open WebUI is already installed"
fi

echo "👷 Starting Open WebUI in background..."
echo "Check logs at ${HTTP_SERVER_LOG_PATH}"

DATA_DIR="${DATA_DIR}" \
  OPENAI_API_KEY="${OPENAI_API_KEY}" \
  open-webui serve --host 0.0.0.0 --port "${HTTP_SERVER_PORT}" > "${HTTP_SERVER_LOG_PATH}" 2>&1 &

echo "🥳 Open WebUI is ready. HTTP server is listening on port ${HTTP_SERVER_PORT}"
