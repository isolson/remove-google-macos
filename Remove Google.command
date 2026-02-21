#!/bin/bash
# Double-click this file in Finder to run the Google removal audit.
# It opens Terminal and runs the audit first so you can see what will be removed.

cd "$(dirname "$0")"
echo ""
echo "============================================"
echo "  Google Removal Tool"
echo "============================================"
echo ""
echo "Choose an option:"
echo ""
echo "  1) Audit   - Scan and report (no changes)"
echo "  2) Dry Run - Preview all changes"
echo "  3) Remove  - Remove all Google software"
echo "  4) Quit"
echo ""
read -rp "Enter choice [1-4]: " choice

case "$choice" in
    1) bash remove-google.sh audit ;;
    2) bash remove-google.sh dryrun ;;
    3) bash remove-google.sh all ;;
    4) echo "Bye." ;;
    *) echo "Invalid choice." ;;
esac

echo ""
read -rp "Press Enter to close..."
