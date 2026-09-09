# Universal AI Connector

The provider system is capability-first. `ProviderType.universalHttp` is a generic HTTP connector rather than a vendor integration.

## Provider configuration

Each universal provider stores:
- Base URL and authentication
- Enabled capabilities (`chat`, `imageGeneration`, `videoGeneration`, etc.)
- HTTP method per capability
- Endpoint per capability (relative or full URL)
- JSON request template per capability
- JSON response path per capability

## Request tokens

Common templates can use `{{MODEL}}`, `{{PROMPT}}`, `{{SYSTEM_PROMPT}}`, `{{MESSAGES}}`, `{{API_KEY}}`. Media templates additionally support `{{SIZE}}`, `{{N}}`, `{{NEGATIVE_PROMPT}}`, `{{ASPECT_RATIO}}`, and `{{DURATION}}`.

## Response normalization

Text, image, and video extraction accepts common shapes and can be overridden with a response path. Images support remote URLs, data URIs, standard/base64url payloads, and nested `data`/`output`/`results`/`artifacts` wrappers.

This keeps provider names out of the core media/chat UI. An API only needs to be mapped once; the same connector can be reused for another vendor with a different URL/schema.
