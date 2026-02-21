#!/bin/bash
# Double-click this file in Finder to restore Google software from Trash.

cd "$(dirname "$0")"
echo ""
echo "============================================"
echo "  Google Restore Tool"
echo "============================================"
echo ""
echo "Choose an option:"
echo ""
echo "  1) Scan    - Show what can be restored from Trash"
echo "  2) Dry Run - Preview restore without changes"
echo "  3) Restore - Restore all Google items from Trash"
echo "  4) Quit"
echo ""
read -rp "Enter choice [1-4]: " choice

case "$choice" in
    1) bash restore-google.sh scan ;;
    2) bash restore-google.sh dryrun ;;
    3) bash restore-google.sh all ;;
    4) echo "Bye." ;;
    *) echo "Invalid choice." ;;
esac

echo ""
read -rp "Press Enter to close..."
