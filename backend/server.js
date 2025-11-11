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

// Log LiveKit configuration after env is loaded and modules are imported
logLiveKitConfig();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

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

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

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
      console.log(`⚠️  No turns found for session ${sessionId}`);
      return;
    }

    // Format transcript
    const transcript = turns.map(t => `${t.speaker}: ${t.text}`).join('\n');

    // Generate summary using GPT-4
    const summaryResponse = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
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
      temperature: 0.3,
      max_tokens: 500
    });

    const summaryText = summaryResponse.choices[0].message.content;

    // Extract action items
    const actionItemsResponse = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
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
      temperature: 0.2,
      max_tokens: 200,
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
      model: 'gpt-4o-mini',
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
      temperature: 0.5,
      max_tokens: 20
    });

    const title = titleResponse.choices[0].message.content.trim().replace(/^["']|["']$/g, '');

    // Generate tags
    const tagsResponse = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
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
      temperature: 0.3,
      max_tokens: 100,
      response_format: { type: 'json_object' }
    });

    let tags = [];
    try {
      const parsed = JSON.parse(tagsResponse.choices[0].message.content);
      tags = parsed.tags || [];
    } catch (e) {
      console.warn('Failed to parse tags:', e);
    }

    // Save summary to database
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

    // Update session status
    const updateStmt = db.prepare('UPDATE sessions SET summary_status = ? WHERE id = ?');
    await updateStmt.run('ready', sessionId);

    console.log(`✅ Summary generated for session ${sessionId}: "${title}"`);
  } catch (error) {
    console.error(`❌ Failed to generate summary for session ${sessionId}:`, error);

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

    for (const session of sessions) {
      await generateSummaryAndTitle(session.id);
    }
  } catch (error) {
    console.error('Error processing pending summaries:', error);
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
  next();
};

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Agent health check
app.get('/health/agent', (req, res) => {
  // Simple endpoint to verify agent is running
  // The agent runs in a separate process, so we can't directly check it
  // Instead, we return the LiveKit config which the agent needs
  const agentConfigured = !!(process.env.LIVEKIT_API_KEY &&
                              process.env.LIVEKIT_API_SECRET &&
                              process.env.LIVEKIT_URL);

  res.json({
    agent_configured: agentConfigured,
    livekit_url: process.env.LIVEKIT_URL || null,
    timestamp: new Date().toISOString()
  });
});

// 1. POST /v1/sessions/start - Start new session
app.post('/v1/sessions/start', authenticateToken, async (req, res) => {
  try {
    const { context, model, voice, realtime } = req.body;

    if (!context || !['phone', 'carplay'].includes(context)) {
      return res.status(400).json({ error: 'Invalid context' });
    }

    const useRealtimeMode = realtime === true;

    // Validate model if provided (optional) - only for turn-based mode
    // Models use LiveKit Inference provider/model format
    // See: https://docs.livekit.io/agents/models/#inference
    const validModels = [
      // OpenAI models available through LiveKit Inference
      'openai/gpt-4.1',
      'openai/gpt-4.1-mini',
      'openai/gpt-4.1-nano',
      // Google models available through LiveKit Inference
      'google/gemini-2.5-pro',
      'google/gemini-2.5-flash-lite'
    ];

    const selectedModel = !useRealtimeMode && model && validModels.includes(model) ? model : null;

    // Handle voice selection based on mode
    let selectedVoice;
    if (useRealtimeMode) {
      // OpenAI Realtime voices: alloy, echo, fable, onyx, nova, shimmer
      const realtimeVoices = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
      selectedVoice = voice && realtimeVoices.includes(voice) ? voice : 'alloy';
    } else {
      // Turn-based mode: Cartesia or ElevenLabs
      const defaultTTS = 'cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc';
      selectedVoice = voice && typeof voice === 'string' ? voice : defaultTTS;
    }

    const sessionId = `session-${crypto.randomUUID()}`;
    const roomName = generateRoomName();
    const participantName = `${req.userId}-${Date.now()}`;

    // Generate LiveKit token
    const livekitToken = await generateLiveKitToken(roomName, participantName);
    const livekitUrl = getLiveKitUrl();

    // Store session in database
    const stmt = db.prepare(`
      INSERT INTO sessions (id, user_id, context, started_at, logging_enabled_snapshot, summary_status, model)
      VALUES (?, ?, ?, ?, ${usePostgres ? 'true' : '1'}, 'pending', ?)
    `);
    await stmt.run(sessionId, req.userId, context, new Date().toISOString(), selectedModel);

    // Log configuration for debugging
    console.log(`Session ${sessionId} started in ${useRealtimeMode ? 'REALTIME' : 'TURN-BASED'} mode`);
    if (useRealtimeMode) {
      console.log(`  OpenAI Realtime voice: ${selectedVoice}`);
    } else {
      console.log(`  Model: ${selectedModel || 'default'}`);
      console.log(`  TTS voice: ${selectedVoice}`);
    }

    // Dispatch agent to room (don't wait for it, run in background)
    dispatchAgentToRoom(roomName, selectedModel, selectedVoice, useRealtimeMode).catch(error => {
      console.error(`Failed to dispatch agent for session ${sessionId}:`, error.message);
    });

    res.json({
      session_id: sessionId,
      livekit_url: livekitUrl,
      livekit_token: livekitToken,
      room_name: roomName,
      realtime: useRealtimeMode,
      model: selectedModel || (useRealtimeMode ? 'openai-realtime' : 'default'),
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
    'free': 60,
    'basic': 300,
    'pro': 1000,
    'enterprise': -1 // Unlimited
  };
  return limits[tier] || 60;
}

// 2. POST /v1/sessions/end - End session
app.post('/v1/sessions/end', authenticateToken, (req, res) => {
  try {
    const { session_id, duration_minutes } = req.body;

    if (!session_id) {
      return res.status(400).json({ error: 'Missing session_id' });
    }

    // Update session with end time and duration
    const updateStmt = duration_minutes !== undefined
      ? db.prepare('UPDATE sessions SET ended_at = ?, duration_minutes = ? WHERE id = ? AND user_id = ?')
      : db.prepare('UPDATE sessions SET ended_at = ? WHERE id = ? AND user_id = ?');
    
    const result = duration_minutes !== undefined
      ? updateStmt.run(new Date().toISOString(), duration_minutes, session_id, req.userId)
      : updateStmt.run(new Date().toISOString(), session_id, req.userId);

    if (result.changes === 0) {
      return res.status(404).json({ error: 'Session not found' });
    }

    res.status(204).send();
  } catch (error) {
    console.error('End session error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 3. POST /v1/sessions/{id}/turns - Log conversation turn
app.post('/v1/sessions/:id/turns', authenticateToken, (req, res) => {
  try {
    const sessionId = req.params.id;
    const { speaker, text, timestamp } = req.body;

    if (!speaker || !text || !['user', 'assistant'].includes(speaker)) {
      return res.status(400).json({ error: 'Invalid turn data' });
    }

    // Verify session belongs to user
    const session = db.prepare('SELECT id FROM sessions WHERE id = ? AND user_id = ?')
      .get(sessionId, req.userId);

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

    // Fetch summary if it exists
    const summaryStmt = db.prepare('SELECT * FROM summaries WHERE session_id = ?');
    const summary = summaryStmt.get(sessionId);

    if (summary) {
      try {
        summary.action_items = JSON.parse(summary.action_items);
      } catch {
        summary.action_items = [];
      }

      try {
        summary.tags = JSON.parse(summary.tags);
      } catch {
        summary.tags = [];
      }
    }

    // Always return turns, even if empty
    const turns = db.prepare(`
      SELECT * FROM turns WHERE session_id = ? ORDER BY timestamp ASC
    `).all(sessionId);

    console.log(`📊 Returning session ${sessionId}:`, {
      sessionFields: Object.keys(session),
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

    const summary = db.prepare('SELECT * FROM summaries WHERE session_id = ?')
      .get(sessionId);

    if (!summary) {
      return res.status(404).json({ error: 'Summary not found' });
    }

    // Parse JSON arrays
    summary.action_items = JSON.parse(summary.action_items);
    summary.tags = JSON.parse(summary.tags);

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
