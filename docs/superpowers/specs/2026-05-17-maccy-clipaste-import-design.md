# Maccy and Clipaste Import Design

## Scope

This change adds a high-fidelity import path for Maccy and Clipaste clipboard history. The feature lives in Settings as an Import page, discovers installed local data sources by default, and also supports manually selected SQLite or SwiftData store files for developers who know exactly which database they want to import.

The import goal is migration quality, not text-only extraction. It should preserve every source field that can map cleanly into the current app: payload, content type, source app, timestamps, copy count, pin/favorite state, groups, Universal Clipboard marker, and diagnostic warnings. The implementation must not modify Maccy or Clipaste files.

Out of scope for this change:

- Building the full LibraryWindow.
- Importing from Paste, PasteNow, iCopy, or other apps.
- Triggering or managing Clipaste CloudKit sync.
- Copying real files referenced by file URL history records.
- Building complex historical report browsing beyond showing the latest report and writing report JSON.

## Source Evidence

The current app already has `ClipboardRecord`, `ClipboardPayload`, `HistoryStore`, `ClipboardPayloadStore`, SQLite persistence, payload files, content hash deduplication, and QuickPanel filtering. The original product spec requires Maccy and Clipaste importers to output a unified `ImportedRecord` and not make either external schema part of our long-term contract.

Local installed apps and source projects are available on this machine:

- Maccy app: `/Applications/Maccy.app`, bundle id `org.p0deje.Maccy`, version `2.6.1`.
- Maccy source: `/Users/lostsheep/programing/projects/Maccy`.
- Maccy store: `~/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite`.
- Clipaste app: `/Applications/Clipaste.app`, bundle id `com.gangz1o.clipaste`, version `2.0.3`.
- Clipaste source: `/Users/lostsheep/programing/projects/Clipaste`.
- Clipaste stores: `~/Library/Containers/com.gangz1o.clipaste/Data/Library/Application Support/com.gangz1o.clipaste/Stores/clipboard-cloud.store` and `clipboard-local.store`.

Maccy stores data in SwiftData/Core Data tables `ZHISTORYITEM` and `ZHISTORYITEMCONTENT`. `ZHISTORYITEM` contains item metadata such as timestamps, source application, title, copy count, and pin. `ZHISTORYITEMCONTENT` contains real pasteboard payloads as `ZTYPE` and `ZVALUE` rows, including text, HTML, RTF, image, file URL, source app, and Universal Clipboard marker types. Therefore the importer must not copy Clipaste's existing text-only Maccy migration approach that reads only `ZHISTORYITEM.ZTITLE`.

Clipaste stores data in `ZCLIPBOARDRECORD` and `ZCLIPBOARDGROUPMODEL`. The local store has fewer records than the cloud store on this machine, and preferences indicate iCloud sync is enabled. Automatic discovery should prefer the cloud cache when readable and fall back to the local store otherwise.

## Architecture

The import implementation is split into four layers.

### ImportSourceDiscovery

`ImportSourceDiscovery` detects available sources and produces `ImportSourceCandidate` values. It handles:

- Standard Maccy store discovery.
- Standard Clipaste cloud and local store discovery.
- Application bundle metadata lookup for version and bundle id.
- Basic readability and schema checks.
- Manual file selection classification.

For Clipaste, cloud cache is default-selected when `enable_icloud_sync = 1`, the cloud store exists, and schema validation succeeds. The local store remains visible as an optional source. If the cloud cache is missing, unreadable, or has an invalid schema, discovery selects the local store when valid.

Manual selection supports `.sqlite`, `.db`, and `.store` files. The schema determines whether a selected file is Maccy or Clipaste; the extension alone is not trusted.

### ImportSnapshotService

`ImportSnapshotService` creates a temporary read-only snapshot before parsing. It copies the selected database file and same-prefix SQLite sidecars such as `-wal` and `-shm` into a temporary directory. Parsing reads only from the snapshot.

The source apps may keep running while import happens. The import only represents a consistent snapshot near the import start time and does not chase live incremental changes. If snapshot creation fails, that source is not imported and no records from that source are written.

### ImportParser

Each source has a parser:

- `MaccyImporter`
- `ClipasteImporter`

Parsers know external schema details and emit unified `ImportedRecord` values. They do not write the current app database and do not know about Settings UI state.

Maccy parsing uses `ZHISTORYITEM` plus all related `ZHISTORYITEMCONTENT` rows. Clipaste parsing uses `ZCLIPBOARDRECORD` plus `ZCLIPBOARDGROUPMODEL` for group names.

### ImportService

`ImportService` owns dry-run, batch import, content hash deduplication, newest-time replacement, metadata merging, payload storage, cancellation, progress, and report writing.

It writes through the current app's `HistoryStore` and `ClipboardPayloadStore`. If the current storage API cannot merge or replace existing records precisely enough, implementation should add narrow import-specific capabilities rather than bypassing the store with raw SQL.

## Unified Model

The parser output is `ImportedRecord`. It is the only input accepted by the write pipeline.

Required fields:

- `source`: `maccy`, `clipasteCloud`, `clipasteLocal`, `manualMaccy`, or `manualClipaste`.
- `sourceRecordID`: external primary key or row id used for progress and failures.
- `payload`: current app `ClipboardPayload`.
- `primaryType`: current app `ClipboardContentType`.
- `pasteboardTypes`: raw pasteboard type strings when available.
- `title`: imported title or generated title.
- `plainTextPreview`: searchable preview when available.
- `sourceAppBundleId`: source application bundle id when known.
- `sourceAppName`: source application name when known.
- `createdAt`: first copied timestamp when known.
- `lastCopiedAt`: last copied timestamp when known.
- `copyCount`: source copy count, defaulting to `1`.
- `isPinned`: source pin state.
- `isFavorite`: source favorite state when available.
- `groupNames`: human-readable group names to preserve or create.
- `sourceDeviceHint`: local, universalClipboard, or imported.
- `externalContentHash`: external hash, if supplied by the source.
- `warnings`: non-fatal parse warnings.

The current app computes its own content hash from the final payload. External hashes are diagnostic only because Maccy, Clipaste, and the current app may hash different representations.

## Source Mapping

### Maccy

Read from `ZHISTORYITEM`:

- `Z_PK` -> `sourceRecordID`
- `ZFIRSTCOPIEDAT` -> `createdAt`
- `ZLASTCOPIEDAT` -> `lastCopiedAt`
- `ZNUMBEROFCOPIES` -> `copyCount`
- `ZAPPLICATION` -> source app bundle id or source app name fallback
- `ZPIN` -> `isPinned = true` when non-empty
- `ZTITLE` -> title fallback only

Read related `ZHISTORYITEMCONTENT` rows:

- `ZTYPE` -> pasteboard type
- `ZVALUE` -> raw payload bytes

Payload priority is image, rich text, file URLs, then text or link. This priority chooses the primary payload for the current app while still preserving all raw pasteboard type strings for search and diagnostics.

Special mapping:

- `com.apple.is-remote-clipboard` -> Universal Clipboard marker.
- `org.nspasteboard.source` -> source app bundle id when present.
- Text that is a single HTTP or HTTPS URL -> `primaryType = .link`.
- Unsupported pasteboard types are not fatal; they become warnings unless no supported payload can be derived.

Maccy does not have named groups. Imported Maccy records receive the `Maccy Import` group.

### Clipaste

Read from `ZCLIPBOARDRECORD`:

- `Z_PK` or `ZID` -> `sourceRecordID`
- `ZTIMESTAMP` -> `createdAt` and `lastCopiedAt`
- `ZCONTENTHASH` -> `externalContentHash`
- `ZTYPERAWVALUE` -> source content type
- `ZPLAINTEXT` -> text payload or preview
- `ZIMAGEDATA` -> image payload
- `ZIMAGEUTTYPE` -> image UTI
- `ZRTFDATA` -> rich text payload
- `ZRICHTEXTARCHIVEDATA` -> rich text diagnostic or future extension input
- `ZAPPBUNDLEID` -> source app bundle id
- `ZAPPLOCALIZEDNAME` -> source app name
- `ZGROUPID` and `ZGROUPIDSRAW` -> group ids
- `ZCUSTOMTITLE` and `ZLINKTITLE` -> title candidates
- `ZISPINNED` -> `isPinned`

Read from `ZCLIPBOARDGROUPMODEL`:

- `ZID` -> external group id
- `ZNAME` -> group name
- `ZSYSTEMICONNAME` and `ZSORTORDER` are optional metadata for future UI, not required for first import.

Clipaste original groups are preserved. Records without a group receive the `Clipaste Import` group. Clipaste `code` currently maps to `.text`, with a warning or metadata marker because the current app does not have a code content type.

## Groups

The first implementation should add a minimal group metadata capability if the current store cannot resolve group names. Storing only opaque `groupIds` without a name registry would make imported groups hard to inspect or delete later.

Group rules:

- Maccy records go into `Maccy Import`.
- Clipaste records keep original Clipaste group names.
- Clipaste records without groups go into `Clipaste Import`.
- Imported records also carry a source marker so later UI can filter by source.
- Duplicate merges union the current record groups, imported source group, and Clipaste original groups.

Group identity should be stable and deterministic. Names should be normalized for lookup but displayed with their original casing. If a group with the same normalized name already exists, reuse it.

## Deduplication And Replacement

Duplicates are detected by the current app's content hash computed from the final payload.

Rules:

- Only one final record exists for one content hash.
- Current app records, Maccy records, and Clipaste records have no source priority.
- The record with the newest `lastCopiedAt` is the canonical record.
- Older duplicates do not remain as separate records.
- Mergeable metadata from older duplicates is carried into the canonical record.

Merged metadata:

- `copyCount` is accumulated, with a defensive upper bound to prevent corrupted sources from creating unrealistic values.
- `groupIds` are unioned.
- `isPinned` and `isFavorite` are true if any duplicate has the flag.
- Universal Clipboard marker is preserved if any duplicate has it.
- Source list is added to import metadata or the import report.

Payload choice:

- Prefer the canonical newest record's payload.
- If the newest record payload is missing or unusable and an older duplicate has a valid payload, use the older payload and add a warning.
- If multiple records have the same timestamp, prefer the richer payload in this order: image, rich text, file URL, link, text.

## Batch Import And Cancellation

Import uses batch commits. A batch may be limited by record count, payload bytes, or both. The implementation should use conservative defaults so large images and RTF blobs do not create one huge transaction.

Flow:

1. Dry-run reads snapshots and computes counts, type distribution, schema status, source sizes, and estimated payload volume.
2. User confirms import.
3. Parser streams or pages records from snapshots.
4. `ImportService` stages payloads for the current batch.
5. The batch commits through the store.
6. The progress state and report counters update after each committed batch.

Cancellation:

- Already committed batches remain in the current app history.
- The current uncommitted batch is discarded.
- Failed single records remain absent from history and are recorded in the report.
- The report status is `cancelled`.
- The report includes the last processed source record id or offset, committed batch count, and final counters.

This avoids the need for a full undo journal. A rerun is safe because deduplication and newest-time replacement are deterministic.

## Reports

The latest report is shown in the Settings Import page after completion, cancellation, or failure. It is also written as JSON under:

`~/Library/Application Support/<bundle-id>/imports/reports/<timestamp>-<source>.json`

The report is not stored as a clipboard record.

Report fields:

- `id`
- `createdAt`
- `status`: `completed`, `cancelled`, or `failed`
- `sources`
- `schemaVersions`
- `counts`: scanned, imported, merged, replacedByNewest, skipped, failed
- `committedBatchCount`
- `lastProcessedSourceRecordID`
- `createdGroupIDs`
- `warnings`
- `failures`
- `duration`
- `appVersion`
- `reportSchemaVersion`

The Settings page should allow copying the report as text. First version does not need a full report history browser.

## Settings UI

Add an Import tab in Settings.

Sections:

- Automatic sources
- Manual database selection
- Preflight summary
- Progress
- Latest report

Automatic source rows show:

- Source name
- Detected app version
- Path
- Store size
- Record count
- Type distribution
- Last modified time
- Schema status
- Default selection state

Manual selection supports either separate Maccy and Clipaste buttons or a single "Select Database File" button followed by schema detection. Schema detection failure should block import and explain what was expected.

Import requires a successful preflight. The "Start Import" button remains disabled until at least one valid source is selected and preflight has completed.

## Error Handling

Source-level errors:

- Source path missing.
- Source file unreadable.
- Snapshot creation failed.
- SQLite open failed.
- Schema does not match Maccy or Clipaste.

These errors block the affected source only.

Batch-level errors:

- Current app storage unavailable.
- Payload store unavailable.
- Disk space exhausted.
- Batch commit failed.

The current batch is not committed. Already committed batches remain. The report status becomes `failed` unless the user cancellation happened first.

Record-level errors:

- Blob cannot be decoded.
- Image cannot be read as data.
- RTF is corrupt.
- File URL is invalid.
- Required source row fields are missing.

Record-level errors do not block the source. The failed row is recorded in the report with source id, type, title or preview, and reason.

## Safety

- Never write to Maccy or Clipaste stores.
- Never delete or compact source stores.
- Never trigger Clipaste CloudKit writes.
- Read source stores only through temporary snapshots.
- Store imported payload bytes in the current app's payload store, not by referencing source container files.
- File URL history stores URLs only; it does not copy the target files.
- Manual file selection must pass schema detection before preflight succeeds.

## Tests

### Unit Tests

`ImportSourceDiscoveryTests`

- Detect Maccy standard store.
- Detect Clipaste cloud and local stores.
- Prefer Clipaste cloud when sync is enabled and schema is valid.
- Fall back to local when cloud is invalid.
- Classify manual Maccy and Clipaste files by schema.
- Reject unknown SQLite files.

`ImportSnapshotServiceTests`

- Copy main database and same-prefix sidecars.
- Open snapshot read-only.
- Fail without mutating target history when snapshot fails.

`MaccyImporterTests`

- Parse text, link, RTF, image, file URL, source app, pin, copy count, and Universal Clipboard marker.
- Use `ZTITLE` only as fallback.
- Warn on unsupported pasteboard types.
- Skip rows with no supported payload.

`ClipasteImporterTests`

- Parse text, link, image, RTF, code-as-text, app metadata, pin, and groups.
- Prefer cloud source identity for cloud store candidates.
- Preserve group names through `ZCLIPBOARDGROUPMODEL`.
- Warn on missing external storage blobs.

`ImportServiceTests`

- Dry-run does not write records.
- New records are inserted.
- Duplicates use newest-time replacement.
- Groups are unioned on duplicates.
- Pin/favorite flags merge.
- Batch cancellation preserves committed batches and drops the current uncommitted batch.
- Report JSON is written.
- Rerun is idempotent.

### Integration Tests

Use small fixture databases for Maccy and Clipaste. Import into temporary SQLite store and payload directory, then verify:

- `HistoryStore.fetchPage` can see imported records.
- `ClipboardPayloadStore.loadPayload` returns valid payloads.
- QuickPanel type filtering works for imported text, link, image, file, and rich text records.
- The latest report exists and has correct counts.

### Manual Acceptance

- Automatic discovery finds installed Maccy and Clipaste.
- Clipaste cloud cache is selected by default when available.
- Manual Maccy and Clipaste file selection works.
- Maccy import preserves text, RTF, image, file URL, source app, pin, copy count, and Universal Clipboard marker where source data exists.
- Clipaste import preserves cloud records, groups, text, link, image, code-as-text, RTF, source app, and pin where source data exists.
- Reimport uses newest-time replacement and does not create duplicate history.
- Cancellation keeps already committed batches and writes a cancelled report.
- Report JSON is written under Application Support.

