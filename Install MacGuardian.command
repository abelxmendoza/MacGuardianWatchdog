#!/bin/bash
# Double-click this file in Finder to set up MacGuardian.
cd "$(dirname "$0")" || exit 1
bash ./install.sh
echo ""
read -r -p "Press Enter to close this window..."
