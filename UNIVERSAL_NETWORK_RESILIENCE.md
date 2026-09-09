# Universal AI Hub — Network resilience

## Long answers

The chat client now defaults to a 10-minute receive timeout. This matters for reasoning models and large responses that legitimately take several minutes. The timeout remains configurable in Settings.

## Transient transport failures

The service uses the existing Retry transient failures setting (0–3), but only retries network/timeout failures before any streamed text has arrived. It does not blindly retry after a partial stream, avoiding repeated long requests and duplicate generations.

## Partial stream preservation

If a streaming connection drops after text has already arrived, the received text is saved into the conversation instead of being discarded. The user gets a concise warning that the connection dropped.

## Universal provider behavior

These changes are provider-agnostic. They apply to OpenAI-compatible gateways and the shared chat service rather than special-casing a particular vendor.
