const DEFAULT_COMMAND_TEMPLATE =
  'Write-Output "Action {{index}} | at={{atMs}}ms | pos={{pos}} | current={{currentMs}}ms | video={{entryTitle}}"';
const DEFAULT_EXECUTION_MODE = "shell";
const DEFAULT_SHELL = "powershell";
const DEFAULT_TIMEOUT_SECONDS = 5;
const DEFAULT_RULES_TEXT = "if pos >= 15 then vibrate(10)\nelse stop()";
const DEFAULT_LOVENSE_CONFIG = {
  scheme: "https",
  host: "127-0-0-1.lovense.club",
  port: "30010",
  platformName: "FHPlayer",
  toyId: "",
  toyName: "",
  toyType: "",
  capabilities: [],
};
const LOVENSE_ACTIONS = {
  all: { apiName: "All", min: 0, max: 20, aliases: ["all"] },
  vibrate: { apiName: "Vibrate", min: 0, max: 20, aliases: ["vibrate", "vibration"] },
  rotate: { apiName: "Rotate", min: 0, max: 20, aliases: ["rotate", "rotation"] },
  pump: { apiName: "Pump", min: 0, max: 3, aliases: ["pump"] },
  thrusting: { apiName: "Thrusting", min: 0, max: 20, aliases: ["thrusting", "thrust"] },
  fingering: { apiName: "Fingering", min: 0, max: 20, aliases: ["fingering", "finger"] },
  suction: { apiName: "Suction", min: 0, max: 20, aliases: ["suction"] },
  depth: { apiName: "Depth", min: 0, max: 3, aliases: ["depth"] },
  stroke: { apiName: "Stroke", min: 0, max: 100, aliases: ["stroke"] },
  oscillate: { apiName: "Oscillate", min: 0, max: 20, aliases: ["oscillate", "oscillation"] },
  stop: { apiName: "Stop", min: 0, max: 0, aliases: ["stop"] },
};
const BASE_RULE_VARIABLES = ["pos", "index", "atMs", "currentMs", "deltaMs"];
const RULE_VARIABLES = new Set(BASE_RULE_VARIABLES);

const state = {
  playlist: [],
  playlistCounter: 0,
  currentEntryId: null,
  nextActionIndex: 0,
  lastTriggeredIndex: null,
  highlightedActionIndex: null,
  armed: false,
  rafId: null,
  logCount: 0,
  pendingExecutions: 0,
  playbackMode: "sequential",
  detectedToys: [],
  scheduledLovenseTimers: new Set(),
};

const ui = {
  backendStatus: document.getElementById("backend-status"),
  playlistCount: document.getElementById("playlist-count"),
  playlistModeStatus: document.getElementById("playlist-mode-status"),
  armedStatus: document.getElementById("armed-status"),
  pendingCount: document.getElementById("pending-count"),
  currentEntryTitle: document.getElementById("current-entry-title"),
  currentEntryMeta: document.getElementById("current-entry-meta"),
  currentTime: document.getElementById("current-time"),
  nextAction: document.getElementById("next-action"),
  lastAction: document.getElementById("last-action"),
  video: document.getElementById("video"),
  videoFiles: document.getElementById("video-files"),
  funscriptFiles: document.getElementById("funscript-files"),
  executionMode: document.getElementById("execution-mode"),
  shell: document.getElementById("shell"),
  timeoutSeconds: document.getElementById("timeout-seconds"),
  dryRun: document.getElementById("dry-run"),
  playlistMode: document.getElementById("playlist-mode"),
  commandTemplate: document.getElementById("command-template"),
  shellConfig: document.getElementById("shell-config"),
  lovenseConfig: document.getElementById("lovense-config"),
  lovenseScheme: document.getElementById("lovense-scheme"),
  lovenseHost: document.getElementById("lovense-host"),
  lovensePort: document.getElementById("lovense-port"),
  lovensePlatformName: document.getElementById("lovense-platform-name"),
  lovenseStatus: document.getElementById("lovense-status"),
  lovenseToySelect: document.getElementById("lovense-toy-select"),
  lovenseCapabilities: document.getElementById("lovense-capabilities"),
  lovenseDeviceType: document.getElementById("lovense-device-type"),
  lovenseParallelActions: document.getElementById("lovense-parallel-actions"),
  lovenseRules: document.getElementById("lovense-rules"),
  lovenseRuleStatus: document.getElementById("lovense-rule-status"),
  addPlaylistButton: document.getElementById("add-playlist-button"),
  updateEntryButton: document.getElementById("update-entry-button"),
  saveFunscriptButton: document.getElementById("save-funscript-button"),
  detectLovenseButton: document.getElementById("detect-lovense-button"),
  stopLovenseButton: document.getElementById("stop-lovense-button"),
  playSelectedButton: document.getElementById("play-selected-button"),
  nextButton: document.getElementById("next-button"),
  removeEntryButton: document.getElementById("remove-entry-button"),
  clearPlaylistButton: document.getElementById("clear-playlist-button"),
  armButton: document.getElementById("arm-button"),
  resetButton: document.getElementById("reset-button"),
  clearLogButton: document.getElementById("clear-log-button"),
  playlistList: document.getElementById("playlist-list"),
  playlistSummary: document.getElementById("playlist-summary"),
  scriptSummary: document.getElementById("script-summary"),
  actionTable: document.getElementById("action-table"),
  log: document.getElementById("log"),
  logSummary: document.getElementById("log-summary"),
};

async function init() {
  bindEvents();
  ui.executionMode.value = DEFAULT_EXECUTION_MODE;
  ui.commandTemplate.value = DEFAULT_COMMAND_TEMPLATE;
  ui.lovenseRules.value = DEFAULT_RULES_TEXT;
  applyLovenseConfigToForm(DEFAULT_LOVENSE_CONFIG);
  await checkBackend();
  renderExecutionModeForm();
  renderLovenseToySelect("", []);
  renderLovenseRuleStatus();
  renderPlaylist();
  renderActionTable();
  renderStatus();
}

function bindEvents() {
  ui.addPlaylistButton.addEventListener("click", handleAddToPlaylist);
  ui.updateEntryButton.addEventListener("click", updateSelectedEntrySettings);
  ui.saveFunscriptButton.addEventListener("click", saveSelectedEntryToFunscript);
  ui.executionMode.addEventListener("change", () => {
    renderExecutionModeForm();
    renderLovenseRuleStatus();
  });
  ui.detectLovenseButton.addEventListener("click", detectLovenseDevices);
  ui.stopLovenseButton.addEventListener("click", () =>
    sendLovenseStopForCurrentEntry("Manual stop command sent.", { force: true }),
  );
  ui.lovenseToySelect.addEventListener("change", handleLovenseToySelectionChange);
  ui.lovenseRules.addEventListener("input", renderLovenseRuleStatus);
  ui.playSelectedButton.addEventListener("click", loadSelectedEntryIntoPlayer);
  ui.nextButton.addEventListener("click", playNextPlaylistEntry);
  ui.removeEntryButton.addEventListener("click", removeSelectedEntry);
  ui.clearPlaylistButton.addEventListener("click", clearPlaylist);
  ui.armButton.addEventListener("click", toggleArmedState);
  ui.resetButton.addEventListener("click", resetScheduler);
  ui.clearLogButton.addEventListener("click", clearLog);
  ui.playlistMode.addEventListener("change", handlePlaybackModeChange);
  ui.playlistList.addEventListener("click", handlePlaylistListClick);

  ui.video.addEventListener("play", startSchedulerLoop);
  ui.video.addEventListener("pause", handleVideoPause);
  ui.video.addEventListener("ended", handleVideoEnded);
  ui.video.addEventListener("timeupdate", renderStatus);
  ui.video.addEventListener("loadedmetadata", renderStatus);
  ui.video.addEventListener("seeked", resyncSchedulerToCurrentTime);
}

async function checkBackend() {
  try {
    const response = await fetch("/api/health", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    ui.backendStatus.textContent = "Connected";
  } catch (error) {
    ui.backendStatus.textContent = "Unavailable";
    appendLog({ ok: false, title: "Backend unavailable", detail: String(error) });
  }
}

function renderExecutionModeForm() {
  const isLovenseMode = ui.executionMode.value === "lovense-rules";
  ui.shellConfig.classList.toggle("hidden", isLovenseMode);
  ui.lovenseConfig.classList.toggle("hidden", !isLovenseMode);
}

async function detectLovenseDevices() {
  const config = getLovenseConfigFromForm();
  ui.lovenseStatus.textContent = "Detecting devices...";

  try {
    const response = await fetch("/api/lovense/detect", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        config,
        timeoutSeconds: 5,
      }),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }

    state.detectedToys = data.normalized?.toys ?? [];
    const preferredToyId = ui.lovenseToySelect.value || getCurrentEntry()?.lovense?.toyId || "";
    renderLovenseToySelect(preferredToyId, state.detectedToys);

    if (state.detectedToys.length) {
      const selectedToy = findToyById(ui.lovenseToySelect.value) ?? state.detectedToys[0];
      if (selectedToy && selectedToy.id !== ui.lovenseToySelect.value) {
        ui.lovenseToySelect.value = selectedToy.id;
      }
      updateLovenseSelectionDetails(selectedToy);
      ui.lovenseStatus.textContent = `Detected ${state.detectedToys.length} device(s).`;
    } else {
      updateLovenseSelectionDetails(null);
      ui.lovenseStatus.textContent = "No Lovense devices detected.";
    }
    renderLovenseRuleStatus();
  } catch (error) {
    state.detectedToys = [];
    renderLovenseToySelect("", []);
    updateLovenseSelectionDetails(null);
    renderLovenseRuleStatus();
    ui.lovenseStatus.textContent = "Device detection failed.";
    appendLog({
      ok: false,
      title: "Lovense detection failed",
      detail: String(error),
    });
  }
}

function handleLovenseToySelectionChange() {
  updateLovenseSelectionDetails(getSelectedLovenseToyData(getCurrentEntry()?.lovense));
  renderLovenseRuleStatus();
}

async function handleAddToPlaylist() {
  const videoFiles = Array.from(ui.videoFiles.files ?? []);
  const funscriptFiles = Array.from(ui.funscriptFiles.files ?? []);
  if (!videoFiles.length || !funscriptFiles.length) {
    appendLog({
      ok: false,
      title: "Could not extend playlist",
      detail: "Please select at least one video file and one funscript file.",
    });
    return;
  }

  try {
    validateCurrentFormForPersistence();
  } catch (error) {
    appendLog({ ok: false, title: "Could not extend playlist", detail: String(error) });
    return;
  }

  let parsedScripts;
  try {
    parsedScripts = await Promise.all(funscriptFiles.map(parseFunscriptFile));
  } catch (error) {
    appendLog({ ok: false, title: "Could not read funscript", detail: String(error) });
    return;
  }

  const pairing = pairVideosWithScripts(videoFiles, parsedScripts);
  if (!pairing.pairs.length) {
    appendLog({
      ok: false,
      title: "No valid pairs found",
      detail: "The selected videos and funscripts could not be matched.",
    });
    return;
  }

  const addedEntries = pairing.pairs.map(({ videoFile, scriptData }) => createPlaylistEntry(videoFile, scriptData));
  state.playlist.push(...addedEntries);

  if (!state.currentEntryId && addedEntries.length) {
    loadEntry(addedEntries[0].id);
  } else {
    renderPlaylist();
    renderStatus();
  }

  ui.videoFiles.value = "";
  ui.funscriptFiles.value = "";

  const details = [`Added ${addedEntries.length} entr${addedEntries.length === 1 ? "y" : "ies"}.`];
  if (pairing.fallbackPairs > 0) {
    details.push(`${pairing.fallbackPairs} pair(s) were matched by selection order instead of filename.`);
  }
  if (pairing.unmatchedVideos.length) {
    details.push(`Without funscript: ${pairing.unmatchedVideos.map((file) => file.name).join(", ")}`);
  }
  if (pairing.unmatchedScripts.length) {
    details.push(`Without video: ${pairing.unmatchedScripts.map((item) => item.file.name).join(", ")}`);
  }

  appendLog({ ok: true, title: "Playlist updated", detail: details.join("\n") });
}

function updateSelectedEntrySettings() {
  const entry = getCurrentEntry();
  if (!entry) {
    appendLog({ ok: false, title: "No playlist entry selected", detail: "Please select an entry first." });
    return;
  }

  try {
    validateCurrentFormForPersistence(entry);
  } catch (error) {
    appendLog({ ok: false, title: "Playlist entry not updated", detail: String(error) });
    return;
  }

  applyCurrentFormToEntry(entry);
  renderPlaylist();
  renderStatus();
  appendLog({
    ok: true,
    title: "Playlist entry updated",
    detail: `${entry.title} now uses ${formatExecutionMode(entry.executionMode)} with ${getEntryModeSummary(entry)}.`,
  });
}

async function saveSelectedEntryToFunscript() {
  const entry = getCurrentEntry();
  if (!entry) {
    appendLog({ ok: false, title: "No playlist entry selected", detail: "Please select an entry first." });
    return;
  }

  try {
    validateCurrentFormForPersistence(entry);
  } catch (error) {
    appendLog({ ok: false, title: "Funscript not saved", detail: String(error) });
    return;
  }

  applyCurrentFormToEntry(entry);

  const updatedDocument = buildSavedFunscriptDocument(entry);
  const content = `${JSON.stringify(updatedDocument, null, 2)}\n`;

  try {
    if (typeof window.showSaveFilePicker === "function") {
      const handle = await window.showSaveFilePicker({
        suggestedName: entry.funscriptName,
        types: [
          {
            description: "Funscript files",
            accept: {
              "application/json": [".funscript", ".json"],
            },
          },
        ],
      });

      const writable = await handle.createWritable();
      await writable.write(content);
      await writable.close();

      entry.scriptDocument = updatedDocument;
      appendLog({
        ok: true,
        title: "Funscript saved",
        detail: `${entry.funscriptName} was updated with FHPlayer settings under metadata.fhplayer.`,
      });
      return;
    }

    downloadTextFile(content, entry.funscriptName, "application/json");
    entry.scriptDocument = updatedDocument;
    appendLog({
      ok: true,
      title: "Funscript download prepared",
      detail: `Your browser does not support direct file saving here. Downloaded ${entry.funscriptName} with metadata.fhplayer settings.`,
    });
  } catch (error) {
    if (error?.name === "AbortError") {
      appendLog({
        ok: false,
        title: "Save cancelled",
        detail: "The funscript file was not changed.",
      });
      return;
    }

    appendLog({
      ok: false,
      title: "Could not save funscript",
      detail: String(error),
    });
  }
}

function loadSelectedEntryIntoPlayer() {
  if (!state.currentEntryId) {
    appendLog({ ok: false, title: "No playlist entry selected", detail: "Please select an entry first." });
    return;
  }
  loadEntry(state.currentEntryId);
}

function playNextPlaylistEntry() {
  const nextEntryId = getNextEntryId();
  if (!nextEntryId) {
    appendLog({
      ok: false,
      title: "No further video available",
      detail: "There is no next entry in the current playlist mode.",
    });
    return;
  }
  loadEntry(nextEntryId, { autoplay: !ui.video.paused });
}

function removeSelectedEntry() {
  const entry = getCurrentEntry();
  if (!entry) {
    appendLog({ ok: false, title: "No playlist entry selected", detail: "Please select an entry first." });
    return;
  }

  const currentIndex = state.playlist.findIndex((item) => item.id === entry.id);
  revokeEntryResources(entry);
  state.playlist = state.playlist.filter((item) => item.id !== entry.id);
  if (!state.playlist.length) {
    clearCurrentEntry();
  } else {
    const nextIndex = Math.min(currentIndex, state.playlist.length - 1);
    loadEntry(state.playlist[nextIndex].id);
  }

  appendLog({ ok: true, title: "Playlist entry removed", detail: `${entry.title} was removed from the playlist.` });
}

function clearPlaylist() {
  state.playlist.forEach(revokeEntryResources);
  state.playlist = [];
  clearCurrentEntry();
  renderPlaylist();
  renderStatus();
  appendLog({ ok: true, title: "Playlist cleared", detail: "All playlist entries were removed." });
}

function toggleArmedState() {
  state.armed = !state.armed;
  if (!state.armed) {
    clearScheduledLovenseActions();
    sendLovenseStopForCurrentEntry("Execution disabled. Sent stop to Lovense device.", { force: true });
  }
  renderStatus();
  appendLog({
    ok: true,
    title: state.armed ? "Execution enabled" : "Execution disabled",
    detail: state.armed ? "Actions will be executed during playback." : "Actions will not be sent to the backend.",
  });
}

function resetScheduler() {
  clearScheduledLovenseActions();
  syncSchedulerFromCurrentTime();
  renderStatus();
}

function handlePlaybackModeChange() {
  state.playbackMode = ui.playlistMode.value;
  renderStatus();
  renderPlaylist();
}

function clearLog() {
  ui.log.innerHTML = "";
  state.logCount = 0;
  ui.logSummary.textContent = "Log cleared.";
}

function resyncSchedulerToCurrentTime() {
  clearScheduledLovenseActions();
  sendLovenseStopForCurrentEntry(null, { force: true });
  syncSchedulerFromCurrentTime();
  renderStatus();
}

function startSchedulerLoop() {
  if (state.rafId !== null) {
    cancelAnimationFrame(state.rafId);
  }

  const loop = () => {
    processPlaybackPosition();
    if (!ui.video.paused && !ui.video.ended) {
      state.rafId = requestAnimationFrame(loop);
    }
  };

  state.rafId = requestAnimationFrame(loop);
}

function stopSchedulerLoop() {
  if (state.rafId !== null) {
    cancelAnimationFrame(state.rafId);
    state.rafId = null;
  }
}

function handleVideoPause() {
  stopSchedulerLoop();
  clearScheduledLovenseActions();
  sendLovenseStopForCurrentEntry("Playback paused. Sent stop to Lovense device.");
}

function processPlaybackPosition() {
  const entry = getCurrentEntry();
  if (!entry) {
    return;
  }

  const currentMs = ui.video.currentTime * 1000;
  ui.currentTime.textContent = formatMs(currentMs);
  while (state.nextActionIndex < entry.actions.length && entry.actions[state.nextActionIndex].atMs <= currentMs) {
    const action = entry.actions[state.nextActionIndex];
    state.nextActionIndex += 1;
    state.lastTriggeredIndex = action.index;
    highlightActionRow(action.index);
    renderStatus();

    if (state.armed) {
      triggerAction(entry, action, currentMs);
    }
  }

  renderStatus();
}

function syncSchedulerFromCurrentTime() {
  const entry = getCurrentEntry();
  const actions = entry?.actions ?? [];
  const currentMs = ui.video.currentTime * 1000;
  state.nextActionIndex = findNextActionIndex(actions, currentMs);
  state.lastTriggeredIndex = state.nextActionIndex > 0 ? state.nextActionIndex - 1 : null;
  highlightActionRow(state.lastTriggeredIndex);
}

function triggerAction(entry, action, currentMs) {
  if (entry.executionMode === "lovense-rules") {
    triggerLovenseRuleAction(entry, action, currentMs);
    return;
  }

  triggerShellAction(entry, action, currentMs);
}

function triggerShellAction(entry, action, currentMs) {
  const payload = {
    index: action.index,
    atMs: action.atMs,
    pos: action.pos,
    currentMs: Math.round(currentMs),
    deltaMs: Math.round(currentMs - action.atMs),
    previousAtMs: action.previousAtMs ?? "",
    nextAtMs: action.nextAtMs ?? "",
    entryTitle: entry.title,
  };
  const command = applyTemplate(entry.commandTemplate, payload);
  state.pendingExecutions += 1;
  renderStatus();

  fetch("/api/execute", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      command,
      shell: entry.shell,
      timeoutSeconds: entry.timeoutSeconds,
      dryRun: ui.dryRun.checked,
      event: payload,
    }),
  })
    .then(async (response) => ({ ok: response.ok, data: await response.json() }))
    .then(({ ok, data }) => {
      appendLog({
        ok: ok && data.ok,
        title: `Action ${action.index} at ${formatMs(action.atMs)} in ${entry.title}`,
        detail: buildExecutionDetail(command, data, entry),
      });
    })
    .catch((error) => {
      appendLog({ ok: false, title: `Action ${action.index} failed`, detail: `${entry.title}\n${String(error)}` });
    })
    .finally(() => {
      state.pendingExecutions = Math.max(0, state.pendingExecutions - 1);
      renderStatus();
    });
}

async function triggerLovenseRuleAction(entry, action, currentMs) {
  const context = {
    index: action.index,
    atMs: action.atMs,
    pos: action.pos,
    currentMs: Math.round(currentMs),
    deltaMs: Math.round(currentMs - action.atMs),
  };

  let commands;
  try {
    commands = buildLovenseCommandsFromRules(entry, context);
  } catch (error) {
    appendLog({
      ok: false,
      title: `Lovense rule error at action ${action.index}`,
      detail: String(error),
    });
    return;
  }

  if (!commands.length) {
    return;
  }

  const batches = groupLovenseCommandsByDelay(commands);
  batches.forEach((batch, batchIndex) => {
    scheduleLovenseCommandBatch(entry, action, batch, batchIndex === 0);
  });
}

function groupLovenseCommandsByDelay(commands) {
  const batches = new Map();
  commands.forEach((command) => {
    const delayMs = command.delayMs ?? 0;
    if (!batches.has(delayMs)) {
      batches.set(delayMs, []);
    }
    batches.get(delayMs).push(command);
  });

  return [...batches.entries()]
    .sort((left, right) => left[0] - right[0])
    .map(([delayMs, groupedCommands]) => ({ delayMs, commands: groupedCommands }));
}

function scheduleLovenseCommandBatch(entry, action, batch, isFirstBatch) {
  const executeBatch = () => {
    const currentEntry = getCurrentEntry();
    if (!state.armed || !currentEntry || currentEntry.id !== entry.id) {
      return;
    }

    sendLovenseCommandBatch(entry, action, batch, isFirstBatch);
  };

  if (batch.delayMs <= 0) {
    executeBatch();
    return;
  }

  const timerId = window.setTimeout(() => {
    state.scheduledLovenseTimers.delete(timerId);
    executeBatch();
  }, batch.delayMs);
  state.scheduledLovenseTimers.add(timerId);
}

async function sendLovenseCommandBatch(entry, action, batch, isFirstBatch) {
  state.pendingExecutions += 1;
  renderStatus();

  const payloadCommands = batch.commands.map((command, commandIndex) => ({
    ...command,
    delayMs: undefined,
    stopPrevious: isFirstBatch && commandIndex === 0 ? 1 : 0,
  }));

  try {
    const response = await fetch("/api/lovense/command", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        config: buildLovenseRequestConfig(entry.lovense),
        timeoutSeconds: 5,
        commands: payloadCommands,
      }),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }

    appendLog({
      ok: true,
      title: `Lovense action ${action.index} at ${formatMs(action.atMs)}`,
      detail: [
        `Device: ${entry.lovense.toyName || entry.lovense.toyId || "current selection"}`,
        `Delay: ${batch.delayMs} ms`,
        `Commands: ${batch.commands.map((item) => `${item.action}${item.strength !== undefined ? `:${item.strength}` : ""}`).join(", ")}`,
      ].join("\n"),
    });
  } catch (error) {
    appendLog({
      ok: false,
      title: `Lovense action ${action.index} failed`,
      detail: `${batch.delayMs} ms delay\n${String(error)}`,
    });
  } finally {
    state.pendingExecutions = Math.max(0, state.pendingExecutions - 1);
    renderStatus();
  }
}

function applyTemplate(template, values) {
  return template.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_, key) => (key in values ? String(values[key]) : ""));
}

function buildExecutionDetail(command, response, entry) {
  const lines = [
    `Video: ${entry.title}`,
    `Command: ${command}`,
    `Shell: ${response.shell ?? "-"}`,
    `Return code: ${response.result?.returnCode ?? "-"}`,
    `Duration: ${response.result?.durationMs ?? "-"} ms`,
  ];
  if (response.result?.stdout) {
    lines.push(`STDOUT:\n${response.result.stdout}`);
  }
  if (response.result?.stderr) {
    lines.push(`STDERR:\n${response.result.stderr}`);
  }
  return lines.join("\n");
}

function renderActionTable() {
  const entry = getCurrentEntry();
  const actions = entry?.actions ?? [];
  ui.actionTable.innerHTML = actions
    .map(
      (action) => `
        <tr data-action-index="${action.index}">
          <td>${action.index}</td>
          <td>${formatMs(action.atMs)}</td>
          <td>${action.pos}</td>
        </tr>
      `,
    )
    .join("");
}

function highlightActionRow(index) {
  if (state.highlightedActionIndex !== null) {
    ui.actionTable.querySelector(`[data-action-index="${state.highlightedActionIndex}"]`)?.classList.remove("active-row");
  }
  if (index !== null) {
    const row = ui.actionTable.querySelector(`[data-action-index="${index}"]`);
    row?.classList.add("active-row");
  }
  state.highlightedActionIndex = index;
}

function renderPlaylist() {
  ui.playlistCount.textContent = `${state.playlist.length} entries`;
  ui.playlistSummary.textContent = state.playlist.length
    ? `${state.playlist.length} entries loaded. Current mode: ${formatPlaybackMode(state.playbackMode)}`
    : "No entries yet.";

  ui.playlistList.innerHTML = state.playlist
    .map(
      (entry, index) => `
        <article class="playlist-item${entry.id === state.currentEntryId ? " selected" : ""}" data-entry-id="${entry.id}">
          <div class="playlist-item-main" data-action="select" data-entry-id="${entry.id}">
            <strong>${escapeHtml(entry.title)}</strong>
            <span>${escapeHtml(entry.funscriptName)} | ${entry.actions.length} actions</span>
            <span>${escapeHtml(formatExecutionMode(entry.executionMode))} | ${escapeHtml(getEntryModeSummary(entry))} | #${index + 1}</span>
          </div>
          <div class="playlist-item-actions">
            <button class="secondary small" data-action="select" data-entry-id="${entry.id}">Load</button>
            <button class="secondary small" data-action="remove" data-entry-id="${entry.id}">Remove</button>
          </div>
        </article>
      `,
    )
    .join("");
}

function renderStatus() {
  const entry = getCurrentEntry();
  const actions = entry?.actions ?? [];
  const nextAction = actions[state.nextActionIndex] ?? null;
  const lastAction = state.lastTriggeredIndex !== null ? actions[state.lastTriggeredIndex] : null;

  ui.playlistCount.textContent = `${state.playlist.length} entries`;
  ui.playlistModeStatus.textContent = formatPlaybackMode(state.playbackMode);
  ui.armedStatus.textContent = state.armed ? "Enabled" : "Disabled";
  ui.pendingCount.textContent = String(state.pendingExecutions);
  ui.armButton.textContent = state.armed ? "Disable execution" : "Enable execution";
  ui.currentTime.textContent = formatMs(ui.video.currentTime * 1000);
  ui.currentEntryTitle.textContent = entry ? entry.title : "No playlist entry loaded";
  ui.currentEntryMeta.textContent = entry
    ? `${entry.funscriptName} | ${actions.length} actions | ${formatExecutionMode(entry.executionMode)} | ${getEntryModeSummary(entry)}`
    : "Add a video and funscript to the playlist.";
  ui.scriptSummary.textContent = entry
    ? `${entry.funscriptName} | ${actions.length} actions | range ${entry.range} | ${entry.inverted ? "inverted" : "normal"}`
    : "No playlist entry loaded.";
  ui.nextAction.textContent = nextAction ? `${nextAction.index} @ ${formatMs(nextAction.atMs)}` : "-";
  ui.lastAction.textContent = lastAction ? `${lastAction.index} @ ${formatMs(lastAction.atMs)}` : "-";
}

function appendLog(entry) {
  state.logCount += 1;
  ui.logSummary.textContent = `${state.logCount} entries`;
  const item = document.createElement("article");
  item.className = `log-entry ${entry.ok ? "ok" : "error"}`;
  item.innerHTML = `
    <strong>${escapeHtml(entry.title)}</strong>
    <span>${new Date().toLocaleTimeString("en-US")}</span>
    <pre>${escapeHtml(entry.detail)}</pre>
  `;
  ui.log.prepend(item);
}

function handlePlaylistListClick(event) {
  const entryId = event.target.dataset.entryId ?? event.target.closest("[data-entry-id]")?.dataset.entryId;
  const action = event.target.dataset.action ?? "select";
  if (!entryId) {
    return;
  }

  if (action === "remove") {
    state.currentEntryId = entryId;
    removeSelectedEntry();
    return;
  }

  loadEntry(entryId);
}

async function parseFunscriptFile(file) {
  const text = await file.text();
  const parsed = JSON.parse(text);
  const actions = (Array.isArray(parsed.actions) ? parsed.actions : [])
    .map((action, index) => ({ index, atMs: Number(action.at), pos: Number(action.pos) }))
    .filter((action) => Number.isFinite(action.atMs) && Number.isFinite(action.pos))
    .sort((left, right) => left.atMs - right.atMs)
    .map((action, index, all) => ({
      ...action,
      index,
      previousAtMs: index > 0 ? all[index - 1].atMs : null,
      nextAtMs: index < all.length - 1 ? all[index + 1].atMs : null,
    }));

  return {
    file,
    stem: normalizeStem(file.name),
    parsed,
    actions,
    settings: extractScriptSettings(parsed),
  };
}

function pairVideosWithScripts(videoFiles, parsedScripts) {
  const pairs = [];
  const unmatchedVideos = [];
  const unusedScriptIndexes = new Set(parsedScripts.map((_, index) => index));

  videoFiles.forEach((videoFile) => {
    const directMatchIndex = parsedScripts.findIndex(
      (scriptData, index) => unusedScriptIndexes.has(index) && scriptData.stem === normalizeStem(videoFile.name),
    );
    if (directMatchIndex >= 0) {
      pairs.push({ videoFile, scriptData: parsedScripts[directMatchIndex] });
      unusedScriptIndexes.delete(directMatchIndex);
    } else {
      unmatchedVideos.push(videoFile);
    }
  });

  const remainingScriptIndexes = [...unusedScriptIndexes];
  const fallbackPairs = Math.min(unmatchedVideos.length, remainingScriptIndexes.length);
  for (let index = 0; index < fallbackPairs; index += 1) {
    pairs.push({ videoFile: unmatchedVideos[index], scriptData: parsedScripts[remainingScriptIndexes[index]] });
    unusedScriptIndexes.delete(remainingScriptIndexes[index]);
  }

  return {
    pairs,
    fallbackPairs,
    unmatchedVideos: unmatchedVideos.slice(fallbackPairs),
    unmatchedScripts: [...unusedScriptIndexes].map((index) => parsedScripts[index]),
  };
}

function createPlaylistEntry(videoFile, scriptData) {
  const settings = resolveInitialEntrySettings(scriptData.settings);
  return {
    id: `entry-${state.playlistCounter += 1}`,
    title: stripExtension(videoFile.name),
    videoUrl: URL.createObjectURL(videoFile),
    funscriptName: scriptData.file.name,
    actions: scriptData.actions,
    range: scriptData.parsed.range ?? "-",
    inverted: Boolean(scriptData.parsed.inverted),
    scriptDocument: scriptData.parsed,
    executionMode: settings.executionMode,
    shell: settings.shell,
    timeoutSeconds: settings.timeoutSeconds,
    commandTemplate: settings.commandTemplate,
    rulesText: settings.rulesText,
    lovense: settings.lovense,
  };
}

function resolveInitialEntrySettings(scriptSettings) {
  const formExecutionMode = ui.executionMode.value;
  const formCommand = normalizeCommandTemplate(ui.commandTemplate.value);
  const formShell = ui.shell.value;
  const formTimeout = clampTimeoutSeconds(Number(ui.timeoutSeconds.value));
  const formRulesText = normalizeRulesText(ui.lovenseRules.value);
  const selectedToy = getSelectedLovenseToyData(scriptSettings.lovense);
  const formLovense = normalizeLovenseConfig({
    ...getLovenseConfigFromForm(),
    toyName: selectedToy?.nickName || selectedToy?.name || scriptSettings.lovense?.toyName || "",
    toyType: selectedToy?.type || scriptSettings.lovense?.toyType || "",
    capabilities: selectedToy?.fullFunctionNames ?? scriptSettings.lovense?.capabilities ?? [],
  });
  return {
    executionMode:
      formExecutionMode !== DEFAULT_EXECUTION_MODE
        ? formExecutionMode
        : scriptSettings.executionMode || DEFAULT_EXECUTION_MODE,
    commandTemplate:
      formCommand !== DEFAULT_COMMAND_TEMPLATE ? formCommand : scriptSettings.commandTemplate || DEFAULT_COMMAND_TEMPLATE,
    shell: formShell !== DEFAULT_SHELL ? formShell : scriptSettings.shell || DEFAULT_SHELL,
    timeoutSeconds:
      Math.abs(formTimeout - DEFAULT_TIMEOUT_SECONDS) > 0.0001 ? formTimeout : scriptSettings.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS,
    rulesText: formRulesText !== DEFAULT_RULES_TEXT ? formRulesText : scriptSettings.rulesText || DEFAULT_RULES_TEXT,
    lovense: isLovenseConfigCustomized(formLovense) ? formLovense : normalizeLovenseConfig(scriptSettings.lovense),
  };
}

function extractScriptSettings(parsed) {
  const fhplayer = parsed && typeof parsed.fhplayer === "object" ? parsed.fhplayer : {};
  const metadata = parsed && typeof parsed.metadata === "object" ? parsed.metadata : {};
  const metadataFhplayer = metadata && typeof metadata.fhplayer === "object" ? metadata.fhplayer : {};
  const metadataFhPlayer = metadata && typeof metadata.fh_player === "object" ? metadata.fh_player : {};
  const lovense = metadataFhplayer.lovense || metadataFhPlayer.lovense || fhplayer.lovense || parsed.lovense || {};
  return {
    executionMode: firstNonEmpty(
      metadataFhplayer.executionMode,
      metadataFhPlayer.executionMode,
      fhplayer.executionMode,
      parsed.executionMode,
    ),
    commandTemplate: firstNonEmpty(
      metadataFhplayer.commandTemplate,
      metadataFhplayer.command,
      metadataFhPlayer.commandTemplate,
      metadataFhPlayer.command,
      fhplayer.commandTemplate,
      fhplayer.command,
      parsed.commandTemplate,
      parsed.command,
    ),
    shell: firstNonEmpty(metadataFhplayer.shell, metadataFhPlayer.shell, fhplayer.shell, parsed.shell),
    timeoutSeconds: clampOptionalNumber(
      firstFiniteNumber(
        metadataFhplayer.timeoutSeconds,
        metadataFhPlayer.timeoutSeconds,
        fhplayer.timeoutSeconds,
        parsed.timeoutSeconds,
      ),
    ),
    rulesText: firstNonEmpty(metadataFhplayer.rulesText, metadataFhPlayer.rulesText, fhplayer.rulesText, parsed.rulesText),
    lovense: normalizeLovenseConfig(lovense),
  };
}

function applyCurrentFormToEntry(entry) {
  const selectedToy = getSelectedLovenseToyData(entry.lovense);
  entry.executionMode = ui.executionMode.value;
  entry.commandTemplate = normalizeCommandTemplate(ui.commandTemplate.value);
  entry.shell = ui.shell.value;
  entry.timeoutSeconds = clampTimeoutSeconds(Number(ui.timeoutSeconds.value));
  entry.rulesText = normalizeRulesText(ui.lovenseRules.value);
  entry.lovense = normalizeLovenseConfig({
    ...getLovenseConfigFromForm(),
    toyName: selectedToy?.nickName || selectedToy?.name || entry.lovense?.toyName || "",
    toyType: selectedToy?.type || entry.lovense?.toyType || "",
    capabilities: selectedToy?.fullFunctionNames ?? entry.lovense?.capabilities ?? [],
  });
}

function buildSavedFunscriptDocument(entry) {
  const documentCopy = cloneJson(entry.scriptDocument ?? {});
  const metadata = documentCopy.metadata && typeof documentCopy.metadata === "object" ? documentCopy.metadata : {};

  metadata.fhplayer = {
    schemaVersion: 2,
    executionMode: entry.executionMode,
    commandTemplate: entry.commandTemplate,
    shell: entry.shell,
    timeoutSeconds: entry.timeoutSeconds,
    rulesText: entry.rulesText,
    lovense: {
      scheme: entry.lovense.scheme,
      host: entry.lovense.host,
      port: entry.lovense.port,
      platformName: entry.lovense.platformName,
      toyId: entry.lovense.toyId,
      toyName: entry.lovense.toyName,
      toyType: entry.lovense.toyType,
      capabilities: entry.lovense.capabilities,
    },
  };

  documentCopy.metadata = metadata;
  return documentCopy;
}

function getLovenseConfigFromForm() {
  const selectedToy = getSelectedLovenseToyData();
  return normalizeLovenseConfig({
    scheme: ui.lovenseScheme.value,
    host: ui.lovenseHost.value,
    port: ui.lovensePort.value,
    platformName: ui.lovensePlatformName.value,
    toyId: ui.lovenseToySelect.value,
    toyName: selectedToy?.nickName || selectedToy?.name || "",
    toyType: selectedToy?.type || "",
    capabilities: selectedToy?.fullFunctionNames ?? [],
  });
}

function applyLovenseConfigToForm(config) {
  const normalized = normalizeLovenseConfig(config);
  ui.lovenseScheme.value = normalized.scheme;
  ui.lovenseHost.value = normalized.host;
  ui.lovensePort.value = normalized.port;
  ui.lovensePlatformName.value = normalized.platformName;
}

function normalizeLovenseConfig(config) {
  const merged = {
    ...DEFAULT_LOVENSE_CONFIG,
    ...(config || {}),
  };
  return {
    scheme: String(merged.scheme || DEFAULT_LOVENSE_CONFIG.scheme).trim().toLowerCase() || DEFAULT_LOVENSE_CONFIG.scheme,
    host: String(merged.host || DEFAULT_LOVENSE_CONFIG.host).trim() || DEFAULT_LOVENSE_CONFIG.host,
    port: String(merged.port || DEFAULT_LOVENSE_CONFIG.port).trim() || DEFAULT_LOVENSE_CONFIG.port,
    platformName: String(merged.platformName || DEFAULT_LOVENSE_CONFIG.platformName).trim() || DEFAULT_LOVENSE_CONFIG.platformName,
    toyId: String(merged.toyId || "").trim(),
    toyName: String(merged.toyName || "").trim(),
    toyType: String(merged.toyType || "").trim(),
    capabilities: Array.isArray(merged.capabilities) ? [...merged.capabilities] : [],
  };
}

function normalizeRulesText(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed || DEFAULT_RULES_TEXT;
}

function getSelectedLovenseToyData(fallbackLovense = null) {
  const selectedToyId = ui.lovenseToySelect.value;
  const detectedToy = findToyById(selectedToyId);
  if (detectedToy) {
    return detectedToy;
  }

  if (fallbackLovense?.toyId && fallbackLovense.toyId === selectedToyId) {
    return {
      id: fallbackLovense.toyId,
      name: fallbackLovense.toyName || fallbackLovense.toyType || fallbackLovense.toyId,
      nickName: fallbackLovense.toyName || "",
      type: fallbackLovense.toyType || fallbackLovense.type || "",
      fullFunctionNames: fallbackLovense.capabilities || [],
    };
  }

  return null;
}

function getNormalizedCapabilityList(source) {
  const rawCapabilities = Array.isArray(source?.fullFunctionNames)
    ? source.fullFunctionNames
    : Array.isArray(source?.capabilities)
      ? source.capabilities
      : [];

  const capabilities = [];
  rawCapabilities.forEach((value) => {
    const normalized = String(value || "").trim().toLowerCase();
    const canonical =
      Object.values(LOVENSE_ACTIONS).find((definition) => definition.apiName.toLowerCase() === normalized)?.apiName ||
      String(value || "").trim();

    if (canonical && !capabilities.includes(canonical)) {
      capabilities.push(canonical);
    }
  });

  return capabilities;
}

function getLovenseDeviceProfile(lovense) {
  const capabilities = getNormalizedCapabilityList(lovense);
  const deviceType = String(lovense?.toyType || lovense?.type || lovense?.toyName || "").trim() || "Unknown";
  const maxSimultaneousActions = Math.max(1, capabilities.length || 1);

  return {
    deviceType,
    capabilities,
    maxSimultaneousActions,
    supportsMultipleActions: maxSimultaneousActions > 1,
  };
}

function getAllowedLovenseActions(profile) {
  const actions = [];
  if (profile.capabilities.length) {
    Object.entries(LOVENSE_ACTIONS).forEach(([actionKey, definition]) => {
      if (actionKey === "stop" || actionKey === "all" || profile.capabilities.includes(definition.apiName)) {
        actions.push(actionKey);
      }
    });
  } else {
    actions.push("stop");
  }
  return actions;
}

function validateCurrentFormForPersistence(entry = null) {
  if (ui.executionMode.value !== "lovense-rules") {
    return;
  }

  const selectedToy = getSelectedLovenseToyData(entry?.lovense);
  const lovenseConfig = normalizeLovenseConfig({
    ...getLovenseConfigFromForm(),
    toyName: selectedToy?.nickName || selectedToy?.name || entry?.lovense?.toyName || "",
    toyType: selectedToy?.type || entry?.lovense?.toyType || entry?.lovense?.type || "",
    capabilities: selectedToy?.fullFunctionNames ?? entry?.lovense?.capabilities ?? [],
  });

  validateLovenseRulesForConfig(ui.lovenseRules.value, lovenseConfig);
}

function isLovenseConfigCustomized(config) {
  const normalized = normalizeLovenseConfig(config);
  return (
    normalized.scheme !== DEFAULT_LOVENSE_CONFIG.scheme ||
    normalized.host !== DEFAULT_LOVENSE_CONFIG.host ||
    normalized.port !== DEFAULT_LOVENSE_CONFIG.port ||
    normalized.platformName !== DEFAULT_LOVENSE_CONFIG.platformName ||
    normalized.toyId !== "" ||
    normalized.capabilities.length > 0
  );
}

function renderLovenseToySelect(selectedToyId, toys, fallbackToy = null) {
  const options = [...toys];
  if (fallbackToy?.toyId && !options.some((toy) => toy.id === fallbackToy.toyId)) {
    options.push({
      id: fallbackToy.toyId,
      name: fallbackToy.toyName || fallbackToy.toyType || fallbackToy.toyId,
      nickName: fallbackToy.toyName || "",
      type: fallbackToy.toyType || "",
      fullFunctionNames: fallbackToy.capabilities || [],
    });
  }

  ui.lovenseToySelect.innerHTML = [
    '<option value="">No device selected</option>',
    ...options.map((toy) => {
      const labelParts = [toy.nickName || toy.name || toy.id];
      if (toy.type && toy.type !== toy.name) {
        labelParts.push(toy.type);
      }
      if (Array.isArray(toy.fullFunctionNames) && toy.fullFunctionNames.length) {
        labelParts.push(toy.fullFunctionNames.join("/"));
      }
      return `<option value="${escapeHtml(toy.id)}">${escapeHtml(labelParts.join(" | "))}</option>`;
    }),
  ].join("");

  ui.lovenseToySelect.value = selectedToyId || "";
}

function findToyById(toyId) {
  return state.detectedToys.find((toy) => toy.id === toyId) ?? null;
}

function updateLovenseSelectionDetails(toy) {
  if (!toy) {
    ui.lovenseCapabilities.value = "-";
    ui.lovenseDeviceType.value = "-";
    ui.lovenseParallelActions.value = "-";
    return;
  }

  const profile = getLovenseDeviceProfile(toy);
  ui.lovenseCapabilities.value = profile.capabilities.length ? profile.capabilities.join(", ") : "-";
  ui.lovenseDeviceType.value = profile.deviceType;
  ui.lovenseParallelActions.value = profile.supportsMultipleActions
    ? `Up to ${profile.maxSimultaneousActions} actions at once`
    : "Single action only";
}

function renderLovenseRuleStatus() {
  if (ui.executionMode.value !== "lovense-rules") {
    ui.lovenseRuleStatus.className = "status-note muted";
    ui.lovenseRuleStatus.textContent = "Lovense rule validation is active when Lovense rules mode is selected.";
    return;
  }

  const currentEntry = getCurrentEntry();
  const selectedToy = findToyById(ui.lovenseToySelect.value);
  const fallbackConfig = selectedToy
    ? selectedToy
    : normalizeLovenseConfig({
        ...currentEntry?.lovense,
        toyId: ui.lovenseToySelect.value || currentEntry?.lovense?.toyId || "",
        toyType: currentEntry?.lovense?.toyType || "",
        capabilities: currentEntry?.lovense?.capabilities ?? [],
      });

  try {
    const { profile, compiled } = validateLovenseRulesForConfig(ui.lovenseRules.value, fallbackConfig);
    const actionList = getAllowedLovenseActions(profile).join(", ");
    ui.lovenseRuleStatus.className = "status-note ok";
    ui.lovenseRuleStatus.textContent =
      `Valid rule script. Device type: ${profile.deviceType}. Allowed actions: ${actionList}. ` +
      `Parallel actions: ${profile.supportsMultipleActions ? `up to ${profile.maxSimultaneousActions}` : "single action only"}. ` +
      `Variables: ${compiled.assignments.length}. Branches: ${compiled.branches.length}.`;
  } catch (error) {
    ui.lovenseRuleStatus.className = "status-note error";
    ui.lovenseRuleStatus.textContent = String(error);
  }
}

function buildLovenseRequestConfig(lovense) {
  const normalized = normalizeLovenseConfig(lovense);
  return {
    scheme: normalized.scheme,
    host: normalized.host,
    port: normalized.port,
    platformName: normalized.platformName,
  };
}

function clearScheduledLovenseActions() {
  state.scheduledLovenseTimers.forEach((timerId) => {
    clearTimeout(timerId);
  });
  state.scheduledLovenseTimers.clear();
}

async function sendLovenseStopForCurrentEntry(logDetail, options = {}) {
  const { force = false } = options;
  const entry = getCurrentEntry();
  if (!entry || entry.executionMode !== "lovense-rules" || (!state.armed && !force)) {
    return;
  }
  if (!entry.lovense?.host || !entry.lovense?.port) {
    return;
  }

  try {
    await fetch("/api/lovense/command", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        config: buildLovenseRequestConfig(entry.lovense),
        timeoutSeconds: 5,
        commands: [
          {
            command: "Function",
            action: "Stop",
            timeSec: 0,
            toy: entry.lovense.toyId || "",
            apiVer: 1,
            stopPrevious: 1,
          },
        ],
      }),
    });

    if (logDetail) {
      appendLog({
        ok: true,
        title: "Lovense stop sent",
        detail: logDetail,
      });
    }
  } catch (error) {
    appendLog({
      ok: false,
      title: "Lovense stop failed",
      detail: String(error),
    });
  }
}

function validateLovenseRulesForConfig(rulesText, lovense) {
  const normalizedLovense = normalizeLovenseConfig({
    ...lovense,
    toyId: lovense?.toyId || lovense?.id || "",
    toyType: lovense?.toyType || lovense?.type || "",
    capabilities: getNormalizedCapabilityList(lovense),
  });

  if (!normalizedLovense.toyId) {
    throw new Error("Select a detected Lovense device before using Lovense rules.");
  }

  const profile = getLovenseDeviceProfile(normalizedLovense);
  if (!profile.capabilities.length) {
    throw new Error(`No supported Lovense capabilities were detected for ${profile.deviceType}.`);
  }

  const compiled = parseRuleScript(rulesText);
  compiled.branches.forEach((branch) => {
    if (branch.commands.length > profile.maxSimultaneousActions) {
      throw new Error(
        `Line ${branch.lineNumber}: ${profile.deviceType} supports ${profile.maxSimultaneousActions} action(s) at once, ` +
          `but ${branch.commands.length} were configured.`,
      );
    }

    branch.commands.forEach((command) => {
      const canonical = LOVENSE_ACTIONS[command.actionKey];
      if (command.actionKey === "stop" || command.actionKey === "all") {
        return;
      }
      if (!profile.capabilities.includes(canonical.apiName)) {
        throw new Error(`Line ${command.lineNumber}: ${profile.deviceType} does not support ${canonical.apiName}.`);
      }
    });
  });

  return { compiled, profile, lovense: normalizedLovense };
}

function buildLovenseCommandsFromRules(entry, context) {
  const { compiled, lovense } = validateLovenseRulesForConfig(entry.rulesText, entry.lovense);
  const scope = buildRuleScope(compiled.assignments, context);
  const matchedBranch = compiled.branches.find((branch) => branch.condition === null || evaluateBooleanExpression(branch.condition, scope));
  if (!matchedBranch) {
    return [];
  }

  return matchedBranch.commands.map((command, index) => {
    const canonical = LOVENSE_ACTIONS[command.actionKey];
    const value =
      command.actionKey === "stop"
        ? 0
        : normalizeRuleNumericValue(
            evaluateNumericExpression(command.valueExpression, scope),
            canonical.min,
            canonical.max,
            command.lineNumber,
            canonical.apiName,
          );
    const delayMs = command.delayExpression
      ? normalizeRuleDelayMs(evaluateNumericExpression(command.delayExpression, scope), command.lineNumber)
      : 0;
    return {
      command: "Function",
      action: command.actionKey === "stop" ? "Stop" : `${canonical.apiName}:${value}`,
      strength: value,
      timeSec: 0,
      toy: lovense.toyId,
      stopPrevious: index === 0 ? 1 : 0,
      apiVer: 1,
      delayMs,
    };
  });
}

function parseRuleScript(scriptText) {
  const lines = normalizeRulesText(scriptText)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#") && !line.startsWith("//"));

  if (!lines.length) {
    throw new Error("Rule script is empty.");
  }

  const assignments = [];
  const branches = [];
  const knownVariables = new Set(BASE_RULE_VARIABLES);
  lines.forEach((line, index) => {
    const lineNumber = index + 1;
    if (/^let\s+/i.test(line)) {
      if (branches.length) {
        throw new Error(`Variables must be declared before rule branches. Invalid let on line ${lineNumber}.`);
      }
      assignments.push(parseVariableAssignment(line, lineNumber, knownVariables));
      return;
    }

    if (/^if\s+/i.test(line)) {
      const match = line.match(/^if\s+(.+?)\s+then\s+(.+)$/i);
      if (!match) {
        throw new Error(`Invalid if syntax on line ${lineNumber}.`);
      }
      branches.push({
        condition: parseConditionExpression(match[1].trim(), lineNumber, knownVariables),
        commands: parseCommandList(match[2].trim(), lineNumber, knownVariables),
        lineNumber,
      });
      return;
    }

    if (/^else\s+if\s+/i.test(line)) {
      const match = line.match(/^else\s+if\s+(.+?)\s+then\s+(.+)$/i);
      if (!match) {
        throw new Error(`Invalid else if syntax on line ${lineNumber}.`);
      }
      branches.push({
        condition: parseConditionExpression(match[1].trim(), lineNumber, knownVariables),
        commands: parseCommandList(match[2].trim(), lineNumber, knownVariables),
        lineNumber,
      });
      return;
    }

    if (/^else\s+/i.test(line)) {
      const match = line.match(/^else\s+(.+)$/i);
      if (!match) {
        throw new Error(`Invalid else syntax on line ${lineNumber}.`);
      }
      branches.push({ condition: null, commands: parseCommandList(match[1].trim(), lineNumber, knownVariables), lineNumber });
      return;
    }

    branches.push({ condition: null, commands: parseCommandList(line, lineNumber, knownVariables), lineNumber });
  });

  if (!branches.length) {
    throw new Error("Rule script does not contain any executable branch.");
  }

  return { assignments, branches };
}

function parseVariableAssignment(line, lineNumber, knownVariables) {
  const match = line.match(/^let\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$/i);
  if (!match) {
    throw new Error(`Invalid variable syntax on line ${lineNumber}. Use let name = expression.`);
  }

  const variableName = match[1];
  const normalizedName = variableName.toLowerCase();
  if (RULE_VARIABLES.has(variableName) || normalizedName === "and" || normalizedName === "or") {
    throw new Error(`Variable ${variableName} on line ${lineNumber} uses a reserved name.`);
  }
  if (knownVariables.has(variableName)) {
    throw new Error(`Variable ${variableName} is already defined before line ${lineNumber}.`);
  }

  const expression = parseNumericExpression(match[2].trim(), lineNumber, knownVariables);
  knownVariables.add(variableName);
  return { type: "assignment", name: variableName, expression, lineNumber };
}

function parseCommandList(commandText, lineNumber, knownVariables) {
  const parts = splitTopLevel(commandText, "+").map((part) => part.trim()).filter(Boolean);
  if (!parts.length) {
    throw new Error(`No command found on line ${lineNumber}.`);
  }

  const commands = parts.map((part) => parseSingleCommand(part, lineNumber, knownVariables));
  const duplicateAction = commands.find((command, index) =>
    commands.findIndex((candidate) => candidate.actionKey === command.actionKey) !== index,
  );
  if (duplicateAction) {
    throw new Error(`Action ${duplicateAction.actionKey} is used more than once on line ${lineNumber}.`);
  }
  if (commands.length > 1 && commands.some((command) => command.actionKey === "stop")) {
    throw new Error(`stop() cannot be combined with other actions on line ${lineNumber}.`);
  }
  if (commands.length > 1 && commands.some((command) => command.actionKey === "all")) {
    throw new Error(`all() cannot be combined with other actions on line ${lineNumber}.`);
  }
  return commands;
}

function parseSingleCommand(commandText, lineNumber, knownVariables) {
  const match = commandText.match(/^([a-zA-Z][a-zA-Z0-9_]*)\s*\((.*)\)$/);
  if (!match) {
    throw new Error(`Invalid command syntax on line ${lineNumber}: ${commandText}`);
  }

  const actionKey = normalizeActionKey(match[1]);
  if (!actionKey) {
    throw new Error(`Unknown Lovense action on line ${lineNumber}: ${match[1]}`);
  }

  const args = splitTopLevel(match[2] || "", ",")
    .map((value) => value.trim())
    .filter(Boolean);

  if (actionKey === "stop") {
    if (args.length > 1) {
      throw new Error(`stop() accepts at most one delay value on line ${lineNumber}.`);
    }
    return {
      actionKey,
      valueExpression: null,
      delayExpression: args[0] ? parseNumericExpression(args[0], lineNumber, knownVariables) : null,
      lineNumber,
    };
  }

  if (args.length < 1 || args.length > 2) {
    throw new Error(`Action ${match[1]} requires a value and optional delay on line ${lineNumber}.`);
  }

  return {
    actionKey,
    valueExpression: parseNumericExpression(args[0], lineNumber, knownVariables),
    delayExpression: args[1] ? parseNumericExpression(args[1], lineNumber, knownVariables) : null,
    lineNumber,
  };
}

function normalizeActionKey(value) {
  const normalized = String(value || "").trim().toLowerCase();
  for (const [actionKey, definition] of Object.entries(LOVENSE_ACTIONS)) {
    if (definition.aliases.includes(normalized)) {
      return actionKey;
    }
  }
  return "";
}

function splitTopLevel(text, delimiter) {
  const parts = [];
  let depth = 0;
  let lastIndex = 0;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char === "(") {
      depth += 1;
      continue;
    }
    if (char === ")") {
      depth -= 1;
      continue;
    }
    if (depth === 0 && char === delimiter) {
      parts.push(text.slice(lastIndex, index));
      lastIndex = index + 1;
    }
  }

  parts.push(text.slice(lastIndex));
  return parts;
}

function tokenizeRuleExpression(expression, lineNumber) {
  const tokens = [];
  let index = 0;
  while (index < expression.length) {
    const char = expression[index];
    if (/\s/.test(char)) {
      index += 1;
      continue;
    }

    const twoChar = expression.slice(index, index + 2);
    if (["==", "!=", ">=", "<="].includes(twoChar)) {
      tokens.push({ type: "operator", value: twoChar });
      index += 2;
      continue;
    }

    if ("()+-*/:><".includes(char)) {
      tokens.push({
        type: char === "(" || char === ")" ? "paren" : "operator",
        value: char,
      });
      index += 1;
      continue;
    }

    const numberMatch = expression.slice(index).match(/^\d+(?:\.\d+)?/);
    if (numberMatch) {
      tokens.push({ type: "number", value: Number(numberMatch[0]) });
      index += numberMatch[0].length;
      continue;
    }

    const identifierMatch = expression.slice(index).match(/^[a-zA-Z_][a-zA-Z0-9_]*/);
    if (identifierMatch) {
      const value = identifierMatch[0];
      const normalized = value.toLowerCase();
      tokens.push({
        type: normalized === "and" || normalized === "or" ? "logical" : "identifier",
        value,
      });
      index += value.length;
      continue;
    }

    throw new Error(`Unexpected token on line ${lineNumber}: ${char}`);
  }

  return tokens;
}

function createTokenStream(tokens) {
  return {
    tokens,
    index: 0,
    peek() {
      return this.tokens[this.index] ?? null;
    },
    consume() {
      const token = this.peek();
      if (token) {
        this.index += 1;
      }
      return token;
    },
  };
}

function parseNumericExpression(expressionText, lineNumber, knownVariables) {
  const stream = createTokenStream(tokenizeRuleExpression(expressionText, lineNumber));
  const expression = parseAdditiveExpression(stream, lineNumber, knownVariables);
  if (stream.peek()) {
    throw new Error(`Unexpected token in numeric expression on line ${lineNumber}: ${stream.peek().value}`);
  }
  return expression;
}

function parseConditionExpression(expressionText, lineNumber, knownVariables) {
  const stream = createTokenStream(tokenizeRuleExpression(expressionText, lineNumber));
  const expression = parseLogicalOrExpression(stream, lineNumber, knownVariables);
  if (stream.peek()) {
    throw new Error(`Unexpected token in condition on line ${lineNumber}: ${stream.peek().value}`);
  }
  return expression;
}

function parseLogicalOrExpression(stream, lineNumber, knownVariables) {
  let left = parseLogicalAndExpression(stream, lineNumber, knownVariables);
  while (stream.peek()?.type === "logical" && stream.peek().value.toLowerCase() === "or") {
    stream.consume();
    left = {
      type: "logical",
      operator: "or",
      left,
      right: parseLogicalAndExpression(stream, lineNumber, knownVariables),
    };
  }
  return left;
}

function parseLogicalAndExpression(stream, lineNumber, knownVariables) {
  let left = parseComparisonExpression(stream, lineNumber, knownVariables);
  while (stream.peek()?.type === "logical" && stream.peek().value.toLowerCase() === "and") {
    stream.consume();
    left = {
      type: "logical",
      operator: "and",
      left,
      right: parseComparisonExpression(stream, lineNumber, knownVariables),
    };
  }
  return left;
}

function parseComparisonExpression(stream, lineNumber, knownVariables) {
  const left = parseAdditiveExpression(stream, lineNumber, knownVariables);
  const operator = stream.peek();
  if (!operator || operator.type !== "operator" || !["==", "!=", ">=", "<=", ">", "<"].includes(operator.value)) {
    throw new Error(`Invalid condition on line ${lineNumber}.`);
  }
  stream.consume();
  return {
    type: "comparison",
    operator: operator.value,
    left,
    right: parseAdditiveExpression(stream, lineNumber, knownVariables),
  };
}

function parseAdditiveExpression(stream, lineNumber, knownVariables) {
  let left = parseMultiplicativeExpression(stream, lineNumber, knownVariables);
  while (stream.peek()?.type === "operator" && ["+", "-"].includes(stream.peek().value)) {
    const operator = stream.consume().value;
    left = {
      type: "binary",
      operator,
      left,
      right: parseMultiplicativeExpression(stream, lineNumber, knownVariables),
    };
  }
  return left;
}

function parseMultiplicativeExpression(stream, lineNumber, knownVariables) {
  let left = parseUnaryExpression(stream, lineNumber, knownVariables);
  while (stream.peek()?.type === "operator" && ["*", "/", ":"].includes(stream.peek().value)) {
    const operator = stream.consume().value;
    left = {
      type: "binary",
      operator,
      left,
      right: parseUnaryExpression(stream, lineNumber, knownVariables),
    };
  }
  return left;
}

function parseUnaryExpression(stream, lineNumber, knownVariables) {
  if (stream.peek()?.type === "operator" && ["+", "-"].includes(stream.peek().value)) {
    return {
      type: "unary",
      operator: stream.consume().value,
      operand: parseUnaryExpression(stream, lineNumber, knownVariables),
    };
  }
  return parsePrimaryExpression(stream, lineNumber, knownVariables);
}

function parsePrimaryExpression(stream, lineNumber, knownVariables) {
  const token = stream.consume();
  if (!token) {
    throw new Error(`Unexpected end of expression on line ${lineNumber}.`);
  }

  if (token.type === "number") {
    return { type: "number", value: token.value };
  }

  if (token.type === "identifier") {
    if (!knownVariables.has(token.value)) {
      throw new Error(`Unknown variable ${token.value} on line ${lineNumber}.`);
    }
    return { type: "identifier", name: token.value };
  }

  if (token.type === "paren" && token.value === "(") {
    const expression = parseAdditiveExpression(stream, lineNumber, knownVariables);
    const closing = stream.consume();
    if (!closing || closing.type !== "paren" || closing.value !== ")") {
      throw new Error(`Missing closing parenthesis on line ${lineNumber}.`);
    }
    return expression;
  }

  throw new Error(`Unexpected token in expression on line ${lineNumber}: ${token.value}`);
}

function buildRuleScope(assignments, context) {
  const scope = { ...context };
  assignments.forEach((assignment) => {
    scope[assignment.name] = evaluateNumericExpression(assignment.expression, scope);
  });
  return scope;
}

function evaluateNumericExpression(expression, scope) {
  switch (expression.type) {
    case "number":
      return expression.value;
    case "identifier": {
      const value = Number(scope[expression.name]);
      if (!Number.isFinite(value)) {
        throw new Error(`Variable ${expression.name} did not resolve to a number.`);
      }
      return value;
    }
    case "unary": {
      const value = evaluateNumericExpression(expression.operand, scope);
      return expression.operator === "-" ? -value : value;
    }
    case "binary": {
      const left = evaluateNumericExpression(expression.left, scope);
      const right = evaluateNumericExpression(expression.right, scope);
      switch (expression.operator) {
        case "+":
          return left + right;
        case "-":
          return left - right;
        case "*":
          return left * right;
        case "/":
        case ":":
          if (right === 0) {
            throw new Error("Division by zero is not allowed in Lovense rules.");
          }
          return left / right;
        default:
          throw new Error(`Unsupported numeric operator: ${expression.operator}`);
      }
    }
    default:
      throw new Error(`Unsupported numeric expression node: ${expression.type}`);
  }
}

function evaluateBooleanExpression(expression, scope) {
  switch (expression.type) {
    case "logical":
      if (expression.operator === "and") {
        return evaluateBooleanExpression(expression.left, scope) && evaluateBooleanExpression(expression.right, scope);
      }
      return evaluateBooleanExpression(expression.left, scope) || evaluateBooleanExpression(expression.right, scope);
    case "comparison": {
      const left = evaluateNumericExpression(expression.left, scope);
      const right = evaluateNumericExpression(expression.right, scope);
      switch (expression.operator) {
        case "==":
          return left === right;
        case "!=":
          return left !== right;
        case ">=":
          return left >= right;
        case "<=":
          return left <= right;
        case ">":
          return left > right;
        case "<":
          return left < right;
        default:
          throw new Error(`Unsupported comparison operator: ${expression.operator}`);
      }
    }
    default:
      throw new Error(`Unsupported boolean expression node: ${expression.type}`);
  }
}

function normalizeRuleNumericValue(value, min, max, lineNumber, label) {
  if (!Number.isFinite(value)) {
    throw new Error(`Line ${lineNumber}: ${label} did not resolve to a valid number.`);
  }

  const rounded = Math.round(value);
  if (rounded < min || rounded > max) {
    throw new Error(`Line ${lineNumber}: ${label} must resolve to a value between ${min} and ${max}.`);
  }
  return rounded;
}

function normalizeRuleDelayMs(value, lineNumber) {
  if (!Number.isFinite(value)) {
    throw new Error(`Line ${lineNumber}: delay must resolve to a valid number.`);
  }

  const rounded = Math.round(value);
  if (rounded < 0) {
    throw new Error(`Line ${lineNumber}: delay must be 0 or greater.`);
  }
  return rounded;
}

function formatExecutionMode(mode) {
  return mode === "lovense-rules" ? "Lovense rules" : "Shell command";
}

function getEntryModeSummary(entry) {
  if (entry.executionMode === "lovense-rules") {
    const deviceName = entry.lovense?.toyName || entry.lovense?.toyType || entry.lovense?.toyId || "no device";
    return `${deviceName} | ${entry.lovense?.host}:${entry.lovense?.port}`;
  }

  return `${entry.shell} | timeout ${entry.timeoutSeconds.toFixed(2)} s`;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function downloadTextFile(content, fileName, mimeType) {
  const blob = new Blob([content], { type: `${mimeType};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = fileName;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return "";
}

function firstFiniteNumber(...values) {
  for (const value of values) {
    const candidate = Number(value);
    if (Number.isFinite(candidate)) {
      return candidate;
    }
  }
  return null;
}

function clampOptionalNumber(value) {
  return value === null ? null : clampTimeoutSeconds(value);
}

function normalizeCommandTemplate(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed || DEFAULT_COMMAND_TEMPLATE;
}

function clampTimeoutSeconds(value) {
  if (!Number.isFinite(value)) {
    return DEFAULT_TIMEOUT_SECONDS;
  }
  return Math.min(60, Math.max(0.01, value));
}

function normalizeStem(fileName) {
  return stripExtension(fileName).toLowerCase().replace(/[\s._-]+/g, " ").trim();
}

function stripExtension(fileName) {
  return fileName.replace(/\.[^/.]+$/, "");
}

function getCurrentEntry() {
  return state.playlist.find((entry) => entry.id === state.currentEntryId) ?? null;
}

function loadEntry(entryId, options = {}) {
  const entry = state.playlist.find((item) => item.id === entryId);
  if (!entry) {
    return;
  }

  stopSchedulerLoop();
  clearScheduledLovenseActions();
  sendLovenseStopForCurrentEntry(null, { force: true });
  state.currentEntryId = entry.id;
  state.nextActionIndex = 0;
  state.lastTriggeredIndex = null;
  highlightActionRow(null);
  ui.video.src = entry.videoUrl;
  ui.video.load();
  ui.executionMode.value = entry.executionMode || DEFAULT_EXECUTION_MODE;
  ui.shell.value = entry.shell;
  ui.timeoutSeconds.value = entry.timeoutSeconds.toFixed(2);
  ui.commandTemplate.value = entry.commandTemplate;
  ui.lovenseRules.value = entry.rulesText || DEFAULT_RULES_TEXT;
  applyLovenseConfigToForm(entry.lovense || DEFAULT_LOVENSE_CONFIG);
  renderLovenseToySelect(entry.lovense?.toyId || "", state.detectedToys, entry.lovense);
  updateLovenseSelectionDetails(findToyById(ui.lovenseToySelect.value) ?? entry.lovense ?? null);
  renderExecutionModeForm();
  renderLovenseRuleStatus();
  renderPlaylist();
  renderActionTable();
  renderStatus();

  if (options.autoplay) {
    ui.video.play().catch((error) => {
      appendLog({ ok: false, title: "Autoplay blocked", detail: String(error) });
    });
  }
}

function clearCurrentEntry() {
  stopSchedulerLoop();
  clearScheduledLovenseActions();
  sendLovenseStopForCurrentEntry(null, { force: true });
  ui.video.pause();
  ui.video.removeAttribute("src");
  ui.video.load();
  state.currentEntryId = null;
  state.nextActionIndex = 0;
  state.lastTriggeredIndex = null;
  highlightActionRow(null);
  updateLovenseSelectionDetails(null);
  renderLovenseRuleStatus();
  renderActionTable();
  renderPlaylist();
  renderStatus();
}

function revokeEntryResources(entry) {
  URL.revokeObjectURL(entry.videoUrl);
}

function getNextEntryId() {
  if (!state.playlist.length || !state.currentEntryId) {
    return null;
  }

  const currentIndex = state.playlist.findIndex((entry) => entry.id === state.currentEntryId);
  if (currentIndex === -1) {
    return null;
  }

  if (state.playbackMode === "random") {
    if (state.playlist.length < 2) {
      return null;
    }
    const candidates = state.playlist.filter((entry) => entry.id !== state.currentEntryId);
    return candidates[Math.floor(Math.random() * candidates.length)]?.id ?? null;
  }

  return currentIndex < state.playlist.length - 1 ? state.playlist[currentIndex + 1].id : null;
}

function handleVideoEnded() {
  stopSchedulerLoop();
  clearScheduledLovenseActions();
  sendLovenseStopForCurrentEntry(null, { force: true });
  const nextEntryId = getNextEntryId();
  if (!nextEntryId) {
    appendLog({ ok: true, title: "Playback finished", detail: "No further playlist entry available." });
    renderStatus();
    return;
  }
  loadEntry(nextEntryId, { autoplay: true });
}

function formatPlaybackMode(mode) {
  return mode === "random" ? "Random" : "Sequential";
}

function findNextActionIndex(actions, currentMs) {
  const nextIndex = actions.findIndex((action) => action.atMs > currentMs);
  return nextIndex === -1 ? actions.length : nextIndex;
}

function formatMs(ms) {
  if (!Number.isFinite(ms)) {
    return "-";
  }
  const safeMs = Math.max(0, Math.round(ms));
  const minutes = Math.floor(safeMs / 60000);
  const seconds = Math.floor((safeMs % 60000) / 1000);
  const milliseconds = safeMs % 1000;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}.${String(milliseconds).padStart(3, "0")}`;
}

function escapeHtml(value) {
  return String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

init();
