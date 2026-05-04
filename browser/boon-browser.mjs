const DEFAULT_DB_NAME = "boon-zig-browser";
const DEFAULT_STORE_NAME = "state";

export class MemoryIndexedDb {
  constructor() {
    this.map = new Map();
  }

  async get(key) {
    return this.map.has(key) ? structuredClone(this.map.get(key)) : null;
  }

  async set(key, value) {
    this.map.set(key, structuredClone(value));
  }

  async clear(key) {
    this.map.delete(key);
  }
}

export async function createIndexedDbStore(options = {}) {
  if (typeof indexedDB === "undefined") {
    return new MemoryIndexedDb();
  }

  const dbName = options.dbName ?? DEFAULT_DB_NAME;
  const storeName = options.storeName ?? DEFAULT_STORE_NAME;
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, 1);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(storeName)) {
        database.createObjectStore(storeName);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("indexedDB open failed"));
  });

  return {
    async get(key) {
      return transact(db, storeName, "readonly", (store) => store.get(key));
    },
    async set(key, value) {
      await transact(db, storeName, "readwrite", (store) => store.put(value, key));
    },
    async clear(key) {
      await transact(db, storeName, "readwrite", (store) => store.delete(key));
    },
  };
}

function transact(db, storeName, mode, action) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode);
    const store = tx.objectStore(storeName);
    const request = action(store);
    request.onsuccess = () => resolve(request.result ?? null);
    request.onerror = () => reject(request.error ?? new Error("indexedDB transaction failed"));
  });
}

const PHYSICAL_THEMES = ["Professional", "Glassmorphism", "Neobrutalism", "Neumorphism"];
const PHYSICAL_THEME_LABELS = {
  Professional: "Professional",
  Glassmorphism: "Glass",
  Neobrutalism: "Brutalist",
  Neumorphism: "Neumorphic",
};

const WASM_PAYLOAD_TAGS = {
  pulse: 0,
  number: 1,
  text: 2,
  bool: 3,
  json: 4,
};

function wasmPayloadTag(payload) {
  if (payload === "pulse" || payload == null) return WASM_PAYLOAD_TAGS.pulse;
  if (typeof payload === "number") return WASM_PAYLOAD_TAGS.number;
  if (typeof payload === "string") return WASM_PAYLOAD_TAGS.text;
  if (typeof payload === "boolean") return WASM_PAYLOAD_TAGS.bool;
  return WASM_PAYLOAD_TAGS.json;
}

function wasmPayloadScalar(payload) {
  if (typeof payload === "number") return payload;
  if (typeof payload === "boolean") return payload ? 1 : 0;
  return 0;
}

export class WasmHostBoundary {
  constructor({ exports = {}, sourceBindings = {}, decodeJson = null } = {}) {
    this.exports = exports;
    this.sourceBindings = sourceBindings;
    this.decodeJson = decodeJson;
    this.dispatched = [];
  }

  dispatchSource(event) {
    this.dispatched.push({ ...event });
    const dispatch = this.exports.dispatch_source ?? this.exports.dispatchSource;
    if (typeof dispatch !== "function") {
      return;
    }
    dispatch(
      event.sourceSlotId,
      event.bindingId,
      wasmPayloadTag(event.payload),
      wasmPayloadScalar(event.payload),
    );
  }

  snapshotPhysicalRenderTarget() {
    const objectSnapshot = this.exports.snapshot_physical_render_target ?? this.exports.snapshotPhysicalRenderTarget;
    if (typeof objectSnapshot === "function") {
      return objectSnapshot();
    }

    const jsonSnapshot = this.exports.snapshot_physical_render_target_json ?? this.exports.snapshotPhysicalRenderTargetJson;
    if (typeof jsonSnapshot === "function" && typeof this.decodeJson === "function") {
      return this.decodeJson(jsonSnapshot());
    }
    return null;
  }
}

export function createWasmHostBoundary(options = {}) {
  return new WasmHostBoundary(options);
}

function createFetchPhysicalStateProvider(baseUrl) {
  if (typeof fetch !== "function" || !baseUrl) {
    return null;
  }
  return async ({ theme, mode }) => {
    const url = new URL(baseUrl, globalThis.location?.href ?? "http://127.0.0.1/");
    url.searchParams.set("theme", theme);
    url.searchParams.set("mode", mode);
    const response = await fetch(url.toString(), { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`physical-state fetch failed: ${response.status}`);
    }
    return await response.json();
  };
}

function defaultPhysicalStateProvider() {
  const explicitBaseUrl = globalThis.__boonPhysicalStateBaseUrl ?? null;
  if (explicitBaseUrl) {
    return createFetchPhysicalStateProvider(explicitBaseUrl);
  }
  if (typeof globalThis.location === "object" && globalThis.location) {
    return createFetchPhysicalStateProvider("/__boon/physical-state");
  }
  return null;
}

export function createFetchRenderedTextProvider(baseUrl = "/__boon/render-text") {
  if (typeof fetch !== "function" || !baseUrl) {
    return null;
  }
  return async () => {
    const url = new URL(baseUrl, globalThis.location?.href ?? "http://127.0.0.1/");
    const response = await fetch(url.toString(), { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`render-text fetch failed: ${response.status}`);
    }
    return await response.text();
  };
}

function projectKey(sourceName) {
  return `source:${sourceName}`;
}

export class BrowserHost {
  constructor({
    sourceName,
    storage,
    root = null,
    physicalRenderTargets = null,
    physicalStateProvider = null,
    renderedTextProvider = null,
    hostBoundary = null,
  }) {
    this.sourceName = sourceName ?? "served-source";
    this.storage = storage;
    this.root = root;
    this.physicalRenderTargets = physicalRenderTargets;
    this.physicalStateProvider = physicalStateProvider;
    this.renderedTextProvider = renderedTextProvider;
    this.renderedText = "";
    this.physicalTheme = "Professional";
    this.physicalMode = "Light";
    this.currentPhysicalRenderTarget = null;
    this.hostBoundary = hostBoundary;
    this.sourceBindings = hostBoundary?.sourceBindings ?? {};
    this.sourceEventTrace = [];
  }

  async init() {
    const stored = await this.storage.get(projectKey(this.sourceName));
    if (stored && typeof stored.theme === "string" && typeof stored.mode === "string") {
      this.physicalTheme = stored.theme;
      this.physicalMode = stored.mode;
    }
    await this.refreshRenderedText();
    await this.refreshPhysicalRenderTarget();
    this.render();
    return this;
  }

  isRenderedTextHost() {
    return this.renderedTextProvider != null;
  }

  isPhysicalHost() {
    return this.currentPhysicalRenderTarget != null ||
      this.physicalStateProvider != null ||
      this.physicalRenderTargets != null ||
      this.hostBoundary != null;
  }

  async refreshRenderedText() {
    if (!this.renderedTextProvider) return;
    this.renderedText = await this.renderedTextProvider();
  }

  async refreshPhysicalRenderTarget() {
    if (!this.isPhysicalHost()) {
      return;
    }
    if (this.hostBoundary && typeof this.hostBoundary.snapshotPhysicalRenderTarget === "function") {
      const target = this.hostBoundary.snapshotPhysicalRenderTarget();
      if (target) {
        this.currentPhysicalRenderTarget = target;
        return;
      }
    }
    if (this.physicalStateProvider) {
      try {
        this.currentPhysicalRenderTarget = await this.physicalStateProvider({
          sourceName: this.sourceName,
          theme: this.physicalTheme,
          mode: this.physicalMode,
        });
        return;
      } catch {}
    }
    this.currentPhysicalRenderTarget = this.physicalRenderTargets?.[this.physicalTheme]
      ?? this.physicalRenderTargets?.Professional
      ?? null;
  }

  physicalRenderTarget() {
    if (!this.currentPhysicalRenderTarget) {
      throw new Error(`${this.sourceName} has no physical render target`);
    }
    return this.currentPhysicalRenderTarget;
  }

  physicalSnapshot() {
    const target = this.physicalRenderTarget();
    const rows = target?.rows;
    if (!Array.isArray(rows) || rows.length === 0) {
      return "physical renderer unavailable";
    }
    return rows.join("\n");
  }

  textContent() {
    const parts = [];
    if (this.isRenderedTextHost()) {
      parts.push(this.renderedText);
    }
    if (this.currentPhysicalRenderTarget) {
      parts.push(`${this.physicalTheme}${this.physicalMode}${this.physicalSnapshot()}`);
    }
    if (parts.length === 0) {
      throw new Error(`${this.sourceName} has no browser render provider`);
    }
    return parts.join("");
  }

  sourceBindingFor(semanticId) {
    return this.sourceBindings[semanticId] ?? null;
  }

  dispatchBrowserSource(semanticId, payload = "pulse") {
    const binding = this.sourceBindingFor(semanticId);
    if (!binding) {
      return null;
    }
    const event = {
      semanticId,
      sourceSlotId: binding.sourceSlotId,
      bindingId: binding.bindingId,
      payload,
    };
    this.sourceEventTrace.push(event);
    if (this.hostBoundary && typeof this.hostBoundary.dispatchSource === "function") {
      this.hostBoundary.dispatchSource(event);
    }
    return event;
  }

  async clearState() {
    await this.storage.clear(projectKey(this.sourceName));
    this.physicalTheme = "Professional";
    this.physicalMode = "Light";
    await this.refreshRenderedText();
    await this.refreshPhysicalRenderTarget();
    this.render();
  }

  async setPhysicalTheme(themeName) {
    if (!this.isPhysicalHost()) {
      throw new Error(`${this.sourceName} does not support setPhysicalTheme`);
    }
    if (!PHYSICAL_THEMES.includes(themeName)) {
      throw new Error(`unsupported physical theme ${themeName}`);
    }
    this.physicalTheme = themeName;
    await this.persistPhysicalState();
  }

  async togglePhysicalMode() {
    if (!this.isPhysicalHost()) {
      throw new Error(`${this.sourceName} does not support togglePhysicalMode`);
    }
    this.physicalMode = this.physicalMode === "Light" ? "Dark" : "Light";
    await this.persistPhysicalState();
  }

  async persistPhysicalState() {
    await this.storage.set(projectKey(this.sourceName), {
      theme: this.physicalTheme,
      mode: this.physicalMode,
    });
    await this.refreshPhysicalRenderTarget();
    this.render();
  }

  render() {
    if (!this.root) return;
    this.root.className = "browser-shell";
    while (this.root.firstChild) {
      this.root.removeChild(this.root.firstChild);
    }

    if (this.isRenderedTextHost()) {
      const output = document.createElement("output");
      output.textContent = this.renderedText;
      this.root.append(output);
    }

    if (this.currentPhysicalRenderTarget) {
      const shell = document.createElement("section");
      shell.className = "physical-shell";

      const title = document.createElement("h1");
      title.textContent = this.sourceName;

      const controls = document.createElement("div");
      controls.className = "physical-controls";
      for (const themeName of PHYSICAL_THEMES) {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = PHYSICAL_THEME_LABELS[themeName] ?? themeName;
        if (themeName === this.physicalTheme) button.className = "active";
        button.addEventListener("click", () => {
          void this.setPhysicalTheme(themeName);
        });
        controls.append(button);
      }

      const modeButton = document.createElement("button");
      modeButton.type = "button";
      modeButton.textContent = `${this.physicalMode} mode`;
      modeButton.addEventListener("click", () => {
        void this.togglePhysicalMode();
      });
      controls.append(modeButton);

      const panel = document.createElement("pre");
      panel.className = "physical-panel";
      panel.textContent = this.physicalSnapshot();

      shell.append(title, controls, panel);
      this.root.append(shell);
    }
  }
}

async function loadBundleManifest() {
  if (typeof fetch !== "function") {
    return null;
  }
  try {
    const response = await fetch("manifest.json", { cache: "no-store" });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

export async function createHost({
  sourceName = null,
  storage,
  root = null,
  physicalRenderTargets = null,
  physicalStateProvider = null,
  renderedTextProvider = null,
  hostBoundary = null,
}) {
  const resolvedStorage = storage ?? (await createIndexedDbStore());
  const resolvedPhysicalStateProvider = physicalStateProvider ?? defaultPhysicalStateProvider();
  const host = new BrowserHost({
    sourceName,
    storage: resolvedStorage,
    root,
    physicalRenderTargets,
    physicalStateProvider: resolvedPhysicalStateProvider,
    renderedTextProvider,
    hostBoundary,
  });
  return host.init();
}

export async function mountExampleFromLocation(root) {
  const manifest = await loadBundleManifest();
  const params = new URLSearchParams(globalThis.location?.search ?? "");
  const sourceName = params.get("source") ?? manifest?.served_source?.name ?? "served-source";
  const renderedTextProvider = createFetchRenderedTextProvider(manifest?.render_text_endpoint ?? "/__boon/render-text");
  const physicalStateProvider =
    typeof globalThis.__boonPhysicalStateProvider === "function"
      ? globalThis.__boonPhysicalStateProvider
      : defaultPhysicalStateProvider();
  return createHost({
    sourceName,
    root,
    physicalRenderTargets: manifest?.physical_render_targets ?? null,
    physicalStateProvider,
    renderedTextProvider,
    hostBoundary: globalThis.__boonWasmHostBoundary ?? null,
  });
}
