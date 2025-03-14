#!/bin/bash
set -e  # Exit immediately on error
set -u  # Treat unset variables as an error
set -o pipefail  # Catch errors in piped commands

# Constants
GITHUB_ORG="CrisisTextLine"
DEV_CLI_REPO="github.com/$GITHUB_ORG/dev-cli/cmd/ctl"

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Xcode (required for Homebrew)
install_xcode() {
    if ! command_exists xcode-select; then
        echo "🔧 Installing Xcode Command Line Tools..."
        xcode-select --install
    else
        echo "✅  Xcode Command Line Tools already installed."
    fi
}

# Install Homebrew
install_homebrew() {
    if ! command_exists brew; then
        echo "🍺 Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"  # Ensure brew is in the path
    else
        echo "✅  Homebrew already installed."
    fi
}

# Install Git and Go if not installed
install_git_go() {
    echo "🔍 Checking for Git and Go installation..."
    missing_packages=""

    for pkg in git go; do
        if ! command_exists "$pkg"; then
            missing_packages="$missing_packages $pkg"
        fi
    done

    if [ -n "$missing_packages" ]; then
        echo "⚙️ Installing missing packages: $missing_packages"
        brew install $missing_packages
    else
        echo "✅  Git and Go are already installed."
    fi
}

# Install Docker or OrbStack
install_docker_orbstack() {
    if command_exists orb; then
        echo "✅  OrbStack is already installed."
        return
    fi

    if command_exists docker; then
        echo "✅  Docker is already installed."
        prompt_for_orbstack
        return
    fi

    prompt_for_orbstack
}

# Function to prompt the user for OrbStack installation
prompt_for_orbstack() {
    read -p "Do you want to use OrbStack (alternative to Docker)? Y/n: " choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    if [[ "$choice" == "y" || "$choice" == "yes" ]]; then
        echo "🌊 Installing OrbStack..."
        brew install --cask orbstack
    else
        echo "🐳 Installing Docker..."
        brew install --cask docker
    fi
}

# Configure SSH for GitHub
configure_ssh() {
    SSH_DIR="$HOME/.ssh"
    GITHUB_HOST="github.com"
    DEV_CLI_REPO="git@github.com:CrisisTextLine/dev-cli.git"

    echo "🔑 Configuring SSH for GitHub..."

    # Ensure SSH directory exists
    mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
    echo "✅  SSH directory created."

    # Ensure known_hosts exists
    touch "$SSH_DIR/known_hosts" && chmod 644 "$SSH_DIR/known_hosts"
    echo "✅  known_hosts file created."

    # Add GitHub SSH key to known_hosts
    if ! grep -q "$GITHUB_HOST" "$SSH_DIR/known_hosts"; then
        echo "🔍 Adding GitHub's SSH host key to known_hosts..."
        ssh-keyscan -H "$GITHUB_HOST" >> "$SSH_DIR/known_hosts"
        echo "✅  GitHub SSH host key added."
    else
        echo "✅  GitHub SSH host key already exists."
    fi

    test_ssh_connection
}

# Test SSH connection to GitHub
test_ssh_connection() {
    echo "🔍 Testing SSH connection to GitHub..."
    set +e
    output=$(git ls-remote "$DEV_CLI_REPO" 2>&1)
    exit_status=$?
    set -e

    if [ $exit_status -eq 0 ]; then
        echo "✅  SSH connection to GitHub successful."
    else
        echo "❌  SSH connection failed. Please check your SSH keys."

        if echo "$output" | grep -q "Permission denied"; then
            echo "🔴 SSH key issue detected. Ensure your key is added to the SSH agent."
            prompt_generate_ssh_key
        elif echo "$output" | grep -q "Repository not found"; then
            echo "🔴 The repository does not exist or you lack access."
            exit 1
        else
            echo "❌  Unknown SSH error."
            exit 1
        fi
    fi
}

# Prompt to generate a new SSH key
prompt_generate_ssh_key() {
    read -p "Do you want to generate a new SSH key? Y/n: " choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    if [[ "$choice" == "" || "$choice" == "y" || "$choice" == "yes" ]]; then
        generate_ssh_key
    else
        echo "❌  SSH key not configured. Please manually add your key and re-run the script."
        exit 1
    fi
}

# Generate SSH key
generate_ssh_key() {
    SSH_DIR="$HOME/.ssh"
    DEFAULT_SSH_KEY="$SSH_DIR/id_ed25519"
    defaultEmail=$(git config --global user.email)
    defaultEmail=${defaultEmail:-"name@crisistextline.org"}

    echo "🔑 Generating new SSH key..."
    read -p "Enter your email for SSH key (default: $defaultEmail): " email
    email=${email:-$defaultEmail}

    read -p "Enter the path to store the SSH key (default: $DEFAULT_SSH_KEY): " key_path
    key_path=${key_path:-$DEFAULT_SSH_KEY}

    key_path="${key_path/#\~/$HOME}"

    mkdir -p "$(dirname "$key_path")"
    ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""
    update_ssh_config "$key_path"
    echo "⚠️ Add your SSH key to GitHub: https://github.com/settings/keys"
    echo "🔗 Public Key:"
    echo ""
    cat "${key_path}.pub"
    echo ""
    read -p "Press Enter after adding your key to GitHub..."
    test_ssh_connection
}

# Update SSH config
update_ssh_config() {
    local key_path="$1"
    local ssh_config="$HOME/.ssh/config"

    key_path="${key_path/#\~/$HOME}"

    echo "🔍 Checking SSH config for GitHub identity file..."

    # Ensure SSH config exists
    mkdir -p "$(dirname "$ssh_config")"
    touch "$ssh_config" && chmod 600 "$ssh_config"
    echo "✅ Created SSH config file."

    if grep -q "Host github.com" "$ssh_config"; then
        if grep -q "IdentityFile" "$ssh_config"; then
            sed -i.bak "/Host github.com/,/IdentityFile/s|IdentityFile .*|IdentityFile $key_path|" "$ssh_config"
            echo "🔄 Updated IdentityFile for GitHub."
        else
            sed -i.bak "/Host github.com/a \ \ IdentityFile $key_path" "$ssh_config"
            echo "➕ Added IdentityFile for GitHub."
        fi
    else
        echo -e "Host github.com\n  AddKeysToAgent yes\n  UseKeychain yes\n  IdentityFile $key_path" >> "$ssh_config"
        echo "📝 Added GitHub host entry to SSH config."
    fi
}

# Configure Go for private repositories
configure_go() {
    echo "⚙️  Configuring Go for private repositories..."

    ZSHRC="$HOME/.zshrc"
    if ! grep -q 'export PATH=$PATH:$(go env GOPATH)/bin' "$ZSHRC"; then
        echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$ZSHRC"
        echo "✅  Updated PATH in $ZSHRC"
    else
        echo "✅  GOPATH already configured."
    fi

    if [[ "$(go env GOPRIVATE)" != "github.com/$GITHUB_ORG/*" ]]; then
        go env -w GOPRIVATE="github.com/$GITHUB_ORG/*"
        echo "✅  GOPRIVATE configured."
    else
        echo "✅  GOPRIVATE already configured."
    fi

    if ! git config --global --get-regexp 'url.git@github.com:.insteadOf' &>/dev/null; then
        git config --global url."git@github.com:".insteadOf "https://github.com/"
        echo "✅  Git configured for SSH."
    else
        echo "✅  Git already configured for SSH."
    fi
}

# Install the dev-cli
install_dev_cli() {
    if command_exists ctl; then
        echo "✅  dev-cli is already installed."
        return 0
    fi

    echo "🚀 Installing dev-cli..."
    go install "$DEV_CLI_REPO@latest"

    if command_exists ctl; then
        echo "✅  dev-cli installed successfully!"
    else
        echo "❌ Installation failed."
        exit 1
    fi
}

# Main execution
main() {
    install_xcode
    install_homebrew
    install_git_go
    install_docker_orbstack
    configure_ssh
    configure_go
    install_dev_cli
    echo "🎉 Setup complete!"
}

main
