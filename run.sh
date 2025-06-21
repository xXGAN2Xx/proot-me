#!/bin/sh

# Color definitions
PURPLE='\033[0;35m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration
HOSTNAME="MyVPS"
HISTORY_FILE="${HOME}/.custom_shell_history"
MAX_HISTORY=1000

# Check if not installed
if [ ! -e "/.installed" ]; then
    # Check if rootfs.tar.xz or rootfs.tar.gz exists and remove them if they do
    if [ -f "/rootfs.tar.xz" ]; then
        rm -f "/rootfs.tar.xz"
    fi
    
    if [ -f "/rootfs.tar.gz" ]; then
        rm -f "/rootfs.tar.gz"
    fi
    
    # Wipe the files we downloaded into /tmp previously
    rm -rf /tmp/sbin
    
    # Mark as installed.
    touch "/.installed"
fi

# Check if the autorun script exists
if [ ! -e "/autorun.sh" ]; then
    touch /autorun.sh
    chmod +x /autorun.sh
fi

printf "\033c"
printf "${GREEN}Starting..${NC}\n"
sleep 1
printf "\033c"

# Logger function
log() {
    level=$1
    message=$2
    color=$3
    
    if [ -z "$color" ]; then
        color=${NC}
    fi
    
    printf "${color}[$level]${NC} $message\n"
}

# Function to handle cleanup on exit
cleanup() {
    log "INFO" "Session ended. Goodbye!" "$GREEN"
    exit 0
}

# Function to detect the machine architecture
detect_architecture() {
    # Detect the machine architecture.
    ARCH=$(uname -m)

    # Detect architecture and return the corresponding value
    case "$ARCH" in
        x86_64)
            echo "amd64"
        ;;
        aarch64)
            echo "arm64"
        ;;
        riscv64)
            echo "riscv64"
        ;;
        *)
            log "ERROR" "Unsupported CPU architecture: $ARCH" "$RED"
        ;;
    esac
}

# Function to get formatted directory
get_formatted_dir() {
    current_dir="$PWD"
    case "$current_dir" in
        "$HOME"*)
            printf "~${current_dir#$HOME}"
        ;;
        *)
            printf "$current_dir"
        ;;
    esac
}

print_instructions() {
    log "INFO" "Type 'help' to view a list of available custom commands." "$YELLOW"
}

# Function to print prompt
print_prompt() {
    user="$1"
    printf "\n${GREEN}${user}@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}# "
}

# Function to save command to history
save_to_history() {
    cmd="$1"
    if [ -n "$cmd" ] && [ "$cmd" != "exit" ]; then
        printf "$cmd\n" >> "$HISTORY_FILE"
        # Keep only last MAX_HISTORY lines
        if [ -f "$HISTORY_FILE" ]; then
            tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
            mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
        fi
    fi
}

# Function reinstall the OS
reinstall() {
    # Source the /etc/os-release file to get OS information
    . /etc/os-release

    printf "${YELLOW}Are you sure you want to reinstall the OS? This will wipe all data. (yes/no): ${NC}"
    read -r confirmation
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Reinstallation cancelled." "$YELLOW"
        return
    fi
    
    log "INFO" "Proceeding with reinstallation..." "$GREEN"
    if [ "$ID" = "alpine" ] || [ "$ID" = "chimera" ]; then
        rm -rf / > /dev/null 2>&1
    else
        rm -rf --no-preserve-root / > /dev/null 2>&1
    fi
}

# Function to install wget
install_wget() {
    distro=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    
    case "$distro" in
        "debian"|"ubuntu"|"devuan"|"linuxmint"|"kali")
            apt-get update -qq && apt-get install -y -qq wget > /dev/null 2>&1
        ;;
        "void")
            xbps-install -Syu -q wget > /dev/null 2>&1
        ;;
        "centos"|"fedora"|"rocky"|"almalinux"|"openEuler"|"amzn"|"ol")
            yum install -y -q wget > /dev/null 2>&1
        ;;
        "opensuse"|"opensuse-tumbleweed"|"opensuse-leap")
            zypper install -y -q wget > /dev/null 2>&1
        ;;
        "alpine"|"chimera")
            apk add --no-scripts -q wget > /dev/null 2>&1
        ;;
        "gentoo")
            emerge --sync -q && emerge -q wget > /dev/null 2>&1
        ;;
        "arch")
            pacman -Syu --noconfirm --quiet wget > /dev/null 2>&1
        ;;
        "slackware")
            yes | slackpkg install wget > /dev/null 2>&1
        ;;
        *)
            log "ERROR" "Unsupported distribution: $distro" "$RED"
            return 1
        ;;
    esac
}

# Function to install SSH from the repository
install_ssh() {
    # Check if SSH is already installed
    if [ -f "/usr/local/bin/ssh" ]; then
        log "ERROR" "SSH is already installed." "$RED"
        return 1
    fi

    # Install wget if not found
    if ! command -v wget &> /dev/null; then
        log "INFO" "Installing wget." "$YELLOW"
        install_wget
    fi
    
    log "INFO" "Installing SSH." "$YELLOW"
    
    # Determine the architecture
    arch=$(detect_architecture)
    
    # URL to download the SSH binary
    url="https://github.com/ysdragon/ssh/releases/latest/download/ssh-$arch"
    
    # Download the SSH binary
    wget -q -O /usr/local/bin/ssh "$url" || {
        log "ERROR" "Failed to download SSH." "$RED"
        return 1
    }
    
    # Make the binary executable
    chmod +x /usr/local/bin/ssh || {
        log "ERROR" "Failed to make ssh executable." "$RED"
        return 1
    }    

    log "SUCCESS" "SSH installed successfully." "$GREEN"
}

# Function to show system status
show_system_status() {
    log "INFO" "System Status:" "$GREEN"
    uptime
    free -h
    df -h
    ps aux --sort=-%mem | head -n 10
}

# Function to create a backup
create_backup() {
    # Check if tar is installed
    if ! command -v tar > /dev/null 2>&1; then
        log "ERROR" "tar is not installed. Please install tar first." "$RED"
        return 1
    fi
    
    backup_file="/backup_$(date +%Y%m%d%H%M%S).tar.gz"
    log "INFO" "Starting backup process..." "$YELLOW"
    tar -czf "$backup_file" / --exclude="$backup_file" --exclude="/proc" --exclude="/tmp" --exclude="/dev" --exclude="/sys" --exclude="/run" --exclude="/vps.config" > /dev/null 2>&1
    log "SUCCESS" "Backup created at $backup_file" "$GREEN"
}

# Function to restore a backup
restore_backup() {
    backup_file="$1"
    
    # Check if tar is installed
    if ! command -v tar > /dev/null 2>&1; then
        log "ERROR" "tar is not installed. Please install tar first." "$RED"
        return 1
    fi
    
    if [ -z "$backup_file" ]; then
        log "INFO" "Usage: restore <backup_file>" "$YELLOW"
        log "INFO" "Example: restore backup_20250620024221.tar.gz" "$YELLOW"
        return 1
    fi

    if [ -f "/$backup_file" ]; then
        log "INFO" "Starting restore process..." "$YELLOW"
        tar -xzf "/$backup_file" -C / --exclude="/$backup_file" --exclude="/proc" --exclude="/tmp" --exclude="/dev" --exclude="/sys" --exclude="/run" --exclude="/vps.config" > /dev/null 2>&1
        log "SUCCESS" "Backup restored from $backup_file" "$GREEN"
    else
        log "ERROR" "Backup file not found: $backup_file" "$RED"
    fi
}

# Function to print initial banner
print_banner() {
    printf "${GREEN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                           ${PURPLE}Done (s)! For help, type "help"${GREEN}  ┃${NC}\n" 
    printf "${GREEN}┃                           ${PURPLE} Pterodactyl VPS EGG ${GREEN}                             ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┃                          ${RED}© 2021 - $(date +%Y) ${PURPLE}@ysdragon${GREEN}                            ┃${NC}\n"
    printf "${GREEN}┃                                                                             ┃${NC}\n"
    printf "${GREEN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
}

# Function to print a beautiful help message
print_help_message() {
    printf "${PURPLE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┃                          ${GREEN}✦ Available Commands ✦${PURPLE}                             ┃${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}clear, cls${GREEN}         ❯  Clear the screen                                  ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}exit${GREEN}               ❯  Shutdown the server                               ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}history${GREEN}            ❯  Show command history                              ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}reinstall${GREEN}          ❯  Reinstall the server                              ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}install-ssh${GREEN}        ❯  Install our custom SSH server                     ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}status${GREEN}             ❯  Show system status                                ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}backup${GREEN}             ❯  Create a system backup                            ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}restore${GREEN}            ❯  Restore a system backup                           ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}help${GREEN}               ❯  Display this help message                         ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
}

# Function to handle command execution
execute_command() {
    cmd="$1"
    user="$2"
    
    # Save command to history
    save_to_history "$cmd"
    
    # Handle special commands
    case "$cmd" in
        "clear"|"cls")
            print_banner
            print_prompt "$user"
            return 0
        ;;
        "exit"|"stop")
            cleanup
        ;;
        "history")
            if [ -f "$HISTORY_FILE" ]; then
                cat "$HISTORY_FILE"
            fi
            print_prompt "$user"
            return 0
        ;;
        "reinstall")
            log "INFO" "Reinstalling...." "$GREEN"
            reinstall
            exit 2
        ;;
        "sudo"|"su")
            log "ERROR" "You are already running as root." "$RED"
            print_prompt "$user"
            return 0
        ;;
        "install-ssh")
            install_ssh
            print_prompt "$user"
            return 0
        ;;
        "status")
            show_system_status
            print_prompt "$user"
            return 0
        ;;
        "backup")
            create_backup
            print_prompt "$user"
            return 0
        ;;
        "restore "*)
            backup_file=$(echo "$cmd" | cut -d' ' -f2-)
            restore_backup "$backup_file"
            print_prompt "$user"
            return 0
        ;;
        "help")
            print_help_message
            print_prompt "$user"
            return 0
        ;;
        *)
            eval "$cmd"
            print_prompt "$user"
            return 0
        ;;
    esac
}

# Function to run command prompt for a specific user
run_prompt() {
    user="$1"
    read -r cmd
    
    execute_command "$cmd" "$user"
    print_prompt "$user"
}

# Create history file if it doesn't exist
touch "$HISTORY_FILE"

# Set up trap for clean exit
trap cleanup INT TERM

# Print the initial banner
print_banner

# Print the initial instructions
print_instructions

# Print initial command
printf "${GREEN}root@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}#\n"

# Execute autorun.sh
sh "/autorun.sh"

# Main command loop
while true; do
    run_prompt "user"
done
