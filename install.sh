#!/bin/bash
set -e  # Exit immediately on error
#set -x  # Enable debugging (this will print all commands to the console)
set -u  # Treat unset variables as an error
set -o pipefail  # Catch errors in piped commands

# Constants
ZSHRC="$HOME/.zshrc"
GITHUB_ORG="CrisisTextLine"
DEV_CLI_GITHUB="git@github.com:CrisisTextLine/dev-cli.git"
DEV_CLI_REPO="github.com/$GITHUB_ORG/dev-cli/cmd/ctl"

# Detect OS & Environment
OS_TYPE="$(uname)"

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prompt user before installation
prompt_install() {
    read -p "Do you want to install $1? (Y/n): " choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    [[ "$choice" == "" || "$choice" == "y" || "$choice" == "yes" ]]
}

# Install Xcode (macOS only)
install_xcode() {
    if [[ "$OS_TYPE" != "Darwin" ]]; then
        echo "⚠️  Skipping Xcode installation (not macOS)."
        return
    fi

    if command_exists xcode-select; then
        echo "✅  Xcode Command Line Tools already installed."
        return
    fi

    if prompt_install "Xcode Command Line Tools"; then
        echo "🔧  Installing Xcode Command Line Tools..."
        xcode-select --install
    else
        echo "🚀  Skipping Xcode installation."
    fi
}

# Install Homebrew
install_homebrew() {
    if command_exists brew; then
        echo "✅  Homebrew already installed."
        return
    fi

    if prompt_install "Homebrew"; then
        echo "🍺  Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"  # Ensure brew is in the path
    else
        echo "🚀  Skipping Homebrew installation."
    fi
}

# Install Git and Go if not installed
install_git_go() {
    missing_packages=""

    for pkg in git go; do
        if ! command_exists "$pkg"; then
            missing_packages="$missing_packages $pkg"
        fi
    done

    if [ -z "$missing_packages" ]; then
        echo "✅  Git and Go are already installed."
        return
    fi

    if prompt_install "$missing_packages"; then
        echo "⚙️  Installing missing packages: $missing_packages"
        brew install $missing_packages
    else
        echo "🚀  Skipping $missing_packages installation."
    fi
}

# Install Docker
install_docker() {
    if command_exists docker; then
        echo "✅  Docker is already installed."
        return
    fi

    if prompt_install "Docker"; then
        echo "🐳  Installing Docker..."
        brew install --cask docker
        echo "✅  Docker installed successfully."
    else
        echo "🚀  Skipping Docker installation."
    fi
}

# Configure SSH for GitHub
configure_ssh() {
    SSH_DIR="$HOME/.ssh"
    GITHUB_HOST="github.com"
    DEV_CLI_REPO="git@github.com:CrisisTextLine/dev-cli.git"

    # Ensure SSH directory and known_hosts file exist
    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
        echo "✅  SSH directory created."
    fi

    # Check if known_hosts file exists, if not, create it
    if [ ! -f "$SSH_DIR/known_hosts" ]; then
        touch "$SSH_DIR/known_hosts" && chmod 644 "$SSH_DIR/known_hosts"
        echo "✅  known_hosts file created."
    fi

    # Add GitHub SSH key to known_hosts if not already present
      if ! ssh-keygen -F "$GITHUB_HOST" -f "$SSH_DIR/known_hosts" >/dev/null; then
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
    set +e
    output=$(git ls-remote "$DEV_CLI_GITHUB" 2>&1)
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

    # Check if Git is configured
    if git config --global --get user.email &>/dev/null; then
        defaultEmail=$(git config --global user.email)
    else
        defaultEmail=""
    fi

    echo "Git user email fetched: '$defaultEmail'"

    # If no global email is set, ask the user for one
    if [ -z "$defaultEmail" ]; then
        echo "No global git email configured. Please enter an email for the SSH key."
        read -p "Enter your email for SSH key: " email
        email=${email:-"name@crisistextline.org"}  # Use the fallback email if none is provided
    else
        echo "Using git email: $defaultEmail"
        email="$defaultEmail"
    fi

    # Set default SSH key path
    read -p "Enter the path to store the SSH key (default: $DEFAULT_SSH_KEY): " key_path
    key_path=${key_path:-$DEFAULT_SSH_KEY}
    key_path="${key_path/#\~/$HOME}"

    mkdir -p "$(dirname "$key_path")"
    ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N "" || { echo "❌ SSH key generation failed."; exit 1; }
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

    # Ensure SSH config exists and is properly configured
    mkdir -p "$(dirname "$ssh_config")"
    touch "$ssh_config" && chmod 600 "$ssh_config"

    echo "🔍 Configuring SSH config for GitHub identity file..."

    # Check if the system is Darwin (macOS)
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS specific configuration
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
            echo "📝 Added GitHub host entry to SSH config (macOS)."
        fi
    else
        # Non-macOS systems (Linux, etc.)
        if grep -q "Host github.com" "$ssh_config"; then
            if grep -q "IdentityFile" "$ssh_config"; then
                sed -i.bak "/Host github.com/,/IdentityFile/s|IdentityFile .*|IdentityFile $key_path|" "$ssh_config"
                echo "🔄 Updated IdentityFile for GitHub."
            else
                sed -i.bak "/Host github.com/a \ \ IdentityFile $key_path" "$ssh_config"
                echo "➕ Added IdentityFile for GitHub."
            fi
        else
            echo -e "Host github.com\n  AddKeysToAgent yes\n  IdentityFile $key_path" >> "$ssh_config"
            echo "📝 Added GitHub host entry to SSH config (non-macOS)."
        fi
    fi
}


# Configure Go for private repositories
configure_go() {
    if [ ! -f "$ZSHRC" ]; then
        touch "$ZSHRC"
        echo "✅  $ZSHRC file created."
    fi

    if grep -q 'export PATH=$PATH:$(go env GOPATH)/bin' "$ZSHRC"; then
        echo "✅  GOPATH already configured in $ZSHRC."
    else
        if ! prompt_install "adding GOPATH to your PATH in $ZSHRC"; then
            echo "🚀  Skipping GOPATH configuration."
            return
        fi
        echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$ZSHRC"
        echo "✅  Updated PATH in $ZSHRC"
    fi

    # Check if GOPRIVATE is already configured
    if [[ "$(go env GOPRIVATE)" == "github.com/$GITHUB_ORG/*" ]]; then
        echo "✅  GOPRIVATE already configured."
    else
        if ! prompt_install "configuring GOPRIVATE for Go"; then
            echo "🚀  Skipping GOPRIVATE configuration."
            return
        fi
        go env -w GOPRIVATE="github.com/$GITHUB_ORG/*"
        echo "✅  GOPRIVATE configured."
    fi

    # Check if Git is already configured to use SSH for GitHub
    if git config --global --get-regexp 'url.git@github.com:.insteadOf' &>/dev/null; then
        echo "✅  Git already configured for SSH."
    else
        if ! prompt_install "configuring Git for SSH"; then
            echo "🚀  Skipping Git SSH configuration."
            return
        fi
        git config --global url."git@github.com:".insteadOf "https://github.com/"
        echo "✅  Git configured for SSH."
    fi
}

# Install the dev-cli
install_dev_cli() {
    if command_exists ctl; then
        echo "✅  dev-cli is already installed."
        return
    fi

    if prompt_install "dev-cli"; then
        echo "🚀  Installing dev-cli..."
        go install "$DEV_CLI_REPO@latest"
        echo "✅  dev-cli installed successfully."
    else
        echo "🚀  Skipping dev-cli installation."
    fi
}

# Main execution
main() {
    install_xcode
    install_homebrew
    install_git_go
    install_docker
    configure_ssh
    configure_go
    install_dev_cli
    echo "🎉 Install complete!"
}

main
