import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fhplayer_flutter/lovense_mock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supportsDesktopWindowManager) {
    await windowManager.ensureInitialized();
  }
  VideoPlayerMediaKit.ensureInitialized(windows: true);
  runApp(const FHPlayerApp());
}

bool get supportsDesktopWindowManager =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class FHPlayerApp extends StatelessWidget {
  const FHPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FHPlayer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Segoe UI',
      ),
      home: const FHPlayerHomePage(),
    );
  }
}

class FHPlayerHomePage extends StatefulWidget {
  const FHPlayerHomePage({super.key});

  @override
  State<FHPlayerHomePage> createState() => _FHPlayerHomePageState();
}

class _FHPlayerHomePageState extends State<FHPlayerHomePage>
    with WindowListener {
  static const int _schedulerIntervalMs = 20;
  static const int _seekJumpToleranceMs = 1500;
  static const int _uiRefreshIntervalMs = 120;
  static const double _wideLayoutMinWidth = 1040;
  static const double _splitPanelsMinWidth = 760;
  static const double _defaultListPanelHeight = 340;
  static const double _widePlayerHeightFactor = 0.38;
  static const double _widePlayerMinHeight = 280;
  static const double _widePlayerMaxHeight = 420;
  static const double _wideListHeightFactor = 0.23;
  static const double _wideListMinHeight = 220;
  static const double _wideListMaxHeight = 300;
  static const Duration _playerControlsHideDelay = Duration(seconds: 2);

  VideoPlayerController? _videoController;
  Timer? _schedulerTimer;
  Timer? _playerControlsHideTimer;
  Funscript? _funscript;
  final FunscriptActionCursor _funscriptCursor = FunscriptActionCursor();
  final LovenseMockClient _lovenseMockClient = LovenseMockClient.demo();
  final Stopwatch _playbackClock = Stopwatch();
  final ScrollController _logScrollController = ScrollController();
  late final TextEditingController _lovenseRulesController;

  String _videoPath = '';
  String _videoName = '';
  String _funscriptPath = '';
  String _funscriptName = '';
  String _videoError = '';

  bool _videoInitializing = false;
  bool _pendingSeekSync = false;
  int? _lastSchedulerPositionMs;
  int _playbackClockBaseMs = 0;
  int? _previewSeekMs;
  int _lastUiRefreshMs = 0;
  int _timingDeltaCount = 0;
  int _timingDeltaTotalMs = 0;
  int? _timingDeltaMinMs;
  int? _timingDeltaMaxMs;
  int? _timingDeltaLastMs;
  bool _timingRunActive = false;
  bool _timingRunSummaryLogged = false;
  bool _logNeedsScrollToTop = false;
  bool _lovenseMockEnabled = true;
  bool _playerControlsVisible = true;
  bool _fullscreenPlayerVisible = false;
  double _playerVolume = 1.0;
  double _lastAudiblePlayerVolume = 1.0;

  final List<ExecutionLogEntry> _logEntries = <ExecutionLogEntry>[
    ExecutionLogEntry.info('App ready', 'Select a video and a funscript.'),
  ];

  bool get _hasInitializedVideo =>
      _videoController?.value.isInitialized ?? false;

  Duration get _currentPosition =>
      Duration(milliseconds: _estimatedPlaybackPositionMs());

  Duration get _videoDuration =>
      _videoController?.value.duration ?? Duration.zero;

  int get _displayPositionMs =>
      _previewSeekMs ?? _estimatedPlaybackPositionMs();

  FunscriptAction? get _currentAction => _funscriptCursor.currentAction;

  FunscriptAction? get _nextAction => _funscriptCursor.nextAction;

  FunscriptAction? get _lastLoggedAction =>
      _funscriptCursor.lastTriggeredAction;

  @override
  void initState() {
    super.initState();
    _lovenseRulesController = TextEditingController(
      text: _lovenseMockClient.rulesText,
    );
    if (supportsDesktopWindowManager) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (supportsDesktopWindowManager) {
      windowManager.removeListener(this);
    }
    _playerControlsHideTimer?.cancel();
    _disposeVideoController();
    _logScrollController.dispose();
    _lovenseRulesController.dispose();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (!mounted || _fullscreenPlayerVisible) {
      return;
    }
    setState(() {
      _fullscreenPlayerVisible = true;
      _playerControlsVisible = true;
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    if (!mounted || !_fullscreenPlayerVisible) {
      return;
    }
    setState(() {
      _fullscreenPlayerVisible = false;
      _playerControlsVisible = true;
    });
  }

  Future<void> _pickVideo() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    final PlatformFile? file = result?.files.single;
    if (file == null) {
      return;
    }

    final String? path = file.path;
    if (path == null || path.isEmpty) {
      _appendLog(
        ExecutionLogEntry.error(
          'Video selection failed',
          'The picker did not return a readable file path.',
        ),
      );
      return;
    }

    setState(() {
      _videoPath = path;
      _videoName = file.name;
      _videoError = '';
      _videoInitializing = true;
    });
    _appendLog(ExecutionLogEntry.info('Video selected', _videoName));
    await _initializeVideo(path);
  }

  Future<void> _pickFunscript() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['funscript', 'json'],
      withData: true,
    );
    final PlatformFile? file = result?.files.single;
    if (file == null) {
      return;
    }

    try {
      final String content = await _readPickedTextFile(file);
      final Funscript script = Funscript.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
        sourceName: file.name,
      );
      setState(() {
        _funscript = script;
        _funscriptName = file.name;
        _funscriptPath = file.path ?? file.name;
        _resetTimingStats();
        _funscriptCursor.setScript(
          script,
          positionMs: _currentPosition.inMilliseconds,
          includeCurrentAction: true,
        );
      });
      _appendLog(
        ExecutionLogEntry.success(
          'Funscript loaded',
          '${script.actions.length} actions from ${file.name}',
        ),
      );
    } on FormatException catch (error) {
      _appendLog(ExecutionLogEntry.error('Invalid funscript', error.message));
    } catch (error) {
      _appendLog(
        ExecutionLogEntry.error('Funscript load failed', error.toString()),
      );
    }
  }

  Future<String> _readPickedTextFile(PlatformFile file) async {
    if (file.bytes != null) {
      return utf8.decode(file.bytes!);
    }
    final String? path = file.path;
    if (path == null || path.isEmpty) {
      throw const FormatException('The selected file has no readable path.');
    }
    return File(path).readAsString();
  }

  Future<void> _initializeVideo(String path) async {
    try {
      _disposeVideoController();
      final VideoPlayerController controller = _createVideoController(path);
      controller.addListener(_handleVideoTick);
      _videoController = controller;

      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(_playerVolume);

      if (!mounted) {
        return;
      }

      setState(() {
        _videoInitializing = false;
        _videoError = controller.value.errorDescription ?? '';
        _lastSchedulerPositionMs = controller.value.position.inMilliseconds;
        _syncPlaybackClock(_lastSchedulerPositionMs ?? 0, running: false);
        _resetTimingStats();
        _funscriptCursor.resetLastTriggered();
        _syncActionCursor(
          _lastSchedulerPositionMs ?? 0,
          includeCurrentAction: true,
        );
      });
      _appendLog(
        ExecutionLogEntry.success(
          'Video initialized',
          '${_videoName.isEmpty ? 'Selected video' : _videoName} | '
              'duration ${formatDuration(controller.value.duration)}',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _videoInitializing = false;
        _videoError = error.toString();
      });
      _appendLog(
        ExecutionLogEntry.error(
          'Video initialization failed',
          error.toString(),
        ),
      );
    }
  }

  VideoPlayerController _createVideoController(String path) {
    final Uri uri = Uri.parse(path);
    if (defaultTargetPlatform == TargetPlatform.android &&
        uri.scheme == 'content') {
      return VideoPlayerController.contentUri(uri);
    }
    return VideoPlayerController.file(File(path));
  }

  void _disposeVideoController() {
    _stopActionScheduler();
    _stopPlaybackClock(anchorMs: 0);
    final VideoPlayerController? controller = _videoController;
    if (controller == null) {
      return;
    }
    controller.removeListener(_handleVideoTick);
    controller.dispose();
    _videoController = null;
  }

  void _handleVideoTick() {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final VideoPlayerValue value = controller.value;
    final int positionMs = value.position.inMilliseconds;
    if (!value.isPlaying) {
      _funscriptCursor.updateCurrentAction(positionMs);
    }
    _refreshUiIfNeeded(positionMs);
  }

  void _startActionScheduler() {
    _schedulerTimer ??= Timer.periodic(
      const Duration(milliseconds: _schedulerIntervalMs),
      (_) => _handleSchedulerTick(),
    );
  }

  void _stopActionScheduler() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
  }

  void _handleSchedulerTick() {
    final VideoPlayerController? controller = _videoController;
    final Funscript? script = _funscript;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final VideoPlayerValue value = controller.value;
    if (value.isBuffering) {
      final int bufferingPositionMs = value.position.inMilliseconds;
      _stopPlaybackClock(anchorMs: bufferingPositionMs);
      _funscriptCursor.updateCurrentAction(bufferingPositionMs);
      _lastSchedulerPositionMs = bufferingPositionMs;
      _refreshUiIfNeeded(bufferingPositionMs);
      return;
    }

    if (value.isPlaying && !_playbackClock.isRunning) {
      _startPlaybackClock(value.position.inMilliseconds);
    } else if (!value.isPlaying && _playbackClock.isRunning) {
      _stopPlaybackClock(anchorMs: value.position.inMilliseconds);
    }

    final int positionMs = _estimatedPlaybackPositionMs(value);
    final int? previousPositionMs = _lastSchedulerPositionMs;
    final bool playbackJumped =
        previousPositionMs != null &&
        (positionMs < previousPositionMs - 250 ||
            positionMs - previousPositionMs > _seekJumpToleranceMs);

    if (_pendingSeekSync || playbackJumped) {
      _syncActionCursor(positionMs, includeCurrentAction: true);
      _pendingSeekSync = false;
      if (playbackJumped && script != null) {
        _appendLog(
          ExecutionLogEntry.info(
            'Scheduler synced',
            'Position ${formatMs(positionMs)} | next ${_formatAction(_nextAction)}',
          ),
          refresh: false,
        );
      }
    } else if (value.isPlaying) {
      _triggerDueActions(positionMs);
    } else {
      _funscriptCursor.updateCurrentAction(positionMs);
      _stopActionScheduler();
      if (_isPlaybackCompleted(positionMs, value)) {
        _finishTimingRun(positionMs);
      }
    }

    _lastSchedulerPositionMs = positionMs;
    _refreshUiIfNeeded(positionMs);
  }

  void _triggerDueActions(int positionMs) {
    final List<FunscriptAction> dueActions = _funscriptCursor.triggerDue(
      positionMs,
    );
    for (final FunscriptAction action in dueActions) {
      final int deltaMs = positionMs - action.atMs;
      _recordTimingDelta(deltaMs);
      _appendLog(
        ExecutionLogEntry.action(
          'Action ${action.index} at ${formatMs(action.atMs)}',
          'pos ${action.pos} | video ${formatMs(positionMs)} | '
              'delta $deltaMs ms',
        ),
        refresh: false,
      );
      _sendLovenseMockAction(action, positionMs, deltaMs);
    }
  }

  void _syncActionCursor(int positionMs, {bool includeCurrentAction = false}) {
    _funscriptCursor.sync(
      positionMs,
      includeCurrentAction: includeCurrentAction,
    );
  }

  void _refreshUiIfNeeded(int positionMs) {
    if (!mounted) {
      return;
    }
    if ((positionMs - _lastUiRefreshMs).abs() < _uiRefreshIntervalMs) {
      return;
    }
    _lastUiRefreshMs = positionMs;
    setState(() {});
  }

  void _appendLog(ExecutionLogEntry entry, {bool refresh = true}) {
    _logEntries.insert(0, entry);
    if (_logEntries.length > 200) {
      _logEntries.removeRange(200, _logEntries.length);
    }
    _scheduleLogScrollToTop();
    if (refresh && mounted) {
      setState(() {});
    }
  }

  void _scheduleLogScrollToTop() {
    _logNeedsScrollToTop = true;
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_logNeedsScrollToTop) {
        return;
      }
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(0);
      }
      _logNeedsScrollToTop = false;
    });
  }

  Future<void> _togglePlayback() async {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      final int pausePositionMs = _estimatedPlaybackPositionMs(
        controller.value,
      );
      await controller.pause();
      _stopPlaybackClock(anchorMs: pausePositionMs);
      _stopActionScheduler();
      _showPlayerControls(autoHide: false);
      _sendLovenseMockStop('Playback paused', pausePositionMs);
      _appendLog(
        ExecutionLogEntry.info(
          'Playback paused',
          'Position ${formatMs(pausePositionMs)}',
        ),
      );
    } else {
      _resetTimingStats();
      _timingRunActive = true;
      _timingRunSummaryLogged = false;
      await controller.play();
      _startPlaybackClock(controller.value.position.inMilliseconds);
      _appendLog(
        ExecutionLogEntry.info(
          'Playback started',
          'Position ${formatMs(_estimatedPlaybackPositionMs(controller.value))}',
        ),
      );
      _startActionScheduler();
      _handleSchedulerTick();
      _showPlayerControls(autoHide: true);
    }
  }

  Future<void> _seekBy(Duration delta) async {
    final Duration target = _clampPosition(_currentPosition + delta);
    await _seekTo(target);
  }

  Future<void> _seekTo(Duration target) async {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    _pendingSeekSync = true;
    await controller.seekTo(_clampPosition(target));
    final int positionMs = controller.value.position.inMilliseconds;
    setState(() {
      _previewSeekMs = null;
      _lastSchedulerPositionMs = positionMs;
      _pendingSeekSync = false;
      _syncPlaybackClock(positionMs, running: controller.value.isPlaying);
      _syncActionCursor(positionMs, includeCurrentAction: true);
    });
    _appendLog(
      ExecutionLogEntry.info(
        'Seek',
        'Position ${formatDuration(controller.value.position)} | '
            'next ${_formatAction(_nextAction)}',
      ),
    );
  }

  Duration _clampPosition(Duration position) {
    final Duration duration = _videoDuration;
    if (position < Duration.zero) {
      return Duration.zero;
    }
    if (duration > Duration.zero && position > duration) {
      return duration;
    }
    return position;
  }

  int _clampPositionMs(int positionMs) {
    final int durationMs = _videoDuration.inMilliseconds;
    if (positionMs < 0) {
      return 0;
    }
    if (durationMs > 0 && positionMs > durationMs) {
      return durationMs;
    }
    return positionMs;
  }

  int _estimatedPlaybackPositionMs([VideoPlayerValue? value]) {
    final VideoPlayerController? controller = _videoController;
    final VideoPlayerValue? videoValue = value ?? controller?.value;
    if (videoValue == null || !videoValue.isInitialized) {
      return 0;
    }

    if (videoValue.isPlaying && _playbackClock.isRunning) {
      return _clampPositionMs(
        _playbackClockBaseMs + _playbackClock.elapsedMilliseconds,
      );
    }

    if (!videoValue.isPlaying && !_playbackClock.isRunning) {
      return _playbackClockBaseMs;
    }

    return _clampPositionMs(videoValue.position.inMilliseconds);
  }

  void _startPlaybackClock(int anchorMs) {
    _syncPlaybackClock(anchorMs, running: true);
  }

  void _stopPlaybackClock({int? anchorMs}) {
    final int positionMs = anchorMs ?? _estimatedPlaybackPositionMs();
    _syncPlaybackClock(positionMs, running: false);
  }

  void _syncPlaybackClock(int anchorMs, {required bool running}) {
    _playbackClockBaseMs = _clampPositionMs(anchorMs);
    _playbackClock.reset();
    if (running) {
      _playbackClock.start();
    } else {
      _playbackClock.stop();
    }
  }

  void _recordTimingDelta(int deltaMs) {
    _timingDeltaCount += 1;
    _timingDeltaTotalMs += deltaMs;
    _timingDeltaLastMs = deltaMs;
    _timingDeltaMinMs = _timingDeltaMinMs == null
        ? deltaMs
        : math.min(_timingDeltaMinMs!, deltaMs);
    _timingDeltaMaxMs = _timingDeltaMaxMs == null
        ? deltaMs
        : math.max(_timingDeltaMaxMs!, deltaMs);
  }

  void _resetTimingStats() {
    _timingDeltaCount = 0;
    _timingDeltaTotalMs = 0;
    _timingDeltaMinMs = null;
    _timingDeltaMaxMs = null;
    _timingDeltaLastMs = null;
    _timingRunActive = false;
    _timingRunSummaryLogged = false;
  }

  bool _isPlaybackCompleted(int positionMs, VideoPlayerValue value) {
    final int durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) {
      return false;
    }
    final int reportedPositionMs = value.position.inMilliseconds;
    final int completionThresholdMs = math.max(0, durationMs - 120);
    return positionMs >= completionThresholdMs ||
        reportedPositionMs >= completionThresholdMs;
  }

  void _finishTimingRun(int positionMs) {
    if (!_timingRunActive || _timingRunSummaryLogged) {
      return;
    }
    _timingRunActive = false;
    _timingRunSummaryLogged = true;
    _sendLovenseMockStop('Run completed', positionMs);

    final String detail = _timingDeltaCount == 0
        ? 'No actions triggered | video ${formatMs(positionMs)}'
        : '$_timingDeltaCount actions | avg ${_formatAverageDelta()} | '
              'min ${_formatDelta(_timingDeltaMinMs)} | '
              'max ${_formatDelta(_timingDeltaMaxMs)} | '
              'last ${_formatDelta(_timingDeltaLastMs)} | '
              'video ${formatMs(positionMs)}';
    _appendLog(ExecutionLogEntry.success('Run completed', detail));
  }

  void _sendLovenseMockAction(
    FunscriptAction action,
    int positionMs,
    int deltaMs,
  ) {
    if (!_lovenseMockEnabled) {
      return;
    }

    final LovenseActionContext context = LovenseActionContext(
      index: action.index,
      atMs: action.atMs,
      pos: action.pos,
      currentMs: positionMs,
      deltaMs: deltaMs,
    );
    final List<LovenseMockEvaluationResult> results = _lovenseMockClient
        .evaluateAction(context);

    for (final LovenseMockEvaluationResult result in results) {
      final String deviceName = result.device?.name ?? 'No device';
      final LovenseMockCommand? command = result.command;
      if (command != null) {
        _appendLog(
          ExecutionLogEntry.info(
            'Lovense mock ${action.index}',
            '$deviceName | ${command.commandText} | '
                'pos ${action.pos} | delta $deltaMs ms',
          ),
          refresh: false,
        );
        continue;
      }
      _appendLog(
        ExecutionLogEntry.info(
          'Lovense eval ${action.index}',
          '$deviceName | ${result.message} | '
              'pos ${action.pos} | delta $deltaMs ms',
        ),
        refresh: false,
      );
    }
  }

  void _sendLovenseMockStop(String reason, int positionMs) {
    if (!_lovenseMockEnabled) {
      return;
    }

    final List<LovenseMockCommand> commands = _lovenseMockClient.stopAllDevices(
      LovenseActionContext(
        index: -1,
        atMs: positionMs,
        pos: 0,
        currentMs: positionMs,
        deltaMs: 0,
      ),
    );
    if (commands.isEmpty) {
      return;
    }
    for (final LovenseMockCommand command in commands) {
      _appendLog(
        ExecutionLogEntry.info(
          'Lovense mock stop',
          '${command.device.name} | ${command.commandText} | $reason',
        ),
        refresh: false,
      );
    }
  }

  bool get _arePlayerControlsLocked =>
      !_hasInitializedVideo || !(_videoController?.value.isPlaying ?? false);

  void _showPlayerControls({bool autoHide = true}) {
    _playerControlsHideTimer?.cancel();
    _playerControlsHideTimer = null;
    if (mounted && !_playerControlsVisible) {
      setState(() {
        _playerControlsVisible = true;
      });
    } else {
      _playerControlsVisible = true;
    }

    if (autoHide) {
      _schedulePlayerControlsAutoHide();
    }
  }

  void _schedulePlayerControlsAutoHide() {
    _playerControlsHideTimer?.cancel();
    if (_arePlayerControlsLocked) {
      return;
    }
    _playerControlsHideTimer = Timer(_playerControlsHideDelay, () {
      if (!mounted || _arePlayerControlsLocked) {
        return;
      }
      setState(() {
        _playerControlsVisible = false;
      });
    });
  }

  void _hidePlayerControls() {
    _playerControlsHideTimer?.cancel();
    _playerControlsHideTimer = null;
    if (_arePlayerControlsLocked || !_playerControlsVisible || !mounted) {
      return;
    }
    setState(() {
      _playerControlsVisible = false;
    });
  }

  Future<void> _toggleFullscreenPlayer() async {
    if (!_hasInitializedVideo) {
      return;
    }
    final bool fullscreen = !_fullscreenPlayerVisible;
    if (supportsDesktopWindowManager) {
      try {
        await windowManager.setFullScreen(fullscreen);
      } catch (error) {
        _appendLog(
          ExecutionLogEntry.error('Fullscreen failed', error.toString()),
        );
        return;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _fullscreenPlayerVisible = fullscreen;
      _playerControlsVisible = true;
    });
    if (fullscreen) {
      _schedulePlayerControlsAutoHide();
    } else {
      _showPlayerControls(autoHide: true);
    }
  }

  Future<void> _togglePlayerMute() async {
    if (!_hasInitializedVideo) {
      return;
    }

    final double targetVolume = _playerVolume <= 0
        ? (_lastAudiblePlayerVolume <= 0 ? 1.0 : _lastAudiblePlayerVolume)
        : 0.0;
    await _setPlayerVolume(targetVolume);
    _showPlayerControls(autoHide: true);
  }

  Future<void> _setPlayerVolume(double volume) async {
    final double safeVolume = volume.clamp(0.0, 1.0).toDouble();
    final VideoPlayerController? controller = _videoController;
    setState(() {
      _playerVolume = safeVolume;
      if (safeVolume > 0) {
        _lastAudiblePlayerVolume = safeVolume;
      }
    });
    if (controller != null && controller.value.isInitialized) {
      await controller.setVolume(safeVolume);
    }
  }

  IconData get _playerVolumeIcon {
    if (_playerVolume <= 0) {
      return Icons.volume_off;
    }
    if (_playerVolume < 0.5) {
      return Icons.volume_down;
    }
    return Icons.volume_up;
  }

  void _clearLog() {
    setState(() {
      _logEntries
        ..clear()
        ..add(ExecutionLogEntry.info('Log cleared', ''));
      _resetTimingStats();
    });
  }

  void _clearLovenseMock() {
    setState(() {
      _lovenseMockClient.clear();
    });
  }

  void _updateLovenseMockRules(String rulesText) {
    setState(() {
      _lovenseMockClient.updateRules(rulesText);
    });
  }

  void _resetLovenseMockRules() {
    _lovenseRulesController.text = LovenseMockRuleScript.defaultSource;
    _updateLovenseMockRules(_lovenseRulesController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _fullscreenPlayerVisible
          ? null
          : AppBar(
              title: const Text('FHPlayer'),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      _funscript == null
                          ? 'Timing idle'
                          : '${_funscript!.actions.length} actions loaded',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
              ],
            ),
      body: _fullscreenPlayerVisible
          ? _buildFullscreenPlayer()
          : SafeArea(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= _wideLayoutMinWidth;
                  final double? maxPlayerHeight = wide
                      ? _scaledHeight(
                          constraints,
                          factor: _widePlayerHeightFactor,
                          minimum: _widePlayerMinHeight,
                          maximum: _widePlayerMaxHeight,
                        )
                      : null;
                  final double listPanelHeight = wide
                      ? _scaledHeight(
                          constraints,
                          factor: _wideListHeightFactor,
                          minimum: _wideListMinHeight,
                          maximum: _wideListMaxHeight,
                        )
                      : _defaultListPanelHeight;
                  final Widget mediaColumn = _buildMediaColumn(
                    maxPlayerHeight: maxPlayerHeight,
                    listPanelHeight: listPanelHeight,
                  );
                  final Widget sideColumn = _buildSideColumn();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(child: mediaColumn),
                              const SizedBox(width: 16),
                              SizedBox(width: 380, child: sideColumn),
                            ],
                          )
                        : Column(
                            children: <Widget>[
                              sideColumn,
                              const SizedBox(height: 16),
                              mediaColumn,
                            ],
                          ),
                  );
                },
              ),
            ),
    );
  }

  double _scaledHeight(
    BoxConstraints constraints, {
    required double factor,
    required double minimum,
    required double maximum,
  }) {
    return (constraints.maxHeight * factor).clamp(minimum, maximum).toDouble();
  }

  Widget _buildMediaColumn({
    required double listPanelHeight,
    double? maxPlayerHeight,
  }) {
    return Column(
      children: <Widget>[
        _buildPlayerPanel(maxPlayerHeight: maxPlayerHeight),
        const SizedBox(height: 16),
        _buildTimelinePanel(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool split = constraints.maxWidth >= _splitPanelsMinWidth;
            if (!split) {
              return Column(
                children: <Widget>[
                  _buildActionTablePanel(height: listPanelHeight),
                  const SizedBox(height: 16),
                  _buildLogPanel(height: listPanelHeight),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _buildActionTablePanel(height: listPanelHeight),
                ),
                const SizedBox(width: 16),
                Expanded(child: _buildLogPanel(height: listPanelHeight)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSideColumn() {
    return Column(
      children: <Widget>[
        _buildFilePanel(),
        const SizedBox(height: 16),
        _buildTimingStatePanel(),
        const SizedBox(height: 16),
        _buildTimingStatsPanel(),
        const SizedBox(height: 16),
        _buildLovenseMockPanel(),
      ],
    );
  }

  Widget _buildFilePanel() {
    return Panel(
      title: 'Playlist entry',
      subtitle: 'Single video and funscript pair',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _videoInitializing ? null : _pickVideo,
                  icon: const Icon(Icons.video_file_outlined),
                  label: const Text('Select video'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _pickFunscript,
                  icon: const Icon(Icons.data_object_outlined),
                  label: const Text('Select funscript'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FileSummaryRow(
            label: 'Video',
            value: _videoName.isEmpty ? 'No video selected' : _videoName,
            detail: _videoPath,
          ),
          const Divider(height: 24),
          FileSummaryRow(
            label: 'Funscript',
            value: _funscriptName.isEmpty
                ? 'No funscript selected'
                : _funscriptName,
            detail: _funscriptPath,
          ),
        ],
      ),
    );
  }

  Widget _buildTimingStatePanel() {
    final VideoPlayerValue? value = _videoController?.value;
    return Panel(
      title: 'Timing state',
      subtitle: _hasInitializedVideo ? 'Player initialized' : 'Waiting',
      child: Column(
        children: <Widget>[
          StateRow(
            label: 'Initialized',
            value: _hasInitializedVideo ? 'yes' : 'no',
          ),
          StateRow(
            label: 'Initializing',
            value: _videoInitializing ? 'yes' : 'no',
          ),
          StateRow(
            label: 'Playing',
            value: value?.isPlaying == true ? 'yes' : 'no',
          ),
          StateRow(
            label: 'Buffering',
            value: value?.isBuffering == true ? 'yes' : 'no',
          ),
          StateRow(
            label: 'Duration',
            value: _hasInitializedVideo ? formatDuration(_videoDuration) : '-',
          ),
          StateRow(
            label: 'Cursor',
            value: _funscript == null
                ? '-'
                : 'next action ${_funscriptCursor.nextActionIndex}',
          ),
          if (_videoError.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            StatusNote.error(_videoError),
          ],
        ],
      ),
    );
  }

  Widget _buildTimingStatsPanel() {
    return Panel(
      title: 'Timing stats',
      subtitle: _timingDeltaCount == 0
          ? 'Waiting for actions'
          : 'Current playback run',
      child: Column(
        children: <Widget>[
          StateRow(label: 'Actions logged', value: '$_timingDeltaCount'),
          StateRow(
            label: 'Last delta',
            value: _formatDelta(_timingDeltaLastMs),
          ),
          StateRow(label: 'Average', value: _formatAverageDelta()),
          StateRow(
            label: 'Min / max',
            value: _timingDeltaCount == 0
                ? '-'
                : '${_formatDelta(_timingDeltaMinMs)} / '
                      '${_formatDelta(_timingDeltaMaxMs)}',
          ),
        ],
      ),
    );
  }

  Widget _buildLovenseMockPanel() {
    final LovenseMockCommand? lastCommand = _lovenseMockClient.lastCommand;
    final String? ruleError = _lovenseMockClient.ruleError;
    final List<LovenseMockDevice> devices = _lovenseMockClient.devices;
    return Panel(
      title: 'Lovense mock',
      subtitle: 'Simulation only',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _lovenseMockEnabled,
            title: const Text('Mock output'),
            subtitle: Text(
              _lovenseMockEnabled
                  ? 'Commands are logged but not sent.'
                  : 'Mock output disabled.',
            ),
            onChanged: (bool value) {
              setState(() {
                _lovenseMockEnabled = value;
              });
            },
          ),
          const Divider(height: 24),
          TextField(
            controller: _lovenseRulesController,
            maxLines: 3,
            minLines: 3,
            style: const TextStyle(fontFamily: 'Consolas'),
            decoration: InputDecoration(
              labelText: 'Rule text',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Reset rules',
                onPressed: _resetLovenseMockRules,
                icon: const Icon(Icons.restart_alt),
              ),
            ),
            onChanged: _updateLovenseMockRules,
          ),
          const SizedBox(height: 10),
          ruleError == null
              ? const StatusNote.info('Rule script valid.')
              : StatusNote.error(ruleError),
          const SizedBox(height: 10),
          StateRow(label: 'Devices', value: '${devices.length}'),
          StateRow(
            label: 'Commands',
            value: '${_lovenseMockClient.history.length}',
          ),
          StateRow(
            label: 'Last command',
            value: lastCommand == null
                ? '-'
                : '${lastCommand.device.name}: ${lastCommand.commandText}',
          ),
          const SizedBox(height: 10),
          Text(
            'Simulated devices',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (devices.isEmpty)
            const StatusNote.error('No simulated devices configured.')
          else
            ...<Widget>[
              for (final LovenseMockDevice device in devices) ...<Widget>[
                SimulatedDeviceTile(device: device),
                const SizedBox(height: 8),
              ],
            ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _lovenseMockEnabled
                      ? () {
                          _sendLovenseMockStop(
                            'Manual mock stop',
                            _displayPositionMs,
                          );
                          if (mounted) {
                            setState(() {});
                          }
                        }
                      : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop mock'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: _clearLovenseMock,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: _lovenseMockClient.history.isEmpty
                ? const EmptyPanelMessage('No mock commands yet.')
                : ListView.separated(
                    itemCount: math.min(_lovenseMockClient.history.length, 8),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      return MockCommandTile(
                        command: _lovenseMockClient.history[index],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerPanel({double? maxPlayerHeight}) {
    final bool canPlay = _hasInitializedVideo && !_videoInitializing;
    final bool isPlaying = _videoController?.value.isPlaying ?? false;
    final double aspectRatio = _hasInitializedVideo
        ? _videoController!.value.aspectRatio
        : 16 / 9;
    final int displayPositionMs = _displayPositionMs;
    final double sliderMax = _videoDuration.inMilliseconds <= 0
        ? 1
        : _videoDuration.inMilliseconds.toDouble();
    final double sliderValue = displayPositionMs
        .clamp(0, sliderMax.toInt())
        .toDouble();

    return Panel(
      title: _videoName.isEmpty ? 'No video loaded' : _videoName,
      subtitle: 'Player',
      child: Column(
        children: <Widget>[
          _buildVideoSurface(
            aspectRatio: aspectRatio,
            maxHeight: maxPlayerHeight,
            canPlay: canPlay,
            isPlaying: isPlaying,
            displayPositionMs: displayPositionMs,
            sliderMax: sliderMax,
            sliderValue: sliderValue,
          ),
        ],
      ),
    );
  }

  Widget _buildFullscreenPlayer() {
    final bool canPlay = _hasInitializedVideo && !_videoInitializing;
    final bool isPlaying = _videoController?.value.isPlaying ?? false;
    final double aspectRatio = _hasInitializedVideo
        ? _videoController!.value.aspectRatio
        : 16 / 9;
    final int displayPositionMs = _displayPositionMs;
    final double sliderMax = _videoDuration.inMilliseconds <= 0
        ? 1
        : _videoDuration.inMilliseconds.toDouble();
    final double sliderValue = displayPositionMs
        .clamp(0, sliderMax.toInt())
        .toDouble();

    return ColoredBox(
      color: AppColors.playerBackground,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size playerSize = _containedSize(
              constraints: constraints,
              aspectRatio: aspectRatio,
            );
            return Center(
              child: SizedBox(
                width: playerSize.width,
                height: playerSize.height,
                child: _buildPlayerShell(
                  canPlay: canPlay,
                  isPlaying: isPlaying,
                  displayPositionMs: displayPositionMs,
                  sliderMax: sliderMax,
                  sliderValue: sliderValue,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoSurface({
    required double aspectRatio,
    required double? maxHeight,
    required bool canPlay,
    required bool isPlaying,
    required int displayPositionMs,
    required double sliderMax,
    required double sliderValue,
  }) {
    final Widget player = _buildPlayerShell(
      canPlay: canPlay,
      isPlaying: isPlaying,
      displayPositionMs: displayPositionMs,
      sliderMax: sliderMax,
      sliderValue: sliderValue,
    );
    final Widget clippedPlayer = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: player,
    );

    if (maxHeight == null) {
      return AspectRatio(aspectRatio: aspectRatio, child: clippedPlayer);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = math.min(
          constraints.maxWidth,
          maxHeight * aspectRatio,
        );
        final double height = width / aspectRatio;
        return SizedBox(
          width: double.infinity,
          height: height,
          child: Center(
            child: SizedBox(width: width, height: height, child: clippedPlayer),
          ),
        );
      },
    );
  }

  Size _containedSize({
    required BoxConstraints constraints,
    required double aspectRatio,
  }) {
    final double availableWidth = constraints.maxWidth;
    final double availableHeight = constraints.maxHeight;
    if (availableWidth <= 0 || availableHeight <= 0) {
      return Size.zero;
    }
    final double widthFromHeight = availableHeight * aspectRatio;
    if (widthFromHeight <= availableWidth) {
      return Size(widthFromHeight, availableHeight);
    }
    return Size(availableWidth, availableWidth / aspectRatio);
  }

  Widget _buildPlayerShell({
    required bool canPlay,
    required bool isPlaying,
    required int displayPositionMs,
    required double sliderMax,
    required double sliderValue,
  }) {
    final bool controlsVisible =
        _playerControlsVisible || !isPlaying || !canPlay;

    return ColoredBox(
      color: AppColors.playerBackground,
      child: MouseRegion(
        onHover: (_) => _showPlayerControls(autoHide: true),
        onExit: (_) => _hidePlayerControls(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_hasInitializedVideo)
              VideoPlayer(_videoController!)
            else
              const PlayerPlaceholder(),
            if (_videoInitializing)
              const Center(child: CircularProgressIndicator()),
            AnimatedOpacity(
              opacity: controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: !controlsVisible,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _buildOverlayIconButton(
                            tooltip: 'Back 10 seconds',
                            icon: Icons.replay_10,
                            size: 56,
                            onPressed: canPlay
                                ? () {
                                    _showPlayerControls(autoHide: true);
                                    _seekBy(const Duration(seconds: -10));
                                  }
                                : null,
                          ),
                          const SizedBox(width: 14),
                          _buildOverlayIconButton(
                            tooltip: isPlaying ? 'Pause' : 'Play',
                            icon: isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 68,
                            accent: true,
                            onPressed: canPlay ? _togglePlayback : null,
                          ),
                          const SizedBox(width: 14),
                          _buildOverlayIconButton(
                            tooltip: 'Forward 10 seconds',
                            icon: Icons.forward_10,
                            size: 56,
                            onPressed: canPlay
                                ? () {
                                    _showPlayerControls(autoHide: true);
                                    _seekBy(const Duration(seconds: 10));
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildPlayerProgressOverlay(
                        canPlay: canPlay,
                        displayPositionMs: displayPositionMs,
                        sliderMax: sliderMax,
                        sliderValue: sliderValue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayIconButton({
    required String tooltip,
    required IconData icon,
    required double size,
    required VoidCallback? onPressed,
    bool accent = false,
  }) {
    final Color background = accent
        ? AppColors.accent
        : const Color(0xA0150D09);
    final Color pressedBackground = accent
        ? AppColors.accentStrong
        : const Color(0xCC150D09);

    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        iconSize: accent ? 34 : 28,
        backgroundColor: background,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0x66150D09),
        disabledForegroundColor: const Color(0x66FFFFFF),
        hoverColor: pressedBackground,
      ),
    );
  }

  Widget _buildPlayerProgressOverlay({
    required bool canPlay,
    required int displayPositionMs,
    required double sliderMax,
    required double sliderValue,
  }) {
    const TextStyle timeStyle = TextStyle(
      color: Color(0xDDFFF8EF),
      fontFamily: 'Consolas',
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[Color(0xF5150D09), Color(0x00150D09)],
        ),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 560;
          final double timeWidth = compact ? 74 : 88;
          return Row(
            children: <Widget>[
              SizedBox(
                width: timeWidth,
                child: Text(formatMs(displayPositionMs), style: timeStyle),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: const Color(0x66FFF8EF),
                    thumbColor: AppColors.accent,
                    overlayColor: AppColors.accentSoft.withValues(alpha: 0.20),
                  ),
                  child: Slider(
                    min: 0,
                    max: sliderMax,
                    value: sliderValue,
                    onChanged: canPlay
                        ? (double value) {
                            _showPlayerControls(autoHide: false);
                            setState(() {
                              _previewSeekMs = value.round();
                              _pendingSeekSync = true;
                              _syncActionCursor(
                                _previewSeekMs!,
                                includeCurrentAction: true,
                              );
                            });
                          }
                        : null,
                    onChangeEnd: canPlay
                        ? (double value) {
                            _showPlayerControls(autoHide: true);
                            _seekTo(Duration(milliseconds: value.round()));
                          }
                        : null,
                  ),
                ),
              ),
              SizedBox(
                width: timeWidth,
                child: Text(
                  formatDuration(_videoDuration),
                  textAlign: TextAlign.right,
                  style: timeStyle,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _playerVolume <= 0 ? 'Unmute' : 'Mute',
                onPressed: _hasInitializedVideo ? _togglePlayerMute : null,
                icon: Icon(_playerVolumeIcon),
                color: const Color(0xDDFFF8EF),
                disabledColor: const Color(0x66FFF8EF),
              ),
              if (!compact) ...<Widget>[
                SizedBox(
                  width: 92,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: const Color(0x66FFF8EF),
                      thumbColor: AppColors.accent,
                      overlayColor: AppColors.accentSoft.withValues(
                        alpha: 0.20,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _playerVolume,
                      onChanged: _hasInitializedVideo
                          ? (double value) {
                              _showPlayerControls(autoHide: false);
                              _setPlayerVolume(value);
                            }
                          : null,
                      onChangeEnd: _hasInitializedVideo
                          ? (_) => _showPlayerControls(autoHide: true)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: _fullscreenPlayerVisible
                    ? 'Exit fullscreen'
                    : 'Fullscreen',
                onPressed: _hasInitializedVideo
                    ? () => _toggleFullscreenPlayer()
                    : null,
                icon: Icon(
                  _fullscreenPlayerVisible
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                ),
                color: const Color(0xDDFFF8EF),
                disabledColor: const Color(0x66FFF8EF),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTimelinePanel() {
    return Row(
      children: <Widget>[
        Expanded(
          child: MetricTile(
            label: 'Current time',
            value: formatMs(_displayPositionMs),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            label: 'Current action',
            value: _formatAction(_currentAction),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            label: 'Next action',
            value: _formatAction(_nextAction),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            label: 'Last logged',
            value: _formatAction(_lastLoggedAction),
          ),
        ),
      ],
    );
  }

  Widget _buildActionTablePanel({required double height}) {
    final List<FunscriptAction> actions =
        _funscript?.actions ?? const <FunscriptAction>[];
    return Panel(
      title: 'Funscript overview',
      subtitle: actions.isEmpty
          ? 'No actions loaded'
          : '${actions.length} actions',
      child: SizedBox(
        height: height,
        child: actions.isEmpty
            ? const EmptyPanelMessage('No funscript loaded.')
            : ListView.separated(
                itemCount: actions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final FunscriptAction action = actions[index];
                  final bool active =
                      index == _funscriptCursor.currentActionIndex;
                  final bool next = index == _funscriptCursor.nextActionIndex;
                  return ActionRow(action: action, active: active, next: next);
                },
              ),
      ),
    );
  }

  Widget _buildLogPanel({required double height}) {
    return Panel(
      title: 'Execution log',
      subtitle: _logEntries.length == 1
          ? '1 event'
          : '${_logEntries.length} events',
      trailing: TextButton.icon(
        onPressed: _clearLog,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Clear'),
      ),
      child: SizedBox(
        height: height,
        child: ListView.separated(
          controller: _logScrollController,
          padding: const EdgeInsets.symmetric(vertical: 2),
          itemCount: _logEntries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int index) {
            return LogEntryTile(entry: _logEntries[index]);
          },
        ),
      ),
    );
  }

  String _formatAction(FunscriptAction? action) {
    if (action == null) {
      return '-';
    }
    return '#${action.index} @ ${formatMs(action.atMs)} | pos ${action.pos}';
  }

  String _formatDelta(int? deltaMs) {
    return deltaMs == null ? '-' : '$deltaMs ms';
  }

  String _formatAverageDelta() {
    if (_timingDeltaCount == 0) {
      return '-';
    }
    final double average = _timingDeltaTotalMs / _timingDeltaCount;
    return '${average.toStringAsFixed(1)} ms';
  }
}

class Funscript {
  Funscript({required this.actions, required this.sourceName});

  final List<FunscriptAction> actions;
  final String sourceName;

  factory Funscript.fromJson(
    Map<String, dynamic> json, {
    required String sourceName,
  }) {
    final Object? actionsJson = json['actions'];
    if (actionsJson is! List) {
      throw const FormatException('Missing actions array.');
    }

    final List<FunscriptAction> parsed = <FunscriptAction>[];
    for (int rawIndex = 0; rawIndex < actionsJson.length; rawIndex += 1) {
      final Object? rawAction = actionsJson[rawIndex];
      if (rawAction is! Map<String, dynamic>) {
        continue;
      }
      final num? at = _readNumber(rawAction['at']);
      final num? pos = _readNumber(rawAction['pos']);
      if (at == null || pos == null) {
        continue;
      }
      parsed.add(
        FunscriptAction(
          originalIndex: rawIndex,
          index: parsed.length,
          atMs: at.round(),
          pos: pos.round(),
        ),
      );
    }

    parsed.sort((FunscriptAction left, FunscriptAction right) {
      final int atCompare = left.atMs.compareTo(right.atMs);
      if (atCompare != 0) {
        return atCompare;
      }
      return left.originalIndex.compareTo(right.originalIndex);
    });

    final List<FunscriptAction> indexed = <FunscriptAction>[
      for (int index = 0; index < parsed.length; index += 1)
        parsed[index].copyWith(index: index),
    ];

    return Funscript(actions: indexed, sourceName: sourceName);
  }

  int indexAfter(int timeMs) {
    int low = 0;
    int high = actions.length;
    while (low < high) {
      final int middle = low + ((high - low) >> 1);
      if (actions[middle].atMs <= timeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int indexAtOrAfter(int timeMs) {
    int low = 0;
    int high = actions.length;
    while (low < high) {
      final int middle = low + ((high - low) >> 1);
      if (actions[middle].atMs < timeMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int? indexAtOrBefore(int timeMs) {
    final int index = indexAfter(timeMs) - 1;
    if (index < 0) {
      return null;
    }
    return index;
  }

  static num? _readNumber(Object? value) {
    if (value is num && value.isFinite) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }
}

class FunscriptActionCursor {
  FunscriptActionCursor([Funscript? script]) : _script = script;

  Funscript? _script;
  int nextActionIndex = 0;
  int? currentActionIndex;
  int? lastTriggeredActionIndex;

  FunscriptAction? get currentAction => _actionAt(currentActionIndex);

  FunscriptAction? get nextAction => _actionAt(nextActionIndex);

  FunscriptAction? get lastTriggeredAction =>
      _actionAt(lastTriggeredActionIndex);

  void setScript(
    Funscript? script, {
    int positionMs = 0,
    bool includeCurrentAction = false,
  }) {
    _script = script;
    lastTriggeredActionIndex = null;
    sync(positionMs, includeCurrentAction: includeCurrentAction);
  }

  void sync(int positionMs, {bool includeCurrentAction = false}) {
    final Funscript? script = _script;
    if (script == null) {
      reset();
      return;
    }

    nextActionIndex = includeCurrentAction
        ? script.indexAtOrAfter(positionMs)
        : script.indexAfter(positionMs);
    currentActionIndex = script.indexAtOrBefore(positionMs);
  }

  void updateCurrentAction(int positionMs) {
    currentActionIndex = _script?.indexAtOrBefore(positionMs);
  }

  List<FunscriptAction> triggerDue(int positionMs) {
    final Funscript? script = _script;
    if (script == null) {
      reset();
      return const <FunscriptAction>[];
    }

    final List<FunscriptAction> dueActions = <FunscriptAction>[];
    while (nextActionIndex < script.actions.length &&
        script.actions[nextActionIndex].atMs <= positionMs) {
      final FunscriptAction action = script.actions[nextActionIndex];
      currentActionIndex = nextActionIndex;
      lastTriggeredActionIndex = nextActionIndex;
      nextActionIndex += 1;
      dueActions.add(action);
    }

    currentActionIndex = script.indexAtOrBefore(positionMs);
    return dueActions;
  }

  void resetLastTriggered() {
    lastTriggeredActionIndex = null;
  }

  void reset() {
    nextActionIndex = 0;
    currentActionIndex = null;
    lastTriggeredActionIndex = null;
  }

  FunscriptAction? _actionAt(int? index) {
    final Funscript? script = _script;
    if (script == null || index == null) {
      return null;
    }
    if (index < 0 || index >= script.actions.length) {
      return null;
    }
    return script.actions[index];
  }
}

class FunscriptAction {
  const FunscriptAction({
    required this.originalIndex,
    required this.index,
    required this.atMs,
    required this.pos,
  });

  final int originalIndex;
  final int index;
  final int atMs;
  final int pos;

  FunscriptAction copyWith({int? index}) {
    return FunscriptAction(
      originalIndex: originalIndex,
      index: index ?? this.index,
      atMs: atMs,
      pos: pos,
    );
  }
}

enum LogKind { info, success, action, error }

class ExecutionLogEntry {
  ExecutionLogEntry({
    required this.kind,
    required this.title,
    required this.detail,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ExecutionLogEntry.info(String title, String detail) {
    return ExecutionLogEntry(kind: LogKind.info, title: title, detail: detail);
  }

  factory ExecutionLogEntry.success(String title, String detail) {
    return ExecutionLogEntry(
      kind: LogKind.success,
      title: title,
      detail: detail,
    );
  }

  factory ExecutionLogEntry.action(String title, String detail) {
    return ExecutionLogEntry(
      kind: LogKind.action,
      title: title,
      detail: detail,
    );
  }

  factory ExecutionLogEntry.error(String title, String detail) {
    return ExecutionLogEntry(kind: LogKind.error, title: title, detail: detail);
  }

  final LogKind kind;
  final String title;
  final String detail;
  final DateTime createdAt;
}

class Panel extends StatelessWidget {
  const Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class PlayerPlaceholder extends StatelessWidget {
  const PlayerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.play_circle_outline,
        color: Color(0x88FFFFFF),
        size: 72,
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class FileSummaryRow extends StatelessWidget {
  const FileSummaryRow({
    required this.label,
    required this.value,
    required this.detail,
    super.key,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (detail.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ],
    );
  }
}

class StateRow extends StatelessWidget {
  const StateRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusNote extends StatelessWidget {
  const StatusNote.info(this.text, {super.key}) : isError = false;

  const StatusNote.error(this.text, {super.key}) : isError = true;

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorSoft : AppColors.infoSoft,
        border: Border.all(
          color: isError ? AppColors.errorBorder : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }
}

class ActionRow extends StatelessWidget {
  const ActionRow({
    required this.action,
    required this.active,
    required this.next,
    super.key,
  });

  final FunscriptAction action;
  final bool active;
  final bool next;

  @override
  Widget build(BuildContext context) {
    final Color background = active
        ? AppColors.accentSoft
        : next
        ? AppColors.infoSoft
        : Colors.transparent;
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 54,
            child: Text(
              '#${action.index}',
              style: const TextStyle(
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              formatMs(action.atMs),
              style: const TextStyle(
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              'pos ${action.pos}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LogEntryTile extends StatelessWidget {
  const LogEntryTile({required this.entry, super.key});

  final ExecutionLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = switch (entry.kind) {
      LogKind.success => AppColors.successBorder,
      LogKind.action => AppColors.accent,
      LogKind.error => AppColors.errorBorder,
      LogKind.info => AppColors.border,
    };
    final Color background = switch (entry.kind) {
      LogKind.success => AppColors.successSoft,
      LogKind.action => AppColors.accentSoft,
      LogKind.error => AppColors.errorSoft,
      LogKind.info => AppColors.panelStrong,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatClock(entry.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.muted,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          if (entry.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              entry.detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.text,
                fontFamily: 'Consolas',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MockCommandTile extends StatelessWidget {
  const MockCommandTile({required this.command, super.key});

  final LovenseMockCommand command;

  @override
  Widget build(BuildContext context) {
    final LovenseActionContext actionContext = command.context;
    final String actionLabel = actionContext.index < 0
        ? 'manual'
        : 'action #${actionContext.index}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panelStrong,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${command.device.name} | ${command.commandText}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatClock(command.createdAt),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$actionLabel | pos ${actionContext.pos} | '
            'video ${formatMs(actionContext.currentMs)} | '
            'delta ${actionContext.deltaMs} ms',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }
}

class SimulatedDeviceTile extends StatelessWidget {
  const SimulatedDeviceTile({required this.device, super.key});

  final LovenseMockDevice device;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panelStrong,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'id ${device.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDeviceCapabilities(device),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyPanelMessage extends StatelessWidget {
  const EmptyPanelMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
      ),
    );
  }
}

String formatDuration(Duration duration) {
  return formatMs(duration.inMilliseconds);
}

String formatMs(num value) {
  if (!value.isFinite) {
    return '-';
  }
  final int roundedMs = value.round();
  final int safeMs = roundedMs < 0 ? 0 : roundedMs;
  final int minutes = safeMs ~/ 60000;
  final int seconds = (safeMs % 60000) ~/ 1000;
  final int milliseconds = safeMs % 1000;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${milliseconds.toString().padLeft(3, '0')}';
}

String formatClock(DateTime dateTime) {
  return '${dateTime.hour.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')}:'
      '${dateTime.second.toString().padLeft(2, '0')}';
}

String _formatDeviceCapabilities(LovenseMockDevice device) {
  if (device.capabilities.isEmpty) {
    return 'caps: -';
  }
  final List<String> ordered = device.capabilities.toList()..sort();
  return 'caps: ${ordered.join(', ')}';
}

class AppColors {
  static const Color background = Color(0xFFF3F5F4);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color panelStrong = Color(0xFFF8FAFA);
  static const Color border = Color(0xFFD7DEDA);
  static const Color text = Color(0xFF1F2A27);
  static const Color muted = Color(0xFF65726D);
  static const Color accent = Color(0xFFB85B2E);
  static const Color accentStrong = Color(0xFF9A431C);
  static const Color accentSoft = Color(0xFFFFEFE7);
  static const Color infoSoft = Color(0xFFEAF3F5);
  static const Color successSoft = Color(0xFFE9F7EE);
  static const Color successBorder = Color(0xFF54A36D);
  static const Color errorSoft = Color(0xFFFFECEC);
  static const Color errorBorder = Color(0xFFD35B5B);
  static const Color playerBackground = Color(0xFF120D0A);
}
