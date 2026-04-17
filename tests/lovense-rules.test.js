const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function createElement() {
  return {
    value: "",
    innerHTML: "",
    textContent: "",
    disabled: false,
    options: [],
    classList: { toggle() {} },
    addEventListener() {},
    append() {},
    remove() {},
    click() {},
    load() {},
    pause() {},
    play() {
      return Promise.resolve();
    },
    removeAttribute() {},
  };
}

function loadRuleEngine() {
  const sourcePath = path.join(__dirname, "..", "static", "playlist-app.js");
  const source = fs.readFileSync(sourcePath, "utf8").replace(/\binit\(\);\s*$/m, "");
  const context = {
    console,
    setTimeout,
    clearTimeout,
    window: null,
    document: {
      getElementById() {
        return createElement();
      },
      createElement() {
        return createElement();
      },
      body: { append() {} },
    },
    URL: {
      createObjectURL() {
        return "blob:test";
      },
      revokeObjectURL() {},
    },
    Blob: class Blob {},
    fetch: async () => {
      throw new Error("fetch is not available in the rule-engine tests");
    },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context, { filename: "playlist-app.js" });
  return context;
}

function createTestLovenseConfig(engine) {
  return engine.normalizeLovenseConfig({
    testSelectedToys: [
      {
        id: "sim-nora",
        name: "Nora Simulator",
        nickName: "Nora Simulator",
        type: "Nora",
        fullFunctionNames: ["Vibrate", "Rotate"],
      },
      {
        id: "sim-max2",
        name: "Max 2 Simulator",
        nickName: "Max 2 Simulator",
        type: "Max 2",
        fullFunctionNames: ["Vibrate", "Pump"],
      },
    ],
  });
}

function toPlainJson(value) {
  return JSON.parse(JSON.stringify(value));
}

const engine = loadRuleEngine();

const tests = [];

function test(name, fn) {
  tests.push({ name, fn });
}

test("parseRuleScript keeps assignments, branches, and selectors", () => {
  const compiled = engine.parseRuleScript(
    [
      "let level = pos * 0.5 + 2",
      "if level >= 15 then [Nora Simulator] vibrate(level, 800) + [Max 2] pump(2)",
      "else stop()",
    ].join("\n"),
  );

  assert.equal(compiled.assignments.length, 1);
  assert.equal(compiled.branches.length, 2);
  assert.equal(compiled.assignments[0].name, "level");
  assert.equal(compiled.branches[0].commands[0].targetSelector, "Nora Simulator");
  assert.equal(compiled.branches[0].commands[1].targetSelector, "Max 2");
});

test("parseRuleScript rejects variable declarations after the first branch", () => {
  assert.throws(
    () =>
      engine.parseRuleScript(
        [
          "if pos >= 15 then vibrate(10)",
          "let level = pos * 0.5 + 2",
        ].join("\n"),
      ),
    /Variables must be declared before rule branches/,
  );
});

test("evaluateLovenseRuleCommands resolves targeted commands and computed strengths", () => {
  const config = createTestLovenseConfig(engine);
  const result = engine.evaluateLovenseRuleCommands(
    [
      "let level = pos * 0.5 + 2",
      "if level >= 15 then [Nora Simulator] vibrate(level, 800) + [Max 2] pump(2)",
      "else stop()",
    ].join("\n"),
    config,
    { pos: 30, index: 4, atMs: 1200, currentMs: 1200, deltaMs: 0 },
    { requireToyId: false, mode: "test" },
  );

  assert.equal(result.commands.length, 2);
  assert.deepEqual(
    toPlainJson(
      result.commands.map((command) => ({
        action: command.action,
        toyIds: command.toyIds,
        delayMs: command.delayMs,
        durationMs: command.durationMs,
        stopPrevious: command.stopPrevious,
      })),
    ),
    [
      {
        action: "Vibrate:17",
        toyIds: ["sim-nora"],
        delayMs: 0,
        durationMs: 800,
        stopPrevious: 1,
      },
      {
        action: "Pump:2",
        toyIds: ["sim-max2"],
        delayMs: 0,
        durationMs: 0,
        stopPrevious: 0,
      },
    ],
  );
});

test("evaluateLovenseRuleCommands applies branch delays and shared commands", () => {
  const config = createTestLovenseConfig(engine);
  const result = engine.evaluateLovenseRuleCommands(
    [
      "let level = pos * 0.5 + 2",
      "if level >= 15 then [Nora Simulator] vibrate(level, 800) + [Max 2] pump(2)",
      "else if pos >= 5 then delay(250) + [sim-nora] rotate(3, 800) + vibrate(5, 800)",
      "else stop()",
    ].join("\n"),
    config,
    { pos: 8, index: 2, atMs: 900, currentMs: 900, deltaMs: 0 },
    { requireToyId: false, mode: "test" },
  );

  assert.equal(result.commands.length, 2);
  assert.deepEqual(
    toPlainJson(
      result.commands.map((command) => ({
        action: command.action,
        toyIds: command.toyIds,
        delayMs: command.delayMs,
        durationMs: command.durationMs,
        stopPrevious: command.stopPrevious,
      })),
    ),
    [
      {
        action: "Rotate:3",
        toyIds: ["sim-nora"],
        delayMs: 250,
        durationMs: 800,
        stopPrevious: 1,
      },
      {
        action: "Vibrate:5",
        toyIds: ["sim-nora", "sim-max2"],
        delayMs: 250,
        durationMs: 800,
        stopPrevious: 0,
      },
    ],
  );
});

test("validateLovenseRulesForConfig rejects unsupported targeted actions", () => {
  const config = createTestLovenseConfig(engine);

  assert.throws(
    () =>
      engine.validateLovenseRulesForConfig("if pos >= 1 then [Max 2] rotate(3)", config, {
        requireToyId: false,
        mode: "test",
      }),
    /does not support Rotate/,
  );
});

test("validateSelectedFunscriptFiles accepts .funscript and .json files", () => {
  assert.doesNotThrow(() =>
    engine.validateSelectedFunscriptFiles([
      { name: "sample.funscript", type: "" },
      { name: "metadata.json", type: "application/json" },
    ]),
  );
});

test("validateSelectedFunscriptFiles rejects video files in the funscript picker", () => {
  assert.throws(
    () =>
      engine.validateSelectedFunscriptFiles([
        { name: "clip.mp4", type: "video/mp4" },
      ]),
    /Only \.funscript and \.json files are allowed/,
  );
});

test("validateLovenseRulesForConfig rejects duplicate actions on the same toy", () => {
  const config = createTestLovenseConfig(engine);

  assert.throws(
    () =>
      engine.validateLovenseRulesForConfig("if pos >= 1 then [sim-nora] vibrate(5) + [Nora Simulator] vibrate(6)", config, {
        requireToyId: false,
        mode: "test",
      }),
    /uses vibrate more than once/,
  );
});

test("groupLovenseCommandsByDelay groups commands in ascending delay order", () => {
  const batches = engine.groupLovenseCommandsByDelay([
    { action: "Rotate:3", delayMs: 250 },
    { action: "Vibrate:5", delayMs: 0 },
    { action: "Pump:2", delayMs: 250 },
    { action: "Stop", delayMs: 100 },
  ]);

  assert.deepEqual(
    toPlainJson(
      batches.map((batch) => ({
        delayMs: batch.delayMs,
        actions: batch.commands.map((command) => command.action),
      })),
    ),
    [
      { delayMs: 0, actions: ["Vibrate:5"] },
      { delayMs: 100, actions: ["Stop"] },
      { delayMs: 250, actions: ["Rotate:3", "Pump:2"] },
    ],
  );
});

test("pairVideosWithScripts prefers filename matches before fallback pairing", () => {
  const pairing = engine.pairVideosWithScripts(
    [
      { name: "scene-01.mp4" },
      { name: "bonus.mp4" },
      { name: "scene-02.mp4" },
    ],
    [
      { stem: engine.normalizeStem("scene_02.funscript"), file: { name: "scene_02.funscript" } },
      { stem: engine.normalizeStem("scene-01.funscript"), file: { name: "scene-01.funscript" } },
      { stem: engine.normalizeStem("mismatch.funscript"), file: { name: "mismatch.funscript" } },
    ],
  );

  assert.deepEqual(
    toPlainJson(pairing.pairs.map(({ videoFile, scriptData }) => [videoFile.name, scriptData.file.name])),
    [
      ["scene-01.mp4", "scene-01.funscript"],
      ["scene-02.mp4", "scene_02.funscript"],
      ["bonus.mp4", "mismatch.funscript"],
    ],
  );
  assert.equal(pairing.fallbackPairs, 1);
  assert.equal(pairing.unmatchedVideos.length, 0);
  assert.equal(pairing.unmatchedScripts.length, 0);
});

test("extractScriptSettings prefers metadata.fhplayer over legacy root values", () => {
  const settings = toPlainJson(
    engine.extractScriptSettings({
      executionMode: "lovense-test",
      rulesText: "if pos >= 1 then stop()",
      lovense: {
        testToyId: "legacy-root",
      },
      metadata: {
        fh_player: {
          executionMode: "lovense-live",
          rulesText: "if pos >= 2 then vibrate(4)",
          lovense: {
            testToyId: "legacy-metadata",
          },
        },
        fhplayer: {
          executionMode: "lovense-test",
          rulesText: "if pos >= 3 then rotate(2)",
          lovense: {
            testSelectedToys: [
              {
                id: "sim-max2",
                name: "Max 2 Simulator",
                nickName: "Max 2 Simulator",
                type: "Max 2",
                fullFunctionNames: ["Vibrate", "Pump"],
              },
            ],
          },
        },
      },
    }),
  );

  assert.equal(settings.executionMode, "lovense-test");
  assert.equal(settings.rulesText, "if pos >= 3 then rotate(2)");
  assert.equal(settings.lovense.testToyId, "sim-max2");
  assert.equal(settings.lovense.testSelectedToys.length, 1);
});

test("buildSavedFunscriptDocument writes schemaVersion 2 metadata without dropping existing data", () => {
  const document = toPlainJson(
    engine.buildSavedFunscriptDocument({
      scriptDocument: {
        actions: [{ at: 100, pos: 50 }],
        metadata: {
          title: "Original title",
        },
      },
      executionMode: "lovense-live",
      rulesText: "if pos >= 15 then vibrate(10)\nelse stop()",
      lovense: engine.normalizeLovenseConfig({
        selectedConnectionId: "user-2",
        connections: [
          {
            id: "user-2",
            label: "User 2",
            scheme: "http",
            host: "192.168.0.2",
            port: "20010",
            platformName: "FHPlayer",
            selectedToys: [
              {
                id: "toy-a",
                name: "Edge 2",
                nickName: "Edge 2",
                type: "Edge 2",
                fullFunctionNames: ["Vibrate2"],
              },
            ],
          },
        ],
      }),
    }),
  );

  assert.equal(document.metadata.title, "Original title");
  assert.equal(document.metadata.fhplayer.schemaVersion, 2);
  assert.equal(document.metadata.fhplayer.executionMode, "lovense-live");
  assert.equal(document.metadata.fhplayer.connections, undefined);
  assert.equal(document.metadata.fhplayer.lovense.selectedConnectionId, "user-2");
  assert.equal(document.metadata.fhplayer.lovense.connections[0].host, "192.168.0.2");
  assert.equal(document.actions.length, 1);
});

test("validateLovenseRulesForConfig rejects delay-only branches", () => {
  const config = createTestLovenseConfig(engine);

  assert.throws(
    () =>
      engine.validateLovenseRulesForConfig("if pos >= 1 then delay(250)", config, {
        requireToyId: false,
        mode: "test",
      }),
    /delay\(\) cannot be the only command in a branch/,
  );
});

test("normalizeLovenseConfig keeps legacy live and test toy fields usable", () => {
  const normalized = toPlainJson(
    engine.normalizeLovenseConfig({
      scheme: "http",
      host: "10.0.0.5",
      port: "20010",
      platformName: "FHPlayer",
      toyId: "legacy-live",
      toyName: "Legacy Nora",
      toyType: "Nora",
      capabilities: ["Vibrate", "Rotate"],
      testToyId: "legacy-test",
      testToyName: "Legacy Test",
      testToyType: "Max 2",
      testCapabilities: ["Vibrate", "Pump"],
    }),
  );

  assert.equal(normalized.connections.length, 1);
  assert.equal(normalized.connections[0].host, "10.0.0.5");
  assert.equal(normalized.connections[0].selectedToys[0].id, "legacy-live");
  assert.equal(normalized.testSelectedToys[0].id, "legacy-test");
  assert.deepEqual(normalized.testCapabilities, ["Vibrate", "Pump"]);
});

let failures = 0;
tests.forEach(({ name, fn }) => {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    failures += 1;
    console.error(`not ok - ${name}`);
    console.error(error.stack || String(error));
  }
});

if (failures > 0) {
  process.exitCode = 1;
} else {
  console.log(`All ${tests.length} rule-engine tests passed.`);
}
