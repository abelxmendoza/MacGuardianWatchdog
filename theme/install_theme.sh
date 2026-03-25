#!/bin/bash

# ===============================
# MacGuardian Watchdog Theme Installer
# Omega Technologies - Cyberpunk Theme
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_FILE="$SCRIPT_DIR/macguardian-watchdog.zsh-theme"

echo "🎨 MacGuardian Watchdog Theme Installer"
echo "=========================================="
echo ""

# Check if theme file exists
if [ ! -f "$THEME_FILE" ]; then
    echo "❌ Theme file not found: $THEME_FILE"
    exit 1
fi

# Detect shell
if [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
    echo "✅ Zsh detected"
    SHELL_TYPE="zsh"
elif [ "$SHELL" = "/bin/bash" ] || [ "$SHELL" = "/usr/bin/bash" ]; then
    echo "⚠️  Bash detected (theme optimized for zsh)"
    SHELL_TYPE="bash"
else
    echo "⚠️  Unknown shell: $SHELL"
    SHELL_TYPE="unknown"
fi

# Check for Oh My Zsh
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "✅ Oh My Zsh found"
    OH_MY_ZSH=true
    THEME_DIR="$HOME/.oh-my-zsh/themes"
else
    echo "ℹ️  Oh My Zsh not found (will install manually)"
    OH_MY_ZSH=false
    THEME_DIR=""
fi

echo ""
echo "Installation options:"
echo "1) Install for Oh My Zsh (recommended)"
echo "2) Install manually (add to .zshrc)"
echo "3) Just show instructions"
read -p "Select (1-3): " install_choice

case "$install_choice" in
    1)
        if [ "$OH_MY_ZSH" = true ]; then
            echo ""
            echo "📦 Installing theme to Oh My Zsh..."
            mkdir -p "$THEME_DIR"
            cp "$THEME_FILE" "$THEME_DIR/macguardian-watchdog.zsh-theme"
            chmod +x "$THEME_DIR/macguardian-watchdog.zsh-theme"
            
            # Update .zshrc
            if grep -q "ZSH_THEME=" ~/.zshrc; then
                # Replace existing theme
                sed -i '' 's/^ZSH_THEME=.*/ZSH_THEME="macguardian-watchdog"/' ~/.zshrc
            else
                # Add theme line before Oh My Zsh init
                if grep -q "source.*oh-my-zsh.sh" ~/.zshrc; then
                    sed -i '' '/source.*oh-my-zsh.sh/i\
ZSH_THEME="macguardian-watchdog"
' ~/.zshrc
                else
                    echo 'ZSH_THEME="macguardian-watchdog"' >> ~/.zshrc
                fi
            fi
            
            echo "✅ Theme installed!"
            echo ""
            echo "🔄 Reload your shell:"
            echo "   source ~/.zshrc"
            echo ""
            echo "Or open a new terminal window."
        else
            echo "❌ Oh My Zsh not found. Please install Oh My Zsh first:"
            echo "   sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
        fi
        ;;
    2)
        echo ""
        echo "📝 Adding theme to ~/.zshrc..."
        
        # Check if already added
        if grep -q "macguardian-watchdog" ~/.zshrc; then
            echo "⚠️  Theme already in .zshrc"
        else
            echo "" >> ~/.zshrc
            echo "# MacGuardian Watchdog Theme" >> ~/.zshrc
            echo "source $THEME_FILE" >> ~/.zshrc
            echo "✅ Theme added to ~/.zshrc"
        fi
        
        echo ""
        echo "🔄 Reload your shell:"
        echo "   source ~/.zshrc"
        ;;
    3)
        echo ""
        echo "📖 Installation Instructions:"
        echo ""
        echo "Option A: Oh My Zsh (Recommended)"
        echo "  1. Install Oh My Zsh:"
        echo "     sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
        echo ""
        echo "  2. Copy theme:"
        echo "     cp $THEME_FILE ~/.oh-my-zsh/themes/macguardian-watchdog.zsh-theme"
        echo ""
        echo "  3. Edit ~/.zshrc:"
        echo "     ZSH_THEME=\"macguardian-watchdog\""
        echo ""
        echo "  4. Reload:"
        echo "     source ~/.zshrc"
        echo ""
        echo "Option B: Manual Installation"
        echo "  1. Add to ~/.zshrc:"
        echo "     source $THEME_FILE"
        echo ""
        echo "  2. Reload:"
        echo "     source ~/.zshrc"
        echo ""
        echo "Option C: Terminal Color Scheme"
        echo "  Import macguardian-color-palette.json into iTerm2 or VS Code"
        echo "  See THEME_INSTALLATION.md for details"
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

