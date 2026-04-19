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

function exampleKey(exampleName) {
  return `example:${exampleName}`;
}

const PHYSICAL_THEMES = ["Professional", "Glassmorphism", "Neobrutalism", "Neumorphism"];
const PHYSICAL_THEME_LABELS = {
  Professional: "Professional",
  Glassmorphism: "Glass",
  Neobrutalism: "Brutalist",
  Neumorphism: "Neumorphic",
};

function createFetchPhysicalStateProvider(baseUrl) {
  if (typeof fetch !== "function" || !baseUrl) {
    return null;
  }
  return async ({ exampleName, theme, mode }) => {
    const url = new URL(baseUrl, globalThis.location?.href ?? "http://127.0.0.1/");
    url.searchParams.set("example", exampleName);
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

export class BrowserHost {
  constructor({
    exampleName,
    storage,
    root = null,
    visualMode = false,
    physicalRenderTargets = null,
    physicalStateProvider = null,
  }) {
    this.exampleName = exampleName;
    this.storage = storage;
    this.root = root;
    this.visualMode = visualMode;
    this.physicalRenderTargets = physicalRenderTargets;
    this.physicalStateProvider = physicalStateProvider;
    this.virtualTimeMs = 0;
    this.intervalTicks = 0;
    this.counterValue = 0;
    this.todoItems = [];
    this.todoRoute = "all";
    this.sheetOverrides = new Map();
    this.editingCell = null;
    this.physicalTheme = "Professional";
    this.physicalMode = "Light";
    this.currentPhysicalRenderTarget = null;
  }

  isCellsExample() {
    return this.exampleName === "cells" || this.exampleName === "cells_dynamic";
  }

  physicalRenderTarget() {
    if (this.exampleName !== "todo_mvc_physical") {
      throw new Error(`${this.exampleName} does not support physicalRenderTarget()`);
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

  async init() {
    if (this.exampleName === "counter") {
      const stored = await this.storage.get(exampleKey(this.exampleName));
      if (stored && typeof stored.count === "number") {
        this.counterValue = stored.count;
      }
    } else if (this.isCellsExample()) {
      const stored = await this.storage.get(exampleKey(this.exampleName));
      this.sheetOverrides = new Map(Object.entries(stored?.overrides ?? {}));
      this.editingCell = null;
    } else if (this.exampleName === "todo_mvc") {
      const stored = await this.storage.get(exampleKey(this.exampleName));
      if (stored && Array.isArray(stored.items) && typeof stored.route === "string") {
        this.todoItems = stored.items.map((item) => ({
          title: String(item.title),
          completed: Boolean(item.completed),
        }));
        this.todoRoute = stored.route;
      } else if (this.visualMode) {
        this.todoItems = [
          { title: "Buy groceries", completed: false },
          { title: "Walk the dog", completed: false },
          { title: "Finish TodoMVC renderer", completed: true },
          { title: "Read documentation", completed: false },
        ];
        this.todoRoute = "all";
      } else {
        this.todoItems = [
          { title: "Buy groceries", completed: false },
          { title: "Clean room", completed: false },
        ];
        this.todoRoute = "all";
      }
    } else if (this.exampleName === "todo_mvc_physical") {
      const stored = await this.storage.get(exampleKey(this.exampleName));
      if (stored && typeof stored.theme === "string" && typeof stored.mode === "string") {
        this.physicalTheme = stored.theme;
        this.physicalMode = stored.mode;
      }
      await this.refreshPhysicalRenderTarget();
    }
    this.render();
    return this;
  }

  async refreshPhysicalRenderTarget() {
    if (this.exampleName !== "todo_mvc_physical") {
      return;
    }
    if (this.physicalStateProvider) {
      try {
        this.currentPhysicalRenderTarget = await this.physicalStateProvider({
          exampleName: this.exampleName,
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

  textContent() {
    if (this.exampleName === "counter") {
      return `${this.counterValue}+`;
    }
    if (this.exampleName === "interval") {
      return `${this.intervalTicks}`;
    }
    if (this.exampleName === "todo_mvc") {
      const visibleItems = this.visibleTodoItems();
      const itemsLeft = this.todoItems.filter((item) => !item.completed).length;
      return [
        "todos",
        ...visibleItems.map((item) => item.title),
        `${itemsLeft}itemsleft`,
        "All",
        "Active",
        "Completed",
        "Double-click to edit a todo",
        "Created by Martin Kavík",
        "Part of TodoMVC",
      ].join("");
    }
    if (this.isCellsExample()) {
      const title = this.exampleName === "cells_dynamic" ? "Cells Dynamic" : "Cells";
      const columns = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
      const parts = [title, columns];
      for (let row = 1; row <= 100; row += 1) {
        parts.push(`${row}`);
        for (let col = 1; col <= 26; col += 1) {
          const value = this.cellDisplayText(row, col);
          if (value !== "") parts.push(value);
        }
      }
      return parts.join("");
    }
    if (this.exampleName === "todo_mvc_physical") {
      return `${this.physicalTheme}${this.physicalMode}${this.physicalSnapshot()}`;
    }
    throw new Error(`unsupported example ${this.exampleName}`);
  }

  async click(label) {
    if (this.exampleName !== "counter") {
      throw new Error(`${this.exampleName} does not support click(${label})`);
    }
    if (label !== "+") {
      throw new Error(`unsupported counter click label ${label}`);
    }
    this.counterValue += 1;
    await this.storage.set(exampleKey(this.exampleName), { count: this.counterValue });
    this.render();
  }

  async clearState() {
    await this.storage.clear(exampleKey(this.exampleName));
    if (this.exampleName === "counter") {
      this.counterValue = 0;
    } else if (this.isCellsExample()) {
      this.sheetOverrides = new Map();
      this.editingCell = null;
    } else if (this.exampleName === "interval") {
      this.intervalTicks = 0;
      this.virtualTimeMs = 0;
    } else if (this.exampleName === "todo_mvc") {
      this.todoItems = [
        { title: "Buy groceries", completed: false },
        { title: "Clean room", completed: false },
      ];
      this.todoRoute = "all";
    } else if (this.exampleName === "todo_mvc_physical") {
      this.physicalTheme = "Professional";
      this.physicalMode = "Light";
    }
    this.render();
  }

  cellKey(row, col) {
    return `${row},${col}`;
  }

  rawCellValue(row, col) {
    const override = this.sheetOverrides.get(this.cellKey(row, col));
    if (override != null) return String(override);
    if (row === 1 && col === 1) return "5";
    if (row === 1 && col === 2) return `${this.numberCellValue(1, 1) + 10}`;
    if (row === 1 && col === 3) return `${this.numberCellValue(1, 1) + 25}`;
    if (row === 2 && col === 1) return "10";
    if (row === 3 && col === 1) return "15";
    return "";
  }

  cellDisplayText(row, col) {
    if (this.editingCell && this.editingCell.row === row && this.editingCell.col === col) {
      return this.editingCell.text;
    }
    return this.rawCellValue(row, col);
  }

  numberCellValue(row, col) {
    const value = Number(this.rawCellValue(row, col));
    return Number.isFinite(value) ? value : 0;
  }

  async persistCells() {
    await this.storage.set(exampleKey(this.exampleName), {
      overrides: Object.fromEntries(this.sheetOverrides.entries()),
    });
    this.render();
  }

  async startEditCell(row, col) {
    if (!this.isCellsExample()) {
      throw new Error(`${this.exampleName} does not support startEditCell`);
    }
    this.editingCell = { row, col, text: this.rawCellValue(row, col) };
    this.render();
  }

  async setEditingText(text) {
    if (!this.isCellsExample()) {
      throw new Error(`${this.exampleName} does not support setEditingText`);
    }
    if (!this.editingCell) {
      throw new Error("no cell is currently being edited");
    }
    this.editingCell = { ...this.editingCell, text: String(text) };
    this.render();
  }

  async commitEditingCell() {
    if (!this.isCellsExample()) {
      throw new Error(`${this.exampleName} does not support commitEditingCell`);
    }
    if (!this.editingCell) return;
    const { row, col, text } = this.editingCell;
    this.sheetOverrides.set(this.cellKey(row, col), String(text));
    this.editingCell = null;
    await this.persistCells();
  }

  cancelEditingCell() {
    if (!this.isCellsExample()) {
      throw new Error(`${this.exampleName} does not support cancelEditingCell`);
    }
    this.editingCell = null;
    this.render();
  }

  async advanceVirtualTime(ms) {
    if (this.exampleName !== "interval") {
      throw new Error(`${this.exampleName} does not support virtual time`);
    }
    this.virtualTimeMs += ms;
    this.intervalTicks = Math.floor(this.virtualTimeMs / 1000);
    this.render();
  }

  async addTodo(title) {
    if (this.exampleName !== "todo_mvc") {
      throw new Error(`${this.exampleName} does not support addTodo`);
    }
    const trimmed = String(title).trim();
    if (!trimmed) return;
    this.todoItems.push({ title: trimmed, completed: false });
    await this.persistTodos();
  }

  async toggleTodo(index) {
    if (this.exampleName !== "todo_mvc") {
      throw new Error(`${this.exampleName} does not support toggleTodo`);
    }
    const item = this.todoItems[index];
    if (!item) {
      throw new Error(`todo index out of range: ${index}`);
    }
    item.completed = !item.completed;
    await this.persistTodos();
  }

  async clearCompleted() {
    if (this.exampleName !== "todo_mvc") {
      throw new Error(`${this.exampleName} does not support clearCompleted`);
    }
    this.todoItems = this.todoItems.filter((item) => !item.completed);
    await this.persistTodos();
  }

  async setRoute(route) {
    if (this.exampleName !== "todo_mvc") {
      throw new Error(`${this.exampleName} does not support setRoute`);
    }
    if (!["all", "active", "completed"].includes(route)) {
      throw new Error(`unsupported todo route ${route}`);
    }
    this.todoRoute = route;
    await this.persistTodos();
  }

  visibleTodoItems() {
    if (this.todoRoute === "active") {
      return this.todoItems.filter((item) => !item.completed);
    }
    if (this.todoRoute === "completed") {
      return this.todoItems.filter((item) => item.completed);
    }
    return this.todoItems;
  }

  async persistTodos() {
    await this.storage.set(exampleKey(this.exampleName), {
      items: this.todoItems,
      route: this.todoRoute,
    });
    this.render();
  }

  async setPhysicalTheme(themeName) {
    if (this.exampleName !== "todo_mvc_physical") {
      throw new Error(`${this.exampleName} does not support setPhysicalTheme`);
    }
    if (!PHYSICAL_THEMES.includes(themeName)) {
      throw new Error(`unsupported physical theme ${themeName}`);
    }
    this.physicalTheme = themeName;
    await this.persistPhysicalState();
  }

  async togglePhysicalMode() {
    if (this.exampleName !== "todo_mvc_physical") {
      throw new Error(`${this.exampleName} does not support togglePhysicalMode`);
    }
    this.physicalMode = this.physicalMode === "Light" ? "Dark" : "Light";
    await this.persistPhysicalState();
  }

  async persistPhysicalState() {
    await this.storage.set(exampleKey(this.exampleName), {
      theme: this.physicalTheme,
      mode: this.physicalMode,
    });
    await this.refreshPhysicalRenderTarget();
    this.render();
  }

  render() {
    if (!this.root) return;
    this.root.className = "";
    while (this.root.firstChild) {
      this.root.removeChild(this.root.firstChild);
    }

    if (this.exampleName === "counter") {
      this.root.className = "browser-shell";
      const output = document.createElement("output");
      output.textContent = `${this.counterValue}`;
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = "+";
      button.addEventListener("click", () => {
        void this.click("+");
      });
      this.root.append(output, button);
      return;
    }

    if (this.exampleName === "interval") {
      this.root.className = "browser-shell";
      const output = document.createElement("output");
      output.textContent = `${this.intervalTicks}`;
      this.root.append(output);
      return;
    }

    if (this.exampleName === "todo_mvc") {
      this.root.className = this.visualMode ? "todo-visual-shell" : "browser-shell";
      const app = document.createElement("section");
      app.className = "todoapp";
      const title = document.createElement("h1");
      title.textContent = "todos";
      app.append(title);

      const header = document.createElement("header");
      header.className = "header";
      const input = document.createElement("input");
      input.className = "new-todo";
      input.placeholder = "What needs to be done?";
      input.value = "";
      header.append(input);
      app.append(header);

      const main = document.createElement("section");
      main.className = "main";
      const toggleAll = document.createElement("input");
      toggleAll.className = "toggle-all";
      toggleAll.type = "checkbox";
      toggleAll.id = "toggle-all";
      const toggleAllLabel = document.createElement("label");
      toggleAllLabel.className = "toggle-all-label";
      toggleAllLabel.htmlFor = "toggle-all";
      toggleAllLabel.textContent = "❯";
      main.append(toggleAll, toggleAllLabel);

      const list = document.createElement("ul");
      list.className = "todo-list";
      for (const [index, item] of this.visibleTodoItems().entries()) {
        const li = document.createElement("li");
        li.className = item.completed ? "todo-item completed" : "todo-item";
        const view = document.createElement("div");
        view.className = "view";
        const checkbox = document.createElement("input");
        checkbox.className = "toggle";
        checkbox.type = "checkbox";
        checkbox.checked = item.completed;
        checkbox.addEventListener("click", () => {
          void this.toggleTodo(index);
        });
        const label = document.createElement("label");
        label.textContent = item.title;
        view.append(checkbox, label);
        li.append(view);
        list.append(li);
      }
      main.append(list);
      app.append(main);

      const footer = document.createElement("footer");
      footer.className = "footer";
      const count = document.createElement("span");
      count.className = "todo-count";
      const countStrong = document.createElement("strong");
      countStrong.textContent = `${this.todoItems.filter((item) => !item.completed).length}`;
      count.append(countStrong, document.createTextNode(" items left"));
      footer.append(count);

      const filters = document.createElement("ul");
      filters.className = "filters";
      for (const route of ["all", "active", "completed"]) {
        const li = document.createElement("li");
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = route[0].toUpperCase() + route.slice(1);
        if (this.todoRoute === route) button.className = "active";
        button.addEventListener("click", () => {
          void this.setRoute(route);
        });
        li.append(button);
        filters.append(li);
      }
      footer.append(filters);

      const clearCompleted = document.createElement("button");
      clearCompleted.className = "clear-completed";
      clearCompleted.type = "button";
      clearCompleted.textContent = "Clear completed";
      clearCompleted.addEventListener("click", () => {
        void this.clearCompleted();
      });
      footer.append(clearCompleted);
      app.append(footer);

      const info = document.createElement("footer");
      info.className = "info";
      const p1 = document.createElement("p");
      p1.textContent = "Double-click to edit a todo";
      const p2 = document.createElement("p");
      p2.textContent = "Created by Martin Kavík";
      const p3 = document.createElement("p");
      p3.append(document.createTextNode("Part of "), document.createTextNode("TodoMVC"));
      info.append(p1, p2, p3);

      this.root.append(app, info);
      return;
    }

    if (this.isCellsExample()) {
      this.root.className = "browser-grid-shell";
      const shell = document.createElement("section");
      shell.className = "browser-grid-shell";

      const title = document.createElement("h1");
      title.textContent = this.exampleName === "cells_dynamic" ? "Cells Dynamic" : "Cells";
      const helper = document.createElement("p");
      helper.className = "grid-helper";
      helper.textContent = "Double-click a cell, type, press Enter.";

      const scroller = document.createElement("div");
      scroller.className = "grid-scroller";
      const table = document.createElement("table");
      table.className = "sheet-grid";

      const thead = document.createElement("thead");
      const headRow = document.createElement("tr");
      headRow.append(document.createElement("th"));
      for (let col = 1; col <= 26; col += 1) {
        const th = document.createElement("th");
        th.textContent = String.fromCharCode(64 + col);
        headRow.append(th);
      }
      thead.append(headRow);
      table.append(thead);

      const tbody = document.createElement("tbody");
      for (let row = 1; row <= 20; row += 1) {
        const tr = document.createElement("tr");
        const rowHeader = document.createElement("th");
        rowHeader.textContent = `${row}`;
        tr.append(rowHeader);

        for (let col = 1; col <= 26; col += 1) {
          const td = document.createElement("td");
          const isEditing = this.editingCell && this.editingCell.row === row && this.editingCell.col === col;
          if (isEditing) {
            const input = document.createElement("input");
            input.type = "text";
            input.value = this.editingCell.text;
            input.className = "sheet-input";
            input.addEventListener("input", (event) => {
              void this.setEditingText(event.currentTarget.value);
            });
            input.addEventListener("keydown", (event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                void this.commitEditingCell();
              } else if (event.key === "Escape") {
                event.preventDefault();
                this.cancelEditingCell();
              }
            });
            input.addEventListener("blur", () => {
              void this.commitEditingCell();
            });
            td.append(input);
            queueMicrotask(() => input.focus());
          } else {
            td.textContent = this.rawCellValue(row, col);
            td.addEventListener("dblclick", () => {
              void this.startEditCell(row, col);
            });
          }
          tr.append(td);
        }
        tbody.append(tr);
      }
      table.append(tbody);
      scroller.append(table);
      shell.append(title, helper, scroller);
      this.root.append(shell);
      return;
    }

    if (this.exampleName === "todo_mvc_physical") {
      this.root.className = "browser-shell";
      const shell = document.createElement("section");
      shell.className = "browser-shell";

      const title = document.createElement("h1");
      title.textContent = "todo_mvc_physical";

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
      return;
    }

    throw new Error(`unsupported example ${this.exampleName}`);
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
  exampleName,
  storage,
  root = null,
  visualMode = false,
  physicalRenderTargets = null,
  physicalStateProvider = null,
}) {
  const resolvedStorage = storage ?? (await createIndexedDbStore());
  const resolvedPhysicalStateProvider = physicalStateProvider ?? defaultPhysicalStateProvider();
  const host = new BrowserHost({
    exampleName,
    storage: resolvedStorage,
    root,
    visualMode,
    physicalRenderTargets,
    physicalStateProvider: resolvedPhysicalStateProvider,
  });
  return host.init();
}

export async function mountExampleFromLocation(root) {
  const params = new URLSearchParams(globalThis.location?.search ?? "");
  const exampleName = params.get("example") ?? "counter";
  const visualMode = params.get("visual") === "1";
  const manifest = await loadBundleManifest();
  const physicalStateProvider =
    typeof globalThis.__boonPhysicalStateProvider === "function"
      ? globalThis.__boonPhysicalStateProvider
      : defaultPhysicalStateProvider();
  return createHost({
    exampleName,
    root,
    visualMode,
    physicalRenderTargets: manifest?.physical_render_targets ?? null,
    physicalStateProvider,
  });
}
