# Universal AI Hub V4
- Multimodal Images and Videos screens
- OpenAI-compatible image generation endpoint `/images/generations`
- Generic asynchronous video job submission with configurable endpoint
- Input file picker for image-to-video/provider-specific workflows
- Persistent local media generation history
- Provider API keys remain in secure storage
- Fixed Dio `ResponseBody` technical error extraction

## Provider compatibility
Chat compatibility does not imply image/video compatibility. Image generation currently targets the OpenAI Images API response shape. Video generation is intentionally configurable because providers use different request and async job schemas.
