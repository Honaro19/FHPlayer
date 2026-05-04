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

test("getAvailableLovenseActionKeysForToys limits Solace actions to Solace capabilities", () => {
  const actionKeys = engine.getAvailableLovenseActionKeysForToys([
    {
      id: "sim-solace",
      name: "Solace Simulator",
      nickName: "Solace Simulator",
      type: "Solace",
    },
  ]);

  assert.deepEqual(toPlainJson(actionKeys), ["all", "thrusting", "depth", "stop"]);
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

test("buildLovensePayloadCommands starts short local-auto-stop commands", () => {
  const commands = engine.buildLovensePayloadCommands(
    {
      delayMs: 0,
      commands: [
        {
          action: "Vibrate:18",
          toyIds: ["toy-a"],
          delayMs: 0,
          durationMs: 200,
          stopPrevious: 1,
        },
      ],
    },
    true,
  );

  assert.equal(commands.length, 1);
  assert.equal(commands[0].timeSec, 1);
  assert.equal(commands[0].localAutoStopDurationMs, 200);
  assert.equal(commands[0].usesLocalAutoStop, true);
  assert.equal(commands[0].durationMs, undefined);
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

test("buildSavedFunscriptDocument removes FHPlayer rule metadata without dropping normal data", () => {
  const document = toPlainJson(
    engine.buildSavedFunscriptDocument({
      scriptDocument: {
        actions: [{ at: 100, pos: 50 }],
        metadata: {
          title: "Original title",
          fhplayer: {
            rulesText: "if pos >= 1 then stop()",
          },
          fh_player: {
            rulesText: "if pos >= 2 then stop()",
          },
        },
        fhplayer: {
          rulesText: "if pos >= 3 then stop()",
        },
        rulesText: "if pos >= 4 then stop()",
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
  assert.equal(document.metadata.fhplayer, undefined);
  assert.equal(document.metadata.fh_player, undefined);
  assert.equal(document.fhplayer, undefined);
  assert.equal(document.rulesText, undefined);
  assert.equal(document.actions.length, 1);
});

test("saved playlist entries keep Lovense programs separate from the funscript document", () => {
  const savedEntry = toPlainJson(
    engine.buildSavedPlaylistEntry(
      {
        title: "Scene A",
        videoName: "scene.mp4",
        videoSource: {
          kind: "videos",
          name: "scene.mp4",
          source: "library",
          path: "C:\\Media\\scene.mp4",
        },
        funscriptName: "shared.funscript",
        funscriptSource: {
          kind: "funscripts",
          name: "shared.funscript",
          source: "library",
          path: "C:\\Media\\shared.funscript",
        },
        scriptDocument: {
          actions: [{ at: 100, pos: 50 }],
          metadata: {
            fhplayer: {
              rulesText: "if pos >= 1 then stop()",
            },
          },
        },
        executionMode: "lovense-test",
        rulesText: "if pos >= 10 then vibrate(8)\nelse stop()",
        lovense: engine.normalizeLovenseConfig({
          testSelectedToys: [
            {
              id: "sim-nora",
              name: "Nora Simulator",
              nickName: "Nora Simulator",
              type: "Nora",
              fullFunctionNames: ["Vibrate", "Rotate"],
            },
          ],
        }),
      },
      0,
    ),
  );

  assert.equal(savedEntry.video.name, "scene.mp4");
  assert.equal(savedEntry.video.path, "C:\\Media\\scene.mp4");
  assert.equal(savedEntry.funscript.name, "shared.funscript");
  assert.equal(savedEntry.funscript.path, "C:\\Media\\shared.funscript");
  assert.equal(savedEntry.funscript.document.metadata.fhplayer, undefined);
  assert.equal(savedEntry.execution.mode, "lovense-test");
  assert.equal(savedEntry.execution.rulesText, "if pos >= 10 then vibrate(8)\nelse stop()");
  assert.equal(savedEntry.execution.lovense.testSelectedToys, undefined);
  assert.equal(savedEntry.execution.lovense.connectionRules[0].connectionId, "user-1");
  assert.equal(savedEntry.execution.lovense.connectionRules[0].rulesText, "if pos >= 10 then vibrate(8)\nelse stop()");
});

test("live playlist entries store active users and per-user rule scripts", () => {
  const playlistLovense = engine.normalizeLovenseConfig({
    selectedConnectionId: "user-2",
    activeConnectionIds: ["user-1", "user-2"],
    connections: [
      {
        id: "user-1",
        label: "User 1",
        scheme: "http",
        host: "192.168.0.10",
        port: "20010",
        platformName: "FHPlayer",
        selectedToys: [
          {
            id: "toy-a",
            name: "Nora",
            nickName: "Nora",
            type: "Nora",
            fullFunctionNames: ["Vibrate", "Rotate"],
          },
        ],
      },
      {
        id: "user-2",
        label: "User 2",
        scheme: "http",
        host: "192.168.0.11",
        port: "20010",
        platformName: "FHPlayer",
        selectedToys: [
          {
            id: "toy-b",
            name: "Max 2",
            nickName: "Max 2",
            type: "Max 2",
            fullFunctionNames: ["Pump"],
          },
        ],
      },
    ],
  });
  const savedEntry = toPlainJson(
    engine.buildSavedPlaylistEntry(
      {
        title: "Multi User Scene",
        videoName: "scene.mp4",
        videoSource: { kind: "videos", name: "scene.mp4", source: "library" },
        funscriptName: "scene.funscript",
        funscriptSource: { kind: "funscripts", name: "scene.funscript", source: "library" },
        scriptDocument: { actions: [{ at: 100, pos: 50 }] },
        executionMode: "lovense-live",
        rulesText: "if pos >= 1 then stop()",
        lovense: engine.normalizeLovenseConfig({
          ...playlistLovense,
          connections: playlistLovense.connections.map((connection) => ({
            ...connection,
            rulesText:
              connection.id === "user-1"
                ? "if pos >= 10 then vibrate(6)\nelse stop()"
                : "if pos >= 10 then pump(2)\nelse stop()",
          })),
        }),
      },
      0,
    ),
  );

  assert.deepEqual(toPlainJson(savedEntry.execution.lovense.activeConnectionIds), ["user-1", "user-2"]);
  assert.equal(savedEntry.execution.lovense.connections, undefined);
  assert.equal(savedEntry.execution.lovense.connectionRules[0].rulesText, "if pos >= 10 then vibrate(6)\nelse stop()");
  assert.equal(savedEntry.execution.lovense.connectionRules[1].rulesText, "if pos >= 10 then pump(2)\nelse stop()");

  const loadedEntry = engine.createPlaylistEntryFromSaved(savedEntry, 0, playlistLovense);
  const programs = toPlainJson(engine.getActiveLovenseRulePrograms(loadedEntry));
  assert.deepEqual(programs.map((program) => program.label), ["User 1", "User 2"]);
  assert.deepEqual(programs.map((program) => program.rulesText), [
    "if pos >= 10 then vibrate(6)\nelse stop()",
    "if pos >= 10 then pump(2)\nelse stop()",
  ]);
});

test("saved playlist document stores users globally and entry rules per user", () => {
  const entryLovense = {
    selectedConnectionId: "user-2",
    activeConnectionIds: ["user-1", "user-2"],
    connections: [
      {
        id: "user-1",
        label: "User 1",
        scheme: "http",
        host: "192.168.0.10",
        port: "20010",
        platformName: "FHPlayer",
        rulesText: "if pos >= 10 then vibrate(6)\nelse stop()",
        selectedToys: [
          {
            id: "toy-a",
            name: "Nora",
            nickName: "Nora",
            type: "Nora",
            fullFunctionNames: ["Vibrate", "Rotate"],
          },
        ],
        testSelectedToys: [
          {
            id: "sim-nora",
            name: "Nora Simulator",
            nickName: "Nora Simulator",
            type: "Nora",
            fullFunctionNames: ["Vibrate", "Rotate"],
          },
        ],
      },
      {
        id: "user-2",
        label: "User 2",
        scheme: "http",
        host: "192.168.0.11",
        port: "20010",
        platformName: "FHPlayer",
        rulesText: "if pos >= 10 then pump(2)\nelse stop()",
        selectedToys: [
          {
            id: "toy-b",
            name: "Max 2",
            nickName: "Max 2",
            type: "Max 2",
            fullFunctionNames: ["Pump"],
          },
        ],
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
    ],
  };

  vm.runInContext(
    `
      state.formLovense = normalizeLovenseConfig(${JSON.stringify(entryLovense)});
      ui.lovenseRules.value = "if pos >= 10 then pump(2)\\nelse stop()";
      state.playlistLovense = normalizeLovenseConfig(${JSON.stringify(entryLovense)});
      state.playlist = [{
        id: "entry-global-users",
        title: "Global Users",
        videoName: "scene.mp4",
        videoSource: { kind: "videos", name: "scene.mp4", source: "library" },
        funscriptName: "scene.funscript",
        funscriptSource: { kind: "funscripts", name: "scene.funscript", source: "library" },
        scriptDocument: { actions: [{ at: 100, pos: 50 }] },
        executionMode: "lovense-test",
        rulesText: "if pos >= 1 then stop()",
        lovense: normalizeLovenseConfig(${JSON.stringify(entryLovense)}),
      }];
      state.playbackMode = "sequential";
    `,
    engine,
  );

  const document = toPlainJson(engine.buildSavedPlaylistDocument());

  assert.equal(document.lovense.connections.length, 2);
  assert.equal(document.lovense.activeConnectionIds, undefined);
  assert.equal(document.lovense.connections[0].rulesText, undefined);
  assert.equal(document.lovense.connections[0].testSelectedToys[0].id, "sim-nora");
  assert.equal(document.lovense.connections[1].testSelectedToys[0].id, "sim-max2");
  assert.equal(document.entries[0].execution.lovense.connections, undefined);
  assert.equal(document.entries[0].execution.lovense.connectionRules[0].rulesText, "if pos >= 10 then vibrate(6)\nelse stop()");
  assert.equal(document.entries[0].execution.lovense.connectionRules[1].rulesText, "if pos >= 10 then pump(2)\nelse stop()");
});

test("Lovense test entries run per active playlist user", () => {
  const playlistLovense = engine.normalizeLovenseConfig({
    selectedConnectionId: "user-1",
    connections: [
      {
        id: "user-1",
        label: "User 1",
        testSelectedToys: [
          {
            id: "sim-nora",
            name: "Nora Simulator",
            nickName: "Nora Simulator",
            type: "Nora",
            fullFunctionNames: ["Vibrate", "Rotate"],
          },
        ],
      },
      {
        id: "user-2",
        label: "User 2",
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
    ],
  });
  const entry = engine.createPlaylistEntryFromSaved(
    {
      title: "Test Users",
      video: { name: "scene.mp4" },
      funscript: { name: "scene.funscript", document: { actions: [{ at: 100, pos: 50 }] } },
      execution: {
        mode: "lovense-test",
        lovense: {
          activeConnectionIds: ["user-1", "user-2"],
          connectionRules: [
            { connectionId: "user-1", rulesText: "if pos >= 1 then vibrate(6)\nelse stop()" },
            { connectionId: "user-2", rulesText: "if pos >= 1 then pump(2)\nelse stop()" },
          ],
        },
      },
    },
    0,
    playlistLovense,
  );

  const programs = toPlainJson(engine.getActiveLovenseRulePrograms(entry));

  assert.deepEqual(programs.map((program) => program.label), ["User 1", "User 2"]);
  assert.deepEqual(programs.map((program) => program.rulesText), [
    "if pos >= 1 then vibrate(6)\nelse stop()",
    "if pos >= 1 then pump(2)\nelse stop()",
  ]);
  assert.equal(programs[0].lovense.testSelectedToys[0].id, "sim-nora");
  assert.equal(programs[1].lovense.testSelectedToys[0].id, "sim-max2");
});

test("saved playlist entries keep Android document URIs playable", () => {
  const uri = "content://com.android.providers.media.documents/document/video%3A42";
  const savedEntry = toPlainJson(
    engine.buildSavedPlaylistEntry(
      {
        title: "Android Scene",
        videoName: "scene.mp4",
        videoSource: {
          kind: "videos",
          name: "scene.mp4",
          source: "android-document",
          uri,
        },
        funscriptName: "scene.funscript",
        funscriptSource: {
          kind: "funscripts",
          name: "scene.funscript",
          source: "android-document",
          uri: "content://com.android.providers.downloads.documents/document/7",
        },
        scriptDocument: { actions: [{ at: 100, pos: 50 }] },
        executionMode: "lovense-test",
        rulesText: "if pos >= 10 then vibrate(8)\nelse stop()",
        lovense: engine.normalizeLovenseConfig({}),
      },
      0,
    ),
  );

  assert.equal(savedEntry.video.uri, uri);
  assert.equal(savedEntry.video.source, "android-document");
  assert.equal(savedEntry.funscript.uri, "content://com.android.providers.downloads.documents/document/7");

  const previousPlatform = vm.runInContext("state.backendCapabilities.platform", engine);
  vm.runInContext("state.backendCapabilities.platform = 'android';", engine);
  try {
    const entry = engine.createPlaylistEntryFromSaved(
      {
        title: "Android Scene",
        video: savedEntry.video,
        funscript: {
          name: "scene.funscript",
          document: { actions: [{ at: 100, pos: 50 }] },
        },
      },
      0,
    );
    assert.equal(
      entry.videoUrl,
      `/api/android/document-file?kind=videos&uri=${encodeURIComponent(uri)}`,
    );
  } finally {
    vm.runInContext(`state.backendCapabilities.platform = ${JSON.stringify(previousPlatform)};`, engine);
  }
});

test("loading playlist entries allows the same funscript with different Lovense programs", () => {
  const sharedScriptDocument = {
    actions: [
      { at: 200, pos: 5 },
      { at: 400, pos: 20 },
    ],
  };

  const firstEntry = toPlainJson(
    engine.createPlaylistEntryFromSaved(
      {
        title: "Playlist One",
        video: { name: "scene.mp4" },
        funscript: { name: "shared.funscript", document: sharedScriptDocument },
        execution: {
          mode: "lovense-test",
          rulesText: "if pos >= 10 then vibrate(6)\nelse stop()",
          lovense: {
            testSelectedToys: [
              {
                id: "sim-nora",
                name: "Nora Simulator",
                nickName: "Nora Simulator",
                type: "Nora",
                fullFunctionNames: ["Vibrate", "Rotate"],
              },
            ],
          },
        },
      },
      0,
    ),
  );
  const secondEntry = toPlainJson(
    engine.createPlaylistEntryFromSaved(
      {
        title: "Playlist Two",
        video: { name: "scene.mp4" },
        funscript: { name: "shared.funscript", document: sharedScriptDocument },
        execution: {
          mode: "lovense-test",
          rulesText: "if pos >= 10 then rotate(3)\nelse stop()",
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
      1,
    ),
  );

  assert.equal(firstEntry.funscriptName, "shared.funscript");
  assert.equal(secondEntry.funscriptName, "shared.funscript");
  assert.equal(firstEntry.videoUrl, "/api/library/file?kind=videos&filename=scene.mp4");
  assert.equal(firstEntry.actions.length, 2);
  assert.notEqual(firstEntry.rulesText, secondEntry.rulesText);
  assert.equal(firstEntry.lovense.testSelectedToys[0].id, "sim-nora");
  assert.equal(secondEntry.lovense.testSelectedToys[0].id, "sim-max2");
});

test("loading saved playlist leaves missing videos unloaded", async () => {
  const previousFetch = engine.fetch;
  const previousServe = vm.runInContext("state.library.capabilities.serve", engine);
  const previousLocalFiles = vm.runInContext("state.library.capabilities.localFiles", engine);
  const requestedUrls = [];

  engine.fetch = async (url) => {
    requestedUrls.push(String(url));
    return { ok: false };
  };
  vm.runInContext("state.library.capabilities.serve = true;", engine);
  vm.runInContext("state.library.capabilities.localFiles = true;", engine);

  try {
    const warnings = [];
    const videoUrl = await engine.resolveSavedVideoUrl(
      {
        kind: "videos",
        name: "scene.mp4",
        path: "C:\\Missing\\scene.mp4",
        libraryName: "scene.mp4",
      },
      "scene.mp4",
      warnings,
    );

    assert.equal(videoUrl, "");
    assert.match(warnings.join(" "), /Video file could not be loaded/);
    assert.equal(requestedUrls.length, 2);
  } finally {
    engine.fetch = previousFetch;
    vm.runInContext(`state.library.capabilities.serve = ${JSON.stringify(previousServe)};`, engine);
    vm.runInContext(`state.library.capabilities.localFiles = ${JSON.stringify(previousLocalFiles)};`, engine);
  }
});

test("playlist library filenames are normalized from display names", () => {
  assert.equal(engine.buildPlaylistLibraryFileName("My Playlist"), "My Playlist.fhplaylist");
  assert.equal(engine.buildPlaylistLibraryFileName("archive.json"), "archive.fhplaylist");
  assert.equal(engine.buildPlaylistLibraryFileName("C:\\Media\\Bad<Name>.fhplaylist"), "BadName.fhplaylist");
  assert.throws(() => engine.buildPlaylistLibraryFileName("?.json"), /Enter a playlist name/);
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

test("evaluateLovenseRuleCommands rejects direct action durations under 200 ms", () => {
  const config = createTestLovenseConfig(engine);

  assert.throws(
    () =>
      engine.evaluateLovenseRuleCommands(
        "if pos >= 1 then vibrate(10, 199)",
        config,
        { pos: 10, index: 0, atMs: 0, currentMs: 0, deltaMs: 0 },
        {
          requireToyId: false,
          mode: "test",
        },
      ),
    /duration must be at least 200 ms/,
  );
});

test("evaluateLovenseRuleCommands rejects variable action durations under 200 ms", () => {
  const config = createTestLovenseConfig(engine);

  assert.throws(
    () =>
      engine.evaluateLovenseRuleCommands(
        [
          "let shortDuration = 150",
          "if pos >= 1 then vibrate(10, shortDuration)",
        ].join("\n"),
        config,
        { pos: 10, index: 0, atMs: 0, currentMs: 0, deltaMs: 0 },
        {
          requireToyId: false,
          mode: "test",
        },
      ),
    /duration must be at least 200 ms/,
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

async function runTests() {
  let failures = 0;
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`ok - ${name}`);
    } catch (error) {
      failures += 1;
      console.error(`not ok - ${name}`);
      console.error(error.stack || String(error));
    }
  }

  if (failures > 0) {
    process.exitCode = 1;
  } else {
    console.log(`All ${tests.length} rule-engine tests passed.`);
  }
}

runTests();
