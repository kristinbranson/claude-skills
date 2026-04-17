---
name: harvard-dataverse
description: Upload and manage datasets on Harvard Dataverse. Use when the user wants to upload data, create datasets, or manage files on Harvard Dataverse.
argument-hint: "[action: upload|create-dataset|list-files|delete-file|status]"
---

# Harvard Dataverse Skill

Help the user upload and manage datasets on Harvard Dataverse (https://dataverse.harvard.edu).

## Authentication

- API token location: `/groups/branson/home/bransonk/Documents/KristinAPIKey_HarvardDataverse.txt`
- Header for all API calls: `X-Dataverse-key: <token>`
- Always use curl (not Python urllib) for API calls — urllib gets 403 errors that curl doesn't.

## Key Constraints

- **2.5 GB per-file hard limit** — applies to web UI, regular API, AND S3 direct upload
- **Regular add API auto-unzips .zip files** — use S3 direct upload to keep zips intact
- **~6-10 sec API overhead per file** — for large datasets with many small files, package into per-directory zips first
- **Newly created datasets may need a few seconds** before API calls work reliably

## API Endpoints

### Create Dataset
```bash
curl -s -H "X-Dataverse-key:$TOKEN" -X POST \
  "https://dataverse.harvard.edu/api/dataverses/harvard/datasets" \
  -H "Content-Type: application/json" -d @dataset.json
```
Returns: `data.id` (numeric ID) and `data.persistentId` (DOI like `doi:10.7910/DVN/XXXXX`).

### List Files (paginated)
```bash
curl -s -o /tmp/dv_files.json -H "X-Dataverse-key:$TOKEN" \
  "https://dataverse.harvard.edu/api/datasets/:persistentId/versions/:latest/files?persistentId=$DOI&start=0&limit=100"
```

### Delete File
```bash
curl -s -H "X-Dataverse-key:$TOKEN" -X DELETE \
  "https://dataverse.harvard.edu/api/files/$FILE_ID"
```

### Delete Draft Dataset
```bash
curl -s -H "X-Dataverse-key:$TOKEN" -X DELETE \
  "https://dataverse.harvard.edu/api/datasets/$DATASET_ID/destroy"
```

## S3 Direct Upload (keeps zips intact, no auto-unzip)

Use this for .zip files or any file where you don't want Dataverse to modify it.

### Step 1: Get presigned upload URL
```bash
curl -s -H "X-Dataverse-key:$TOKEN" \
  "https://dataverse.harvard.edu/api/datasets/:persistentId/uploadurls?persistentId=$DOI&size=$FILESIZE"
```
Returns: `data.url` (presigned S3 URL), `data.storageIdentifier`

### Step 2: Upload to S3
```bash
curl -s -X PUT -H "x-amz-tagging: dv-state=temp" \
  --upload-file "$FILEPATH" "$UPLOAD_URL"
```

### Step 3: Compute SHA-256 checksum
```bash
sha256sum "$FILEPATH"
```

### Step 4: Register file with dataset
```bash
curl -s -H "X-Dataverse-key:$TOKEN" -X POST \
  "https://dataverse.harvard.edu/api/datasets/:persistentId/add?persistentId=$DOI" \
  -F "jsonData={\"storageIdentifier\":\"$STORAGE_ID\",\"fileName\":\"$FILENAME\",\"mimeType\":\"application/zip\",\"directoryLabel\":\"$DIR_LABEL\",\"checksum\":{\"@type\":\"SHA-256\",\"@value\":\"$SHA256\"}}"
```

## Regular Direct Upload (auto-unzips .zip files!)

Only use for non-zip files or when you WANT Dataverse to unzip:
```bash
curl -s -H "X-Dataverse-key:$TOKEN" -X POST \
  "https://dataverse.harvard.edu/api/datasets/:persistentId/add?persistentId=$DOI" \
  -F "file=@$FILEPATH" \
  -F "jsonData={\"directoryLabel\":\"$DIR_LABEL\"}" \
  --max-time 600
```

## Upload Strategy

1. **< 100 files, all < 2.5 GB**: Regular direct upload is fine
2. **Many small files (1000+)**: Package into per-directory zips, use S3 direct upload
   - 22K files × 10 sec = 60+ hours vs 165 zips × 8 sec = 22 min
3. **Files > 2.5 GB**: Must split into smaller pieces; no workaround
4. **Always build resumable upload scripts**: Track uploaded files in a JSON progress file

## Upload Script Pattern

When writing upload scripts:
- Use Python 3 with subprocess calling curl (not urllib)
- Track progress in a JSON file (list of uploaded relative paths)
- Save progress after every successful upload
- Use S3 direct upload for .zip files, regular upload for everything else
- Log to a file with timestamps
- Continue on error, report failures at end
- Run in background with `run_in_background=true`

## Dataset JSON Template

```json
{
  "datasetVersion": {
    "license": {"name": "CC BY 4.0", "uri": "https://creativecommons.org/licenses/by/4.0/"},
    "metadataBlocks": {
      "citation": {
        "fields": [
          {"typeName": "title", "value": "TITLE"},
          {"typeName": "author", "multiple": true, "typeClass": "compound", "value": [
            {"authorName": {"value": "Last, First"}, "authorAffiliation": {"value": "AFFILIATION"}}
          ]},
          {"typeName": "datasetContact", "multiple": true, "typeClass": "compound", "value": [
            {"datasetContactName": {"value": "Last, First"}, "datasetContactEmail": {"value": "EMAIL"}}
          ]},
          {"typeName": "dsDescription", "multiple": true, "typeClass": "compound", "value": [
            {"dsDescriptionValue": {"value": "DESCRIPTION"}}
          ]},
          {"typeName": "subject", "multiple": true, "typeClass": "controlledVocabulary",
           "value": ["Medicine, Health and Life Sciences"]},
          {"typeName": "keyword", "multiple": true, "typeClass": "compound", "value": [
            {"keywordValue": {"value": "keyword1"}}
          ]}
        ]
      }
    }
  }
}
```

## Download Script Pattern

For datasets stored as zips, include a `download_dataset.py` that:
1. Lists files via `/api/datasets/:persistentId/versions/:latest-published/files` (paginated)
2. Downloads each via `/api/access/datafile/{id}` (no auth needed for published datasets)
3. Extracts zips and deletes them to save disk space
4. Uses `.done` marker files for resumability
5. Requires only Python 3.6+ stdlib — no pip packages

## Existing Datasets

- **NCF FlyBowl Data**: `doi:10.7910/DVN/KEEJ4A` (ID 13452322)
  - 165 files (~85 GB zipped, ~108 GB unzipped)
  - Upload script: `/nrs/branson/upload_zips.py`
  - Zips: `/nrs/branson/NCF_FlyBowlData_zips/`
  - Source data: `/nrs/branson/NCF_FlyBowlData/`
