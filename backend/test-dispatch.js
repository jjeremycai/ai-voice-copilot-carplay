#!/usr/bin/env node
/**
 * Test script to manually dispatch an agent to a room
 */

import { RoomServiceClient, AgentDispatchClient } from 'livekit-server-sdk';

const LIVEKIT_URL = process.env.LIVEKIT_URL || 'wss://bunnyai-4r3cmnxl.livekit.cloud';
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY || 'APIdMjzJuD2sqxn';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || 'cHNMaqoykB6SzASgdn5ofYekt4jxSHrFBM53NHfvwWXB';

// Convert wss:// to https:// for API calls
const API_URL = LIVEKIT_URL.replace('wss://', 'https://').replace('ws://', 'http://');

async function testDispatch() {
  console.log('🧪 Testing agent dispatch...');
  console.log(`   URL: ${LIVEKIT_URL}`);
  console.log(`   API Key: ${LIVEKIT_API_KEY.substring(0, 10)}...`);
  console.log('');

  const roomName = `test-room-${Date.now()}`;
  const agentName = 'agent';
  
  const agentMetadata = {
    session_id: `test-session-${Date.now()}`,
    realtime: false,
    model: 'openai/gpt-5-mini',
    voice: 'cartesia/sonic-3:...',
    tool_calling_enabled: true,
    web_search_enabled: true,
  };

  try {
    console.log(`📡 Creating dispatch to room: ${roomName}`);
    console.log(`   Agent name: ${agentName}`);
    console.log(`   Metadata:`, JSON.stringify(agentMetadata, null, 2));
    console.log('');

    const agentDispatchClient = new AgentDispatchClient(API_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET);
    const dispatch = await agentDispatchClient.createDispatch(roomName, agentName, {
      metadata: JSON.stringify(agentMetadata),
    });

    console.log(`✅ Dispatch created successfully!`);
    console.log(`   Dispatch ID: ${dispatch.id}`);
    console.log(`   Room: ${roomName}`);
    console.log('');

    // Wait a bit and check if agent joined
    console.log('⏳ Waiting 5 seconds for agent to join...');
    await new Promise(resolve => setTimeout(resolve, 5000));

    const roomService = new RoomServiceClient(API_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET);
    const rooms = await roomService.listRooms();
    const room = rooms.find(r => r.name === roomName);

    if (room) {
      console.log(`✅ Room found: ${room.name}`);
      console.log(`   Participants: ${room.numParticipants}`);
      const creationTime = typeof room.creationTime === 'bigint' 
        ? Number(room.creationTime) 
        : room.creationTime;
      console.log(`   Creation time: ${new Date(creationTime * 1000).toISOString()}`);
      console.log('');

      // List participants
      try {
        const participants = await roomService.listParticipants(roomName);
        console.log(`👥 Participants in room (${participants.length}):`);
        participants.forEach(p => {
          console.log(`   - ${p.identity} (${p.state})`);
          if (p.attributes && Object.keys(p.attributes).length > 0) {
            console.log(`     Attributes:`, JSON.stringify(p.attributes, null, 2));
          }
        });
      } catch (err) {
        console.log(`⚠️  Could not list participants: ${err.message}`);
      }
    } else {
      console.log(`⚠️  Room not found yet (may be auto-created when agent joins)`);
    }

  } catch (error) {
    console.error('❌ Dispatch failed:', error.message);
    console.error('   Full error:', error);
    process.exit(1);
  }
}

testDispatch().catch(console.error);

