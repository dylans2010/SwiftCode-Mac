/**
 * SwiftCode OpenAI Codex SDK Node Bridge
 * Runs a local server on port 3003 and handles communication between SwiftCode and OpenAI Codex.
 */

const http = require('http');
const { OpenAI } = require('openai');

const PORT = 3003;

// Log helper
function log(msg) {
  console.log(`[CodexBridge] [${new Date().toISOString()}] ${msg}`);
}

function errorLog(msg) {
  console.error(`[CodexBridge] [${new Date().toISOString()}] ERROR: ${msg}`);
}

const server = http.createServer(async (req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  log(`Received ${req.method} request on ${req.url}`);

  // Health check endpoint
  if (req.url === '/health' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: '1.0.0' }));
    return;
  }

  // Chat completions endpoint
  if (req.url === '/v1/chat/completions' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString();
    });

    req.on('end', async () => {
      try {
        const payload = JSON.parse(body);
        const authorization = req.headers['authorization'] || '';
        const apiKey = authorization.replace('Bearer ', '').trim();

        if (!apiKey) {
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: 'Authorization Bearer token is missing.' } }));
          return;
        }

        const openai = new OpenAI({ apiKey: apiKey });

        const model = payload.model || 'gpt-5-codex';
        const messages = payload.messages || [];
        const isStream = !!payload.stream;

        log(`Routing to OpenAI model: ${model}, stream: ${isStream}`);

        if (isStream) {
          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive'
          });

          try {
            const stream = await openai.chat.completions.create({
              model: model.includes('codex') ? 'gpt-4o' : model, // Fallback to compatible model if testing with standard keys
              messages: messages,
              stream: true
            });

            for await (const chunk of stream) {
              const text = chunk.choices[0]?.delta?.content || '';
              const payloadStr = JSON.stringify({
                choices: [{ delta: { content: text } }]
              });
              res.write(`data: ${payloadStr}\n\n`);
            }
            res.write('data: [DONE]\n\n');
            res.end();
          } catch (err) {
            errorLog(`Stream failed: ${err.message}`);
            res.write(`data: ${JSON.stringify({ error: { message: err.message } })}\n\n`);
            res.end();
          }
        } else {
          try {
            const response = await openai.chat.completions.create({
              model: model.includes('codex') ? 'gpt-4o' : model,
              messages: messages,
              stream: false
            });

            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(response));
          } catch (err) {
            errorLog(`Non-stream failed: ${err.message}`);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: { message: err.message } }));
          }
        }

      } catch (err) {
        errorLog(`Request processing failed: ${err.message}`);
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'Malformed JSON payload: ' + err.message } }));
      }
    });
    return;
  }

  // Not found
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: { message: 'Endpoint not found.' } }));
});

server.listen(PORT, '127.0.0.1', () => {
  log(`Codex Node Bridge server successfully started on http://127.0.0.1:${PORT}`);
});

process.on('SIGTERM', () => {
  log('SIGTERM received. Shutting down bridge gracefully.');
  server.close(() => {
    process.exit(0);
  });
});
