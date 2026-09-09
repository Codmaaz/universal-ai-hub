# V4.2 Universal API architecture update

This update treats vendor documentation as examples, not hard-coded integrations.

## Universal HTTP API

A provider can now be configured with independent capability mappings for chat, image generation, video generation, audio, embeddings, moderation, files, and custom operations. Each mapping can define its own HTTP method, endpoint, request JSON template, and response JSON path.

Provider configuration is stored in the existing JSON data blob, so these new fields are backward-compatible with the current SQLite schema.

## Response normalization

The media layer accepts common URL/base64 wrappers and can apply a configured response path before extraction. Full endpoint URLs are accepted in addition to relative paths.

No provider is required to be named or shaped like a particular vendor. OpenAI-compatible, Anthropic, Gemini, gateways, local servers, and arbitrary REST APIs can coexist.
