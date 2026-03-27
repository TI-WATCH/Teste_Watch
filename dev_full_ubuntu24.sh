#!/usr/bin/env bash
set -euo pipefail

log() {
  echo -e "\n[INFO] $1"
}

fail() {
  echo -e "\n[ERRO] $1" >&2
  exit 1
}

if [[ "$EUID" -eq 0 ]]; then
  fail "Execute como usuário normal. O script usa sudo quando necessário."
fi

UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
if [[ "$UBUNTU_CODENAME" != "noble" ]]; then
  echo "[AVISO] Este script foi feito para Ubuntu 24.04 LTS (noble). Sistema detectado: ${UBUNTU_CODENAME:-desconhecido}"
fi

log "Atualizando o sistema"
sudo apt update
sudo apt upgrade -y

log "Instalando dependências básicas"
sudo apt install -y \
  curl \
  wget \
  gpg \
  gnupg \
  ca-certificates \
  apt-transport-https \
  software-properties-common \
  lsb-release \
  build-essential \
  unzip

log "Instalando Python"
sudo apt install -y \
  python3 \
  python3-pip \
  python3-venv \
  python3-full

log "Instalando Java JDK"
sudo apt install -y default-jdk

log "Configurando Node.js 22 (NodeSource)"
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

log "Atualizando npm"
sudo npm install -g npm@latest

log "Instalando Vite globalmente para projetos React"
sudo npm install -g vite

log "Instalando .NET SDK e C#"
sudo apt install -y dotnet-sdk-9.0 || sudo apt install -y dotnet-sdk-8.0

log "Instalando PostgreSQL"
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt update
sudo apt install -y postgresql-17 postgresql-client-17

log "Habilitando PostgreSQL"
sudo systemctl enable postgresql
sudo systemctl start postgresql

log "Configurando Redis oficial"
sudo install -d -m 0755 /usr/share/keyrings
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
sudo chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/redis.list > /dev/null
sudo apt update
sudo apt install -y redis

log "Habilitando Redis"
sudo systemctl enable redis-server || true
sudo systemctl enable redis || true
sudo systemctl start redis-server || sudo systemctl start redis || true

log "Instalando Visual Studio Code"
TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"
wget -O code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
sudo apt install -y ./code.deb

log "Instalando DBeaver Community"
wget -O dbeaver.deb "https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb"
sudo apt install -y ./dbeaver.deb || {
  sudo dpkg -i ./dbeaver.deb
  sudo apt -f install -y
}

log "Limpando arquivos temporários"
rm -rf "$TMP_DIR"

log "Instalação concluída. Versões detectadas:"
echo "--------------------------------------------------"
echo "Python:   $(python3 --version 2>/dev/null || echo 'não encontrado')"
echo "Pip:      $(pip3 --version 2>/dev/null | head -n 1 || echo 'não encontrado')"
echo "Node:     $(node -v 2>/dev/null || echo 'não encontrado')"
echo "npm:      $(npm -v 2>/dev/null || echo 'não encontrado')"
echo "Java:"
java -version 2>&1 | head -n 2 || true
echo ".NET:"
dotnet --info 2>/dev/null | head -n 12 || true
echo "PostgreSQL:"
psql --version 2>/dev/null || true
echo "Redis:"
redis-server --version 2>/dev/null || true
echo "Code:"
code --version 2>/dev/null | head -n 1 || true
echo "--------------------------------------------------"

cat <<'EOF'

PRÓXIMOS PASSOS

1) Criar projeto React:
   npm create vite@latest meu-projeto -- --template react
   cd meu-projeto
   npm install
   npm run dev

2) Testar C# / .NET:
   dotnet new console -o MeuConsole
   cd MeuConsole
   dotnet run

3) Entrar no PostgreSQL:
   sudo -u postgres psql

4) Testar Redis:
   redis-cli ping

EOF
