---
id: 11111111-1111-1111-1111-111111110002
author: Database Specialist
version: 1.0.0
tags: coredata, database, storage
recommendedTools: read_file, edit_file
guidance: Perform all database changes inside backgroundContext.perform blocks; pass NSManagedObjectID
---
# CoreData Thread Safety

Ensure background contexts and main queue context never cause data race exceptions.

## Guidelines
- Never pass NSManagedObject instances across thread boundaries.
- Retrieve local objects inside background threads using standard NSManagedObjectID lookups.
- Synchronize main and background persistent store contexts using automaticallyMergesChangesFromParent.
