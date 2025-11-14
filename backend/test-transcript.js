#!/usr/bin/env node
/**
 * Test script to fetch transcript from a session
 */

const BACKEND_URL = process.env.BACKEND_URL || 'https://shaw.up.railway.app';
const TEST_SESSION_ID = process.argv[2] || null;

async function testTranscript() {
  console.log('🧪 Testing transcript fetching...');
  console.log(`   Backend URL: ${BACKEND_URL}`);
  console.log('');

  if (!TEST_SESSION_ID) {
    console.log('❌ Please provide a session ID as argument');
    console.log('   Usage: node test-transcript.js <session-id>');
    console.log('');
    console.log('   Or create a test session first...');
    
    // Try to create a test session
    try {
      console.log('📝 Creating test session...');
      const createResponse = await fetch(`${BACKEND_URL}/v1/sessions/start`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer device_test_token_${Date.now()}`,
        },
        body: JSON.stringify({
          context: 'phone',
          logging_enabled: true,
        }),
      });

      if (!createResponse.ok) {
        throw new Error(`Failed to create session: ${createResponse.status} ${createResponse.statusText}`);
      }

      const sessionData = await createResponse.json();
      const sessionId = sessionData.session_id || sessionData.sessionId || sessionData.id;
      
      if (!sessionId) {
        console.error('❌ Session ID not found in response:', JSON.stringify(sessionData, null, 2));
        process.exit(1);
      }
      
      console.log(`✅ Test session created: ${sessionId}`);
      console.log('   Response:', JSON.stringify(sessionData, null, 2));
      console.log('');

      // Add some test turns
      console.log('📝 Adding test turns...');
      const turns = [
        { speaker: 'user', text: 'Hello, I need help with my car' },
        { speaker: 'assistant', text: 'Hello! I\'d be happy to help you with your car. What seems to be the issue?' },
        { speaker: 'user', text: 'The engine is making a strange noise' },
        { speaker: 'assistant', text: 'I understand that can be concerning. Can you describe the noise? Is it a knocking, rattling, or squealing sound?' },
        { speaker: 'user', text: 'It sounds like a knocking sound' },
        { speaker: 'assistant', text: 'A knocking sound could indicate several issues. When does it occur - when starting, while driving, or when idling?' },
      ];

      for (const turn of turns) {
        const turnResponse = await fetch(`${BACKEND_URL}/v1/sessions/${sessionId}/turns`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            speaker: turn.speaker,
            text: turn.text,
          }),
        });

        if (turnResponse.ok) {
          console.log(`   ✅ Added ${turn.speaker} turn: "${turn.text.substring(0, 50)}..."`);
        } else {
          const errorText = await turnResponse.text();
          console.log(`   ⚠️  Failed to add turn: ${turnResponse.status} - ${errorText}`);
        }
        
        // Small delay between turns
        await new Promise(resolve => setTimeout(resolve, 100));
      }

      console.log('');
      console.log('📊 Fetching transcript...');
      await fetchTranscript(sessionId);
      
      // End the session
      console.log('');
      console.log('🏁 Ending session...');
      const endResponse = await fetch(`${BACKEND_URL}/v1/sessions/end`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer device_test_token_${Date.now()}`,
        },
        body: JSON.stringify({
          session_id: sessionData.sessionId,
        }),
      });

      if (endResponse.ok) {
        console.log('✅ Session ended');
      }

      return;
    } catch (error) {
      console.error('❌ Failed to create test session:', error.message);
      process.exit(1);
    }
  }

  await fetchTranscript(TEST_SESSION_ID);
}

async function fetchTranscript(sessionId) {
  try {
    console.log(`📡 Fetching transcript for session: ${sessionId}`);
    console.log('');

    const response = await fetch(`${BACKEND_URL}/v1/sessions/${sessionId}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer device_test_token_${Date.now()}`,
      },
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch transcript: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    
    // Handle nested structure: { session, summary, turns }
    const session = data.session || data;
    const summary = data.summary;
    const turns = data.turns || [];
    
    console.log('✅ Transcript fetched successfully!');
    console.log('');
    console.log('📋 Session Info:');
    console.log(`   ID: ${session.id || session.session_id || 'N/A'}`);
    console.log(`   Started: ${session.startedAt || session.started_at || 'N/A'}`);
    console.log(`   Ended: ${session.endedAt || session.ended_at || 'Still active'}`);
    console.log(`   Summary Status: ${session.summaryStatus || session.summary_status || 'N/A'}`);
    console.log(`   Context: ${session.context || 'N/A'}`);
    console.log('');

    if (summary) {
      console.log('📄 Summary:');
      console.log(`   Title: ${summary.title || summary.title_text || 'N/A'}`);
      console.log(`   Summary: ${summary.summaryText || summary.summary_text || 'N/A'}`);
      console.log(`   Action Items: ${summary.actionItems?.length || summary.action_items?.length || 0}`);
      if (summary.actionItems || summary.action_items) {
        const items = summary.actionItems || summary.action_items;
        items.forEach((item, i) => console.log(`     ${i + 1}. ${item}`));
      }
      console.log(`   Tags: ${summary.tags?.join(', ') || 'None'}`);
      console.log('');
    } else {
      console.log('⚠️  No summary available yet');
      console.log('');
    }

    if (turns && turns.length > 0) {
      console.log(`💬 Transcript (${turns.length} turns):`);
      console.log('');
      turns.forEach((turn, index) => {
        const speaker = turn.speaker === 'user' ? '👤 User' : '🤖 Assistant';
        const time = new Date(turn.timestamp).toLocaleTimeString();
        console.log(`   [${index + 1}] ${speaker} (${time}):`);
        console.log(`       ${turn.text}`);
        console.log('');
      });
    } else {
      console.log('⚠️  No turns found in transcript');
    }

  } catch (error) {
    console.error('❌ Failed to fetch transcript:', error.message);
    console.error('   Full error:', error);
    process.exit(1);
  }
}

testTranscript().catch(console.error);

