# WezTerm Unraid Plugin Development Notes

## Plugin Installation

**IMPORTANT**: When installing Unraid plugins, use simple separate commands:

```bash
curl -sL https://raw.githubusercontent.com/ToxMox/wezterm-unraid/main/wezterm.plg -o /tmp/test.plg
plugin install /tmp/test.plg
```

Do NOT chain commands with `&&` or include `rm -rf` cleanup steps before install - this breaks the plugin installer.

## Version Bumping

When making changes to the plugin:
1. Bump the version in both `wezterm.plg` and `build-package.sh` (e.g., `2025.12.24` -> `2025.12.24a`)
2. Rebuild the .txz package with `bash build-package.sh`
3. Update the MD5 in `wezterm.plg` to match the new .txz
4. Commit and push both files together

This avoids GitHub CDN caching issues where old .txz files get served with new .plg files.

## Dark Theme CSS

Unraid's Dynamix themes use CSS variables defined in:
- `/usr/local/emhttp/plugins/dynamix/styles/default-color-palette.css` - color definitions
- `/usr/local/emhttp/plugins/dynamix/styles/themes/black.css` - dark theme variable mappings

Key variables for dark theme compatibility:
- `--text-color` - main text color
- `--background-color` - page background
- `--mild-background-color` - section backgrounds
- `--border-color` - borders
- `--table-background-color`, `--table-border-color`, `--table-header-background-color`
- `--input-bg-color`, `--input-border-color`
- `--green-500`, `--red-500` - status colors

## Building

Run from WSL:
```bash
cd /mnt/t/wezterm-unraid && bash build-package.sh
```

## File Structure

- `wezterm.plg` - Plugin manifest (XML)
- `build-package.sh` - Builds the .txz package
- `archive/wezterm-VERSION.txz` - Slackware package
- `archive/usr/local/emhttp/plugins/wezterm/` - Plugin files:
  - `wezterm.page` - Web UI
  - `include/exec.php` - AJAX handler
  - `include/helpers.php` - PHP helpers
  - `scripts/rc.wezterm` - Service control
  - `scripts/install.sh` - WezTerm binary installer
  - `scripts/cert-manager.sh` - Certificate management
