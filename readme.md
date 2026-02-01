# Star Citizen Localization Merge Tool

> [!NOTE]
> Originally based on [ExoAE's ScCompLangPack](https://github.com/ExoAE/ScCompLangPack). Rebuilt into a modular localization workbench by [MrKraken](https://www.youtube.com/@MrKraken).

Customize how Star Citizen displays item names, UI labels, and other in-game text. The tool merges your custom strings into the game's `global.ini` so you can see component grades, manufacturer info, weapon stats, and whatever else you want at a glance without digging through menus.

> [!WARNING]
> If you are uneasy running PowerShell scripts, you can still manually adjust your localization file by searching for strings with `CTRL`+`F` or using find & replace with `CTRL`+`H` in your text editor.

## Features

| Feature | What it does |
|---------|-------------|
| **Merge** | Applies your custom strings from `target_strings.ini` onto `global.ini`, outputs `merged.ini`, and optionally writes directly to your game folder |
| **Patch Update** | One-stop workflow: extracts latest `global.ini` from `Data.p4k`, checks version, diffs old vs new, backs up old source, swaps in the new one, and offers to re-merge |
| **Browse** | Browse `global.ini` keys by category (vehicles, UI, hints, etc.) and add them to your target file |
| **Diff** | Compare cached `global.ini` versions to see what changed between patches, highlighting conflicts with your customizations |
| **Extract** | Pull `global.ini` directly from your game's `Data.p4k` using unp4k (auto-downloaded if needed) |
| **Settings** | Configure game path, environments (LIVE/PTU/EPTU), language, and preferences |

The merge also handles `user.cfg` automatically. If your game folder is missing `user.cfg` or it doesn't have the right `g_language` line, the tool creates or updates it for you.

## Quick Start

1. Clone or download this repo
2. Right-click `merge.ps1` and select **Run in PowerShell**
3. Done — the tool auto-detects your game, extracts the latest strings, and merges your customizations

On first run the tool finds your Star Citizen installation automatically (checks the RSI Launcher log, default paths, and scans all drives). It defaults to the LIVE environment with auto-write enabled so the merged file goes straight into your game folder.

### Command-Line Usage

```powershell
# One-command auto workflow (default)
.\merge.ps1

# Interactive menu (for power users)
.\merge.ps1 -Menu

# Direct commands
.\merge.ps1 -Merge                    # Run merge only
.\merge.ps1 -Update                   # Interactive patch update workflow
.\merge.ps1 -Browse                   # Open category browser
.\merge.ps1 -Diff                     # Compare cached versions
.\merge.ps1 -Extract                  # Extract from Data.p4k
.\merge.ps1 -Settings                 # Edit configuration
.\merge.ps1 -Merge -Environment PTU   # Merge for PTU
```

### Backwards Compatibility

`merge-translations.ps1` still works the same as before, running the merge directly.

## Typical Workflow

1. **Extract** (or manually place) `global.ini` into `src/`
2. **Browse** categories to find strings you want to customize
3. Edit the values in `target_strings.ini`
4. **Merge** to generate the output and write to your game folder
5. After a game patch, run **Patch Update** — it extracts the new `global.ini`, shows what changed (including conflicts with your customizations), backs up the old version, and offers to re-merge

## What `target_strings.ini` Looks Like

Each entry has a comment preserving the original value, followed by your custom label:

```ini
; @original=FullStop
item_NameSHLD_GODI_S02_FullStop=FullStop [Gorgon | S2 | Gr.C | Mil]

; @original=Explorer
item_NameJUMP_TARS_S1_C=Explorer [Tarsus | S1 | Gr.C | Civ]
```

The `; @original=` comments let the tool track upstream changes. When a patch changes a value you've customized, the **Diff** feature flags it as a conflict.

## File Structure

```
SCLocalizationMergeTool/
  merge.ps1                    # Main entry point (auto workflow by default)
  merge-translations.ps1       # Backwards compat (runs merge directly)
  lib/
    Categories.ps1             # Category definitions
    Config.ps1                 # Configuration and setup wizard
    Extract.ps1                # Data.p4k extraction
    Merge.ps1                  # Merge engine + user.cfg management
    Diff.ps1                   # Patch diff and conflict detection
    Browse.ps1                 # Category browser
  target_strings.ini           # Your custom translations
  src/
    global.ini                 # Source strings from Data.p4k
    vehicles.ini               # Vehicle name reference
    user.example.cfg           # Example user.cfg
  config.json                  # Auto-created settings (gitignored)
  cache/                       # Cached global.ini versions (gitignored)
  tools/                       # unp4k (gitignored, auto-downloaded)
  output/                      # Merge output (gitignored)
```

## General Localization Installation

Any localization files go in your Star Citizen install folder (LIVE, PTU, EPTU, etc.):

```
StarCitizen/
└── LIVE/
    ├── user.cfg
    └── data/
        └── Localization/
            └── english/
                └── global.ini
```

If you have auto-write enabled, the tool handles this for you. Otherwise, copy `output/merged.ini` to the path above and ensure `user.cfg` contains `g_language = english` (or your configured language).

## Is this... legit?

> [!IMPORTANT]
> **Made by the Community** — This is an unofficial Star Citizen fan project, not affiliated with the Cloud Imperium group of companies. All content in this repository not authored by its host or users are property of their respective owners.

- Customising your localisation using the extracted `global.ini` is intended and authorised by CIG to support community-made translations until official integration
    - *[Star Citizen: Community Localization Update](https://robertsspaceindustries.com/spectrum/community/SC/forum/1/thread/star-citizen-community-localization-update) 2023-10-11*
- Considered as third-party contributions, use at your own discretion
- [RSI Terms of Service](https://robertsspaceindustries.com/en/tos)
- [Translation & Fan Localization Statement](https://support.robertsspaceindustries.com/hc/en-us/articles/360006895793-Star-Citizen-Fankit-and-Fandom-FAQ#h_01JNKSPM7MRSB1WNBW6FGD2H98)

## Win11 Gave an Error

> [!CAUTION]
> Certain operating system versions may require you to unrestrict PowerShell execution in order to run the unsigned script. You can either look up how to self-sign, or unrestrict and do so at your own risk.
> - Changing execution policy is done by running PowerShell as admin
> - [Microsoft Info on Execution Policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.5&viewFallbackFrom=powershell-7.2)
> - When you are done ensure you then revert to only running signed scripts

Unrestricting:
```
Set-ExecutionPolicy Unrestricted -Scope CurrentUser
```
Reverting to default:
```
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```
To block scripts:
```
Set-ExecutionPolicy Restricted -Scope CurrentUser
```
