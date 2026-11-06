# Apple Developer Documentation Assets

This directory reproduces Apple's **Xcode Developer Documentation System** with exact fidelity to Apple's specifications, schemas, runtime engines, and caching infrastructure.

---

## 🏛 Directory Architecture

```
Documentation Assets/
│
├── DeveloperDocumentation.doccarchive/        # 📦 Official Apple DocC Archive Package
│   ├── metadata.json                          # com.apple.documentation bundle specification
│   ├── theme-settings.json                    # Dark / light mode and theme palette config
│   ├── favicon.ico / favicon.svg / apple-logo.svg
│   ├── developer-og.jpg / developer-og-twitter.jpg
│   ├── index.html                             # WebKit SPA Documentation Viewer entrypoint
│   ├── css/                                   # Compiled DocC styling stylesheets
│   ├── js/                                    # Vue.js runtime, chunks, and Highlight.js grammars
│   ├── img/                                   # Apple badges, status indicators, and SVG icons
│   ├── index/
│   │   └── index.json                         # Complete Apple technology navigation hierarchy
│   ├── data/
│   │   └── documentation/
│   │       ├── developerdocumentation.json    # Technology root collection
│   │       └── developerdocumentation/        # 57 Topic and Symbol JSON graphs
│   └── documentation/                         # Static hosting routes with index.html fallbacks
│       └── developerdocumentation/            # Pre-rendered routes for 57 symbols/technologies
│
├── DocumentationCache/                        # 🗄️ Exact Xcode System Documentation Cache
│   └── v2024/
│       └── 27.2/
│           └── DeveloperDocumentation.index/
│               ├── .pc.fixup.marker           # Xcode cache integrity marker
│               ├── icu_rules_en-US@collation=search_1_1 # Apple ICU text collation engine
│               ├── Documentation.sqlite       # Spotlight index decoded into SQLite + FTS5
│               └── NSFileProtectionCompleteUntilFirstUserAuthentication/
│                   └── index.spotlightV3      # Symlink to raw 1.73 GB Spotlight V3 index
│
├── XcodeFrameworks/                           # 🧩 Xcode Internal Framework Resources
│   ├── CoreDocumentation.framework/           # Apple WebKit doc rendering engine bundle
│   │   └── Versions/A/Resources/
│   │       ├── documentation_template/
│   │       └── Info.plist
│   ├── IDEDocViewer.framework/                # Xcode Native Doc Viewer AppKit Window UI
│   │   └── Versions/A/Resources/
│   │       ├── Assets.car                     # Xcode DocViewer compiled artwork catalog
│   │       ├── IDEDocSearchResultsWindowController.nib
│   │       ├── IDEDocNavigatorArea.nib
│   │       ├── IDEDocTabbedWindowController.nib
│   │       ├── biglist.css / biglisttemplate.html
│   │       ├── Search.pdf
│   │       └── documentation_catalog.icns
│   └── IDEDocumentation.framework/            # Documentation Model & Catalog Icons
│       └── Versions/A/Resources/
│           ├── documentation_catalog.icns
│           ├── markdown@2x.png
│           └── tutorials@2x.png
│
├── Documentation.sqlite                       # 🔍 172,730-record SQLite DB + FTS5 full-text index
├── Preview Documentation.command              # 🚀 1-Click interactive browser launcher
│
├── index.html                                 # Root WebKit SPA entrypoint
├── metadata.json                              # Bundle metadata
├── theme-settings.json                        # Theme configuration
├── apple-logo.svg / favicon.ico / favicon.svg
├── css/                                       # Root CSS stylesheets
├── js/                                        # Root JS runtime modules
├── img/                                       # Root UI icons and assets
├── index/                                     # Root navigation tree
├── data/                                      # Root topic & symbol JSON data
└── documentation/                             # Root static routing fallbacks
```

---

## ⚡ How to Use

### 1. One-Click Interactive Preview (Browser)
Double-click `Preview Documentation.command` in Finder (or run `./Preview\ Documentation.command` in Terminal). This will:
1. Spin up a local documentation web server on port `8765`.
2. Automatically launch Safari to `http://localhost:8765/documentation/developerdocumentation`.
3. Provide the identical Apple Developer Documentation UI as inside Xcode, including sidebar navigation, search, dark/light theme switching, and syntax highlighting.

### 2. Apple DocC Archive (`DeveloperDocumentation.doccarchive`)
The `.doccarchive` bundle conforms directly to Apple's `com.apple.documentation.doccarchive` UTType specification.
- You can preview it directly using the Apple DocC compiler:
  ```bash
  xcrun docc preview DeveloperDocumentation.doccarchive
  ```
- Or open it directly inside Xcode:
  ```bash
  open -a Xcode DeveloperDocumentation.doccarchive
  ```

### 3. Querying the 172,730-Symbol Index via SQLite
Query symbols, frameworks, and docstrings using standard SQL or SQLite CLI:
```bash
sqlite3 Documentation.sqlite "SELECT title, abstract FROM documentation WHERE title LIKE 'SwiftUI%' LIMIT 10;"
```
Or run full-text search against the FTS5 index:
```bash
sqlite3 Documentation.sqlite "SELECT title, abstract FROM documentation_fts WHERE documentation_fts MATCH 'animation' LIMIT 10;"
```
