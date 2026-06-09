# SalahTime

A Waybar wrapper that displays Islamic prayer times in your status bar, with Hijri date support and desktop notifications.

> **Note:** SalahTime is just a wrapper — it can work with any CLI prayer time tool, not only the one listed below.

---

## Dependencies

- [`salah_cli`](https://crates.io/crates/salah_cli) — a CLI prayer time tool (or any compatible alternative)
- [Waybar](https://github.com/Alexays/Waybar)

---

## Installation

### 1. Install `salah_cli`

```bash
cargo install salah_cli
```

### 2. Copy the script

Place `prayer-waybar.sh` in your Waybar scripts directory and make it executable:

```bash
cp prayer-waybar.sh ~/.config/waybar/scripts/prayer-waybar.sh
chmod +x ~/.config/waybar/scripts/prayer-waybar.sh
```

---

## Waybar Configuration

### 3. Add the module to your bar

In your Waybar `config` (or `config.jsonc`), add `"custom/prayer"` to `modules-center` (or whichever bar position you prefer):

```json
"modules-center": [
  "...",
  "custom/prayer"
]
```

### 4. Define the module

Add the following to your Waybar `config` or a separate modules `.json` file:

```json
"custom/prayer": {
  "exec": "~/.config/waybar/scripts/prayer-waybar.sh",
  "interval": 60,
  "return-type": "json",
  "tooltip": true
}
```

### 5. Add the styles

Add the following to your Waybar `style.css`:

```css
#custom-prayer {
  border-radius: 6px;
  margin: 0px 0px;
  padding: 0px 10px;
  font-weight: 500;
}

/* Default state */
#custom-prayer.normal {
  color: rgba(110, 231, 183, 0.9);
  background-color: rgba(110, 231, 183, 0.08);
}

/* Upcoming prayer is soon */
#custom-prayer.urgent {
  color: rgba(248, 113, 113, 0.9);
  background-color: rgba(248, 113, 113, 0.08);
}

/* Prayer just passed */
#custom-prayer.just-passed {
  color: rgba(251, 191, 36, 0.9);
  background-color: rgba(251, 191, 36, 0.08);
}
```

---

## Known Issues

- **Hijri date display is not working yet** — this feature is still under development.

---

## License

MIT
