## Observations
- Client connects and publishes microphone successfully; detail requests return 200 but show summary=false, turns=0 (Screens/SessionDetailScreen.swift:158–165; Services/SessionLogger.swift:174–229).
- Backend endpoint returns full transcript data from `turns` (id, session_id, timestamp, speaker, text) ordered by time (backend/server.js:737–741) and includes `session` + `summary` (backend/server.js:717–756). 
- Summary processor only runs when there are turns and `OPENAI_API_KEY` is set (backend/server.js:118–120, 289–317). With zero turns it marks `summary_status = 'failed'` (backend/server.js:136–141).
- LiveKit logs show “Unable to find handler for incoming stream: lk.transcription” opened by the agent, indicating the client lacks a handler for that stream and, more importantly, that hybrid mode likely has no ASR pipeline, so no `user_speech_committed` events.

## Likely Root Causes
1. No ASR in Hybrid mode: Selected voice is Cartesia (`cartesia/...`), which triggers hybrid mode (not OpenAI Realtime). In this path, the agent session lacks STT/ASR, so user speech isn’t transcribed and no turns are saved (backend/agent.py:299–361).
2. Summary generation blocked: If `OPENAI_API_KEY` is missing, summaries cannot be generated, even if turns arrive (backend/server.js:118–120, 122–287).
3. Metadata/session_id mismatch: If dispatch metadata didn’t include the `session_id`, `save_turn` will skip writes (backend/agent.py:223–235, 175–184). Dispatch code includes it (backend/livekit.js:205–214), but we’ll verify in logs.

## Verification Steps
1. Agent log checks
- Tail agent worker logs and verify:
  - Metadata received includes `session_id` (backend/agent.py:228–234).
  - `user_speech_committed` and `agent_speech_committed` handlers fire.
  - `save_turn()` attempts and responses (201 vs error). 
- Use the existing health endpoint to confirm LiveKit credentials: `GET /health/agent` (backend/server.js:341–421).

2. Backend checks
- Confirm `OPENAI_API_KEY` is set in Railway environment; check startup log for `⚠️ OPENAI_API_KEY not set` (backend/server.js:118–120).
- Verify that `POST /v1/sessions/:id/turns` receives writes for the session; check DB for rows in `turns`.

3. Client checks
- Ensure microphone track is published (already observed) and the app does not rely on `lk.transcription` stream; the backend will persist via agent.

## Implementation Plan
### A. Quick Unblock: Force OpenAI Realtime mode
- Temporarily select an OpenAI Realtime voice (`alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`) to enter full Realtime (audio I/O) so `user_speech_committed` fires and turns are saved (backend/server.js:447–452 determines mode).
- Re-test session → confirm turns > 0 → summary processor picks it up within 30s.

### B. Proper Fix in Hybrid Mode: Add ASR/STT
- Add an STT plugin to the agent for hybrid mode to transcribe subscribed audio and emit `user_speech_committed`. Example approach:
  - Instantiate an STT component (e.g., OpenAI/Whisper via LiveKit plugins) and pass it to `AgentSession` in hybrid mode along with LLM and TTS.
  - Ensure RoomIO subscribes to user audio and routes it through STT.
- Keep Cartesia/ElevenLabs TTS while enabling ASR for user input.

### C. Hardening & Instrumentation
- Increase agent logging around `save_turn()` (log session_id, speaker, first 80 chars, HTTP status).
- Log failure reasons from `/v1/sessions/:id/turns` (status 404 Session not found, 400 invalid data).
- Add server log breadcrumbs for summary processor decisions (turn count, key presence).

### D. Environment & Health
- Set/verify `OPENAI_API_KEY` in Railway.
- Verify `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_URL` are set; use `/health/agent` to confirm connectivity.

### E. Client UX Improvements (Optional)
- If `turns.count == 0` after end, show “No transcript received yet” tip with a retry.
- Navigation title already uses the AI title; keep focus there while processing.

## Deliverables After Approval
1. Update agent hybrid mode to include STT, subscribe to audio, and persist turns.
2. Add agent/server logging to verify end-to-end turn writes.
3. Validate with a test session; confirm turns appear and summary is generated.
4. Provide a short report with log excerpts and timestamps proving the pipeline works end-to-end.

Let me know if you want the quick unblock (Realtime voice) applied first, or proceed directly with STT integration in hybrid mode.