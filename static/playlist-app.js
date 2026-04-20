const DEFAULT_EXECUTION_MODE = "lovense-live";
const DEFAULT_RULES_TEXT = "if pos >= 15 then vibrate(10)\nelse stop()";
const DEFAULT_LOVENSE_CONNECTION = {
  id: "user-1",
  label: "User 1",
  scheme: "https",
  host: "127.0.0.1",
  port: "30010",
  platformName: "FHPlayer",
  selectedToys: [],
};
const DEFAULT_LOVENSE_CONFIG = {
  selectedConnectionId: DEFAULT_LOVENSE_CONNECTION.id,
  connections: [{ ...DEFAULT_LOVENSE_CONNECTION }],
  testSelectedToys: [
    {
      id: "sim-nora",
      name: "Nora Simulator",
      nickName: "Nora Simulator",
      type: "Nora",
      fullFunctionNames: ["Vibrate", "Rotate"],
    },
  ],
};
const ACCEPTED_FUNSCRIPT_EXTENSIONS = new Set(["funscript", "json"]);
const ACCEPTED_FUNSCRIPT_MIME_TYPES = new Set(["application/json", "text/json"]);
const LOVENSE_ACTIONS = {
  all: {
    apiName: "All",
    capabilityNames: ["All"],
    aliases: ["all"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `All:${strength}`,
  },
  vibrate: {
    apiName: "Vibrate",
    capabilityNames: ["Vibrate"],
    aliases: ["vibrate", "vibration"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `Vibrate:${strength}`,
  },
  vibrate2: {
    apiName: "Vibrate2",
    capabilityNames: ["Vibrate2"],
    aliases: ["vibrate2", "vibration2", "secondaryvibrate"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `Vibrate2:${strength}`,
  },
  rotate: {
    apiName: "Rotate",
    capabilityNames: ["Rotate"],
    aliases: ["rotate", "rotation"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `Rotate:${strength}`,
  },
  rotatechange: {
    apiName: "RotateChange",
    capabilityNames: ["Rotate"],
    aliases: ["rotatechange", "rotate_change", "directionchange"],
    parameterRanges: [],
    allowDuration: false,
    buildAction: () => "RotateChange",
  },
  pump: {
    apiName: "Pump",
    capabilityNames: ["Pump", "Air"],
    aliases: ["pump"],
    parameterRanges: [{ label: "level", min: 0, max: 3 }],
    allowDuration: true,
    buildAction: ([level]) => `Pump:${level}`,
  },
  airlevel: {
    apiName: "Air:Level",
    capabilityNames: ["Air", "Pump"],
    aliases: ["airlevel", "air_level", "airpressure", "air"],
    parameterRanges: [{ label: "level", min: 0, max: 5 }],
    allowDuration: true,
    buildAction: ([level]) => `Air:Level:${level}`,
  },
  airin: {
    apiName: "Air:In",
    capabilityNames: ["Air", "Pump"],
    aliases: ["airin", "air_in", "inflate"],
    parameterRanges: [],
    allowDuration: false,
    buildAction: () => "Air:In:1",
  },
  airout: {
    apiName: "Air:Out",
    capabilityNames: ["Air", "Pump"],
    aliases: ["airout", "air_out", "deflate"],
    parameterRanges: [],
    allowDuration: false,
    buildAction: () => "Air:Out:1",
  },
  thrusting: {
    apiName: "Thrusting",
    capabilityNames: ["Thrusting"],
    aliases: ["thrusting", "thrust"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `Thrusting:${strength}`,
  },
  fingering: {
    apiName: "Fingering",
    capabilityNames: ["Fingering"],
    aliases: ["fingering", "finger"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `Fingering:${strength}`,
  },
  suction: {
    apiName: "Suction",
    capabilityNames: ["Suction"],
    aliases: ["suction"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `Suction:${strength}`,
  },
  setlevel: {
    apiName: "SetLevel",
    capabilityNames: ["SetLevel"],
    aliases: ["setlevel", "set_level"],
    parameterRanges: [
      { label: "button", min: 1, max: 3 },
      { label: "level", min: 0, max: 20 },
    ],
    allowDuration: true,
    buildAction: ([button, level]) => `SetLevel:${button}:${level}`,
  },
  depth: {
    apiName: "Depth",
    capabilityNames: ["Depth"],
    aliases: ["depth"],
    parameterRanges: [{ label: "level", min: 0, max: 3 }],
    allowDuration: true,
    buildAction: ([level]) => `Depth:${level}`,
  },
  stroke: {
    apiName: "Stroke",
    capabilityNames: ["Stroke"],
    aliases: ["stroke"],
    parameterRanges: [{ label: "value", min: 0, max: 100 }],
    allowDuration: true,
    buildAction: ([value]) => `Stroke:${value}`,
  },
  oscillate: {
    apiName: "Oscillate",
    capabilityNames: ["Oscillate"],
    aliases: ["oscillate", "oscillation"],
    parameterRanges: [{ label: "strength", min: 0, max: 20 }],
    allowDuration: true,
    buildAction: ([strength]) => `Oscillate:${strength}`,
  },
  stop: {
    apiName: "Stop",
    capabilityNames: ["Stop"],
    aliases: ["stop"],
    parameterRanges: [],
    allowDuration: false,
    buildAction: () => "Stop",
  },
};
const LOVENSE_SHORT_CAPABILITY_MAP = {
  v: "Vibrate",
  v2: "Vibrate2",
  r: "Rotate",
  a: "Air",
  p: "Pump",
  sl: "SetLevel",
  t: "Thrusting",
  f: "Fingering",
  s: "Suction",
  d: "Depth",
  o: "Oscillate",
};
const LOVENSE_TYPE_CAPABILITY_HINTS = [
  { match: /solace\s*pro/i, capabilities: ["Vibrate", "Thrusting", "Suction", "Stroke"] },
  { match: /solace/i, capabilities: ["Vibrate", "Thrusting", "Suction"] },
  { match: /\bmax(?:\s*2)?\b/i, capabilities: ["Air"] },
  { match: /\bnora\b/i, capabilities: ["Vibrate", "Rotate"] },
  { match: /\b(?:edge(?:\s*2)?|lapis)\b/i, capabilities: ["Vibrate2"] },
  { match: /\bmission\s*2\b/i, capabilities: ["Vibrate"] },
  { match: /\blush\b/i, capabilities: ["Vibrate"] },
  { match: /\bhush\b/i, capabilities: ["Vibrate"] },
  { match: /\bferri\b/i, capabilities: ["Vibrate"] },
  { match: /\bdomi\b/i, capabilities: ["SetLevel"] },
  { match: /\bambi\b/i, capabilities: ["Vibrate"] },
  { match: /\btenera\b/i, capabilities: ["Suction"] },
  { match: /\bflexer\b/i, capabilities: ["Fingering"] },
  { match: /\b(?:gravity|sex\s*machine)\b/i, capabilities: ["Thrusting"] },
  { match: /\bosci\b/i, capabilities: ["Oscillate"] },
];
const BASE_RULE_VARIABLES = ["pos", "index", "atMs", "currentMs", "deltaMs"];
const RULE_VARIABLES = new Set(BASE_RULE_VARIABLES);
const SIMULATED_TOYS = [
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
  {
    id: "sim-edge2",
    name: "Edge 2 Simulator",
    nickName: "Edge 2 Simulator",
    type: "Edge 2",
    fullFunctionNames: ["Vibrate", "Oscillate"],
  },
  {
    id: "sim-solace",
    name: "Solace Simulator",
    nickName: "Solace Simulator",
    type: "Solace",
    fullFunctionNames: ["Vibrate", "Thrusting", "Suction"],
  },
];

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
  currentVersion: "",
  backendCapabilities: {
    lovense: true,
    platform: "desktop",
    updates: false,
    diagnostics: false,
  },
  updateSupport: {
    configured: false,
    sourceUrl: "",
  },
  appSettings: {
    updates: {
      autoCheckEnabled: false,
      lastResult: null,
    },
    ui: {
      showDiagnostics: true,
      showFunscriptOverview: true,
      showExecutionLog: true,
    },
  },
  diagnostics: {
    available: false,
    platform: "desktop",
    version: "",
    paths: {
      appData: "",
      libraryRoot: "",
      settingsFile: "",
      logDirectory: "",
      logFile: "",
    },
    capabilities: {
      openLogFolder: false,
    },
    recentLog: "",
  },
  library: {
    available: false,
    platform: "desktop",
    rootPath: "",
    directories: {
      videos: "",
      funscripts: "",
      exports: "",
    },
    capabilities: {
      import: false,
      reveal: false,
    },
  },
  detectedToysByConnection: {},
  formLovense: normalizeLovenseConfig(DEFAULT_LOVENSE_CONFIG),
  scheduledLovenseTimers: new Set(),
  lovenseAutoStopTimers: new Map(),
};

const ui = {
  backendStatus: document.getElementById("backend-status"),
  playlistCount: document.getElementById("playlist-count"),
  playlistModeStatus: document.getElementById("playlist-mode-status"),
  armedStatus: document.getElementById("armed-status"),
  pendingCount: document.getElementById("pending-count"),
  libraryStatus: document.getElementById("library-status"),
  libraryPaths: document.getElementById("library-paths"),
  showDiagnosticsToggle: document.getElementById("show-diagnostics-toggle"),
  showFunscriptOverviewToggle: document.getElementById("show-funscript-overview-toggle"),
  showExecutionLogToggle: document.getElementById("show-execution-log-toggle"),
  updateVersionLabel: document.getElementById("update-version-label"),
  updateAutoCheck: document.getElementById("update-auto-check"),
  checkUpdatesButton: document.getElementById("check-updates-button"),
  updateReleaseLink: document.getElementById("update-release-link"),
  updateStatus: document.getElementById("update-status"),
  diagnosticsPanel: document.getElementById("diagnostics-panel"),
  diagnosticsStatus: document.getElementById("diagnostics-status"),
  diagnosticsPaths: document.getElementById("diagnostics-paths"),
  diagnosticsLog: document.getElementById("diagnostics-log"),
  currentEntryTitle: document.getElementById("current-entry-title"),
  currentEntryMeta: document.getElementById("current-entry-meta"),
  currentTime: document.getElementById("current-time"),
  nextAction: document.getElementById("next-action"),
  lastAction: document.getElementById("last-action"),
  video: document.getElementById("video"),
  videoFiles: document.getElementById("video-files"),
  funscriptFiles: document.getElementById("funscript-files"),
  executionMode: document.getElementById("execution-mode"),
  dryRun: document.getElementById("dry-run"),
  playlistMode: document.getElementById("playlist-mode"),
  lovenseConfig: document.getElementById("lovense-config"),
  lovenseLiveConfig: document.getElementById("lovense-live-config"),
  lovenseConnectionSelect: document.getElementById("lovense-connection-select"),
  lovenseConnectionName: document.getElementById("lovense-connection-name"),
  lovenseScheme: document.getElementById("lovense-scheme"),
  lovenseHost: document.getElementById("lovense-host"),
  lovensePort: document.getElementById("lovense-port"),
  lovensePlatformName: document.getElementById("lovense-platform-name"),
  lovenseStatus: document.getElementById("lovense-status"),
  lovenseDeviceLabel: document.getElementById("lovense-device-label"),
  lovenseToySelect: document.getElementById("lovense-toy-select"),
  lovenseCapabilities: document.getElementById("lovense-capabilities"),
  lovenseDeviceType: document.getElementById("lovense-device-type"),
  lovenseParallelActions: document.getElementById("lovense-parallel-actions"),
  lovenseRules: document.getElementById("lovense-rules"),
  lovenseRuleStatus: document.getElementById("lovense-rule-status"),
  lovenseActionRanges: document.getElementById("lovense-action-ranges"),
  addPlaylistButton: document.getElementById("add-playlist-button"),
  updateEntryButton: document.getElementById("update-entry-button"),
  saveFunscriptButton: document.getElementById("save-funscript-button"),
  detectLovenseButton: document.getElementById("detect-lovense-button"),
  stopLovenseButton: document.getElementById("stop-lovense-button"),
  addLovenseConnectionButton: document.getElementById("add-lovense-connection-button"),
  removeLovenseConnectionButton: document.getElementById("remove-lovense-connection-button"),
  importLibraryButton: document.getElementById("import-library-button"),
  openVideoLibraryButton: document.getElementById("open-video-library-button"),
  openFunscriptLibraryButton: document.getElementById("open-funscript-library-button"),
  openExportsLibraryButton: document.getElementById("open-exports-library-button"),
  refreshDiagnosticsButton: document.getElementById("refresh-diagnostics-button"),
  openDiagnosticsButton: document.getElementById("open-diagnostics-button"),
  playSelectedButton: document.getElementById("play-selected-button"),
  nextButton: document.getElementById("next-button"),
  removeEntryButton: document.getElementById("remove-entry-button"),
  clearPlaylistButton: document.getElementById("clear-playlist-button"),
  armButton: document.getElementById("arm-button"),
  resetButton: document.getElementById("reset-button"),
  clearLogButton: document.getElementById("clear-log-button"),
  playlistList: document.getElementById("playlist-list"),
  playlistSummary: document.getElementById("playlist-summary"),
  scriptCard: document.getElementById("script-card"),
  scriptSummary: document.getElementById("script-summary"),
  actionTable: document.getElementById("action-table"),
  logCard: document.getElementById("log-card"),
  log: document.getElementById("log"),
  logSummary: document.getElementById("log-summary"),
};

async function init() {
  bindEvents();
  ui.executionMode.value = DEFAULT_EXECUTION_MODE;
  ui.lovenseRules.value = DEFAULT_RULES_TEXT;
  applyLovenseConfigToForm(DEFAULT_LOVENSE_CONFIG, { resetDetectedToys: true });
  await checkBackend();
  await loadAppSettings();
  await refreshLibraryInfo();
  await loadDiagnosticsInfo();
  renderUpdateSettings();
  renderSectionVisibilitySettings();
  if (state.backendCapabilities.updates && state.appSettings.updates.autoCheckEnabled) {
    await checkForUpdates({ automatic: true });
  }
  renderExecutionModeForm();
  renderLovenseToySelect(getCurrentSelectedToyIds(), getCurrentAvailableToys());
  renderLovenseActionRanges(resolveLovenseRuleConfig(null, { allowOfflineTest: true, requireToyId: false }), {
    mode: ui.executionMode.value === "lovense-test" ? "test" : "live",
  });
  renderLovenseRuleStatus();
  renderPlaylist();
  renderActionTable();
  renderStatus();
}

function bindEvents() {
  ui.addPlaylistButton.addEventListener("click", handleAddToPlaylist);
  ui.updateEntryButton.addEventListener("click", updateSelectedEntrySettings);
  ui.saveFunscriptButton.addEventListener("click", saveSelectedEntryToFunscript);
  ui.funscriptFiles.addEventListener("change", handleFunscriptSelectionPreview);
  ui.executionMode.addEventListener("change", () => {
    renderExecutionModeForm();
    renderLovenseToySelect(getCurrentSelectedToyIds(), getCurrentAvailableToys(), getCurrentToyFallbacks());
    updateLovenseSelectionDetails(getSelectedToysForCurrentMode(getCurrentEntry()?.lovense));
    renderLovenseRuleStatus();
  });
  ui.detectLovenseButton.addEventListener("click", detectLovenseDevices);
  ui.stopLovenseButton.addEventListener("click", () =>
    sendLovenseStopForCurrentEntry("Manual stop command sent.", { force: true }),
  );
  ui.addLovenseConnectionButton.addEventListener("click", addLovenseConnectionProfile);
  ui.removeLovenseConnectionButton.addEventListener("click", removeLovenseConnectionProfile);
  ui.importLibraryButton.addEventListener("click", handleImportSelectedFilesToLibrary);
  ui.openVideoLibraryButton.addEventListener("click", () => openLibraryDirectory("videos"));
  ui.openFunscriptLibraryButton.addEventListener("click", () => openLibraryDirectory("funscripts"));
  ui.openExportsLibraryButton.addEventListener("click", () => openLibraryDirectory("exports"));
  ui.refreshDiagnosticsButton.addEventListener("click", loadDiagnosticsInfo);
  ui.openDiagnosticsButton.addEventListener("click", openDiagnosticsFolder);
  ui.lovenseConnectionSelect.addEventListener("change", handleLovenseConnectionSelectionChange);
  ui.lovenseConnectionName.addEventListener("input", handleLovenseConnectionFieldInput);
  ui.lovenseScheme.addEventListener("change", handleLovenseConnectionFieldInput);
  ui.lovenseHost.addEventListener("input", handleLovenseConnectionFieldInput);
  ui.lovensePort.addEventListener("input", handleLovenseConnectionFieldInput);
  ui.lovensePlatformName.addEventListener("input", handleLovenseConnectionFieldInput);
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
  ui.updateAutoCheck.addEventListener("change", handleUpdateAutoCheckChange);
  ui.showDiagnosticsToggle.addEventListener("change", handleSectionVisibilityChange);
  ui.showFunscriptOverviewToggle.addEventListener("change", handleSectionVisibilityChange);
  ui.showExecutionLogToggle.addEventListener("change", handleSectionVisibilityChange);
  ui.checkUpdatesButton.addEventListener("click", () => checkForUpdates({ automatic: false }));

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

    const data = await response.json();
    state.backendCapabilities = {
      lovense: data.capabilities?.lovense !== false,
      platform: data.platform || "desktop",
      updates: data.capabilities?.updates === true,
      diagnostics: data.capabilities?.diagnostics === true,
    };
    state.currentVersion = String(data.version || "");
    ui.backendStatus.textContent = state.backendCapabilities.platform === "android" ? "Connected (Android)" : "Connected";
  } catch (error) {
    ui.backendStatus.textContent = "Unavailable";
    appendLog({ ok: false, title: "Backend unavailable", detail: String(error) });
  }
}

async function loadAppSettings() {
  try {
    const response = await fetch("/api/settings", { cache: "no-store" });
    const data = await parseJsonResponse(response);
    if (!response.ok || !data.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }

    state.currentVersion = String(data.currentVersion || state.currentVersion || "");
    state.updateSupport = {
      configured: data.updateSupport?.configured === true,
      sourceUrl: String(data.updateSupport?.sourceUrl || ""),
    };
    state.appSettings = normalizeAppSettings(data.settings);
  } catch (error) {
    state.updateSupport = {
      configured: false,
      sourceUrl: "",
    };
    state.appSettings = normalizeAppSettings({});
    renderUpdateStatus({
      status: "error",
      message: `Could not load app settings: ${String(error)}`,
    });
  } finally {
    renderUpdateSettings();
    renderSectionVisibilitySettings();
  }
}

function normalizeAppSettings(settings) {
  return {
    updates: {
      autoCheckEnabled: settings?.updates?.autoCheckEnabled === true,
      lastResult: normalizeUpdateResult(settings?.updates?.lastResult),
    },
    ui: {
      showDiagnostics: settings?.ui?.showDiagnostics !== false,
      showFunscriptOverview: settings?.ui?.showFunscriptOverview !== false,
      showExecutionLog: settings?.ui?.showExecutionLog !== false,
    },
  };
}

function buildAppSettingsPayload() {
  return {
    updates: {
      autoCheckEnabled: state.appSettings.updates.autoCheckEnabled,
    },
    ui: {
      showDiagnostics: state.appSettings.ui.showDiagnostics,
      showFunscriptOverview: state.appSettings.ui.showFunscriptOverview,
      showExecutionLog: state.appSettings.ui.showExecutionLog,
    },
  };
}

async function persistAppSettings() {
  const response = await fetch("/api/settings", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(buildAppSettingsPayload()),
  });
  const data = await parseJsonResponse(response);
  if (!response.ok || !data.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }

  state.currentVersion = String(data.currentVersion || state.currentVersion || "");
  state.updateSupport = {
    configured: data.updateSupport?.configured === true,
    sourceUrl: String(data.updateSupport?.sourceUrl || state.updateSupport.sourceUrl || ""),
  };
  state.appSettings = normalizeAppSettings(data.settings);
  return data;
}

function normalizeUpdateResult(result) {
  if (!result || typeof result !== "object") {
    return null;
  }

  return {
    status: String(result.status || "unknown"),
    checkedAt: String(result.checkedAt || ""),
    currentVersion: String(result.currentVersion || state.currentVersion || ""),
    latestVersion: String(result.latestVersion || ""),
    updateAvailable: result.updateAvailable === true,
    releaseUrl: String(result.releaseUrl || ""),
    downloadUrl: String(result.downloadUrl || ""),
    assetName: String(result.assetName || ""),
    publishedAt: String(result.publishedAt || ""),
    message: String(result.message || ""),
  };
}

function renderUpdateSettings() {
  ui.updateVersionLabel.textContent = state.currentVersion ? `Version ${state.currentVersion}` : "Version unknown";
  ui.updateAutoCheck.disabled = !state.backendCapabilities.updates;
  ui.checkUpdatesButton.disabled = !state.backendCapabilities.updates;
  ui.updateAutoCheck.checked = state.appSettings.updates.autoCheckEnabled;

  if (!state.backendCapabilities.updates) {
    renderUpdateStatus({
      status: "muted",
      message: "Update checks are not available in the current backend.",
    });
    return;
  }

  if (!state.updateSupport.configured) {
    renderUpdateStatus({
      status: "muted",
      message: "The update feed is not configured yet. You can still keep the option disabled.",
    });
    return;
  }

  if (state.appSettings.updates.lastResult) {
    renderUpdateStatus(state.appSettings.updates.lastResult);
    return;
  }

  renderUpdateStatus({
    status: "muted",
    message: state.appSettings.updates.autoCheckEnabled
      ? "Automatic update checks are enabled and will run on startup."
      : "Automatic update checks are disabled. Use Check now whenever you want.",
  });
}

function renderUpdateStatus(result) {
  const status = String(result?.status || "muted");
  const checkedAt = String(result?.checkedAt || "");
  const latestVersion = String(result?.latestVersion || "");
  const releaseUrl = String(result?.downloadUrl || result?.releaseUrl || "");
  const message = String(result?.message || "");
  const detailLines = [];
  if (message) {
    detailLines.push(message);
  }
  if (latestVersion) {
    detailLines.push(`Latest known version: ${latestVersion}`);
  }
  if (checkedAt) {
    detailLines.push(`Last checked: ${checkedAt}`);
  }
  if (!detailLines.length) {
    detailLines.push("No update information available yet.");
  }

  ui.updateStatus.className = `status-note ${status === "available" || status === "current" ? "ok" : status === "error" ? "error" : "muted"}`;
  ui.updateStatus.textContent = detailLines.join("\n");

  if (releaseUrl) {
    ui.updateReleaseLink.href = releaseUrl;
    ui.updateReleaseLink.classList.remove("hidden");
  } else {
    ui.updateReleaseLink.href = "#";
    ui.updateReleaseLink.classList.add("hidden");
  }
}

function renderSectionVisibilitySettings() {
  ui.showDiagnosticsToggle.checked = state.appSettings.ui.showDiagnostics;
  ui.showFunscriptOverviewToggle.checked = state.appSettings.ui.showFunscriptOverview;
  ui.showExecutionLogToggle.checked = state.appSettings.ui.showExecutionLog;
  ui.diagnosticsPanel.classList.toggle("hidden", !state.appSettings.ui.showDiagnostics);
  ui.scriptCard.classList.toggle("hidden", !state.appSettings.ui.showFunscriptOverview);
  ui.logCard.classList.toggle("hidden", !state.appSettings.ui.showExecutionLog);
}

async function handleUpdateAutoCheckChange() {
  const previousValue = state.appSettings.updates.autoCheckEnabled;
  state.appSettings.updates.autoCheckEnabled = ui.updateAutoCheck.checked;
  renderUpdateSettings();

  try {
    await persistAppSettings();
    renderUpdateSettings();
    renderSectionVisibilitySettings();

    if (state.appSettings.updates.autoCheckEnabled) {
      await checkForUpdates({ automatic: true });
    }
  } catch (error) {
    state.appSettings.updates.autoCheckEnabled = previousValue;
    ui.updateAutoCheck.checked = previousValue;
    renderUpdateStatus({
      status: "error",
      message: `Could not save update setting: ${String(error)}`,
    });
  }
}

async function handleSectionVisibilityChange() {
  const previousSettings = normalizeAppSettings(state.appSettings);
  state.appSettings.ui.showDiagnostics = ui.showDiagnosticsToggle.checked;
  state.appSettings.ui.showFunscriptOverview = ui.showFunscriptOverviewToggle.checked;
  state.appSettings.ui.showExecutionLog = ui.showExecutionLogToggle.checked;
  renderSectionVisibilitySettings();

  try {
    await persistAppSettings();
    renderUpdateSettings();
    renderSectionVisibilitySettings();
  } catch (error) {
    state.appSettings = previousSettings;
    renderSectionVisibilitySettings();
    appendLog({ ok: false, title: "Could not save panel visibility", detail: String(error) });
  }
}

async function checkForUpdates({ automatic = false } = {}) {
  if (!state.backendCapabilities.updates) {
    return;
  }

  ui.checkUpdatesButton.disabled = true;
  try {
    const response = await fetch("/api/update/check", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ automatic }),
    });
    const data = await parseJsonResponse(response);
    state.currentVersion = String(data.currentVersion || state.currentVersion || "");
    state.appSettings = normalizeAppSettings(data.settings);
    state.appSettings.updates.lastResult = normalizeUpdateResult(data.result) || state.appSettings.updates.lastResult;
    if (!response.ok || !data.ok) {
      renderUpdateSettings();
      throw new Error(data.error || data.result?.message || `HTTP ${response.status}`);
    }

    renderUpdateSettings();
  } catch (error) {
    renderUpdateStatus({
      status: "error",
      message: `Update check failed: ${String(error)}`,
    });
    if (!automatic) {
      appendLog({ ok: false, title: "Update check failed", detail: String(error) });
    }
  } finally {
    ui.checkUpdatesButton.disabled = !state.backendCapabilities.updates;
  }
}

function normalizeDiagnosticsInfo(payload) {
  return {
    available: payload?.ok === true,
    platform: String(payload?.platform || state.backendCapabilities.platform || "desktop"),
    version: String(payload?.version || state.currentVersion || ""),
    paths: {
      appData: String(payload?.paths?.appData || ""),
      libraryRoot: String(payload?.paths?.libraryRoot || ""),
      settingsFile: String(payload?.paths?.settingsFile || ""),
      logDirectory: String(payload?.paths?.logDirectory || ""),
      logFile: String(payload?.paths?.logFile || ""),
    },
    capabilities: {
      openLogFolder: payload?.capabilities?.openLogFolder === true,
    },
    recentLog: String(payload?.recentLog || ""),
  };
}

function renderDiagnosticsInfo() {
  if (!ui.diagnosticsStatus || !ui.diagnosticsPaths || !ui.diagnosticsLog) {
    return;
  }

  if (!state.backendCapabilities.diagnostics) {
    ui.diagnosticsStatus.textContent = "Diagnostics unavailable";
    ui.diagnosticsPaths.value = "The current backend does not expose diagnostics information.";
    ui.diagnosticsLog.value = "No diagnostic log output is available.";
    ui.refreshDiagnosticsButton.disabled = true;
    ui.openDiagnosticsButton.disabled = true;
    ui.openDiagnosticsButton.classList.add("hidden");
    return;
  }

  if (!state.diagnostics.available) {
    ui.diagnosticsStatus.textContent = "Diagnostics not loaded";
    ui.diagnosticsPaths.value = "Could not load diagnostics information from the backend.";
    ui.diagnosticsLog.value = "No diagnostic log output is available yet.";
    ui.refreshDiagnosticsButton.disabled = false;
    ui.openDiagnosticsButton.disabled = true;
    ui.openDiagnosticsButton.classList.add("hidden");
    return;
  }

  ui.diagnosticsStatus.textContent = state.diagnostics.version
    ? `${state.diagnostics.platform} | v${state.diagnostics.version}`
    : state.diagnostics.platform;
  ui.diagnosticsPaths.value = [
    `App data: ${state.diagnostics.paths.appData || "-"}`,
    `Library root: ${state.diagnostics.paths.libraryRoot || "-"}`,
    `Settings: ${state.diagnostics.paths.settingsFile || "-"}`,
    `Log directory: ${state.diagnostics.paths.logDirectory || "-"}`,
    `Log file: ${state.diagnostics.paths.logFile || "-"}`,
  ].join("\n");
  ui.diagnosticsLog.value = state.diagnostics.recentLog || "No recent log output has been written yet.";
  ui.refreshDiagnosticsButton.disabled = false;
  ui.openDiagnosticsButton.disabled = !state.diagnostics.capabilities.openLogFolder;
  ui.openDiagnosticsButton.classList.toggle("hidden", !state.diagnostics.capabilities.openLogFolder);
}

async function loadDiagnosticsInfo() {
  if (!state.backendCapabilities.diagnostics) {
    renderDiagnosticsInfo();
    return;
  }

  ui.refreshDiagnosticsButton.disabled = true;
  try {
    const response = await fetch("/api/diagnostics/info", { cache: "no-store" });
    const data = await parseJsonResponse(response);
    if (!response.ok || !data.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }
    state.diagnostics = normalizeDiagnosticsInfo(data);
    renderDiagnosticsInfo();
  } catch (error) {
    state.diagnostics = normalizeDiagnosticsInfo({});
    renderDiagnosticsInfo();
    appendLog({ ok: false, title: "Diagnostics unavailable", detail: String(error) });
  } finally {
    ui.refreshDiagnosticsButton.disabled = !state.backendCapabilities.diagnostics;
  }
}

async function openDiagnosticsFolder() {
  if (!state.diagnostics.capabilities.openLogFolder) {
    return;
  }

  try {
    const response = await fetch("/api/diagnostics/open", {
      method: "POST",
    });
    const data = await parseJsonResponse(response);
    if (!response.ok || !data.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }
  } catch (error) {
    appendLog({
      ok: false,
      title: "Could not open diagnostics folder",
      detail: String(error),
    });
  }
}

function renderExecutionModeForm() {
  const isLovenseMode = ui.executionMode.value === "lovense-live" || ui.executionMode.value === "lovense-test";
  const isLovenseLiveMode = ui.executionMode.value === "lovense-live";
  ui.lovenseConfig.classList.toggle("hidden", !isLovenseMode);
  ui.lovenseLiveConfig.classList.toggle("hidden", !isLovenseLiveMode);
  ui.lovenseDeviceLabel.textContent = isLovenseLiveMode ? "Detected devices" : "Simulated devices";
  if (isLovenseMode) {
    ui.lovenseStatus.textContent = isLovenseLiveMode
      ? `Active profile: ${getSelectedConnection(state.formLovense)?.label || "User"}`
      : "Simulation mode active.";
  }
}

async function refreshLibraryInfo() {
  try {
    const response = await fetch("/api/library/info", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json();
    state.library = {
      available: true,
      platform: data.platform || state.backendCapabilities.platform || "desktop",
      rootPath: String(data.rootPath || ""),
      directories: {
        videos: String(data.directories?.videos || ""),
        funscripts: String(data.directories?.funscripts || ""),
        exports: String(data.directories?.exports || ""),
      },
      capabilities: {
        import: data.capabilities?.import !== false,
        reveal: data.capabilities?.reveal === true,
      },
    };
  } catch (error) {
    state.library = {
      available: false,
      platform: state.backendCapabilities.platform || "desktop",
      rootPath: "",
      directories: {
        videos: "",
        funscripts: "",
        exports: "",
      },
      capabilities: {
        import: false,
        reveal: false,
      },
    };
    appendLog({ ok: false, title: "Library unavailable", detail: String(error) });
  }

  renderLibraryInfo();
}

function renderLibraryInfo() {
  if (!ui.libraryStatus || !ui.libraryPaths) {
    return;
  }

  if (!state.library.available) {
    ui.libraryStatus.textContent = "Managed library unavailable.";
    ui.libraryPaths.value = "No managed library endpoint was detected.";
    toggleLibraryRevealButtons(false);
    ui.importLibraryButton.disabled = true;
    return;
  }

  const pathLines = [
    `Root: ${state.library.rootPath || "-"}`,
    `Videos: ${state.library.directories.videos || "-"}`,
    `Funscripts: ${state.library.directories.funscripts || "-"}`,
    `Exports: ${state.library.directories.exports || "-"}`,
  ];
  ui.libraryStatus.textContent =
    state.library.platform === "android"
      ? "App-managed library is ready on this device."
      : "Managed FHPlayer folders are ready.";
  ui.libraryPaths.value = pathLines.join("\n");
  ui.importLibraryButton.disabled = !state.library.capabilities.import;
  toggleLibraryRevealButtons(state.library.capabilities.reveal);
}

function toggleLibraryRevealButtons(isEnabled) {
  [ui.openVideoLibraryButton, ui.openFunscriptLibraryButton, ui.openExportsLibraryButton].forEach((button) => {
    button.disabled = !isEnabled;
    button.classList.toggle("hidden", !isEnabled);
  });
}

async function detectLovenseDevices() {
  if (ui.executionMode.value !== "lovense-live") {
    ui.lovenseStatus.textContent = "Device detection is only available in Lovense live mode.";
    return;
  }

  const config = getLovenseConfigFromForm();
  const connection = getSelectedConnection(state.formLovense);
  if (!connection) {
    appendLog({ ok: false, title: "Lovense detection failed", detail: "No connection profile selected." });
    return;
  }
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

    state.detectedToysByConnection[connection.id] = data.normalized?.toys ?? [];
    const detectedToys = getCurrentAvailableToys();
    const detectedToyIds = new Set(detectedToys.map((toy) => toy.id));
    const preferredToys = getSelectedToysForCurrentMode(getCurrentEntry()?.lovense).filter((toy) => detectedToyIds.has(toy.id));
    const nextSelectedToys = preferredToys.length ? preferredToys : detectedToys.slice(0, 1).map((toy) => normalizeToySelection(toy));
    assignSelectedToysToForm(nextSelectedToys);
    renderLovenseToySelect(
      nextSelectedToys.map((toy) => toy.id),
      detectedToys,
      getCurrentToyFallbacks(getCurrentEntry()?.lovense),
    );

    if (detectedToys.length) {
      updateLovenseSelectionDetails(nextSelectedToys);
      ui.lovenseStatus.textContent = data.resolvedEndpoint
        ? `Detected ${detectedToys.length} device(s) for ${connection.label} via ${data.resolvedEndpoint}.`
        : `Detected ${detectedToys.length} device(s) for ${connection.label}.`;
    } else {
      assignSelectedToysToForm([]);
      updateLovenseSelectionDetails([]);
      ui.lovenseStatus.textContent = data.resolvedEndpoint
        ? `No Lovense devices detected for ${connection.label} via ${data.resolvedEndpoint}.`
        : `No Lovense devices detected for ${connection.label}.`;
    }
    renderLovenseRuleStatus();
  } catch (error) {
    state.detectedToysByConnection[connection.id] = [];
    renderLovenseToySelect([], getCurrentAvailableToys(), getCurrentToyFallbacks());
    assignSelectedToysToForm([]);
    updateLovenseSelectionDetails([]);
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
  const selectedToys = getSelectedToysForCurrentMode(getCurrentEntry()?.lovense);
  assignSelectedToysToForm(selectedToys);
  updateLovenseSelectionDetails(selectedToys);
  renderPlaylist();
  renderStatus();
  renderLovenseRuleStatus();
}

function handleLovenseConnectionSelectionChange() {
  const selectedConnectionId = ui.lovenseConnectionSelect.value;
  state.formLovense = normalizeLovenseConfig({
    ...state.formLovense,
    selectedConnectionId,
  });
  syncLovenseConnectionFields();
  renderExecutionModeForm();
  renderLovenseToySelect(getCurrentSelectedToyIds(), getCurrentAvailableToys(), getCurrentToyFallbacks());
  updateLovenseSelectionDetails(getSelectedToysForCurrentMode(getCurrentEntry()?.lovense));
  renderLovenseRuleStatus();
}

function handleLovenseConnectionFieldInput() {
  const selectedConnection = getSelectedConnection(state.formLovense);
  if (!selectedConnection) {
    return;
  }

  const updatedConnections = state.formLovense.connections.map((connection) =>
    connection.id === selectedConnection.id
      ? normalizeLovenseConnection({
          ...connection,
          label: ui.lovenseConnectionName.value,
          scheme: ui.lovenseScheme.value,
          host: ui.lovenseHost.value,
          port: ui.lovensePort.value,
          platformName: ui.lovensePlatformName.value,
        })
      : connection,
  );

  state.formLovense = normalizeLovenseConfig({
    ...state.formLovense,
    connections: updatedConnections,
    selectedConnectionId: selectedConnection.id,
  });

  renderLovenseConnectionSelect();
  syncLovenseConnectionFields();
  renderExecutionModeForm();
  renderPlaylist();
  renderStatus();
}

function addLovenseConnectionProfile() {
  const nextIndex = state.formLovense.connections.length + 1;
  const newConnection = normalizeLovenseConnection({
    ...DEFAULT_LOVENSE_CONNECTION,
    id: `user-${Date.now()}`,
    label: `User ${nextIndex}`,
  });
  state.formLovense = normalizeLovenseConfig({
    ...state.formLovense,
    connections: [...state.formLovense.connections, newConnection],
    selectedConnectionId: newConnection.id,
  });
  syncLovenseConnectionFields();
  renderLovenseConnectionSelect();
  renderExecutionModeForm();
  renderLovenseToySelect(getCurrentSelectedToyIds(), getCurrentAvailableToys(), getCurrentToyFallbacks());
  updateLovenseSelectionDetails(getSelectedToysForCurrentMode());
  renderLovenseRuleStatus();
}

function removeLovenseConnectionProfile() {
  if (state.formLovense.connections.length <= 1) {
    appendLog({ ok: false, title: "Connection profile not removed", detail: "At least one Lovense user profile must remain." });
    return;
  }

  const selectedConnection = getSelectedConnection(state.formLovense);
  const nextConnections = state.formLovense.connections.filter((connection) => connection.id !== selectedConnection?.id);
  const nextSelectedId = nextConnections[0]?.id || DEFAULT_LOVENSE_CONNECTION.id;
  if (selectedConnection?.id) {
    delete state.detectedToysByConnection[selectedConnection.id];
  }

  state.formLovense = normalizeLovenseConfig({
    ...state.formLovense,
    connections: nextConnections,
    selectedConnectionId: nextSelectedId,
  });
  syncLovenseConnectionFields();
  renderLovenseConnectionSelect();
  renderExecutionModeForm();
  renderLovenseToySelect(getCurrentSelectedToyIds(), getCurrentAvailableToys(), getCurrentToyFallbacks());
  updateLovenseSelectionDetails(getSelectedToysForCurrentMode(getCurrentEntry()?.lovense));
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

  try {
    validateSelectedFunscriptFiles(funscriptFiles);
  } catch (error) {
    appendLog({ ok: false, title: "Could not extend playlist", detail: String(error) });
    return;
  }

  let parsedScripts;
  try {
    const selectedDocuments = await getSelectedDocumentsForFiles("funscripts", funscriptFiles);
    parsedScripts = await Promise.all(
      funscriptFiles.map((file, index) => parseFunscriptFile(file, selectedDocuments[index] || null)),
    );
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

async function handleFunscriptSelectionPreview() {
  const funscriptFiles = Array.from(ui.funscriptFiles.files ?? []);
  if (!funscriptFiles.length) {
    return;
  }

  try {
    validateSelectedFunscriptFiles(funscriptFiles);
  } catch (error) {
    appendLog({ ok: false, title: "Could not read funscript", detail: String(error) });
    return;
  }

  let parsedScripts;
  try {
    const selectedDocuments = await getSelectedDocumentsForFiles("funscripts", funscriptFiles);
    parsedScripts = await Promise.all(
      funscriptFiles.map((file, index) => parseFunscriptFile(file, selectedDocuments[index] || null)),
    );
  } catch (error) {
    appendLog({ ok: false, title: "Could not read funscript", detail: String(error) });
    return;
  }

  const previewScript = parsedScripts[0];
  if (!previewScript) {
    return;
  }

  if (!hasPersistedScriptSettings(previewScript.settings)) {
    appendLog({
      ok: true,
      title: "Funscript loaded",
      detail: `${previewScript.file.name} contains no saved FHPlayer settings. Current form values were kept.`,
    });
    return;
  }

  applyScriptSettingsToForm(previewScript.settings);

  const detailLines = [`Loaded saved FHPlayer settings from ${previewScript.file.name} into the form.`];
  if (parsedScripts.length > 1) {
    detailLines.push("With multiple selected funscripts, the first file is used as the form template.");
  }

  appendLog({
    ok: true,
    title: "Funscript settings applied",
    detail: detailLines.join("\n"),
  });
}

async function handleImportSelectedFilesToLibrary() {
  if (!state.library.available || !state.library.capabilities.import) {
    appendLog({
      ok: false,
      title: "Library import unavailable",
      detail: "This build does not support importing files into the managed FHPlayer library.",
    });
    return;
  }

  const videoFiles = Array.from(ui.videoFiles.files ?? []);
  const funscriptFiles = Array.from(ui.funscriptFiles.files ?? []);
  if (!videoFiles.length && !funscriptFiles.length) {
    appendLog({
      ok: false,
      title: "Nothing to import",
      detail: "Select one or more videos or funscripts first.",
    });
    return;
  }

  try {
    validateSelectedFunscriptFiles(funscriptFiles);
  } catch (error) {
    appendLog({
      ok: false,
      title: "Library import failed",
      detail: String(error),
    });
    return;
  }

  try {
    const importedVideos = [];
    for (const file of videoFiles) {
      importedVideos.push(await uploadFileToLibrary("videos", file));
    }

    const importedScripts = [];
    for (const file of funscriptFiles) {
      importedScripts.push(await uploadFileToLibrary("funscripts", file));
    }

    const detailLines = [];
    if (importedVideos.length) {
      detailLines.push(`Videos: ${importedVideos.map((item) => item.fileName).join(", ")}`);
      detailLines.push(`Video folder: ${state.library.directories.videos || "-"}`);
    }
    if (importedScripts.length) {
      detailLines.push(`Funscripts: ${importedScripts.map((item) => item.fileName).join(", ")}`);
      detailLines.push(`Funscript folder: ${state.library.directories.funscripts || "-"}`);
    }

    appendLog({
      ok: true,
      title: "Library import finished",
      detail: detailLines.join("\n"),
    });
  } catch (error) {
    appendLog({
      ok: false,
      title: "Library import failed",
      detail: String(error),
    });
  }
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
    if (state.backendCapabilities.platform === "android" && entry.funscriptSource?.token) {
      const result = await overwriteSelectedAndroidDocument(entry.funscriptSource.token, content);
      entry.scriptDocument = updatedDocument;
      appendLog({
        ok: true,
        title: "Funscript saved",
        detail:
          `${entry.funscriptName} was overwritten in place. Only FHPlayer metadata values were updated.\n` +
          `Target: ${result.name || entry.funscriptName}`,
      });
      return;
    }

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

    if (state.library.available && state.library.capabilities.import) {
      const result = await uploadTextToLibrary("exports", entry.funscriptName, content);
      entry.scriptDocument = updatedDocument;
      appendLog({
        ok: true,
        title: "Funscript exported",
        detail:
          `${entry.funscriptName} was saved into the FHPlayer export folder.\n` +
          `Path: ${result.path || state.library.directories.exports || "-"}`,
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
    sendLovenseStopForCurrentEntry("Execution disabled. Sent stop to the selected Lovense devices.", { force: true });
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
  sendLovenseStopForCurrentEntry("Playback paused. Sent stop to the selected Lovense devices.");
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
  triggerLovenseRuleAction(entry, action, currentMs);
}

async function triggerLovenseRuleAction(entry, action, currentMs) {
  const executionMode = normalizeExecutionMode(entry.executionMode);
  const context = {
    index: action.index,
    atMs: action.atMs,
    pos: action.pos,
    currentMs: Math.round(currentMs),
    deltaMs: Math.round(currentMs - action.atMs),
  };

  let commands;
  try {
    commands = evaluateLovenseRuleCommands(entry.rulesText, entry.lovense, context, {
      requireToyId: executionMode === "lovense-live",
      mode: executionMode === "lovense-test" ? "test" : "live",
    }).commands;
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
  const executionMode = normalizeExecutionMode(entry.executionMode);
  state.pendingExecutions += 1;
  renderStatus();

  const selectedToys = getEffectiveLovenseSelectedToys(entry.lovense, executionMode === "lovense-test" ? "test" : "live");
  const detailLines = [
    `Devices: ${formatLovenseSelectedToySummary(
      selectedToys,
      executionMode === "lovense-test" ? "no simulated device" : "current selection",
    )}`,
    `Delay: ${batch.delayMs} ms`,
    `Commands: ${batch.commands.map((item) => formatLovenseCommandForLog(item, selectedToys)).join(", ")}`,
  ];

  if (executionMode === "lovense-test") {
    appendLog({
      ok: true,
      title: `Lovense test ${action.index} at ${formatMs(action.atMs)}`,
      detail: detailLines.join("\n"),
    });
    state.pendingExecutions = Math.max(0, state.pendingExecutions - 1);
    renderStatus();
    return;
  }

  if (ui.dryRun.checked) {
    appendLog({
      ok: true,
      title: `Lovense dry run ${action.index} at ${formatMs(action.atMs)}`,
      detail: detailLines.join("\n"),
    });
    state.pendingExecutions = Math.max(0, state.pendingExecutions - 1);
    renderStatus();
    return;
  }

  const seenToyIds = new Set();
  const payloadCommands = batch.commands.flatMap((command) =>
    (command.toyIds || []).map((toyId) => {
      const usesLocalAutoStop = command.durationMs > 0 && command.durationMs < 1000;
      const payloadCommand = {
        ...command,
        toyIds: undefined,
        toy: toyId,
        delayMs: undefined,
        durationMs: undefined,
        timeSec: usesLocalAutoStop ? 0 : Math.max(0, (command.durationMs ?? 0) / 1000),
        localAutoStopDurationMs: usesLocalAutoStop ? command.durationMs : 0,
        usesLocalAutoStop,
        stopPrevious: isFirstBatch && !seenToyIds.has(toyId) ? 1 : 0,
      };
      seenToyIds.add(toyId);
      return payloadCommand;
    }),
  );
  if (!payloadCommands.length) {
    appendLog({
      ok: false,
      title: `Lovense action ${action.index} skipped`,
      detail: `${detailLines.join("\n")}\nNo target device was resolved for this batch.`,
    });
    state.pendingExecutions = Math.max(0, state.pendingExecutions - 1);
    renderStatus();
    return;
  }

  const requestCommands = payloadCommands.map(({ usesLocalAutoStop, localAutoStopDurationMs, ...command }) => command);

  try {
    const response = await fetch("/api/lovense/command", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        config: buildLovenseRequestConfig(entry.lovense),
        timeoutSeconds: 5,
        commands: requestCommands,
      }),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }

    const affectedToyIds = [...new Set(payloadCommands.map((command) => command.toy).filter(Boolean))];
    affectedToyIds.forEach(clearLovenseAutoStopTimer);
    payloadCommands.forEach((command) => {
      if (command.usesLocalAutoStop && command.localAutoStopDurationMs > 0) {
        scheduleLovenseAutoStop(entry, action, command.toy, command.localAutoStopDurationMs);
      }
    });

    appendLog({
      ok: true,
      title: `Lovense action ${action.index} at ${formatMs(action.atMs)}`,
      detail: detailLines.join("\n"),
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

async function parseFunscriptFile(file, sourceDocument = null) {
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
    sourceDocument: sourceDocument ? normalizeSelectedDocument(sourceDocument) : null,
  };
}

function validateSelectedFunscriptFiles(files) {
  const invalidFiles = files.filter((file) => !isAcceptedFunscriptFile(file));
  if (!invalidFiles.length) {
    return;
  }

  throw new Error(
    `Only .funscript and .json files are allowed for funscripts. Invalid selection: ${invalidFiles.map((file) => file.name).join(", ")}`,
  );
}

function isAcceptedFunscriptFile(file) {
  const extension = getFileExtension(file.name);
  if (ACCEPTED_FUNSCRIPT_EXTENSIONS.has(extension)) {
    return true;
  }

  return ACCEPTED_FUNSCRIPT_MIME_TYPES.has(String(file.type || "").trim().toLowerCase());
}

function getFileExtension(fileName) {
  const normalizedName = String(fileName || "").trim().toLowerCase();
  const lastDotIndex = normalizedName.lastIndexOf(".");
  if (lastDotIndex < 0 || lastDotIndex === normalizedName.length - 1) {
    return "";
  }

  return normalizedName.slice(lastDotIndex + 1);
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
    funscriptSource: scriptData.sourceDocument,
    executionMode: settings.executionMode,
    rulesText: settings.rulesText,
    lovense: settings.lovense,
  };
}

function resolveInitialEntrySettings(scriptSettings) {
  const formExecutionMode = ui.executionMode.value;
  const formRulesText = normalizeRulesText(ui.lovenseRules.value);
  const formLovense = normalizeLovenseConfig(getLovenseConfigFromForm());
  return {
    executionMode:
      formExecutionMode !== DEFAULT_EXECUTION_MODE
        ? formExecutionMode
        : normalizeExecutionMode(scriptSettings.executionMode) || DEFAULT_EXECUTION_MODE,
    rulesText: formRulesText !== DEFAULT_RULES_TEXT ? formRulesText : scriptSettings.rulesText || DEFAULT_RULES_TEXT,
    lovense: isLovenseConfigCustomized(formLovense) ? formLovense : normalizeLovenseConfig(scriptSettings.lovense),
  };
}

function hasPersistedScriptSettings(scriptSettings) {
  return Boolean(
    scriptSettings.executionMode ||
      scriptSettings.rulesText ||
      isLovenseConfigCustomized(scriptSettings.lovense),
  );
}

function applyScriptSettingsToForm(scriptSettings) {
  ui.executionMode.value = normalizeExecutionMode(scriptSettings.executionMode) || DEFAULT_EXECUTION_MODE;
  ui.lovenseRules.value = scriptSettings.rulesText || DEFAULT_RULES_TEXT;
  applyLovenseConfigToForm(scriptSettings.lovense, { resetDetectedToys: true });
  renderExecutionModeForm();
  renderLovenseToySelect(
    getCurrentSelectedToyIds(),
    getCurrentAvailableToys(),
    getCurrentToyFallbacks(scriptSettings.lovense),
  );
  updateLovenseSelectionDetails(getSelectedToysForCurrentMode(scriptSettings.lovense));
  renderLovenseRuleStatus();
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
    rulesText: firstNonEmpty(metadataFhplayer.rulesText, metadataFhPlayer.rulesText, fhplayer.rulesText, parsed.rulesText),
    lovense: normalizeLovenseConfig(lovense),
  };
}

function applyCurrentFormToEntry(entry) {
  entry.executionMode = ui.executionMode.value;
  entry.rulesText = normalizeRulesText(ui.lovenseRules.value);
  entry.lovense = normalizeLovenseConfig(getLovenseConfigFromForm());
}

function buildSavedFunscriptDocument(entry) {
  const documentCopy = cloneJson(entry.scriptDocument ?? {});
  const metadata = documentCopy.metadata && typeof documentCopy.metadata === "object" ? documentCopy.metadata : {};
  const normalizedLovense = normalizeLovenseConfig(entry.lovense);

  metadata.fhplayer = {
    schemaVersion: 2,
    executionMode: entry.executionMode,
    rulesText: entry.rulesText,
    lovense: {
      selectedConnectionId: normalizedLovense.selectedConnectionId,
      connections: normalizedLovense.connections,
      testSelectedToys: normalizedLovense.testSelectedToys,
      testToyId: normalizedLovense.testToyId,
      testToyName: normalizedLovense.testToyName,
      testToyType: normalizedLovense.testToyType,
      testCapabilities: normalizedLovense.testCapabilities,
    },
  };

  documentCopy.metadata = metadata;
  return documentCopy;
}

function getLovenseConfigFromForm() {
  return normalizeLovenseConfig(state.formLovense);
}

function applyLovenseConfigToForm(config, options = {}) {
  const { resetDetectedToys = false } = options;
  state.formLovense = normalizeLovenseConfig(config);
  if (resetDetectedToys) {
    state.detectedToysByConnection = {};
  }
  renderLovenseConnectionSelect();
  syncLovenseConnectionFields();
}

function normalizeLovenseConnection(connection, index = 1) {
  const merged = connection || {};
  const legacyToy =
    merged.toyId || merged.toyName || merged.toyType || (Array.isArray(merged.capabilities) && merged.capabilities.length)
      ? [
          normalizeToySelection({
            toyId: merged.toyId,
            toyName: merged.toyName,
            toyType: merged.toyType,
            capabilities: merged.capabilities,
          }),
        ].filter((toy) => toy.id)
      : [];
  const selectedToys = (Array.isArray(merged.selectedToys) ? merged.selectedToys : legacyToy)
    .map((toy) => normalizeToySelection(toy))
    .filter((toy) => toy.id);
  const primaryToy = selectedToys[0] || null;
  const capabilities = getSharedCapabilitiesForToys(selectedToys);
  return {
    id: String(merged.id || `user-${index}`).trim() || `user-${index}`,
    label: String(merged.label || `User ${index}`).trim() || `User ${index}`,
    scheme: String(merged.scheme || DEFAULT_LOVENSE_CONNECTION.scheme).trim().toLowerCase() || DEFAULT_LOVENSE_CONNECTION.scheme,
    host: String(merged.host || "").trim(),
    port: String(merged.port || "").trim(),
    platformName: String(merged.platformName || DEFAULT_LOVENSE_CONNECTION.platformName).trim() || DEFAULT_LOVENSE_CONNECTION.platformName,
    selectedToys,
    toyId: primaryToy?.id || "",
    toyName: primaryToy?.nickName || primaryToy?.name || "",
    toyType: primaryToy?.type || "",
    capabilities,
  };
}

function normalizeLovenseConfig(config) {
  const merged = {
    ...DEFAULT_LOVENSE_CONFIG,
    ...(config || {}),
  };
  const explicitConnections = Array.isArray(config?.connections) ? config.connections : null;
  const explicitTestSelectedToys = Array.isArray(config?.testSelectedToys) ? config.testSelectedToys : null;
  const hasLegacyLiveConfig = Boolean(
    merged.scheme ||
      merged.host ||
      merged.port ||
      merged.platformName ||
      merged.toyId ||
      merged.toyName ||
      merged.toyType ||
      (Array.isArray(merged.capabilities) && merged.capabilities.length),
  );
  const hasLegacyTestConfig = Boolean(
    merged.testToyId ||
      merged.testToyName ||
      merged.testToyType ||
      (Array.isArray(merged.testCapabilities) && merged.testCapabilities.length),
  );
  const legacyConnection = {
    id: DEFAULT_LOVENSE_CONNECTION.id,
    label: DEFAULT_LOVENSE_CONNECTION.label,
    scheme: merged.scheme || DEFAULT_LOVENSE_CONNECTION.scheme,
    host: merged.host || DEFAULT_LOVENSE_CONNECTION.host,
    port: merged.port || DEFAULT_LOVENSE_CONNECTION.port,
    platformName: merged.platformName || DEFAULT_LOVENSE_CONNECTION.platformName,
    selectedToys:
      merged.toyId || merged.toyName || merged.toyType || merged.capabilities
        ? [
            {
              toyId: merged.toyId,
              toyName: merged.toyName,
              toyType: merged.toyType,
              capabilities: merged.capabilities,
            },
          ]
        : [],
  };
  const rawConnections =
    explicitConnections && explicitConnections.length
      ? explicitConnections
      : hasLegacyLiveConfig
        ? [legacyConnection]
        : DEFAULT_LOVENSE_CONFIG.connections;
  const connections = rawConnections.map((connection, index) => normalizeLovenseConnection(connection, index + 1));
  const selectedConnectionId =
    String(merged.selectedConnectionId || "").trim() && connections.some((connection) => connection.id === merged.selectedConnectionId)
      ? String(merged.selectedConnectionId).trim()
      : connections[0]?.id || DEFAULT_LOVENSE_CONNECTION.id;
  const selectedConnection = connections.find((connection) => connection.id === selectedConnectionId) || connections[0];

  const legacyTestToy =
    merged.testToyId || merged.testToyName || merged.testToyType || merged.testCapabilities
      ? [
          normalizeToySelection({
            toyId: merged.testToyId,
            toyName: merged.testToyName,
            toyType: merged.testToyType,
            capabilities: merged.testCapabilities,
            }),
        ].filter((toy) => toy.id)
      : [];
  const testSelectedToys = (
    explicitTestSelectedToys && explicitTestSelectedToys.length
      ? explicitTestSelectedToys
      : hasLegacyTestConfig
        ? legacyTestToy
        : DEFAULT_LOVENSE_CONFIG.testSelectedToys
  )
    .map((toy) => normalizeToySelection(toy))
    .filter((toy) => toy.id);
  const normalizedTestSelectedToys = testSelectedToys.length
    ? testSelectedToys
    : DEFAULT_LOVENSE_CONFIG.testSelectedToys.map((toy) => normalizeToySelection(toy));
  const primaryTestToy = normalizedTestSelectedToys[0] || null;
  const sharedTestCapabilities = getSharedCapabilitiesForToys(normalizedTestSelectedToys);

  return {
    selectedConnectionId,
    connections,
    scheme: selectedConnection?.scheme || DEFAULT_LOVENSE_CONNECTION.scheme,
    host: selectedConnection?.host || "",
    port: selectedConnection?.port || "",
    platformName: selectedConnection?.platformName || DEFAULT_LOVENSE_CONNECTION.platformName,
    selectedToys: selectedConnection?.selectedToys || [],
    toyId: selectedConnection?.toyId || "",
    toyName: selectedConnection?.toyName || "",
    toyType: selectedConnection?.toyType || "",
    capabilities: selectedConnection?.capabilities || [],
    testSelectedToys: normalizedTestSelectedToys,
    testToyId: primaryTestToy?.id || "",
    testToyName: primaryTestToy?.nickName || primaryTestToy?.name || "",
    testToyType: primaryTestToy?.type || "",
    testCapabilities: sharedTestCapabilities,
  };
}

function normalizeRulesText(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed || DEFAULT_RULES_TEXT;
}

function normalizeToySelection(toy) {
  return {
    id: String(toy?.id || toy?.toyId || "").trim(),
    name: String(toy?.name || toy?.toyName || toy?.type || toy?.toyType || toy?.id || toy?.toyId || "").trim(),
    nickName: String(toy?.nickName || toy?.toyName || toy?.name || "").trim(),
    type: String(toy?.type || toy?.toyType || "").trim(),
    fullFunctionNames: getNormalizedCapabilityList(toy),
  };
}

function getSelectedConnection(lovenseConfig) {
  const normalized = normalizeLovenseConfig(lovenseConfig);
  return normalized.connections.find((connection) => connection.id === normalized.selectedConnectionId) || normalized.connections[0] || null;
}

function getEffectiveLovenseSelectedToys(lovense, mode = "live") {
  const normalizedLovense = normalizeLovenseConfig(lovense);
  const toys =
    mode === "test"
      ? normalizedLovense.testSelectedToys || []
      : getSelectedConnection(normalizedLovense)?.selectedToys || [];
  return toys.map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
}

function renderLovenseConnectionSelect() {
  ui.lovenseConnectionSelect.innerHTML = state.formLovense.connections
    .map((connection) => `<option value="${escapeHtml(connection.id)}">${escapeHtml(connection.label)}</option>`)
    .join("");
  ui.lovenseConnectionSelect.value = state.formLovense.selectedConnectionId || state.formLovense.connections[0]?.id || "";
}

function syncLovenseConnectionFields() {
  const selectedConnection = getSelectedConnection(state.formLovense);
  ui.lovenseConnectionName.value = selectedConnection?.label || "";
  ui.lovenseScheme.value = selectedConnection?.scheme || DEFAULT_LOVENSE_CONNECTION.scheme;
  ui.lovenseHost.value = selectedConnection?.host || "";
  ui.lovensePort.value = selectedConnection?.port || "";
  ui.lovensePlatformName.value = selectedConnection?.platformName || DEFAULT_LOVENSE_CONNECTION.platformName;
}

function getCurrentAvailableToys() {
  if (ui.executionMode.value === "lovense-test") {
    return SIMULATED_TOYS;
  }

  const selectedConnection = getSelectedConnection(state.formLovense);
  return selectedConnection ? state.detectedToysByConnection[selectedConnection.id] ?? [] : [];
}

function getCurrentSelectedToyIds() {
  if (ui.executionMode.value === "lovense-test") {
    return (state.formLovense.testSelectedToys || []).map((toy) => toy.id).filter(Boolean);
  }

  return (getSelectedConnection(state.formLovense)?.selectedToys || []).map((toy) => toy.id).filter(Boolean);
}

function getCurrentToyFallbacks(fallbackLovense = null) {
  const normalizedFallback = fallbackLovense ? normalizeLovenseConfig(fallbackLovense) : null;
  if (ui.executionMode.value === "lovense-test") {
    return normalizedFallback ? normalizedFallback.testSelectedToys || [] : [];
  }

  const fallbackConnection = normalizedFallback ? getSelectedConnection(normalizedFallback) : null;
  return fallbackConnection ? fallbackConnection.selectedToys || [] : [];
}

function collectSelectedToyIdsFromUi() {
  return Array.from(ui.lovenseToySelect.selectedOptions)
    .map((option) => option.value)
    .filter(Boolean);
}

function getSelectedToysForCurrentMode(fallbackLovense = null) {
  const selectedToyIds = collectSelectedToyIdsFromUi();
  const availableToys = getCurrentAvailableToys();
  const selectedToys = availableToys.filter((toy) => selectedToyIds.includes(toy.id)).map((toy) => normalizeToySelection(toy));
  if (selectedToys.length) {
    return selectedToys;
  }

  const fallbackToys = (getCurrentToyFallbacks(fallbackLovense) || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  if (fallbackToys.length) {
    return fallbackToys;
  }

  if (ui.executionMode.value === "lovense-test") {
    return [normalizeToySelection(SIMULATED_TOYS[0])];
  }

  return [];
}

function assignSelectedToysToForm(toys) {
  const normalizedToys = (toys || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  if (ui.executionMode.value === "lovense-test") {
    state.formLovense = normalizeLovenseConfig({
      ...state.formLovense,
      testSelectedToys: normalizedToys.length ? normalizedToys : [normalizeToySelection(SIMULATED_TOYS[0])],
    });
    return;
  }

  const selectedConnection = getSelectedConnection(state.formLovense);
  if (!selectedConnection) {
    return;
  }

  state.formLovense = normalizeLovenseConfig({
    ...state.formLovense,
    connections: state.formLovense.connections.map((connection) =>
      connection.id === selectedConnection.id
        ? {
            ...connection,
            selectedToys: normalizedToys,
          }
        : connection,
    ),
  });
}

function normalizeLovenseCapabilityName(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (!normalized) {
    return "";
  }

  for (const definition of Object.values(LOVENSE_ACTIONS)) {
    const capabilityNames = definition.capabilityNames || [definition.apiName];
    const matchedCapability = capabilityNames.find((entry) => String(entry || "").trim().toLowerCase() === normalized);
    if (matchedCapability) {
      return matchedCapability;
    }
    if (String(definition.apiName || "").trim().toLowerCase() === normalized || (definition.aliases || []).includes(normalized)) {
      return capabilityNames[0] || definition.apiName;
    }
  }

  return String(value || "").trim();
}

function getLovenseActionCapabilities(definition) {
  return (definition?.capabilityNames || [definition?.apiName]).map((value) => normalizeLovenseCapabilityName(value)).filter(Boolean);
}

function isLovenseActionSupportedByCapabilities(definition, capabilities) {
  const normalizedCapabilities = (capabilities || []).map((value) => normalizeLovenseCapabilityName(value)).filter(Boolean);
  if (!normalizedCapabilities.length) {
    return false;
  }

  return getLovenseActionCapabilities(definition).some((capability) => normalizedCapabilities.includes(capability));
}

function formatLovenseActionSignature(actionKey) {
  const definition = LOVENSE_ACTIONS[actionKey];
  if (!definition) {
    return "";
  }

  if (!definition.parameterRanges.length) {
    return definition.allowDuration ? `${actionKey}([durationMs])` : `${actionKey}()`;
  }

  const parameterText = definition.parameterRanges
    .map((parameter) => (parameter.min === parameter.max ? `${parameter.min}` : `${parameter.min}-${parameter.max}`))
    .join(", ");
  return definition.allowDuration ? `${actionKey}(${parameterText}[, durationMs])` : `${actionKey}(${parameterText})`;
}

function getNormalizedCapabilityList(source) {
  const fullFunctionNames = Array.isArray(source?.fullFunctionNames)
    ? source.fullFunctionNames.map((value) => String(value || "").trim()).filter(Boolean)
    : [];
  const capabilities = Array.isArray(source?.capabilities)
    ? source.capabilities.map((value) => String(value || "").trim()).filter(Boolean)
    : [];
  const shortFunctionNames = Array.isArray(source?.shortFunctionNames)
    ? source.shortFunctionNames
        .map((value) => LOVENSE_SHORT_CAPABILITY_MAP[String(value || "").trim().toLowerCase()] || value)
        .map((value) => String(value || "").trim())
        .filter(Boolean)
    : [];

  const rawCapabilities = fullFunctionNames.length
    ? fullFunctionNames
    : capabilities.length
      ? capabilities
      : shortFunctionNames.length
        ? shortFunctionNames
        : inferLovenseCapabilitiesFromType(source);

  const normalizedCapabilities = [];
  rawCapabilities.forEach((value) => {
    const canonical = normalizeLovenseCapabilityName(value);

    if (canonical && !normalizedCapabilities.includes(canonical)) {
      normalizedCapabilities.push(canonical);
    }
  });

  return normalizedCapabilities;
}

function inferLovenseCapabilitiesFromType(source) {
  const candidateText = [source?.type, source?.toyType, source?.name, source?.toyName, source?.nickName]
    .map((value) => String(value || "").trim())
    .filter(Boolean)
    .join(" ");

  if (!candidateText) {
    return [];
  }

  const matchedHint = LOVENSE_TYPE_CAPABILITY_HINTS.find((hint) => hint.match.test(candidateText));
  return matchedHint ? matchedHint.capabilities : [];
}

function getSharedCapabilitiesForToys(toys) {
  const normalizedToys = (toys || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  if (!normalizedToys.length) {
    return [];
  }

  return normalizedToys
    .map((toy) => toy.fullFunctionNames)
    .reduce((shared, current) => shared.filter((capability) => current.includes(capability)));
}

function getCombinedCapabilitiesForToys(toys) {
  const combinedCapabilities = [];
  (toys || []).forEach((toy) => {
    normalizeToySelection(toy).fullFunctionNames.forEach((capability) => {
      if (capability && !combinedCapabilities.includes(capability)) {
        combinedCapabilities.push(capability);
      }
    });
  });
  return combinedCapabilities;
}

function formatLovenseSelectedToySummary(toys, emptyLabel = "no device") {
  const normalizedToys = (toys || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  if (!normalizedToys.length) {
    return emptyLabel;
  }

  if (normalizedToys.length === 1) {
    return normalizedToys[0].nickName || normalizedToys[0].name || normalizedToys[0].type || normalizedToys[0].id;
  }

  const labels = normalizedToys
    .map((toy) => toy.nickName || toy.name || toy.type || toy.id)
    .filter(Boolean);
  return `${normalizedToys.length} devices (${labels.slice(0, 2).join(", ")}${labels.length > 2 ? ", ..." : ""})`;
}

function normalizeToySelectorValue(value) {
  return String(value || "").trim().toLowerCase();
}

function slugifyToySelectorValue(value) {
  return normalizeToySelectorValue(value).replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

function getToySelectorCandidates(toy) {
  const normalizedToy = normalizeToySelection(toy);
  const candidates = new Set();
  [normalizedToy.id, normalizedToy.nickName, normalizedToy.name, normalizedToy.type].forEach((value) => {
    const normalizedValue = normalizeToySelectorValue(value);
    const slugValue = slugifyToySelectorValue(value);
    if (normalizedValue) {
      candidates.add(normalizedValue);
    }
    if (slugValue) {
      candidates.add(slugValue);
    }
  });
  return [...candidates];
}

function formatLovenseToySelectors(toys) {
  return (toys || [])
    .map((toy) => normalizeToySelection(toy))
    .filter((toy) => toy.id)
    .map((toy) => `${toy.nickName || toy.name || toy.type || toy.id} [${toy.id}]`)
    .join(", ");
}

function resolveCommandTargetToys(command, selectedToys, lineNumber = command?.lineNumber) {
  const normalizedToys = (selectedToys || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  if (!normalizedToys.length) {
    return [];
  }

  const selector = normalizeToySelectorValue(command?.targetSelector);
  if (!selector) {
    return normalizedToys;
  }

  const byIdMatches = normalizedToys.filter((toy) => normalizeToySelectorValue(toy.id) === selector);
  if (byIdMatches.length) {
    return byIdMatches;
  }

  const matches = normalizedToys.filter((toy) => getToySelectorCandidates(toy).includes(selector));
  if (matches.length) {
    return matches;
  }

  throw new Error(
    `Line ${lineNumber}: unknown device selector [${command.targetSelector}]. Available selectors: ${formatLovenseToySelectors(normalizedToys)}.`,
  );
}

function formatLovenseCommandForLog(command, selectedToys) {
  const normalizedToys = (selectedToys || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  if (!normalizedToys.length) {
    return `no target device: ${command.action} | durationMs=${command.durationMs ?? 0}`;
  }
  const targetToys = normalizedToys.filter((toy) => (command.toyIds || []).includes(toy.id));
  const targetLabel =
    targetToys.length === normalizedToys.length
      ? "all selected devices"
      : formatLovenseSelectedToySummary(targetToys, command.targetSelector ? `[${command.targetSelector}]` : "no device");
  return `${targetLabel}: ${command.action} | durationMs=${command.durationMs ?? 0}`;
}

function parseOfflineCapabilityText(value) {
  return String(value || "")
    .split(/[,/;|]+/)
    .map((part) => normalizeLovenseCapabilityName(part))
    .filter((part, index, all) => part && all.indexOf(part) === index);
}

function getLovenseDeviceProfile(lovense) {
  const capabilities = getNormalizedCapabilityList(lovense);
  const selectedToys = (lovense?.selectedToys || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  const uniqueTypes = [...new Set(selectedToys.map((toy) => toy.type || toy.name || toy.id).filter(Boolean))];
  const deviceType =
    (selectedToys.length > 1 ? uniqueTypes.join(", ") : "") ||
    String(lovense?.toyType || lovense?.type || lovense?.toyName || "").trim() ||
    "Unknown";
  const maxSimultaneousActions = Math.max(1, capabilities.length || 1);

  return {
    deviceType,
    capabilities,
    maxSimultaneousActions,
    supportsMultipleActions: maxSimultaneousActions > 1,
    selectedToyCount: selectedToys.length || (lovense?.toyId ? 1 : 0),
  };
}

function getAllowedLovenseActions(profile) {
  const actions = [];
  if (profile.capabilities.length) {
    Object.entries(LOVENSE_ACTIONS).forEach(([actionKey, definition]) => {
      if (actionKey === "stop" || actionKey === "all" || isLovenseActionSupportedByCapabilities(definition, profile.capabilities)) {
        actions.push(actionKey);
      }
    });
  } else {
    actions.push("stop");
  }
  return actions;
}

function formatLovenseActionRange(actionKey) {
  const definition = LOVENSE_ACTIONS[actionKey];
  if (!definition) {
    return "";
  }
  return formatLovenseActionSignature(actionKey);
}

function getAvailableLovenseActionKeysForToys(toys, options = {}) {
  const { includeMetaActions = true } = options;
  const combinedCapabilities = getCombinedCapabilitiesForToys(toys);
  const actionKeys = [];

  Object.entries(LOVENSE_ACTIONS).forEach(([actionKey, definition]) => {
    if (actionKey === "stop" || actionKey === "all") {
      return;
    }
    if (isLovenseActionSupportedByCapabilities(definition, combinedCapabilities)) {
      actionKeys.push(actionKey);
    }
  });

  if (!includeMetaActions) {
    return actionKeys;
  }

  return ["all", ...actionKeys, "stop"].filter((actionKey, index, all) => all.indexOf(actionKey) === index);
}

function renderLovenseActionRanges(lovenseConfig = null, options = {}) {
  if (!ui.lovenseActionRanges) {
    return;
  }

  const { mode = ui.executionMode.value === "lovense-test" ? "test" : "live" } = options;
  const normalizedMode = mode === "test" ? "test" : "live";

  try {
    const effectiveConfig = lovenseConfig ? getEffectiveLovenseDeviceConfig(lovenseConfig, normalizedMode) : null;
    const selectedToys = effectiveConfig?.selectedToys || [];
    const visibleToys = selectedToys.length ? selectedToys : getCurrentAvailableToys().map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
    const actionKeys = visibleToys.length ? getAvailableLovenseActionKeysForToys(visibleToys) : [];
    if (!actionKeys.length) {
      ui.lovenseActionRanges.innerHTML = visibleToys.length
        ? "<strong>Action ranges:</strong> No supported Lovense actions were detected for the current devices."
        : "<strong>Action ranges:</strong> Detect or select a device to see the relevant actions.";
      return;
    }

    const rangeText = actionKeys.map((actionKey) => formatLovenseActionRange(actionKey)).filter(Boolean).join(", ");
    ui.lovenseActionRanges.innerHTML = selectedToys.length
      ? `<strong>Action ranges for current selection:</strong> <strong>${escapeHtml(rangeText)}</strong>.`
      : `<strong>Action ranges for detected devices:</strong> <strong>${escapeHtml(rangeText)}</strong>.`;
  } catch (_error) {
    ui.lovenseActionRanges.innerHTML = "<strong>Action ranges:</strong> Detect or select a device to see the relevant actions.";
  }
}

function buildOfflineLovenseTestConfig() {
  const simulatedToys = getSelectedToysForCurrentMode();
  return normalizeLovenseConfig({
    ...state.formLovense,
    testSelectedToys: simulatedToys.length ? simulatedToys : DEFAULT_LOVENSE_CONFIG.testSelectedToys,
  });
}

function resolveLovenseRuleConfig(entry = null, { allowOfflineTest = false, requireToyId = true } = {}) {
  const normalizedEntryLovense = entry?.lovense ? normalizeLovenseConfig(entry.lovense) : null;
  const selectedConfig = normalizeLovenseConfig(getLovenseConfigFromForm());

  if (ui.executionMode.value === "lovense-test") {
    const offlineConfig = allowOfflineTest ? buildOfflineLovenseTestConfig() : selectedConfig;
    const selectedToys = getSelectedToysForCurrentMode(normalizedEntryLovense);
    return normalizeLovenseConfig({
      ...offlineConfig,
      testSelectedToys:
        selectedToys.length ||
        normalizedEntryLovense?.testSelectedToys?.length ||
        offlineConfig.testSelectedToys?.length
          ? selectedToys.length
            ? selectedToys
            : normalizedEntryLovense?.testSelectedToys || offlineConfig.testSelectedToys
          : DEFAULT_LOVENSE_CONFIG.testSelectedToys,
    });
  }

  const selectedConnection = getSelectedConnection(selectedConfig);
  if ((selectedConnection?.selectedToys || []).length) {
    return selectedConfig;
  }

  if (allowOfflineTest) {
    const fallbackConnection = normalizedEntryLovense ? getSelectedConnection(normalizedEntryLovense) : null;
    if ((fallbackConnection?.selectedToys || []).length) {
      return normalizedEntryLovense;
    }
  }

  if (!requireToyId) {
    return selectedConfig;
  }

  return selectedConfig;
}

function validateCurrentFormForPersistence(entry = null) {
  if (ui.executionMode.value !== "lovense-live" && ui.executionMode.value !== "lovense-test") {
    return;
  }

  const isTestMode = ui.executionMode.value === "lovense-test";
  const lovenseConfig = resolveLovenseRuleConfig(entry, { allowOfflineTest: isTestMode, requireToyId: !isTestMode });
  validateLovenseRulesForConfig(ui.lovenseRules.value, lovenseConfig, {
    requireToyId: !isTestMode,
    mode: isTestMode ? "test" : "live",
  });
}

function isLovenseConfigCustomized(config) {
  const normalized = normalizeLovenseConfig(config);
  return (
    normalized.connections.some((connection, index) => {
      const defaultConnection = normalizeLovenseConnection(
        {
          ...DEFAULT_LOVENSE_CONNECTION,
          id: `user-${index + 1}`,
          label: `User ${index + 1}`,
        },
        index + 1,
      );
      return (
        connection.label !== defaultConnection.label ||
        connection.scheme !== defaultConnection.scheme ||
        connection.host !== defaultConnection.host ||
        connection.port !== defaultConnection.port ||
        connection.platformName !== defaultConnection.platformName ||
        connection.selectedToys.map((toy) => toy.id).join(",") !== defaultConnection.selectedToys.map((toy) => toy.id).join(",") ||
        connection.capabilities.length > 0
      );
    }) ||
    normalized.connections.length > 1 ||
    normalized.testSelectedToys.map((toy) => toy.id).join(",") !== DEFAULT_LOVENSE_CONFIG.testSelectedToys.map((toy) => toy.id).join(",")
  );
}

function renderLovenseToySelect(selectedToyIds, toys, fallbackToys = null) {
  const options = [...toys].map((toy) => normalizeToySelection(toy));
  (fallbackToys || []).forEach((fallbackToy) => {
    const fallbackToyId = fallbackToy?.id || fallbackToy?.toyId || "";
    if (fallbackToyId && !options.some((toy) => toy.id === fallbackToyId)) {
      options.push(normalizeToySelection({
        id: fallbackToyId,
        name: fallbackToy.name || fallbackToy.toyName || fallbackToy.type || fallbackToy.toyType || fallbackToyId,
        nickName: fallbackToy.nickName || fallbackToy.toyName || "",
        type: fallbackToy.type || fallbackToy.toyType || "",
        fullFunctionNames: fallbackToy.fullFunctionNames || fallbackToy.capabilities || [],
      }));
    }
  });

  const requestedSelection = (Array.isArray(selectedToyIds) ? selectedToyIds : [selectedToyIds]).filter(Boolean);
  const matchedSelection = requestedSelection.filter((toyId) => options.some((toy) => toy.id === toyId));
  const effectiveSelection = matchedSelection.length ? matchedSelection : options[0] ? [options[0].id] : [];
  const selectedSet = new Set(effectiveSelection);
  ui.lovenseToySelect.innerHTML = options.length
    ? options
        .map((toy) => {
          const labelParts = [toy.nickName || toy.name || toy.id];
          if (toy.type && toy.type !== toy.name) {
            labelParts.push(toy.type);
          }
          labelParts.push(`ID:${toy.id}`);
          if (Array.isArray(toy.fullFunctionNames) && toy.fullFunctionNames.length) {
            labelParts.push(toy.fullFunctionNames.join("/"));
          }
          return `<option value="${escapeHtml(toy.id)}"${selectedSet.has(toy.id) ? " selected" : ""}>${escapeHtml(labelParts.join(" | "))}</option>`;
        })
        .join("")
    : '<option value="" disabled>No devices available</option>';

  Array.from(ui.lovenseToySelect.options).forEach((option) => {
    option.selected = selectedSet.has(option.value);
  });

  if (effectiveSelection.join(",") !== requestedSelection.join(",")) {
    assignSelectedToysToForm(options.filter((toy) => selectedSet.has(toy.id)));
  }
}

function findToyById(toyId) {
  return getCurrentAvailableToys().find((toy) => toy.id === toyId) ?? null;
}

function updateLovenseSelectionDetails(toys) {
  const normalizedToys = (toys || []).map((toy) => normalizeToySelection(toy)).filter((toy) => toy.id);
  if (!normalizedToys.length) {
    ui.lovenseCapabilities.value = "-";
    ui.lovenseDeviceType.value = "-";
    ui.lovenseParallelActions.value = "-";
    return;
  }

  const combinedCapabilities = getCombinedCapabilitiesForToys(normalizedToys);
  const sharedCapabilities = getSharedCapabilitiesForToys(normalizedToys);
  const deviceTypes = normalizedToys.map((toy) => toy.type || toy.name || toy.id).filter(Boolean);
  const sharedLimit = Math.max(1, sharedCapabilities.length || 1);
  const capabilityLines = normalizedToys.map((toy) => {
    const toyLabel = toy.nickName || toy.name || toy.type || toy.id;
    return `${toyLabel}: ${toy.fullFunctionNames.join(", ") || "-"}`;
  });
  const parallelActionLines = normalizedToys.map((toy) => {
    const toyLabel = toy.nickName || toy.name || toy.type || toy.id;
    const toyLimit = Math.max(1, toy.fullFunctionNames.length || 1);
    return `${toyLabel}: up to ${toyLimit} action(s) at once`;
  });

  ui.lovenseCapabilities.value =
    normalizedToys.length === 1
      ? combinedCapabilities.join(", ") || "-"
      : [`Shared: ${sharedCapabilities.join(", ") || "none"}`, ...capabilityLines].join("\n");
  ui.lovenseDeviceType.value = normalizedToys.length === 1 ? deviceTypes[0] || "-" : deviceTypes.join(", ");
  ui.lovenseParallelActions.value =
    normalizedToys.length === 1
      ? `Up to ${Math.max(1, combinedCapabilities.length || 1)} actions at once`
      : [`Shared limit: ${sharedLimit}`, ...parallelActionLines].join("\n");
}

function renderLovenseRuleStatus() {
  if (ui.executionMode.value !== "lovense-live" && ui.executionMode.value !== "lovense-test") {
    ui.lovenseRuleStatus.className = "status-note muted";
    ui.lovenseRuleStatus.textContent = "Lovense rule validation is active in Lovense live and Lovense test mode.";
    renderLovenseActionRanges();
    return;
  }

  const currentEntry = getCurrentEntry();
  const isTestMode = ui.executionMode.value === "lovense-test";
  const validationConfig = resolveLovenseRuleConfig(currentEntry, { allowOfflineTest: isTestMode, requireToyId: !isTestMode });
  renderLovenseActionRanges(validationConfig, { mode: isTestMode ? "test" : "live" });

  try {
    const { profile, compiled } = validateLovenseRulesForConfig(ui.lovenseRules.value, validationConfig, {
      requireToyId: !isTestMode,
      mode: isTestMode ? "test" : "live",
    });
    const selectedToys = getEffectiveLovenseSelectedToys(validationConfig, isTestMode ? "test" : "live");
    const actionList = getAllowedLovenseActions(profile).join(", ");
    const selectorList = formatLovenseToySelectors(selectedToys) || "-";
    ui.lovenseRuleStatus.className = "status-note ok";
    ui.lovenseRuleStatus.textContent =
      `${isTestMode ? "Simulation active. " : ""}Valid rule script. Devices: ${formatLovenseSelectedToySummary(
        selectedToys,
        isTestMode ? "no simulated device" : "no device",
      )}. Device type: ${profile.deviceType}. Shared actions without selector: ${actionList}. ` +
      `Available selectors: ${selectorList}. ` +
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
  state.lovenseAutoStopTimers.forEach((timerId) => {
    clearTimeout(timerId);
  });
  state.lovenseAutoStopTimers.clear();
}

function clearLovenseAutoStopTimer(toyId) {
  if (!toyId || !state.lovenseAutoStopTimers.has(toyId)) {
    return;
  }
  clearTimeout(state.lovenseAutoStopTimers.get(toyId));
  state.lovenseAutoStopTimers.delete(toyId);
}

function scheduleLovenseAutoStop(entry, action, toyId, durationMs) {
  if (!toyId || !(durationMs > 0)) {
    return;
  }

  clearLovenseAutoStopTimer(toyId);
  const timerId = window.setTimeout(async () => {
    state.lovenseAutoStopTimers.delete(toyId);
    const currentEntry = getCurrentEntry();
    if (!state.armed || !currentEntry || currentEntry.id !== entry.id) {
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
              toy: toyId,
              apiVer: 1,
              stopPrevious: 1,
            },
          ],
        }),
      });
    } catch (error) {
      appendLog({
        ok: false,
        title: `Lovense auto-stop failed for action ${action.index}`,
        detail: `${toyId} after ${durationMs} ms\n${String(error)}`,
      });
    }
  }, durationMs);
  state.lovenseAutoStopTimers.set(toyId, timerId);
}

async function sendLovenseStopForCurrentEntry(logDetail, options = {}) {
  const { force = false } = options;
  const entry = getCurrentEntry();
  if (!entry || normalizeExecutionMode(entry.executionMode) !== "lovense-live" || (!state.armed && !force)) {
    return;
  }
  if (!entry.lovense?.host || !entry.lovense?.port) {
    return;
  }

  const selectedToys = getEffectiveLovenseSelectedToys(entry.lovense, "live");
  if (!selectedToys.length) {
    return;
  }

  try {
    await fetch("/api/lovense/command", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        config: buildLovenseRequestConfig(entry.lovense),
        timeoutSeconds: 5,
        commands: selectedToys.map((toy, index) => ({
          command: "Function",
          action: "Stop",
          timeSec: 0,
          toy: toy.id,
          apiVer: 1,
          stopPrevious: index === 0 ? 1 : 0,
        })),
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

function getEffectiveLovenseDeviceConfig(lovense, mode = "live") {
  const normalizedLovense = normalizeLovenseConfig(lovense);
  const selectedToys = getEffectiveLovenseSelectedToys(normalizedLovense, mode);
  const primaryToy = selectedToys[0] || null;

  return {
    ...normalizedLovense,
    selectedToys,
    toyIds: selectedToys.map((toy) => toy.id).filter(Boolean),
    toyId: primaryToy?.id || "",
    toyName: primaryToy?.nickName || primaryToy?.name || "",
    toyType:
      [...new Set(selectedToys.map((toy) => toy.type || toy.name || toy.id).filter(Boolean))].join(", ") ||
      (mode === "test" ? normalizedLovense.testToyType : normalizedLovense.toyType) ||
      "",
    capabilities: getSharedCapabilitiesForToys(selectedToys),
  };
}

function validateLovenseRulesForConfig(rulesText, lovense, options = {}) {
  const { requireToyId = true, mode = "live" } = options;
  const normalizedLovense = getEffectiveLovenseDeviceConfig(lovense, mode);

  if (requireToyId && !normalizedLovense.toyIds.length) {
    throw new Error("Select at least one detected Lovense device before using Lovense rules.");
  }

  const profile = getLovenseDeviceProfile(normalizedLovense);
  const selectedToys = normalizedLovense.selectedToys || [];
  if (!selectedToys.length && requireToyId) {
    throw new Error("Select at least one detected Lovense device before using Lovense rules.");
  }
  if (!profile.capabilities.length && selectedToys.length <= 1) {
    throw new Error(
      profile.selectedToyCount > 1
        ? "The selected devices do not share any supported Lovense capabilities."
        : `No supported Lovense capabilities were detected for ${profile.deviceType}.`,
    );
  }

  const compiled = parseRuleScript(rulesText);
  compiled.branches.forEach((branch) => {
    const actualCommands = branch.commands.filter((command) => command.actionKey !== "delay");
    if (!actualCommands.length) {
      throw new Error(`Line ${branch.lineNumber}: delay() cannot be the only command in a branch.`);
    }

    const perToyCommands = new Map();
    actualCommands.forEach((command) => {
      const targetToys = resolveCommandTargetToys(command, selectedToys, branch.lineNumber);
      if (!targetToys.length) {
        throw new Error(`Line ${command.lineNumber}: no selected Lovense devices match this command.`);
      }

      const canonical = LOVENSE_ACTIONS[command.actionKey];
      targetToys.forEach((toy) => {
        const toyProfile = getLovenseDeviceProfile({
          selectedToys: [toy],
          toyId: toy.id,
          toyName: toy.nickName || toy.name,
          toyType: toy.type,
          capabilities: toy.fullFunctionNames,
        });
        if (
          command.actionKey !== "stop" &&
          command.actionKey !== "all" &&
          !isLovenseActionSupportedByCapabilities(canonical, toyProfile.capabilities)
        ) {
          throw new Error(
            `Line ${command.lineNumber}: ${(toy.nickName || toy.name || toy.id)} does not support ${canonical.apiName}.`,
          );
        }

        if (!perToyCommands.has(toy.id)) {
          perToyCommands.set(toy.id, []);
        }
        perToyCommands.get(toy.id).push(command);
      });
    });

    perToyCommands.forEach((toyCommands, toyId) => {
      const toy = selectedToys.find((candidate) => candidate.id === toyId) || null;
      const toyLabel = toy?.nickName || toy?.name || toy?.id || toyId;
      const toyProfile = getLovenseDeviceProfile({
        selectedToys: toy ? [toy] : [],
        toyId,
        toyName: toyLabel,
        toyType: toy?.type || "",
        capabilities: toy?.fullFunctionNames || [],
      });
      const duplicateAction = toyCommands.find((command, index) =>
        toyCommands.findIndex((candidate) => candidate.actionKey === command.actionKey) !== index,
      );
      if (duplicateAction) {
        throw new Error(`Line ${duplicateAction.lineNumber}: ${toyLabel} uses ${duplicateAction.actionKey} more than once.`);
      }
      if (toyCommands.length > 1 && toyCommands.some((command) => command.actionKey === "stop")) {
        throw new Error(`Line ${branch.lineNumber}: stop() cannot be combined with other actions for ${toyLabel}.`);
      }
      if (toyCommands.length > 1 && toyCommands.some((command) => command.actionKey === "all")) {
        throw new Error(`Line ${branch.lineNumber}: all() cannot be combined with other actions for ${toyLabel}.`);
      }
      if (toyCommands.length > toyProfile.maxSimultaneousActions) {
        throw new Error(
          `Line ${branch.lineNumber}: ${toyLabel} supports ${toyProfile.maxSimultaneousActions} action(s) at once, but ${toyCommands.length} were configured.`,
        );
      }
    });
  });

  return { compiled, profile, lovense: normalizedLovense };
}

function evaluateLovenseRuleCommands(rulesText, lovenseConfig, context, options = {}) {
  const { compiled, lovense, profile } = validateLovenseRulesForConfig(rulesText, lovenseConfig, options);
  const scope = buildRuleScope(compiled.assignments, context);
  const matchedBranch = compiled.branches.find((branch) => branch.condition === null || evaluateBooleanExpression(branch.condition, scope));
  if (!matchedBranch) {
    return { commands: [], matchedBranch: null, compiled, lovense, profile, scope };
  }

  const branchDelayCommand = matchedBranch.commands.find((command) => command.actionKey === "delay") ?? null;
  const branchDelayMs = branchDelayCommand
    ? normalizeRuleDelayMs(evaluateNumericExpression(branchDelayCommand.valueExpression, scope), branchDelayCommand.lineNumber)
    : 0;
  const commands = matchedBranch.commands
    .filter((command) => command.actionKey !== "delay")
    .map((command, index) => {
      const targetToys = resolveCommandTargetToys(command, lovense.selectedToys, command.lineNumber);
      const canonical = LOVENSE_ACTIONS[command.actionKey];
      const parameterValues =
        command.actionKey === "stop"
          ? []
          : (command.valueExpressions || []).map((expression, parameterIndex) => {
              const parameter = canonical.parameterRanges[parameterIndex];
              return normalizeRuleNumericValue(
                evaluateNumericExpression(expression, scope),
                parameter.min,
                parameter.max,
                command.lineNumber,
                `${canonical.apiName} ${parameter.label}`,
              );
            });
      const durationMs =
        command.actionKey === "stop" || !command.durationExpression
          ? 0
          : normalizeRuleDurationMs(evaluateNumericExpression(command.durationExpression, scope), command.lineNumber);
      return {
        command: "Function",
        action: canonical.buildAction(parameterValues),
        strength: parameterValues.length ? parameterValues[parameterValues.length - 1] : undefined,
        timeSec: 0,
        toyIds: targetToys.map((toy) => toy.id),
        targetSelector: command.targetSelector || "",
        stopPrevious: index === 0 ? 1 : 0,
        apiVer: 1,
        delayMs: branchDelayMs,
        durationMs,
      };
    });

  return { commands, matchedBranch, compiled, lovense, profile, scope };
}

function buildLovenseCommandsFromRules(entry, context) {
  const executionMode = normalizeExecutionMode(entry.executionMode);
  return evaluateLovenseRuleCommands(entry.rulesText, entry.lovense, context, {
    requireToyId: executionMode === "lovense-live",
    mode: executionMode === "lovense-test" ? "test" : "live",
  }).commands;
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
  const delayCommands = commands.filter((command) => command.actionKey === "delay");
  if (delayCommands.length > 1) {
    throw new Error(`delay() can only be used once on line ${lineNumber}.`);
  }
  return commands;
}

function parseSingleCommand(commandText, lineNumber, knownVariables) {
  let targetSelector = "";
  let normalizedCommandText = commandText.trim();
  const targetMatch = normalizedCommandText.match(/^\[([^\]]+)\]\s*(.+)$/);
  if (targetMatch) {
    targetSelector = String(targetMatch[1] || "").trim();
    normalizedCommandText = String(targetMatch[2] || "").trim();
    if (!targetSelector) {
      throw new Error(`Invalid empty device selector on line ${lineNumber}.`);
    }
  }

  const match = normalizedCommandText.match(/^([a-zA-Z][a-zA-Z0-9_]*)\s*\((.*)\)$/);
  if (!match) {
    throw new Error(`Invalid command syntax on line ${lineNumber}: ${commandText}`);
  }

  const rawActionName = String(match[1] || "").trim().toLowerCase();
  const actionKey = rawActionName === "delay" ? "delay" : normalizeActionKey(match[1]);
  if (!actionKey) {
    throw new Error(`Unknown Lovense action on line ${lineNumber}: ${match[1]}`);
  }

  const args = splitTopLevel(match[2] || "", ",")
    .map((value) => value.trim())
    .filter(Boolean);

  if (actionKey === "delay") {
    if (targetSelector) {
      throw new Error(`delay() cannot target a specific device on line ${lineNumber}.`);
    }
    if (args.length !== 1) {
      throw new Error(`delay() requires exactly one delay value on line ${lineNumber}.`);
    }
    return {
      targetSelector,
      actionKey,
      valueExpression: parseNumericExpression(args[0], lineNumber, knownVariables),
      durationExpression: null,
      lineNumber,
    };
  }

  if (actionKey === "stop") {
    if (args.length) {
      throw new Error(`stop() does not accept value or duration arguments on line ${lineNumber}. Use delay(ms) + stop().`);
    }
    return {
      targetSelector,
      actionKey,
      valueExpressions: [],
      durationExpression: null,
      lineNumber,
    };
  }

  const definition = LOVENSE_ACTIONS[actionKey];
  const requiredArgumentCount = definition.parameterRanges.length;
  const maximumArgumentCount = requiredArgumentCount + (definition.allowDuration ? 1 : 0);

  if (args.length < requiredArgumentCount || args.length > maximumArgumentCount) {
    throw new Error(`Action ${match[1]} must use ${formatLovenseActionSignature(actionKey)} on line ${lineNumber}.`);
  }

  return {
    targetSelector,
    actionKey,
    valueExpressions: args
      .slice(0, requiredArgumentCount)
      .map((value) => parseNumericExpression(value, lineNumber, knownVariables)),
    durationExpression:
      definition.allowDuration && args[requiredArgumentCount]
        ? parseNumericExpression(args[requiredArgumentCount], lineNumber, knownVariables)
        : null,
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

function normalizeRuleDurationMs(value, lineNumber) {
  if (!Number.isFinite(value)) {
    throw new Error(`Line ${lineNumber}: duration must resolve to a valid number.`);
  }

  const rounded = Math.round(value);
  if (rounded < 0) {
    throw new Error(`Line ${lineNumber}: duration must be 0 or greater.`);
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

function normalizeExecutionMode(mode) {
  if (mode === "lovense-rules") {
    return "lovense-live";
  }
  return mode || DEFAULT_EXECUTION_MODE;
}

function formatExecutionMode(mode) {
  const normalizedMode = normalizeExecutionMode(mode);
  if (normalizedMode === "lovense-live") {
    return "Lovense live";
  }
  if (normalizedMode === "lovense-test") {
    return "Lovense test";
  }
  return "Lovense live";
}

function getEntryModeSummary(entry) {
  const executionMode = normalizeExecutionMode(entry.executionMode);
  if (executionMode === "lovense-live") {
    const normalizedLovense = normalizeLovenseConfig(entry.lovense);
    const connection = getSelectedConnection(normalizedLovense);
    return (
      `${connection?.label || "User"} | ` +
      `${formatLovenseSelectedToySummary(connection?.selectedToys || [], "no device")} | ` +
      `${connection?.host || "-"}:${connection?.port || "-"}`
    );
  }

  if (executionMode === "lovense-test") {
    const normalizedLovense = normalizeLovenseConfig(entry.lovense);
    return `${formatLovenseSelectedToySummary(normalizedLovense.testSelectedToys || [], "simulated device")} | simulated`;
  }

  const normalizedLovense = normalizeLovenseConfig(entry.lovense);
  const connection = getSelectedConnection(normalizedLovense);
  return (
    `${connection?.label || "User"} | ` +
    `${formatLovenseSelectedToySummary(connection?.selectedToys || [], "no device")} | ` +
    `${connection?.host || "-"}:${connection?.port || "-"}`
  );
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

async function uploadFileToLibrary(kind, file) {
  const response = await fetch(buildLibraryImportUrl(kind, file.name), {
    method: "PUT",
    headers: {
      "Content-Type": file.type || "application/octet-stream",
    },
    body: file,
  });
  const data = await parseJsonResponse(response);
  if (!response.ok || !data.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return data;
}

async function uploadTextToLibrary(kind, fileName, content) {
  const response = await fetch(buildLibraryImportUrl(kind, fileName), {
    method: "PUT",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
    body: content,
  });
  const data = await parseJsonResponse(response);
  if (!response.ok || !data.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return data;
}

async function openLibraryDirectory(kind) {
  if (!state.library.capabilities.reveal) {
    return;
  }

  try {
    const response = await fetch(`/api/library/open?kind=${encodeURIComponent(kind)}`, {
      method: "POST",
    });
    const data = await parseJsonResponse(response);
    if (!response.ok || !data.ok) {
      throw new Error(data.error || `HTTP ${response.status}`);
    }
  } catch (error) {
    appendLog({
      ok: false,
      title: "Could not open library folder",
      detail: String(error),
    });
  }
}

function buildLibraryImportUrl(kind, fileName) {
  return `/api/library/import?kind=${encodeURIComponent(kind)}&filename=${encodeURIComponent(fileName)}`;
}

async function parseJsonResponse(response) {
  try {
    return await response.json();
  } catch {
    return { ok: false, error: `HTTP ${response.status}` };
  }
}

async function getSelectedDocumentsForFiles(kind, files) {
  if (state.backendCapabilities.platform !== "android") {
    return files.map(() => null);
  }

  const response = await fetch(`/api/android/document-selection?kind=${encodeURIComponent(kind)}`, {
    cache: "no-store",
  });
  const data = await parseJsonResponse(response);
  if (!response.ok || !data.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }

  return mapSelectedDocumentsToFiles(files, Array.isArray(data.documents) ? data.documents : []);
}

function mapSelectedDocumentsToFiles(files, documents) {
  const remainingDocuments = [...documents];
  return files.map((file) => {
    const exactMatchIndex = remainingDocuments.findIndex((document) => document?.name === file.name);
    if (exactMatchIndex >= 0) {
      const [matchedDocument] = remainingDocuments.splice(exactMatchIndex, 1);
      return normalizeSelectedDocument(matchedDocument);
    }

    const fallbackDocument = remainingDocuments.shift() || null;
    return fallbackDocument ? normalizeSelectedDocument(fallbackDocument) : null;
  });
}

function normalizeSelectedDocument(document) {
  if (!document || !document.token) {
    return null;
  }

  return {
    token: String(document.token).trim(),
    kind: String(document.kind || "").trim(),
    name: String(document.name || "").trim(),
    mimeType: String(document.mimeType || "").trim(),
    sizeBytes: Number.isFinite(Number(document.sizeBytes)) ? Number(document.sizeBytes) : null,
  };
}

async function overwriteSelectedAndroidDocument(token, content) {
  const response = await fetch(`/api/android/document-write?token=${encodeURIComponent(token)}`, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
    body: content,
  });
  const data = await parseJsonResponse(response);
  if (!response.ok || !data.ok) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }
  return data;
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return "";
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
  ui.executionMode.value = normalizeExecutionMode(entry.executionMode) || DEFAULT_EXECUTION_MODE;
  ui.lovenseRules.value = entry.rulesText || DEFAULT_RULES_TEXT;
  applyLovenseConfigToForm(entry.lovense || DEFAULT_LOVENSE_CONFIG);
  renderExecutionModeForm();
  renderLovenseToySelect(getCurrentSelectedToyIds(), getCurrentAvailableToys(), getCurrentToyFallbacks(entry.lovense));
  updateLovenseSelectionDetails(getSelectedToysForCurrentMode(entry.lovense));
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
  applyLovenseConfigToForm(DEFAULT_LOVENSE_CONFIG);
  renderExecutionModeForm();
  renderLovenseToySelect(getCurrentSelectedToyIds(), getCurrentAvailableToys(), getCurrentToyFallbacks());
  updateLovenseSelectionDetails(getSelectedToysForCurrentMode());
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
