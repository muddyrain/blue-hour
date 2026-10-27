import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { assertTarget, saveObservedState, sampleThenPause } from '../tools/reference_capture.mjs';

const target = { app: 'fake:reference', id: 2 };
const old = { app: target.app, id: 1 };
const snapshot = window => ({ window, screenshots: [{ url: 'data:image/jpeg;base64,Y3VycmVudA==' }] });
const root = await mkdtemp(join(tmpdir(), 'blue-hour-capture-'));
try {
  assert.throws(() => assertTarget(snapshot(old), target), /current target/);
  await assert.rejects(saveObservedState(snapshot(old), target, join(root, 'stale.jpg')), /current target/);
  assert.deepEqual(await readdir(root), []);
  await saveObservedState(snapshot(target), target, join(root, 'fresh.jpg'));
  assert.equal(await readFile(join(root, 'fresh.jpg'), 'utf8'), 'current');
  let inputs = 0;
  let captures = 0;
  const client = {
    list_windows: async () => [target],
    get_window_state: async ({ window }) => { assert.equal(window.id, 2); captures++; return snapshot(target); },
    press_key: async ({ window, key }) => { assert.equal(window.id, 2); assert.equal(key, 'space'); inputs++; },
  };
  await assert.rejects(sampleThenPause(client, old, join(root, 'obsolete'), 1), /no longer open/);
  assert.equal(inputs, 0);
  assert.equal(captures, 0);
  const result = await sampleThenPause(client, target, join(root, 'current'), 30);
  assert.equal(inputs, 1);
  assert.equal(result.metadata.pause_key_sent, true);
  assert.equal(result.metadata.pause_verified, false);
  client.get_window_state = async () => snapshot(old);
  await assert.rejects(sampleThenPause(client, target, join(root, 'wrong-snapshot'), 30), /current target/);
  assert.equal(inputs, 1);
  client.get_window_state = async () => { throw Error('capture unavailable'); };
  await assert.rejects(sampleThenPause(client, target, join(root, 'failed'), 1), /capture unavailable/);
  assert.equal(inputs, 1);
  const failed = JSON.parse(await readFile(join(root, 'failed', 'frames.json'), 'utf8'));
  assert.equal(failed.pause_key_sent, false);
  assert.match(failed.error, /capture unavailable/);
  console.log('PASS: other-window snapshot and stale window rejected before writes/input; explicit current target retained; capture failure does not claim pause; visual pause confirmation remains required.');
} finally {
  // The generated temporary directory is the only cleanup target.
  assert.equal(dirname(root), resolve(tmpdir()));
  assert.ok(basename(root).startsWith('blue-hour-capture-'));
  await rm(root, { recursive: true, force: true });
}
