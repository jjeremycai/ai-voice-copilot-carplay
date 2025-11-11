import os
import logging
from dotenv import load_dotenv
from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions
from livekit.plugins import openai

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Assistant(Agent):
    def __init__(self) -> None:
        super().__init__(
            instructions="You are a helpful voice AI assistant for CarPlay. Keep responses concise, clear, and in English for safe driving. Default to English unless the driver explicitly asks for another language."
        )

async def entrypoint(ctx: agents.JobContext):
    """Entry point for the LiveKit agent - supports both Realtime and Turn-based modes"""
    logger.info(f"🎙️  Agent joining room: {ctx.room.name}")

    # Parse metadata from dispatch
    import json
    metadata = {}
    try:
        if ctx.job.metadata:
            metadata = json.loads(ctx.job.metadata)
            logger.info(f"📋 Received metadata: {metadata}")
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

            session = AgentSession(llm=realtime_model)

            await session.start(
                room=ctx.room,
                agent=Assistant(),
                room_input_options=RoomInputOptions(),
            )

            await session.generate_reply(
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

            session = AgentSession(llm=realtime_model)

            await session.start(
                room=ctx.room,
                agent=Assistant(),
                room_input_options=RoomInputOptions(),
            )

            await session.generate_reply(
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
