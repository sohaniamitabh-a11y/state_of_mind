/**
 * State of Mind — My Journal Feature Core
 * -------------------------------------------------------------
 * A standalone, zero-dependency data manager and storage service for
 * personal entertainment journaling (movies, TV shows, music, games).
 *
 * Designed to be completely decoupled from the UI: your UI developer
 * friend can call these methods from vanilla JS, React, Vue, or any
 * other frontend framework.
 *
 * DATA FLOW
 * ---------
 * When the Flask backend is reachable (backendConnected === true) all
 * mutations go to the API first.  The in-memory cache and localStorage
 * are only updated after the API confirms success.  If the API is
 * unavailable the library falls back to localStorage-only mode so the
 * UI never breaks.
 *
 * MIGRATION
 * ---------
 * On init, if the backend is reachable and there are existing
 * localStorage entries/collections that have not yet been migrated, a
 * safe, retryable migration is run automatically.  Entries are POSTed
 * one at a time; a local migration-status key records which ones
 * succeeded.  Existing localStorage data is kept until migration
 * succeeds completely.
 *
 * SECURITY NOTE
 * -------------
 * X-User-ID is NOT authenticated.  It is a best-effort anonymous-
 * browser isolation mechanism.  Never store sensitive personal data.
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.Journal = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ---------------------------------------------------------------------------
  // CONSTANTS
  // ---------------------------------------------------------------------------
  const STORAGE_KEY             = 'state_of_mind_journal_entries';
  const COLLECTIONS_STORAGE_KEY = 'state_of_mind_journal_collections';
  const USER_ID_KEY             = 'state_of_mind_user_id';
  const MIGRATED_IDS_KEY        = 'state_of_mind_migrated_ids';      // Set of local IDs already sent
  const MIGRATED_COLS_KEY       = 'state_of_mind_migrated_col_ids';  // Set of local collection IDs

  let apiBaseUrl       = 'http://127.0.0.1:5001';
  let syncEnabled      = true;
  let backendConnected = false;

  const MEDIA_TYPES = Object.freeze({
    MOVIE: 'movie',
    TV:    'tv',
    MUSIC: 'music',
    GAME:  'game'
  });

  const MOODS = Object.freeze([
    'Happy/Excitement',
    'Calm/Serene',
    'Sad/Melancholy',
    'Anger/Rage',
    'Confusion/Anxiety'
  ]);

  const STATUS = Object.freeze({
    EXPERIENCED: 'experienced',
    WISHLIST:    'wishlist'
  });

  // ---------------------------------------------------------------------------
  // SAMPLE DATA (used by loadSampleData / seedIfEmpty)
  // ---------------------------------------------------------------------------
  const SAMPLE_ENTRIES = [
    {
      title: 'Spirited Away',
      mediaType: MEDIA_TYPES.MOVIE,
      mood: 'Calm/Serene',
      rating: 5,
      dateExperienced: '2026-10-10',
      status: STATUS.EXPERIENCED,
      isFavorite: true,
      notes: 'Beautiful animation and soothing soundtrack. Watched on a rainy evening.',
      metadata: {
        creator: 'Hayao Miyazaki',
        genres: ['Animation', 'Fantasy'],
        imageUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=600&q=80'
      }
    },
    {
      title: 'Severance (Season 1)',
      mediaType: MEDIA_TYPES.TV,
      mood: 'Confusion/Anxiety',
      rating: 4.5,
      dateExperienced: '2026-10-08',
      status: STATUS.EXPERIENCED,
      isFavorite: true,
      notes: 'Incredible mystery and suspense. The season finale had my heart pounding.',
      metadata: { creator: 'Dan Erickson', genres: ['Sci-Fi', 'Thriller'] }
    },
    {
      title: 'Random Access Memories',
      mediaType: MEDIA_TYPES.MUSIC,
      mood: 'Happy/Excitement',
      rating: 5,
      dateExperienced: '2026-10-05',
      status: STATUS.EXPERIENCED,
      isFavorite: true,
      notes: 'Instant mood booster. Flawless production from start to finish.',
      metadata: { creator: 'Daft Punk', genres: ['Electronic', 'Disco', 'Funk'] }
    },
    {
      title: 'Hades',
      mediaType: MEDIA_TYPES.GAME,
      mood: 'Anger/Rage',
      rating: 4.8,
      dateExperienced: '2026-10-01',
      status: STATUS.EXPERIENCED,
      isFavorite: false,
      notes: 'Fast-paced, satisfying combat for when you need to let off steam.',
      metadata: { creator: 'Supergiant Games', genres: ['Roguelike', 'Action'] }
    },
    {
      title: 'Dune: Part Two',
      mediaType: MEDIA_TYPES.MOVIE,
      mood: null,
      rating: null,
      dateExperienced: null,
      status: STATUS.WISHLIST,
      isFavorite: false,
      notes: 'Heard the cinematography and Hans Zimmer score in IMAX are breathtaking.',
      metadata: { creator: 'Denis Villeneuve', genres: ['Sci-Fi', 'Adventure'] }
    },
    {
      title: 'Hollow Knight: Silksong',
      mediaType: MEDIA_TYPES.GAME,
      mood: null,
      rating: null,
      dateExperienced: null,
      status: STATUS.WISHLIST,
      isFavorite: true,
      notes: 'Patiently waiting for the release day!',
      metadata: { creator: 'Team Cherry', genres: ['Metroidvania', 'Action'] }
    }
  ];

  const SAMPLE_COLLECTIONS = [
    {
      name: 'Weekend Chill',
      description: 'Relaxing films, comforting shows, and soothing music.',
      itemTitles: ['Spirited Away', 'Random Access Memories']
    },
    {
      name: 'Adrenaline Rush',
      description: 'Fast-paced action, thrillers, and intense gaming sessions.',
      itemTitles: ['Severance (Season 1)', 'Hades']
    }
  ];

  // ---------------------------------------------------------------------------
  // IN-MEMORY STATE
  // ---------------------------------------------------------------------------
  let entries        = [];
  let collections    = [];
  let isInitialized  = false;
  let listeners      = [];
  let memoryFallback = false;

  // ---------------------------------------------------------------------------
  // LOGGER
  // ---------------------------------------------------------------------------
  const logger = {
    warn:  function () { if (typeof console !== 'undefined' && typeof console.warn  === 'function') console.warn.apply(console, arguments); },
    error: function () { if (typeof console !== 'undefined' && typeof console.error === 'function') console.error.apply(console, arguments); },
    info:  function () { if (typeof console !== 'undefined' && typeof console.info  === 'function') console.info.apply(console, arguments); }
  };

  // ---------------------------------------------------------------------------
  // LOCAL STORAGE HELPERS
  // ---------------------------------------------------------------------------
  function canUseLocalStorage() {
    try {
      if (typeof window === 'undefined' || !window.localStorage) return false;
      const key = '__som_journal_test__';
      window.localStorage.setItem(key, '1');
      window.localStorage.removeItem(key);
      return true;
    } catch (e) {
      return false;
    }
  }

  function lsGet(key) {
    if (!canUseLocalStorage()) return null;
    try { return window.localStorage.getItem(key); } catch (e) { return null; }
  }

  function lsSet(key, value) {
    if (!canUseLocalStorage()) return false;
    try { window.localStorage.setItem(key, value); return true; } catch (e) { return false; }
  }

  function lsRemove(key) {
    if (!canUseLocalStorage()) return;
    try { window.localStorage.removeItem(key); } catch (e) {}
  }

  function loadFromStorage() {
    if (!canUseLocalStorage()) { memoryFallback = true; return []; }
    try {
      const data = lsGet(STORAGE_KEY);
      if (!data) return [];
      const parsed = JSON.parse(data);
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      logger.warn('[Journal] Failed to parse local storage entries.', err);
      return [];
    }
  }

  function saveToStorage() {
    if (memoryFallback || !canUseLocalStorage()) { notifyListeners(); return true; }
    try {
      lsSet(STORAGE_KEY, JSON.stringify(entries));
      notifyListeners();
      return true;
    } catch (err) {
      logger.error('[Journal] Could not save to localStorage:', err);
      return false;
    }
  }

  function loadCollectionsFromStorage() {
    if (!canUseLocalStorage()) return [];
    try {
      const data = lsGet(COLLECTIONS_STORAGE_KEY);
      if (!data) return [];
      const parsed = JSON.parse(data);
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      logger.warn('[Journal] Failed to parse local storage collections.', err);
      return [];
    }
  }

  function saveCollectionsToStorage() {
    if (memoryFallback || !canUseLocalStorage()) { notifyListeners(); return true; }
    try {
      lsSet(COLLECTIONS_STORAGE_KEY, JSON.stringify(collections));
      notifyListeners();
      return true;
    } catch (err) {
      logger.error('[Journal] Could not save collections to localStorage:', err);
      return false;
    }
  }

  // Migrated-ID tracking (stored as JSON arrays in localStorage)
  function getMigratedIds() {
    try { return new Set(JSON.parse(lsGet(MIGRATED_IDS_KEY) || '[]')); } catch (e) { return new Set(); }
  }
  function saveMigratedIds(set) { lsSet(MIGRATED_IDS_KEY, JSON.stringify([...set])); }

  function getMigratedColIds() {
    try { return new Set(JSON.parse(lsGet(MIGRATED_COLS_KEY) || '[]')); } catch (e) { return new Set(); }
  }
  function saveMigratedColIds(set) { lsSet(MIGRATED_COLS_KEY, JSON.stringify([...set])); }

  // ---------------------------------------------------------------------------
  // SNAPSHOT HELPERS
  // ---------------------------------------------------------------------------
  function getAllEntriesSnapshot()    { return JSON.parse(JSON.stringify(entries)); }
  function getAllCollectionsSnapshot() { return JSON.parse(JSON.stringify(collections)); }

  function notifyListeners() {
    const snap     = getAllEntriesSnapshot();
    const colSnap  = getAllCollectionsSnapshot();
    listeners.forEach(function (cb) {
      try { cb(snap, colSnap); } catch (err) { logger.error('[Journal] Listener error:', err); }
    });
    if (typeof window !== 'undefined' && typeof window.dispatchEvent === 'function') {
      try {
        window.dispatchEvent(new CustomEvent('journal:changed', { detail: { entries: snap, collections: colSnap } }));
      } catch (e) {}
    }
  }

  // ---------------------------------------------------------------------------
  // ID GENERATORS
  // ---------------------------------------------------------------------------
  function generateId()           { return 'jnl_' + Date.now().toString(36) + '_' + Math.random().toString(36).substr(2, 6); }
  function generateCollectionId() { return 'col_' + Date.now().toString(36) + '_' + Math.random().toString(36).substr(2, 6); }

  // ---------------------------------------------------------------------------
  // USER IDENTITY — stable browser UUID
  // ---------------------------------------------------------------------------
  function getOrCreateUserId() {
    const stored = lsGet(USER_ID_KEY);
    if (stored && stored.trim()) return stored.trim();

    let uid;
    try {
      uid = (typeof crypto !== 'undefined' && crypto.randomUUID)
        ? crypto.randomUUID()
        : 'uid_' + Date.now().toString(36) + '_' + Math.random().toString(36).substr(2, 9);
    } catch (e) {
      uid = 'uid_' + Date.now().toString(36) + '_' + Math.random().toString(36).substr(2, 9);
    }
    lsSet(USER_ID_KEY, uid);
    return uid;
  }

  // Expose for read-only reference
  function currentUserId() { return lsGet(USER_ID_KEY) || getOrCreateUserId(); }

  // ---------------------------------------------------------------------------
  // API CLIENT
  // ---------------------------------------------------------------------------
  /**
   * Sends a JSON request to the Flask backend and returns the parsed response.
   *
   * @param {string} method   HTTP verb ('GET', 'POST', 'PUT', 'DELETE')
   * @param {string} path     Path relative to apiBaseUrl (e.g. '/api/library')
   * @param {Object} [body]   Optional JSON-serialisable request body
   * @returns {Promise<Object>} Parsed JSON response
   * @throws {Error} on network failure or non-2xx response
   */
  async function apiRequest(method, path, body) {
    const uid = currentUserId();
    const headers = { 'Content-Type': 'application/json', 'X-User-ID': uid };
    const options = { method, headers };
    if (body !== undefined && body !== null) {
      options.body = JSON.stringify(body);
    }

    let response;
    try {
      response = await fetch(apiBaseUrl + path, options);
    } catch (networkErr) {
      throw new Error('Network error: ' + networkErr.message);
    }

    let data;
    try {
      data = await response.json();
    } catch (parseErr) {
      throw new Error('Invalid JSON response from server (HTTP ' + response.status + ')');
    }

    if (!response.ok) {
      throw new Error(data.error || 'API error (HTTP ' + response.status + ')');
    }
    return data;
  }

  /**
   * Lightweight health-check.  Sets backendConnected and returns true/false.
   */
  async function checkBackend() {
    try {
      const data = await fetch(apiBaseUrl + '/api/health').then(function (r) { return r.json(); });
      backendConnected = (data && data.status === 'ok');
    } catch (e) {
      backendConnected = false;
    }
    return backendConnected;
  }

  // ---------------------------------------------------------------------------
  // FIELD MAP  (localStorage camelCase → API snake_case)
  // ---------------------------------------------------------------------------
  function entryToApiPayload(data) {
    return {
      title:           data.title,
      media_type:      data.mediaType,
      mood_id:         data.moodId || null,
      rating:          data.rating !== undefined ? data.rating : null,
      date_experienced: data.dateExperienced || null,
      notes:           data.notes || '',
      is_favorite:     Boolean(data.isFavorite),
      status:          data.status || STATUS.EXPERIENCED,
      item_id:         data.itemId || null,
      metadata:        data.metadata || {}
    };
  }

  function apiEntryToLocal(apiEntry) {
    return {
      id:              String(apiEntry.id),           // keep as string for compatibility
      _serverId:       apiEntry.id,                   // numeric DB id
      title:           apiEntry.title,
      mediaType:       apiEntry.media_type,
      mood:            apiEntry.mood_name || null,
      moodId:          apiEntry.mood_id   || null,
      rating:          apiEntry.rating    !== undefined ? apiEntry.rating : null,
      dateExperienced: apiEntry.date_experienced || null,
      notes:           apiEntry.notes     || '',
      isFavorite:      Boolean(apiEntry.is_favorite),
      status:          apiEntry.status,
      metadata:        apiEntry.metadata  || {},
      itemId:          apiEntry.item_id   || null,
      createdAt:       apiEntry.created_at || new Date().toISOString(),
      updatedAt:       apiEntry.updated_at || new Date().toISOString()
    };
  }

  function apiCollectionToLocal(apiCol) {
    return {
      id:          String(apiCol.id),
      _serverId:   apiCol.id,
      name:        apiCol.name,
      description: apiCol.description || '',
      itemIds:     (apiCol.item_ids || []).map(function (n) { return String(n); }),
      createdAt:   apiCol.created_at || new Date().toISOString(),
      updatedAt:   apiCol.updated_at || new Date().toISOString()
    };
  }

  // ---------------------------------------------------------------------------
  // SYNC  — load all data from backend into in-memory cache + localStorage
  // ---------------------------------------------------------------------------
  async function syncFromBackend() {
    const [apiEntries, apiCollections] = await Promise.all([
      apiRequest('GET', '/api/library'),
      apiRequest('GET', '/api/collections')
    ]);
    entries     = apiEntries.map(apiEntryToLocal);
    collections = apiCollections.map(apiCollectionToLocal);
    saveToStorage();
    saveCollectionsToStorage();
    logger.info('[Journal] Synced from backend: ' + entries.length + ' entries, ' + collections.length + ' collections.');
  }

  // ---------------------------------------------------------------------------
  // SAFE MIGRATION — push existing localStorage data to the backend
  // ---------------------------------------------------------------------------
  /**
   * Migrates localStorage entries and collections that have not yet been
   * uploaded.  Skips entries whose local ID is already in the migrated set.
   * Retries are handled by the caller (simply call migrateLocalData() again).
   *
   * Returns { migratedEntries, migratedCollections, errors }.
   * Does NOT delete local data until every entry migrates successfully.
   */
  async function migrateLocalData() {
    const localEntries     = loadFromStorage();
    const localCollections = loadCollectionsFromStorage();

    const migratedIds    = getMigratedIds();
    const migratedColIds = getMigratedColIds();

    const errors = [];

    // Map from old local id → new server id (for collection membership fixup)
    const idMap = {};

    // --- migrate entries ---
    for (const entry of localEntries) {
      if (migratedIds.has(entry.id)) {
        // Already uploaded; try to find the server id from existing entries
        const existing = entries.find(function (e) { return e.id === entry.id || e._localId === entry.id; });
        if (existing && existing._serverId) idMap[entry.id] = existing._serverId;
        continue;
      }

      try {
        const payload = entryToApiPayload({
          title:           entry.title,
          mediaType:       entry.mediaType,
          moodId:          entry.moodId || null,
          rating:          entry.rating,
          dateExperienced: entry.dateExperienced,
          notes:           entry.notes,
          isFavorite:      entry.isFavorite,
          status:          entry.status,
          metadata:        entry.metadata
        });
        const result = await apiRequest('POST', '/api/library', payload);
        idMap[entry.id] = result.id;
        migratedIds.add(entry.id);
        saveMigratedIds(migratedIds);
      } catch (err) {
        errors.push('Entry "' + entry.title + '": ' + err.message);
      }
    }

    // --- migrate collections ---
    for (const col of localCollections) {
      if (migratedColIds.has(col.id)) continue;

      try {
        const result = await apiRequest('POST', '/api/collections', {
          name:        col.name,
          description: col.description || ''
        });
        const serverColId = result.id;

        // Add items using the server IDs we just obtained
        for (const localItemId of (col.itemIds || [])) {
          const serverItemId = idMap[localItemId];
          if (!serverItemId) continue;
          try {
            await apiRequest('POST', '/api/collections/' + serverColId + '/items', { journal_id: serverItemId });
          } catch (itemErr) {
            errors.push('Collection "' + col.name + '" item ' + localItemId + ': ' + itemErr.message);
          }
        }

        migratedColIds.add(col.id);
        saveMigratedColIds(migratedColIds);
      } catch (err) {
        // 409 = duplicate name — collection probably already migrated; mark as done
        if (err.message && err.message.includes('already exists')) {
          migratedColIds.add(col.id);
          saveMigratedColIds(migratedColIds);
        } else {
          errors.push('Collection "' + col.name + '": ' + err.message);
        }
      }
    }

    // After migration re-sync from backend so in-memory cache is authoritative
    if (errors.length === 0) {
      try {
        await syncFromBackend();
      } catch (syncErr) {
        logger.warn('[Journal] Migration succeeded but re-sync failed:', syncErr);
      }
    }

    if (errors.length > 0) {
      logger.warn('[Journal] Migration completed with errors:', errors);
    } else {
      logger.info('[Journal] Migration complete.');
    }

    return {
      migratedEntries:     migratedIds.size,
      migratedCollections: migratedColIds.size,
      errors
    };
  }

  // ---------------------------------------------------------------------------
  // VALIDATION HELPER
  // ---------------------------------------------------------------------------
  function validateEntryInput(data, isUpdate) {
    const errors = [];
    if (!isUpdate || data.title !== undefined) {
      if (!data.title || typeof data.title !== 'string' || !data.title.trim()) {
        errors.push('Title is required and must be a non-empty string.');
      }
    }
    if (!isUpdate || data.mediaType !== undefined) {
      const validTypes = Object.values(MEDIA_TYPES);
      if (!validTypes.includes(data.mediaType)) {
        errors.push('Invalid mediaType "' + data.mediaType + '". Must be one of: ' + validTypes.join(', ') + '.');
      }
    }
    if (data.mood !== undefined && data.mood !== null) {
      if (!MOODS.includes(data.mood)) {
        errors.push('Invalid mood "' + data.mood + '". Must be one of: ' + MOODS.join(', ') + ' or null.');
      }
    }
    if (data.rating !== undefined && data.rating !== null) {
      const num = Number(data.rating);
      if (isNaN(num) || num < 0 || num > 5) {
        errors.push('Rating must be a number between 0 and 5.');
      }
    }
    if (data.status !== undefined) {
      const validStatuses = Object.values(STATUS);
      if (!validStatuses.includes(data.status)) {
        errors.push('Invalid status "' + data.status + '". Must be one of: ' + validStatuses.join(', ') + '.');
      }
    }
    return errors;
  }

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------
  const Journal = {
    MEDIA_TYPES,
    MOODS,
    STATUS,

    // Expose for UI to read
    get backendConnected() { return backendConnected; },
    get userId()           { return currentUserId(); },

    // ------------------------------------------------------------------
    // INITIALISATION
    // ------------------------------------------------------------------
    /**
     * Initialises the Journal store.
     * - Ensures a stable user UUID exists.
     * - Checks whether the backend is reachable.
     * - If connected: syncs data from the API and runs any pending migration.
     * - If offline: falls back to localStorage.
     *
     * @param {Object}  [options]
     * @param {boolean} [options.seedIfEmpty=false]  Load sample data when store is empty.
     * @param {string}  [options.apiBaseUrl]         Override the default API URL.
     * @returns {Promise<Array>} Current list of entries.
     */
    async init(options) {
      options = options || {};
      if (options.apiBaseUrl) apiBaseUrl = options.apiBaseUrl;

      // Ensure UUID is created and persisted before any network call
      getOrCreateUserId();

      // Load local data first so there is always something to show
      entries     = loadFromStorage();
      collections = loadCollectionsFromStorage();
      isInitialized = true;

      if (syncEnabled) {
        await checkBackend();
        if (backendConnected) {
          try {
            // Run migration for any unsynced local data (safe, no-op if already done)
            const localEntries = loadFromStorage();
            const migratedIds  = getMigratedIds();
            const hasUnmigrated = localEntries.some(function (e) { return !migratedIds.has(e.id); });

            if (hasUnmigrated) {
              logger.info('[Journal] Unmigrated local data detected. Running migration…');
              const migResult = await migrateLocalData();
              if (migResult.errors.length > 0) {
                logger.warn('[Journal] Partial migration — will retry on next load.', migResult.errors);
              }
            } else {
              await syncFromBackend();
            }
          } catch (err) {
            logger.warn('[Journal] Backend sync failed, using local data.', err);
            backendConnected = false;
          }
        }
      }

      if (options.seedIfEmpty && entries.length === 0) {
        await this.loadSampleData();
      }

      return this.getAllEntries();
    },

    // Synchronous initialisation for environments where async is not practical
    initSync(options) {
      options = options || {};
      if (options.apiBaseUrl) apiBaseUrl = options.apiBaseUrl;
      getOrCreateUserId();
      entries       = loadFromStorage();
      collections   = loadCollectionsFromStorage();
      isInitialized = true;
      if (options.seedIfEmpty && entries.length === 0) {
        this.loadSampleData();
      }
      return this.getAllEntries();
    },

    // ------------------------------------------------------------------
    // SUBSCRIPTION
    // ------------------------------------------------------------------
    subscribe(callback) {
      if (typeof callback !== 'function') return function () {};
      listeners.push(callback);
      callback(this.getAllEntries(), this.getAllCollections());
      return function () { listeners = listeners.filter(function (cb) { return cb !== callback; }); };
    },

    // ------------------------------------------------------------------
    // READ OPERATIONS (always from in-memory cache)
    // ------------------------------------------------------------------
    getAllEntries() {
      if (!isInitialized) this.initSync();
      return getAllEntriesSnapshot();
    },

    getEntry(id) {
      if (!isInitialized) this.initSync();
      const entry = entries.find(function (e) { return e.id === id || String(e._serverId) === String(id); });
      return entry ? JSON.parse(JSON.stringify(entry)) : null;
    },

    getHistory()   { return this.filterEntries({ status: STATUS.EXPERIENCED, sortBy: 'dateExperienced', sortOrder: 'desc' }); },
    getWishlist()  { return this.filterEntries({ status: STATUS.WISHLIST,    sortBy: 'createdAt',       sortOrder: 'desc' }); },
    getFavorites() { return this.filterEntries({ isFavorite: true }); },

    filterEntries(criteria) {
      if (!isInitialized) this.initSync();
      criteria = criteria || {};
      const {
        query     = '',
        mediaType = 'all',
        mood      = 'all',
        status    = 'all',
        isFavorite,
        minRating,
        sortBy    = 'createdAt',
        sortOrder = 'desc'
      } = criteria;

      const lq = query.trim().toLowerCase();

      let results = entries.filter(function (item) {
        if (lq) {
          const titleMatch   = item.title.toLowerCase().includes(lq);
          const notesMatch   = (item.notes || '').toLowerCase().includes(lq);
          const creatorMatch = item.metadata && item.metadata.creator
            ? item.metadata.creator.toLowerCase().includes(lq) : false;
          if (!titleMatch && !notesMatch && !creatorMatch) return false;
        }
        if (mediaType && mediaType !== 'all' && item.mediaType !== mediaType) return false;
        if (mood      && mood      !== 'all' && item.mood      !== mood)      return false;
        if (status    && status    !== 'all' && item.status    !== status)    return false;
        if (typeof isFavorite === 'boolean'  && item.isFavorite !== isFavorite) return false;
        if (minRating !== undefined && minRating !== null && minRating !== '') {
          if (item.rating === null || item.rating < Number(minRating)) return false;
        }
        return true;
      });

      results.sort(function (a, b) {
        let vA = a[sortBy]; let vB = b[sortBy];
        if (vA == null) vA = ''; if (vB == null) vB = '';
        if (typeof vA === 'string') return sortOrder === 'asc' ? vA.localeCompare(vB) : vB.localeCompare(vA);
        return sortOrder === 'asc' ? vA - vB : vB - vA;
      });

      return JSON.parse(JSON.stringify(results));
    },

    // ------------------------------------------------------------------
    // WRITE OPERATIONS — API-first, localStorage fallback
    // ------------------------------------------------------------------

    /**
     * Creates a new journal entry.
     * If the backend is connected the entry is created via the API and the
     * returned server ID is used.  On failure an error is thrown (no false
     * success is reported).
     */
    async createEntry(data) {
      data = data || {};
      if (!isInitialized) this.initSync();

      const errors = validateEntryInput(data, false);
      if (errors.length > 0) throw new Error('[Journal.createEntry] ' + errors.join(' '));

      const now = new Date().toISOString();

      if (backendConnected) {
        const result = await apiRequest('POST', '/api/library', entryToApiPayload(data));
        // Fetch the full entry back so we have all server-generated fields
        let serverEntry;
        try {
          serverEntry = await apiRequest('GET', '/api/library/' + result.id);
        } catch (e) {
          // If fetch fails build a minimal object from what we know
          serverEntry = Object.assign(entryToApiPayload(data), { id: result.id });
        }
        const local = apiEntryToLocal(serverEntry);
        entries.unshift(local);
        saveToStorage();
        return JSON.parse(JSON.stringify(local));
      }

      // Offline fallback
      const newEntry = {
        id:              generateId(),
        title:           data.title.trim(),
        mediaType:       data.mediaType,
        mood:            data.mood || null,
        moodId:          data.moodId || null,
        rating:          data.rating !== undefined && data.rating !== null ? Number(data.rating) : null,
        dateExperienced: data.dateExperienced || (data.status === STATUS.WISHLIST ? null : now.split('T')[0]),
        notes:           (data.notes || '').trim(),
        isFavorite:      Boolean(data.isFavorite),
        status:          data.status || STATUS.EXPERIENCED,
        metadata:        data.metadata && typeof data.metadata === 'object' ? data.metadata : {},
        createdAt:       now,
        updatedAt:       now
      };
      entries.unshift(newEntry);
      saveToStorage();
      return JSON.parse(JSON.stringify(newEntry));
    },

    /**
     * Updates an existing entry.
     * Throws on API or not-found errors so the UI is never given false success.
     */
    async updateEntry(id, updates) {
      updates = updates || {};
      if (!isInitialized) this.initSync();

      const existing = entries.find(function (e) { return e.id === id || String(e._serverId) === String(id); });
      if (!existing) throw new Error('[Journal.updateEntry] Entry with ID "' + id + '" not found.');

      const errors = validateEntryInput(updates, true);
      if (errors.length > 0) throw new Error('[Journal.updateEntry] ' + errors.join(' '));

      if (backendConnected && existing._serverId) {
        const payload = {};
        if (updates.title           !== undefined) payload.title            = updates.title;
        if (updates.mediaType       !== undefined) payload.media_type       = updates.mediaType;
        if (updates.moodId          !== undefined) payload.mood_id          = updates.moodId;
        if (updates.rating          !== undefined) payload.rating           = updates.rating;
        if (updates.dateExperienced !== undefined) payload.date_experienced = updates.dateExperienced;
        if (updates.notes           !== undefined) payload.notes            = updates.notes;
        if (updates.isFavorite      !== undefined) payload.is_favorite      = updates.isFavorite;
        if (updates.status          !== undefined) payload.status           = updates.status;
        if (updates.metadata        !== undefined) payload.metadata         = updates.metadata;

        await apiRequest('PUT', '/api/library/' + existing._serverId, payload);
      }

      const idx = entries.indexOf(existing);
      const updated = Object.assign({}, existing, updates, {
        id:        existing.id,
        createdAt: existing.createdAt,
        updatedAt: new Date().toISOString()
      });
      if (updates.title  !== undefined) updated.title  = updates.title.trim();
      if (updates.notes  !== undefined) updated.notes  = updates.notes.trim();
      if (updates.rating !== undefined) updated.rating = updates.rating !== null ? Number(updates.rating) : null;
      if (updates.isFavorite !== undefined) updated.isFavorite = Boolean(updates.isFavorite);

      entries[idx] = updated;
      saveToStorage();
      return JSON.parse(JSON.stringify(updated));
    },

    /**
     * Deletes an entry by ID (local id or server id).
     * Returns true if deleted, false if not found.
     */
    async deleteEntry(id) {
      if (!isInitialized) this.initSync();

      const existing = entries.find(function (e) { return e.id === id || String(e._serverId) === String(id); });
      if (!existing) return false;

      if (backendConnected && existing._serverId) {
        await apiRequest('DELETE', '/api/library/' + existing._serverId);
      }

      entries = entries.filter(function (e) { return e !== existing; });
      let colsChanged = false;
      collections.forEach(function (col) {
        if (col.itemIds.includes(id)) {
          col.itemIds = col.itemIds.filter(function (i) { return i !== id; });
          col.updatedAt = new Date().toISOString();
          colsChanged = true;
        }
      });
      saveToStorage();
      if (colsChanged) saveCollectionsToStorage();
      return true;
    },

    async toggleFavorite(id) {
      if (!isInitialized) this.initSync();
      const entry = this.getEntry(id);
      if (!entry) throw new Error('[Journal.toggleFavorite] Entry "' + id + '" not found.');

      if (backendConnected && entry._serverId) {
        await apiRequest('POST', '/api/library/' + entry._serverId + '/favorite');
      }
      return this.updateEntry(id, { isFavorite: !entry.isFavorite });
    },

    async toggleStatus(id) {
      if (!isInitialized) this.initSync();
      const entry = this.getEntry(id);
      if (!entry) throw new Error('[Journal.toggleStatus] Entry "' + id + '" not found.');

      if (backendConnected && entry._serverId) {
        await apiRequest('POST', '/api/library/' + entry._serverId + '/status');
      }

      const nextStatus = entry.status === STATUS.WISHLIST ? STATUS.EXPERIENCED : STATUS.WISHLIST;
      const upd = { status: nextStatus };
      if (nextStatus === STATUS.EXPERIENCED && !entry.dateExperienced) {
        upd.dateExperienced = new Date().toISOString().split('T')[0];
      }
      return this.updateEntry(id, upd);
    },

    async markAsExperienced(id, details) {
      details = details || {};
      return this.updateEntry(id, {
        status:          STATUS.EXPERIENCED,
        rating:          details.rating          !== undefined ? details.rating          : null,
        mood:            details.mood            !== undefined ? details.mood            : null,
        notes:           details.notes           !== undefined ? details.notes           : '',
        dateExperienced: details.dateExperienced || new Date().toISOString().split('T')[0]
      });
    },

    // ------------------------------------------------------------------
    // MOODS  — fetch from API when connected
    // ------------------------------------------------------------------
    async getMoodsFromAPI() {
      if (!backendConnected) return MOODS.map(function (name, i) { return { id: i + 1, name }; });
      return apiRequest('GET', '/api/moods');
    },

    // ------------------------------------------------------------------
    // COLLECTIONS — read
    // ------------------------------------------------------------------
    getAllCollections() {
      if (!isInitialized) this.initSync();
      return getAllCollectionsSnapshot();
    },

    getCollection(id) {
      if (!isInitialized) this.initSync();
      const col = collections.find(function (c) { return c.id === id || String(c._serverId) === String(id); });
      return col ? JSON.parse(JSON.stringify(col)) : null;
    },

    getCollectionItems(collectionId) {
      if (!isInitialized) this.initSync();
      const col = collections.find(function (c) { return c.id === collectionId; });
      if (!col) return [];
      return col.itemIds.map(function (id) { return Journal.getEntry(id); }).filter(Boolean);
    },

    getCollectionsForItem(itemId) {
      if (!isInitialized) this.initSync();
      return JSON.parse(JSON.stringify(collections.filter(function (c) { return c.itemIds.includes(itemId); })));
    },

    // ------------------------------------------------------------------
    // COLLECTIONS — write
    // ------------------------------------------------------------------
    async createCollection(data) {
      data = data || {};
      if (!isInitialized) this.initSync();

      if (!data.name || typeof data.name !== 'string' || !data.name.trim()) {
        throw new Error('[Journal.createCollection] Collection name is required.');
      }
      const trimmed = data.name.trim();
      if (collections.some(function (c) { return c.name.toLowerCase() === trimmed.toLowerCase(); })) {
        throw new Error('[Journal.createCollection] A collection named "' + trimmed + '" already exists.');
      }

      const now = new Date().toISOString();
      let newCol;

      if (backendConnected) {
        const result = await apiRequest('POST', '/api/collections', {
          name:        trimmed,
          description: (data.description || '').trim()
        });
        newCol = {
          id:          String(result.id),
          _serverId:   result.id,
          name:        trimmed,
          description: (data.description || '').trim(),
          itemIds:     [],
          createdAt:   now,
          updatedAt:   now
        };
      } else {
        newCol = {
          id:          generateCollectionId(),
          name:        trimmed,
          description: (data.description || '').trim(),
          itemIds:     [],
          createdAt:   now,
          updatedAt:   now
        };
      }

      // Seed with initial item IDs if supplied
      const rawItemIds = Array.isArray(data.itemIds) ? data.itemIds : [];
      for (const itemId of rawItemIds) {
        if (this.getEntry(itemId)) {
          try {
            await this.addItemToCollection(newCol.id, itemId);
          } catch (e) {
            logger.warn('[Journal] Could not add item ' + itemId + ' to new collection:', e);
          }
        }
      }

      collections.push(newCol);
      saveCollectionsToStorage();
      return JSON.parse(JSON.stringify(newCol));
    },

    async updateCollection(id, updates) {
      updates = updates || {};
      if (!isInitialized) this.initSync();

      const col = collections.find(function (c) { return c.id === id || String(c._serverId) === String(id); });
      if (!col) throw new Error('[Journal.updateCollection] Collection "' + id + '" not found.');

      if (updates.name !== undefined) {
        if (!updates.name || typeof updates.name !== 'string' || !updates.name.trim()) {
          throw new Error('[Journal.updateCollection] Collection name must be a non-empty string.');
        }
        const trimmed = updates.name.trim();
        if (collections.some(function (c) { return c.id !== id && c.name.toLowerCase() === trimmed.toLowerCase(); })) {
          throw new Error('[Journal.updateCollection] A collection named "' + trimmed + '" already exists.');
        }
        if (backendConnected && col._serverId) {
          await apiRequest('PUT', '/api/collections/' + col._serverId, {
            name:        trimmed,
            description: updates.description !== undefined ? updates.description : col.description
          });
        }
        col.name = trimmed;
      }
      if (updates.description !== undefined) col.description = (updates.description || '').trim();
      col.updatedAt = new Date().toISOString();
      saveCollectionsToStorage();
      return JSON.parse(JSON.stringify(col));
    },

    // Keep backward-compat alias
    async renameCollection(id, newName) {
      return this.updateCollection(id, { name: newName });
    },

    async deleteCollection(id) {
      if (!isInitialized) this.initSync();

      const col = collections.find(function (c) { return c.id === id || String(c._serverId) === String(id); });
      if (!col) return false;

      if (backendConnected && col._serverId) {
        await apiRequest('DELETE', '/api/collections/' + col._serverId);
      }

      collections = collections.filter(function (c) { return c !== col; });
      saveCollectionsToStorage();
      return true;
    },

    async addItemToCollection(collectionId, itemId) {
      if (!isInitialized) this.initSync();

      const col   = collections.find(function (c) { return c.id === collectionId || String(c._serverId) === String(collectionId); });
      if (!col) throw new Error('[Journal.addItemToCollection] Collection "' + collectionId + '" not found.');

      const entry = this.getEntry(itemId);
      if (!entry) throw new Error('[Journal.addItemToCollection] Entry "' + itemId + '" not found.');

      if (backendConnected && col._serverId && entry._serverId) {
        await apiRequest('POST', '/api/collections/' + col._serverId + '/items', { journal_id: entry._serverId });
      }

      if (!col.itemIds.includes(itemId)) {
        col.itemIds.push(itemId);
        col.updatedAt = new Date().toISOString();
        saveCollectionsToStorage();
      }
      return JSON.parse(JSON.stringify(col));
    },

    async removeItemFromCollection(collectionId, itemId) {
      if (!isInitialized) this.initSync();

      const col   = collections.find(function (c) { return c.id === collectionId || String(c._serverId) === String(collectionId); });
      if (!col) throw new Error('[Journal.removeItemFromCollection] Collection "' + collectionId + '" not found.');

      const entry = entries.find(function (e) { return e.id === itemId || String(e._serverId) === String(itemId); });

      if (backendConnected && col._serverId && entry && entry._serverId) {
        await apiRequest('DELETE', '/api/collections/' + col._serverId + '/items/' + entry._serverId);
      }

      const before = col.itemIds.length;
      col.itemIds = col.itemIds.filter(function (i) { return i !== itemId; });
      if (col.itemIds.length !== before) {
        col.updatedAt = new Date().toISOString();
        saveCollectionsToStorage();
      }
      return JSON.parse(JSON.stringify(col));
    },

    async setCollectionsForItem(itemId, targetCollectionIds) {
      if (!isInitialized) this.initSync();
      targetCollectionIds = targetCollectionIds || [];

      const entry = this.getEntry(itemId);
      if (!entry) throw new Error('[Journal.setCollectionsForItem] Entry "' + itemId + '" not found.');

      const targetSet = new Set(targetCollectionIds);
      for (const col of collections) {
        const hasItem    = col.itemIds.includes(itemId);
        const shouldHave = targetSet.has(col.id);
        if (shouldHave && !hasItem) {
          await this.addItemToCollection(col.id, itemId);
        } else if (!shouldHave && hasItem) {
          await this.removeItemFromCollection(col.id, itemId);
        }
      }
      return this.getCollectionsForItem(itemId);
    },

    // ------------------------------------------------------------------
    // STATS
    // ------------------------------------------------------------------
    getStats() {
      if (!isInitialized) this.initSync();
      let experiencedCount = 0, wishlistCount = 0, favoritesCount = 0,
          totalRating = 0, ratedCount = 0;
      const byMediaType = { movie: 0, tv: 0, music: 0, game: 0 };
      const byMood = {};
      MOODS.forEach(function (m) { byMood[m] = 0; });

      entries.forEach(function (item) {
        if (item.status === STATUS.EXPERIENCED) experiencedCount++;
        if (item.status === STATUS.WISHLIST)    wishlistCount++;
        if (item.isFavorite) favoritesCount++;
        if (byMediaType[item.mediaType] !== undefined) byMediaType[item.mediaType]++;
        if (item.mood && byMood[item.mood] !== undefined) byMood[item.mood]++;
        if (item.rating !== null && item.rating !== undefined) { totalRating += Number(item.rating); ratedCount++; }
      });

      let topMood = null, maxMoodCount = 0;
      for (const [m, count] of Object.entries(byMood)) {
        if (count > maxMoodCount) { maxMoodCount = count; topMood = m; }
      }

      return {
        total:            entries.length,
        experiencedCount, wishlistCount, favoritesCount, ratedCount,
        averageRating:    ratedCount > 0 ? Number((totalRating / ratedCount).toFixed(1)) : null,
        byMediaType, byMood, topMood,
        collectionsCount: collections.length
      };
    },

    // ------------------------------------------------------------------
    // SAMPLE DATA
    // ------------------------------------------------------------------
    async loadSampleData() {
      for (const sample of SAMPLE_ENTRIES) {
        const exists = entries.some(function (e) { return e.title.toLowerCase() === sample.title.toLowerCase(); });
        if (!exists) {
          try { await this.createEntry(sample); } catch (e) { logger.warn('[Journal] Sample entry error:', e); }
        }
      }
      if (collections.length === 0) {
        for (const sc of SAMPLE_COLLECTIONS) {
          const matchedIds = entries
            .filter(function (e) { return sc.itemTitles.includes(e.title); })
            .map(function (e) { return e.id; });
          try { await this.createCollection({ name: sc.name, description: sc.description, itemIds: matchedIds }); }
          catch (e) { logger.warn('[Journal] Sample collection error:', e); }
        }
      }
      return this.getAllEntries();
    },

    // ------------------------------------------------------------------
    // EXPORT / IMPORT
    // ------------------------------------------------------------------
    exportToJSON() {
      return JSON.stringify({ version: 2, entries: this.getAllEntries(), collections: this.getAllCollections() }, null, 2);
    },

    importFromJSON(jsonString, options) {
      options = options || { merge: true };
      try {
        const parsed = JSON.parse(jsonString);
        let rawEntries = [], rawCollections = [];
        if (Array.isArray(parsed)) {
          rawEntries = parsed;
        } else if (parsed && typeof parsed === 'object') {
          if (Array.isArray(parsed.entries))     rawEntries     = parsed.entries;
          if (Array.isArray(parsed.collections)) rawCollections = parsed.collections;
        } else {
          throw new Error('Import data must be a JSON array of entries or an object containing entries.');
        }

        const validEntries = [], errors = [];
        rawEntries.forEach(function (item, idx) {
          const errs = validateEntryInput(item, false);
          if (errs.length > 0) {
            errors.push('Item #' + (idx + 1) + ' ("' + (item.title || 'Untitled') + '"): ' + errs.join(' '));
          } else {
            const now = new Date().toISOString();
            validEntries.push({
              id:              item.id || generateId(),
              title:           item.title.trim(),
              mediaType:       item.mediaType,
              mood:            item.mood || null,
              rating:          item.rating !== null && item.rating !== undefined ? Number(item.rating) : null,
              dateExperienced: item.dateExperienced || (item.status === STATUS.WISHLIST ? null : now.split('T')[0]),
              notes:           (item.notes || '').trim(),
              isFavorite:      Boolean(item.isFavorite),
              status:          item.status || STATUS.EXPERIENCED,
              metadata:        item.metadata && typeof item.metadata === 'object' ? item.metadata : {},
              createdAt:       item.createdAt || now,
              updatedAt:       item.updatedAt || now
            });
          }
        });

        const validCollections = [];
        rawCollections.forEach(function (col, idx) {
          if (col && typeof col === 'object' && col.name && col.name.trim()) {
            const now = new Date().toISOString();
            validCollections.push({
              id:          col.id || generateCollectionId(),
              name:        col.name.trim(),
              description: (col.description || '').trim(),
              itemIds:     Array.isArray(col.itemIds) ? [...new Set(col.itemIds)] : [],
              createdAt:   col.createdAt || now,
              updatedAt:   col.updatedAt || now
            });
          } else {
            errors.push('Collection #' + (idx + 1) + ': Name is required.');
          }
        });

        if (options.merge) {
          const eMap = new Map(entries.map(function (e) { return [e.id, e]; }));
          validEntries.forEach(function (v) { eMap.set(v.id, v); });
          entries = Array.from(eMap.values());
          const cMap = new Map(collections.map(function (c) { return [c.id, c]; }));
          validCollections.forEach(function (c) { cMap.set(c.id, c); });
          collections = Array.from(cMap.values());
        } else {
          entries     = validEntries;
          collections = validCollections;
        }

        saveToStorage();
        saveCollectionsToStorage();
        return { success: true, imported: validEntries.length, importedCollections: validCollections.length, errors };
      } catch (err) {
        return { success: false, imported: 0, importedCollections: 0, errors: [err.message] };
      }
    },

    // ------------------------------------------------------------------
    // MIGRATION (public — callable from UI to retry)
    // ------------------------------------------------------------------
    migrateLocalData,

    // ------------------------------------------------------------------
    // CONFIGURATION
    // ------------------------------------------------------------------
    configure(opts) {
      opts = opts || {};
      if (opts.apiBaseUrl   !== undefined) apiBaseUrl   = opts.apiBaseUrl;
      if (opts.syncEnabled  !== undefined) syncEnabled   = Boolean(opts.syncEnabled);
    },

    // ------------------------------------------------------------------
    // UTILITIES
    // ------------------------------------------------------------------
    clearAll() {
      entries     = [];
      collections = [];
      saveToStorage();
      saveCollectionsToStorage();
    }
  };

  return Journal;
});
