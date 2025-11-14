## Overview
- Goal: Resolve failures where TTS voices (Cartesia/ElevenLabs) in the Hybrid path and OpenAI Realtime path do not result in agents joining LiveKit rooms, and restore end-to-end transcription and summaries.
- Scope covers: Room creation and join, URL/auth correctness, audio pipeline on agent, transcription persistence, log-based debugging, and preventive monitoring.

## Current Architecture
- Backend issues LiveKit join credentials and dispatches an agent worker:
  - Token minting and grants in `backend/livekit.js:61-75`.
  - Session start returns `livekit_url`, `livekit_token`, `room_name` in `backend/server.js:523-531`.
  - Agent dispatch and join verification in `backend/livekit.js:246-273`.
  - Agent worker connects via LiveKit Agents SDK and starts `AgentSession` in `backend/agent.py:266-276` (Realtime) and `backend/agent.py:336-340` (Hybrid).
- Transcription storage and summary generation:
  - Turns stored via `/v1/sessions/:id/turns` in `backend/server.js:636-668`.
  - Summary pipeline in `backend/server.js:111-250` with background job `processPendingSummaries()` at `backend/server.js:279-306`.

## Sequence Diagrams
- Successful Realtime (OpenAI)
  1) Client → Backend `/v1/sessions/start` → returns URL/token/room
  2) Backend → LiveKit Dispatch (OpenAI voice) → Agent Worker receives job
  3) Worker → `AgentSession(llm=openai.realtime.RealtimeModel)` → joins room
  4) RoomIO auto-subscribes, emits speech events → Backend `/turns`
  5) Backend summarizes after session end
- Successful Hybrid (Cartesia/ElevenLabs)
  1) Client → Backend `/v1/sessions/start` with `voice=cartesia/...` or `elevenlabs/...`
  2) Backend → LiveKit Dispatch (metadata carries `model`, `voice`) → Worker receives
  3) Worker → `AgentSession(llm=<inference string>, tts=<plugin or descriptor>)` → joins room
  4) RoomIO auto-subscribes; commit events → Backend `/turns`
  5) Summaries pipeline runs
- Failed Workflow (observed)
  - Dispatch created → Agent does not join → `verifyAgentJoined` logs no participants; no `/turns`; summaries stay `pending` or fail.

## Findings (Root Causes)
- LiveKit REST vs WebSocket URL mismatch for server-side SDK calls:
  - `RoomServiceClient` and `AgentDispatchClient` used with `LIVEKIT_URL` as `wss://...` in `backend/livekit.js:198-205` and `backend/livekit.js:103-122`.
  - Working test path converts `wss://`→`https://` (`backend/test-dispatch.js:13`). Without conversion, REST calls may fail silently or time out.
- Invalid/default LLM model strings on Hybrid path:
  - Defaults like `openai/gpt-5-nano` (dispatch metadata `backend/livekit.js:201-209`) and `openai/gpt-5-mini` (worker `backend/agent.py:231-235`) are not in `validModels` and likely unsupported by LiveKit Inference, causing `AgentSession.start()` to fail.
- Potential agent name mismatch between dispatch and worker:
  - Dispatch uses agent name `'agent'` (`backend/livekit.js:214-218`), while worker allows env override `LIVEKIT_AGENT_NAME` (`backend/agent.py:383-393`). Cloud workers often use a different name; mismatch prevents job pickup.
- Transcription failures are secondary effects of agent not joining:
  - Commit event handlers correctly push turns (`backend/agent.py:256-265`, `backend/agent.py:320-329`), but if session never starts, no turns are emitted; summaries cannot run.

## Fixes (Design)
- URL Scheme Correction for Server SDK calls
  - Add `getLiveKitApiUrl()` that transforms `wss://`→`https://` and `ws://`→`http://` for REST clients.
  - Use API URL for `RoomServiceClient` and `AgentDispatchClient` while continuing to return `wss://` to clients.
- Model Consistency and Validation
  - Replace default Hybrid LLM with a valid LiveKit Inference model (e.g., `openai/gpt-4.1-mini`).
  - Align model names across backend dispatch metadata and agent worker defaults.
- Agent Name Alignment
  - Read `LIVEKIT_AGENT_NAME` on the server and pass it to dispatch; or have server-side dispatch use the same env that worker reads.
- Transcription & Summary Reliability
  - Once join succeeds, turns will populate. Keep existing summary job; ensure model names for summaries are valid or switch to a reliable summarizer.

## Specific Code Changes Required
- `backend/livekit.js`
  - Introduce API URL helper and use it:
    - Add `function getLiveKitApiUrl() { const url = getLiveKitUrl(); return url.replace('wss://','https://').replace('ws://','http://'); }` near `getLiveKitUrl()`.
    - Replace `new RoomServiceClient(url, ...)` with `new RoomServiceClient(getLiveKitApiUrl(), ...)` in `backend/livekit.js:103`.
    - Replace `new AgentDispatchClient(url, ...)` with `new AgentDispatchClient(getLiveKitApiUrl(), ...)` in `backend/livekit.js:198`.
  - Use env-driven agent name:
    - Read `process.env.LIVEKIT_AGENT_NAME || 'agent'` and use in `createDispatch(roomName, agentName, ...)` at `backend/livekit.js:214-218`.
  - Metadata defaults:
    - Change `model` default from `openai/gpt-5-nano` to `openai/gpt-4.1-mini` at `backend/livekit.js:201-209`.
- `backend/server.js`
  - Keep `validModels` list; set Hybrid default to a valid model:
    - Ensure `selectedModel` default resolves to `openai/gpt-4.1-mini` when Hybrid at `backend/server.js:463-475`.
  - Maintain response consistency with chosen model at `backend/server.js:529-531`.
- `backend/agent.py`
  - Align default Hybrid model: change `model = metadata.get('model', 'openai/gpt-4.1-mini')` at `backend/agent.py:231-235` and corresponding `llm_model = model or 'openai/gpt-4.1-mini'` at `backend/agent.py:301-305`.
  - Optional: add ElevenLabs plugin support if available in `livekit.plugins` (leave current Inference fallback in place). No change required for Cartesia plugin path.

## Testing Procedures
- Room Creation & Join
  - Start backend; hit `/health/agent` to confirm LiveKit API connectivity (`backend/server.js:331-409`).
  - Realtime path: POST `/v1/sessions/start` with `voice='alloy'`. Expect join verification success in logs and one participant in room.
  - Hybrid path: POST `/v1/sessions/start` with `voice='cartesia/sonic-3:<id>'` and default model. Expect agent to join within ~7.5s (`backend/livekit.js:255-267`).
- Audio Pipeline & WebRTC
  - Join via client using returned `livekit_token`/`livekit_url`. Confirm audio from agent.
  - Use LiveKit Console to view tracks; check ICE gathering/completion.
- Transcription
  - During calls, verify turns are created via `GET /v1/sessions/:id/turns` (`backend/server.js:740-762`).
  - End session and observe summaries transition from `pending`→`ready`.
- Logs and Network
  - Compare dispatch logs before/after changes; ensure REST URL shows `https://...` for server SDK, and participant identities are listed by `verifyAgentJoined()`.

## Monitoring Improvements
- Keep `/health/agent` and add join/dispatch counters in logs.
- Alert on repeated "Agent dispatch succeeded but agent did not join" occurrences (`backend/livekit.js:257-266`).

## Architecture Diagram (Text)
- Backend → LiveKit REST (https) for dispatch, verification.
- Client → LiveKit WS (wss) using minted token.
- Agent Worker → LiveKit Agents (worker → room join, RoomIO auto-subscribe/publish).
- Agent → Backend `/turns` for transcripts; Backend → OpenAI summaries.

## Sequence Differences (Success vs Failure)
- Success: Dispatch (https) → Worker receives → `AgentSession.start()` succeeds (valid model) → Participant appears → Events emit → `/turns` fills.
- Failure: Dispatch uses `wss` (REST mismatch) OR invalid model → `AgentSession.start()` raises → No participant → No `/turns`.

## Implementation Notes
- No changes to JWT grants (`backend/livekit.js:66-72`); permissions already correct.
- Keep `wss://` in what the backend returns to the client; only server SDK switches to `https://`.
- Ensure `LIVEKIT_AGENT_NAME` is consistent across server and worker; document env requirement.

## Deliverables
- Updated server and worker code per above references.
- Verified E2E tests for both Realtime and Hybrid flows.
- Documentation update noting proper URL schemes and supported models list.
