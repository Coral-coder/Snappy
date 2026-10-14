// On-device roll.
//
// Captures live in IndexedDB on this device. Nothing is uploaded — there is no
// server in this app — and nothing reaches the system photo library until you
// share or download a shot yourself.

const DB_NAME = 'snappy';
const DB_VERSION = 1;
const STORE = 'captures';

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE)) {
        const store = db.createObjectStore(STORE, { keyPath: 'id' });
        store.createIndex('created', 'created');
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function run(mode, work) {
  return open().then((db) => new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const store = tx.objectStore(STORE);
    let result;
    try {
      result = work(store);
    } catch (error) {
      reject(error);
      return;
    }
    tx.oncomplete = () => resolve(result?.result ?? result);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  }));
}

export async function addCapture({ blob, thumbnail, kind, mime }) {
  const record = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    created: Date.now(),
    kind,
    mime,
    blob,
    thumbnail
  };
  await run('readwrite', (store) => store.put(record));
  return record;
}

export async function allCaptures() {
  const records = await run('readonly', (store) => store.getAll());
  return (records ?? []).sort((a, b) => b.created - a.created);
}

export function deleteCapture(id) {
  return run('readwrite', (store) => store.delete(id));
}

export async function latestCapture() {
  const all = await allCaptures();
  return all[0] ?? null;
}

/** Rough bytes used, so Settings can be honest about what is on the device. */
export async function usage() {
  if (!navigator.storage?.estimate) return null;
  const { usage: used, quota } = await navigator.storage.estimate();
  return { used, quota };
}

export function fileNameFor(record) {
  const stamp = new Date(record.created).toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const extension = record.kind === 'video' ? (record.mime.includes('mp4') ? 'mp4' : 'webm') : 'jpg';
  return `snappy-${stamp}.${extension}`;
}
