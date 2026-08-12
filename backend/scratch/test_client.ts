import { WebSocket } from 'ws';

const URL = 'ws://localhost:8080';

interface PendingResolver {
  resolver: (val: any) => void;
  predicate?: (msg: any) => boolean;
}

// Helper to wrap WebSocket connection and events in a promise
function createClient(name: string): Promise<{
  ws: WebSocket;
  messages: any[];
  waitForMessage: (type: string, predicate?: (msg: any) => boolean) => Promise<any>;
}> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL);
    const messages: any[] = [];
    const pendingResolvers = new Map<string, PendingResolver>();

    ws.on('open', () => {
      resolve({
        ws,
        messages,
        waitForMessage: (type: string, predicate?: (msg: any) => boolean) => {
          // Check existing messages
          const index = messages.findIndex((m) => m.type === type && (!predicate || predicate(m)));
          if (index !== -1) {
            const found = messages[index];
            messages.splice(index, 1);
            return Promise.resolve(found);
          }
          // Register resolver
          return new Promise((res) => {
            pendingResolvers.set(type, { resolver: res, predicate });
          });
        }
      });
    });

    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString());
      console.log(`[Client - ${name}] Received:`, msg);
      messages.push(msg);

      const pending = pendingResolvers.get(msg.type);
      if (pending) {
        if (!pending.predicate || pending.predicate(msg)) {
          pendingResolvers.delete(msg.type);
          // Remove from messages array since it is consumed
          const idx = messages.indexOf(msg);
          if (idx !== -1) {
            messages.splice(idx, 1);
          }
          pending.resolver(msg);
        }
      }
    });

    ws.on('error', (err) => {
      reject(err);
    });
  });
}

async function runTests() {
  console.log('Starting Wayfinder Phase 1 Verification tests...\n');

  let hostId = '';
  let roomCode = '';
  let guestId = '';

  // 1. Establish Host (Alice) connection
  console.log('--- Step 1: Connecting Host (Alice) ---');
  const alice = await createClient('Alice');
  
  // 2. Alice creates a room
  console.log('--- Step 2: Creating Room ---');
  alice.ws.send(JSON.stringify({ type: 'create_room', playerName: 'Alice' }));
  const createdMsg = await alice.waitForMessage('room_created');
  roomCode = createdMsg.roomCode;
  hostId = createdMsg.userId;
  console.log(`Room created successfully! Code: ${roomCode}, Host UserId: ${hostId}`);

  // Await room state update
  let aliceState = await alice.waitForMessage('room_state');
  console.log('Alice initial room state:', JSON.stringify(aliceState.players, null, 2));

  // 3. Guest (Bob) joins
  console.log('\n--- Step 3: Connecting Guest (Bob) ---');
  const bob = await createClient('Bob');
  bob.ws.send(JSON.stringify({ type: 'join_room', roomCode, playerName: 'Bob' }));
  
  const bobJoinedMsg = await bob.waitForMessage('room_joined');
  guestId = bobJoinedMsg.userId;
  console.log(`Bob joined successfully! Bob UserId: ${guestId}`);

  // Alice should receive room_state containing Bob
  const aliceStateWithBob = await alice.waitForMessage('room_state', (msg) => 
    msg.players.some((p: any) => p.name === 'Bob')
  );
  console.log('Alice room state (with Bob):', JSON.stringify(aliceStateWithBob.players, null, 2));

  // 4. Bob updates state
  console.log('\n--- Step 4: Bob updates games and ready status ---');
  bob.ws.send(JSON.stringify({ type: 'update_state', games: ['Super Metroid', 'Slay the Spire'], isReady: true }));
  
  // Both Alice and Bob should receive updated room state (where Bob is ready and has games)
  const isBobReadyPredicate = (msg: any) => 
    msg.players.some((p: any) => p.name === 'Bob' && p.isReady && p.games.length > 0);

  const aliceUpdatedState = await alice.waitForMessage('room_state', isBobReadyPredicate);
  const bobUpdatedState = await bob.waitForMessage('room_state', isBobReadyPredicate);
  
  console.log('Alice received updated state:', JSON.stringify(aliceUpdatedState.players, null, 2));
  console.log('Bob received updated state:', JSON.stringify(bobUpdatedState.players, null, 2));

  // 5. Bob disconnects
  console.log('\n--- Step 5: Bob disconnects ---');
  bob.ws.close();
  
  // Alice should receive room_state with Bob marked as disconnected (isConnected: false)
  const aliceStateBobDisconnected = await alice.waitForMessage('room_state', (msg) =>
    msg.players.some((p: any) => p.name === 'Bob' && !p.isConnected)
  );
  console.log('Alice received state (Bob disconnected):', JSON.stringify(aliceStateBobDisconnected.players, null, 2));

  // 6. Bob reconnects
  console.log('\n--- Step 6: Bob reconnects using userId ---');
  const bob2 = await createClient('Bob (Reconnected)');
  bob2.ws.send(JSON.stringify({ type: 'reconnect', userId: guestId, roomCode }));

  const bobRejoinedMsg = await bob2.waitForMessage('room_joined');
  console.log('Bob reconnected successfully! Bob state:', JSON.stringify(bobRejoinedMsg.players, null, 2));

  // Alice should receive room_state with Bob marked as connected (isConnected: true) again
  const aliceStateBobReconnected = await alice.waitForMessage('room_state', (msg) =>
    msg.players.some((p: any) => p.name === 'Bob' && p.isConnected)
  );
  console.log('Alice received state (Bob reconnected):', JSON.stringify(aliceStateBobReconnected.players, null, 2));

  // Cleanup
  console.log('\n--- Cleanup: Closing all connections ---');
  alice.ws.close();
  bob2.ws.close();

  console.log('\nAll verification tests completed successfully!');
}

runTests().catch((err) => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
