#!/usr/bin/env node
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { WorkspaceClient } from './client.mjs';
import { tools, validate } from './tools.mjs';

const client = new WorkspaceClient();
const server = new Server({ name: 'minami-yomado', version: '0.1.0' }, {
  capabilities: { tools: {} },
  instructions: 'Manage task-owned virtual displays and whole-desktop previews. Check service_status for permissions first; the user grants them. Keep a physical display main. Create a stopped profile, configure it, then start. Move only explicitly authorized window IDs. Open one compact PiP and keep it open during work; respect saved user size and position. Never enlarge or close/reopen it between actions, or reopen a viewer the user closed without a viewing request. Virtual displays share the login and input session; use Minami for application input. Restore moved windows before stopping. Native workspaces survive MCP disconnect. Never retry a timed-out mutation without inspecting state.',
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
