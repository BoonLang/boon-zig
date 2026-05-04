import { createHost, MemoryIndexedDb } from "./boon-browser.mjs";

const EXAMPLES = {
  counter: {
    sourcePath: "examples/source_physical/counter/counter.bn",
    source:
      "increment_button: [event: [press: SOURCE]]\n\n" +
      "counter: 0 |> HOLD counter {\n" +
      "    increment_button.event.press |> THEN { counter + 1 }\n" +
      "}\n",
  },
  todo_mvc: {
    sourcePath: "examples/source_physical/todo_mvc/todo_mvc.bn",
    source:
      "sources: [\n" +
      "    new_todo: [\n" +
      "        event: [\n" +
      "            change: SOURCE\n" +
      "            key_down: SOURCE\n" +
      "        ]\n" +
      "    ]\n\n" +
      "    remove_completed_button: [\n" +
      "        event: [press: SOURCE]\n" +
      "        hovered: SOURCE\n" +
      "    ]\n" +
      "]\n\n" +
      "draft_title: 0 |> HOLD draft_title {\n" +
      "    sources.new_todo.event.change\n" +
      "}\n\n" +
      "submitted_count: 0 |> HOLD submitted_count {\n" +
      "    sources.new_todo.event.key_down |> THEN { submitted_count + 1 }\n" +
      "}\n",
  },
  cells: {
    sourcePath: "examples/source_physical/cells/cells.bn",
    source:
      "sources: [\n" +
      "    editor: [\n" +
      "        event: [\n" +
      "            change: SOURCE\n" +
      "            key_down: SOURCE\n" +
      "        ]\n" +
      "    ]\n" +
      "]\n\n" +
      "editing_formula: 0 |> HOLD editing_formula {\n" +
      "    sources.editor.event.change\n" +
      "}\n\n" +
      "commit_count: 0 |> HOLD commit_count {\n" +
      "    sources.editor.event.key_down |> THEN { commit_count + 1 }\n" +
      "}\n",
  },
};

export function createBrowserPlaygroundApi({
  compileProvider = compileViaServer,
  interpreterHostFactory = createHost,
} = {}) {
  return {
    examples: EXAMPLES,

    async interpreterPreview({ exampleName }) {
      const host = await interpreterHostFactory({
        sourceName: EXAMPLES[exampleName]?.sourcePath ?? exampleName,
        storage: new MemoryIndexedDb(),
      });
      return {
        ok: true,
        mode: "interpreter",
        exampleName,
        text: host.textContent(),
      };
    },

    async compileToZig(request) {
      return compileProvider(request);
    },

    async generatedZigViewer(compileResult) {
      if (!compileResult.ok) {
        return {
          ok: false,
          diagnostics: compileResult.diagnostics ?? [],
        };
      }
      return {
        ok: true,
        source: compileResult.generatedZig ?? "",
        path: compileResult.generatedZigPath ?? null,
      };
    },
  };
}

async function compileViaServer(request) {
  if (typeof fetch !== "function") {
    return {
      ok: false,
      mode: "edge-zig",
      diagnostics: [{
        sourcePath: request.sourcePath,
        step: "fetch",
        message: "playground compile endpoint unavailable",
      }],
    };
  }
  const response = await fetch("/__boon/playground/compile", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
  });
  const payload = await response.json();
  if (!response.ok && payload.ok !== false) {
    return {
      ok: false,
      mode: "edge-zig",
      diagnostics: [{
        sourcePath: request.sourcePath,
        step: "edge-compile",
        message: `playground compile failed: ${response.status}`,
      }],
    };
  }
  return payload;
}

function el(tagName, className = null, text = null) {
  const node = document.createElement(tagName);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

export async function mountPlayground(root, api = createBrowserPlaygroundApi()) {
  const shell = el("section", "playground-shell");
  const toolbar = el("div", "playground-toolbar");
  const select = el("select", "playground-select");
  for (const name of Object.keys(api.examples)) {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = name;
    select.append(option);
  }
  select.value = Object.keys(api.examples)[0];

  const runButton = el("button", null, "Run preview");
  runButton.type = "button";
  const compileButton = el("button", null, "Compile Zig");
  compileButton.type = "button";
  const pathLabel = el("output", "playground-path");
  toolbar.append(select, runButton, compileButton, pathLabel);

  const editor = el("textarea", "playground-editor");
  editor.spellcheck = false;
  const preview = el("pre", "playground-preview");
  const generated = el("pre", "playground-generated");
  const diagnostics = el("pre", "playground-diagnostics");

  shell.append(toolbar, editor, preview, generated, diagnostics);
  root.replaceChildren(shell);

  function loadExample(name) {
    const example = api.examples[name];
    editor.value = example.source;
    pathLabel.textContent = example.sourcePath;
    preview.textContent = "";
    generated.textContent = "";
    diagnostics.textContent = "";
  }

  async function runPreview() {
    const result = await api.interpreterPreview({ exampleName: select.value });
    preview.textContent = result.ok ? result.text : "preview failed";
  }

  async function compile() {
    const example = api.examples[select.value];
    const result = await api.compileToZig({
      exampleName: select.value,
      sourcePath: example.sourcePath,
      source: editor.value,
      target: "native-preview",
    });
    if (!result.ok) {
      diagnostics.textContent = (result.diagnostics ?? []).map((item) => `${item.sourcePath}: ${item.message}`).join("\n");
      return;
    }
    diagnostics.textContent = `compiler path: ${result.mode}`;
    preview.textContent = result.previewStdout ?? "";
    const viewer = await api.generatedZigViewer(result);
    generated.textContent = viewer.ok ? viewer.source : "";
  }

  select.addEventListener("change", () => loadExample(select.value));
  runButton.addEventListener("click", () => {
    void runPreview();
  });
  compileButton.addEventListener("click", () => {
    void compile();
  });
  loadExample(select.value);
  await runPreview();
  return { api, shell, select, editor, preview, generated, diagnostics, runPreview, compile };
}

export async function mountPlaygroundFromLocation(root) {
  return mountPlayground(root);
}
