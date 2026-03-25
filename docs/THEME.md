# MacGuardian Watchdog Theme Installation
## Omega Technologies - Dark Cyberpunk Aesthetic

### 🎨 Color Palette
- **Primary (Electric Purple)**: `#8A2BE2` - Highlights, headers, prompts
- **Secondary (Neon Red)**: `#FF0044` - Alerts, errors, danger outputs
- **Accent (Cyan Glow)**: `#00FFFF` - Selection, cursor, git status
- **Text (Dim Gray)**: `#808080` - Regular text
- **Background (Deep Black)**: `#000000` - Base background

---

## 📦 Installation Options

### Option 1: Zsh Theme (Recommended for Oh My Zsh)

1. **Copy theme file:**
   ```bash
   cp theme/macguardian-watchdog.zsh-theme ~/.oh-my-zsh/themes/macguardian-watchdog.zsh-theme
   ```

2. **Set theme in `~/.zshrc`:**
   ```bash
   ZSH_THEME="macguardian-watchdog"
   ```

3. **Reload shell:**
   ```bash
   source ~/.zshrc
   ```

**Or for manual zsh setup (without Oh My Zsh):**
```bash
# Add to ~/.zshrc
source theme/macguardian-watchdog.zsh-theme
```

---

### Option 2: Powerlevel10k

1. **Install Powerlevel10k** (if not already installed):
   ```bash
   git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
   ```

2. **Set Powerlevel10k in `~/.zshrc`:**
   ```bash
   ZSH_THEME="powerlevel10k/powerlevel10k"
   ```

3. **Source MacGuardian config:**
   ```bash
   # Add to ~/.zshrc after Powerlevel10k init
   source /path/to/powerlevel10k-macguardian.zsh
   ```

4. **Reload shell:**
   ```bash
   source ~/.zshrc
   ```

---

### Option 3: Starship

1. **Install Starship** (if not already installed):
   ```bash
   curl -sS https://starship.rs/install.sh | sh
   ```

2. **Copy config:**
   ```bash
   mkdir -p ~/.config
   cp starship-macguardian.toml ~/.config/starship.toml
   ```

3. **Add to `~/.zshrc` (or `~/.bashrc`):**
   ```bash
   eval "$(starship init zsh)"
   ```

4. **Reload shell:**
   ```bash
   source ~/.zshrc
   ```

---

## 🖥️ Terminal Color Schemes

### iTerm2

1. **Import color scheme:**
   - Open iTerm2 → Preferences → Profiles → Colors
   - Click "Color Presets" → "Import..."
   - Select `macguardian-color-palette.json`
   - Choose "MacGuardian Watchdog" from presets

2. **Or manually configure:**
   - Background: `#000000` (Deep Black)
   - Foreground: `#808080` (Dim Gray)
   - Cursor: `#00FFFF` (Cyan Glow)
   - Selection: `#00FFFF33` (Cyan with transparency)
   - ANSI Colors: Use values from `macguardian-color-palette.json`

### VS Code Terminal

1. **Add to `settings.json`:**
   ```json
   {
     "workbench.colorCustomizations": {
       "terminal.background": "#000000",
       "terminal.foreground": "#808080",
       "terminalCursor.foreground": "#00FFFF",
       "terminal.selectionBackground": "#00FFFF33",
       "terminal.ansiMagenta": "#8A2BE2",
       "terminal.ansiRed": "#FF0044",
       "terminal.ansiCyan": "#00FFFF"
     }
   }
   ```

2. **Or use the full palette:**
   - Copy the `vscode` section from `macguardian-color-palette.json`
   - Paste into your VS Code `settings.json`

### Terminal.app (macOS)

1. **Open Terminal → Preferences → Profiles**
2. **Create new profile "MacGuardian Watchdog"**
3. **Set colors:**
   - Background: `#000000`
   - Text: `#808080`
   - Bold Text: `#8A2BE2`
   - Selection: `#00FFFF33`
   - Cursor: `#00FFFF`

---

## 🎯 Features

### ASCII Header
The theme displays an ASCII art header on shell startup:
```
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║    Ω-Technologies // MacGuardian Watchdog                 ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
```

### Dynamic Prompt
- **Timestamp** in purple: `[HH:MM:SS]`
- **Username** in purple
- **Git repo name** in purple (if in git repo)
- **Current directory** in dim gray
- **Git status indicator**: Cyan (clean) or Red (dirty)
- **Prompt symbol** in neon red: `>`

### Command Execution Time
- Shows execution time for commands taking >2 seconds
- Displayed in purple on the right side

### Git Integration
- Shows current branch in purple
- Status indicators:
  - `●` Cyan = clean
  - `●` Red = modified/untracked
- Shows ahead/behind status

---

## 🔧 Customization

### Change Colors

Edit the color definitions in the theme file:
```zsh
MACGUARDIAN_PURPLE='%F{135}%B'  # Change 135 to different color code
MACGUARDIAN_RED='%F{196}%B'     # Change 196 to different color code
```

### Disable Header

Add to `~/.zshrc`:
```zsh
export MACGUARDIAN_HEADER_SHOWN=1  # Prevents header from showing
```

### Custom Prompt Format

Modify the `PROMPT` variable in the theme file to change the prompt layout.

---

## 🐛 Troubleshooting

### Theme not loading
- Check file permissions: `chmod +x macguardian-watchdog.zsh-theme`
- Verify path in `~/.zshrc` is correct
- Reload shell: `source ~/.zshrc`

### Colors not showing
- Ensure terminal supports 256 colors
- Check `$TERM` variable: `echo $TERM` (should be `xterm-256color` or similar)
- For iTerm2: Preferences → Profiles → Terminal → Report terminal type: `xterm-256color`

### Git functions not working
- Ensure git is installed: `which git`
- Check if in a git repository: `git rev-parse --show-toplevel`

### Header shows every time
- The header should only show once per session
- If it shows repeatedly, check `$MACGUARDIAN_HEADER_SHOWN` is being set

---

## 📝 Notes

- **Compatible with**: zsh 5.0+, Oh My Zsh, Powerlevel10k, Starship
- **Terminal requirements**: 256-color support recommended
- **Performance**: Minimal overhead, fast prompt rendering
- **Accessibility**: High contrast for readability

---

## 🎨 Preview

```
[14:32:15] abel_elreaper [MacGuardianProject] ~/Desktop/MacGuardianProject ● >
```

The prompt shows:
- `[14:32:15]` - Current time (purple)
- `abel_elreaper` - Username (purple)
- `[MacGuardianProject]` - Git repo name (purple, if in repo)
- `~/Desktop/MacGuardianProject` - Current directory (gray)
- `●` - Git status (cyan if clean, red if dirty)
- `>` - Prompt symbol (neon red)

---

**Enjoy your cyberpunk intrusion detection console! 🛡️💜**

