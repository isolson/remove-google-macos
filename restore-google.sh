#!/bin/bash
# =============================================================================
# restore-google.sh
# Restores Google software that was removed by remove-google.sh.
# Searches ~/.Trash/ for trashed items and moves them back to their
# original locations.
#
# Usage:
#   bash restore-google.sh scan      # Show what can be restored
#   bash restore-google.sh all       # Restore everything found
#   bash restore-google.sh dryrun    # Preview without changes
# =============================================================================

set -euo pipefail

TRASH="$HOME/.Trash"
DRY_RUN=false
RESTORED=0
ERRORS=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_found()  { echo -e "  ${GREEN}[FOUND]${NC} $*"; }
log_clean()  { echo -e "  ${BLUE}[CLEAN]${NC} $*"; }
log_dry()    { echo -e "  ${CYAN}[DRY RUN]${NC} Would restore: $*"; }
log_action() { echo -e "  ${GREEN}[DONE]${NC} $*"; }
log_warn()   { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
log_error()  { echo -e "  ${RED}[ERROR]${NC} $*"; ERRORS=$((ERRORS + 1)); }

# ---------------------------------------------------------------------------
# Restore map: parallel arrays of trash basenames and original paths.
# This covers everything remove-google.sh might have trashed.
# ---------------------------------------------------------------------------

RESTORE_NAMES=(
    # LaunchAgents / LaunchDaemons
    "com.google.keystone.agent.plist"
    "com.google.keystone.xpcservice.plist"
    "com.google.keystone.daemon.plist"
    "com.google.GoogleUpdater.wake.system.plist"
    "com.google.GoogleUpdater.wake.login.plist"
    # Applications
    "Google Chrome.app"
    "Google Earth Pro.app"
    "Google Drive.app"
    # System directories
    "Google"
    # User data
    "com.google.GoogleUpdater"
    "com.google.Chrome.plist"
    "com.google.GECommonSettings.plist"
    "com.google.GoogleEarthPro.plist"
    "com.google.Keystone.Agent.plist"
    "com.google.Chrome"
    "GoogleSoftwareUpdateAgent.log"
)

RESTORE_PATHS=(
    # LaunchAgents / LaunchDaemons
    "/Library/LaunchAgents/com.google.keystone.agent.plist"
    "/Library/LaunchAgents/com.google.keystone.xpcservice.plist"
    "/Library/LaunchDaemons/com.google.keystone.daemon.plist"
    "/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist"
    "$HOME/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist"
    # Applications
    "/Applications/Google Chrome.app"
    "/Applications/Google Earth Pro.app"
    "/Applications/Google Drive.app"
    # System directories
    "/Library/Google"
    # User data
    "$HOME/Library/Caches/com.google.GoogleUpdater"
    "$HOME/Library/Preferences/com.google.Chrome.plist"
    "$HOME/Library/Preferences/com.google.GECommonSettings.plist"
    "$HOME/Library/Preferences/com.google.GoogleEarthPro.plist"
    "$HOME/Library/Preferences/com.google.Keystone.Agent.plist"
    "$HOME/Library/WebKit/com.google.Chrome"
    "$HOME/Library/Logs/GoogleSoftwareUpdateAgent.log"
)

# ---------------------------------------------------------------------------
# Search for items in Trash (including timestamp-suffixed collisions)
# ---------------------------------------------------------------------------

find_in_trash() {
    local name="$1"

    # Exact match first
    if [ -e "$TRASH/$name" ]; then
        echo "$TRASH/$name"
        return 0
    fi

    # Timestamp-suffixed match (from safe_trash collision handling)
    for candidate in "$TRASH/${name}_"[0-9]*; do
        if [ -e "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
}

safe_restore() {
    local trash_path="$1"
    local dest_path="$2"
    local use_sudo="${3:-false}"

    if [ "$DRY_RUN" = true ]; then
        log_dry "$trash_path -> $dest_path"
        RESTORED=$((RESTORED + 1))
        return 0
    fi

    # Don't overwrite existing files
    if [ -e "$dest_path" ]; then
        log_warn "Skipping, already exists: $dest_path"
        return 0
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$dest_path")
    if [ ! -d "$parent_dir" ]; then
        if [ "$use_sudo" = true ]; then
            sudo mkdir -p "$parent_dir"
        else
            mkdir -p "$parent_dir"
        fi
    fi

    if [ "$use_sudo" = true ]; then
        sudo mv "$trash_path" "$dest_path"
    else
        mv "$trash_path" "$dest_path"
    fi

    log_action "Restored: $dest_path"
    RESTORED=$((RESTORED + 1))
}

needs_sudo() {
    local path="$1"
    case "$path" in
        /Library/*|/Applications/*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Remove blocker file if present
# ---------------------------------------------------------------------------

remove_blocker() {
    local blocker="$HOME/Library/Google"
    if [ -f "$blocker" ] && [ ! -d "$blocker" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${CYAN}[DRY RUN]${NC} Would remove blocker file: $blocker"
        else
            chmod 644 "$blocker" 2>/dev/null || true
            rm "$blocker"
            log_action "Removed blocker file: $blocker"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------

scan() {
    echo -e "\n${GREEN}=== Scanning Trash for Google items ===${NC}\n"
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
            log_found "$trash_path ($size) -> $dest"
            found=$((found + 1))
        fi
        i=$((i + 1))
    done

    # Check for blocker file
    if [ -f "$HOME/Library/Google" ] && [ ! -d "$HOME/Library/Google" ]; then
        echo -e "\n  ${YELLOW}[BLOCKER]${NC} ~/Library/Google blocker file exists (will be removed on restore)"
        found=$((found + 1))
    fi

    echo ""
    if [ "$found" -eq 0 ]; then
        echo -e "${YELLOW}No Google items found in Trash. Nothing to restore.${NC}"
        echo -e "${BLUE}(Items are only available until you empty the Trash.)${NC}"
    else
        echo -e "${GREEN}Found $found restorable item(s). Run 'all' to restore.${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Restore all
# ---------------------------------------------------------------------------

restore_all() {
    echo -e "\n${GREEN}=== Restoring Google items from Trash ===${NC}\n"

    # Remove blocker first
    remove_blocker

    # Check if sudo will be needed
    local sudo_needed=false
    local i=0
    while [ $i -lt ${#RESTORE_NAMES[@]} ]; do
        local name="${RESTORE_NAMES[$i]}"
        local dest="${RESTORE_PATHS[$i]}"
        local trash_path
        trash_path=$(find_in_trash "$name")
        if [ -n "$trash_path" ]; then
            if needs_sudo "$dest"; then
                sudo_needed=true
                break
            fi
        fi
        i=$((i + 1))
    done

    if [ "$sudo_needed" = true ] && [ "$DRY_RUN" = false ]; then
        echo -e "${YELLOW}System-level items found. sudo will be required.${NC}"
        echo -e "${YELLOW}Proceed with restore? (yes/no)${NC}"
        read -r response
        if [ "$response" != "yes" ]; then
            echo -e "${BLUE}Restore cancelled.${NC}"
            return 0
        fi
    fi

    # Restore items
    i=0
    while [ $i -lt ${#RESTORE_NAMES[@]} ]; do
        local name="${RESTORE_NAMES[$i]}"
        local dest="${RESTORE_PATHS[$i]}"
        local trash_path
        trash_path=$(find_in_trash "$name")
        if [ -n "$trash_path" ]; then
            local use_sudo="false"
            if needs_sudo "$dest"; then
                use_sudo="true"
            fi
            safe_restore "$trash_path" "$dest" "$use_sudo"
        fi
        i=$((i + 1))
    done

    # Reload any restored plists
    echo -e "\n${BOLD}Reloading restored services:${NC}"
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
                log_dry "Would reload: $plist"
            else
                case "$plist" in
                    /Library/*)
                        sudo launchctl load -w "$plist" 2>/dev/null || true
                        ;;
                    *)
                        launchctl load -w "$plist" 2>/dev/null || true
                        ;;
                esac
                log_action "Reloaded: $plist"
            fi
        fi
    done

    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Restore Complete${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "  Items restored:  ${GREEN}$RESTORED${NC}"
    echo -e "  Errors:          ${RED}$ERRORS${NC}"
    echo -e "${GREEN}================================================${NC}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local cmd="${1:-help}"

    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Google Software Restore Script${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo -e "  Trash location:  ${BLUE}$TRASH${NC}"
    echo -e "  Current user:    ${BLUE}$(whoami)${NC}"
    echo ""

    case "$cmd" in
        scan)
            scan
            ;;
        all)
            restore_all
            ;;
        dryrun)
            DRY_RUN=true
            restore_all
            echo -e "\n${CYAN}DRY RUN complete. No changes were made.${NC}"
            ;;
        *)
            echo "Usage: bash restore-google.sh <command>"
            echo ""
            echo "Commands:"
            echo "  scan     Search Trash for restorable Google items"
            echo "  all      Restore all Google items from Trash"
            echo "  dryrun   Preview restore without changes"
            echo ""
            echo "Note: Items are only available until you empty the Trash."
            ;;
    esac
}

main "$@"
