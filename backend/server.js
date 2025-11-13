import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// Get the directory of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load .env file from the backend directory
const envResult = config({ path: join(__dirname, '.env') });

if (envResult.error) {
  console.warn('⚠️  Warning: Could not load .env file:', envResult.error.message);
  console.warn('   Make sure .env exists in the backend directory');
} else {
  console.log('✅ Loaded .env file successfully');
}

import express from 'express';
import cors from 'cors';
import crypto from 'crypto';
import https from 'https';
import http from 'http';
import path from 'path';
import fs from 'fs';
import OpenAI from 'openai';
import db, { usePostgres } from './database.js';
import { generateRoomName, generateLiveKitToken, getLiveKitUrl, logLiveKitConfig, dispatchAgentToRoom } from './livekit.js';
import iapRoutes from './routes/iap.js';
import { checkEntitlement, incrementFreeTierUsage, FREE_TIER_MINUTES } from './middleware/entitlementCheck.js';

// Log LiveKit configuration after env is loaded and modules are imported
logLiveKitConfig();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// IAP routes
app.use('/iap', iapRoutes);

// Serve static voice preview files
const previewsDir = path.join(__dirname, 'public', 'voice-previews');
if (fs.existsSync(previewsDir)) {
  app.use('/voice-previews', express.static(previewsDir));
  console.log(`✅ Serving voice previews from: ${previewsDir}`);
}

// Helper to conditionally await database calls
const maybeAwait = (promise) => {
  return usePostgres ? promise : promise;
};

const normalizeBoolean = (value) => {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') {
    return value === '1' || value.toLowerCase() === 'true';
  }
  return false;
};

const normalizeSession = (session) => {
  if (!session) return null;
  return {
    ...session,
    logging_enabled_snapshot: normalizeBoolean(session.logging_enabled_snapshot)
  };
};

const normalizeSummary = (summary) => {
  if (!summary) return null;

  const normalized = { ...summary };

  // Parse JSON fields
  try {
    normalized.action_items = JSON.parse(summary.action_items);
  } catch {
    normalized.action_items = [];
  }

  try {
    normalized.tags = JSON.parse(summary.tags);
  } catch {
    normalized.tags = [];
  }

  // Convert PostgreSQL timestamp to ISO8601
  // PostgreSQL returns: "2025-11-11 18:14:20"
  // Swift expects: "2025-11-11T18:14:20Z"
  if (normalized.created_at && typeof normalized.created_at === 'string') {
    normalized.created_at = normalized.created_at.replace(' ', 'T') + 'Z';
  }

  return normalized;
};

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

// Verify OpenAI API key is configured
if (!process.env.OPENAI_API_KEY) {
  console.warn('⚠️  OPENAI_API_KEY not set - summary generation will fail');
}

// Generate summary and title from transcription
async function generateSummaryAndTitle(sessionId) {
  try {
    console.log(`📝 Generating summary for session ${sessionId}`);

    // Get all turns for this session
    const stmt = db.prepare(`
      SELECT speaker, text, timestamp
      FROM turns
      WHERE session_id = ?
      ORDER BY timestamp ASC
    `);
    const turns = await stmt.all(sessionId);

    if (!turns || turns.length === 0) {
      console.log(`⚠️  No turns found for session ${sessionId} - cannot generate summary`);
      // Update status to 'failed' to prevent retries (matches SummaryStatus enum in Swift)
      const updateStmt = db.prepare('UPDATE sessions SET summary_status = ? WHERE id = ?');
      await updateStmt.run('failed', sessionId);
      return;
    }

    console.log(`📊 Found ${turns.length} turns for session ${sessionId}`);

    // Format transcript
    const transcript = turns.map(t => `${t.speaker}: ${t.text}`).join('\n');

    // Generate summary using GPT-5-nano via OpenAI API
    const summaryResponse = await openai.chat.completions.create({
      model: 'gpt-5-nano',
      messages: [
        {
          role: 'system',
          content: 'You are a helpful assistant that summarizes voice conversations. Provide a concise summary that captures the key topics, decisions, and action items discussed.'
        },
        {
          role: 'user',
          content: `Summarize this conversation:\n\n${transcript}`
        }
      ],
      max_completion_tokens: 500
    });

    const summaryText = summaryResponse.choices[0]?.message?.content;
    if (!summaryText) {
      console.error('❌ GPT-5-nano returned empty summary:', JSON.stringify(summaryResponse, null, 2));
      throw new Error('GPT-5-nano returned empty summary content');
    }

    // Extract action items
    const actionItemsResponse = await openai.chat.completions.create({
      model: 'gpt-5-nano',
      messages: [
        {
          role: 'system',
          content: 'Extract action items from the summary as a JSON array of strings. If there are no action items, return an empty array.'
        },
        {
          role: 'user',
          content: summaryText
        }
      ],
      max_completion_tokens: 200,
      response_format: { type: 'json_object' }
    });

    let actionItems = [];
    try {
      const parsed = JSON.parse(actionItemsResponse.choices[0].message.content);
      actionItems = parsed.action_items || parsed.actions || [];
    } catch (e) {
      console.warn('Failed to parse action items:', e);
    }

    // Generate title from summary
    const titleResponse = await openai.chat.completions.create({
      model: 'gpt-5-nano',
      messages: [
        {
          role: 'system',
          content: 'Generate a short, descriptive title (3-6 words) for this conversation summary. Return only the title, no quotes or extra text.'
        },
        {
          role: 'user',
          content: summaryText
        }
      ],
      max_completion_tokens: 20
    });

    const title = titleResponse.choices[0].message.content.trim().replace(/^["']|["']$/g, '');

    // Generate tags
    const tagsResponse = await openai.chat.completions.create({
      model: 'gpt-5-nano',
      messages: [
        {
          role: 'system',
          content: 'Extract 2-5 relevant topic tags from the summary as a JSON array of strings.'
        },
        {
          role: 'user',
          content: summaryText
        }
      ],
      max_completion_tokens: 100,
      response_format: { type: 'json_object' }
    });

    let tags = [];
    try {
      const parsed = JSON.parse(tagsResponse.choices[0].message.content);
      tags = parsed.tags || [];
    } catch (e) {
      console.warn('Failed to parse tags:', e);
    }

    // Save summary to database (linked to session via foreign key)
    const summaryId = crypto.randomUUID();
    const insertStmt = db.prepare(`
      INSERT INTO summaries (id, session_id, title, summary_text, action_items, tags, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ${usePostgres ? 'CURRENT_TIMESTAMP' : 'datetime(\'now\')'})
    `);

    await insertStmt.run(
      summaryId,
      sessionId,
      title,
      summaryText,
      JSON.stringify(actionItems),
      JSON.stringify(tags)
    );

    // Update session status to 'ready' - summary is now available
    const updateStmt = db.prepare('UPDATE sessions SET summary_status = ? WHERE id = ?');
    await updateStmt.run('ready', sessionId);

    console.log(`✅ Summary generated and saved for session ${sessionId}:`);
    console.log(`   Title: "${title}"`);
    console.log(`   Summary ID: ${summaryId}`);
    console.log(`   Action items: ${actionItems.length}`);
    console.log(`   Tags: ${tags.length}`);
    console.log(`   Session summary_status updated to 'ready'`);
  } catch (error) {
    console.error(`❌ Failed to generate summary for session ${sessionId}:`, error.message);
    console.error(`   Error type: ${error.constructor.name}`);
    console.error(`   Error details:`, error);
    
    // Log OpenAI API errors specifically
    if (error.response) {
      console.error(`   OpenAI API Error:`, {
        status: error.response.status,
        statusText: error.response.statusText,
        data: error.response.data
      });
    }
    
    if (error.message?.includes('model')) {
      console.error(`   ⚠️  Model-related error - check if model name is correct`);
    }

    // Mark as failed
    const updateStmt = db.prepare('UPDATE sessions SET summary_status = ? WHERE id = ?');
    await updateStmt.run('failed', sessionId);
  }
}

// Background job to process pending summaries
async function processPendingSummaries() {
  try {
    // Find sessions that are ended and need summaries
    const stmt = db.prepare(`
      SELECT id
      FROM sessions
      WHERE summary_status = 'pending'
        AND ended_at IS NOT NULL
        AND logging_enabled_snapshot = ${usePostgres ? 'true' : '1'}
      LIMIT 5
    `);
    const sessions = await stmt.all();

    if (sessions.length > 0) {
      console.log(`🔄 Processing ${sessions.length} pending summary(ies)...`);
    }

    for (const session of sessions) {
      await generateSummaryAndTitle(session.id);
    }
  } catch (error) {
    console.error('❌ Error processing pending summaries:', error);
  }
}

// Run summary processor every 30 seconds
setInterval(processPendingSummaries, 30000);

// Simple auth middleware (checks Bearer token exists)
const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    console.warn('⚠️  No auth token provided');
    return res.status(401).json({ error: 'No token provided' });
  }

  // Accept any token (device tokens start with "device_", JWT tokens are longer)
  // In production, you would validate JWT tokens properly
  console.log(`✅ Auth token accepted: ${token.substring(0, 20)}...`);
  req.userId = 'user-' + Buffer.from(token).toString('base64').slice(0, 10);
  req.deviceId = token;
  next();
};

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Agent health check
app.get('/health/agent', async (req, res) => {
  // Check if agent is configured and can connect to LiveKit
  const agentConfigured = !!(process.env.LIVEKIT_API_KEY &&
                              process.env.LIVEKIT_API_SECRET &&
                              process.env.LIVEKIT_URL);

  let agentStatus = 'unknown';
  let lastRoomActivity = null;
  let agentWorkerInfo = null;
  
  if (agentConfigured) {
    try {
      // Try to connect to LiveKit to verify credentials work
      const { RoomServiceClient, AgentDispatchClient } = await import('livekit-server-sdk');
      const apiUrl = (process.env.LIVEKIT_URL || '').replace('wss://', 'https://').replace('ws://', 'http://');
      const roomService = new RoomServiceClient(
        apiUrl,
        process.env.LIVEKIT_API_KEY,
        process.env.LIVEKIT_API_SECRET
      );
      
      const agentDispatchClient = new AgentDispatchClient(
        apiUrl,
        process.env.LIVEKIT_API_KEY,
        process.env.LIVEKIT_API_SECRET
      );
      
      // List recent rooms to verify API access works
      try {
        const rooms = await roomService.listRooms();
        agentStatus = 'livekit_connected';
        if (rooms && rooms.length > 0) {
          // Get the most recent room
          const recentRoom = rooms[0];
          lastRoomActivity = {
            room_name: recentRoom.name,
            num_participants: recentRoom.numParticipants || 0,
            created_at: recentRoom.creationTime ? new Date(recentRoom.creationTime * 1000).toISOString() : null
          };
        }
        
        // Try to list dispatches to see if agent worker is registered
        // This helps verify the agent worker is running and listening
        try {
          // List dispatches for a test room (won't create anything)
          // If this works, it means the API can communicate with LiveKit
          // Note: We can't directly check if workers are registered via API
          agentWorkerInfo = {
            note: 'Agent worker registration cannot be verified via API',
            check_logs: 'Check /tmp/agent.log for worker registration messages',
            expected_log: 'Agent worker appears to be connecting (checking logs...)',
            agent_name: process.env.LIVEKIT_AGENT_NAME || 'agent'
          };
        } catch (error) {
          // Ignore - dispatch API might not be available
        }
      } catch (error) {
        agentStatus = 'livekit_error';
        console.error('LiveKit health check error:', error.message);
      }
    } catch (error) {
      agentStatus = 'sdk_error';
      console.error('Agent health check error:', error.message);
    }
  } else {
    agentStatus = 'not_configured';
  }

  res.json({
    agent_configured: agentConfigured,
    agent_status: agentStatus,
    livekit_url: process.env.LIVEKIT_URL || null,
    last_room_activity: lastRoomActivity,
    agent_worker_info: agentWorkerInfo,
    timestamp: new Date().toISOString(),
    note: agentStatus === 'livekit_connected' 
      ? 'LiveKit API is accessible. Check agent worker logs to verify registration: tail -f /tmp/agent.log'
      : 'Check agent worker logs: tail -f /tmp/agent.log'
  });
});

// 1. POST /v1/sessions/start - Start new session
app.post('/v1/sessions/start', authenticateToken, async (req, res) => {
  try {
    const { context, model, voice, tool_calling_enabled, web_search_enabled } = req.body;

    if (!context || !['phone', 'carplay'].includes(context)) {
      return res.status(400).json({ error: 'Invalid context' });
    }

    const deviceId = req.deviceId || req.headers['x-device-id'] || req.userId;

    const entitlementCheck = await checkEntitlement(deviceId);

    if (!entitlementCheck.allowed) {
      console.log(`🚫 Session blocked for device ${deviceId.substring(0, 20)}... - ${entitlementCheck.reason}`);
      return res.status(402).json({
        error: 'ENTITLEMENT_REQUIRED',
        message: 'Subscription required. Free tier limit reached (10 min/month).',
        freeMinutesUsed: entitlementCheck.freeMinutesUsed,
        freeMinutesLimit: entitlementCheck.freeMinutesLimit
      });
    }

    // Determine mode from voice ID
    // OpenAI Realtime voices are simple names without slashes: alloy, echo, fable, onyx, nova, shimmer
    // Hybrid mode voices have provider prefix: cartesia/sonic-3:..., elevenlabs/...
    const openAIRealtimeVoices = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
    const selectedVoice = voice && typeof voice === 'string' ? voice : 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc';
    const useRealtimeMode = openAIRealtimeVoices.includes(selectedVoice);

    // Validate model if provided (optional) - only for hybrid mode (non-realtime)
    // Models use LiveKit Inference provider/model format
    // See: https://docs.livekit.io/agents/models/#inference
    const validModels = [
      // OpenAI models available through LiveKit Inference
      'openai/gpt-4.1',
      'openai/gpt-4.1-mini',
      'openai/gpt-4.1-nano',
      // Anthropic models available through LiveKit Inference
      'claude-sonnet-4-5',
      'claude-haiku-4-5',
      // Google models available through LiveKit Inference
      'google/gemini-2.5-pro',
      'google/gemini-2.5-flash-lite'
    ];

    // Pro-only models require active subscription
    const proOnlyModels = [
      'claude-sonnet-4-5',
      'google/gemini-2.5-pro'
    ];

    const selectedModel = useRealtimeMode ? null : (model && validModels.includes(model) ? model : 'openai/gpt-4.1-mini');

    // Check if user is trying to use a Pro-only model without Pro subscription
    if (selectedModel && proOnlyModels.includes(selectedModel)) {
      const hasPro = entitlementCheck.allowed && entitlementCheck.reason === 'subscription';
      if (!hasPro) {
        return res.status(403).json({
          error: 'PRO_REQUIRED',
          message: 'This model requires a Pro subscription.',
          model: selectedModel
        });
      }
    }

    const sessionId = `session-${crypto.randomUUID()}`;
    const roomName = generateRoomName();
    const participantName = `${req.userId}-${Date.now()}`;

    // Generate LiveKit token
    const livekitToken = await generateLiveKitToken(roomName, participantName);
    const livekitUrl = getLiveKitUrl();

    // Store session in database
    const stmt = db.prepare(`
      INSERT INTO sessions (id, user_id, context, started_at, logging_enabled_snapshot, summary_status, model, original_transaction_id, entitlement_checked_at)
      VALUES (?, ?, ?, ?, ${usePostgres ? 'true' : '1'}, 'pending', ?, ?, ?)
    `);
    await stmt.run(
      sessionId,
      req.userId,
      context,
      new Date().toISOString(),
      selectedModel,
      entitlementCheck.originalTransactionId || null,
      new Date().toISOString()
    );

    // Log configuration for debugging
    console.log(`Session ${sessionId} started in ${useRealtimeMode ? 'OPENAI REALTIME (Full Audio I/O)' : 'HYBRID (Realtime text-only + TTS)'} mode`);
    if (useRealtimeMode) {
      console.log(`  OpenAI Realtime voice: ${selectedVoice}`);
    } else {
      console.log(`  Model: ${selectedModel}`);
      console.log(`  TTS voice: ${selectedVoice}`);
    }

    // Dispatch agent to room with verification (runs in background, but logs verification results)
    // Verification ensures the agent actually joins before the client starts speaking
    dispatchAgentToRoom(roomName, sessionId, selectedModel, selectedVoice, useRealtimeMode, tool_calling_enabled, web_search_enabled, true)
      .then(dispatch => {
        console.log(`✅ Agent dispatch completed for session ${sessionId} - dispatch ID: ${dispatch.id}`);
      })
      .catch(error => {
        console.error(`❌ CRITICAL: Failed to dispatch agent for session ${sessionId}:`, error.message);
        console.error(`   Room: ${roomName}`);
        console.error(`   This session may not work - agent will not join the room`);
        console.error(`   Check if agent worker is running: ps aux | grep "agent.py"`);
        console.error(`   Check agent logs: tail -f /tmp/agent.log`);
      });

    res.json({
      session_id: sessionId,
      livekit_url: livekitUrl,
      livekit_token: livekitToken,
      room_name: roomName,
      mode: useRealtimeMode ? 'realtime' : 'hybrid',
      model: selectedModel || (useRealtimeMode ? 'openai-realtime' : 'openai/gpt-4.1-mini'),
      voice: selectedVoice
    });
  } catch (error) {
    console.error('Start session error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Helper function to get or initialize user subscription
function getUserSubscription(userId) {
  let subscription = db.prepare('SELECT * FROM user_subscriptions WHERE user_id = ?').get(userId);
  
  if (!subscription) {
    // Initialize with free tier
    const now = new Date();
    const billingPeriodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    const billingPeriodEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59).toISOString();
    
    db.prepare(`
      INSERT INTO user_subscriptions (user_id, subscription_tier, monthly_minutes_limit, billing_period_start, billing_period_end, updated_at)
      VALUES (?, 'free', 60, ?, ?, ?)
    `).run(userId, billingPeriodStart, billingPeriodEnd, now.toISOString());
    
    subscription = db.prepare('SELECT * FROM user_subscriptions WHERE user_id = ?').get(userId);
  }
  
  return subscription;
}

// Helper function to get current month usage
function getCurrentMonthUsage(userId) {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth() + 1; // 1-12
  
  let usage = db.prepare('SELECT * FROM monthly_usage WHERE user_id = ? AND year = ? AND month = ?')
    .get(userId, year, month);
  
  if (!usage) {
    // Initialize usage for this month
    const usageId = `usage-${crypto.randomUUID()}`;
    db.prepare(`
      INSERT INTO monthly_usage (id, user_id, year, month, used_minutes)
      VALUES (?, ?, ?, ?, 0)
    `).run(usageId, userId, year, month);
    
    usage = db.prepare('SELECT * FROM monthly_usage WHERE user_id = ? AND year = ? AND month = ?')
      .get(userId, year, month);
  }
  
  return usage;
}

// Helper function to get subscription tier limits
function getTierLimits(tier) {
  const limits = {
    'free': FREE_TIER_MINUTES, // Use the actual free tier limit
    'basic': 300,
    'pro': 1000,
    'enterprise': -1 // Unlimited
  };
  return limits[tier] || FREE_TIER_MINUTES;
}

// 2. POST /v1/sessions/end - End session
app.post('/v1/sessions/end', authenticateToken, async (req, res) => {
  try {
    const { session_id, duration_minutes } = req.body;

    if (!session_id) {
      return res.status(400).json({ error: 'Missing session_id' });
    }

    const sessionStmt = db.prepare('SELECT original_transaction_id FROM sessions WHERE id = ? AND user_id = ?');
    const session = await sessionStmt.get(session_id, req.userId);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    // Update session with end time and duration
    const updateStmt = duration_minutes !== undefined
      ? db.prepare('UPDATE sessions SET ended_at = ?, duration_minutes = ? WHERE id = ? AND user_id = ?')
      : db.prepare('UPDATE sessions SET ended_at = ? WHERE id = ? AND user_id = ?');

    const result = duration_minutes !== undefined
      ? await updateStmt.run(new Date().toISOString(), duration_minutes, session_id, req.userId)
      : await updateStmt.run(new Date().toISOString(), session_id, req.userId);

    if (result.changes === 0) {
      return res.status(404).json({ error: 'Session not found' });
    }

    if (!session.original_transaction_id && duration_minutes) {
      const deviceId = req.deviceId || req.headers['x-device-id'] || req.userId;
      await incrementFreeTierUsage(deviceId, duration_minutes);
      console.log(`📊 Free tier usage incremented: ${duration_minutes} minutes for device ${deviceId.substring(0, 20)}...`);
    }

    res.status(204).send();
  } catch (error) {
    console.error('End session error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 3. POST /v1/sessions/{id}/turns - Log conversation turn (no auth for agent)
app.post('/v1/sessions/:id/turns', (req, res) => {
  try {
    const sessionId = req.params.id;
    const { speaker, text, timestamp } = req.body;

    if (!speaker || !text || !['user', 'assistant'].includes(speaker)) {
      return res.status(400).json({ error: 'Invalid turn data' });
    }

    // Verify session exists (no user check since agent is calling this)
    const session = db.prepare('SELECT id FROM sessions WHERE id = ?')
      .get(sessionId);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    const turnId = `turn-${crypto.randomUUID()}`;
    const turnTimestamp = timestamp || new Date().toISOString();

    const stmt = db.prepare(`
      INSERT INTO turns (id, session_id, timestamp, speaker, text)
      VALUES (?, ?, ?, ?, ?)
    `);
    stmt.run(turnId, sessionId, turnTimestamp, speaker, text);

    res.status(201).json({ id: turnId });
  } catch (error) {
    console.error('Log turn error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 4. GET /v1/sessions - Fetch user's sessions
app.get('/v1/sessions', authenticateToken, async (req, res) => {
  try {
    const stmt = db.prepare(`
      SELECT
        s.id,
        COALESCE(sm.title, 'Session ' || substr(s.id, 9, 8)) as title,
        COALESCE(sm.summary_text, 'No summary available') as summary_snippet,
        s.started_at,
        s.ended_at
      FROM sessions s
      LEFT JOIN summaries sm ON s.id = sm.session_id
      WHERE s.user_id = ? AND s.logging_enabled_snapshot = ${usePostgres ? 'true' : '1'}
      ORDER BY s.started_at DESC
      LIMIT 50
    `);
    const sessions = await stmt.all(req.userId);

    res.json(sessions);
  } catch (error) {
    console.error('Fetch sessions error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 5. GET /v1/sessions/{id} - Get session details (session + summary + turns)
app.get('/v1/sessions/:id', authenticateToken, (req, res) => {
  try {
    const sessionId = req.params.id;

    const sessionRow = db.prepare(`
      SELECT * FROM sessions WHERE id = ? AND user_id = ?
    `).get(sessionId, req.userId);

    if (!sessionRow) {
      return res.status(404).json({ error: 'Session not found' });
    }
    
    const session = normalizeSession(sessionRow);

    // Fetch summary if it exists (linked via session_id foreign key)
    const summaryStmt = db.prepare('SELECT * FROM summaries WHERE session_id = ?');
    const summaryRow = summaryStmt.get(sessionId);
    const summary = normalizeSummary(summaryRow);

    // Always return turns, even if empty (linked via session_id foreign key)
    const turns = db.prepare(`
      SELECT * FROM turns WHERE session_id = ? ORDER BY timestamp ASC
    `).all(sessionId);

    console.log(`📊 Returning session ${sessionId}:`, {
      sessionFields: Object.keys(session),
      summaryStatus: session.summary_status,
      summaryExists: !!summary,
      summaryFields: summary ? Object.keys(summary) : null,
      turnsCount: turns.length,
      firstTurnFields: turns[0] ? Object.keys(turns[0]) : null
    });

    res.json({
      session,
      summary: summary || null,
      turns
    });
  } catch (error) {
    console.error('Get session error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 6. GET /v1/sessions/{id}/turns - Get conversation turns
app.get('/v1/sessions/:id/turns', authenticateToken, (req, res) => {
  try {
    const sessionId = req.params.id;

    // Verify session belongs to user
    const session = db.prepare('SELECT id FROM sessions WHERE id = ? AND user_id = ?')
      .get(sessionId, req.userId);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    const turns = db.prepare(`
      SELECT * FROM turns WHERE session_id = ? ORDER BY timestamp ASC
    `).all(sessionId);

    res.json(turns);
  } catch (error) {
    console.error('Get turns error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 7. GET /v1/sessions/{id}/summary - Get session summary
app.get('/v1/sessions/:id/summary', authenticateToken, (req, res) => {
  try {
    const sessionId = req.params.id;

    // Verify session belongs to user
    const session = db.prepare('SELECT id FROM sessions WHERE id = ? AND user_id = ?')
      .get(sessionId, req.userId);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    const summaryRow = db.prepare('SELECT * FROM summaries WHERE session_id = ?')
      .get(sessionId);

    if (!summaryRow) {
      return res.status(404).json({ error: 'Summary not found' });
    }

    const summary = normalizeSummary(summaryRow);

    res.json(summary);
  } catch (error) {
    console.error('Get summary error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 8. PUT /v1/sessions/{id}/title - Update session title
app.put('/v1/sessions/:id/title', authenticateToken, async (req, res) => {
  try {
    const sessionId = req.params.id;
    const { title } = req.body;

    if (!title || typeof title !== 'string' || title.trim().length === 0) {
      return res.status(400).json({ error: 'Invalid title' });
    }

    // Verify session belongs to user
    const sessionStmt = db.prepare('SELECT id FROM sessions WHERE id = ? AND user_id = ?');
    const session = await sessionStmt.get(sessionId, req.userId);

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    // Check if summary exists
    const summaryStmt = db.prepare('SELECT id FROM summaries WHERE session_id = ?');
    const summary = await summaryStmt.get(sessionId);

    if (!summary) {
      return res.status(404).json({ error: 'Summary not found for this session' });
    }

    // Update title
    const updateStmt = db.prepare('UPDATE summaries SET title = ? WHERE session_id = ?');
    await updateStmt.run(title.trim(), sessionId);

    res.json({ title: title.trim() });
  } catch (error) {
    console.error('Update title error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 9. DELETE /v1/sessions/{id} - Delete session
app.delete('/v1/sessions/:id', authenticateToken, (req, res) => {
  try {
    const sessionId = req.params.id;

    const stmt = db.prepare('DELETE FROM sessions WHERE id = ? AND user_id = ?');
    const result = stmt.run(sessionId, req.userId);

    if (result.changes === 0) {
      return res.status(404).json({ error: 'Session not found' });
    }

    res.status(204).send();
  } catch (error) {
    console.error('Delete session error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 9. POST /v1/auth/login - Simple login (returns mock token)
app.post('/v1/auth/login', (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Missing credentials' });
    }

    // Mock auth - in production, validate against real user database
    const token = Buffer.from(`${email}:${Date.now()}`).toString('base64');
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(); // 24 hours

    res.json({
      token,
      expires_at: expiresAt
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 10. POST /v1/auth/refresh - Refresh auth token
app.post('/v1/auth/refresh', authenticateToken, (req, res) => {
  try {
    // Generate new token
    const token = Buffer.from(`${req.userId}:${Date.now()}`).toString('base64');
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

    res.json({
      user_id: req.userId,
      token,
      expires_at: expiresAt
    });
  } catch (error) {
    console.error('Refresh token error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 11. GET /v1/usage/credits - Check remaining credits
app.get('/v1/usage/credits', authenticateToken, (req, res) => {
  try {
    const subscription = getUserSubscription(req.userId);
    const usage = getCurrentMonthUsage(req.userId);
    const monthlyLimit = getTierLimits(subscription.subscription_tier);
    
    const usedMinutes = usage.used_minutes || 0;
    const hasCredits = monthlyLimit === -1 || usedMinutes < monthlyLimit;
    const remainingMinutes = monthlyLimit === -1 ? null : Math.max(0, monthlyLimit - usedMinutes);
    
    res.json({
      has_credits: hasCredits,
      remaining_minutes: remainingMinutes,
      monthly_limit: monthlyLimit === -1 ? null : monthlyLimit,
      used_minutes: usedMinutes,
      subscription_tier: subscription.subscription_tier
    });
  } catch (error) {
    console.error('Check credits error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 12. POST /v1/usage/report - Report usage for a session
app.post('/v1/usage/report', authenticateToken, (req, res) => {
  try {
    const { session_id, minutes } = req.body;
    
    if (!session_id || minutes === undefined) {
      return res.status(400).json({ error: 'Missing session_id or minutes' });
    }
    
    // Verify session belongs to user
    const session = db.prepare('SELECT id FROM sessions WHERE id = ? AND user_id = ?')
      .get(session_id, req.userId);
    
    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }
    
    // Get current month usage
    const usage = getCurrentMonthUsage(req.userId);
    
    // Update usage
    const updateStmt = db.prepare(`
      UPDATE monthly_usage 
      SET used_minutes = used_minutes + ? 
      WHERE id = ?
    `);
    updateStmt.run(minutes, usage.id);
    
    res.status(204).send();
  } catch (error) {
    console.error('Report usage error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 13. GET /v1/usage/stats - Get usage statistics
app.get('/v1/usage/stats', authenticateToken, (req, res) => {
  try {
    const subscription = getUserSubscription(req.userId);
    const usage = getCurrentMonthUsage(req.userId);
    const monthlyLimit = getTierLimits(subscription.subscription_tier);
    
    const usedMinutes = usage.used_minutes || 0;
    const remainingMinutes = monthlyLimit === -1 ? null : Math.max(0, monthlyLimit - usedMinutes);
    
    res.json({
      used_minutes: usedMinutes,
      remaining_minutes: remainingMinutes,
      monthly_limit: monthlyLimit === -1 ? null : monthlyLimit,
      subscription_tier: subscription.subscription_tier,
      billing_period_start: subscription.billing_period_start,
      billing_period_end: subscription.billing_period_end
    });
  } catch (error) {
    console.error('Get usage stats error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 14. GET /v1/voice-preview/:voiceId - Get pre-generated voice preview audio
// Voice previews are pre-generated and stored as static files
// Use the generate-voice-previews.js script to create them
app.get('/v1/voice-preview/:voiceId', (req, res) => {
  try {
    const { voiceId } = req.params;
    
    // Determine file extension based on voice ID prefix
    const extension = voiceId.startsWith('cartesia-') ? 'm4a' : 'mp3';
    const filePath = path.join(previewsDir, `${voiceId}.${extension}`);
    
    // Check if file exists
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ 
        error: 'Preview not found',
        message: `Voice preview for ${voiceId} not found. Run generate-voice-previews.js script to generate previews.`
      });
    }
    
    // Determine content type
    const contentType = extension === 'm4a' ? 'audio/mp4' : 'audio/mpeg';
    const stats = fs.statSync(filePath);
    
    // Set headers and send file
    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Length', stats.size);
    res.setHeader('Cache-Control', 'public, max-age=31536000'); // Cache for 1 year
    res.setHeader('Accept-Ranges', 'bytes');
    
    const fileStream = fs.createReadStream(filePath);
    fileStream.pipe(res);
    
  } catch (error) {
    console.error('Voice preview error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Error handling
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Validate LiveKit configuration before starting server
const validateLiveKitConfig = () => {
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;
  const url = process.env.LIVEKIT_URL;
  
  console.log('\n🔍 LiveKit Configuration Check:');
  console.log(`   API Key: ${apiKey ? `${apiKey.slice(0, 6)}...` : '❌ NOT SET'}`);
  console.log(`   API Secret: ${apiSecret ? '✅ SET' : '❌ NOT SET'}`);
  console.log(`   URL: ${url || '❌ NOT SET'}`);
  
  if (!apiKey || !apiSecret || !url) {
    console.error('\n❌ ERROR: LiveKit credentials are not fully configured!');
    console.error('   Please check your .env file in the backend directory.');
    console.error('   Required variables: LIVEKIT_API_KEY, LIVEKIT_API_SECRET, LIVEKIT_URL');
    return false;
  }
  
  console.log('✅ LiveKit configuration is valid\n');
  return true;
};

// Start server
if (validateLiveKitConfig()) {
  app.listen(PORT, () => {
    console.log(`🚀 Server running on http://localhost:${PORT}`);
    console.log(`📊 Database: ${db.name}`);
    console.log(`🎙️  LiveKit URL: ${process.env.LIVEKIT_URL}`);
  });
} else {
  console.error('\n❌ Server startup aborted due to missing LiveKit configuration.');
  console.error('   Fix your .env file and restart the server.');
  process.exit(1);
}
