// Persistent food database in IndexedDB (images are stored inline as data URLs).
const DB_NAME = 'nutricard';
const STORE = 'foods';

let dbPromise;

function open() {
  dbPromise ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE, { keyPath: 'id' });
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

async function tx(mode, fn) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const t = db.transaction(STORE, mode);
    const result = fn(t.objectStore(STORE));
    t.oncomplete = () => resolve(result?.result ?? result);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  });
}

export const store = {
  all: () => tx('readonly', (s) => s.getAll()),
  put: (food) => tx('readwrite', (s) => s.put(food)),
  putMany: (foods) => tx('readwrite', (s) => foods.forEach((f) => s.put(f))),
  remove: (id) => tx('readwrite', (s) => s.delete(id)),
};
