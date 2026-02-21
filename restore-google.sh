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
# Map of trashable basenames to their original paths.
# This covers everything remove-google.sh might have trashed.
# ---------------------------------------------------------------------------

declare -A RESTORE_MAP

# LaunchAgents / LaunchDaemons
RESTORE_MAP["com.google.keystone.agent.plist"]="/Library/LaunchAgents/com.google.keystone.agent.plist"
RESTORE_MAP["com.google.keystone.xpcservice.plist"]="/Library/LaunchAgents/com.google.keystone.xpcservice.plist"
RESTORE_MAP["com.google.keystone.daemon.plist"]="/Library/LaunchDaemons/com.google.keystone.daemon.plist"
RESTORE_MAP["com.google.GoogleUpdater.wake.system.plist"]="/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist"
RESTORE_MAP["com.google.GoogleUpdater.wake.login.plist"]="$HOME/Library/LaunchAgents/com.google.GoogleUpdater.wake.login.plist"

# Applications
RESTORE_MAP["Google Chrome.app"]="/Applications/Google Chrome.app"
RESTORE_MAP["Google Earth Pro.app"]="/Applications/Google Earth Pro.app"
RESTORE_MAP["Google Drive.app"]="/Applications/Google Drive.app"

# System directories
RESTORE_MAP["Google"]="/Library/Google"

# User directories
RESTORE_MAP["com.google.GoogleUpdater"]="$HOME/Library/Caches/com.google.GoogleUpdater"
RESTORE_MAP["com.google.Chrome.plist"]="$HOME/Library/Preferences/com.google.Chrome.plist"
RESTORE_MAP["com.google.GECommonSettings.plist"]="$HOME/Library/Preferences/com.google.GECommonSettings.plist"
RESTORE_MAP["com.google.GoogleEarthPro.plist"]="$HOME/Library/Preferences/com.google.GoogleEarthPro.plist"
RESTORE_MAP["com.google.Keystone.Agent.plist"]="$HOME/Library/Preferences/com.google.Keystone.Agent.plist"
RESTORE_MAP["com.google.Chrome"]="$HOME/Library/WebKit/com.google.Chrome"
RESTORE_MAP["GoogleSoftwareUpdateAgent.log"]="$HOME/Library/Logs/GoogleSoftwareUpdateAgent.log"

# ---------------------------------------------------------------------------
# Also search for items trashed with timestamp suffix (_1234567890)
# ---------------------------------------------------------------------------

find_in_trash() {
    local basename="$1"
    local matches=()

    # Exact match
    if [ -e "$TRASH/$basename" ]; then
        matches+=("$TRASH/$basename")
    fi

    # Timestamp-suffixed match (from safe_trash collision handling)
    for candidate in "$TRASH/${basename}_"[0-9]*; do
        if [ -e "$candidate" ]; then
            matches+=("$candidate")
        fi
    done

    if [ ${#matches[@]} -gt 0 ]; then
        echo "${matches[0]}"  # Return the first (most likely) match
    fi
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
            log_dry "Would remove blocker file: $blocker"
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

    for basename in "${!RESTORE_MAP[@]}"; do
        local trash_path
        trash_path=$(find_in_trash "$basename")
        if [ -n "$trash_path" ]; then
            local dest="${RESTORE_MAP[$basename]}"
            local size
            size=$(du -sh "$trash_path" 2>/dev/null | cut -f1)
            log_found "$trash_path ($size) -> $dest"
            found=$((found + 1))
        fi
    done

    # Check for blocker file
    if [ -f "$HOME/Library/Google" ] && [ ! -d "$HOME/Library/Google" ]; then
        echo -e "\n  ${YELLOW}[BLOCKER]${NC} ~/Library/Google blocker file exists (will be removed on restore)"
        found=$((found + 1))
    fi

    # Also scan for Application Support/Google
    local as_trash
    as_trash=$(find_in_trash "Google")
    # Check specifically for the user-level one (might have timestamp suffix)
    for candidate in "$TRASH/Google" "$TRASH/Google_"[0-9]*; do
        if [ -d "$candidate" ]; then
            # Determine if it's the /Library/Google or ~/Library/Application Support/Google
            # by checking contents
            if [ -d "$candidate/Chrome" ] || [ -d "$candidate/GoogleUpdater" ]; then
                log_found "$candidate -> likely Application Support or /Library"
            fi
        fi
    done

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

    local sudo_needed=false
    for basename in "${!RESTORE_MAP[@]}"; do
        local trash_path
        trash_path=$(find_in_trash "$basename")
        if [ -n "$trash_path" ]; then
            local dest="${RESTORE_MAP[$basename]}"
            if needs_sudo "$dest"; then
                sudo_needed=true
                break
            fi
        fi
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

    for basename in "${!RESTORE_MAP[@]}"; do
        local trash_path
        trash_path=$(find_in_trash "$basename")
        if [ -n "$trash_path" ]; then
            local dest="${RESTORE_MAP[$basename]}"
            local use_sudo="false"
            if needs_sudo "$dest"; then
                use_sudo="true"
            fi
            safe_restore "$trash_path" "$dest" "$use_sudo"
        fi
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
