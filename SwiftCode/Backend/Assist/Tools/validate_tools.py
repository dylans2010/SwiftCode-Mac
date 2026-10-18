#!/usr/bin/env python3
"""Static audit for the SwiftCode Assist tool ecosystem.

Parses Swift + Markdown with regexes — no Swift toolchain needed, so it
runs in CI/Linux. Checks:

  1. Registry completeness: every tool struct in Tools/ (+ use_workers)
     is registered in AssistToolRegistry; no duplicates; no register()
     without a matching struct.
  2. ID uniqueness + shape: IDs must match ^[A-Za-z][A-Za-z0-9_-]*$
     (plan-AskUser is the intentional hyphen/uppercase exception).
  3. Docs completeness: every registered tool has an AvailableTools.md
     catalog entry (before the Cloud Toolkit section) and vice versa;
     the catalog (risk) label matches the tool's declared riskLevel.
  4. file_read line-range requirement: schema declares `lines` and
     execute() handles it.
  5. Terminal-execution exclusivity: only use_terminal + the explicit
     approval-exempt allowlist may spawn processes; allowlisted files
     must contain no shell-string execution (/bin/bash, /bin/sh, -lc).
  6. suggestedNextActions validity: every suggested ID is registered.
  7. isReadOnly honesty: safeRead tools must not call file-mutation APIs
     (known exception: project_snapshot copies the workspace to a
     snapshot directory, documented in AvailableTools.md).

Usage: python3 validate_tools.py [--repo <path>] [--strict]
Exit code 1 on any FAIL (or WARN under --strict).
"""
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]  # SwiftCode-Mac/
ASSIST = REPO / "SwiftCode/Backend/Assist"
TOOLS_DIR = ASSIST / "Tools"
CATALOG = ASSIST / "Functions/System Assets/AvailableTools.md"
REGISTRY = ASSIST / "AssistToolRegistry.swift"

# Files allowed to spawn processes, with the justification for each.
# Everything else in Tools/ must not contain Process(, ProcessRunnerTool,
# AgentTerminalService, AssistArgvRunner, /bin/bash, /bin/sh.
PROCESS_ALLOWLIST = {
    "UseTermFunction.swift": "use_terminal — the sole model-facing terminal tool",
    "AssistBuildProjectTool.swift": "project_build + generate_xcodeproj — approval-exempt fixed-argv xcodebuild/xcodegen",
    "AssistTestRunnerTool.swift": "project_test — delegates to AssistVerificationPipeline (fixed argv)",
    "AssistCompilerDiagnosticsEngine.swift": "compiler_diagnostics_engine — approval-exempt fixed-argv xcodebuild",
    "AssistDependencyResolutionEngine.swift": "dependency_resolution_engine — approval-exempt fixed-argv xcodebuild",
    "AssistVersionControlOperator.swift": "version_control_operator — approval-exempt fixed-argv git",
    "AssistToolingSupport.swift": "AssistArgvRunner — the shared fixed-argv runner itself (not a tool)",
    "AssistXcodeProjectResolver.swift": "read-only `xcodebuild -list -json` via fixed argv",
    # Union with main's 60+ tool files (verified: every entry below runs a
    # fixed system executable via Process() + argv array — no shell string,
    # no model-chosen executable, except performance_benchmark whose
    # executable is restricted to its own 5-entry allowlist).
    "AssistBinaryPlistConverterTool.swift": "binary_plist_converter — fixed /usr/bin/plutil, argv array",
    "AssistDeviceListTool.swift": "device_list — fixed /usr/bin/xcrun (devicectl/xctrace), argv array",
    "AssistDoccBuildTool.swift": "docc_build — fixed /usr/bin/xcodebuild, argv array",
    "AssistFileHashVerifyTool.swift": "file_hash_verify — fixed /usr/bin/shasum, /usr/bin/md5, argv array",
    "AssistFinderTools.swift": "open_in_finder/reveal_in_finder — fixed /usr/bin/open, argv array",
    "AssistGitBisectTool.swift": "git_bisect — fixed /usr/bin/git, argv array",
    "AssistGitBlameTool.swift": "git_blame_inspector — fixed /usr/bin/git, argv array",
    "AssistGitBranchCompareTool.swift": "git_branch_compare — fixed /usr/bin/git, argv array",
    "AssistGitBranchManagerTool.swift": "git_branch_manager — fixed /usr/bin/git, argv array",
    "AssistGitCherryPickTool.swift": "git_cherry_pick — fixed /usr/bin/git, argv array",
    "AssistGitLogViewerTool.swift": "git_log_viewer — fixed /usr/bin/git, argv array",
    "AssistGitPRSummaryTool.swift": "git_pr_summary — fixed /usr/bin/git, argv array",
    "AssistGitStashTool.swift": "git_stash_operator — fixed /usr/bin/git, argv array",
    "AssistMachOBinaryAnalyzerTool.swift": "mach_o_binary_analyzer — fixed /usr/bin/file, /usr/bin/xcrun (otool), argv array",
    "AssistPackageDependencyAuditTool.swift": "package_dependency_audit — fixed /usr/bin/swift, argv array",
    "AssistPackageDependencyUpdateTool.swift": "package_dependency_update — fixed /usr/bin/swift, argv array",
    "AssistPackageManifestValidateTool.swift": "package_manifest_validate — fixed /usr/bin/swift, argv array",
    "AssistPerformanceBenchmarkTool.swift": "performance_benchmark — executable restricted to 5-entry allowlist (/usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du), argv array, no shell",
    "AssistProcessMonitorTool.swift": "process_monitor_tool — fixed /bin/ps, argv array",
    "AssistProjectArchiveTool.swift": "project_archive — fixed /usr/bin/xcodebuild, argv array",
    "AssistProjectBuildSettingsTool.swift": "project_build_settings — fixed /usr/bin/xcodebuild, argv array",
    "AssistProjectCleanTool.swift": "project_clean — fixed /usr/bin/xcodebuild, argv array",
    "AssistProjectSchemeListTool.swift": "project_scheme_list — fixed /usr/bin/xcodebuild, argv array",
    "AssistProjectSigningTool.swift": "project_signing — fixed /usr/bin/xcodebuild, argv array",
    "AssistProjectTargetListTool.swift": "project_target_list — fixed /usr/bin/xcodebuild, argv array",
    "AssistProvisioningCheckTool.swift": "provisioning_check — fixed /usr/bin/security, argv array",
    "AssistProvisioningProfileReaderTool.swift": "provisioning_profile_reader — fixed /usr/bin/security, argv array",
    "AssistSigningCertificateInspectorTool.swift": "signing_certificate_inspector — fixed /usr/bin/security, argv array",
    "AssistSimulatorBootTool.swift": "simulator_boot — fixed /usr/bin/xcrun, argv array",
    "AssistSimulatorControllerTool.swift": "simulator_controller — fixed /usr/bin/xcrun (simctl), argv array",
    "AssistSimulatorListTool.swift": "simulator_list — fixed /usr/bin/xcrun, argv array",
    "AssistSwiftASTInspectorTool.swift": "swift_ast_inspector — fixed /usr/bin/xcrun (swiftc -dump-ast), argv array",
    "AssistSwiftPackageTool.swift": "swift_package_manager — fixed /usr/bin/swift, argv array",
    "AssistSystemNotificationTool.swift": "system_notification_tool — fixed /usr/bin/osascript, argv array (UNUserNotificationCenter first; AppleScript fallback with quote escaping)",
    "AssistTestCoverageReportTool.swift": "test_coverage_report — fixed /usr/bin/xcodebuild, argv array",
    "AssistTestCoverageReporterTool.swift": "test_coverage_reporter — fixed /usr/bin/xcrun (xccov), argv array",
    "AssistTestRunSingleTool.swift": "test_run_single — fixed /usr/bin/xcodebuild, argv array",
    "AssistXCResultParserTool.swift": "xcresult_parser — fixed /usr/bin/xcrun (xcresulttool), argv array",
    "AssistXcodeBuildSettingsTool.swift": "xcode_build_settings_inspector — fixed /usr/bin/xcrun, argv array",
    "AssistXcodeDeviceDestinationTool.swift": "xcode_device_destination_finder — fixed /usr/bin/xcrun (simctl), argv array",
    "AssistXcodeSchemeTool.swift": "xcode_scheme_manager — fixed /usr/bin/xcodebuild, argv array",
}

# Shell-executable patterns. The /bin/sh and /bin/bash patterns are
# boundary-aware: "/usr/bin/shasum" must NOT match (it is a fixed-argv
# checksum executable, not a shell). A match requires the shell name to
# end at a non-word character (quote, space, end of line, ...).
SHELL_PATTERNS = [r"/bin/(?:ba)?sh(?![A-Za-z0-9_])", r'"-lc"', r"'-lc'"]

# safeRead tools with a documented, intentional write side effect.
READONLY_WRITE_EXCEPTIONS = {
    "project_snapshot": "copies the workspace to a snapshot directory (documented)",
}

MUTATION_PATTERNS = [r"\.writeFile\(", r"removeItem\(", r"createDirectory\(", r"\.deleteFile\(", r"\.write\(to:"]

failures = []
warnings = []


def fail(msg):
    failures.append(msg)
    print(f"FAIL {msg}")


def warn(msg):
    warnings.append(msg)
    print(f"WARN {msg}")


def ok(msg):
    print(f"PASS {msg}")


def parse_tool_file(path):
    text = path.read_text()
    ids = re.findall(r'public (?:let|var) id(?::\s*String)?\s*=\s*"([^"]+)"', text)
    # Some tools declare their ID via a static constant, e.g.
    # ReverseToolAdapter: `public static let toolID = "reverse_analyze"`.
    ids += re.findall(r'public static let toolID\s*=\s*"([^"]+)"', text)
    risk = None
    m = re.search(r"riskLevel[^.]*\.\s*(\w+)", text)
    if m:
        risk = m.group(1)
    return ids, risk, text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=str(REPO))
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()
    repo = Path(args.repo)
    globals().update({
        "REPO": repo,
        "ASSIST": repo / "SwiftCode/Backend/Assist",
        "TOOLS_DIR": repo / "SwiftCode/Backend/Assist/Tools",
        "CATALOG": repo / "SwiftCode/Backend/Assist/Functions/System Assets/AvailableTools.md",
        "REGISTRY": repo / "SwiftCode/Backend/Assist/AssistToolRegistry.swift",
    })

    # --- 1. Registry completeness -------------------------------------
    registry_text = REGISTRY.read_text()
    registered = re.findall(r"register\(\s*(\w+)\(\)\s*\)", registry_text)
    # Map struct names -> ids by scanning tool files.
    struct_to_ids = {}
    id_to_file = {}
    for path in sorted(TOOLS_DIR.glob("*.swift")):
        ids, risk, _ = parse_tool_file(path)
        for tid in ids:
            id_to_file.setdefault(tid, path.name)
    workers = ASSIST / "Subagents/Tools/UseWorkersTool.swift"
    # Tools declared outside Tools/: the native Reverse adapter lives in
    # API/Internal API/Reverse/ but is registered like any other tool.
    extra_tool_files = [ASSIST / "API/Internal API/Reverse/ReverseToolAdapter.swift"]
    if workers.exists():
        ids, _, _ = parse_tool_file(workers)
        for tid in ids:
            id_to_file.setdefault(tid, "Subagents/Tools/UseWorkersTool.swift")
    for extra in extra_tool_files:
        if extra.exists():
            ids, _, _ = parse_tool_file(extra)
            for tid in ids:
                id_to_file.setdefault(tid, str(extra.relative_to(ASSIST)))

    # Struct names registered: register(X()) -> find the file declaring
    # struct/class X, and take the IDs declared in that file. (A file may
    # hold 2 tools, e.g. the build file; the union across registered
    # structs is what the completeness check needs.)
    struct_to_file = {}
    for path in sorted(list(TOOLS_DIR.glob("*.swift")) + [workers] + extra_tool_files):
        text = path.read_text()
        for struct_name in re.findall(r"(?:struct|class)\s+(\w+)", text):
            struct_to_file.setdefault(struct_name, path)

    registered_ids = set()
    for struct_name in registered:
        fpath = struct_to_file.get(struct_name)
        if fpath is None:
            fail(f"registry: register({struct_name}()) has no matching tool struct")
            continue
        ids, _, _ = parse_tool_file(fpath)
        registered_ids.update(ids)
    declared_ids = set(id_to_file)
    missing_from_registry = sorted(declared_ids - registered_ids)
    if missing_from_registry:
        fail(f"registry: tools declared but not registered: {missing_from_registry}")
    else:
        ok(f"registry: all {len(declared_ids)} declared tools registered")
    extra_registered = sorted(registered_ids - declared_ids)
    if extra_registered:
        fail(f"registry: registered IDs with no tool struct: {extra_registered}")
    if len(registered) != len(set(registered)):
        fail("registry: duplicate register() calls")
    else:
        ok("registry: no duplicate register() calls")

    # --- 2. ID uniqueness + shape -------------------------------------
    seen = {}
    dup = False
    for tid, fname in id_to_file.items():
        if tid in seen:
            dup = True
        seen[tid] = fname
    # Count raw declarations to catch same-file duplicates.
    all_ids = []
    for path in sorted(list(TOOLS_DIR.glob("*.swift")) + [workers] + extra_tool_files):
        ids, _, _ = parse_tool_file(path)
        all_ids.extend(ids)
    if len(all_ids) != len(set(all_ids)):
        fail(f"ids: duplicate tool IDs: {[x for x in set(all_ids) if all_ids.count(x) > 1]}")
    elif dup:
        fail("ids: duplicate tool IDs across files")
    else:
        ok(f"ids: {len(all_ids)} unique tool IDs")
    bad_shape = [t for t in all_ids if not re.match(r"^[A-Za-z][A-Za-z0-9_-]*$", t)]
    if bad_shape:
        fail(f"ids: malformed IDs: {bad_shape}")
    else:
        ok("ids: all IDs match ^[A-Za-z][A-Za-z0-9_-]*$")

    # --- 3. Docs completeness -----------------------------------------
    catalog_text = CATALOG.read_text()
    catalog_section = catalog_text.split("## Cloud Toolkit")[0]
    doc_entries = {}
    for line in catalog_section.splitlines():
        m = re.match(r"\s*-\s*`([^`]+)`\s*\(([^)]+)\)", line)
        if m:
            doc_entries[m.group(1)] = m.group(2)
    missing_docs = sorted(declared_ids - set(doc_entries))
    if missing_docs:
        fail(f"docs: registered tools missing from AvailableTools.md: {missing_docs}")
    else:
        ok(f"docs: all {len(declared_ids)} registered tools documented")
    orphans = sorted(set(doc_entries) - declared_ids)
    if orphans:
        fail(f"docs: catalog entries with no registered tool: {orphans}")
    else:
        ok("docs: no orphan catalog entries")
    risk_mismatch = []
    for tid, doc_risk in doc_entries.items():
        fname = id_to_file.get(tid)
        if not fname:
            continue
        # Filenames with a "/" are relative to ASSIST (Subagents/..., API/...);
        # bare filenames live in Tools/.
        fpath = (ASSIST / fname) if "/" in fname else (TOOLS_DIR / fname)
        _, risk, _ = parse_tool_file(fpath)
        if risk and risk != doc_risk:
            risk_mismatch.append(f"{tid}: doc={doc_risk} impl={risk}")
    if risk_mismatch:
        fail(f"docs: risk label mismatches: {risk_mismatch}")
    else:
        ok("docs: catalog risk labels match implementations")

    # --- 4. file_read lines -------------------------------------------
    fr = TOOLS_DIR / "AssistReadFileTool.swift"
    fr_text = fr.read_text()
    if '"lines"' in fr_text and 'input["lines"]' in fr_text:
        ok("file_read: schema declares lines and execute() handles it")
    else:
        fail("file_read: lines parameter missing from schema or execute()")

    # --- 5. Terminal exclusivity --------------------------------------
    proc_pat = re.compile(r"Process\(|ProcessRunnerTool|AgentTerminalService|AssistArgvRunner")
    shell_violations = []
    for path in sorted(TOOLS_DIR.glob("*.swift")):
        text = path.read_text()
        if proc_pat.search(text):
            if path.name not in PROCESS_ALLOWLIST:
                fail(f"terminal: {path.name} spawns processes but is not in the approval-exempt allowlist")
            # Shell-pattern check ignores //-comments (docs mention /bin/bash
            # to forbid it); only code counts.
            code = "\n".join(
                line.split("//")[0] for line in text.splitlines()
            )
            for sp in SHELL_PATTERNS:
                if re.search(sp, code):
                    shell_violations.append(f"{path.name}: shell pattern {sp}")
    if shell_violations:
        fail(f"terminal: shell-string execution in process-spawning files: {shell_violations}")
    else:
        ok("terminal: no shell-string execution (/bin/bash, /bin/sh, -lc) in Tools/")
    ok(f"terminal: process-spawning allowlist has {len(PROCESS_ALLOWLIST)} entries (explicit)")

    # --- 6. suggestedNextActions --------------------------------------
    bad_suggestions = []
    for path in sorted(TOOLS_DIR.glob("*.swift")):
        text = path.read_text()
        for m in re.finditer(r"suggestedNextActions:\s*\[([^\]]*)\]", text):
            for lit in re.findall(r'"([^"]+)"', m.group(1)):
                if lit not in declared_ids:
                    bad_suggestions.append(f"{path.name}: {lit}")
        for m in re.finditer(r"suggestedActions\.insert\(\s*\"([^\"]+)\"", text):
            if m.group(1) not in declared_ids:
                bad_suggestions.append(f"{path.name}: {m.group(1)}")
    if bad_suggestions:
        fail(f"suggestedNextActions: unregistered IDs: {bad_suggestions}")
    else:
        ok("suggestedNextActions: all suggested IDs are registered")

    # --- 7. isReadOnly honesty ----------------------------------------
    dishonest = []
    for tid, fname in id_to_file.items():
        # Filenames with a "/" are relative to ASSIST (Subagents/..., API/...);
        # bare filenames live in Tools/.
        fpath = (ASSIST / fname) if "/" in fname else (TOOLS_DIR / fname)
        _, risk, text = parse_tool_file(fpath)
        if risk != "safeRead":
            continue
        if tid in READONLY_WRITE_EXCEPTIONS:
            continue
        # Only inspect the execute() body, not the whole file.
        m = re.search(r"func execute\(.*?\n    \}", text, re.DOTALL)
        body = m.group(0) if m else text
        for mp in MUTATION_PATTERNS:
            if re.search(mp, body):
                dishonest.append(f"{tid} ({fname}): safeRead but calls {mp}")
    if dishonest:
        fail(f"readonly: {dishonest}")
    else:
        ok("readonly: no safeRead tool calls file-mutation APIs in execute()")

    print(f"\n{len(failures)} failure(s), {len(warnings)} warning(s)")
    if failures:
        return 1
    if args.strict and warnings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
