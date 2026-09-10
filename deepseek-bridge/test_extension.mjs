// Offline test of the actual TypeScript extension's history hooks. No Pi/model run.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const piRoot = process.env.ATOLL_TEST_PI_ROOT || '/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent';
const requirePi = createRequire(path.join(piRoot, 'package.json'));
const {createJiti} = requirePi('jiti');
const jiti = createJiti(import.meta.url, {fsCache: false, moduleCache: false,
  alias: {typebox: requirePi.resolve('typebox')}});
const extension = await jiti.import(fileURLToPath(new URL('./pi-tools.ts', import.meta.url)), {default: true});
const commands = new Map();
const events = new Map();
let activeTools = [];
let modelCalls = 0;
const pi = {
  registerCommand: (name, spec) => commands.set(name, spec),
  registerTool: () => {},
  on: (name, handler) => events.set(name, handler),
  setActiveTools: names => { activeTools = names; },
  sendUserMessage: () => { modelCalls++; },
  sendMessage: () => { modelCalls++; },
};
extension(pi);
const image = {type: 'image', data: 'image-bytes', mimeType: 'image/png'};
const history = [
  {role: 'system', content: 'Keep user instructions'},
  {role: 'user', content: 'Look at this', images: [image]},
  {role: 'assistant', content: 'It is red'},
];
await commands.get('atoll-context').handler(JSON.stringify(history));
assert.equal(modelCalls, 0);
const current = {role: 'user', content: [{type: 'text', text: 'What color?'}], timestamp: 1};
const turn = {messages: [current]};
for (let round = 0; round < 3; round++) {
  const result = await events.get('context')(turn);
  assert.deepEqual(result.messages.map(m => m.role), ['user', 'assistant', 'user']);
  assert.deepEqual(result.messages[0].content, [{type: 'text', text: 'Look at this'}, image]);
  assert.deepEqual(result.messages[1].content, [{type: 'text', text: 'It is red'}]);
  assert.deepEqual(result.messages[2], current);
  assert.deepEqual(turn.messages, [current]);
}
assert.equal((await events.get('before_agent_start')({systemPrompt: 'Base'})).systemPrompt,
  'Base\n\nKeep user instructions');
await commands.get('atoll-tools').handler('off');
assert.deepEqual(activeTools, []);
await commands.get('atoll-tools').handler('on');
assert.deepEqual(activeTools, ['web_search', 'read_webpage', 'list_files', 'read_file']);
await commands.get('atoll-context').handler('[]');
assert.deepEqual((await events.get('context')(turn)).messages, [current]);
assert.equal(await events.get('before_agent_start')({systemPrompt: 'Base'}), undefined);
assert.equal(modelCalls, 0);
console.log('Extension history, image, system, tool-switch, and zero-replay checks passed.');
