#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================
NODE_MAJOR="22"
DOTNET_PREFERRED="9.0"
DOTNET_FALLBACK="8.0"
PG_VERSION="17"

# =========================
# HELPERS
# =========================
log() {
  echo -e "\n[INFO] $1"
}

warn() {
  echo -e "\n[AVISO] $1"
}

fail() {
  echo -e "\n[ERRO] $1" >&2
  exit 1
}

run_or_warn() {
  local desc="$1"
  shift
  if ! "$@"; then
    warn "Falhou: ${desc}"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Comando obrigatório não encontrado: $1"
}

# =========================
# CHECKS
# =========================
if [[ "$EUID" -eq 0 ]]; then
  fail "Execute como usuário normal. O script usa sudo quando necessário."
fi

require_cmd sudo
require_cmd curl
require_cmd wget

UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
if [[ "$UBUNTU_CODENAME" != "noble" ]]; then
  warn "Este script foi feito para Ubuntu 24.04 LTS (noble). Detectado: ${UBUNTU_CODENAME:-desconhecido}"
fi

CURRENT_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"

if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
  fail "Não foi possível determinar a home do usuário."
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# =========================
# UPDATE
# =========================
log "Atualizando pacotes"
sudo apt update
sudo apt upgrade -y

# =========================
# BASE DEPENDENCIES
# =========================
log "Instalando dependências básicas"
sudo apt install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  wget \
  gpg \
  gnupg \
  lsb-release \
  software-properties-common \
  build-essential \
  pkg-config \
  unzip \
  zip \
  tar \
  xz-utils \
  git \
  nano \
  vim \
  jq \
  tree \
  net-tools \
  openssl \
  libssl-dev \
  zlib1g-dev \
  libbz2-dev \
  libreadline-dev \
  libsqlite3-dev \
  libffi-dev \
  liblzma-dev \
  libncursesw5-dev \
  tk-dev \
  xclip \
  libnss3 \
  libasound2t64 \
  libgbm1 \
  libgtk-3-0 \
  libxss1 \
  libsecret-1-0

# =========================
# PYTHON
# =========================
log "Instalando Python e dependências"
sudo apt install -y \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  python3-full \
  python-is-python3

log "Atualizando ferramentas Python no escopo do usuário"
python3 -m pip install --user --upgrade pip setuptools wheel

# =========================
# JAVA
# =========================
log "Instalando Java JDK"
sudo apt install -y default-jdk maven gradle

# =========================
# NODE.JS + NPM
# =========================
log "Configurando Node.js ${NODE_MAJOR}"
curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
sudo apt install -y nodejs

log "Atualizando npm"
sudo npm install -g npm@latest

log "Instalando ferramentas globais front-end"
sudo npm install -g \
  vite \
  create-vite \
  yarn \
  pnpm \
  typescript \
  eslint \
  prettier

# =========================
# .NET + C#
# =========================
log "Instalando .NET SDK"

# No Ubuntu 24.04, versões suportadas do .NET podem vir do feed do Ubuntu/Canonical.
# Se a versão preferida não existir, tentamos o repositório backports.
if ! apt-cache policy "dotnet-sdk-${DOTNET_PREFERRED}" | grep -q Candidate; then
  warn ".NET SDK ${DOTNET_PREFERRED} não apareceu no feed atual. Tentando backports."
  sudo add-apt-repository -y ppa:dotnet/backports
  sudo apt update
fi

if apt-cache policy "dotnet-sdk-${DOTNET_PREFERRED}" | grep -q Candidate; then
  sudo apt install -y "dotnet-sdk-${DOTNET_PREFERRED}"
elif apt-cache policy "dotnet-sdk-${DOTNET_FALLBACK}" | grep -q Candidate; then
  warn "Instalando fallback .NET SDK ${DOTNET_FALLBACK}"
  sudo apt install -y "dotnet-sdk-${DOTNET_FALLBACK}"
else
  fail "Nenhuma versão suportada do .NET SDK encontrada."
fi

# =========================
# POSTGRESQL
# =========================
log "Instalando PostgreSQL ${PG_VERSION} via PGDG"
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt update

sudo apt install -y \
  "postgresql-${PG_VERSION}" \
  "postgresql-client-${PG_VERSION}" \
  postgresql-contrib \
  libpq-dev

sudo systemctl enable postgresql
sudo systemctl start postgresql

# =========================
# REDIS
# =========================
log "Instalando Redis oficial"
sudo install -d -m 0755 /usr/share/keyrings
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
sudo chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/redis.list > /dev/null

sudo apt update
sudo apt install -y redis

sudo systemctl enable redis-server || true
sudo systemctl start redis-server || sudo systemctl start redis || true

# =========================
# VSCODE
# =========================
log "Instalando Visual Studio Code"
cd "$TMP_DIR"
wget -O code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
sudo apt install -y ./code.deb

# =========================
# DBEAVER
# =========================
log "Instalando DBeaver Community"
wget -O dbeaver.deb "https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb"
if ! sudo apt install -y ./dbeaver.deb; then
  sudo dpkg -i ./dbeaver.deb || true
  sudo apt -f install -y
fi

# =========================
# VSCODE EXTENSIONS
# =========================
log "Aguardando o comando 'code' ficar disponível"
for _ in {1..20}; do
  if command -v code >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if command -v code >/dev/null 2>&1; then
  log "Instalando extensões do VS Code"
  EXTENSIONS=(
    "ms-python.python"
    "ms-python.vscode-pylance"
    "ms-python.black-formatter"
    "ms-python.isort"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "xabikos.JavaScriptSnippets"
    "dsznajder.es7-react-js-snippets"
    "vscjava.vscode-java-pack"
    "redhat.vscode-xml"
    "redhat.java"
    "vmware.vscode-spring-boot"
    "ms-dotnettools.csharp"
    "ms-dotnettools.vscode-dotnet-runtime"
    "ms-azuretools.vscode-docker"
    "ms-vscode.vscode-typescript-next"
    "mtxr.sqltools"
    "mtxr.sqltools-driver-pg"
    "ms-ossdata.vscode-postgresql"
    "redis.redis-for-vscode"
    "github.copilot"
    "github.copilot-chat"
  )

  for ext in "${EXTENSIONS[@]}"; do
    run_or_warn "Extensão VS Code ${ext}" code --install-extension "$ext" --force
  done
else
  warn "O comando 'code' não ficou disponível. Instale as extensões manualmente depois."
fi

# =========================
# PERMISSIONS / GROUPS
# =========================
log "Ajustando grupos úteis"
sudo usermod -aG dialout "$CURRENT_USER" || true
sudo usermod -aG plugdev "$CURRENT_USER" || true

# =========================
# OPTIONAL DEV TOOLS
# =========================
log "Instalando ferramentas extras úteis"
sudo apt install -y \
  make \
  gcc \
  g++ \
  openjdk-21-jdk-headless || true

# =========================
# TESTS
# =========================
log "Executando testes básicos"

echo "--------------------------------------------------"
echo "Python:"
python3 --version || true
pip3 --version || true

echo
echo "Node:"
node -v || true
npm -v || true
npx vite --version || true

echo
echo "Java:"
java -version || true
javac -version || true
mvn -version | head -n 2 || true
gradle --version | head -n 3 || true

echo
echo ".NET:"
dotnet --info | head -n 20 || true

echo
echo "PostgreSQL:"
psql --version || true
systemctl is-active postgresql || true

echo
echo "Redis:"
redis-server --version || true
redis-cli ping || true
systemctl is-active redis-server || systemctl is-active redis || true

echo
echo "VS Code:"
code --version | head -n 1 || true

echo
echo "DBeaver:"
if command -v dbeaver >/dev/null 2>&1; then
  dbeaver --version || true
else
  echo "DBeaver instalado via .deb; atalho disponível no menu."
fi
echo "--------------------------------------------------"

# =========================
# FINAL NOTES
# =========================
cat <<EOF

INSTALAÇÃO CONCLUÍDA

Próximos comandos úteis:

1) React
   npm create vite@latest meu-projeto -- --template react
   cd meu-projeto
   npm install
   npm run dev

2) Python
   python3 -m venv .venv
   source .venv/bin/activate

3) C#
   dotnet new console -o MeuProjetoCSharp
   cd MeuProjetoCSharp
   dotnet run

4) PostgreSQL
   sudo -u postgres psql

5) Redis
   redis-cli ping

Observações:
- Faça logout/login para garantir grupos como dialout e plugdev.
- O VS Code foi instalado por pacote .deb oficial. :contentReference[oaicite:1]{index=1}
- O PostgreSQL usa o repositório oficial PGDG para Ubuntu noble. :contentReference[oaicite:2]{index=2}
- O Redis usa o repositório oficial packages.redis.io. :contentReference[oaicite:3]{index=3}
- O .NET em Ubuntu 24.04 pode vir do feed do Ubuntu e, quando preciso, do backports. :contentReference[oaicite:4]{index=4}

EOF
