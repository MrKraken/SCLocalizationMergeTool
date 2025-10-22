# Star Citizen String Translation Merger Tool
> [!NOTE]
> Originally based on [ExoAE's ScCompLangPack](https://github.com/ExoAE/ScCompLangPack) idea but rather than another fork, I decided instead to tweak the merge tool to make it more usable. target_strings.ini is provided for example of organising your ASOP

### 🗒️ Current String Base: `sc-alpha-4.3.2.10452200`

## 📝 What it Does
- Takes `target_strings.ini` as the input file & `global.ini` as source file from Data.p4k
- Finds the keys from input, matches them to source and replaces the value
- Outputs `merged.ini`
- Optionally outputs directly to the specified game file. See code comments in `merge-translations.ps1` for details

## 🗺️ Usage
1. Find the strings you want to customize in `src/global.ini` or `src/vehicles.ini`
2. Copy the line(s) to `target_strings.ini`
3. If you already have a `user.cfg` file in `StarCitizen\LIVE` add the line `g_language = english`
    - If not, create one or copy `src\user.example.cfg` and rename it to `user.cfg`
4. If you want to write localization straight to game folder
    - Open `merge-translations.ps1` in notepad (or other text editor)
        1. Define your folder if not default
        2. Change `$gameIniWrite = $false` to `$gameIniWrite = $true`
5. Right click `merge-translations.ps1` & select *Run in Powershell*
    - If prompted, input `r` then press `enter` to run the tool
6. You can verify the changes have taken effect by going to your install location → `data\Localization\english\global.ini` & searching for one of your strings using `CTRL`+`F`

## 🛠️ General Localization Installation
- Any translations (localization) files you download should go in your Star Citizen install folder (LIVE, PTU, TECH-PREVIEW etc.) in the following structure:
```
StarCitizen/
└── LIVE/
    ├── user.cfg
    └── data/
        └── Localization/
            └── english/
                └── global.ini
```
- If you already have a `user.cfg` file, add the line `g_language = english`
    - Otherwise just make one or rename `user.example.cfg` → `user.cfg` & put it in your SC directory as above

## 🤔 Is this... legit?
> [!IMPORTANT]
> **Made by the Community** - This is an unofficial Star Citizen fan project, not affiliated with the Cloud Imperium group of companies. All content in this repository not authored by its host or users are property of their respective owners.
- The ability to customise your localisation using the extracted global.ini file is intended/authorised by CIG to support community made translations until it is officially integrated
    - *[Star Citizen: Community Localization Update](https://robertsspaceindustries.com/spectrum/community/SC/forum/1/thread/star-citizen-community-localization-update) 2023-10-11*
- Considered as third-party contributions, use at your own discretion
- [RSI Terms of Service](https://robertsspaceindustries.com/en/tos)
- [Translation & Fan Localization Statement](https://support.robertsspaceindustries.com/hc/en-us/articles/360006895793-Star-Citizen-Fankit-and-Fandom-FAQ#h_01JNKSPM7MRSB1WNBW6FGD2H98)

