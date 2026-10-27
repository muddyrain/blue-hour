import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

// Pass the current window and snapshot explicitly: REPL cell closures can retain old bindings.
export function assertTarget(state, target) {
  if (state?.window?.id !== target.id || state.window.app !== target.app) {
    throw new Error('Snapshot does not belong to the current target window');
  }
  const url = state.screenshots?.[0]?.url;
  if (!url?.startsWith('data:image/jpeg;base64,')) {
    throw new Error('Expected a target-window JPEG snapshot');
  }
  return Buffer.from(url.split(',')[1], 'base64');
}

export async function saveObservedState(state, target, file) {
  const bytes = assertTarget(state, target);
  if (!file.endsWith('.jpg')) throw new Error('JPEG evidence requires .jpg');
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, bytes);
}

// Call only after observing this exact window running; inspect the returned pause state.
// A failed capture aborts, and must never be reported as a successful pause.
export async function sampleThenPause(client, target, directory, durationMs) {
  if (!(durationMs > 0 && durationMs <= 3000)) throw new Error('Use a 1..3000ms sample');
  const windows = await client.list_windows();
  if (!windows.some(w => w.id === target.id && w.app === target.app)) {
    throw new Error('Target window is no longer open; refresh selection before any input');
  }
  await mkdir(directory, { recursive: true });
  const started = Date.now();
  const metadata = { started: new Date(started).toISOString(), frames: [], pause_key_sent: false, pause_verified: false };
  try {
    while (Date.now() - started < durationMs) {
      const state = await client.get_window_state({ window: target });
      const file = String(metadata.frames.length).padStart(4, '0') + '.jpg';
      await saveObservedState(state, target, join(directory, file));
      metadata.frames.push({ file, time_ms: Date.now() - started });
      await new Promise(resolve => setTimeout(resolve, 180));
    }
    await client.press_key({ window: target, key: 'space' });
    metadata.pause_key_sent = true;
    const state = await client.get_window_state({ window: target });
    assertTarget(state, target);
    await saveObservedState(state, target, join(directory, 'after-key.jpg'));
    return { state, metadata };
  } catch (error) {
    metadata.error = String(error);
    throw error;
  } finally {
    await writeFile(join(directory, 'frames.json'), JSON.stringify(metadata, null, 2) + '\n');
  }
}
