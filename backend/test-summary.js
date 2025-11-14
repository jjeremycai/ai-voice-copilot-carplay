#!/usr/bin/env node
/**
 * Test script to manually trigger summary generation for a session
 */

const BACKEND_URL = process.env.BACKEND_URL || 'https://shaw.up.railway.app';
const SESSION_ID = process.argv[2];

if (!SESSION_ID) {
  console.error('❌ Please provide a session ID');
  console.error('   Usage: node test-summary.js <session-id>');
  process.exit(1);
}

async function testSummary() {
  console.log('🧪 Testing summary generation...');
  console.log(`   Session ID: ${SESSION_ID}`);
  console.log('');

  try {
    // First, check current session status
    console.log('📊 Checking current session status...');
    const checkResponse = await fetch(`${BACKEND_URL}/v1/sessions/${SESSION_ID}`, {
      headers: {
        'Authorization': `Bearer device_test_token_${Date.now()}`,
      },
    });

    if (!checkResponse.ok) {
      throw new Error(`Failed to fetch session: ${checkResponse.status}`);
    }

    const sessionData = await checkResponse.json();
    const session = sessionData.session || sessionData;
    const turns = sessionData.turns || [];

    console.log(`   Status: ${session.summaryStatus || session.summary_status || 'N/A'}`);
    console.log(`   Ended: ${session.endedAt || session.ended_at || 'Not ended'}`);
    console.log(`   Turns: ${turns.length}`);
    console.log('');

    if (!session.endedAt && !session.ended_at) {
      console.log('⚠️  Session is not ended yet. Ending it first...');
      const endResponse = await fetch(`${BACKEND_URL}/v1/sessions/end`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer device_test_token_${Date.now()}`,
        },
        body: JSON.stringify({
          session_id: SESSION_ID,
        }),
      });

      if (endResponse.ok) {
        console.log('✅ Session ended');
      } else {
        throw new Error(`Failed to end session: ${endResponse.status}`);
      }
    }

    console.log('⏳ Waiting for background job to process summary (checking every 5 seconds)...');
    console.log('');

    // Poll for summary
    for (let i = 0; i < 12; i++) { // Check for up to 60 seconds
      await new Promise(resolve => setTimeout(resolve, 5000));

      const statusResponse = await fetch(`${BACKEND_URL}/v1/sessions/${SESSION_ID}`, {
        headers: {
          'Authorization': `Bearer device_test_token_${Date.now()}`,
        },
      });

      if (!statusResponse.ok) {
        throw new Error(`Failed to fetch session: ${statusResponse.status}`);
      }

      const statusData = await statusResponse.json();
      const statusSession = statusData.session || statusData;
      const statusSummary = statusData.summary;
      const status = statusSession.summaryStatus || statusSession.summary_status;

      console.log(`   [${i + 1}/12] Status: ${status}`);

      if (status === 'ready' && statusSummary) {
        console.log('');
        console.log('✅ Summary generated successfully!');
        console.log('');
        console.log('📄 Summary:');
        console.log(`   Title: ${statusSummary.title || statusSummary.title_text}`);
        console.log(`   Summary: ${statusSummary.summaryText || statusSummary.summary_text}`);
        console.log(`   Action Items: ${statusSummary.actionItems?.length || statusSummary.action_items?.length || 0}`);
        if (statusSummary.actionItems || statusSummary.action_items) {
          const items = statusSummary.actionItems || statusSummary.action_items;
          items.forEach((item, idx) => console.log(`     ${idx + 1}. ${item}`));
        }
        console.log(`   Tags: ${statusSummary.tags?.join(', ') || 'None'}`);
        return;
      }

      if (status === 'failed') {
        console.log('');
        console.error('❌ Summary generation failed');
        console.error('   Check Railway logs for error details');
        return;
      }
    }

    console.log('');
    console.log('⚠️  Summary not generated after 60 seconds');
    console.log('   Check Railway logs for background job status');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

testSummary().catch(console.error);






