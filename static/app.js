const state = {
  actions: [],
  nextActionIndex: 0,
  lastTriggeredIndex: null,
  armed: false,
  rafId: null,
  logCount: 0,
};

const ui = {
  backendStatus: document.getElementById("backend-status"),
  actionCount: document.getElementById("action-count"),
  armedStatus: document.getElementById("armed-status"),
  currentTime: document.getElementById("current-time"),
  nextAction: document.getElementById("next-action"),
  lastAction: document.getElementById("last-action"),
  video: document.getElementById("video"),
  videoFile: document.getElementById("video-file"),
  funscriptFile: document.getElementById("funscript-file"),
  shell: document.getElementById("shell"),
  timeoutSeconds: document.getElementById("timeout-seconds"),
  dryRun: document.getElementById("dry-run"),
  commandTemplate: document.getElementById("command-template"),
  armButton: document.getElementById("arm-button"),
  resetButton: document.getElementById("reset-button"),
  clearLogButton: document.getElementById("clear-log-button"),
  scriptSummary: document.getElementById("script-summary"),
  actionTable: document.getElementById("action-table"),
  log: document.getElementById("log"),
  logSummary: document.getElementById("log-summary"),
};

async function init() {
  bindEvents();
  await checkBackend();
  renderActionTable();
  renderStatus();
}

function bindEvents() {
  ui.videoFile.addEventListener("change", handleVideoFile);
  ui.funscriptFile.addEventListener("change", handleFunscriptFile);
  ui.armButton.addEventListener("click", toggleArmedState);
  ui.resetButton.addEventListener("click", resetScheduler);
  ui.clearLogButton.addEventListener("click", clearLog);

  ui.video.addEventListener("play", startSchedulerLoop);
  ui.video.addEventListener("pause", stopSchedulerLoop);
  ui.video.addEventListener("ended", stopSchedulerLoop);
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
    appendLog({
      ok: false,
      title: "Backend unavailable",
      detail: String(error),
    });
  }
}

function handleVideoFile(event) {
  const file = event.target.files?.[0];
  if (!file) {
    return;
  }

  const url = URL.createObjectURL(file);
  ui.video.src = url;
  ui.video.load();
  appendLog({
    ok: true,
    title: "Video loaded",
    detail: `${file.name}`,
  });
}

async function handleFunscriptFile(event) {
  const file = event.target.files?.[0];
  if (!file) {
    return;
  }

  try {
    const text = await file.text();
    const parsed = JSON.parse(text);
    const actions = Array.isArray(parsed.actions) ? parsed.actions : [];

    state.actions = actions
      .map((action, index) => ({
        index,
        atMs: Number(action.at),
        pos: Number(action.pos),
      }))
      .filter((action) => Number.isFinite(action.atMs) && Number.isFinite(action.pos))
      .sort((left, right) => left.atMs - right.atMs)
      .map((action, index, all) => ({
        ...action,
        index,
        previousAtMs: index > 0 ? all[index - 1].atMs : null,
        nextAtMs: index < all.length - 1 ? all[index + 1].atMs : null,
      }));

    resetScheduler();
    renderActionTable();
    renderStatus();

    const inverted = parsed.inverted ? "inverted" : "normal";
    ui.scriptSummary.textContent = `${file.name} | ${state.actions.length} Actions | range ${parsed.range ?? "-"} | ${inverted}`;
    appendLog({
      ok: true,
      title: "Funscript loaded",
      detail: `${file.name} with ${state.actions.length} actions`,
    });
  } catch (error) {
    appendLog({
      ok: false,
      title: "Could not read funscript",
      detail: String(error),
    });
  }
}

function toggleArmedState() {
  state.armed = !state.armed;
  renderStatus();
  appendLog({
    ok: true,
    title: state.armed ? "Execution enabled" : "Execution disabled",
    detail: state.armed
      ? "Actions will be executed during playback."
      : "Actions will not be sent to the backend.",
  });
}

function resetScheduler() {
  syncSchedulerFromCurrentTime();
  renderStatus();
}

function clearLog() {
  ui.log.innerHTML = "";
  state.logCount = 0;
  ui.logSummary.textContent = "Log cleared.";
}

function resyncSchedulerToCurrentTime() {
  syncSchedulerFromCurrentTime();
  renderStatus();
}

function startSchedulerLoop() {
  if (state.rafId !== null) {
    cancelAnimationFrame(state.rafId);
  }

  const loop = async () => {
    await processPlaybackPosition();
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

async function processPlaybackPosition() {
  const currentMs = ui.video.currentTime * 1000;
  ui.currentTime.textContent = formatMs(currentMs);

  while (state.nextActionIndex < state.actions.length && state.actions[state.nextActionIndex].atMs <= currentMs) {
    const action = state.actions[state.nextActionIndex];
    state.nextActionIndex += 1;
    state.lastTriggeredIndex = action.index;
    highlightActionRow(action.index);
    renderStatus();

    if (state.armed) {
      await triggerAction(action, currentMs);
    }
  }

  renderStatus();
}

function findNextActionIndex(currentMs) {
  const nextIndex = state.actions.findIndex((action) => action.atMs > currentMs);
  return nextIndex === -1 ? state.actions.length : nextIndex;
}

function syncSchedulerFromCurrentTime() {
  const currentMs = ui.video.currentTime * 1000;
  state.nextActionIndex = findNextActionIndex(currentMs);
  state.lastTriggeredIndex = state.nextActionIndex > 0 ? state.nextActionIndex - 1 : null;
  highlightActionRow(state.lastTriggeredIndex);
}

async function triggerAction(action, currentMs) {
  const deltaMs = currentMs - action.atMs;
  const payload = {
    index: action.index,
    atMs: action.atMs,
    pos: action.pos,
    currentMs: Math.round(currentMs),
    deltaMs: Math.round(deltaMs),
    previousAtMs: action.previousAtMs ?? "",
    nextAtMs: action.nextAtMs ?? "",
  };

  const command = applyTemplate(ui.commandTemplate.value, payload);

  try {
    const response = await fetch("/api/execute", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        command,
        shell: ui.shell.value,
        timeoutSeconds: Number(ui.timeoutSeconds.value || 5),
        dryRun: ui.dryRun.checked,
        event: payload,
      }),
    });

    const data = await response.json();
    appendLog({
      ok: response.ok && data.ok,
      title: `Action ${action.index} at ${formatMs(action.atMs)}`,
      detail: buildExecutionDetail(command, data),
    });
  } catch (error) {
    appendLog({
      ok: false,
      title: `Action ${action.index} failed`,
      detail: String(error),
    });
  }
}

function applyTemplate(template, values) {
  return template.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_, key) => {
    if (!(key in values)) {
      return "";
    }

    return String(values[key]);
  });
}

function buildExecutionDetail(command, response) {
  const lines = [
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
  ui.actionCount.textContent = String(state.actions.length);
  ui.actionTable.innerHTML = state.actions
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
  ui.actionTable.querySelectorAll("tr").forEach((row) => {
    row.classList.toggle("active-row", Number(row.dataset.actionIndex) === index);
  });
}

function renderStatus() {
  const nextAction = state.actions[state.nextActionIndex] ?? null;
  const lastAction = state.lastTriggeredIndex !== null ? state.actions[state.lastTriggeredIndex] : null;

  ui.actionCount.textContent = String(state.actions.length);
  ui.armedStatus.textContent = state.armed ? "Enabled" : "Disabled";
  ui.armButton.textContent = state.armed ? "Disable execution" : "Enable execution";
  ui.currentTime.textContent = formatMs(ui.video.currentTime * 1000);
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
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

init();
