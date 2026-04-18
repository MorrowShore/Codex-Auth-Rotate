# Codex Auth ROTATE

Quick account switcher for the [OpenAI Codex CLI](https://developers.openai.com/codex/cli). When you hit your usage limit, run one command to swap to the next account.
Also works for the VSCode-based Codex extension.

These scripts work because Codex stores credentials in `~/.codex/auth.json` (Linux/macOS) or `%USERPROFILE%\.codex\auth.json` (Windows) when `cli_auth_credentials_store = "file"` is set; these scripts offer to do that for you anyway.

---

## Files

| File | Platform | Purpose |
|------|----------|---------|
| `Rotate-Codex-Auth.sh` | Linux/macOS | Cycle to the next account |
| `Import-Codex-Auth.sh` | Linux/macOS | Save the current logged-in account |
| `Rotate-Codex-Auth.ps1` | Windows | Cycle to the next account |
| `Import-Codex-Auth.ps1` | Windows | Save the current logged-in account |

---

## How to use

**1. (Optional) Create an `accounts/` folder** next to the scripts (the script will auto-generate it anyway).

**2. (Optional) Add the `cli_auth_credentials_store = "file"` line** to `~/.codex/config.toml` if you haven't already (the script will check for this and auto-add it anyway).

**3. For each account:** properly log into Codex, then just run the import script to capture it and save its auth file in the `accounts/` folder.

Linux/macOS:
```bash
chmod +x Import-Codex-Auth.sh Rotate-Codex-Auth.sh
./Import-Codex-Auth.sh
```

Windows (right-click → *Run with PowerShell*):
```
Import-Codex-Auth.ps1
```

Repeat for each account. Switch to each one in Codex before saving.

The save script reads the current `auth.json`, decodes the email from the JWT for confirmation, and prompts for a label. It auto-numbers the files to control cycle order like so:
```
accounts/
  01_Personal.json
  02_CompanyA.json
  03_CompanyB.json
```

**4. When you hit your usage limit, run the rotate script. Each run advances to the next account and eventually loops around.**

Linux/macOS:
```bash
./Rotate-Codex-Auth.sh
```

Windows:
```
Rotate-Codex-Auth.ps1
```



---

## Notes

- **Windows:** `Rotate-Codex-Auth.ps1` requires admin rights (for writing to the `.codex` folder under some configurations) and auto-elevates. `Import-Codex-Auth.ps1` does not require elevation.
- **Linux/macOS:** No elevated permissions needed.
- A `.bak` copy of `auth.json` is created on every switch.
- The active account index is tracked in `.auth_state` next to the scripts.
- Requires `python3` on Linux/macOS for email decoding (gracefully skipped if unavailable).
