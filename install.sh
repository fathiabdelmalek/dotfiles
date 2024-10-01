#!/bin/bash

# Load variables from the .env file
if [ -f .env ]; then
	export $(grep -v '^#' .env | xargs)
else
	echo ".env file not found!"
	exit 1
fi

# Copy important config files
sudo cp ./sudoers /etc/sudoers
sudo cp ./dnf.conf /etc/dnf/dnf.conf

# Update system and install essential packages
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf update -y
sudo dnf install -y htop neofetch stow neovim nodejs pnpm docker-ce docker-ci-cli docker-buildx-plugin docker-compose-plugin sqlitebrowser texstudio qt5-designer
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Create symbolic links for dotfiles
stow */
echo $TOKEN > ~/.git-credentials

# Configure docker
if [ ! getent group docker  &> /dev/null ]; then
	sudo groupadd docker
fi 
sudo usermod -aG docker $USER
newgrp docker
sudo systemctl enable docker

# Generate SSH key if it doesn't exist
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
	echo "Generating SSH key..."
	ssh-keygen -t rsa -b 4096 -C "$EMAIL" -f "$HOME/.ssh/id_rsa" -N ""
	eval "$(ssh-agent -s)"
	ssh-add ~/.ssh/id_rsa
	echo "Your SSH public key has been generated. You can add it to your GitHub or other services."
else
	echo "SSH key already exists."
fi

# Install and configure nodejs
sudo dnf install -y node
sudo npm install -y typescript eslint

# Install essential applications
# Jetbrains Toolbox
if [ ! -d "$HOME/jetbrains-toolbox" ]; then
    echo "Installing JetBrains Toolbox..."
    wget -O ~/jetbrains-toolbox.tar.gz https://data.services.jetbrains.com/products/download?code=TBA&platform=linux
    mkdir ~/jetbrains-toolbox
    tar -xzf ~/jetbrains-toolbox.tar.gz -C ~/jetbrains-toolbox --strip-components=1
    ~/jetbrains-toolbox/jetbrains-toolbox
    rm ~/jetbrains-toolbox.tar.gz
else
    echo "JetBrains Toolbox is already installed."
fi
# VS Code
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf check-update
sudo dnf install -y code
# Google Chrome
sudo dnf install -y fedora-workstation-repositories
sudo dnf config-manager --set-enabled google-chrome
sudo dnf install -y google-chrome-stable
# Scene Builder
wget https://download2.gluonhq.com/scenebuilder/19.0.0/install/linux/SceneBuilder-19.0.0.rpm
sudo dnf install -y SceneBuilder-19.0.0.rpm
rm SceneBuilder-19.0.0.rpm
# Insomnia
echo "[insomnia]
name=Insomnia
baseurl=https://download.konghq.com/insomnia/rpm/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://download.konghq.com/insomnia/rpm/repomd.xml.key" | sudo tee -a /etc/yum.repos.d/insomnia.repo
sudo dnf install -y insomnia

# Clean up installation files
sudo dnf autoremove -y
sudo dnf clean all

