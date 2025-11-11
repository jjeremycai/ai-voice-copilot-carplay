import os
import logging
import aiohttp
from dotenv import load_dotenv
from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions
from livekit.plugins import openai

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Backend API configuration
BACKEND_URL = os.getenv('BACKEND_URL', 'https://shaw.up.railway.app')

class Assistant(Agent):
    def __init__(self) -> None:
        super().__init__(
            instructions="You are a helpful voice AI assistant for CarPlay. Keep responses concise, clear, and in English for safe driving. Default to English unless the driver explicitly asks for another language."
        )

async def save_turn(session_id: str, speaker: str, text: str):
    """Save a conversation turn to the backend"""
    if not session_id or not text.strip():
        return

    try:
        url = f"{BACKEND_URL}/v1/sessions/{session_id}/turns"
        async with aiohttp.ClientSession() as session:
            async with session.post(
                url,
                json={
                    "speaker": speaker,
                    "text": text.strip()
                },
                headers={"Content-Type": "application/json"}
            ) as response:
                if response.status == 201:
                    logger.info(f"✅ Saved {speaker} turn for session {session_id[:20]}...")
                else:
                    error_text = await response.text()
                    logger.error(f"❌ Failed to save turn: {response.status} - {error_text}")
    except Exception as e:
        logger.error(f"❌ Error saving turn: {e}")

async def entrypoint(ctx: agents.JobContext):
    """Entry point for the LiveKit agent - supports both Realtime and Turn-based modes"""
    logger.info(f"🎙️  Agent joining room: {ctx.room.name}")

    # Parse metadata from dispatch
    import json
    metadata = {}
    session_id = None
    try:
        if ctx.job.metadata:
            metadata = json.loads(ctx.job.metadata)
            logger.info(f"📋 Received metadata: {metadata}")
            session_id = metadata.get('session_id')
            if session_id:
                logger.info(f"📝 Session ID: {session_id}")
    except Exception as e:
        logger.warning(f"Failed to parse metadata: {e}")

    realtime_mode = metadata.get('realtime', True)  # Default to realtime for now
    voice = metadata.get('voice', 'alloy')
    model = metadata.get('model', 'openai/gpt-4.1-mini')

    try:
        if realtime_mode:
            # OpenAI Realtime mode: direct speech-to-speech
            logger.info(f"🔥 Using OpenAI Realtime mode with voice: {voice}")
            realtime_model = openai.realtime.RealtimeModel(
                voice=voice,  # OpenAI Realtime voices: alloy, echo, fable, onyx, nova, shimmer
                temperature=0.8,
                modalities=["text", "audio"],
            )

            agent_session = AgentSession(llm=realtime_model)

            # Set up event handlers for transcription capture
            @agent_session.on("user_speech_committed")
            async def on_user_speech(msg: agents.llm.ChatMessage):
                if session_id and msg.content:
                    await save_turn(session_id, "user", msg.content)

            @agent_session.on("agent_speech_committed")
            async def on_agent_speech(msg: agents.llm.ChatMessage):
                if session_id and msg.content:
                    await save_turn(session_id, "assistant", msg.content)

            await agent_session.start(
                room=ctx.room,
                agent=Assistant(),
                room_input_options=RoomInputOptions(),
            )

            await agent_session.generate_reply(
                instructions="Greet the driver briefly in English and ask how you can help them."
            )

            logger.info("✅ Realtime agent session started successfully")
        else:
            # Turn-based mode: STT → LLM → TTS pipeline
            logger.info(f"🔄 Using turn-based mode with model: {model}, voice: {voice}")
            # TODO: Implement turn-based mode with separate STT/LLM/TTS
            # For now, fall back to realtime
            logger.warning("⚠️  Turn-based mode not yet implemented, using realtime")
            realtime_model = openai.realtime.RealtimeModel(
                voice="alloy",
                temperature=0.8,
                modalities=["text", "audio"],
            )

            agent_session = AgentSession(llm=realtime_model)

            # Set up event handlers for transcription capture (same as realtime mode)
            @agent_session.on("user_speech_committed")
            async def on_user_speech(msg: agents.llm.ChatMessage):
                if session_id and msg.content:
                    await save_turn(session_id, "user", msg.content)

            @agent_session.on("agent_speech_committed")
            async def on_agent_speech(msg: agents.llm.ChatMessage):
                if session_id and msg.content:
                    await save_turn(session_id, "assistant", msg.content)

            await agent_session.start(
                room=ctx.room,
                agent=Assistant(),
                room_input_options=RoomInputOptions(),
            )

            await agent_session.generate_reply(
                instructions="Greet the driver briefly in English and ask how you can help them."
            )

            logger.info("✅ Agent session started (realtime fallback)")

    except Exception as e:
        logger.error(f"❌ Agent error: {e}")
        raise

if __name__ == "__main__":
    # Start the agent worker
    agents.cli.run_app(
        agents.WorkerOptions(
            entrypoint_fnc=entrypoint,
        ),
    )
