#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { WorkspaceClient } from './client.mjs';
import { tools, validate } from './tools.mjs';

const client = new WorkspaceClient();
const server = new Server({ name: 'yomado-workspaces', version: '0.1.0' }, {
  capabilities: { tools: {} },
  instructions: 'Manage task-owned virtual displays and whole-desktop previews. Keep a physical display main. Create a stopped profile, configure it, then start. Move only explicitly authorized window IDs. Virtual displays share the login and input session; use Minami for application input. Restore moved windows before stopping. Native workspaces survive MCP disconnect. Never retry a timed-out mutation without inspecting state.',
});
server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));
server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  try {
    const result = await client.call(params.name, validate(params.name, params.arguments ?? {}));
    return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }], structuredContent: result };
  } catch (error) {
    return { isError: true, content: [{ type: 'text', text: JSON.stringify({ error: error.code || 'operation_failed', message: error.message }) }] };
  }
});
await server.connect(new StdioServerTransport());
