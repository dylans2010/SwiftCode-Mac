import os
import uuid
import hashlib

def generate_uuid(seed):
    m = hashlib.sha1(seed.encode('utf-8'))
    return m.hexdigest()[:24].upper()

def main():
    with open('file_list.txt', 'r') as f:
        all_paths = [line.strip() for line in f if line.strip()]

    # Normalize xcassets: if any file is inside .xcassets, we treat the .xcassets folder as the file reference.
    normalized_paths = set()
    for path in all_paths:
        if '.xcassets/' in path:
            xcassets_path = path[:path.find('.xcassets') + 9]
            normalized_paths.add(xcassets_path)
        else:
            normalized_paths.add(path)

    paths = sorted(list(normalized_paths))

    file_refs = {} # path -> uuid
    build_files = {} # path -> uuid
    group_ids = {} # folder_path -> uuid

    # Special UUIDs
    target_id = generate_uuid("target_SwiftCode")
    product_ref_id = generate_uuid("product_SwiftCode")
    main_group_id = generate_uuid("main_group")
    products_group_id = generate_uuid("products_group")
    sources_build_phase_id = generate_uuid("sources_build_phase")
    resources_build_phase_id = generate_uuid("resources_build_phase")
    frameworks_build_phase_id = generate_uuid("frameworks_build_phase")
    configuration_list_id = generate_uuid("configuration_list")
    debug_config_id = generate_uuid("debug_config")
    release_config_id = generate_uuid("release_config")
    project_id = generate_uuid("project")
    project_configuration_list_id = generate_uuid("project_configuration_list")
    project_debug_config_id = generate_uuid("project_debug_config")
    project_release_config_id = generate_uuid("project_release_config")

    for path in paths:
        file_refs[path] = generate_uuid(f"file_ref_{path}")
        if path.endswith('.swift') or path.endswith('.json') or path.endswith('.xcassets') or path.endswith('.entitlements'):
             build_files[path] = generate_uuid(f"build_file_{path}")

    # Build folder hierarchy
    folders = set()
    for path in paths:
        parts = path.split('/')
        for i in range(1, len(parts)):
            folders.add('/'.join(parts[:i]))

    for folder in folders:
        group_ids[folder] = generate_uuid(f"group_{folder}")

    # Start writing pbxproj
    out = []
    out.append("// !$*UTF8*$!")
    out.append("{")
    out.append("\tarchiveVersion = 1;")
    out.append("\tclasses = {")
    out.append("\t};")
    out.append("\tobjectVersion = 77;")
    out.append("\tobjects = {")
    out.append("")

    # PBXBuildFile
    out.append("/* Begin PBXBuildFile section */")
    for path, uid in build_files.items():
        out.append(f"\t\t{uid} /* {os.path.basename(path)} in Sources/Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]}; }};")
    out.append("/* End PBXBuildFile section */")
    out.append("")

    # PBXFileReference
    out.append("/* Begin PBXFileReference section */")
    out.append(f"\t\t{product_ref_id} /* SwiftCode.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SwiftCode.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for path, uid in file_refs.items():
        name = os.path.basename(path)
        if path.endswith('.swift'):
            ft = "sourcecode.swift"
        elif path.endswith('.xcassets'):
            ft = "folder.assetcatalog"
        elif path.endswith('.json'):
            ft = "text.json"
        elif path.endswith('.entitlements'):
            ft = "text.plist.entitlements"
        else:
            ft = "text"
        out.append(f"\t\t{uid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = \"{name}\"; sourceTree = \"<group>\"; }};")
    out.append("/* End PBXFileReference section */")
    out.append("")

    # PBXFrameworksBuildPhase
    out.append("/* Begin PBXFrameworksBuildPhase section */")
    out.append(f"\t\t{frameworks_build_phase_id} /* Frameworks */ = {{")
    out.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")
    out.append("/* End PBXFrameworksBuildPhase section */")
    out.append("")

    # PBXGroup
    out.append("/* Begin PBXGroup section */")
    # Main Group
    out.append(f"\t\t{main_group_id} = {{")
    out.append("\t\t\tisa = PBXGroup;")
    out.append("\t\t\tchildren = (")
    out.append(f"\t\t\t\t{group_ids['SwiftCode']},")
    out.append(f"\t\t\t\t{products_group_id} /* Products */,")
    out.append("\t\t\t);")
    out.append("\t\t\tsourceTree = \"<group>\";")
    out.append("\t\t};")

    # Products Group
    out.append(f"\t\t{products_group_id} /* Products */ = {{")
    out.append("\t\t\tisa = PBXGroup;")
    out.append("\t\t\tchildren = (")
    out.append(f"\t\t\t\t{product_ref_id} /* SwiftCode.app */,")
    out.append("\t\t\t);")
    out.append("\t\t\tname = Products;")
    out.append("\t\t\tsourceTree = \"<group>\";")
    out.append("\t\t};")

    # Folder Groups
    sorted_folders = sorted(list(folders), key=lambda x: x.count('/'), reverse=True)
    folder_children = {f: [] for f in folders}
    for path in paths:
        parent = os.path.dirname(path)
        if parent in folder_children:
            folder_children[parent].append(file_refs[path])

    for folder in sorted_folders:
        parent = os.path.dirname(folder)
        if parent in folder_children:
            folder_children[parent].append(group_ids[folder])

    for folder in sorted(list(folders)):
        out.append(f"\t\t{group_ids[folder]} /* {os.path.basename(folder)} */ = {{")
        out.append("\t\t\tisa = PBXGroup;")
        out.append("\t\t\tchildren = (")
        for child_uid in sorted(folder_children[folder]):
            out.append(f"\t\t\t\t{child_uid},")
        out.append("\t\t\t);")
        out.append(f"\t\t\tpath = \"{os.path.basename(folder)}\";")
        out.append("\t\t\tsourceTree = \"<group>\";")
        out.append("\t\t};")

    out.append("/* End PBXGroup section */")
    out.append("")

    # PBXNativeTarget
    out.append("/* Begin PBXNativeTarget section */")
    out.append(f"\t\t{target_id} /* SwiftCode */ = {{")
    out.append("\t\t\tisa = PBXNativeTarget;")
    out.append(f"\t\t\tbuildConfigurationList = {configuration_list_id} /* Build configuration list for PBXNativeTarget \"SwiftCode\" */;")
    out.append("\t\t\tbuildPhases = (")
    out.append(f"\t\t\t\t{sources_build_phase_id} /* Sources */,")
    out.append(f"\t\t\t\t{frameworks_build_phase_id} /* Frameworks */,")
    out.append(f"\t\t\t\t{resources_build_phase_id} /* Resources */,")
    out.append("\t\t\t);")
    out.append("\t\t\tbuildRules = (")
    out.append("\t\t\t);")
    out.append("\t\t\tdependencies = (")
    out.append("\t\t\t);")
    out.append("\t\t\tname = SwiftCode;")
    out.append("\t\t\tproductName = SwiftCode;")
    out.append(f"\t\t\tproductReference = {product_ref_id} /* SwiftCode.app */;")
    out.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    out.append("\t\t};")
    out.append("/* End PBXNativeTarget section */")
    out.append("")

    # PBXProject
    out.append("/* Begin PBXProject section */")
    out.append(f"\t\t{project_id} /* Project object */ = {{")
    out.append("\t\t\tisa = PBXProject;")
    out.append("\t\t\tattributes = {")
    out.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    out.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    out.append("\t\t\t\tLastUpgradeCheck = 1600;")
    out.append("\t\t\t\tTargetAttributes = {")
    out.append(f"\t\t\t\t\t{target_id} = {{")
    out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    out.append("\t\t\t\t\t};")
    out.append("\t\t\t\t};")
    out.append("\t\t\t};")
    out.append(f"\t\t\tbuildConfigurationList = {project_configuration_list_id} /* Build configuration list for PBXProject \"SwiftCode\" */;")
    out.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    out.append("\t\t\tdevelopmentRegion = en;")
    out.append("\t\t\thasScannedForEncodings = 0;")
    out.append("\t\t\tknownRegions = (")
    out.append("\t\t\t\ten,")
    out.append("\t\t\t\tBase,")
    out.append("\t\t\t);")
    out.append(f"\t\t\tmainGroup = {main_group_id};")
    out.append("\t\t\tproductRefGroup = {products_group_id} /* Products */;")
    out.append("\t\t\tprojectDirPath = \"\";")
    out.append("\t\t\tprojectRoot = \"\";")
    out.append("\t\t\ttargets = (")
    out.append(f"\t\t\t\t{target_id} /* SwiftCode */,")
    out.append("\t\t\t);")
    out.append("\t\t};")
    out.append("/* End PBXProject section */")
    out.append("")

    # PBXResourcesBuildPhase
    out.append("/* Begin PBXResourcesBuildPhase section */")
    out.append(f"\t\t{resources_build_phase_id} /* Resources */ = {{")
    out.append("\t\t\tisa = PBXResourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    for path in paths:
        if path.startswith('SwiftCode/Resources/') and path in build_files:
             out.append(f"\t\t\t\t{build_files[path]} /* {os.path.basename(path)} in Resources */,")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")
    out.append("/* End PBXResourcesBuildPhase section */")
    out.append("")

    # PBXSourcesBuildPhase
    out.append("/* Begin PBXSourcesBuildPhase section */")
    out.append(f"\t\t{sources_build_phase_id} /* Sources */ = {{")
    out.append("\t\t\tisa = PBXSourcesBuildPhase;")
    out.append("\t\t\tbuildActionMask = 2147483647;")
    out.append("\t\t\tfiles = (")
    for path in paths:
        if path.endswith('.swift') and path in build_files:
            out.append(f"\t\t\t\t{build_files[path]} /* {os.path.basename(path)} in Sources */,")
    out.append("\t\t\t);")
    out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    out.append("\t\t};")
    out.append("/* End PBXSourcesBuildPhase section */")
    out.append("")

    # XCBuildConfiguration
    out.append("/* Begin XCBuildConfiguration section */")
    # Target configs
    out.append(f"\t\t{debug_config_id} /* Debug */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    out.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = SwiftCode/Resources/SwiftCode.entitlements;")
    out.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    out.append("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    out.append("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    out.append("\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.developer-tools\";")
    out.append("\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = \"\";")
    out.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/../Frameworks\";")
    out.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.swiftcode.app;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tSWIFT_VERSION = 6.0;")
    out.append("\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Debug;")
    out.append("\t\t};")

    out.append(f"\t\t{release_config_id} /* Release */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
    out.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
    out.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = SwiftCode/Resources/SwiftCode.entitlements;")
    out.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    out.append("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    out.append("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    out.append("\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.developer-tools\";")
    out.append("\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = \"\";")
    out.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/../Frameworks\";")
    out.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;")
    out.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.swiftcode.app;")
    out.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
    out.append("\t\t\t\tSWIFT_VERSION = 6.0;")
    out.append("\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Release;")
    out.append("\t\t};")

    # Project configs
    out.append(f"\t\t{project_debug_config_id} /* Debug */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    out.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    out.append("\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
    out.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    out.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    out.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    out.append("\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
    out.append("\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;")
    out.append("\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_COMMA = YES;")
    out.append("\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;")
    out.append("\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;")
    out.append("\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;")
    out.append("\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;")
    out.append("\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;")
    out.append("\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;")
    out.append("\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;")
    out.append("\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;")
    out.append("\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;")
    out.append("\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;")
    out.append("\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;")
    out.append("\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;")
    out.append("\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;")
    out.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    out.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    out.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    out.append("\t\t\t\tENABLE_TESTABILITY = YES;")
    out.append("\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;")
    out.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    out.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    out.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
    out.append("\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (")
    out.append("\t\t\t\t\t\"DEBUG=1\",")
    out.append("\t\t\t\t\t\"$(inherited)\",")
    out.append("\t\t\t\t);")
    out.append("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    out.append("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    out.append("\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    out.append("\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    out.append("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    out.append("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    out.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;")
    out.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
    out.append("\t\t\t\tMTL_FAST_MATH = YES;")
    out.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    out.append("\t\t\t\tSDKROOT = macosx;")
    out.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    out.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Debug;")
    out.append("\t\t};")

    out.append(f"\t\t{project_release_config_id} /* Release */ = {{")
    out.append("\t\t\tisa = XCBuildConfiguration;")
    out.append("\t\t\tbuildSettings = {")
    out.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    out.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    out.append("\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;")
    out.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    out.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    out.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    out.append("\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;")
    out.append("\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;")
    out.append("\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_COMMA = YES;")
    out.append("\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;")
    out.append("\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;")
    out.append("\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;")
    out.append("\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;")
    out.append("\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;")
    out.append("\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;")
    out.append("\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;")
    out.append("\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;")
    out.append("\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;")
    out.append("\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;")
    out.append("\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;")
    out.append("\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;")
    out.append("\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;")
    out.append("\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;")
    out.append("\t\t\t\tCOPY_PHASE_STRIP = YES;")
    out.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
    out.append("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
    out.append("\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;")
    out.append("\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;")
    out.append("\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;")
    out.append("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
    out.append("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
    out.append("\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
    out.append("\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
    out.append("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
    out.append("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
    out.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;")
    out.append("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
    out.append("\t\t\t\tMTL_FAST_MATH = YES;")
    out.append("\t\t\t\tSDKROOT = macosx;")
    out.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    out.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
    out.append("\t\t\t};")
    out.append("\t\t\tname = Release;")
    out.append("\t\t};")
    out.append("/* End XCBuildConfiguration section */")
    out.append("")

    # XCConfigurationList
    out.append("/* Begin XCConfigurationList section */")
    out.append(f"\t\t{configuration_list_id} /* Build configuration list for PBXNativeTarget \"SwiftCode\" */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    out.append(f"\t\t\t\t{debug_config_id} /* Debug */,")
    out.append(f"\t\t\t\t{release_config_id} /* Release */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")

    out.append(f"\t\t{project_configuration_list_id} /* Build configuration list for PBXProject \"SwiftCode\" */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    out.append(f"\t\t\t\t{project_debug_config_id} /* Debug */,")
    out.append(f"\t\t\t\t{project_release_config_id} /* Release */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")
    out.append("/* End XCConfigurationList section */")
    out.append("")

    out.append("\t};")
    out.append(f"\trootObject = {project_id} /* Project object */;")
    out.append("}")

    # Create directories
    os.makedirs('SwiftCode.xcodeproj', exist_ok=True)
    os.makedirs('SwiftCode.xcodeproj/project.xcworkspace', exist_ok=True)
    os.makedirs('SwiftCode.xcodeproj/xcshareddata/xcschemes', exist_ok=True)

    with open('SwiftCode.xcodeproj/project.pbxproj', 'w') as f:
        f.write('\n'.join(out))

    with open('SwiftCode.xcodeproj/project.xcworkspace/contents.xcworkspacedata', 'w') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0">\n  <FileRef location="self:"></FileRef>\n</Workspace>')

    with open('SwiftCode.xcodeproj/xcshareddata/xcschemes/SwiftCode.xcscheme', 'w') as f:
        f.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildItems>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference
               BuildableIdentifier="primary"
               BlueprintIdentifier="{target_id}"
               BuildableName="SwiftCode.app"
               BlueprintName="SwiftCode"
               ReferencedContainer="container:SwiftCode.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildItems>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables></Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useLaunchSchemeArgsEnv="YES" askForAppToLaunch="NO" ignoreLaunchSystems="YES" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runableDebuggingMode="0">
         <BuildableReference
            BuildableIdentifier="primary"
            BlueprintIdentifier="{target_id}"
            BuildableName="SwiftCode.app"
            BlueprintName="SwiftCode"
            ReferencedContainer="container:SwiftCode.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>""")

if __name__ == "__main__":
    main()
