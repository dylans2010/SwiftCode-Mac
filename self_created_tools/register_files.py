#!/usr/bin/env python3
import sys
import os
import re
import uuid

def generate_uuid():
    # Generate a unique 24-char uppercase hex string
    return uuid.uuid4().hex[:24].upper()

def register_file(project_path, filepath, group_uuid, sources_build_phase_uuid):
    filename = os.path.basename(filepath)
    print("Registering %s in %s..." % (filename, project_path))

    with open(project_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Check if already registered
    if "/* %s */" % filename in content:
        print("%s is already registered. Skipping." % filename)
        return True

    # Generate UUIDs
    build_file_uuid = generate_uuid()
    file_ref_uuid = generate_uuid()

    print("Generated Build File UUID: %s" % build_file_uuid)
    print("Generated File Reference UUID: %s" % file_ref_uuid)

    # 1. PBXBuildFile Section
    build_file_entry = "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (build_file_uuid, filename, file_ref_uuid, filename)
    content = content.replace("/* Begin PBXBuildFile section */\n", "/* Begin PBXBuildFile section */\n" + build_file_entry)

    # 2. PBXFileReference Section
    file_ref_entry = "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };\n" % (file_ref_uuid, filename, filename)
    content = content.replace("/* Begin PBXFileReference section */\n", "/* Begin PBXFileReference section */\n" + file_ref_entry)

    # 3. Add to Group children
    # Find the children of the group block
    group_pattern = r"(%s /\* [^*]+ \*/ = \{[^}]+children = \(\n)" % group_uuid
    match = re.search(group_pattern, content)
    if not match:
        print("Error: Could not find Group %s" % group_uuid)
        return False

    group_insertion = "\t\t\t\t%s /* %s */,\n" % (file_ref_uuid, filename)
    content = content.replace(match.group(1), match.group(1) + group_insertion)

    # 4. Add to Sources Build Phase
    sources_pattern = r"(%s /\* Sources \*/ = \{[^}]+files = \(\n)" % sources_build_phase_uuid
    match_sources = re.search(sources_pattern, content)
    if not match_sources:
        print("Error: Could not find Sources Build Phase %s" % sources_build_phase_uuid)
        return False

    sources_insertion = "\t\t\t\t%s /* %s in Sources */,\n" % (build_file_uuid, filename)
    content = content.replace(match_sources.group(1), match_sources.group(1) + sources_insertion)

    with open(project_path, "w", encoding="utf-8") as f:
        f.write(content)

    print("Successfully registered %s!" % filename)
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: register_file.py <relative_filepath> <group_uuid>")
        sys.exit(1)

    filepath = sys.argv[1]
    group_uuid = sys.argv[2]
    sources_build_phase_uuid = "9BF8BFB9B87ED46BDA700029"
    project_path = "SwiftCode.xcodeproj/project.pbxproj"

    if not os.path.exists(project_path):
        print("Error: Xcode project file not found at %s" % project_path)
        sys.exit(1)

    success = register_file(project_path, filepath, group_uuid, sources_build_phase_uuid)
    if not success:
        sys.exit(1)
