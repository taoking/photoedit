# Batch workflow

Phase 4 batches retain only security-scoped file URLs after selection. `BatchExportQueue` opens, decodes, renders and encodes one source at a time, then drops its local asset before moving to the next job. A source failure is recorded as an item result and does not stop later jobs.

The batch adjustment source is explicit: current editor state, copied adjustments, a saved preset or a LUT. JPEG/HEIF, resize, quality, GPS preservation and filename strategy use the same `ExportSettings` model as single export. Exported files are temporary until the user shares or saves them through the system sheet; originals are never overwritten.
