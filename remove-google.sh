#!/bin/bash
# =============================================================================
# remove-google.sh
# Safely removes all Google software from macOS (Keystone updater, Chrome
# remnants, Google Earth Pro, caches, preferences, and support files).
#
# Moves files to Trash (~/.Trash/) instead of deleting. Unloads launch
# agents/daemons before removal. Requires explicit confirmation before each
# destructive phase.
#
# Usage:
#   bash remove-google.sh audit    # Scan and report (no changes)
#   bash remove-google.sh phase1   # Kill Google processes
#   bash remove-google.sh phase2   # Unload + trash LaunchAgents/Daemons
#   bash remove-google.sh phase3   # Trash Google applications + /Library/Google
#   bash remove-google.sh phase4   # Trash caches, preferences, support files
#   bash remove-google.sh phase5   # Block reinstall + final summary
#   bash remove-google.sh all      # Run all phases with confirmation prompts
#   bash remove-google.sh dryrun   # Preview all changes without executing
# =============================================================================

set -euo pipefail

TRASH="$HOME/.Trash"
DRY_RUN=false
REMOVED=0
ERRORS=0
CURRENT_UID=$(id -u)

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

# Prefixes for glob expansion (caches, prefs, etc.)
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

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

log_info()   { echo -e "  ${BLUE}[INFO]${NC} $*"; }
log_warn()   { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
log_error()  { echo -e "  ${RED}[ERROR]${NC} $*"; ERRORS=$((ERRORS + 1)); }
log_found()  { echo -e "  ${RED}[FOUND]${NC} $*"; }
log_clean()  { echo -e "  ${GREEN}[CLEAN]${NC} $*"; }
log_dry()    { echo -e "  ${CYAN}[DRY RUN]${NC} Would trash: $*"; }
log_action() { echo -e "  ${GREEN}[DONE]${NC} $*"; }

confirm_phase() {
    local phase_name="$1"
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    echo ""
    echo -e "${YELLOW}Proceed with ${phase_name}? (yes/no)${NC}"
    read -r response
    if [ "$response" != "yes" ]; then
        echo -e "${BLUE}Skipped ${phase_name}.${NC}"
        return 1
    fi
    return 0
}

safe_trash() {
    local src="$1"
    local use_sudo="${2:-false}"

    if [ ! -e "$src" ]; then
        return 0
    fi

    local basename
    basename=$(basename "$src")

    if [ "$DRY_RUN" = true ]; then
        log_dry "$src"
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
        echo -e "  ${CYAN}[DRY RUN]${NC} Would unload: $plist (domain: $domain)"
        return 0
    fi

    # Try to extract the label from the plist
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
        # Fallback for plists with empty dicts / no Label key
        if [ "$use_sudo" = true ]; then
            sudo launchctl unload -w "$plist" 2>/dev/null || true
        else
            launchctl unload -w "$plist" 2>/dev/null || true
        fi
        log_action "Unloaded (legacy): $plist"
    fi
}

# ---------------------------------------------------------------------------
# Phase 0: Audit
# ---------------------------------------------------------------------------

phase0_audit() {
    echo -e "\n${GREEN}=== PHASE 0: AUDIT — Scanning for Google Software ===${NC}"
    local found=0

    # Running processes
    echo -e "\n${BOLD}Running Google processes:${NC}"
    local proc_found=false
    for proc in "${GOOGLE_PROCESSES[@]}"; do
        if pgrep -f "$proc" >/dev/null 2>&1; then
            log_found "Process: $proc (PID: $(pgrep -f "$proc" | tr '\n' ' '))"
            proc_found=true
            found=$((found + 1))
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
        found=$((found + 1))
    else
        log_clean "No Google services loaded"
    fi

    # LaunchAgents and LaunchDaemons
    echo -e "\n${BOLD}LaunchAgent/LaunchDaemon plists:${NC}"
    local plist_found=false
    for plist in "${USER_LAUNCH_AGENTS[@]}" "${SYSTEM_LAUNCH_AGENTS[@]}" "${SYSTEM_LAUNCH_DAEMONS[@]}"; do
        if [ -f "$plist" ]; then
            log_found "$plist"
            found=$((found + 1))
            plist_found=true
        fi
    done
    if [ "$plist_found" = false ]; then
        log_clean "No Google plists found"
    fi

    # Applications
    echo -e "\n${BOLD}Google applications:${NC}"
    local app_found=false
    for app in "${GOOGLE_APPS[@]}"; do
        if [ -d "$app" ]; then
            local size
            size=$(du -sh "$app" 2>/dev/null | cut -f1)
            log_found "$app ($size)"
            found=$((found + 1))
            app_found=true
        fi
    done
    if [ "$app_found" = false ]; then
        log_clean "No Google applications found"
    fi

    # System-level directories
    echo -e "\n${BOLD}System-level Google directories (/Library/):${NC}"
    local sysdir_found=false
    for dir in "${SYSTEM_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            local size
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            log_found "$dir ($size)"
            found=$((found + 1))
            sysdir_found=true
        fi
    done
    if [ "$sysdir_found" = false ]; then
        log_clean "No system-level Google directories"
    fi

    # User-level directories
    echo -e "\n${BOLD}User-level Google directories (~/Library/):${NC}"
    local userdir_found=false
    for dir in "${USER_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            local size
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            log_found "$dir ($size)"
            found=$((found + 1))
            userdir_found=true
        fi
    done
    if [ "$userdir_found" = false ]; then
        log_clean "No user-level Google directories"
    fi

    # Glob-matched items (caches, prefs, etc.)
    echo -e "\n${BOLD}User-level caches, preferences, and data:${NC}"
    local glob_found=false
    for prefix in "${USER_GLOB_PREFIXES[@]}"; do
        for match in "${prefix}"*; do
            if [ -e "$match" ]; then
                local size
                size=$(du -sh "$match" 2>/dev/null | cut -f1)
                log_found "$match ($size)"
                found=$((found + 1))
                glob_found=true
            fi
        done
    done

    # Group Containers
    for match in "$HOME/Library/Group Containers/"*google* "$HOME/Library/Group Containers/"*Google*; do
        if [ -e "$match" ]; then
            log_found "$match"
            found=$((found + 1))
            glob_found=true
        fi
    done

    # Logs
    for logfile in "${GOOGLE_LOGS[@]}"; do
        if [ -f "$logfile" ]; then
            log_found "$logfile"
            found=$((found + 1))
            glob_found=true
        fi
    done

    if [ "$glob_found" = false ]; then
        log_clean "No user-level Google data"
    fi

    # Summary
    echo ""
    if [ "$found" -eq 0 ]; then
        echo -e "${GREEN}No Google software found. System is clean.${NC}"
    else
        echo -e "${YELLOW}Found $found Google item(s). Run 'all' or individual phases to remove.${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Phase 1: Kill running Google processes
# ---------------------------------------------------------------------------

phase1_kill_processes() {
    echo -e "\n${GREEN}=== PHASE 1: Kill Running Google Processes ===${NC}"

    local killed=0
    for proc in "${GOOGLE_PROCESSES[@]}"; do
        if pgrep -f "$proc" >/dev/null 2>&1; then
            if [ "$DRY_RUN" = true ]; then
                log_dry "Would kill process: $proc"
            else
                killall "$proc" 2>/dev/null || true
                log_action "Killed: $proc"
            fi
            killed=$((killed + 1))
        fi
    done

    if [ "$killed" -eq 0 ]; then
        log_clean "No Google processes were running"
    elif [ "$DRY_RUN" = false ]; then
        sleep 2
    fi

    echo -e "${GREEN}Phase 1 complete. $killed process(es) handled.${NC}"
}

# ---------------------------------------------------------------------------
# Phase 2: Unload and trash LaunchAgents/LaunchDaemons
# ---------------------------------------------------------------------------

phase2_unload_launch_items() {
    echo -e "\n${GREEN}=== PHASE 2: Unload + Trash LaunchAgents/Daemons ===${NC}"

    local needs_sudo=false
    for plist in "${SYSTEM_LAUNCH_AGENTS[@]}" "${SYSTEM_LAUNCH_DAEMONS[@]}"; do
        if [ -f "$plist" ]; then
            needs_sudo=true
            break
        fi
    done

    if [ "$needs_sudo" = true ] && [ "$DRY_RUN" = false ]; then
        echo -e "${YELLOW}System-level items found. sudo will be required.${NC}"
    fi

    confirm_phase "Phase 2: Unload and trash launch items" || return 0

    # User-level LaunchAgents
    echo -e "\n${BOLD}User-level LaunchAgents:${NC}"
    local user_found=false
    for plist in "${USER_LAUNCH_AGENTS[@]}"; do
        if [ -f "$plist" ]; then
            safe_unload "$plist" "gui/$CURRENT_UID" false
            safe_trash "$plist" false
            user_found=true
        fi
    done
    if [ "$user_found" = false ]; then
        log_clean "No user-level LaunchAgents found"
    fi

    # System-level LaunchAgents
    echo -e "\n${BOLD}System-level LaunchAgents:${NC}"
    local sys_agent_found=false
    for plist in "${SYSTEM_LAUNCH_AGENTS[@]}"; do
        if [ -f "$plist" ]; then
            safe_unload "$plist" "system" true
            safe_trash "$plist" true
            sys_agent_found=true
        fi
    done
    if [ "$sys_agent_found" = false ]; then
        log_clean "No system-level LaunchAgents found"
    fi

    # System-level LaunchDaemons
    echo -e "\n${BOLD}System-level LaunchDaemons:${NC}"
    local sys_daemon_found=false
    for plist in "${SYSTEM_LAUNCH_DAEMONS[@]}"; do
        if [ -f "$plist" ]; then
            safe_unload "$plist" "system" true
            safe_trash "$plist" true
            sys_daemon_found=true
        fi
    done
    if [ "$sys_daemon_found" = false ]; then
        log_clean "No system-level LaunchDaemons found"
    fi

    echo -e "\n${GREEN}Phase 2 complete.${NC}"
}

# ---------------------------------------------------------------------------
# Phase 3: Trash Google applications and system directories
# ---------------------------------------------------------------------------

phase3_trash_apps() {
    echo -e "\n${GREEN}=== PHASE 3: Trash Google Applications + System Dirs ===${NC}"

    confirm_phase "Phase 3: Trash Google apps and /Library/Google" || return 0

    echo -e "\n${BOLD}Google applications:${NC}"
    local app_found=false
    for app in "${GOOGLE_APPS[@]}"; do
        if [ -d "$app" ]; then
            app_found=true
            local app_name
            app_name=$(basename "$app")
            if [ "$DRY_RUN" = true ]; then
                safe_trash "$app" true
            else
                echo -e "  ${YELLOW}Remove ${app_name}? (yes/no/skip)${NC}"
                read -r response
                if [ "$response" = "yes" ]; then
                    safe_trash "$app" true
                else
                    log_info "Kept: $app"
                fi
            fi
        fi
    done
    if [ "$app_found" = false ]; then
        log_clean "No Google applications found"
    fi

    echo -e "\n${BOLD}System-level Google directories:${NC}"
    local dir_found=false
    for dir in "${SYSTEM_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            safe_trash "$dir" true
            dir_found=true
        fi
    done
    if [ "$dir_found" = false ]; then
        log_clean "No system-level Google directories"
    fi

    echo -e "\n${GREEN}Phase 3 complete.${NC}"
}

# ---------------------------------------------------------------------------
# Phase 4: Trash user-level caches, preferences, and support data
# ---------------------------------------------------------------------------

phase4_trash_user_data() {
    echo -e "\n${GREEN}=== PHASE 4: Trash User-Level Google Data ===${NC}"

    confirm_phase "Phase 4: Trash ~/Library Google caches, prefs, and support files" || return 0

    # Named directories
    echo -e "\n${BOLD}User-level Google directories:${NC}"
    local dir_found=false
    for dir in "${USER_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            safe_trash "$dir" false
            dir_found=true
        fi
    done
    if [ "$dir_found" = false ]; then
        log_clean "No user-level Google directories"
    fi

    # Glob-matched items
    echo -e "\n${BOLD}Caches, preferences, and data stores:${NC}"
    local glob_found=false
    for prefix in "${USER_GLOB_PREFIXES[@]}"; do
        for match in "${prefix}"*; do
            if [ -e "$match" ]; then
                safe_trash "$match" false
                glob_found=true
            fi
        done
    done

    # Group Containers
    for match in "$HOME/Library/Group Containers/"*google* "$HOME/Library/Group Containers/"*Google*; do
        if [ -e "$match" ]; then
            safe_trash "$match" false
            glob_found=true
        fi
    done

    # Log files
    for logfile in "${GOOGLE_LOGS[@]}"; do
        if [ -f "$logfile" ]; then
            safe_trash "$logfile" false
            glob_found=true
        fi
    done

    if [ "$glob_found" = false ]; then
        log_clean "No user-level Google data found"
    fi

    echo -e "\n${GREEN}Phase 4 complete.${NC}"
}

# ---------------------------------------------------------------------------
# Phase 5: Anti-reinstall blockers + final summary
# ---------------------------------------------------------------------------

phase5_block_and_summary() {
    echo -e "\n${GREEN}=== PHASE 5: Block Reinstall + Final Summary ===${NC}"

    confirm_phase "Phase 5: Create blocker files to prevent Keystone reinstall" || return 0

    # Create a regular file where ~/Library/Google used to be so Google
    # installers cannot recreate the directory.
    local blocker="$HOME/Library/Google"
    if [ ! -e "$blocker" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${CYAN}[DRY RUN]${NC} Would create blocker file: $blocker (chmod 000)"
        else
            touch "$blocker"
            chmod 000 "$blocker"
            log_action "Created blocker: $blocker (chmod 000)"
        fi
    else
        log_warn "Skipping blocker for $blocker (path still exists)"
    fi

    # Final verification scan
    echo -e "\n${BOLD}Final verification scan:${NC}"
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
        log_warn "Services still loaded:"
        echo "$services"
        remaining=$((remaining + 1))
    fi

    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Google Removal Complete${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "  Items trashed:    ${GREEN}$REMOVED${NC}"
    echo -e "  Errors:           ${RED}$ERRORS${NC}"
    echo -e "  Items remaining:  ${YELLOW}$remaining${NC}"
    echo ""
    if [ "$remaining" -eq 0 ]; then
        echo -e "  ${GREEN}System is clean of Google software.${NC}"
    else
        echo -e "  ${YELLOW}Some items remain. A reboot may be needed.${NC}"
    fi
    echo ""
    echo -e "  ${BLUE}All removed files are in ~/.Trash/ and can be${NC}"
    echo -e "  ${BLUE}restored if needed before emptying the Trash.${NC}"
    echo -e "${GREEN}================================================${NC}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local phase="${1:-help}"

    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Google Software Removal Script${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo -e "  Trash destination: ${BLUE}$TRASH${NC}"
    echo -e "  Current user:     ${BLUE}$(whoami) (UID $CURRENT_UID)${NC}"
    echo ""

    case "$phase" in
        audit)
            phase0_audit
            ;;
        phase1)
            confirm_phase "Phase 1: Kill Google processes" && phase1_kill_processes
            ;;
        phase2)
            phase2_unload_launch_items
            ;;
        phase3)
            phase3_trash_apps
            ;;
        phase4)
            phase4_trash_user_data
            ;;
        phase5)
            phase5_block_and_summary
            ;;
        all)
            phase0_audit
            echo ""
            echo -e "${YELLOW}The audit above shows what will be removed.${NC}"
            confirm_phase "Full removal (phases 1-5)" || exit 0
            phase1_kill_processes
            phase2_unload_launch_items
            phase3_trash_apps
            phase4_trash_user_data
            phase5_block_and_summary
            ;;
        dryrun)
            DRY_RUN=true
            phase0_audit
            phase1_kill_processes
            phase2_unload_launch_items
            phase3_trash_apps
            phase4_trash_user_data
            phase5_block_and_summary
            echo -e "\n${CYAN}DRY RUN complete. No changes were made.${NC}"
            ;;
        *)
            echo "Usage: bash remove-google.sh <command>"
            echo ""
            echo "Commands:"
            echo "  audit    Scan and report all Google software (no changes)"
            echo "  phase1   Kill running Google processes"
            echo "  phase2   Unload + trash LaunchAgents/LaunchDaemons"
            echo "  phase3   Trash Google applications + /Library/Google"
            echo "  phase4   Trash user-level caches, prefs, support files"
            echo "  phase5   Create anti-reinstall blockers + final summary"
            echo "  all      Run audit then all phases with confirmation"
            echo "  dryrun   Preview all changes without executing"
            ;;
    esac
}

main "$@"
