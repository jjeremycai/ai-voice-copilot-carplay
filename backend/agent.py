import os
import logging
import aiohttp
from dotenv import load_dotenv
from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions, function_tool, RunContext
from livekit.plugins import openai

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Backend API configuration
BACKEND_URL = os.getenv('BACKEND_URL', 'https://shaw.up.railway.app')

class Assistant(Agent):
    def __init__(self, tool_calling_enabled=True, web_search_enabled=True) -> None:
        # Update instructions based on tool availability
        base_instructions = "You are a helpful voice AI assistant for CarPlay. Keep responses concise, clear, and in English for safe driving. Default to English unless the driver explicitly asks for another language."

        if tool_calling_enabled and web_search_enabled:
            instructions = base_instructions + " When users ask questions requiring current information (news, weather, traffic, events, facts), use the web_search tool."
        else:
            instructions = base_instructions + " Rely on your built-in knowledge to answer questions."

        super().__init__(instructions=instructions)

        # Store settings
        self._web_search_enabled = web_search_enabled

    @function_tool()
    async def web_search(
        self,
        context: RunContext,
        query: str,
    ) -> str:
        """Search the web for current information using Perplexity.

        Args:
            query: The search query to look up current information, news, weather, traffic, or real-time facts

        Returns:
            A concise answer based on web search results
        """
        # Check if web search is enabled
        if not self._web_search_enabled:
            return "Web search is currently disabled in your settings."

        try:
            api_key = os.getenv('PERPLEXITY_API_KEY')
            if not api_key:
                logger.error("PERPLEXITY_API_KEY not found")
                return "Search unavailable: API key not configured"

            logger.info(f"🔍 Perplexity search: {query}")

            async with aiohttp.ClientSession() as session:
                async with session.post(
                    'https://api.perplexity.ai/chat/completions',
                    headers={
                        'Authorization': f'Bearer {api_key}',
                        'Content-Type': 'application/json'
                    },
                    json={
                        'model': 'llama-3.1-sonar-small-128k-online',
                        'messages': [
                            {
                                'role': 'system',
                                'content': 'Provide concise, factual answers suitable for voice interaction while driving. Keep responses under 3 sentences for safety.'
                            },
                            {
                                'role': 'user',
                                'content': query
                            }
                        ],
                        'temperature': 0.2,
                        'max_tokens': 200,
                    },
                    timeout=aiohttp.ClientTimeout(total=10)
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        result = data['choices'][0]['message']['content']
                        logger.info(f"✅ Perplexity result: {result[:100]}...")
                        return result
                    else:
                        error_text = await response.text()
                        logger.error(f"❌ Perplexity API error: {response.status} - {error_text}")
                        return "I'm having trouble searching the web right now."
        except Exception as e:
            logger.error(f"❌ Web search error: {e}")
            return "Search is temporarily unavailable."

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

    realtime_mode = metadata.get('realtime', False)  # Backend sends true for full Realtime, false for hybrid
    voice = metadata.get('voice', 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc')
    model = metadata.get('model', 'openai/gpt-5-mini')
    tool_calling_enabled = metadata.get('tool_calling_enabled', True)
    web_search_enabled = metadata.get('web_search_enabled', True)

    logger.info(f"🔧 Tool settings - Tool calling: {tool_calling_enabled}, Web search: {web_search_enabled}")

    try:
        if realtime_mode:
            # Full OpenAI Realtime mode (audio I/O) - Pro only
            logger.info(f"🎙️  Using OpenAI Realtime (Full Audio I/O)")
            logger.info(f"📢 Realtime voice: {voice}")

            # Full Realtime model with audio input and output
            realtime_model = openai.realtime.RealtimeModel(
                voice=voice,  # OpenAI voice: alloy, echo, fable, onyx, nova, shimmer
                temperature=0.8,
                modalities=["text", "audio"],  # Full audio I/O
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
                agent=Assistant(tool_calling_enabled=tool_calling_enabled, web_search_enabled=web_search_enabled),
                room_input_options=RoomInputOptions(),
            )

            await agent_session.generate_reply(
                instructions="Greet the driver briefly in English and ask how you can help them."
            )

            logger.info("✅ Full Realtime agent session started successfully")
        else:
            # Hybrid mode: OpenAI Realtime (text-only) + separate TTS (Cartesia/ElevenLabs)
            logger.info(f"💰 Using HYBRID mode: OpenAI Realtime (text-only) + {voice}")
            logger.info(f"📢 TTS voice: {voice}")

            # Realtime model in text-only mode for speech understanding
            realtime_model = openai.realtime.RealtimeModel(
                temperature=0.8,
                modalities=["text"],  # Text-only output (no audio generation)
            )

            # AgentSession with separate TTS (Cartesia or ElevenLabs)
            agent_session = AgentSession(
                llm=realtime_model,
                tts=voice  # e.g., "cartesia/sonic-3:..." or "elevenlabs/..."
            )

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
                agent=Assistant(tool_calling_enabled=tool_calling_enabled, web_search_enabled=web_search_enabled),
                room_input_options=RoomInputOptions(),
            )

            await agent_session.generate_reply(
                instructions="Greet the driver briefly in English and ask how you can help them."
            )

            logger.info("✅ Hybrid agent session started successfully")

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
