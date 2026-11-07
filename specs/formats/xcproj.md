# Spec: The JSON `.xcproj` project format

Status: **draft** (clean-room spec derived from reference evidence).

SwiftCode supports the modern JSON-based project representation `.xcproj`,
introduced in Xcode 27 as an alternative to the legacy OpenStep ASCII `.pbxproj` format.
This specification defines the file structure, schema, data types, inheritance model,
and expansion semantics observed in canonical `.xcproj` bundles.

---

## 1. File Location and Bundle Structure

An `.xcodeproj` bundle using the modern project format contains:

```
<ProjectName>.xcodeproj/
├── project.xcproj                          # The primary JSON project file
├── project.xcworkspace/
│   └── contents.xcworkspacedata            # Workspace wrapper XML
└── xcuserdata/
    └── <username>.xcuserdatad/
        └── xcschemes/
            └── xcschememanagement.plist     # Scheme ordering and shared state
```

Unlike `.pbxproj`, which serializes an object graph as a flat list of UUID-keyed objects,
`project.xcproj` is a hierarchical JSON document with explicit typed arrays and objects.

---

## 2. Top-Level JSON Document Schema

A valid `project.xcproj` file contains the following top-level keys:

| Key | Type | Description |
|---|---|---|
| `default-configuration` | String | The default build configuration (e.g. `"Release"` or `"Debug"`). |
| `configurations` | Array of Strings | All valid build configuration names defined in the project. |
| `localizations` | Object | Development region and list of supported localizations. |
| `files` | Array of Objects | Tree of source files, groups, folders, and product references. |
| `targets` | Array of Objects | Target definitions with build phases and target-level settings. |
| `build-settings` | Object (Dictionary) | Project-level default build settings and configuration overrides. |
| `last-upgrade` | String | The Xcode/tooling version at last project upgrade (e.g. `"27.0"`). |
| `last-swift-update` | String | The Swift language/compiler version update level (e.g. `"27.0"`). |

Trailing commas are permitted in container literals (arrays and dictionaries), following
relaxed JSON / JSON5 parsing conventions.

---

## 3. Localizations Schema

The `localizations` dictionary configures the localization environment:

```json
"localizations": {
  "development": "en",
  "supported": [
    "Base"
  ]
}
```

- `development`: ISO language code for the development region (e.g. `"en"`).
- `supported`: List of supported localization names or language codes (e.g. `["Base", "es", "fr"]`).

---

## 4. Files Hierarchy

The `files` array represents the file system hierarchy and project organization.
Entries are distinguished by the `kind` property:

### 4.1 Folder Entry (`kind: "folder"`)
Represents a synchronized directory on disk whose children are automatically discovered by the build system.

```json
{
  "kind": "folder",
  "path": "MyApp",
  "target-membership": [ "MyApp" ]
}
```

- `path`: Relative path from the project bundle directory to the folder on disk.
- `target-membership`: Array of target names that compile or consume files inside this folder.

### 4.2 Group Entry (`kind: "group"`)
Represents a logical grouping (virtual folder), such as Products or Frameworks.

```json
{
  "kind": "group",
  "name": "Products",
  "children": [
    {
      "path": "<PRODUCTS>/MyApp.app",
      "id": "000000000000000000000120",
      "type": "wrapper.application",
      "index": false
    }
  ]
}
```

- `name`: Logical name of the group.
- `children`: Array of child file or group entries.

### 4.3 File Entry
Represents an explicit file or product reference.

- `path`: Path to the file, optionally using virtual roots like `<PRODUCTS>/`.
- `id`: Unique 24-character hex identifier (matching PBX object ID format).
- `type`: Uniform Type Identifier (UTI) describing the file type (e.g. `"wrapper.application"`, `"sourcecode.swift"`).
- `index`: Boolean indicating whether the file should be indexed by the IDE indexer (`false` for built products).

---

## 5. Targets Schema

Each element of `targets` defines a build target:

```json
{
  "name": "MyApp",
  "id": "00000000000100000000",
  "product": "Products/MyApp.app",
  "product-type": "application",
  "build-phases": [
    "compile-sources",
    "frameworks",
    "resources"
  ],
  "build-settings": { ... }
}
```

### 5.1 Target Properties

| Property | Type | Description |
|---|---|---|
| `name` | String | Target name. |
| `id` | String | Unique 24-character identifier. |
| `product` | String | Relative path to the product in the `files` Products group. |
| `product-type` | String | Target product type (`"application"`, `"framework"`, `"bundle"`, `"tool"`, `"unit-test"`, etc.). |
| `build-phases` | Array of Strings | Ordered list of phase identifiers executed during target build. |
| `build-settings` | Object | Target-level build settings dictionary. |

### 5.2 Build Phases Ordering
Standard phases execute in declarative order:
1. `"headers"` (if applicable)
2. `"compile-sources"`
3. `"frameworks"`
4. `"resources"`
5. Custom script phases (referenced by name or id)

---

## 6. Build Settings and Condition Overrides

Build settings are key-value pairs where keys represent Xcode/Swift build setting names,
and values are strings, booleans, integers, or arrays of strings.

### 6.1 Inheritance Model
Settings resolve in the following precedence order (highest to lowest):
1. Command-line overrides (`xcodebuild FOO=bar`)
2. Target-level per-configuration/per-SDK overrides (e.g. `DEBUG_INFORMATION_FORMAT[config=Debug]`)
3. Target-level general settings
4. Project-level per-configuration/per-SDK overrides
5. Project-level general settings
6. Architecture / platform defaults

### 6.2 Condition Overrides Syntax
Keys may include conditions inside square brackets:
- `[config=<ConfigurationName>]`: Overrides setting for a specific configuration (e.g. `[config=Debug]`).
- `[sdk=<SDKPattern>]`: Overrides setting for matching SDKs (e.g. `[sdk=iphoneos*]`, `[sdk=macosx*]`).
- Compound conditions: `[config=Debug][sdk=iphoneos*]`.

### 6.3 Variable Expansion & Templates
Settings support standard Xcode variable expansion:
- `$(TARGET_NAME)`: Evaluates to target's name.
- `$(PROJECT_UNIQUE_VALUE)`: A unique project-level alphanumeric identifier (e.g. `"B1CRO35L"`).
- `$(PROJECT_UNIQUE_VALUE:identifier)`: Identifier-sanitized unique project value.
- `$(PRODUCT_NAME:rfc1034identifier)`: RFC-1034 sanitized product name suitable for bundle IDs.
- `$(inherited)`: Expands to the value inherited from the next level down in precedence.

Example bundle identifier expansion:
```
devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)
```

---

## 7. Evidence

- **Level 2 (Reference File)**: Derived from inspection of canonical reference bundle
  `/Users/dylan/Downloads/Testing.xcodeproj/project.xcproj` created by Xcode 27.1 (27A9269).
