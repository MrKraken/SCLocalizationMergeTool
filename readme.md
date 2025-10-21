# Star Citizen String Translation Merger Tool
> [!NOTE]
> Originally based on [ExoAE's ScCompLangPack](https://github.com/ExoAE/ScCompLangPack) idea but rather than another fork, I decided instead to tweak the merge tool instead. target_strings.ini is provided for example of organising your ASOP

### 🗒️ Current String Base: `sc-alpha-4.3.2.10452200`

## 📝 What it Does
- Takes `target_strings.ini` as the input file & `global.ini` as source file from Data.p4k
- Finds the keys from input, matches them to source and replaces the value
- Outputs `merged.ini`
- Optionally outputs directly to the specified game file. See code comments in `merge-translations.ps1` for details

## 🛠️ Localization Installation
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
- The ability to customise your localisation is intended by CIG to support translation
    - *[Star Citizen: Community Localization Update](https://robertsspaceindustries.com/spectrum/community/SC/forum/1/thread/star-citizen-community-localization-update) 2023-10-11*
- Considered as third-party contributions, use at your own discretion

## Made by the Community
This is a fan project made by Star Citizen community members and is not affiliated with or endorsed by Cloud Imperium Games/Roberts Space Industries