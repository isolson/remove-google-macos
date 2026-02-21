#!/bin/bash
# =============================================================================
# remove-google.sh
# Safely removes all Google software from macOS, or restores it from Trash.
#
# Double-click "Remove Google.command" or run: bash remove-google.sh
# =============================================================================

set -euo pipefail

TRASH="$HOME/.Trash"
DRY_RUN=false
REMOVED=0
RESTORED=0
ERRORS=0
CURRENT_UID=$(id -u)
AUDIT_COUNT=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Known Google paths
# ---------------------------------------------------------------------------

USER_LAUNCH_AGENTS=(
    "$HOME/Library/LaunchAgents/com.google.keystone.agent.plist"
    "$HOME/Library/LaunchAgents/com.google.keystone.xpcservice.plist"
    "$HOME/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist"
)

SYSTEM_LAUNCH_AGENTS=(
    "/Library/LaunchAgents/com.google.keystone.agent.plist"
    "/Library/LaunchAgents/com.google.keystone.xpcservice.plist"
)

SYSTEM_LAUNCH_DAEMONS=(
    "/Library/LaunchDaemons/com.google.keystone.daemon.plist"
    "/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist"
)

GOOGLE_APPS=(
    "/Applications/Google Chrome.app"
    "/Applications/Google Earth Pro.app"
    "/Applications/Google Drive.app"
)

SYSTEM_DIRS=(
    "/Library/Google"
    "/Library/Application Support/Google"
)

USER_DIRS=(
    "$HOME/Library/Google"
    "$HOME/Library/Application Support/Google"
)

USER_GLOB_PREFIXES=(
    "$HOME/Library/Caches/com.google."
    "$HOME/Library/Preferences/com.google."
    "$HOME/Library/Containers/com.google."
    "$HOME/Library/HTTPStorages/com.google."
    "$HOME/Library/Saved Application State/com.google."
    "$HOME/Library/WebKit/com.google."
)

GOOGLE_LOGS=(
    "$HOME/Library/Logs/GoogleSoftwareUpdateAgent.log"
)

GOOGLE_PROCESSES=(
    "GoogleUpdater"
    "GoogleSoftwareUpdateAgent"
    "GoogleSoftwareUpdateDaemon"
    "Google Chrome Helper"
    "Google Chrome"
    "Google Earth Pro"
    "keystone"
    "ksinstall"
    "ksadmin"
)

# Restore map: parallel arrays (bash 3.2 compatible)
RESTORE_NAMES=(
    "com.google.keystone.agent.plist"
    "com.google.keystone.xpcservice.plist"
    "com.google.keystone.daemon.plist"
    "com.google.GoogleUpdater.wake.system.plist"
    "com.google.GoogleUpdater.wake.login.plist"
    "Google Chrome.app"
    "Google Earth Pro.app"
    "Google Drive.app"
    "Google"
    "com.google.GoogleUpdater"
    "com.google.Chrome.plist"
    "com.google.GECommonSettings.plist"
    "com.google.GoogleEarthPro.plist"
    "com.google.Keystone.Agent.plist"
    "com.google.Chrome"
    "GoogleSoftwareUpdateAgent.log"
)

RESTORE_PATHS=(
    "/Library/LaunchAgents/com.google.keystone.agent.plist"
    "/Library/LaunchAgents/com.google.keystone.xpcservice.plist"
    "/Library/LaunchDaemons/com.google.keystone.daemon.plist"
    "/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist"
    "$HOME/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist"
    "/Applications/Google Chrome.app"
    "/Applications/Google Earth Pro.app"
    "/Applications/Google Drive.app"
    "/Library/Google"
    "$HOME/Library/Caches/com.google.GoogleUpdater"
    "$HOME/Library/Preferences/com.google.Chrome.plist"
    "$HOME/Library/Preferences/com.google.GECommonSettings.plist"
    "$HOME/Library/Preferences/com.google.GoogleEarthPro.plist"
    "$HOME/Library/Preferences/com.google.Keystone.Agent.plist"
    "$HOME/Library/WebKit/com.google.Chrome"
    "$HOME/Library/Logs/GoogleSoftwareUpdateAgent.log"
)

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log_info()   { echo -e "  ${BLUE}[INFO]${NC} $*"; }
log_warn()   { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
log_error()  { echo -e "  ${RED}[ERROR]${NC} $*"; ERRORS=$((ERRORS + 1)); }
log_found()  { echo -e "  ${RED}[FOUND]${NC} $*"; }
log_clean()  { echo -e "  ${GREEN}[CLEAN]${NC} $*"; }
log_action() { echo -e "  ${GREEN}[DONE]${NC} $*"; }

safe_trash() {
    local src="$1"
    local use_sudo="${2:-false}"

    if [ ! -e "$src" ]; then
        return 0
    fi

    local basename
    basename=$(basename "$src")

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${CYAN}[DRY RUN]${NC} Would trash: $src"
        REMOVED=$((REMOVED + 1))
        return 0
    fi

    # Handle name collisions in Trash
    local dest_path="$TRASH/$basename"
    if [ -e "$dest_path" ]; then
        dest_path="$TRASH/${basename}_$(date +%s)"
    fi

    if [ "$use_sudo" = true ]; then
        sudo mv "$src" "$dest_path"
    else
        mv "$src" "$dest_path"
    fi

    log_action "Trashed: $src"
    REMOVED=$((REMOVED + 1))
}

safe_unload() {
    local plist="$1"
    local domain="$2"
    local use_sudo="${3:-false}"

    if [ ! -f "$plist" ]; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${CYAN}[DRY RUN]${NC} Would unload: $plist"
        return 0
    fi

    local label
    label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || true)

    if [ -n "$label" ]; then
        if [ "$use_sudo" = true ]; then
            sudo launchctl bootout "$domain/$label" 2>/dev/null || true
        else
            launchctl bootout "$domain/$label" 2>/dev/null || true
        fi
        log_action "Unloaded service: $label"
    else
        if [ "$use_sudo" = true ]; then
            sudo launchctl unload -w "$plist" 2>/dev/null || true
        else
            launchctl unload -w "$plist" 2>/dev/null || true
        fi
        log_action "Unloaded: $(basename "$plist")"
    fi
}

find_in_trash() {
    local name="$1"
    if [ -e "$TRASH/$name" ]; then
        echo "$TRASH/$name"
        return 0
    fi
    for candidate in "$TRASH/${name}_"[0-9]*; do
        if [ -e "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
}

needs_sudo() {
    local path="$1"
    case "$path" in
        /Library/*|/Applications/*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Audit — runs automatically, returns count of items found
# ---------------------------------------------------------------------------

run_audit() {
    echo -e "\n${GREEN}=== Scanning for Google Software ===${NC}"
    AUDIT_COUNT=0

    # Running processes
    echo -e "\n${BOLD}Running Google processes:${NC}"
    local proc_found=false
    for proc in "${GOOGLE_PROCESSES[@]}"; do
        if pgrep -f "$proc" >/dev/null 2>&1; then
            log_found "Process: $proc (PID: $(pgrep -f "$proc" | tr '\n' ' '))"
            proc_found=true
            AUDIT_COUNT=$((AUDIT_COUNT + 1))
        fi
    done
    if [ "$proc_found" = false ]; then
        log_clean "No Google processes running"
    fi

    # Loaded launchctl services
    echo -e "\n${BOLD}Loaded Google services (launchctl):${NC}"
    local services
    services=$(launchctl list 2>/dev/null | grep -i google || true)
    if [ -n "$services" ]; then
        while IFS= read -r line; do
            log_found "Service: $line"
        done <<< "$services"
        AUDIT_COUNT=$((AUDIT_COUNT + 1))
    else
        log_clean "No Google services loaded"
    fi

    # LaunchAgents and LaunchDaemons
    echo -e "\n${BOLD}Launch services (the hourly updater lives here):${NC}"
    local plist_found=false
    for plist in "${USER_LAUNCH_AGENTS[@]}" "${SYSTEM_LAUNCH_AGENTS[@]}" "${SYSTEM_LAUNCH_DAEMONS[@]}"; do
        if [ -f "$plist" ]; then
            log_found "$plist"
            AUDIT_COUNT=$((AUDIT_COUNT + 1))
            plist_found=true
        fi
    done
    if [ "$plist_found" = false ]; then
        log_clean "No Google launch service plists found"
    fi

    # Applications
    echo -e "\n${BOLD}Google applications:${NC}"
    local app_found=false
    for app in "${GOOGLE_APPS[@]}"; do
        if [ -d "$app" ]; then
            local size
            size=$(du -sh "$app" 2>/dev/null | cut -f1)
            log_found "$app ($size)"
            AUDIT_COUNT=$((AUDIT_COUNT + 1))
            app_found=true
        fi
    done
    if [ "$app_found" = false ]; then
        log_clean "No Google applications found"
    fi

    # System-level directories
    echo -e "\n${BOLD}System-level Google directories:${NC}"
    local sysdir_found=false
    for dir in "${SYSTEM_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            local size
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            log_found "$dir ($size)"
            AUDIT_COUNT=$((AUDIT_COUNT + 1))
            sysdir_found=true
        fi
    done
    if [ "$sysdir_found" = false ]; then
        log_clean "No system-level Google directories"
    fi

    # User-level directories
    echo -e "\n${BOLD}User-level Google directories:${NC}"
    local userdir_found=false
    for dir in "${USER_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            local size
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            log_found "$dir ($size)"
            AUDIT_COUNT=$((AUDIT_COUNT + 1))
            userdir_found=true
        fi
    done
    if [ "$userdir_found" = false ]; then
        log_clean "No user-level Google directories"
    fi

    # Caches, prefs, etc.
    echo -e "\n${BOLD}Caches, preferences, and data:${NC}"
    local glob_found=false
    for prefix in "${USER_GLOB_PREFIXES[@]}"; do
        for match in "${prefix}"*; do
            if [ -e "$match" ]; then
                local size
                size=$(du -sh "$match" 2>/dev/null | cut -f1)
                log_found "$match ($size)"
                AUDIT_COUNT=$((AUDIT_COUNT + 1))
                glob_found=true
            fi
        done
    done
    for match in "$HOME/Library/Group Containers/"*google* "$HOME/Library/Group Containers/"*Google*; do
        if [ -e "$match" ]; then
            log_found "$match"
            AUDIT_COUNT=$((AUDIT_COUNT + 1))
            glob_found=true
        fi
    done
    for logfile in "${GOOGLE_LOGS[@]}"; do
        if [ -f "$logfile" ]; then
            log_found "$logfile"
            AUDIT_COUNT=$((AUDIT_COUNT + 1))
            glob_found=true
        fi
    done
    if [ "$glob_found" = false ]; then
        log_clean "No user-level Google data"
    fi

    echo ""
    if [ "$AUDIT_COUNT" -eq 0 ]; then
        echo -e "${GREEN}No Google software found. Your system is clean.${NC}"
    else
        echo -e "${YELLOW}Found $AUDIT_COUNT Google item(s) on this Mac.${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Remove — the full removal flow
# ---------------------------------------------------------------------------

do_remove() {
    local dry_label=""
    if [ "$DRY_RUN" = true ]; then
        dry_label=" (DRY RUN)"
    fi

    # --- Stop processes and services ---
    echo -e "\n${GREEN}=== Stopping Google processes and services${dry_label} ===${NC}"

    local needs_sudo=false
    for plist in "${SYSTEM_LAUNCH_AGENTS[@]}" "${SYSTEM_LAUNCH_DAEMONS[@]}"; do
        if [ -f "$plist" ]; then
            needs_sudo=true
            break
        fi
    done
    for dir in "${SYSTEM_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            needs_sudo=true
            break
        fi
    done

    if [ "$needs_sudo" = true ] && [ "$DRY_RUN" = false ]; then
        echo -e "\n${YELLOW}Some Google files are in system directories and require your password (sudo).${NC}"
    fi

    for proc in "${GOOGLE_PROCESSES[@]}"; do
        if pgrep -f "$proc" >/dev/null 2>&1; then
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${CYAN}[DRY RUN]${NC} Would kill: $proc"
            else
                killall "$proc" 2>/dev/null || true
                log_action "Killed: $proc"
            fi
        fi
    done

    for plist in "${USER_LAUNCH_AGENTS[@]}"; do
        safe_unload "$plist" "gui/$CURRENT_UID" false
        safe_trash "$plist" false
    done
    for plist in "${SYSTEM_LAUNCH_AGENTS[@]}"; do
        safe_unload "$plist" "system" true
        safe_trash "$plist" true
    done
    for plist in "${SYSTEM_LAUNCH_DAEMONS[@]}"; do
        safe_unload "$plist" "system" true
        safe_trash "$plist" true
    done

    if [ "$DRY_RUN" = false ]; then
        sleep 1
    fi

    # --- Applications (ask about each one) ---
    echo -e "\n${GREEN}=== Google Applications${dry_label} ===${NC}"
    echo -e "  ${BLUE}You will be asked about each app individually.${NC}\n"

    for app in "${GOOGLE_APPS[@]}"; do
        if [ -d "$app" ]; then
            local app_name
            app_name=$(basename "$app")
            local size
            size=$(du -sh "$app" 2>/dev/null | cut -f1)
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${CYAN}[DRY RUN]${NC} Would ask to trash: $app ($size)"
                REMOVED=$((REMOVED + 1))
            else
                echo -e "  ${YELLOW}Remove ${app_name} (${size})? [y/n]${NC} "
                read -r response
                if [ "$response" = "y" ] || [ "$response" = "yes" ]; then
                    safe_trash "$app" true
                else
                    log_info "Kept: $app_name"
                fi
            fi
        fi
    done

    # --- System directories ---
    echo -e "\n${GREEN}=== System-level Google directories${dry_label} ===${NC}"
    for dir in "${SYSTEM_DIRS[@]}"; do
        safe_trash "$dir" true
    done

    # --- User data ---
    echo -e "\n${GREEN}=== User-level Google data${dry_label} ===${NC}"
    for dir in "${USER_DIRS[@]}"; do
        safe_trash "$dir" false
    done
    for prefix in "${USER_GLOB_PREFIXES[@]}"; do
        for match in "${prefix}"*; do
            if [ -e "$match" ]; then
                safe_trash "$match" false
            fi
        done
    done
    for match in "$HOME/Library/Group Containers/"*google* "$HOME/Library/Group Containers/"*Google*; do
        if [ -e "$match" ]; then
            safe_trash "$match" false
        fi
    done
    for logfile in "${GOOGLE_LOGS[@]}"; do
        safe_trash "$logfile" false
    done

    # --- Anti-reinstall blocker ---
    echo -e "\n${GREEN}=== Anti-reinstall blocker${dry_label} ===${NC}"
    local blocker="$HOME/Library/Google"
    if [ ! -e "$blocker" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${CYAN}[DRY RUN]${NC} Would create blocker file: $blocker (chmod 000)"
        else
            touch "$blocker"
            chmod 000 "$blocker"
            log_action "Created blocker: $blocker (prevents Keystone from reinstalling)"
        fi
    fi

    # --- Verification ---
    echo -e "\n${BOLD}Verification:${NC}"
    local remaining=0
    for proc in "${GOOGLE_PROCESSES[@]}"; do
        if pgrep -f "$proc" >/dev/null 2>&1; then
            log_warn "Process still running: $proc"
            remaining=$((remaining + 1))
        fi
    done
    local services
    services=$(launchctl list 2>/dev/null | grep -i google || true)
    if [ -n "$services" ]; then
        log_warn "Services still loaded (will clear after reboot):"
        echo "$services"
        remaining=$((remaining + 1))
    fi

    # --- Summary ---
    echo ""
    echo -e "${GREEN}================================================${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${GREEN}  Dry Run Complete — No changes were made${NC}"
    else
        echo -e "${GREEN}  Removal Complete${NC}"
    fi
    echo -e "${GREEN}================================================${NC}"
    echo -e "  Items trashed:    ${GREEN}$REMOVED${NC}"
    echo -e "  Errors:           ${RED}$ERRORS${NC}"
    if [ "$DRY_RUN" = false ]; then
        echo -e "  Items remaining:  ${YELLOW}$remaining${NC}"
    fi
    echo ""
    if [ "$DRY_RUN" = false ]; then
        if [ "$remaining" -eq 0 ]; then
            echo -e "  ${GREEN}System is clean of Google software.${NC}"
        else
            echo -e "  ${YELLOW}Some items remain. A reboot should clear them.${NC}"
        fi
        echo ""
        echo -e "  ${BLUE}All removed files are in ~/.Trash/ and can be${NC}"
        echo -e "  ${BLUE}restored by running this script again and choosing Restore.${NC}"
        echo ""
        echo -e "  ${YELLOW}A reboot is recommended.${NC}"
    fi
    echo -e "${GREEN}================================================${NC}"
}

# ---------------------------------------------------------------------------
# Restore — put things back from Trash
# ---------------------------------------------------------------------------

do_restore() {
    local dry_label=""
    if [ "$DRY_RUN" = true ]; then
        dry_label=" (DRY RUN)"
    fi

    echo -e "\n${GREEN}=== Scanning Trash for Google items${dry_label} ===${NC}\n"

    local found=0
    local i=0
    while [ $i -lt ${#RESTORE_NAMES[@]} ]; do
        local name="${RESTORE_NAMES[$i]}"
        local dest="${RESTORE_PATHS[$i]}"
        local trash_path
        trash_path=$(find_in_trash "$name")
        if [ -n "$trash_path" ]; then
            local size
            size=$(du -sh "$trash_path" 2>/dev/null | cut -f1)
            echo -e "  ${GREEN}[FOUND]${NC} $trash_path ($size) -> $dest"
            found=$((found + 1))
        fi
        i=$((i + 1))
    done

    # Blocker file
    local has_blocker=false
    if [ -f "$HOME/Library/Google" ] && [ ! -d "$HOME/Library/Google" ]; then
        echo -e "\n  ${YELLOW}[BLOCKER]${NC} ~/Library/Google blocker file will be removed"
        has_blocker=true
    fi

    if [ "$found" -eq 0 ] && [ "$has_blocker" = false ]; then
        echo -e "\n${YELLOW}No Google items found in Trash. Nothing to restore.${NC}"
        echo -e "${BLUE}(Items are only available until you empty the Trash.)${NC}"
        return 0
    fi

    echo -e "\n${GREEN}Found $found restorable item(s).${NC}"

    if [ "$DRY_RUN" = false ]; then
        echo -e "\n${YELLOW}Restore these items? [y/n]${NC}"
        read -r response
        if [ "$response" != "y" ] && [ "$response" != "yes" ]; then
            echo -e "${BLUE}Restore cancelled.${NC}"
            return 0
        fi
    fi

    # Remove blocker
    if [ "$has_blocker" = true ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${CYAN}[DRY RUN]${NC} Would remove blocker file: ~/Library/Google"
        else
            chmod 644 "$HOME/Library/Google" 2>/dev/null || true
            rm "$HOME/Library/Google"
            log_action "Removed blocker file: ~/Library/Google"
        fi
    fi

    # Restore items
    echo -e "\n${GREEN}=== Restoring${dry_label} ===${NC}\n"

    i=0
    while [ $i -lt ${#RESTORE_NAMES[@]} ]; do
        local name="${RESTORE_NAMES[$i]}"
        local dest="${RESTORE_PATHS[$i]}"
        local trash_path
        trash_path=$(find_in_trash "$name")
        if [ -n "$trash_path" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${CYAN}[DRY RUN]${NC} Would restore: $trash_path -> $dest"
                RESTORED=$((RESTORED + 1))
            elif [ -e "$dest" ]; then
                log_warn "Skipping, already exists: $dest"
            else
                local parent_dir
                parent_dir=$(dirname "$dest")
                if [ ! -d "$parent_dir" ]; then
                    if needs_sudo "$dest"; then
                        sudo mkdir -p "$parent_dir"
                    else
                        mkdir -p "$parent_dir"
                    fi
                fi
                if needs_sudo "$dest"; then
                    sudo mv "$trash_path" "$dest"
                else
                    mv "$trash_path" "$dest"
                fi
                log_action "Restored: $dest"
                RESTORED=$((RESTORED + 1))
            fi
        fi
        i=$((i + 1))
    done

    # Reload plists
    echo -e "\n${BOLD}Reloading services:${NC}"
    local plists=(
        "/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist"
        "/Library/LaunchDaemons/com.google.keystone.daemon.plist"
        "/Library/LaunchAgents/com.google.keystone.agent.plist"
        "/Library/LaunchAgents/com.google.keystone.xpcservice.plist"
        "$HOME/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist"
    )
    for plist in "${plists[@]}"; do
        if [ -f "$plist" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${CYAN}[DRY RUN]${NC} Would reload: $plist"
            else
                case "$plist" in
                    /Library/*)
                        sudo launchctl load -w "$plist" 2>/dev/null || true
                        ;;
                    *)
                        launchctl load -w "$plist" 2>/dev/null || true
                        ;;
                esac
                log_action "Reloaded: $(basename "$plist")"
            fi
        fi
    done

    echo ""
    echo -e "${GREEN}================================================${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${GREEN}  Dry Run Complete — No changes were made${NC}"
    else
        echo -e "${GREEN}  Restore Complete${NC}"
    fi
    echo -e "${GREEN}================================================${NC}"
    echo -e "  Items restored:  ${GREEN}$RESTORED${NC}"
    echo -e "  Errors:          ${RED}$ERRORS${NC}"
    echo -e "${GREEN}================================================${NC}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Remove Google from macOS${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo -e "  ${BLUE}Nothing is permanently deleted — files are moved to Trash.${NC}"
    echo -e "  ${BLUE}You choose which apps to remove. Everything else is automatic.${NC}"
    echo ""

    # Always run audit first
    run_audit

    if [ "$AUDIT_COUNT" -eq 0 ]; then
        # Nothing found — offer restore only
        echo ""
        echo -e "What would you like to do?"
        echo ""
        echo -e "  1) Restore  — put Google items back from Trash"
        echo -e "  2) Quit"
        echo ""
        read -rp "Enter choice [1-2]: " choice
        case "$choice" in
            1) do_restore ;;
            *) echo "Bye." ;;
        esac
        return
    fi

    echo ""
    echo -e "What would you like to do?"
    echo ""
    echo -e "  1) Remove   — remove Google software (asks about each app)"
    echo -e "  2) Dry run  — preview what would happen (no changes)"
    echo -e "  3) Restore  — put previously removed items back from Trash"
    echo -e "  4) Quit"
    echo ""
    read -rp "Enter choice [1-4]: " choice

    case "$choice" in
        1)
            do_remove
            ;;
        2)
            DRY_RUN=true
            do_remove
            ;;
        3)
            do_restore
            ;;
        *)
            echo "Bye."
            ;;
    esac
}

main
