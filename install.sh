#!/bin/bash

# =============================================================================
# Fedora Post-Install Setup Script
# =============================================================================
set -euo pipefail

# --- Logging Helpers ----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

download() {
    local url="$1"
    local dest="$2"
    local name="$3"
    local max_retries=3
    
    for i in $(seq 1 $max_retries); do
        if curl -L --retry 3 --retry-delay 5 --fail -o "$dest" "$url" 2>/dev/null; then
            return 0
        fi
        warn "Download attempt $i/$max_retries failed for $name"
    done
    error "Failed to download $name after $max_retries attempts"
    return 1
}

# --- Load .env ----------------------------------------------------------------
if [ -f .env ]; then
    set -a; source .env; set +a
    success "Loaded .env"
else
    error ".env file not found!"; exit 1
fi

for var in GIT_USER GIT_TOKEN; do
    if [ -z "${!var:-}" ]; then
        error "Required variable \$$var is not set in .env"; exit 1
    fi
done

# =============================================================================
## 1. System Configs (always overwrite — these are declarative)
# =============================================================================
log "Applying system configs..."
sudo cp ./sudoers /etc/sudoers
sudo cp ./dnf.conf /etc/dnf/dnf.conf
success "System configs applied."

# =============================================================================
## 2. Repositories
# =============================================================================
log "Setting up repositories..."

# Docker — check for repo file
if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
    success "Docker repo added."
else
    warn "Docker repo file exists, skipping."
fi

# VS Code — check for repo file
if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    success "VS Code repo added."
else
    warn "VS Code repo file exists, skipping."
fi

# ngrok -- ngrok no longer provides an RPM repo; install via direct binary download
if command -v ngrok &>/dev/null; then
    warn "ngrok already installed, skipping."
else
    log "Installing ngrok..."
    NGROK_TGZ="$(mktemp --suffix=.tgz)"
    if download "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz" "$NGROK_TGZ" "ngrok"; then
        sudo tar -xzf "$NGROK_TGZ" -C /usr/local/bin ngrok
        rm -f "$NGROK_TGZ"
        success "ngrok $(ngrok --version) installed."
    else
        rm -f "$NGROK_TGZ"
        warn "ngrok installation failed, skipping."
    fi
fi

# Flathub — --if-not-exists handles this natively
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
success "Flathub remote ensured."

# =============================================================================
## 3. System Update + Package Installation
# =============================================================================
log "Running system update..."
sudo dnf update -y

# dnf skips already-installed packages natively; --skip-unavailable handles
# anything not in the current repos (e.g. freeworld codecs needing RPM Fusion)
log "Installing packages..."
sudo dnf install -y --skip-unavailable \
    gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-good gstreamer1-plugins-base gstreamer1-libav \
    akmod-nvidia xorg-x11-drv-nvidia-cuda \
    gcc gcc-c++ make \
    htop btop fastfetch stow vim neovim \
    nodejs \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    sqlitebrowser texstudio thunderbird google-chrome-stable code \
    python3-pip python3-wheel \
    wget curl git jq unzip

success "Core packages done."

# =============================================================================
## 4. Manual / Third-Party Tools
# =============================================================================

# --- Starship -----------------------------------------------------------------
if ! command -v starship &>/dev/null; then
    log "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    success "Starship installed."
else
    warn "Starship already installed, skipping."
fi

# --- uv (Python) --------------------------------------------------------------
if ! command -v uv &>/dev/null; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    success "uv installed."
else
    warn "uv already installed, skipping."
fi

# --- Rust & Cargo (via rustup) -----------------------------------------------
if command -v rustc &>/dev/null && command -v cargo &>/dev/null; then
    warn "Rust and Cargo already installed, skipping."
else
    log "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # Source the env so cargo/rustc are available for the rest of this session
    source "$HOME/.cargo/env"
    success "Rust $(rustc --version) installed."
fi

# --- Node global tools (check each package individually) ---------------------
for pkg in pnpm typescript eslint; do
    if npm list -g --depth=0 "$pkg" &>/dev/null; then
        warn "Node $pkg already installed, skipping."
    else
        log "Installing Node package: $pkg..."
        sudo npm install -g "$pkg"
        success "$pkg installed."
    fi
done

# --- ngrok auth (optional, only if token provided) ---------------------------
if [ -n "${NGROK_TOKEN:-}" ]; then
    if ngrok config check 2>/dev/null | grep -q "authtoken"; then
        warn "ngrok auth token already set, skipping."
    else
        log "Configuring ngrok auth token..."
        ngrok config add-authtoken "$NGROK_TOKEN"
        success "ngrok configured."
    fi
fi

# --- Zotero ------------------------------------------------------------------
# Checks are layered: binary exists → skip download+install; desktop linked → skip integration.
ZOTERO_DIR="/opt/zotero"
ZOTERO_DESKTOP="$HOME/.local/share/applications/zotero.desktop"
ZOTERO_TARBALL="$HOME/zotero.tar.xz"

if [ -f "$ZOTERO_DIR/zotero" ]; then
    warn "Zotero binary already present, skipping download and install."
else
    log "Installing Zotero..."

    # Scrape the version number from the download page, then build the direct CDN URL.
    # The type=version param is not valid; the dl redirect is a multi-hop that breaks curl.
    log "Resolving latest Zotero version..."
    ZOTERO_VERSION="$(curl -sSf 'https://www.zotero.org/download/' \
        | grep -oP '"linux-x86_64":"\K[^"]+')"
    if [ -z "$ZOTERO_VERSION" ]; then
        error "Could not determine Zotero version from download page"; exit 1
    fi
    ZOTERO_URL="https://download.zotero.org/client/release/${ZOTERO_VERSION}/Zotero-${ZOTERO_VERSION}_linux-x86_64.tar.xz"
    log "Downloading Zotero ${ZOTERO_VERSION}..."

    # Reuse tarball if a previous run downloaded it but failed mid-install
    if [ ! -f "$ZOTERO_TARBALL" ]; then
        if ! download "$ZOTERO_URL" "$ZOTERO_TARBALL" "Zotero"; then
            warn "Zotero download failed, skipping installation."
            exit 0
        fi
    else
        warn "Zotero tarball already present, reusing."
    fi

    sudo mkdir -p "$ZOTERO_DIR"
    sudo tar -xJf "$ZOTERO_TARBALL" -C "$ZOTERO_DIR" --strip-components=1
    sudo chown -R "$USER:$USER" "$ZOTERO_DIR"
    rm -f "$ZOTERO_TARBALL"
    success "Zotero ${ZOTERO_VERSION} extracted."
fi

# Desktop integration — separate check so it runs even if install was skipped
if [ -L "$ZOTERO_DESKTOP" ]; then
    warn "Zotero desktop entry already linked, skipping."
else
    log "Configuring Zotero desktop integration..."
    bash "$ZOTERO_DIR/set_launcher_icon"
    mkdir -p "$HOME/.local/share/applications"
    ln -sf "$ZOTERO_DIR/zotero.desktop" "$ZOTERO_DESKTOP"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    success "Zotero desktop entry linked."
fi

# --- JetBrains Toolbox -------------------------------------------------------
JB_TOOLBOX_BIN="$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
if [ -f "$JB_TOOLBOX_BIN" ] || [ -d "$HOME/.local/share/JetBrains/Toolbox" ]; then
    warn "JetBrains Toolbox already installed, skipping."
else
    log "Installing JetBrains Toolbox..."
    TOOLBOX_TARBALL="$(mktemp --suffix=.tar.gz)"
    if ! wget -q --show-progress -O "$TOOLBOX_TARBALL" \
         "https://data.services.jetbrains.com/products/download?code=TBA&platform=linux"; then
        warn "JetBrains Toolbox download failed, skipping."
    else
        TOOLBOX_TMPDIR="$(mktemp -d)"
        tar -xzf "$TOOLBOX_TARBALL" -C "$TOOLBOX_TMPDIR"
        TOOLBOX_BIN="$(find "$TOOLBOX_TMPDIR" -type f -name "jetbrains-toolbox*" ! -name "*.desktop" ! -name "*.svg" ! -name "*.png" | head -1)"
        if [ -z "$TOOLBOX_BIN" ]; then
            warn "Could not find jetbrains-toolbox binary in tarball, skipping."
        else
            "$TOOLBOX_BIN" --install
            success "JetBrains Toolbox installed."
        fi
        rm -rf "$TOOLBOX_TMPDIR" "$TOOLBOX_TARBALL"
    fi
fi

# --- Postman -----------------------------------------------------------------
POSTMAN_DESKTOP="$HOME/.local/share/applications/postman.desktop"

if [ -d "/opt/Postman" ]; then
    warn "Postman already installed, skipping."
else
    log "Installing Postman..."
    POSTMAN_TARBALL="$(mktemp --suffix=.tar.gz)"
    if wget -q --show-progress -O "$POSTMAN_TARBALL" \
         "https://dl.pstmn.io/download/latest/linux_64"; then
        sudo tar -xzf "$POSTMAN_TARBALL" -C /opt
        sudo ln -sf /opt/Postman/Postman /usr/local/bin/postman
        rm -f "$POSTMAN_TARBALL"
        success "Postman installed."
    else
        warn "Postman download failed, skipping."
    fi
fi

# Desktop integration -- separate check so it runs even if install was skipped
if [ -f "$POSTMAN_DESKTOP" ]; then
    warn "Postman desktop entry already exists, skipping."
else
    log "Creating Postman desktop entry..."
    mkdir -p "$HOME/.local/share/applications"
    cat > "$POSTMAN_DESKTOP" <<DESKTOP
[Desktop Entry]
Name=Postman
Exec=/opt/Postman/Postman
Icon=/opt/Postman/app/icons/icon_128x128.png
Type=Application
Categories=Development;Utility;
Terminal=false
DESKTOP
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    success "Postman desktop entry created."
fi

# =============================================================================
## 5. Docker Group & Service
# =============================================================================
log "Configuring Docker service..."

sudo groupadd -f docker  # -f is idempotent: no error if group already exists

if id -nG "$USER" | grep -qw docker; then
    warn "$USER already in docker group, skipping."
else
    sudo usermod -aG docker "$USER"
    success "Added $USER to docker group."
fi

sudo systemctl enable --now docker  # idempotent
success "Docker service enabled."

# =============================================================================
## 6. Git & Dotfiles
# =============================================================================

# --adopt pulls in any existing untracked files before relinking, preventing conflicts
log "Setting up dotfiles via stow..."
stow --adopt -t "$HOME" bash git vim tmux && success "Dotfiles stowed." || warn "stow had conflicts — review manually."

# Git credentials — always overwrite (token may have rotated)
log "Configuring Git credentials..."
echo "https://$GIT_USER:$GIT_TOKEN@github.com" > ~/.git-credentials
git config --global credential.helper store
success "Git configured."

# =============================================================================
## 7. System Optimizations
# =============================================================================
log "Enabling system optimizations..."
sudo systemctl enable nvidia-persistenced 2>/dev/null \
    && success "nvidia-persistenced enabled." \
    || warn "nvidia-persistenced not available, skipping."
sudo systemctl enable fstrim.timer
success "fstrim.timer enabled."

# =============================================================================
## 8. Cleanup
# =============================================================================
log "Cleaning up..."
sudo dnf autoremove -y
sudo dnf clean all
success "Cleanup done."

# =============================================================================
## 9. Done
# =============================================================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ALL DONE! Please reboot or log out/in   ${NC}"
echo -e "${GREEN}  for Docker group changes to take effect. ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
fastfetch
