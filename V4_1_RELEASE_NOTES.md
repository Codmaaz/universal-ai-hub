# Universal AI Hub V4.1 — Multimodal Foundation

## Images
- Text-to-image using the OpenAI-compatible `/images/generations` shape
- Prompt, negative prompt, size and image count controls
- Multiple returned URLs are preserved in local metadata/history
- Download generated output into app storage and share the downloaded file

## Videos
- Text-to-video requests with configurable create endpoint
- Image/file-to-video input using multipart/form-data
- Configurable aspect ratio and duration
- Async job ID detection
- Configurable polling endpoint using `{id}` replacement
- Status refresh, failed/completed detection and persistent history
- In-app video preview for direct output URLs
- Download and share completed video files

## Files
- File picker for video generation input
- Missing-file validation
- Multipart upload using `input_file`

## Provider compatibility
No provider is assumed to support every capability. Video APIs differ widely.
The generic implementation is intended for endpoints compatible with the
configured JSON/multipart conventions. Provider-specific adapters should be
added for APIs with different field names, polling schemas, or upload flows.

## Storage
- Generated media remains in SQLite history
- Downloaded files are stored in the app documents directory under
  `generated_media`
- API keys remain in secure storage and are not written to media history
