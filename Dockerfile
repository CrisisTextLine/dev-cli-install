# Use Debian Slim as the base image
FROM debian:bullseye-slim

# Install required packages (curl, bash, git, sudo)
RUN apt-get update && \
    apt-get install -y \
    curl \
    bash \
    nano \
    build-essential \
    git \
    sudo && \
    rm -rf /var/lib/apt/lists/*  # Clean up cache to reduce image size

# Create a non-root user and set up necessary permissions
RUN useradd -m -s /bin/bash developer && \
    echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to the non-root user
USER developer
WORKDIR /home/developer

# Install Homebrew, skipping ARM check
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true && \
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc

# Set Homebrew environment variables
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"

# Default to interactive shell
CMD ["/bin/bash"]