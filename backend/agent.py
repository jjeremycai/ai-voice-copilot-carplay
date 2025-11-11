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
            instructions="You are a helpful voice AI assistant for CarPlay. Keep responses concise and clear for safe driving. Answer questions directly and briefly."
        )

async def entrypoint(ctx: agents.JobContext):
    """Entry point for the LiveKit agent - using OpenAI Realtime API"""
    logger.info(f"🎙️  Agent joining room: {ctx.room.name}")

    try:
        # Use OpenAI Realtime model for direct speech-to-speech
        # This bypasses separate STT/LLM/TTS pipeline for lower latency
        realtime_model = openai.realtime.RealtimeModel(
            voice="alloy",  # OpenAI Realtime voices: alloy, echo, fable, onyx, nova, shimmer
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
            instructions="Greet the user briefly and ask how you can help them."
        )

        logger.info("✅ Realtime agent session started successfully")

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
