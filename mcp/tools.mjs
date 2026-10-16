const text = (description, extra = {}) => ({ type: 'string', description, ...extra });
const integer = (description, minimum, maximum) => ({ type: 'integer', description, minimum, maximum });
const workspace = { workspace_id: text('Stable ID returned by workspace_create.') };
const settings = {
  name: text('Display label (OS name changes on next start).', { minLength: 1, maxLength: 100 }),
  width: integer('Logical desktop width. Change only while stopped.', 320, 8192),
  height: integer('Logical desktop height. Change only while stopped.', 240, 8192),
  hidpi: { type: 'boolean', description: 'Render at twice the logical dimensions.' },
};
function tool(name, description, properties = {}, required = [], readOnly = false) {
  return { name, description, inputSchema: { type: 'object', properties, required, additionalProperties: false },
    annotations: { readOnlyHint: readOnly, destructiveHint: !readOnly, openWorldHint: false } };
}
export const tools = [
  tool('service_status', 'Read native helper version and capture/control permission status.', {}, [], true),
  tool('workspace_list', 'List owned workspace profiles and current macOS displays. Other applications’ displays are read-only.', {}, [], true),
  tool('workspace_create', 'Save a new stopped virtual workspace profile. Call workspace_start separately to activate it.', settings),
  tool('workspace_get', 'Read workspace settings and actual running display bounds.', workspace, ['workspace_id'], true),
  tool('workspace_configure', 'Rename or configure resolution/HiDPI. Resolution changes require a stopped workspace.', { ...workspace, ...settings }, ['workspace_id']),
  tool('workspace_start', 'Start an owned virtual display; verify extended mode and unchanged existing display layout.', workspace, ['workspace_id']),
  tool('workspace_stop', 'Stop an empty owned virtual display, retaining its profile. Restore moved windows first.', workspace, ['workspace_id']),
  tool('workspace_destroy', 'Delete a stopped workspace profile. Does not forcibly stop occupied displays.', workspace, ['workspace_id']),
  tool('workspace_recover', 'Retry pending topology recovery. Unrelated display changes may require manual recovery.'),
  tool('window_list', 'List ordinary window IDs, owner PIDs and bounds for explicitly scoped placement.', {}, [], true),
  tool('workspace_move_window', 'Move one exact window/PID into an owned workspace without taking focus. First placement requires a physical origin; retain its restoration checkpoint.', {
    ...workspace, window_id: integer('Exact CGWindowID from window_list.', 1, 4294967295), pid: integer('Owning process ID from window_list.', 1, 2147483647),
    x: integer('Optional left offset within the virtual workspace, in points.', 0, 8192),
    y: integer('Optional top offset within the virtual workspace, in points.', 0, 8192),
  }, ['workspace_id', 'window_id', 'pid']),
  tool('workspace_restore', 'Restore only windows tracked for this workspace to their original physical positions. Closed windows release their checkpoints.', workspace, ['workspace_id']),
  tool('preview_open', 'Ensure one independent live whole-desktop PiP is open. Reuse the existing viewer; do not close/reopen it between actions. Restore the last user size/position, even if stale dimensions are supplied. First-open default is compact 480×300. Use preview_configure only for an explicitly requested resize. No Minami dependency.', {
    ...workspace, width: integer('Initial panel width only; ignored when saved geometry exists.', 240, 4096), height: integer('Initial panel height only; ignored when saved geometry exists.', 160, 4096),
    output_width: integer('Capture pixel width; default 1280.', 320, 3840), fps: integer('Capture frame-rate limit; default 30.', 1, 60),
    shows_cursor: { type: 'boolean', description: 'Include the shared system cursor; default true.' },
  }, ['workspace_id']),
  tool('preview_configure', 'Resize/reposition an open preview. Coordinates are screen points from the physical main display top-left. To change capture settings, close and reopen.', {
    ...workspace, width: integer('Floating panel width.', 240, 4096), height: integer('Floating panel height.', 160, 4096),
    x: integer('Left edge on physical main display.', 0, 16384), y: integer('Top edge on physical main display.', 0, 16384),
  }, ['workspace_id']),
  tool('preview_close', 'Close this workspace’s live viewer; keep its virtual display and windows running.', workspace, ['workspace_id']),
  tool('service_shutdown', 'Exit the shared native helper only when all workspaces are stopped. MCP disconnect alone never destroys displays.'),
];

export function validate(name, args) {
  const definition = tools.find(t => t.name === name);
  if (!definition) throw new Error(`Unknown tool: ${name}`);
  if (!args || typeof args !== 'object' || Array.isArray(args)) throw new Error('arguments must be an object');
  const { properties, required } = definition.inputSchema;
  for (const key of required) if (!(key in args)) throw new Error(`Missing ${key}`);
  for (const [key, value] of Object.entries(args)) {
    const rule = properties[key];
    if (!rule) throw new Error(`Unknown argument: ${key}`);
    if (rule.type === 'integer' ? !Number.isSafeInteger(value) : typeof value !== rule.type) throw new Error(`Invalid ${key}`);
    if (rule.type === 'integer' && (value < rule.minimum || value > rule.maximum)) throw new Error(`Out of range: ${key}`);
    if (rule.type === 'string' && (value.length < (rule.minLength ?? 1) || value.length > (rule.maxLength ?? 200))) throw new Error(`Invalid length: ${key}`);
  }
  return args;
}
