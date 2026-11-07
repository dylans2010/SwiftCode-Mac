# Finalization Worker Dispatch

## Mission
Execute the finalization steps for the entire project session immediately:
1. Ensure all 10 mandated audit reports are present, complete, and finalized in the repository root (`/Users/dylan/Downloads/SwiftCode/`):
   - `MIGRATION_TRACKER.md`
   - `LEGACY_FEATURE_PARITY_AUDIT.md`
   - `IMPORT_AND_MODULE_AUDIT.md`
   - `REBRANDING_AND_IMPORT_REGRESSION_AUDIT.md`
   - `ASSIST_MIGRATION_AUDIT.md`
   - `PROJECT_INTEGRATION_AUDIT.md`
   - `REGRESSION_AUDIT.md`
   - `FILE_ROUTING_AUDIT.md`
   - `TOOLS_DRAWER_AUDIT.md`
   - `FINAL_MIGRATION_REPORT.md`
   If any of these 10 is missing or incomplete, generate it immediately.
2. Run `python3 -I tools/check_comment_policy.py --all` to verify 0 comment policy violations across the entire repository.
3. Verify `cd swiftcode && swift build` succeeds cleanly across all targets.
4. Stage all changes with `git add -A`, commit with descriptive commit message, and push:
   `git add -A && git commit -m "Migrate missing features from SwiftCode-Legacy, Assist realignment, comment removal, and V2 roadmap" && git push origin HEAD`
5. Write your handoff report to `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_finalizer/handoff.md` with full terminal outputs and status.

## Working Directory
/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_finalizer/
