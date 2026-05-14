import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fhplayer_flutter/lovense_live.dart';
import 'package:fhplayer_flutter/lovense_mock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

enum PlaylistMode { sequential, random }

enum LovenseExecutionMode { live, test }

const String kDefaultReleasePageUrl =
    'https://github.com/Honaro19/FHPlayer/releases';
const String kDefaultUpdateFeedUrl =
    'https://api.github.com/repos/Honaro19/FHPlayer/releases/latest';
const String kUpdateManualDisclosure =
    'During the update check, release metadata is retrieved from GitHub to determine whether a new version is available. No update is downloaded automatically. If an update is found, you can choose to open the release location manually and download it yourself.';
const String kAutoUpdateDisclosure =
    'When enabled, the application will automatically check for updates by retrieving release metadata from GitHub. No updates are downloaded automatically.';
const String kReleaseDisclosure =
    'You are about to open an external GitHub release page where releases are stored.';
const String kUpdateStatusDisclosure =
    'Checks for updates via GitHub Releases.';
const int kPlaylistSchemaVersion = 1;
const String kPlaylistType = 'fhplayer-playlist';
const List<({String action, String range, Set<String> requiredCapabilities})>
kLovenseActionRangeCatalog =
    <({String action, String range, Set<String> requiredCapabilities})>[
      (action: 'stop', range: 'stop()', requiredCapabilities: <String>{}),
      (
        action: 'vibrate',
        range: 'vibrate(0-20[, durationMs])',
        requiredCapabilities: <String>{'vibrate'},
      ),
      (
        action: 'rotate',
        range: 'rotate(0-20[, durationMs])',
        requiredCapabilities: <String>{'rotate'},
      ),
      (
        action: 'pump',
        range: 'pump(0-3[, durationMs])',
        requiredCapabilities: <String>{'pump'},
      ),
      (
        action: 'thrusting',
        range: 'thrusting(0-20[, durationMs])',
        requiredCapabilities: <String>{'thrusting'},
      ),
      (
        action: 'fingering',
        range: 'fingering(0-20[, durationMs])',
        requiredCapabilities: <String>{'fingering'},
      ),
      (
        action: 'suction',
        range: 'suction(0-20[, durationMs])',
        requiredCapabilities: <String>{'suction'},
      ),
      (
        action: 'depth',
        range: 'depth(0-3[, durationMs])',
        requiredCapabilities: <String>{'depth'},
      ),
      (
        action: 'stroke',
        range: 'stroke(0-100[, durationMs])',
        requiredCapabilities: <String>{'stroke'},
      ),
      (
        action: 'oscillate',
        range: 'oscillate(0-20[, durationMs])',
        requiredCapabilities: <String>{'oscillate'},
      ),
      (
        action: 'setlevel',
        range: 'setlevel(1-3, 0-20[, durationMs])',
        requiredCapabilities: <String>{'setlevel'},
      ),
    ];

class PlaylistMediaReference {
  const PlaylistMediaReference({
    required this.kind,
    required this.source,
    required this.name,
    this.libraryName = '',
    this.path = '',
    this.uri = '',
    this.token = '',
  });

  final String kind;
  final String source;
  final String name;
  final String libraryName;
  final String path;
  final String uri;
  final String token;

  String get resolvedLibraryName {
    final String explicitLibraryName = libraryName.trim();
    if (explicitLibraryName.isNotEmpty) {
      return explicitLibraryName;
    }
    return name.trim();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': name,
      'source': source,
    };
    if (path.trim().isNotEmpty) {
      payload['path'] = path.trim();
    }
    if (uri.trim().isNotEmpty) {
      payload['uri'] = uri.trim();
    }
    if (token.trim().isNotEmpty) {
      payload['token'] = token.trim();
    }
    if (resolvedLibraryName.isNotEmpty && resolvedLibraryName != name) {
      payload['libraryName'] = resolvedLibraryName;
    }
    return payload;
  }

  PlaylistMediaReference copyWith({
    String? kind,
    String? source,
    String? name,
    String? libraryName,
    String? path,
    String? uri,
    String? token,
  }) {
    return PlaylistMediaReference(
      kind: kind ?? this.kind,
      source: source ?? this.source,
      name: name ?? this.name,
      libraryName: libraryName ?? this.libraryName,
      path: path ?? this.path,
      uri: uri ?? this.uri,
      token: token ?? this.token,
    );
  }

  factory PlaylistMediaReference.fromLegacy({
    required String kind,
    required String path,
    required String name,
  }) {
    final String normalizedName = name.trim().isEmpty
        ? _pathFileName(path)
        : name.trim();
    return PlaylistMediaReference(
      kind: _normalizePlaylistLibraryKind(kind),
      source: path.trim().isEmpty ? 'library' : 'path',
      name: normalizedName,
      libraryName: normalizedName,
      path: path.trim(),
    );
  }

  factory PlaylistMediaReference.fromJson(
    Map<String, dynamic> json, {
    required String kind,
    String fallbackName = '',
    String fallbackPath = '',
  }) {
    final String normalizedKind = _normalizePlaylistLibraryKind(kind);
    final String name = _firstNonEmptyString(<Object?>[
      json['name'],
      json['fileName'],
      fallbackName,
    ]);
    return PlaylistMediaReference(
      kind: normalizedKind,
      source: _firstNonEmptyString(<Object?>[
        json['source'],
        json['type'],
        'library',
      ]),
      name: name,
      libraryName: _firstNonEmptyString(<Object?>[
        json['libraryName'],
        json['libraryFileName'],
        name,
      ]),
      path: _firstNonEmptyString(<Object?>[
        json['path'],
        json['filePath'],
        fallbackPath,
      ]),
      uri: _firstNonEmptyString(<Object?>[json['uri'], json['documentUri']]),
      token: _firstNonEmptyString(<Object?>[json['token']]),
    );
  }
}

class PlaylistEntryData {
  const PlaylistEntryData({
    required this.videoPath,
    required this.videoName,
    required this.funscriptPath,
    required this.funscriptName,
    this.activeLovenseProfileIds = const <String>[],
    this.videoSource,
    this.funscriptSource,
    this.embeddedFunscriptDocument,
    this.executionMode = '',
    this.rulesText = '',
  });

  final String videoPath;
  final String videoName;
  final String funscriptPath;
  final String funscriptName;
  final List<String> activeLovenseProfileIds;
  final PlaylistMediaReference? videoSource;
  final PlaylistMediaReference? funscriptSource;
  final Map<String, dynamic>? embeddedFunscriptDocument;
  final String executionMode;
  final String rulesText;

  String get title => videoName.isEmpty ? 'Untitled entry' : videoName;

  PlaylistMediaReference get effectiveVideoSource {
    return videoSource ??
        PlaylistMediaReference.fromLegacy(
          kind: 'videos',
          path: videoPath,
          name: videoName,
        );
  }

  PlaylistMediaReference get effectiveFunscriptSource {
    return funscriptSource ??
        PlaylistMediaReference.fromLegacy(
          kind: 'funscripts',
          path: funscriptPath,
          name: funscriptName,
        );
  }

  PlaylistEntryData copyWith({
    String? videoPath,
    String? videoName,
    String? funscriptPath,
    String? funscriptName,
    List<String>? activeLovenseProfileIds,
    PlaylistMediaReference? videoSource,
    PlaylistMediaReference? funscriptSource,
    Map<String, dynamic>? embeddedFunscriptDocument,
    String? executionMode,
    String? rulesText,
    bool clearEmbeddedFunscriptDocument = false,
  }) {
    return PlaylistEntryData(
      videoPath: videoPath ?? this.videoPath,
      videoName: videoName ?? this.videoName,
      funscriptPath: funscriptPath ?? this.funscriptPath,
      funscriptName: funscriptName ?? this.funscriptName,
      activeLovenseProfileIds:
          activeLovenseProfileIds ?? this.activeLovenseProfileIds,
      videoSource: videoSource ?? this.videoSource,
      funscriptSource: funscriptSource ?? this.funscriptSource,
      embeddedFunscriptDocument: clearEmbeddedFunscriptDocument
          ? null
          : (embeddedFunscriptDocument ?? this.embeddedFunscriptDocument),
      executionMode: executionMode ?? this.executionMode,
      rulesText: rulesText ?? this.rulesText,
    );
  }

  Map<String, dynamic> toLegacyJson() {
    return <String, dynamic>{
      'videoPath': videoPath,
      'videoName': videoName,
      'funscriptPath': funscriptPath,
      'funscriptName': funscriptName,
      'activeLovenseProfileIds': activeLovenseProfileIds,
    };
  }

  factory PlaylistEntryData.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> video = json['video'] is Map
        ? Map<String, dynamic>.from(json['video'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> funscript = json['funscript'] is Map
        ? Map<String, dynamic>.from(json['funscript'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> execution = json['execution'] is Map
        ? Map<String, dynamic>.from(json['execution'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> executionLovense = execution['lovense'] is Map
        ? Map<String, dynamic>.from(execution['lovense'] as Map)
        : <String, dynamic>{};

    final String videoName = _firstNonEmptyString(<Object?>[
      video['name'],
      json['videoName'],
      json['fileName'],
      json['title'],
      _pathFileName((json['videoPath'] as String?) ?? ''),
    ]);
    final String funscriptName = _firstNonEmptyString(<Object?>[
      funscript['name'],
      json['funscriptName'],
      _pathFileName((json['funscriptPath'] as String?) ?? ''),
      'playlist-entry.funscript',
    ]);
    final List<String> activeIds = _readStringList(
      executionLovense['activeConnectionIds'] ??
          json['activeLovenseProfileIds'],
    );

    final Map<String, dynamic>? embeddedDocument = funscript['document'] is Map
        ? _cloneJsonMap(Map<String, dynamic>.from(funscript['document'] as Map))
        : (json['scriptDocument'] is Map
              ? _cloneJsonMap(
                  Map<String, dynamic>.from(json['scriptDocument'] as Map),
                )
              : null);
    return PlaylistEntryData(
      videoPath: _firstNonEmptyString(<Object?>[
        video['path'],
        json['videoPath'],
      ]),
      videoName: videoName,
      funscriptPath: _firstNonEmptyString(<Object?>[
        funscript['path'],
        json['funscriptPath'],
      ]),
      funscriptName: funscriptName,
      activeLovenseProfileIds: activeIds,
      videoSource: PlaylistMediaReference.fromJson(
        video,
        kind: 'videos',
        fallbackName: videoName,
        fallbackPath: _firstNonEmptyString(<Object?>[json['videoPath']]),
      ),
      funscriptSource: PlaylistMediaReference.fromJson(
        funscript,
        kind: 'funscripts',
        fallbackName: funscriptName,
        fallbackPath: _firstNonEmptyString(<Object?>[json['funscriptPath']]),
      ),
      embeddedFunscriptDocument: embeddedDocument,
      executionMode: _firstNonEmptyString(<Object?>[
        execution['mode'],
        json['executionMode'],
      ]),
      rulesText: _firstNonEmptyString(<Object?>[
        execution['rulesText'],
        json['rulesText'],
      ]),
    );
  }
}

class FhplayerScriptSettings {
  const FhplayerScriptSettings({
    this.executionMode,
    this.rulesText = '',
    this.selectedConnectionId = '',
    this.activeConnectionIds = const <String>[],
    this.rulesByConnectionId = const <String, String>{},
    this.connections = const <LovenseConnectionProfile>[],
  });

  final LovenseExecutionMode? executionMode;
  final String rulesText;
  final String selectedConnectionId;
  final List<String> activeConnectionIds;
  final Map<String, String> rulesByConnectionId;
  final List<LovenseConnectionProfile> connections;

  bool get hasSettings {
    return executionMode != null ||
        rulesText.trim().isNotEmpty ||
        selectedConnectionId.trim().isNotEmpty ||
        activeConnectionIds.isNotEmpty ||
        rulesByConnectionId.isNotEmpty ||
        connections.isNotEmpty;
  }
}

class ConfirmActionResult {
  const ConfirmActionResult({
    required this.confirmed,
    this.dontShowAgain = false,
  });

  final bool confirmed;
  final bool dontShowAgain;
}

class LovenseConnectionProfile {
  const LovenseConnectionProfile({
    required this.id,
    required this.label,
    required this.scheme,
    required this.host,
    required this.port,
    required this.platformName,
    required this.rulesText,
    this.detectedDevices = const <LovenseLiveDevice>[],
    this.selectedDeviceIds = const <String>{},
  });

  final String id;
  final String label;
  final String scheme;
  final String host;
  final String port;
  final String platformName;
  final String rulesText;
  final List<LovenseLiveDevice> detectedDevices;
  final Set<String> selectedDeviceIds;

  String get displayLabel => label.trim().isEmpty ? id : label.trim();

  LovenseLiveConnectionConfig? connectionConfigOrNull() {
    final String normalizedHost = host.trim();
    final String normalizedPlatform = platformName.trim();
    final int? normalizedPort = int.tryParse(port.trim());
    if (normalizedHost.isEmpty ||
        normalizedPort == null ||
        normalizedPort <= 0 ||
        normalizedPort > 65535) {
      return null;
    }
    return LovenseLiveConnectionConfig(
      scheme: scheme.trim().isEmpty ? 'https' : scheme.trim().toLowerCase(),
      host: normalizedHost,
      port: normalizedPort,
      platformName: normalizedPlatform.isEmpty
          ? 'FHPlayer'
          : normalizedPlatform,
      timeoutSeconds: 5,
    );
  }

  LovenseConnectionProfile copyWith({
    String? id,
    String? label,
    String? scheme,
    String? host,
    String? port,
    String? platformName,
    String? rulesText,
    List<LovenseLiveDevice>? detectedDevices,
    Set<String>? selectedDeviceIds,
  }) {
    return LovenseConnectionProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      scheme: scheme ?? this.scheme,
      host: host ?? this.host,
      port: port ?? this.port,
      platformName: platformName ?? this.platformName,
      rulesText: rulesText ?? this.rulesText,
      detectedDevices: detectedDevices ?? this.detectedDevices,
      selectedDeviceIds: selectedDeviceIds ?? this.selectedDeviceIds,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'scheme': scheme,
      'host': host,
      'port': port,
      'platformName': platformName,
      'rulesText': rulesText,
    };
  }

  factory LovenseConnectionProfile.fromJson(Map<String, dynamic> json) {
    final String? id = (json['id'] as String?)?.trim();
    return LovenseConnectionProfile(
      id: id == null || id.isEmpty ? 'user-1' : id,
      label: (json['label'] as String?)?.trim() ?? '',
      scheme: (json['scheme'] as String?)?.trim().toLowerCase() == 'http'
          ? 'http'
          : 'https',
      host: (json['host'] as String?)?.trim() ?? '127.0.0.1',
      port: (json['port'] as String?)?.trim() ?? '30010',
      platformName: (json['platformName'] as String?)?.trim() ?? 'FHPlayer',
      rulesText: (json['rulesText'] as String?)?.trim().isNotEmpty == true
          ? (json['rulesText'] as String).trim()
          : LovenseMockRuleScript.defaultSource,
    );
  }
}

String _pathFileName(String path) {
  final String normalized = path.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) {
    return '';
  }
  final List<String> segments = normalized.split('/');
  return segments.isEmpty ? normalized : segments.last;
}

bool _pathsEqual(String left, String right) {
  final String leftNormalized = left.replaceAll('\\', '/').trim();
  final String rightNormalized = right.replaceAll('\\', '/').trim();
  if (leftNormalized.isEmpty || rightNormalized.isEmpty) {
    return false;
  }
  if (Platform.isWindows) {
    return leftNormalized.toLowerCase() == rightNormalized.toLowerCase();
  }
  return leftNormalized == rightNormalized;
}

String _normalizePlaylistLibraryKind(String kind) {
  final String normalizedKind = kind.trim().toLowerCase();
  if (normalizedKind == 'video') {
    return 'videos';
  }
  if (normalizedKind == 'funscript') {
    return 'funscripts';
  }
  return normalizedKind;
}

String _firstNonEmptyString(Iterable<Object?> values) {
  for (final Object? value in values) {
    if (value == null) {
      continue;
    }
    final String text = value is String
        ? value.trim()
        : value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((Object? item) => item == null ? '' : item.toString().trim())
      .where((String item) => item.isNotEmpty)
      .toList();
}

Map<String, dynamic> _readJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry(key == null ? '' : key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _cloneJsonMap(Map<String, dynamic> source) {
  final Object? clone = jsonDecode(jsonEncode(source));
  if (clone is Map<String, dynamic>) {
    return clone;
  }
  return <String, dynamic>{};
}

String _stripFileExtension(String fileName) {
  final String trimmed = fileName.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final int dot = trimmed.lastIndexOf('.');
  if (dot <= 0) {
    return trimmed;
  }
  return trimmed.substring(0, dot);
}

List<int>? _parseVersionParts(String value) {
  final RegExp matchPattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');
  final RegExpMatch? match = matchPattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return <int>[
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

int _compareVersions(String left, String right) {
  final List<int>? leftParts = _parseVersionParts(left);
  final List<int>? rightParts = _parseVersionParts(right);
  if (leftParts == null || rightParts == null) {
    return left.trim().compareTo(right.trim());
  }
  for (int index = 0; index < 3; index += 1) {
    final int compare = leftParts[index].compareTo(rightParts[index]);
    if (compare != 0) {
      return compare;
    }
  }
  return 0;
}

class FHPlayerApp extends StatelessWidget {
  const FHPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ).copyWith(
          surface: AppColors.panelStrong,
          onSurface: AppColors.text,
          primary: AppColors.accent,
          onPrimary: Colors.white,
          secondaryContainer: AppColors.panelStrong,
          onSecondaryContainer: AppColors.text,
          outline: AppColors.border,
          error: AppColors.errorBorder,
          onError: Colors.white,
        );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FHPlayer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Segoe UI',
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: AppColors.text,
          displayColor: AppColors.text,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.panelStrong,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 44)),
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            textStyle: const WidgetStatePropertyAll<TextStyle>(
              TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll<Color>(
              AppColors.text,
            ),
            backgroundColor: const WidgetStatePropertyAll<Color>(
              AppColors.secondaryButton,
            ),
            minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 40)),
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
        checkboxTheme: CheckboxThemeData(
          side: const BorderSide(color: AppColors.muted, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.accent;
            }
            return null;
          }),
          trackColor: WidgetStateProperty.resolveWith<Color?>((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.accentSoft;
            }
            return null;
          }),
        ),
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
  final LovenseLiveClient _lovenseLiveClient = LovenseLiveClient();
  final LovenseLiveRuleEngine _lovenseLiveRuleEngine =
      const LovenseLiveRuleEngine();
  final Stopwatch _playbackClock = Stopwatch();
  final ScrollController _logScrollController = ScrollController();
  late final TextEditingController _lovenseRulesController;
  late final TextEditingController _lovenseLiveHostController;
  late final TextEditingController _lovenseLivePortController;
  late final TextEditingController _lovenseLivePlatformController;

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
  bool _lovenseLiveEnabled = false;
  bool _lovenseLiveDetecting = false;
  List<LovenseConnectionProfile> _lovenseProfiles = <LovenseConnectionProfile>[
    const LovenseConnectionProfile(
      id: 'user-1',
      label: 'User 1',
      scheme: 'https',
      host: '127.0.0.1',
      port: '30010',
      platformName: 'FHPlayer',
      rulesText: LovenseMockRuleScript.defaultSource,
    ),
  ];
  String _lovenseSelectedProfileId = 'user-1';
  Set<String> _lovenseFormActiveProfileIds = <String>{'user-1'};
  String _lovenseLiveStatus = 'Not connected.';
  List<LovenseLiveRuleIssue> _lovenseLiveRuleIssues = <LovenseLiveRuleIssue>[];
  final Set<Timer> _lovenseLiveDelayTimers = <Timer>{};
  final Map<String, Timer> _lovenseLiveAutoStopTimers = <String, Timer>{};
  bool _playerControlsVisible = true;
  bool _fullscreenPlayerVisible = false;
  double _playerVolume = 1.0;
  double _lastAudiblePlayerVolume = 1.0;
  PlaylistMode _playlistMode = PlaylistMode.sequential;
  final math.Random _playlistRandom = math.Random();
  final List<PlaylistEntryData> _playlistEntries = <PlaylistEntryData>[];
  int _selectedPlaylistIndex = -1;
  bool _showDiagnosticsPanel = true;
  bool _showFunscriptOverviewPanel = true;
  bool _showExecutionLogPanel = true;
  bool _showUpdatesPanel = true;
  bool _lovensePanelCollapsed = false;
  bool _lovenseRuleSyntaxExpanded = false;
  bool _updateAutoCheck = false;
  bool _updateChecking = false;
  String _appVersion = '0.0.0';
  String _updateStatus =
      'Checks for updates via GitHub Releases.\nPress "Check now" to fetch the latest version.';
  String _updateReleaseUrl = kDefaultReleasePageUrl;
  String _updateManualDisclosureAcknowledgedVersion = '';
  String _updateReleaseDisclosureSuppressedVersion = '';
  String _diagnosticsStatus = 'Loading diagnostics...';
  String _diagnosticsPathsText = 'Loading diagnostic paths...';
  String _diagnosticsRecentLogText = 'No log output yet.';
  String _libraryStatus = 'Checking managed FHPlayer folders...';
  String _libraryPlaylistFileName = '';

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

  FunscriptAction? get _nextAction => _funscriptCursor.nextAction;

  FunscriptAction? get _lastLoggedAction =>
      _funscriptCursor.lastTriggeredAction;

  String get _appDataPath {
    if (Platform.isWindows) {
      final String? localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.trim().isNotEmpty) {
        return '${localAppData.trim()}\\FHPlayer';
      }
    }
    final String home = Platform.environment['HOME'] ?? '.';
    return '$home/.fhplayer';
  }

  String get _libraryRootPath =>
      '$_appDataPath${Platform.pathSeparator}Library';
  String get _libraryVideosPath =>
      '$_libraryRootPath${Platform.pathSeparator}Videos';
  String get _libraryFunscriptsPath =>
      '$_libraryRootPath${Platform.pathSeparator}Funscripts';
  String get _libraryExportsPath =>
      '$_libraryRootPath${Platform.pathSeparator}Exports';
  String get _logsDirectoryPath => '$_appDataPath${Platform.pathSeparator}Logs';
  String get _appLogPath =>
      '$_logsDirectoryPath${Platform.pathSeparator}fhplayer.log';
  String get _settingsPath =>
      '$_appDataPath${Platform.pathSeparator}settings.json';

  bool get _hasLoadedEntry =>
      _videoPath.trim().isNotEmpty && _funscriptPath.trim().isNotEmpty;

  bool get _hasSelectedPlaylistEntry =>
      _selectedPlaylistIndex >= 0 &&
      _selectedPlaylistIndex < _playlistEntries.length;

  String get _playlistModeLabel =>
      _playlistMode == PlaylistMode.sequential ? 'Sequential' : 'Random';

  LovenseExecutionMode get _lovenseExecutionMode => _lovenseLiveEnabled
      ? LovenseExecutionMode.live
      : LovenseExecutionMode.test;

  int get _selectedLovenseProfileIndex {
    final int index = _lovenseProfiles.indexWhere(
      (LovenseConnectionProfile profile) =>
          profile.id == _lovenseSelectedProfileId,
    );
    return index < 0 ? 0 : index;
  }

  LovenseConnectionProfile get _selectedLovenseProfile {
    if (_lovenseProfiles.isEmpty) {
      return const LovenseConnectionProfile(
        id: 'user-1',
        label: 'User 1',
        scheme: 'https',
        host: '127.0.0.1',
        port: '30010',
        platformName: 'FHPlayer',
        rulesText: LovenseMockRuleScript.defaultSource,
      );
    }
    return _lovenseProfiles[_selectedLovenseProfileIndex];
  }

  List<String> _activeLovenseProfileIds() {
    final Set<String> availableIds = _lovenseProfiles
        .map((LovenseConnectionProfile profile) => profile.id)
        .toSet();
    final List<String> raw = _hasSelectedPlaylistEntry
        ? _playlistEntries[_selectedPlaylistIndex].activeLovenseProfileIds
        : _lovenseFormActiveProfileIds.toList();
    final List<String> filtered = raw
        .where((String id) => availableIds.contains(id))
        .toSet()
        .toList();
    if (filtered.isNotEmpty) {
      return filtered;
    }
    final String fallback = _selectedLovenseProfile.id;
    return fallback.isEmpty ? const <String>[] : <String>[fallback];
  }

  List<LovenseConnectionProfile> _activeLovenseProfiles() {
    final Set<String> activeIds = _activeLovenseProfileIds().toSet();
    return _lovenseProfiles
        .where(
          (LovenseConnectionProfile profile) => activeIds.contains(profile.id),
        )
        .toList();
  }

  List<LovenseLiveDevice> _selectedLovenseLiveDevicesForProfile(
    LovenseConnectionProfile profile,
  ) {
    return profile.detectedDevices
        .where(
          (LovenseLiveDevice device) =>
              profile.selectedDeviceIds.contains(device.id),
        )
        .toList();
  }

  String _rulesTextForProfile(LovenseConnectionProfile profile) {
    final String trimmed = profile.rulesText.trim();
    return trimmed.isEmpty ? LovenseMockRuleScript.defaultSource : trimmed;
  }

  void _syncControllersFromSelectedLovenseProfile() {
    final LovenseConnectionProfile profile = _selectedLovenseProfile;
    _lovenseLiveHostController.text = profile.host;
    _lovenseLivePortController.text = profile.port;
    _lovenseLivePlatformController.text = profile.platformName;
  }

  void _syncRulesControllerFromSelectedLovenseProfile() {
    final String text = _rulesTextForProfile(_selectedLovenseProfile);
    if (_lovenseRulesController.text == text) {
      return;
    }
    _lovenseRulesController.text = text;
    _lovenseMockClient.updateRules(text);
  }

  void _updateSelectedLovenseProfile(
    LovenseConnectionProfile Function(LovenseConnectionProfile current)
    transform, {
    bool persist = true,
  }) {
    final int index = _selectedLovenseProfileIndex;
    if (index < 0 || index >= _lovenseProfiles.length) {
      return;
    }
    final LovenseConnectionProfile current = _lovenseProfiles[index];
    final LovenseConnectionProfile updated = transform(current);
    setState(() {
      _lovenseProfiles[index] = updated;
    });
    _refreshLovenseLiveRuleValidation();
    if (persist) {
      unawaited(_saveLocalSettings());
    }
  }

  @override
  void initState() {
    super.initState();
    _lovenseRulesController = TextEditingController(
      text: _lovenseMockClient.rulesText,
    );
    _lovenseLiveHostController = TextEditingController();
    _lovenseLivePortController = TextEditingController();
    _lovenseLivePlatformController = TextEditingController();
    _syncControllersFromSelectedLovenseProfile();
    _syncRulesControllerFromSelectedLovenseProfile();
    _lovenseRulesController.addListener(_refreshLovenseLiveRuleValidation);
    unawaited(_initializeLocalEnvironment());
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
    _lovenseRulesController.removeListener(_refreshLovenseLiveRuleValidation);
    _lovenseRulesController.dispose();
    _lovenseLiveHostController.dispose();
    _lovenseLivePortController.dispose();
    _lovenseLivePlatformController.dispose();
    _clearScheduledLovenseLiveActions(cancelAutoStops: true);
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

  Future<void> _initializeLocalEnvironment() async {
    await _ensureManagedDirectories();
    await _loadAppVersion();
    await _loadLocalSettings();
    if (!mounted) {
      _updateStatus = _buildUpdateIdleStatusMessage();
    } else {
      setState(() {
        _updateStatus = _buildUpdateIdleStatusMessage();
      });
    }
    _refreshLovenseLiveRuleValidation();
    await _refreshDiagnosticsInfo();
    _refreshLibraryStatus();
    if (_updateAutoCheck) {
      await _checkForUpdates(manual: false);
    }
  }

  Future<void> _ensureManagedDirectories() async {
    for (final String path in <String>[
      _appDataPath,
      _libraryRootPath,
      _libraryVideosPath,
      _libraryFunscriptsPath,
      _libraryExportsPath,
      _logsDirectoryPath,
    ]) {
      await Directory(path).create(recursive: true);
    }
  }

  Future<void> _loadAppVersion() async {
    final List<String> candidatePaths = <String>[
      'VERSION',
      '..${Platform.pathSeparator}..${Platform.pathSeparator}VERSION',
    ];
    for (final String candidate in candidatePaths) {
      final File file = File(candidate);
      if (!await file.exists()) {
        continue;
      }
      final String raw = (await file.readAsString()).trim();
      if (_parseVersionParts(raw) != null) {
        if (!mounted) {
          _appVersion = raw.replaceFirst(RegExp(r'^v'), '');
          return;
        }
        setState(() {
          _appVersion = raw.replaceFirst(RegExp(r'^v'), '');
        });
        return;
      }
    }
  }

  Future<void> _loadLocalSettings() async {
    final File file = File(_settingsPath);
    if (!await file.exists()) {
      return;
    }
    try {
      final Map<String, dynamic> json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final Map<String, dynamic> updates =
          (json['updates'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> ui =
          (json['ui'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> lovense =
          (json['lovense'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> library =
          (json['library'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final String executionMode =
          (lovense['executionMode'] as String?)?.trim().toLowerCase() ?? '';
      final bool useLiveMode = executionMode == 'live';
      final Object? rawProfiles = lovense['profiles'];
      final List<LovenseConnectionProfile> parsedProfiles = rawProfiles is List
          ? <LovenseConnectionProfile>[
              for (final Object? item in rawProfiles)
                if (item is Map<String, dynamic>)
                  LovenseConnectionProfile.fromJson(item),
            ]
          : const <LovenseConnectionProfile>[];
      final List<LovenseConnectionProfile> profiles = parsedProfiles.isEmpty
          ? const <LovenseConnectionProfile>[
              LovenseConnectionProfile(
                id: 'user-1',
                label: 'User 1',
                scheme: 'https',
                host: '127.0.0.1',
                port: '30010',
                platformName: 'FHPlayer',
                rulesText: LovenseMockRuleScript.defaultSource,
              ),
            ]
          : parsedProfiles;
      final Set<String> profileIds = profiles
          .map((LovenseConnectionProfile profile) => profile.id)
          .toSet();
      final String savedSelectedId =
          (lovense['selectedProfileId'] as String?)?.trim() ?? '';
      final String selectedId = profileIds.contains(savedSelectedId)
          ? savedSelectedId
          : profiles.first.id;
      if (!mounted) {
        _updateAutoCheck = updates['autoCheckEnabled'] == true;
        _updateManualDisclosureAcknowledgedVersion = _firstNonEmptyString(
          <Object?>[updates['manualDisclosureAcknowledgedVersion']],
        );
        _updateReleaseDisclosureSuppressedVersion = _firstNonEmptyString(
          <Object?>[updates['releaseDisclosureSuppressedVersion']],
        );
        _showDiagnosticsPanel = ui['showDiagnostics'] != false;
        _showFunscriptOverviewPanel = ui['showFunscriptOverview'] != false;
        _showExecutionLogPanel = ui['showExecutionLog'] != false;
        _showUpdatesPanel = ui['showUpdates'] != false;
        _lovenseLiveEnabled = useLiveMode;
        _lovensePanelCollapsed = lovense['panelCollapsed'] == true;
        _lovenseProfiles = profiles;
        _lovenseSelectedProfileId = selectedId;
        _lovenseFormActiveProfileIds = <String>{selectedId};
        _libraryPlaylistFileName =
            (library['playlistFileName'] as String?)?.trim() ?? '';
        _updateStatus = _buildUpdateIdleStatusMessage();
        _syncControllersFromSelectedLovenseProfile();
        _syncRulesControllerFromSelectedLovenseProfile();
        return;
      }
      setState(() {
        _updateAutoCheck = updates['autoCheckEnabled'] == true;
        _updateManualDisclosureAcknowledgedVersion = _firstNonEmptyString(
          <Object?>[updates['manualDisclosureAcknowledgedVersion']],
        );
        _updateReleaseDisclosureSuppressedVersion = _firstNonEmptyString(
          <Object?>[updates['releaseDisclosureSuppressedVersion']],
        );
        _showDiagnosticsPanel = ui['showDiagnostics'] != false;
        _showFunscriptOverviewPanel = ui['showFunscriptOverview'] != false;
        _showExecutionLogPanel = ui['showExecutionLog'] != false;
        _showUpdatesPanel = ui['showUpdates'] != false;
        _lovenseLiveEnabled = useLiveMode;
        _lovensePanelCollapsed = lovense['panelCollapsed'] == true;
        _lovenseProfiles = profiles;
        _lovenseSelectedProfileId = selectedId;
        _lovenseFormActiveProfileIds = <String>{selectedId};
        _libraryPlaylistFileName =
            (library['playlistFileName'] as String?)?.trim() ?? '';
        _updateStatus = _buildUpdateIdleStatusMessage();
      });
      _syncControllersFromSelectedLovenseProfile();
      _syncRulesControllerFromSelectedLovenseProfile();
    } catch (_) {}
  }

  Future<void> _saveLocalSettings() async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'updates': <String, dynamic>{
        'autoCheckEnabled': _updateAutoCheck,
        'manualDisclosureAcknowledgedVersion':
            _updateManualDisclosureAcknowledgedVersion,
        'releaseDisclosureSuppressedVersion':
            _updateReleaseDisclosureSuppressedVersion,
      },
      'ui': <String, dynamic>{
        'showDiagnostics': _showDiagnosticsPanel,
        'showFunscriptOverview': _showFunscriptOverviewPanel,
        'showExecutionLog': _showExecutionLogPanel,
        'showUpdates': _showUpdatesPanel,
      },
      'lovense': <String, dynamic>{
        'executionMode': _lovenseExecutionMode.name,
        'panelCollapsed': _lovensePanelCollapsed,
        'selectedProfileId': _lovenseSelectedProfileId,
        'profiles': _lovenseProfiles
            .map((LovenseConnectionProfile profile) => profile.toJson())
            .toList(),
      },
      'library': <String, dynamic>{
        'playlistFileName': _libraryPlaylistFileName,
      },
    };
    await File(
      _settingsPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  Future<void> _refreshDiagnosticsInfo() async {
    await _ensureManagedDirectories();
    final File logFile = File(_appLogPath);
    String recentLog = '';
    if (await logFile.exists()) {
      try {
        final List<String> lines = await logFile.readAsLines();
        final List<String> recentLines = lines.length <= 120
            ? lines
            : lines.sublist(lines.length - 120);
        recentLog = recentLines.join('\n');
      } catch (_) {}
    }
    if (recentLog.trim().isEmpty) {
      recentLog = _logEntries
          .take(40)
          .map(
            (ExecutionLogEntry entry) =>
                '${entry.createdAt.toIso8601String()} ${entry.kind.name.toUpperCase()} '
                '${entry.title}${entry.detail.isEmpty ? '' : ' | ${entry.detail}'}',
          )
          .join('\n');
    }
    final String paths = <String>[
      'App data: $_appDataPath',
      'Library root: $_libraryRootPath',
      'Settings file: $_settingsPath',
      'Log directory: $_logsDirectoryPath',
      'Log file: $_appLogPath',
    ].join('\n');
    if (!mounted) {
      _diagnosticsPathsText = paths;
      _diagnosticsRecentLogText = recentLog.trim().isEmpty
          ? 'No recent log output.'
          : recentLog;
      _diagnosticsStatus = 'desktop | v$_appVersion';
      return;
    }
    setState(() {
      _diagnosticsPathsText = paths;
      _diagnosticsRecentLogText = recentLog.trim().isEmpty
          ? 'No recent log output.'
          : recentLog;
      _diagnosticsStatus = 'desktop | v$_appVersion';
    });
  }

  Future<void> _persistLogEntry(ExecutionLogEntry entry) async {
    try {
      await _ensureManagedDirectories();
      final String line =
          '${entry.createdAt.toIso8601String()} ${entry.kind.name.toUpperCase()} '
          '${entry.title}${entry.detail.isEmpty ? '' : ' | ${entry.detail}'}\n';
      await File(_appLogPath).writeAsString(line, mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _openDirectoryInFileManager(String path) async {
    final Directory directory = Directory(path);
    await directory.create(recursive: true);
    if (Platform.isWindows) {
      await Process.start('explorer.exe', <String>[directory.path]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', <String>[directory.path]);
      return;
    }
    await Process.start('xdg-open', <String>[directory.path]);
  }

  Future<void> _copyRecentDiagnosticsLog() async {
    await Clipboard.setData(ClipboardData(text: _diagnosticsRecentLogText));
    _appendLog(
      ExecutionLogEntry.success(
        'Diagnostics copied',
        'Recent diagnostics log copied to clipboard.',
      ),
    );
  }

  Future<void> _openDiagnosticsFolder() async {
    try {
      await _openDirectoryInFileManager(_logsDirectoryPath);
      _appendLog(
        ExecutionLogEntry.info('Diagnostics folder opened', _logsDirectoryPath),
      );
    } catch (error) {
      _appendLog(
        ExecutionLogEntry.error(
          'Diagnostics folder open failed',
          error.toString(),
        ),
      );
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String body,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    if (!mounted) {
      return true;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                    )
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<ConfirmActionResult> _confirmActionWithDontShowAgain({
    required String title,
    required String body,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    String dontShowAgainLabel = 'Do not show this again for this version.',
    bool destructive = false,
  }) async {
    if (!mounted) {
      return const ConfirmActionResult(confirmed: true);
    }
    bool dontShowAgain = false;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext dialogContext,
                void Function(void Function()) setDialogState,
              ) {
                return AlertDialog(
                  title: Text(title),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(body),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: dontShowAgain,
                        onChanged: (bool? value) {
                          setDialogState(() {
                            dontShowAgain = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          dontShowAgainLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(cancelLabel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: destructive
                          ? FilledButton.styleFrom(
                              backgroundColor: AppColors.danger,
                              foregroundColor: Colors.white,
                            )
                          : null,
                      child: Text(confirmLabel),
                    ),
                  ],
                );
              },
        );
      },
    );
    return ConfirmActionResult(
      confirmed: confirmed == true,
      dontShowAgain: dontShowAgain,
    );
  }

  bool _shouldShowManualUpdateDisclosure() {
    final String currentVersion = _appVersion.trim();
    if (currentVersion.isEmpty) {
      return true;
    }
    return _updateManualDisclosureAcknowledgedVersion != currentVersion;
  }

  bool _shouldShowReleaseDisclosure() {
    final String currentVersion = _appVersion.trim();
    if (currentVersion.isEmpty) {
      return true;
    }
    return _updateReleaseDisclosureSuppressedVersion != currentVersion;
  }

  Future<void> _handleUpdateAutoCheckToggle(bool nextValue) async {
    final bool previousValue = _updateAutoCheck;
    if (nextValue == previousValue) {
      return;
    }
    if (nextValue) {
      final bool confirmed = await _confirmAction(
        title: 'Automatic update checks',
        body: kAutoUpdateDisclosure,
        confirmLabel: 'Enable',
      );
      if (!confirmed) {
        if (mounted) {
          setState(() {});
        }
        return;
      }
    }
    setState(() {
      _updateAutoCheck = nextValue;
      _updateStatus = _buildUpdateIdleStatusMessage();
    });
    try {
      await _saveLocalSettings();
    } catch (error) {
      setState(() {
        _updateAutoCheck = previousValue;
      });
      _appendLog(
        ExecutionLogEntry.error(
          'Update setting not saved',
          'Could not save update setting: $error',
        ),
      );
    }
  }

  Future<bool> _ensureManualUpdateDisclosureAcknowledged() async {
    if (!_shouldShowManualUpdateDisclosure()) {
      return true;
    }
    final bool confirmed = await _confirmAction(
      title: 'Check for updates',
      body: kUpdateManualDisclosure,
      confirmLabel: 'Check now',
    );
    if (!confirmed) {
      return false;
    }
    _updateManualDisclosureAcknowledgedVersion = _appVersion.trim();
    await _saveLocalSettings();
    return true;
  }

  Future<void> _openLibraryFolder({
    required String kind,
    required String directoryPath,
  }) async {
    try {
      await _openDirectoryInFileManager(directoryPath);
      _appendLog(
        ExecutionLogEntry.info(
          'Library folder opened',
          '$kind: $directoryPath',
        ),
      );
    } catch (error) {
      _appendLog(
        ExecutionLogEntry.error('Library folder open failed', '$kind: $error'),
      );
    }
  }

  void _refreshLibraryStatus() {
    setState(() {
      _libraryStatus = 'Managed FHPlayer folders are ready.';
    });
  }

  String _buildUpdateIdleStatusMessage() {
    final String modeLine = _updateAutoCheck
        ? 'Automatic update checks are enabled and will run on startup.'
        : 'Automatic update checks are disabled. Use "Check now" whenever you want.';
    return '$modeLine\n$kUpdateStatusDisclosure\nSource: $kDefaultUpdateFeedUrl';
  }

  Future<void> _checkForUpdates({required bool manual}) async {
    if (_updateChecking) {
      return;
    }
    if (manual) {
      try {
        final bool acknowledged =
            await _ensureManualUpdateDisclosureAcknowledged();
        if (!acknowledged) {
          _appendLog(
            ExecutionLogEntry.info(
              'Update check cancelled',
              'The update disclosure was not acknowledged.',
            ),
          );
          return;
        }
      } catch (error) {
        _appendLog(
          ExecutionLogEntry.error(
            'Update check blocked',
            'Could not persist update disclosure acknowledgement: $error',
          ),
        );
        return;
      }
    }
    setState(() {
      _updateChecking = true;
      if (manual) {
        _updateStatus = 'Checking for updates...';
      }
    });
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final Uri uri = Uri.parse(kDefaultUpdateFeedUrl);
      final HttpClientRequest request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FHPlayer/$_appVersion');
      final HttpClientResponse response = await request.close();
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, dynamic> payload =
          jsonDecode(body) as Map<String, dynamic>;
      final String latestTag = (payload['tag_name'] as String?)?.trim() ?? '';
      final String normalizedLatest = latestTag.replaceFirst(RegExp(r'^v'), '');
      final String releaseUrl =
          (payload['html_url'] as String?)?.trim().isNotEmpty == true
          ? (payload['html_url'] as String).trim()
          : kDefaultReleasePageUrl;
      final bool updateAvailable =
          _parseVersionParts(normalizedLatest) != null &&
          _compareVersions(normalizedLatest, _appVersion) > 0;
      final String message = updateAvailable
          ? 'Version $normalizedLatest is available.\nCurrent version: $_appVersion.'
          : 'You are already on the latest version ($_appVersion).';
      if (!mounted) {
        _updateChecking = false;
        _updateReleaseUrl = releaseUrl;
        _updateStatus =
            '$message\nSource: $kDefaultUpdateFeedUrl\n'
            'Last checked: ${DateTime.now().toLocal().toString()}';
        return;
      }
      setState(() {
        _updateChecking = false;
        _updateReleaseUrl = releaseUrl;
        _updateStatus =
            '$message\nSource: $kDefaultUpdateFeedUrl\n'
            'Last checked: ${DateTime.now().toLocal().toString()}';
      });
      _appendLog(
        ExecutionLogEntry.success(
          'Update check',
          message.replaceAll('\n', ' '),
        ),
      );
    } catch (error) {
      if (!mounted) {
        _updateChecking = false;
        _updateStatus = 'Update check failed: $error';
        return;
      }
      setState(() {
        _updateChecking = false;
        _updateStatus = 'Update check failed: $error';
      });
      _appendLog(
        ExecutionLogEntry.error('Update check failed', error.toString()),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openReleasePage() async {
    final String url = _updateReleaseUrl.trim().isEmpty
        ? kDefaultReleasePageUrl
        : _updateReleaseUrl.trim();
    try {
      if (_shouldShowReleaseDisclosure()) {
        final ConfirmActionResult confirmation =
            await _confirmActionWithDontShowAgain(
              title: 'Open release',
              body: '$kReleaseDisclosure\n\n$url',
              confirmLabel: 'Open release',
            );
        if (!confirmation.confirmed) {
          _appendLog(
            ExecutionLogEntry.info(
              'Open release page cancelled',
              'The browser was not opened.',
            ),
          );
          return;
        }
        if (confirmation.dontShowAgain) {
          final String previousSuppressedVersion =
              _updateReleaseDisclosureSuppressedVersion;
          _updateReleaseDisclosureSuppressedVersion = _appVersion.trim();
          try {
            await _saveLocalSettings();
          } catch (error) {
            _updateReleaseDisclosureSuppressedVersion =
                previousSuppressedVersion;
            _appendLog(
              ExecutionLogEntry.error(
                'Release notice preference not saved',
                'Could not save release notice preference: $error',
              ),
            );
          }
        }
      }
      if (Platform.isWindows) {
        await Process.start('cmd', <String>['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.start('open', <String>[url]);
      } else {
        await Process.start('xdg-open', <String>[url]);
      }
      _appendLog(ExecutionLogEntry.info('Open release page', url));
    } catch (error) {
      _appendLog(
        ExecutionLogEntry.error('Open release page failed', error.toString()),
      );
    }
  }

  Future<void> _importCurrentEntryToLibrary() async {
    if (!_hasLoadedEntry) {
      _appendLog(
        ExecutionLogEntry.error(
          'Library import failed',
          'Load a video and a funscript first.',
        ),
      );
      return;
    }
    try {
      await _ensureManagedDirectories();
      final List<PlaylistEntryData> sourceEntries = _playlistEntries.isEmpty
          ? <PlaylistEntryData>[_currentEntrySnapshot()]
          : List<PlaylistEntryData>.from(_playlistEntries);
      final String? playlistFileName = await _promptLibraryPlaylistFileName(
        sourceEntries: sourceEntries,
      );
      if (playlistFileName == null) {
        _appendLog(
          ExecutionLogEntry.info(
            'Library save cancelled',
            'The playlist was not changed.',
          ),
        );
        return;
      }
      final String previousLibraryPlaylistFileName = _libraryPlaylistFileName
          .trim();
      final String playlistPath =
          '$_libraryExportsPath${Platform.pathSeparator}$playlistFileName';
      final Set<String> overwriteTargets = <String>{};
      final Set<String> removeTargets = <String>{};
      for (final PlaylistEntryData entry in sourceEntries) {
        if (entry.videoPath.trim().isEmpty ||
            entry.funscriptPath.trim().isEmpty) {
          continue;
        }
        final File sourceVideo = File(entry.videoPath);
        final File sourceFunscript = File(entry.funscriptPath);
        if (!await sourceVideo.exists() || !await sourceFunscript.exists()) {
          continue;
        }
        final String targetVideoName = _pathFileName(entry.videoPath);
        final String targetFunscriptName = _pathFileName(entry.funscriptPath);
        if (targetVideoName.isEmpty || targetFunscriptName.isEmpty) {
          continue;
        }
        final String targetVideoPath =
            '$_libraryVideosPath${Platform.pathSeparator}$targetVideoName';
        final String targetFunscriptPath =
            '$_libraryFunscriptsPath${Platform.pathSeparator}$targetFunscriptName';
        if (await File(targetVideoPath).exists() &&
            !_pathsEqual(sourceVideo.path, targetVideoPath)) {
          overwriteTargets.add('Video: $targetVideoName');
        }
        if (await File(targetFunscriptPath).exists() &&
            !_pathsEqual(sourceFunscript.path, targetFunscriptPath)) {
          overwriteTargets.add('Funscript: $targetFunscriptName');
        }
      }
      if (await File(playlistPath).exists()) {
        overwriteTargets.add('Playlist: $playlistFileName');
      }
      if (previousLibraryPlaylistFileName.isNotEmpty &&
          previousLibraryPlaylistFileName != playlistFileName) {
        final String previousPath =
            '$_libraryExportsPath${Platform.pathSeparator}'
            '$previousLibraryPlaylistFileName';
        if (await File(previousPath).exists()) {
          removeTargets.add('Playlist: $previousLibraryPlaylistFileName');
        }
      }
      if (overwriteTargets.isNotEmpty || removeTargets.isNotEmpty) {
        final String overwritePreview = _buildFileActionPreview(
          overwriteTargets,
        );
        final String removePreview = _buildFileActionPreview(removeTargets);
        final StringBuffer body = StringBuffer(
          'Saving to Library will change existing files.',
        );
        if (overwritePreview.isNotEmpty) {
          body
            ..write('\n\nFiles that will be overwritten:\n')
            ..write(overwritePreview);
        }
        if (removePreview.isNotEmpty) {
          body
            ..write('\n\nFiles that will be removed:\n')
            ..write(removePreview);
        }
        body.write('\n\nContinue?');
        final bool confirmed = await _confirmAction(
          title: 'Replace Library files',
          body: body.toString(),
          confirmLabel: 'Replace',
          destructive: true,
        );
        if (!confirmed) {
          _appendLog(
            ExecutionLogEntry.info(
              'Library save cancelled',
              'Existing library files were not replaced.',
            ),
          );
          return;
        }
      }
      final List<PlaylistEntryData> importedEntries = <PlaylistEntryData>[];
      int importedVideos = 0;
      int importedFunscripts = 0;
      for (final PlaylistEntryData entry in sourceEntries) {
        if (entry.videoPath.trim().isEmpty ||
            entry.funscriptPath.trim().isEmpty) {
          continue;
        }
        final File sourceVideo = File(entry.videoPath);
        final File sourceFunscript = File(entry.funscriptPath);
        if (!await sourceVideo.exists() || !await sourceFunscript.exists()) {
          continue;
        }
        final String targetVideoName = _pathFileName(entry.videoPath);
        final String targetFunscriptName = _pathFileName(entry.funscriptPath);
        if (targetVideoName.isEmpty || targetFunscriptName.isEmpty) {
          continue;
        }
        final String targetVideoPath =
            '$_libraryVideosPath${Platform.pathSeparator}$targetVideoName';
        final String targetFunscriptPath =
            '$_libraryFunscriptsPath${Platform.pathSeparator}$targetFunscriptName';
        await _copyFileReplacing(sourceVideo.path, targetVideoPath);
        await _copyFileReplacing(sourceFunscript.path, targetFunscriptPath);
        importedVideos += 1;
        importedFunscripts += 1;
        importedEntries.add(
          PlaylistEntryData(
            videoPath: targetVideoPath,
            videoName: entry.videoName.trim().isEmpty
                ? targetVideoName
                : entry.videoName,
            funscriptPath: targetFunscriptPath,
            funscriptName: entry.funscriptName.trim().isEmpty
                ? targetFunscriptName
                : entry.funscriptName,
            activeLovenseProfileIds: entry.activeLovenseProfileIds,
            videoSource: PlaylistMediaReference(
              kind: 'videos',
              source: 'library',
              name: entry.videoName.trim().isEmpty
                  ? targetVideoName
                  : entry.videoName,
              libraryName: targetVideoName,
              path: targetVideoPath,
            ),
            funscriptSource: PlaylistMediaReference(
              kind: 'funscripts',
              source: 'library',
              name: entry.funscriptName.trim().isEmpty
                  ? targetFunscriptName
                  : entry.funscriptName,
              libraryName: targetFunscriptName,
              path: targetFunscriptPath,
            ),
            embeddedFunscriptDocument: entry.embeddedFunscriptDocument == null
                ? null
                : _cloneJsonMap(entry.embeddedFunscriptDocument!),
            executionMode: entry.executionMode,
            rulesText: entry.rulesText,
          ),
        );
      }

      if (importedEntries.isEmpty) {
        _appendLog(
          ExecutionLogEntry.error(
            'Library import failed',
            'No valid video/funscript entries could be copied.',
          ),
        );
        return;
      }

      final Map<String, dynamic> playlistPayload =
          await _buildSavedPlaylistDocument(entries: importedEntries);
      await File(playlistPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(playlistPayload),
      );
      String replacedFileName = '';
      if (previousLibraryPlaylistFileName.isNotEmpty &&
          previousLibraryPlaylistFileName != playlistFileName) {
        final String previousPath =
            '$_libraryExportsPath${Platform.pathSeparator}'
            '$previousLibraryPlaylistFileName';
        final File previousFile = File(previousPath);
        if (await previousFile.exists()) {
          await previousFile.delete();
          replacedFileName = previousLibraryPlaylistFileName;
        }
      }
      if (mounted) {
        setState(() {
          _libraryPlaylistFileName = playlistFileName;
        });
      } else {
        _libraryPlaylistFileName = playlistFileName;
      }
      await _saveLocalSettings();

      _appendLog(
        ExecutionLogEntry.success(
          'Library import',
          'Saved $importedVideos video(s), $importedFunscripts funscript(s), '
              'playlist $playlistFileName'
              '${replacedFileName.isEmpty ? '' : ' (replaced $replacedFileName)'}'
              '.',
        ),
      );
      _refreshLibraryStatus();
      await _refreshDiagnosticsInfo();
    } catch (error) {
      _appendLog(
        ExecutionLogEntry.error('Library import failed', error.toString()),
      );
    }
  }

  String _buildFileActionPreview(Set<String> entries, {int maxItems = 6}) {
    if (entries.isEmpty) {
      return '';
    }
    final List<String> sorted = entries.toList()..sort();
    final int shown = math.min(sorted.length, maxItems);
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < shown; index += 1) {
      if (index > 0) {
        buffer.writeln();
      }
      buffer.write('- ${sorted[index]}');
    }
    final int hiddenCount = sorted.length - shown;
    if (hiddenCount > 0) {
      buffer
        ..writeln()
        ..write('- ... and $hiddenCount more');
    }
    return buffer.toString();
  }

  Future<void> _copyFileReplacing(String sourcePath, String targetPath) async {
    if (_pathsEqual(sourcePath, targetPath)) {
      return;
    }
    final File target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await File(sourcePath).copy(targetPath);
  }

  String _sanitizePlaylistBaseName(String name) {
    final String sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .trim()
        .replaceAll(RegExp(r'[ .]+$'), '');
    return sanitized;
  }

  String _buildLibraryPlaylistFileName({
    required List<PlaylistEntryData> sourceEntries,
  }) {
    final String rememberedFileName = _libraryPlaylistFileName.trim();
    if (rememberedFileName.isNotEmpty) {
      final String rememberedBase = _sanitizePlaylistBaseName(
        _stripPlaylistFileExtension(rememberedFileName),
      );
      if (rememberedBase.isNotEmpty) {
        return '$rememberedBase.fhplaylist';
      }
    }
    final String fallbackVideoName = sourceEntries.isEmpty
        ? ''
        : sourceEntries.first.videoName;
    final String preferred = _videoName.trim().isNotEmpty
        ? _videoName
        : fallbackVideoName;
    final String base = _sanitizePlaylistBaseName(
      _stripFileExtension(preferred),
    );
    final String safeBase = base.isEmpty ? 'fhplayer-playlist' : base;
    return '$safeBase.fhplaylist';
  }

  String _stripPlaylistFileExtension(String fileName) {
    return fileName.trim().replaceAll(
      RegExp(r'\.(?:fhplaylist|json)$', caseSensitive: false),
      '',
    );
  }

  String _buildLibraryPlaylistFileNameFromInput(String value) {
    final String baseName = _sanitizePlaylistBaseName(
      _stripPlaylistFileExtension(value),
    );
    if (baseName.isEmpty) {
      throw const FormatException(
        'Enter a playlist name before saving to Library.',
      );
    }
    return '$baseName.fhplaylist';
  }

  Future<String?> _promptLibraryPlaylistFileName({
    required List<PlaylistEntryData> sourceEntries,
  }) async {
    if (!mounted) {
      return _buildLibraryPlaylistFileName(sourceEntries: sourceEntries);
    }
    final String defaultFileName = _buildLibraryPlaylistFileName(
      sourceEntries: sourceEntries,
    );
    final TextEditingController controller = TextEditingController(
      text: _stripPlaylistFileExtension(defaultFileName),
    );
    String errorMessage = '';
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder:
                (
                  BuildContext dialogContext,
                  void Function(void Function()) setDialogState,
                ) {
                  return AlertDialog(
                    title: const Text('Save playlist to Library'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _libraryExportsPath,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: 'Playlist name',
                            hintText: 'My playlist',
                            errorText: errorMessage.isEmpty
                                ? null
                                : errorMessage,
                          ),
                          onSubmitted: (_) {
                            try {
                              final String fileName =
                                  _buildLibraryPlaylistFileNameFromInput(
                                    controller.text,
                                  );
                              Navigator.of(dialogContext).pop(fileName);
                            } on FormatException catch (error) {
                              setDialogState(() {
                                errorMessage = error.message;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          try {
                            final String fileName =
                                _buildLibraryPlaylistFileNameFromInput(
                                  controller.text,
                                );
                            Navigator.of(dialogContext).pop(fileName);
                          } on FormatException catch (error) {
                            setDialogState(() {
                              errorMessage = error.message;
                            });
                          }
                        },
                        child: const Text('Save to Library'),
                      ),
                    ],
                  );
                },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _selectVideoFromLibrary() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      initialDirectory: _libraryVideosPath,
    );
    final PlatformFile? file = result?.files.single;
    if (file?.path == null || file!.path!.trim().isEmpty) {
      return;
    }
    setState(() {
      _videoPath = file.path!;
      _videoName = file.name;
      _videoInitializing = true;
      _videoError = '';
    });
    await _initializeVideo(file.path!);
  }

  Future<void> _selectFunscriptFromLibrary() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['funscript', 'json'],
      initialDirectory: _libraryFunscriptsPath,
    );
    final PlatformFile? file = result?.files.single;
    if (file?.path == null || file!.path!.trim().isEmpty) {
      return;
    }
    await _loadFunscriptFromPath(file.path!, sourceName: file.name);
  }

  Future<void> _selectPlaylistFromLibrary() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['fhplaylist', 'json'],
      initialDirectory: _libraryExportsPath,
      withData: true,
    );
    final PlatformFile? file = result?.files.single;
    if (file == null) {
      return;
    }
    await _loadExternalPlaylistFile(file);
  }

  Future<void> _deleteLibraryFile({
    required String kind,
    required String initialDirectory,
    required List<String> allowedExtensions,
  }) async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      initialDirectory: initialDirectory,
    );
    final PlatformFile? file = result?.files.single;
    if (file?.path == null || file!.path!.trim().isEmpty) {
      return;
    }
    final bool confirmed = await _confirmAction(
      title: 'Delete from Library',
      body:
          'Delete $kind file "${file.name}" permanently from the FHPlayer Library?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) {
      _appendLog(
        ExecutionLogEntry.info(
          'Library delete cancelled',
          '$kind: ${file.name}',
        ),
      );
      return;
    }
    try {
      await File(file.path!).delete();
      _appendLog(
        ExecutionLogEntry.info('Library file deleted', '$kind: ${file.name}'),
      );
      _refreshLibraryStatus();
      await _refreshDiagnosticsInfo();
    } catch (error) {
      _appendLog(
        ExecutionLogEntry.error('Library delete failed', error.toString()),
      );
    }
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
      final Object? rawDocument = jsonDecode(content);
      if (rawDocument is! Map) {
        throw const FormatException('Invalid funscript JSON object.');
      }
      final Map<String, dynamic> document = Map<String, dynamic>.from(
        rawDocument,
      );
      await _loadFunscriptFromDocument(
        document,
        sourceName: file.name,
        sourcePath: file.path ?? file.name,
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
      _sendLovenseAction(action, positionMs, deltaMs);
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
    unawaited(_persistLogEntry(entry));
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
      _sendLovenseStop('Playback paused', pausePositionMs);
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
    _sendLovenseStop('Run completed', positionMs);

    final String detail = _timingDeltaCount == 0
        ? 'No actions triggered | video ${formatMs(positionMs)}'
        : '$_timingDeltaCount actions | avg ${_formatAverageDelta()} | '
              'min ${_formatDelta(_timingDeltaMinMs)} | '
              'max ${_formatDelta(_timingDeltaMaxMs)} | '
              'last ${_formatDelta(_timingDeltaLastMs)} | '
              'video ${formatMs(positionMs)}';
    _appendLog(ExecutionLogEntry.success('Run completed', detail));
    if (_playlistEntries.length > 1 && _hasSelectedPlaylistEntry) {
      _appendLog(
        ExecutionLogEntry.info(
          'Playlist advance',
          'Loading next entry ($_playlistModeLabel mode).',
        ),
      );
      unawaited(_loadNextPlaylistEntry());
    }
  }

  void _sendLovenseAction(FunscriptAction action, int positionMs, int deltaMs) {
    if (_lovenseLiveEnabled) {
      unawaited(_sendLovenseLiveAction(action, positionMs, deltaMs));
      return;
    }
    _sendLovenseMockAction(action, positionMs, deltaMs);
  }

  void _sendLovenseStop(String reason, int positionMs) {
    if (_lovenseLiveEnabled) {
      unawaited(_sendLovenseLiveStop(reason, positionMs));
      return;
    }
    _sendLovenseMockStop(reason, positionMs);
  }

  LovenseLiveConnectionConfig? _liveConnectionConfigOrNull({
    LovenseConnectionProfile? profile,
  }) {
    return (profile ?? _selectedLovenseProfile).connectionConfigOrNull();
  }

  Future<void> _detectLovenseLiveDevices() async {
    final LovenseConnectionProfile selectedProfile = _selectedLovenseProfile;
    final String selectedProfileId = selectedProfile.id;
    final LovenseLiveConnectionConfig? config = _liveConnectionConfigOrNull(
      profile: selectedProfile,
    );
    if (config == null) {
      setState(() {
        _lovenseLiveStatus =
            'Invalid host or port for ${selectedProfile.displayLabel}.';
      });
      return;
    }

    setState(() {
      _lovenseLiveDetecting = true;
      _lovenseLiveStatus = 'Detecting devices...';
    });

    try {
      final LovenseLiveDetectResult result = await _lovenseLiveClient
          .detectDevices(config);
      final Set<String> detectedIds = <String>{
        for (final LovenseLiveDevice device in result.devices) device.id,
      };
      final Set<String> preservedSelection = selectedProfile.selectedDeviceIds
          .where(detectedIds.contains)
          .toSet();
      final Set<String> nextSelection = preservedSelection.isNotEmpty
          ? preservedSelection
          : (result.devices.isEmpty
                ? <String>{}
                : <String>{result.devices.first.id});

      setState(() {
        final int profileIndex = _lovenseProfiles.indexWhere(
          (LovenseConnectionProfile profile) => profile.id == selectedProfileId,
        );
        if (profileIndex >= 0) {
          _lovenseProfiles[profileIndex] = _lovenseProfiles[profileIndex]
              .copyWith(
                detectedDevices: result.devices,
                selectedDeviceIds: nextSelection,
              );
        }
        _lovenseLiveStatus = result.devices.isEmpty
            ? 'No devices detected for ${selectedProfile.displayLabel}.'
            : 'Detected ${result.devices.length} device(s) for ${selectedProfile.displayLabel}.';
      });
      _refreshLovenseLiveRuleValidation();
      _appendLog(
        ExecutionLogEntry.success('Lovense detect', _lovenseLiveStatus),
      );
    } catch (error) {
      setState(() {
        final int profileIndex = _lovenseProfiles.indexWhere(
          (LovenseConnectionProfile profile) => profile.id == selectedProfileId,
        );
        if (profileIndex >= 0) {
          _lovenseProfiles[profileIndex] = _lovenseProfiles[profileIndex]
              .copyWith(
                detectedDevices: const <LovenseLiveDevice>[],
                selectedDeviceIds: const <String>{},
              );
        }
        _lovenseLiveRuleIssues = <LovenseLiveRuleIssue>[];
        _lovenseLiveStatus = 'Detection failed: $error';
      });
      _appendLog(
        ExecutionLogEntry.error('Lovense detect failed', error.toString()),
      );
    } finally {
      if (mounted) {
        setState(() {
          _lovenseLiveDetecting = false;
        });
      }
    }
  }

  void _refreshLovenseLiveRuleValidation() {
    if (!_lovenseLiveEnabled) {
      if (_lovenseLiveRuleIssues.isNotEmpty) {
        setState(() {
          _lovenseLiveRuleIssues = <LovenseLiveRuleIssue>[];
        });
      }
      return;
    }

    final List<LovenseLiveRuleIssue> issues = <LovenseLiveRuleIssue>[];
    for (final LovenseConnectionProfile profile in _activeLovenseProfiles()) {
      final List<LovenseLiveRuleIssue> profileIssues = _lovenseLiveRuleEngine
          .validate(
            rulesText: _rulesTextForProfile(profile),
            selectedDevices: _selectedLovenseLiveDevicesForProfile(profile),
          );
      issues.addAll(
        profileIssues.map(
          (LovenseLiveRuleIssue issue) => LovenseLiveRuleIssue(
            '[${profile.displayLabel}] ${issue.message}',
            lineNumber: issue.lineNumber,
          ),
        ),
      );
    }
    if (!mounted) {
      _lovenseLiveRuleIssues = issues;
      return;
    }
    setState(() {
      _lovenseLiveRuleIssues = issues;
    });
  }

  void _setLovenseExecutionMode(
    LovenseExecutionMode mode, {
    bool persist = true,
  }) {
    final bool enableLive = mode == LovenseExecutionMode.live;
    setState(() {
      _lovenseLiveEnabled = enableLive;
      if (!enableLive) {
        _clearScheduledLovenseLiveActions(cancelAutoStops: true);
      }
    });
    _refreshLovenseLiveRuleValidation();
    if (persist) {
      unawaited(_saveLocalSettings());
    }
  }

  void _setSelectedLovenseProfile(String profileId) {
    if (!_lovenseProfiles.any(
      (LovenseConnectionProfile profile) => profile.id == profileId,
    )) {
      return;
    }
    setState(() {
      _lovenseSelectedProfileId = profileId;
    });
    _syncControllersFromSelectedLovenseProfile();
    _syncRulesControllerFromSelectedLovenseProfile();
    _refreshLovenseLiveRuleValidation();
    unawaited(_saveLocalSettings());
  }

  void _applyActiveProfileIdsToCurrentContext(Set<String> ids) {
    final Set<String> available = _lovenseProfiles
        .map((LovenseConnectionProfile profile) => profile.id)
        .toSet();
    final Set<String> normalized = ids.where(available.contains).toSet();
    if (normalized.isEmpty && _lovenseProfiles.isNotEmpty) {
      normalized.add(_selectedLovenseProfile.id);
    }
    if (_hasSelectedPlaylistEntry) {
      final PlaylistEntryData entry = _playlistEntries[_selectedPlaylistIndex];
      _playlistEntries[_selectedPlaylistIndex] = entry.copyWith(
        activeLovenseProfileIds: normalized.toList(),
      );
    }
    _lovenseFormActiveProfileIds = normalized;
  }

  void _toggleLovenseActiveProfileForCurrentEntry(
    String profileId,
    bool active,
  ) {
    final Set<String> next = _activeLovenseProfileIds().toSet();
    if (active) {
      next.add(profileId);
    } else {
      next.remove(profileId);
    }
    setState(() {
      _applyActiveProfileIdsToCurrentContext(next);
    });
    _refreshLovenseLiveRuleValidation();
  }

  int _nextAvailableLovenseUserNumber() {
    final Set<int> used = <int>{};
    final RegExp labelPattern = RegExp(r'^user\s+(\d+)$', caseSensitive: false);
    for (final LovenseConnectionProfile profile in _lovenseProfiles) {
      final RegExpMatch? labelMatch = labelPattern.firstMatch(
        profile.label.trim(),
      );
      if (labelMatch != null) {
        final int? parsed = int.tryParse(labelMatch.group(1)!);
        if (parsed != null && parsed > 0) {
          used.add(parsed);
        }
      }
    }
    int candidate = 1;
    while (used.contains(candidate)) {
      candidate += 1;
    }
    return candidate;
  }

  String _nextLovenseProfileId() {
    final Set<String> usedIds = _lovenseProfiles
        .map((LovenseConnectionProfile profile) => profile.id)
        .toSet();
    final int seed = DateTime.now().microsecondsSinceEpoch;
    int attempt = 0;
    String candidate = 'profile-$seed';
    while (usedIds.contains(candidate)) {
      attempt += 1;
      candidate = 'profile-$seed-$attempt';
    }
    return candidate;
  }

  void _addLovenseConnectionProfile() {
    final int number = _nextAvailableLovenseUserNumber();
    final String id = _nextLovenseProfileId();
    final String label = 'User $number';
    final LovenseConnectionProfile base = _selectedLovenseProfile;
    final LovenseConnectionProfile profile = LovenseConnectionProfile(
      id: id,
      label: label,
      scheme: base.scheme,
      host: base.host,
      port: base.port,
      platformName: base.platformName,
      rulesText: _rulesTextForProfile(base),
    );
    setState(() {
      _lovenseProfiles = <LovenseConnectionProfile>[
        ..._lovenseProfiles,
        profile,
      ];
      _lovenseSelectedProfileId = id;
      _applyActiveProfileIdsToCurrentContext(
        _activeLovenseProfileIds().toSet()..add(id),
      );
    });
    _syncControllersFromSelectedLovenseProfile();
    _syncRulesControllerFromSelectedLovenseProfile();
    _refreshLovenseLiveRuleValidation();
    unawaited(_saveLocalSettings());
  }

  void _removeSelectedLovenseConnectionProfile() {
    if (_lovenseProfiles.length <= 1) {
      _appendLog(
        ExecutionLogEntry.error(
          'Connection profile not removed',
          'At least one Lovense user profile must remain.',
        ),
      );
      return;
    }
    final String removedId = _selectedLovenseProfile.id;
    setState(() {
      _lovenseProfiles.removeWhere(
        (LovenseConnectionProfile profile) => profile.id == removedId,
      );
      _lovenseSelectedProfileId = _lovenseProfiles.first.id;
      final Set<String> nextActive = _activeLovenseProfileIds().toSet()
        ..remove(removedId);
      _applyActiveProfileIdsToCurrentContext(nextActive);
    });
    _syncControllersFromSelectedLovenseProfile();
    _syncRulesControllerFromSelectedLovenseProfile();
    _refreshLovenseLiveRuleValidation();
    unawaited(_saveLocalSettings());
  }

  Set<String> _activeLovenseCapabilities() {
    if (_lovenseLiveEnabled) {
      final Set<String> capabilities = <String>{};
      for (final LovenseConnectionProfile profile in _activeLovenseProfiles()) {
        for (final LovenseLiveDevice device
            in _selectedLovenseLiveDevicesForProfile(profile)) {
          capabilities.addAll(device.ruleCapabilities);
        }
      }
      return capabilities;
    }
    final Set<String> capabilities = <String>{};
    for (final LovenseMockDevice device in _lovenseMockClient.devices) {
      capabilities.addAll(device.capabilities);
    }
    return capabilities;
  }

  String _lovenseCapabilitiesLabel() {
    final Set<String> capabilities = _activeLovenseCapabilities();
    if (capabilities.isEmpty) {
      return '-';
    }
    final List<String> ordered = capabilities.toList()..sort();
    return ordered.join(', ');
  }

  String _lovenseDeviceTypeLabel() {
    if (_lovenseLiveEnabled) {
      final List<LovenseLiveDevice> selected = <LovenseLiveDevice>[
        for (final LovenseConnectionProfile profile in _activeLovenseProfiles())
          ..._selectedLovenseLiveDevicesForProfile(profile),
      ];
      if (selected.isEmpty) {
        return '-';
      }
      final Set<String> types = selected
          .map((LovenseLiveDevice device) => device.type.trim())
          .where((String type) => type.isNotEmpty)
          .toSet();
      if (types.isEmpty) {
        return selected.length == 1 ? selected.first.displayName : 'Mixed';
      }
      final List<String> ordered = types.toList()..sort();
      return ordered.join(', ');
    }
    final Set<String> names = _lovenseMockClient.devices
        .map((LovenseMockDevice device) => device.name.trim())
        .where((String name) => name.isNotEmpty)
        .toSet();
    if (names.isEmpty) {
      return '-';
    }
    final List<String> ordered = names.toList()..sort();
    return ordered.join(', ');
  }

  String _lovenseParallelActionsLabel() {
    if (_lovenseLiveEnabled) {
      final int deviceCount = _activeLovenseProfiles()
          .map(_selectedLovenseLiveDevicesForProfile)
          .fold<int>(
            0,
            (int sum, List<LovenseLiveDevice> items) => sum + items.length,
          );
      return deviceCount <= 0 ? '-' : 'Up to $deviceCount devices in parallel';
    }
    final int deviceCount = _lovenseMockClient.devices.length;
    return deviceCount <= 0 ? '-' : 'Up to $deviceCount simulated devices';
  }

  ({bool isError, String text}) _lovenseRuleStatusSummary() {
    if (_lovenseLiveEnabled) {
      final List<LovenseConnectionProfile> activeProfiles =
          _activeLovenseProfiles();
      final int selectedDeviceCount = activeProfiles
          .map(_selectedLovenseLiveDevicesForProfile)
          .fold<int>(
            0,
            (int sum, List<LovenseLiveDevice> items) => sum + items.length,
          );
      if (_lovenseLiveRuleIssues.isNotEmpty) {
        return (
          isError: true,
          text: _lovenseLiveRuleIssues
              .map((LovenseLiveRuleIssue issue) => issue.toString())
              .join(' | '),
        );
      }
      if (selectedDeviceCount == 0) {
        return (
          isError: false,
          text: 'Select at least one detected live device to validate rules.',
        );
      }
      return (
        isError: false,
        text:
            'Rule validation active for ${activeProfiles.length} active user(s), $selectedDeviceCount selected live device(s).',
      );
    }
    final String? ruleError = _lovenseMockClient.ruleError;
    if (ruleError != null && ruleError.trim().isNotEmpty) {
      return (isError: true, text: ruleError);
    }
    return (
      isError: false,
      text: 'Rule validation active for simulated Lovense devices.',
    );
  }

  String _lovenseActionRangesSummary() {
    final Set<String> capabilities = _activeLovenseCapabilities();
    final List<String> ranges = <String>[];
    for (final ({String action, String range, Set<String> requiredCapabilities})
        item
        in kLovenseActionRangeCatalog) {
      final Set<String> required = item.requiredCapabilities;
      if (required.isEmpty || required.every(capabilities.contains)) {
        ranges.add(item.range);
      }
    }
    if (ranges.isEmpty) {
      return 'Detect or select a device to show action ranges.';
    }
    return ranges.join(', ');
  }

  void _clearScheduledLovenseLiveActions({required bool cancelAutoStops}) {
    for (final Timer timer in _lovenseLiveDelayTimers) {
      timer.cancel();
    }
    _lovenseLiveDelayTimers.clear();

    if (!cancelAutoStops) {
      return;
    }
    final List<String> keys = _lovenseLiveAutoStopTimers.keys.toList();
    for (final String key in keys) {
      _lovenseLiveAutoStopTimers[key]?.cancel();
      _lovenseLiveAutoStopTimers.remove(key);
    }
  }

  void _scheduleLovenseLiveAutoStop({
    required LovenseLiveConnectionConfig config,
    required String timerKey,
    required String toyId,
    required int durationMs,
  }) {
    final Timer? existing = _lovenseLiveAutoStopTimers.remove(timerKey);
    existing?.cancel();
    final Timer timer = Timer(Duration(milliseconds: durationMs), () async {
      _lovenseLiveAutoStopTimers.remove(timerKey);
      try {
        await _lovenseLiveClient.stopDevices(
          config: config,
          toyIds: <String>[toyId],
        );
      } catch (_) {}
    });
    _lovenseLiveAutoStopTimers[timerKey] = timer;
  }

  Future<void> _sendLovenseLiveAction(
    FunscriptAction action,
    int positionMs,
    int deltaMs,
  ) async {
    final List<LovenseConnectionProfile> activeProfiles =
        _activeLovenseProfiles();
    if (activeProfiles.isEmpty) {
      _appendLog(
        ExecutionLogEntry.error(
          'Lovense live',
          'No active Lovense user selected.',
        ),
      );
      return;
    }
    final LovenseActionContext context = LovenseActionContext(
      index: action.index,
      atMs: action.atMs,
      pos: action.pos,
      currentMs: positionMs,
      deltaMs: deltaMs,
    );

    final List<LovenseLiveRuleIssue> aggregatedIssues =
        <LovenseLiveRuleIssue>[];
    bool sentAnyCommand = false;
    for (final LovenseConnectionProfile profile in activeProfiles) {
      final LovenseLiveConnectionConfig? config = _liveConnectionConfigOrNull(
        profile: profile,
      );
      if (config == null) {
        aggregatedIssues.add(
          LovenseLiveRuleIssue(
            'Invalid host/port configuration for ${profile.displayLabel}.',
          ),
        );
        continue;
      }
      final List<LovenseLiveDevice> selectedDevices =
          _selectedLovenseLiveDevicesForProfile(profile);
      if (selectedDevices.isEmpty) {
        continue;
      }
      final LovenseLiveRuleEvaluation evaluation = _lovenseLiveRuleEngine
          .evaluate(
            rulesText: _rulesTextForProfile(profile),
            context: context,
            selectedDevices: selectedDevices,
          );
      if (evaluation.issues.isNotEmpty) {
        aggregatedIssues.addAll(
          evaluation.issues.map(
            (LovenseLiveRuleIssue issue) => LovenseLiveRuleIssue(
              '[${profile.displayLabel}] ${issue.message}',
              lineNumber: issue.lineNumber,
            ),
          ),
        );
        continue;
      }
      if (evaluation.commands.isEmpty) {
        continue;
      }
      sentAnyCommand = true;
      final Map<int, List<LovenseLiveDispatchCommand>> byDelay =
          <int, List<LovenseLiveDispatchCommand>>{};
      for (final LovenseLiveDispatchCommand command in evaluation.commands) {
        byDelay
            .putIfAbsent(command.delayMs, () => <LovenseLiveDispatchCommand>[])
            .add(command);
      }
      for (final int delayMs in byDelay.keys) {
        final List<LovenseLiveDispatchCommand> batch = byDelay[delayMs]!;
        void executeBatch() {
          unawaited(() async {
            try {
              await _lovenseLiveClient.sendCommands(
                config: config,
                commands: <LovenseLiveCommand>[
                  for (final LovenseLiveDispatchCommand item in batch)
                    item.command,
                ],
              );
              for (final LovenseLiveDispatchCommand item in batch) {
                if (item.durationMs > 0 && item.durationMs < 1000) {
                  _scheduleLovenseLiveAutoStop(
                    config: config,
                    timerKey: '${profile.id}:${item.command.toy}',
                    toyId: item.command.toy,
                    durationMs: item.durationMs,
                  );
                }
              }
              _appendLog(
                ExecutionLogEntry.success(
                  'Lovense live ${action.index}',
                  '${profile.displayLabel} | ${batch.length} command(s) | delay $delayMs ms | '
                      'pos ${action.pos} | delta $deltaMs ms',
                ),
                refresh: false,
              );
            } catch (error) {
              _appendLog(
                ExecutionLogEntry.error(
                  'Lovense live ${action.index} failed',
                  '${profile.displayLabel} | $error',
                ),
              );
            }
          }());
        }

        if (delayMs <= 0) {
          executeBatch();
          continue;
        }
        late final Timer timer;
        timer = Timer(Duration(milliseconds: delayMs), () {
          _lovenseLiveDelayTimers.remove(timer);
          executeBatch();
        });
        _lovenseLiveDelayTimers.add(timer);
      }
    }
    if (aggregatedIssues.isNotEmpty) {
      if (mounted) {
        setState(() {
          _lovenseLiveRuleIssues = aggregatedIssues;
        });
      }
      _appendLog(
        ExecutionLogEntry.error(
          'Lovense live rule failed',
          aggregatedIssues
              .map((LovenseLiveRuleIssue issue) => issue.toString())
              .join(' | '),
        ),
      );
      return;
    }
    if (!sentAnyCommand) {
      _appendLog(
        ExecutionLogEntry.info(
          'Lovense live skipped',
          'No selected live device for the active user(s).',
        ),
        refresh: false,
      );
    }
  }

  Future<void> _sendLovenseLiveStop(String reason, int positionMs) async {
    _clearScheduledLovenseLiveActions(cancelAutoStops: true);
    final List<LovenseConnectionProfile> activeProfiles =
        _activeLovenseProfiles();
    if (activeProfiles.isEmpty) {
      return;
    }

    for (final LovenseConnectionProfile profile in activeProfiles) {
      final LovenseLiveConnectionConfig? config = _liveConnectionConfigOrNull(
        profile: profile,
      );
      final Set<String> selectedIds = profile.selectedDeviceIds;
      if (config == null || selectedIds.isEmpty) {
        continue;
      }
      try {
        await _lovenseLiveClient.stopDevices(
          config: config,
          toyIds: selectedIds.toList(),
        );
        _appendLog(
          ExecutionLogEntry.info(
            'Lovense live stop',
            '${profile.displayLabel} | ${selectedIds.length} device(s) | $reason | '
                'video ${formatMs(positionMs)}',
          ),
          refresh: false,
        );
      } catch (error) {
        _appendLog(
          ExecutionLogEntry.error(
            'Lovense live stop failed',
            '${profile.displayLabel} | $error',
          ),
        );
      }
    }
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
    _updateSelectedLovenseProfile(
      (LovenseConnectionProfile current) =>
          current.copyWith(rulesText: rulesText),
    );
    setState(() {
      _lovenseMockClient.updateRules(rulesText);
    });
    _refreshLovenseLiveRuleValidation();
  }

  void _resetLovenseMockRules() {
    _lovenseRulesController.text = LovenseMockRuleScript.defaultSource;
    _updateLovenseMockRules(_lovenseRulesController.text);
  }

  PlaylistEntryData _currentEntrySnapshot() {
    final Set<String> knownProfileIds = _lovenseProfiles
        .map((LovenseConnectionProfile profile) => profile.id)
        .toSet();
    final List<String> activeProfiles = _activeLovenseProfileIds()
        .where((String id) => knownProfileIds.contains(id))
        .toList();
    final String normalizedVideoPath = _videoPath.trim();
    final String normalizedVideoName = _videoName.trim().isEmpty
        ? _pathFileName(normalizedVideoPath)
        : _videoName.trim();
    final String normalizedFunscriptPath = _funscriptPath.trim();
    final String normalizedFunscriptName = _funscriptName.trim().isEmpty
        ? _pathFileName(normalizedFunscriptPath)
        : _funscriptName.trim();
    return PlaylistEntryData(
      videoPath: normalizedVideoPath,
      videoName: normalizedVideoName,
      funscriptPath: normalizedFunscriptPath,
      funscriptName: normalizedFunscriptName,
      activeLovenseProfileIds: activeProfiles,
      videoSource: PlaylistMediaReference.fromLegacy(
        kind: 'videos',
        path: normalizedVideoPath,
        name: normalizedVideoName,
      ),
      funscriptSource: PlaylistMediaReference.fromLegacy(
        kind: 'funscripts',
        path: normalizedFunscriptPath,
        name: normalizedFunscriptName,
      ),
      embeddedFunscriptDocument: _funscript == null
          ? null
          : _cloneJsonMap(_funscript!.document),
      executionMode: _lovenseExecutionMode == LovenseExecutionMode.live
          ? 'lovense-live'
          : 'lovense-test',
      rulesText: _lovenseRulesController.text.trim(),
    );
  }

  LovenseExecutionMode? _parseFhplayerExecutionMode(Object? value) {
    final String normalized = value == null
        ? ''
        : value.toString().trim().toLowerCase();
    if (normalized == 'live' ||
        normalized == 'lovense-live' ||
        normalized == 'lovense-rules') {
      return LovenseExecutionMode.live;
    }
    if (normalized == 'test' || normalized == 'lovense-test') {
      return LovenseExecutionMode.test;
    }
    return null;
  }

  FhplayerScriptSettings _extractFhplayerScriptSettings(
    Map<String, dynamic> document,
  ) {
    final Map<String, dynamic> metadata = _readJsonMap(document['metadata']);
    final Map<String, dynamic> metadataFhplayer = _readJsonMap(
      metadata['fhplayer'],
    );
    final Map<String, dynamic> metadataFhPlayer = _readJsonMap(
      metadata['fh_player'],
    );
    final Map<String, dynamic> rootFhplayer = _readJsonMap(
      document['fhplayer'],
    );
    final Map<String, dynamic> execution = _readJsonMap(document['execution']);
    final Map<String, dynamic> executionLovense = _readJsonMap(
      execution['lovense'],
    );
    final List<Map<String, dynamic>> lovenseCandidates = <Map<String, dynamic>>[
      _readJsonMap(metadataFhplayer['lovense']),
      _readJsonMap(metadataFhPlayer['lovense']),
      _readJsonMap(rootFhplayer['lovense']),
      _readJsonMap(document['lovense']),
      executionLovense,
    ];
    Map<String, dynamic> lovense = <String, dynamic>{};
    for (final Map<String, dynamic> candidate in lovenseCandidates) {
      if (candidate.isNotEmpty) {
        lovense = candidate;
        break;
      }
    }

    final String rulesText = _firstNonEmptyString(<Object?>[
      metadataFhplayer['rulesText'],
      metadataFhPlayer['rulesText'],
      rootFhplayer['rulesText'],
      execution['rulesText'],
      document['rulesText'],
    ]);
    final String selectedConnectionId = _firstNonEmptyString(<Object?>[
      lovense['selectedConnectionId'],
      lovense['selectedProfileId'],
      lovense['selectedConnection'],
    ]);
    final List<String> activeConnectionIds = _readStringList(
      lovense['activeConnectionIds'] ?? document['activeLovenseProfileIds'],
    );
    final Map<String, String> rulesByConnectionId = <String, String>{};
    final Object? rawConnectionRules = lovense['connectionRules'];
    if (rawConnectionRules is List) {
      for (final Object? item in rawConnectionRules) {
        final Map<String, dynamic> map = _readJsonMap(item);
        final String connectionId = _firstNonEmptyString(<Object?>[
          map['connectionId'],
          map['id'],
        ]);
        final String connectionRulesText = _firstNonEmptyString(<Object?>[
          map['rulesText'],
        ]);
        if (connectionId.isNotEmpty && connectionRulesText.isNotEmpty) {
          rulesByConnectionId[connectionId] = connectionRulesText;
        }
      }
    }

    final List<LovenseConnectionProfile> connections =
        <LovenseConnectionProfile>[];
    final Object? rawConnections = lovense['connections'];
    if (rawConnections is List) {
      for (final Object? rawConnection in rawConnections) {
        final Map<String, dynamic> connection = _readJsonMap(rawConnection);
        final String id = _firstNonEmptyString(<Object?>[
          connection['id'],
          connection['connectionId'],
        ]);
        if (id.isEmpty) {
          continue;
        }
        final String profileRules = _firstNonEmptyString(<Object?>[
          rulesByConnectionId[id],
          connection['rulesText'],
          rulesText,
          LovenseMockRuleScript.defaultSource,
        ]);
        connections.add(
          LovenseConnectionProfile(
            id: id,
            label: _firstNonEmptyString(<Object?>[
              connection['label'],
              connection['name'],
              id,
            ]),
            scheme:
                _firstNonEmptyString(<Object?>[
                      connection['scheme'],
                      'https',
                    ]).toLowerCase() ==
                    'http'
                ? 'http'
                : 'https',
            host: _firstNonEmptyString(<Object?>[
              connection['host'],
              '127.0.0.1',
            ]),
            port: _firstNonEmptyString(<Object?>[connection['port'], '30010']),
            platformName: _firstNonEmptyString(<Object?>[
              connection['platformName'],
              'FHPlayer',
            ]),
            rulesText: profileRules,
          ),
        );
      }
    }

    final LovenseExecutionMode? executionMode = _parseFhplayerExecutionMode(
      _firstNonEmptyString(<Object?>[
        metadataFhplayer['executionMode'],
        metadataFhPlayer['executionMode'],
        rootFhplayer['executionMode'],
        execution['mode'],
        document['executionMode'],
      ]),
    );

    return FhplayerScriptSettings(
      executionMode: executionMode,
      rulesText: rulesText,
      selectedConnectionId: selectedConnectionId,
      activeConnectionIds: activeConnectionIds,
      rulesByConnectionId: rulesByConnectionId,
      connections: connections,
    );
  }

  void _applyFhplayerScriptSettings(
    FhplayerScriptSettings settings, {
    bool persist = true,
  }) {
    if (!settings.hasSettings) {
      return;
    }

    final List<LovenseConnectionProfile> mergedProfiles =
        List<LovenseConnectionProfile>.from(_lovenseProfiles);
    for (final LovenseConnectionProfile parsedProfile in settings.connections) {
      final int existingIndex = mergedProfiles.indexWhere(
        (LovenseConnectionProfile profile) => profile.id == parsedProfile.id,
      );
      if (existingIndex >= 0) {
        final LovenseConnectionProfile current = mergedProfiles[existingIndex];
        mergedProfiles[existingIndex] = current.copyWith(
          label: parsedProfile.label.trim().isEmpty
              ? current.label
              : parsedProfile.label,
          scheme: parsedProfile.scheme,
          host: parsedProfile.host,
          port: parsedProfile.port,
          platformName: parsedProfile.platformName,
          rulesText: parsedProfile.rulesText.trim().isEmpty
              ? current.rulesText
              : parsedProfile.rulesText,
        );
      } else {
        mergedProfiles.add(parsedProfile);
      }
    }

    if (settings.rulesByConnectionId.isNotEmpty) {
      for (int index = 0; index < mergedProfiles.length; index += 1) {
        final LovenseConnectionProfile profile = mergedProfiles[index];
        final String? rulesText = settings.rulesByConnectionId[profile.id];
        if (rulesText == null || rulesText.trim().isEmpty) {
          continue;
        }
        mergedProfiles[index] = profile.copyWith(rulesText: rulesText.trim());
      }
    }

    final Set<String> availableIds = mergedProfiles
        .map((LovenseConnectionProfile profile) => profile.id)
        .toSet();
    String selectedId = _firstNonEmptyString(<Object?>[
      settings.selectedConnectionId,
      _lovenseSelectedProfileId,
      mergedProfiles.isEmpty ? '' : mergedProfiles.first.id,
    ]);
    if (!availableIds.contains(selectedId)) {
      selectedId = mergedProfiles.isEmpty ? '' : mergedProfiles.first.id;
    }

    final bool hasActiveDirective =
        settings.activeConnectionIds.isNotEmpty ||
        settings.selectedConnectionId.trim().isNotEmpty;
    final Set<String> activeIds = hasActiveDirective
        ? settings.activeConnectionIds.where(availableIds.contains).toSet()
        : _activeLovenseProfileIds().where(availableIds.contains).toSet();
    if (hasActiveDirective && activeIds.isEmpty && selectedId.isNotEmpty) {
      activeIds.add(selectedId);
    }

    if (settings.rulesText.trim().isNotEmpty && selectedId.isNotEmpty) {
      final int selectedIndex = mergedProfiles.indexWhere(
        (LovenseConnectionProfile profile) => profile.id == selectedId,
      );
      if (selectedIndex >= 0 &&
          !settings.rulesByConnectionId.containsKey(selectedId)) {
        mergedProfiles[selectedIndex] = mergedProfiles[selectedIndex].copyWith(
          rulesText: settings.rulesText.trim(),
        );
      }
    }

    setState(() {
      _lovenseProfiles = mergedProfiles;
      _lovenseSelectedProfileId = selectedId;
      if (settings.executionMode != null) {
        _lovenseLiveEnabled =
            settings.executionMode == LovenseExecutionMode.live;
      }
      _applyActiveProfileIdsToCurrentContext(activeIds);
    });
    _syncControllersFromSelectedLovenseProfile();
    _syncRulesControllerFromSelectedLovenseProfile();
    _refreshLovenseLiveRuleValidation();
    if (persist) {
      unawaited(_saveLocalSettings());
    }
  }

  void _applyPlaylistEntryExecutionSettings(PlaylistEntryData entry) {
    final LovenseExecutionMode? mode = _parseFhplayerExecutionMode(
      entry.executionMode,
    );
    if (mode != null) {
      _setLovenseExecutionMode(mode, persist: false);
    }
    final String rulesText = entry.rulesText.trim();
    if (rulesText.isNotEmpty) {
      _updateSelectedLovenseProfile(
        (LovenseConnectionProfile current) =>
            current.copyWith(rulesText: rulesText),
        persist: false,
      );
      _syncRulesControllerFromSelectedLovenseProfile();
    }
  }

  Map<String, dynamic> _buildCleanFunscriptDocument(
    Map<String, dynamic> source,
  ) {
    final Map<String, dynamic> cleaned = _cloneJsonMap(source);
    final Map<String, dynamic> metadata = _readJsonMap(cleaned['metadata']);
    if (metadata.isNotEmpty) {
      metadata.remove('fhplayer');
      metadata.remove('fh_player');
      if (metadata.isEmpty) {
        cleaned.remove('metadata');
      } else {
        cleaned['metadata'] = metadata;
      }
    }
    cleaned.remove('fhplayer');
    cleaned.remove('lovense');
    cleaned.remove('executionMode');
    cleaned.remove('rulesText');
    cleaned.remove('execution');
    return cleaned;
  }

  Future<void> _loadFunscriptFromDocument(
    Map<String, dynamic> document, {
    required String sourceName,
    String sourcePath = '',
    bool appendSuccessLog = true,
    bool applyScriptSettings = true,
  }) async {
    final Funscript script = Funscript.fromJson(
      document,
      sourceName: sourceName,
      sourcePath: sourcePath,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _funscript = script;
      _funscriptPath = sourcePath.trim();
      _funscriptName = sourceName.trim();
      _resetTimingStats();
      _funscriptCursor.setScript(
        script,
        positionMs: _currentPosition.inMilliseconds,
        includeCurrentAction: true,
      );
    });
    if (applyScriptSettings) {
      final FhplayerScriptSettings settings = _extractFhplayerScriptSettings(
        script.document,
      );
      _applyFhplayerScriptSettings(settings);
    }
    if (appendSuccessLog) {
      _appendLog(
        ExecutionLogEntry.success(
          'Funscript loaded',
          '${script.actions.length} actions from $_funscriptName',
        ),
      );
    }
  }

  Future<void> _loadFunscriptFromPath(
    String path, {
    String? sourceName,
    bool appendSuccessLog = true,
    bool applyScriptSettings = true,
  }) async {
    final String content = await File(path).readAsString();
    final String resolvedSourceName =
        (sourceName ?? File(path).uri.pathSegments.last).trim();
    final Object? rawDocument = jsonDecode(content);
    if (rawDocument is! Map) {
      throw const FormatException('Invalid funscript JSON object.');
    }
    await _loadFunscriptFromDocument(
      Map<String, dynamic>.from(rawDocument),
      sourceName: resolvedSourceName,
      sourcePath: path.trim(),
      appendSuccessLog: appendSuccessLog,
      applyScriptSettings: applyScriptSettings,
    );
  }

  String _buildLibraryFilePath(String kind, String fileName) {
    final String normalizedKind = _normalizePlaylistLibraryKind(kind);
    final String normalizedFileName = fileName.trim();
    if (normalizedFileName.isEmpty) {
      return '';
    }
    final String directory = normalizedKind == 'videos'
        ? _libraryVideosPath
        : _libraryFunscriptsPath;
    return '$directory${Platform.pathSeparator}$normalizedFileName';
  }

  List<String> _buildMediaPathCandidates({
    required PlaylistEntryData entry,
    required String kind,
  }) {
    final Set<String> seen = <String>{};
    final List<String> candidates = <String>[];
    void addCandidate(String candidate) {
      final String normalized = candidate.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        return;
      }
      candidates.add(normalized);
    }

    final bool isVideo = _normalizePlaylistLibraryKind(kind) == 'videos';
    final PlaylistMediaReference source = isVideo
        ? entry.effectiveVideoSource
        : entry.effectiveFunscriptSource;
    addCandidate(isVideo ? entry.videoPath : entry.funscriptPath);
    addCandidate(source.path);
    final String preferredLibraryName = _firstNonEmptyString(<Object?>[
      source.resolvedLibraryName,
      source.name,
      isVideo ? entry.videoName : entry.funscriptName,
      _pathFileName(isVideo ? entry.videoPath : entry.funscriptPath),
    ]);
    if (preferredLibraryName.isNotEmpty) {
      addCandidate(_buildLibraryFilePath(kind, preferredLibraryName));
    }
    return candidates;
  }

  Future<String?> _resolveFirstExistingFilePath(List<String> candidates) async {
    for (final String candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _loadPlaylistEntryAt(int index) async {
    if (index < 0 || index >= _playlistEntries.length) {
      return;
    }
    final PlaylistEntryData entry = _playlistEntries[index];
    final List<String> videoCandidates = _buildMediaPathCandidates(
      entry: entry,
      kind: 'videos',
    );
    final List<String> funscriptCandidates = _buildMediaPathCandidates(
      entry: entry,
      kind: 'funscripts',
    );
    final String? resolvedVideoPath = await _resolveFirstExistingFilePath(
      videoCandidates,
    );
    final String? resolvedFunscriptPath = await _resolveFirstExistingFilePath(
      funscriptCandidates,
    );
    final bool hasEmbeddedFunscript =
        entry.embeddedFunscriptDocument != null &&
        entry.embeddedFunscriptDocument!['actions'] is List;

    if (resolvedVideoPath == null ||
        (resolvedFunscriptPath == null && !hasEmbeddedFunscript)) {
      final List<String> missingDetails = <String>[];
      if (resolvedVideoPath == null) {
        missingDetails.add(
          'video: ${videoCandidates.isEmpty ? '(no candidates)' : videoCandidates.join(' | ')}',
        );
      }
      if (resolvedFunscriptPath == null && !hasEmbeddedFunscript) {
        missingDetails.add(
          'funscript: ${funscriptCandidates.isEmpty ? '(no candidates)' : funscriptCandidates.join(' | ')}',
        );
      }
      _appendLog(
        ExecutionLogEntry.error(
          'Playlist entry unavailable',
          'Missing file(s): ${missingDetails.join(' ; ')}',
        ),
      );
      return;
    }

    if (mounted) {
      final Set<String> availableProfileIds = _lovenseProfiles
          .map((LovenseConnectionProfile profile) => profile.id)
          .toSet();
      final List<String> entryActiveIds = entry.activeLovenseProfileIds
          .where((String id) => availableProfileIds.contains(id))
          .toList();
      final String fallbackProfileId = _selectedLovenseProfile.id;
      final Set<String> activeIds = entryActiveIds.isEmpty
          ? <String>{fallbackProfileId}
          : entryActiveIds.toSet();
      setState(() {
        _selectedPlaylistIndex = index;
        _lovenseFormActiveProfileIds = activeIds;
      });
      _applyPlaylistEntryExecutionSettings(entry);
    }
    final String resolvedVideoName = entry.videoName.trim().isEmpty
        ? _pathFileName(resolvedVideoPath)
        : entry.videoName.trim();
    final String resolvedFunscriptName = entry.funscriptName.trim().isEmpty
        ? _pathFileName(resolvedFunscriptPath ?? '')
        : entry.funscriptName.trim();
    if (resolvedFunscriptPath != null) {
      await _loadFunscriptFromPath(
        resolvedFunscriptPath,
        sourceName: resolvedFunscriptName,
        appendSuccessLog: false,
        applyScriptSettings: false,
      );
    } else {
      await _loadFunscriptFromDocument(
        _cloneJsonMap(entry.embeddedFunscriptDocument!),
        sourceName: resolvedFunscriptName.isEmpty
            ? 'playlist-entry.funscript'
            : resolvedFunscriptName,
        sourcePath: '',
        appendSuccessLog: false,
        applyScriptSettings: false,
      );
      _appendLog(
        ExecutionLogEntry.info(
          'Playlist funscript fallback',
          'Loaded embedded funscript for ${entry.title}.',
        ),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _playlistEntries[index] = entry.copyWith(
        videoPath: resolvedVideoPath,
        videoName: resolvedVideoName,
        funscriptPath: resolvedFunscriptPath ?? '',
        funscriptName: resolvedFunscriptName,
        videoSource: entry.effectiveVideoSource.copyWith(
          kind: 'videos',
          source: 'path',
          name: resolvedVideoName,
          path: resolvedVideoPath,
          libraryName: _firstNonEmptyString(<Object?>[
            entry.effectiveVideoSource.resolvedLibraryName,
            resolvedVideoName,
          ]),
        ),
        funscriptSource: entry.effectiveFunscriptSource.copyWith(
          kind: 'funscripts',
          source: resolvedFunscriptPath == null ? 'embedded' : 'path',
          name: resolvedFunscriptName,
          path: resolvedFunscriptPath ?? '',
          libraryName: _firstNonEmptyString(<Object?>[
            entry.effectiveFunscriptSource.resolvedLibraryName,
            resolvedFunscriptName,
          ]),
        ),
      );
    });
    setState(() {
      _videoPath = resolvedVideoPath;
      _videoName = resolvedVideoName;
      _videoInitializing = true;
      _videoError = '';
    });
    await _initializeVideo(resolvedVideoPath);
    _appendLog(
      ExecutionLogEntry.success(
        'Playlist entry loaded',
        '${entry.title} | ${resolvedFunscriptPath == null ? '$resolvedFunscriptName (embedded)' : resolvedFunscriptName}',
      ),
    );
  }

  Future<void> _addCurrentToPlaylist() async {
    if (!_hasLoadedEntry) {
      _appendLog(
        ExecutionLogEntry.error(
          'Playlist not updated',
          'Load a video and a funscript before adding an entry.',
        ),
      );
      return;
    }
    final PlaylistEntryData entry = _currentEntrySnapshot();
    setState(() {
      _playlistEntries.add(entry);
      _selectedPlaylistIndex = _playlistEntries.length - 1;
    });
    _appendLog(ExecutionLogEntry.success('Playlist updated', 'Added 1 entry.'));
  }

  void _saveSelectedPlaylistEntry() {
    if (!_hasLoadedEntry) {
      _appendLog(
        ExecutionLogEntry.error(
          'Playlist entry not saved',
          'Load a video and a funscript first.',
        ),
      );
      return;
    }
    if (!_hasSelectedPlaylistEntry) {
      _appendLog(
        ExecutionLogEntry.error(
          'Playlist entry not saved',
          'Select a playlist entry first.',
        ),
      );
      return;
    }
    final PlaylistEntryData entry = _currentEntrySnapshot();
    setState(() {
      _playlistEntries[_selectedPlaylistIndex] = entry;
    });
    _appendLog(
      ExecutionLogEntry.success(
        'Playlist entry saved',
        '${entry.title} updated.',
      ),
    );
  }

  Future<void> _saveCurrentFunscript() async {
    final Funscript? script = _funscript;
    if (script == null) {
      _appendLog(
        ExecutionLogEntry.error(
          'Funscript not saved',
          'Load a funscript first.',
        ),
      );
      return;
    }
    final String defaultName = _funscriptName.isEmpty
        ? 'export.funscript'
        : _funscriptName;
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save funscript',
      fileName: defaultName,
      allowedExtensions: <String>['funscript', 'json'],
      type: FileType.custom,
      initialDirectory: _libraryFunscriptsPath,
    );
    if (outputPath == null || outputPath.trim().isEmpty) {
      return;
    }
    final File outputFile = File(outputPath);
    if (await outputFile.exists()) {
      final bool confirmed = await _confirmAction(
        title: 'Overwrite funscript file',
        body: 'The file already exists.\n\n$outputPath\n\nOverwrite it?',
        confirmLabel: 'Overwrite',
        destructive: true,
      );
      if (!confirmed) {
        _appendLog(
          ExecutionLogEntry.info(
            'Funscript save cancelled',
            'Existing file was not overwritten.',
          ),
        );
        return;
      }
    }
    final Map<String, dynamic> payload = _buildCleanFunscriptDocument(
      _cloneJsonMap(script.document),
    );
    await File(
      outputPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    _appendLog(ExecutionLogEntry.success('Funscript saved', outputPath));
  }

  Future<void> _loadSelectedPlaylistEntry() async {
    if (!_hasSelectedPlaylistEntry) {
      _appendLog(
        ExecutionLogEntry.error(
          'No playlist entry selected',
          'Select an entry first.',
        ),
      );
      return;
    }
    await _loadPlaylistEntryAt(_selectedPlaylistIndex);
  }

  int _resolveNextPlaylistIndex() {
    if (_playlistEntries.isEmpty) {
      return -1;
    }
    if (_playlistMode == PlaylistMode.random) {
      if (_playlistEntries.length == 1) {
        return 0;
      }
      int next = _playlistRandom.nextInt(_playlistEntries.length);
      if (_hasSelectedPlaylistEntry && next == _selectedPlaylistIndex) {
        next = (next + 1) % _playlistEntries.length;
      }
      return next;
    }
    if (!_hasSelectedPlaylistEntry) {
      return 0;
    }
    return (_selectedPlaylistIndex + 1) % _playlistEntries.length;
  }

  Future<void> _loadNextPlaylistEntry() async {
    final int nextIndex = _resolveNextPlaylistIndex();
    if (nextIndex < 0) {
      _appendLog(
        ExecutionLogEntry.error('No next video', 'The playlist is empty.'),
      );
      return;
    }
    await _loadPlaylistEntryAt(nextIndex);
  }

  Future<void> _loadPreviousPlaylistEntry() async {
    if (_playlistEntries.isEmpty) {
      _appendLog(
        ExecutionLogEntry.error('No previous video', 'The playlist is empty.'),
      );
      return;
    }
    final int previousIndex;
    if (!_hasSelectedPlaylistEntry) {
      previousIndex = 0;
    } else {
      previousIndex =
          (_selectedPlaylistIndex - 1 + _playlistEntries.length) %
          _playlistEntries.length;
    }
    await _loadPlaylistEntryAt(previousIndex);
  }

  Future<void> _removeSelectedPlaylistEntry() async {
    if (!_hasSelectedPlaylistEntry) {
      _appendLog(
        ExecutionLogEntry.error(
          'No playlist entry selected',
          'Select an entry first.',
        ),
      );
      return;
    }
    final PlaylistEntryData removed = _playlistEntries[_selectedPlaylistIndex];
    final bool confirmed = await _confirmAction(
      title: 'Remove playlist entry',
      body: 'Remove "${removed.title}" from the current playlist?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    setState(() {
      _playlistEntries.removeAt(_selectedPlaylistIndex);
      if (_playlistEntries.isEmpty) {
        _selectedPlaylistIndex = -1;
      } else if (_selectedPlaylistIndex >= _playlistEntries.length) {
        _selectedPlaylistIndex = _playlistEntries.length - 1;
      }
    });
    _appendLog(ExecutionLogEntry.info('Playlist entry removed', removed.title));
  }

  Future<void> _clearPlaylist() async {
    if (_playlistEntries.isEmpty) {
      return;
    }
    final bool confirmed = await _confirmAction(
      title: 'Clear playlist',
      body:
          'This will remove all ${_playlistEntries.length} entries from the current playlist. Continue?',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    final int removed = _playlistEntries.length;
    setState(() {
      _playlistEntries.clear();
      _selectedPlaylistIndex = -1;
    });
    _appendLog(
      ExecutionLogEntry.info('Playlist cleared', 'Removed $removed entries.'),
    );
  }

  PlaylistMode _parsePlaylistMode(Object? value) {
    final String modeRaw = value == null
        ? ''
        : value.toString().trim().toLowerCase();
    if (modeRaw == PlaylistMode.random.name) {
      return PlaylistMode.random;
    }
    return PlaylistMode.sequential;
  }

  String _normalizeExecutionModeForSave(String mode) {
    final String normalized = mode.trim().toLowerCase();
    if (normalized == 'live') {
      return 'lovense-live';
    }
    if (normalized == 'test') {
      return 'lovense-test';
    }
    if (normalized == 'lovense-live' || normalized == 'lovense-test') {
      return normalized;
    }
    return _lovenseExecutionMode == LovenseExecutionMode.live
        ? 'lovense-live'
        : 'lovense-test';
  }

  PlaylistMediaReference _buildMediaSourceForSave({
    required PlaylistMediaReference source,
    required String kind,
    required String fallbackName,
    required String fallbackPath,
  }) {
    final String normalizedName = _firstNonEmptyString(<Object?>[
      source.name,
      fallbackName,
      _pathFileName(fallbackPath),
    ]);
    final String normalizedPath = _firstNonEmptyString(<Object?>[
      source.path,
      fallbackPath,
    ]);
    final String normalizedLibraryName = _firstNonEmptyString(<Object?>[
      source.resolvedLibraryName,
      normalizedName,
    ]);
    final String normalizedSource = _firstNonEmptyString(<Object?>[
      source.source,
      normalizedPath.isEmpty ? 'library' : 'path',
    ]);
    return source.copyWith(
      kind: _normalizePlaylistLibraryKind(kind),
      name: normalizedName,
      path: normalizedPath,
      libraryName: normalizedLibraryName,
      source: normalizedSource,
    );
  }

  Map<String, dynamic> _buildDefaultFunscriptDocument() {
    return <String, dynamic>{
      'version': '1.0',
      'inverted': false,
      'range': 100,
      'actions': <Map<String, int>>[],
    };
  }

  Future<Map<String, dynamic>> _loadEntryFunscriptDocumentForSave(
    PlaylistEntryData entry,
  ) async {
    final String path = entry.funscriptPath.trim();
    if (path.isNotEmpty) {
      try {
        final String content = await File(path).readAsString();
        final Object? raw = jsonDecode(content);
        if (raw is Map<String, dynamic>) {
          return _buildCleanFunscriptDocument(_cloneJsonMap(raw));
        }
      } catch (_) {
        // Keep fallback chain below.
      }
    }
    if (entry.embeddedFunscriptDocument != null) {
      return _buildCleanFunscriptDocument(
        _cloneJsonMap(entry.embeddedFunscriptDocument!),
      );
    }
    if (_funscript != null) {
      final bool pathMatches = path.isNotEmpty && path == _funscriptPath.trim();
      final bool nameMatches =
          entry.funscriptName.trim().isNotEmpty &&
          entry.funscriptName.trim() == _funscriptName.trim();
      if (pathMatches || nameMatches) {
        return _buildCleanFunscriptDocument(
          _cloneJsonMap(_funscript!.document),
        );
      }
    }
    return _buildDefaultFunscriptDocument();
  }

  Map<String, dynamic> _buildSavedPlaylistLovense() {
    final String selectedConnectionId = _firstNonEmptyString(<Object?>[
      _lovenseSelectedProfileId,
      _lovenseProfiles.isEmpty ? '' : _lovenseProfiles.first.id,
    ]);
    return <String, dynamic>{
      'selectedConnectionId': selectedConnectionId,
      'connections': <Map<String, dynamic>>[
        for (final LovenseConnectionProfile profile in _lovenseProfiles)
          <String, dynamic>{
            'id': profile.id,
            'label': profile.label,
            'scheme': profile.scheme,
            'host': profile.host,
            'port': profile.port,
            'platformName': profile.platformName,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> _buildSavedPlaylistDocument({
    required List<PlaylistEntryData> entries,
  }) async {
    final List<Map<String, dynamic>> savedEntries = <Map<String, dynamic>>[];
    for (int index = 0; index < entries.length; index += 1) {
      final PlaylistEntryData entry = entries[index];
      final PlaylistMediaReference videoSource = _buildMediaSourceForSave(
        source: entry.effectiveVideoSource,
        kind: 'videos',
        fallbackName: entry.videoName,
        fallbackPath: entry.videoPath,
      );
      final PlaylistMediaReference funscriptSource = _buildMediaSourceForSave(
        source: entry.effectiveFunscriptSource,
        kind: 'funscripts',
        fallbackName: entry.funscriptName,
        fallbackPath: entry.funscriptPath,
      );
      final Map<String, dynamic> funscriptDocument =
          await _loadEntryFunscriptDocumentForSave(entry);
      final Set<String> availableProfileIds = _lovenseProfiles
          .map((LovenseConnectionProfile profile) => profile.id)
          .toSet();
      final List<String> activeProfileIds = entry.activeLovenseProfileIds
          .where((String id) => availableProfileIds.contains(id))
          .toList();
      final String selectedConnectionId = _firstNonEmptyString(<Object?>[
        activeProfileIds.isEmpty ? '' : activeProfileIds.first,
        _lovenseSelectedProfileId,
      ]);
      savedEntries.add(<String, dynamic>{
        'title': entry.title.trim().isEmpty
            ? 'Playlist entry ${index + 1}'
            : entry.title.trim(),
        'video': videoSource.toJson(),
        'funscript': <String, dynamic>{
          ...funscriptSource.toJson(),
          'document': funscriptDocument,
        },
        'execution': <String, dynamic>{
          'mode': _normalizeExecutionModeForSave(entry.executionMode),
          'rulesText': entry.rulesText.trim(),
          'lovense': <String, dynamic>{
            'selectedConnectionId': selectedConnectionId,
            'activeConnectionIds': activeProfileIds,
            'connectionRules': <Map<String, dynamic>>[
              for (final LovenseConnectionProfile profile in _lovenseProfiles)
                <String, dynamic>{
                  'connectionId': profile.id,
                  'rulesText': profile.rulesText.trim(),
                },
            ],
          },
        },
      });
    }
    return <String, dynamic>{
      'schemaVersion': kPlaylistSchemaVersion,
      'type': kPlaylistType,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'playbackMode': _playlistMode.name,
      'lovense': _buildSavedPlaylistLovense(),
      'entries': savedEntries,
    };
  }

  bool _entryHasVideoReference(PlaylistEntryData entry) {
    final PlaylistMediaReference source = entry.effectiveVideoSource;
    return entry.videoPath.trim().isNotEmpty ||
        source.path.trim().isNotEmpty ||
        source.name.trim().isNotEmpty ||
        source.resolvedLibraryName.trim().isNotEmpty ||
        entry.videoName.trim().isNotEmpty;
  }

  bool _entryHasFunscriptReference(PlaylistEntryData entry) {
    final PlaylistMediaReference source = entry.effectiveFunscriptSource;
    final bool hasEmbeddedDocument =
        entry.embeddedFunscriptDocument != null &&
        entry.embeddedFunscriptDocument!['actions'] is List;
    return hasEmbeddedDocument ||
        entry.funscriptPath.trim().isNotEmpty ||
        source.path.trim().isNotEmpty ||
        source.name.trim().isNotEmpty ||
        source.resolvedLibraryName.trim().isNotEmpty ||
        entry.funscriptName.trim().isNotEmpty;
  }

  void _validatePlaylistDocumentSchema(Map<String, dynamic> json) {
    final String type = _firstNonEmptyString(<Object?>[json['type']]);
    if (type.isNotEmpty && type != kPlaylistType) {
      throw FormatException('Unsupported playlist type: $type');
    }
    final Object? schemaRaw = json['schemaVersion'] ?? json['schema_version'];
    if (schemaRaw == null) {
      return;
    }
    final int? schemaVersion = int.tryParse(schemaRaw.toString());
    if (schemaVersion == null || schemaVersion < 1) {
      throw FormatException('Invalid playlist schema version: $schemaRaw');
    }
    if (schemaVersion > kPlaylistSchemaVersion) {
      throw FormatException(
        'Unsupported playlist schema version: $schemaVersion',
      );
    }
  }

  Future<void> _saveExternalPlaylist() async {
    if (_playlistEntries.isEmpty) {
      _appendLog(
        ExecutionLogEntry.error(
          'Playlist not saved',
          'Add at least one playlist entry first.',
        ),
      );
      return;
    }
    final String? outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save playlist',
      fileName: 'playlist.fhplaylist',
      allowedExtensions: <String>['fhplaylist', 'json'],
      type: FileType.custom,
      initialDirectory: _libraryExportsPath,
    );
    if (outputPath == null || outputPath.trim().isEmpty) {
      return;
    }
    final File outputFile = File(outputPath);
    if (await outputFile.exists()) {
      final bool confirmed = await _confirmAction(
        title: 'Overwrite playlist file',
        body: 'The file already exists.\n\n$outputPath\n\nOverwrite it?',
        confirmLabel: 'Overwrite',
        destructive: true,
      );
      if (!confirmed) {
        _appendLog(
          ExecutionLogEntry.info(
            'Playlist save cancelled',
            'Existing file was not overwritten.',
          ),
        );
        return;
      }
    }
    final Map<String, dynamic> payload = await _buildSavedPlaylistDocument(
      entries: _playlistEntries,
    );
    await File(
      outputPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    _appendLog(ExecutionLogEntry.success('Playlist saved', outputPath));
  }

  Future<void> _loadExternalPlaylist() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['fhplaylist', 'json'],
      withData: true,
      initialDirectory: _libraryExportsPath,
    );
    final PlatformFile? file = result?.files.single;
    if (file == null) {
      return;
    }
    await _loadExternalPlaylistFile(file);
  }

  Future<void> _loadExternalPlaylistFile(PlatformFile file) async {
    try {
      if (_playlistEntries.isNotEmpty) {
        final bool confirmed = await _confirmAction(
          title: 'Load playlist',
          body:
              'Loading "${file.name}" will replace the current playlist (${_playlistEntries.length} entries). Continue?',
          confirmLabel: 'Load and replace',
        );
        if (!confirmed) {
          _appendLog(
            ExecutionLogEntry.info(
              'Playlist load cancelled',
              'Kept current playlist.',
            ),
          );
          return;
        }
      }
      final String content = await _readPickedTextFile(file);
      final Object? decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException(
          'Playlist file must contain a JSON object.',
        );
      }
      final Map<String, dynamic> json = Map<String, dynamic>.from(decoded);
      _validatePlaylistDocumentSchema(json);
      final Object? rawEntries = json['entries'];
      if (rawEntries is! List) {
        throw const FormatException('Missing entries array.');
      }
      final List<PlaylistEntryData> allEntries = <PlaylistEntryData>[
        for (final Object? raw in rawEntries)
          if (raw is Map)
            PlaylistEntryData.fromJson(Map<String, dynamic>.from(raw)),
      ];
      final List<PlaylistEntryData> parsed = allEntries.where((
        PlaylistEntryData entry,
      ) {
        return _entryHasVideoReference(entry) &&
            _entryHasFunscriptReference(entry);
      }).toList();
      if (parsed.isEmpty) {
        throw const FormatException('No usable playlist entries found.');
      }
      final int skippedEntries = allEntries.length - parsed.length;
      final PlaylistMode mode = _parsePlaylistMode(
        json['playbackMode'] ?? json['mode'],
      );
      setState(() {
        _playlistMode = mode;
        _playlistEntries
          ..clear()
          ..addAll(parsed);
        _selectedPlaylistIndex = _playlistEntries.isEmpty ? -1 : 0;
      });
      _appendLog(
        ExecutionLogEntry.success(
          'Playlist loaded',
          '${_playlistEntries.length} entries from ${file.name}',
        ),
      );
      if (skippedEntries > 0) {
        _appendLog(
          ExecutionLogEntry.info(
            'Playlist load notice',
            'Skipped $skippedEntries invalid entry(s).',
          ),
        );
      }
      if (_playlistEntries.isNotEmpty) {
        await _loadPlaylistEntryAt(_selectedPlaylistIndex);
      }
    } catch (error) {
      _appendLog(
        ExecutionLogEntry.error('Playlist load failed', error.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_fullscreenPlayerVisible) {
            return;
          }
          unawaited(_toggleFullscreenPlayer());
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: _fullscreenPlayerVisible
              ? _buildFullscreenPlayer()
              : Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: <Color>[
                        Color(0xFFF1E4D2),
                        AppColors.background,
                        AppColors.background,
                      ],
                      stops: <double>[0, 0.32, 1],
                    ),
                  ),
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1380),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                          child: LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  final bool wide =
                                      constraints.maxWidth >=
                                      _wideLayoutMinWidth;
                                  final bool splitHero =
                                      constraints.maxWidth >= 980;
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

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      _buildHeroSection(split: splitHero),
                                      const SizedBox(height: 20),
                                      if (wide)
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Expanded(child: mediaColumn),
                                            const SizedBox(width: 20),
                                            SizedBox(
                                              width: 410,
                                              child: sideColumn,
                                            ),
                                          ],
                                        )
                                      else
                                        Column(
                                          children: <Widget>[
                                            mediaColumn,
                                            const SizedBox(height: 20),
                                            sideColumn,
                                          ],
                                        ),
                                    ],
                                  );
                                },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroSection({required bool split}) {
    if (!split) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeroCopy(),
          const SizedBox(height: 16),
          _buildStatusCard(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 3, child: _buildHeroCopy()),
        const SizedBox(width: 20),
        Expanded(flex: 2, child: _buildStatusCard()),
      ],
    );
  }

  Widget _buildHeroCopy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'FHPLAYER',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.accentStrong,
            letterSpacing: 4.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Control playlists, videos, and\nfunscripts in sync',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 0.95,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 14),
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.muted,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
            children: const <InlineSpan>[
              TextSpan(text: 'Load multiple videos with their matching '),
              TextSpan(
                text: '.funscript',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  color: AppColors.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextSpan(
                text:
                    ' files, configure Lovense playback per entry, and play the playlist sequentially or randomly.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    final int pendingCount =
        _lovenseLiveDelayTimers.length + _lovenseLiveAutoStopTimers.length;
    final String playlistCount = _playlistEntries.length == 1
        ? '1 entries'
        : '${_playlistEntries.length} entries';
    final bool rulesActive = _lovenseRulesController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          _buildStatusLine('Backend', 'Connected'),
          _buildStatusLine('Playlist', playlistCount),
          _buildStatusLine('Mode', _playlistModeLabel),
          _buildStatusLine('Rule script', rulesActive ? 'Active' : 'Inactive'),
          _buildStatusLine('Pending triggers', '$pendingCount', isLast: true),
        ],
      ),
    );
  }

  Widget _buildStatusLine(String label, String value, {bool isLast = false}) {
    return Container(
      padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 12),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: isLast
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
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
    final List<Widget> lowerPanels = <Widget>[
      if (_showFunscriptOverviewPanel)
        _buildActionTablePanel(height: listPanelHeight),
      if (_showExecutionLogPanel) _buildLogPanel(height: listPanelHeight),
    ];
    return Column(
      children: <Widget>[
        _buildPlayerPanel(maxPlayerHeight: maxPlayerHeight),
        const SizedBox(height: 16),
        _buildPlaylistPanel(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool split = constraints.maxWidth >= _splitPanelsMinWidth;
            final Widget visiblePanels = _buildTimingStatePanel();
            final Widget libraryFolders = _buildLibraryFoldersPanel();
            final List<Widget> additionalPanels = <Widget>[
              if (_showUpdatesPanel) _buildUpdatesPanel(),
              if (_showDiagnosticsPanel) _buildTimingStatsPanel(),
            ];
            return Column(
              children: <Widget>[
                if (!split)
                  Column(
                    children: <Widget>[
                      visiblePanels,
                      const SizedBox(height: 16),
                      libraryFolders,
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: visiblePanels),
                      const SizedBox(width: 16),
                      Expanded(child: libraryFolders),
                    ],
                  ),
                if (additionalPanels.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  _buildPanelGrid(panels: additionalPanels, split: split),
                ],
              ],
            );
          },
        ),
        if (lowerPanels.isNotEmpty) const SizedBox(height: 16),
        if (lowerPanels.isNotEmpty)
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool split = constraints.maxWidth >= _splitPanelsMinWidth;
              return _buildPanelGrid(panels: lowerPanels, split: split);
            },
          ),
      ],
    );
  }

  Widget _buildPanelGrid({required List<Widget> panels, required bool split}) {
    if (panels.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!split) {
      return Column(
        children: <Widget>[
          for (int i = 0; i < panels.length; i += 1) ...<Widget>[
            panels[i],
            if (i < panels.length - 1) const SizedBox(height: 16),
          ],
        ],
      );
    }
    return Column(
      children: <Widget>[
        for (int i = 0; i < panels.length; i += 2) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: panels[i]),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < panels.length
                    ? panels[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (i + 2 < panels.length) const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildSideColumn() {
    return Column(
      children: <Widget>[
        _buildFilePanel(),
        const SizedBox(height: 16),
        _buildLovenseMockPanel(),
      ],
    );
  }

  Widget _buildPlaylistPanel() {
    final bool hasEntries = _playlistEntries.isNotEmpty;
    final String summary = hasEntries
        ? '${_playlistEntries.length} entries loaded. Current mode: $_playlistModeLabel'
        : 'No entries yet.';
    return Panel(
      title: 'Playlist',
      subtitle: summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: DropdownButtonFormField<PlaylistMode>(
              initialValue: _playlistMode,
              decoration: const InputDecoration(labelText: 'Playlist mode'),
              items: const <DropdownMenuItem<PlaylistMode>>[
                DropdownMenuItem<PlaylistMode>(
                  value: PlaylistMode.sequential,
                  child: Text('Sequential'),
                ),
                DropdownMenuItem<PlaylistMode>(
                  value: PlaylistMode.random,
                  child: Text('Random'),
                ),
              ],
              onChanged: (PlaylistMode? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _playlistMode = value;
                });
              },
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton(
                onPressed: _addCurrentToPlaylist,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Add to playlist'),
              ),
              TextButton(
                onPressed: _hasSelectedPlaylistEntry
                    ? _saveSelectedPlaylistEntry
                    : null,
                child: const Text('Save selected entry'),
              ),
              TextButton(
                onPressed: _funscript == null ? null : _saveCurrentFunscript,
                child: const Text('Save to funscript'),
              ),
              TextButton(
                onPressed: _resetTimingStats,
                child: const Text('Reset scheduler'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              TextButton(
                onPressed: _saveExternalPlaylist,
                child: const Text('Save external'),
              ),
              TextButton(
                onPressed: _loadExternalPlaylist,
                child: const Text('Load external'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton(
                onPressed: _hasSelectedPlaylistEntry
                    ? _loadSelectedPlaylistEntry
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Load selected video'),
              ),
              TextButton(
                onPressed: hasEntries ? _loadNextPlaylistEntry : null,
                child: const Text('Next video'),
              ),
              TextButton(
                onPressed: _hasSelectedPlaylistEntry
                    ? () {
                        unawaited(_removeSelectedPlaylistEntry());
                      }
                    : null,
                child: const Text('Remove entry'),
              ),
              TextButton(
                onPressed: hasEntries
                    ? () {
                        unawaited(_clearPlaylist());
                      }
                    : null,
                child: const Text('Clear playlist'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: hasEntries
                ? ListView.separated(
                    itemCount: _playlistEntries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final PlaylistEntryData entry = _playlistEntries[index];
                      final bool selected = index == _selectedPlaylistIndex;
                      return _buildPlaylistItem(
                        index: index,
                        entry: entry,
                        selected: selected,
                      );
                    },
                  )
                : const EmptyPanelMessage('No playlist entries loaded.'),
          ),
        ],
      ),
    );
  }

  String _formatEntryActiveUsers(PlaylistEntryData entry) {
    final Map<String, String> labels = <String, String>{
      for (final LovenseConnectionProfile profile in _lovenseProfiles)
        profile.id: profile.displayLabel,
    };
    final List<String> active = entry.activeLovenseProfileIds
        .where((String id) => labels.containsKey(id))
        .map((String id) => labels[id]!)
        .toList();
    if (active.isEmpty) {
      return 'No active users';
    }
    return active.join(', ');
  }

  void _setActiveLovenseProfileForPlaylistEntry({
    required int entryIndex,
    required String profileId,
    required bool active,
  }) {
    if (entryIndex < 0 || entryIndex >= _playlistEntries.length) {
      return;
    }
    final Set<String> availableProfileIds = _lovenseProfiles
        .map((LovenseConnectionProfile profile) => profile.id)
        .toSet();
    if (!availableProfileIds.contains(profileId)) {
      return;
    }
    final PlaylistEntryData current = _playlistEntries[entryIndex];
    final Set<String> activeIds = current.activeLovenseProfileIds
        .where((String id) => availableProfileIds.contains(id))
        .toSet();
    if (active) {
      activeIds.add(profileId);
    } else {
      activeIds.remove(profileId);
    }
    if (activeIds.isEmpty) {
      activeIds.add(profileId);
    }
    final PlaylistEntryData updated = current.copyWith(
      activeLovenseProfileIds: activeIds.toList(),
    );
    setState(() {
      _playlistEntries[entryIndex] = updated;
      if (_selectedPlaylistIndex == entryIndex) {
        _lovenseFormActiveProfileIds = activeIds;
      }
    });
    if (_selectedPlaylistIndex == entryIndex) {
      _refreshLovenseLiveRuleValidation();
    }
  }

  Widget _buildPlaylistItem({
    required int index,
    required PlaylistEntryData entry,
    required bool selected,
  }) {
    final Set<String> availableProfileIds = _lovenseProfiles
        .map((LovenseConnectionProfile profile) => profile.id)
        .toSet();
    final Set<String> activeProfileIds = entry.activeLovenseProfileIds
        .where((String id) => availableProfileIds.contains(id))
        .toSet();
    if (activeProfileIds.isEmpty && _lovenseProfiles.isNotEmpty) {
      activeProfileIds.add(_lovenseProfiles.first.id);
    }
    return Material(
      color: selected ? AppColors.accentSoft : AppColors.panelStrong,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          final Set<String> availableProfileIds = _lovenseProfiles
              .map((LovenseConnectionProfile profile) => profile.id)
              .toSet();
          final Set<String> activeIds = entry.activeLovenseProfileIds
              .where((String id) => availableProfileIds.contains(id))
              .toSet();
          setState(() {
            _selectedPlaylistIndex = index;
            _lovenseFormActiveProfileIds = activeIds.isEmpty
                ? <String>{_selectedLovenseProfile.id}
                : activeIds;
          });
        },
        onDoubleTap: () {
          unawaited(_loadPlaylistEntryAt(index));
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.accentSoftBorder : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.funscriptName} | #${index + 1}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 3),
              Text(
                _formatEntryActiveUsers(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _lovenseProfiles.map((
                  LovenseConnectionProfile profile,
                ) {
                  final bool profileActive = activeProfileIds.contains(
                    profile.id,
                  );
                  return FilterChip(
                    label: Text(
                      profile.displayLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    selected: profileActive,
                    onSelected: (bool value) {
                      _setActiveLovenseProfileForPlaylistEntry(
                        entryIndex: index,
                        profileId: profile.id,
                        active: value,
                      );
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    unawaited(_loadPlaylistEntryAt(index));
                  },
                  child: const Text('Load'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilePanel() {
    return Panel(
      title: 'Playlist entry',
      subtitle: 'Add new pairs or update the selected entry.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _videoInitializing ? null : _pickVideo,
                  icon: const Icon(Icons.video_file_outlined),
                  label: const Text('Video files'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _pickFunscript,
                  icon: const Icon(Icons.data_object_outlined),
                  label: const Text('Funscript files'),
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
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              border: Border.all(color: AppColors.accentSoftBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Notes', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text(
                  'Videos and funscripts are paired by filename first. '
                  'If no matching base name is found, remaining files are '
                  'paired in their selection order.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimingStatePanel() {
    return Panel(
      title: 'Visible panels',
      subtitle: 'Show only the sections you want to keep on screen.',
      child: Column(
        children: <Widget>[
          _buildPanelToggle(
            label: 'Diagnostics',
            value: _showDiagnosticsPanel,
            onChanged: (bool value) {
              setState(() {
                _showDiagnosticsPanel = value;
              });
              unawaited(_saveLocalSettings());
            },
          ),
          _buildPanelToggle(
            label: 'Funscript overview',
            value: _showFunscriptOverviewPanel,
            onChanged: (bool value) {
              setState(() {
                _showFunscriptOverviewPanel = value;
              });
              unawaited(_saveLocalSettings());
            },
          ),
          _buildPanelToggle(
            label: 'Execution log',
            value: _showExecutionLogPanel,
            onChanged: (bool value) {
              setState(() {
                _showExecutionLogPanel = value;
              });
              unawaited(_saveLocalSettings());
            },
          ),
          _buildPanelToggle(
            label: 'Updates',
            value: _showUpdatesPanel,
            onChanged: (bool value) {
              setState(() {
                _showUpdatesPanel = value;
              });
              unawaited(_saveLocalSettings());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPanelToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
          ),
          Checkbox(
            value: value,
            onChanged: (bool? next) => onChanged(next ?? false),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesPanel() {
    return Panel(
      title: 'Updates',
      subtitle: 'Version $_appVersion',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Check automatically on startup',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ),
              Checkbox(
                value: _updateAutoCheck,
                onChanged: (bool? value) {
                  unawaited(_handleUpdateAutoCheckToggle(value ?? false));
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  onPressed: _updateChecking
                      ? null
                      : () {
                          unawaited(_checkForUpdates(manual: true));
                        },
                  child: Text(_updateChecking ? 'Checking...' : 'Check now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  onPressed: _openReleasePage,
                  child: const Text('Open release'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatusNote.info(_updateStatus),
        ],
      ),
    );
  }

  Widget _buildTimingStatsPanel() {
    return Panel(
      title: 'Diagnostics',
      subtitle: _diagnosticsStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.panelStrong,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(
              _diagnosticsPathsText,
              style: const TextStyle(fontFamily: 'Consolas'),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              TextButton(
                onPressed: () {
                  unawaited(_refreshDiagnosticsInfo());
                },
                child: const Text('Refresh diagnostics'),
              ),
              TextButton(
                onPressed: () {
                  unawaited(_copyRecentDiagnosticsLog());
                },
                child: const Text('Copy recent log'),
              ),
              TextButton(
                onPressed: () {
                  unawaited(_openDiagnosticsFolder());
                },
                child: const Text('Open log folder'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Recent log output',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 160, maxHeight: 240),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.panelStrong,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _diagnosticsRecentLogText,
                style: const TextStyle(fontFamily: 'Consolas'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Playback timing',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 4),
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
          if (_videoError.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            StatusNote.error(_videoError),
          ],
        ],
      ),
    );
  }

  Widget _buildLibraryFoldersPanel() {
    return Panel(
      title: 'Library folders',
      subtitle: _libraryStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              TextButton(
                onPressed: () {
                  unawaited(_importCurrentEntryToLibrary());
                },
                child: const Text('Save to Library'),
              ),
              TextButton(
                onPressed: () {
                  unawaited(
                    _openLibraryFolder(
                      kind: 'Videos',
                      directoryPath: _libraryVideosPath,
                    ),
                  );
                },
                child: const Text('Open video folder'),
              ),
              TextButton(
                onPressed: () {
                  unawaited(
                    _openLibraryFolder(
                      kind: 'Funscripts',
                      directoryPath: _libraryFunscriptsPath,
                    ),
                  );
                },
                child: const Text('Open funscript folder'),
              ),
              TextButton(
                onPressed: () {
                  unawaited(
                    _openLibraryFolder(
                      kind: 'Exports',
                      directoryPath: _libraryExportsPath,
                    ),
                  );
                },
                child: const Text('Open exports folder'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              TextButton(
                onPressed: () {
                  unawaited(_selectVideoFromLibrary());
                },
                child: const Text('Select video from Library'),
              ),
              TextButton(
                onPressed: () {
                  unawaited(_selectFunscriptFromLibrary());
                },
                child: const Text('Select funscript from Library'),
              ),
              TextButton(
                onPressed: () {
                  unawaited(_selectPlaylistFromLibrary());
                },
                child: const Text('Select playlist from Library'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton(
                onPressed: () {
                  unawaited(
                    _deleteLibraryFile(
                      kind: 'video',
                      initialDirectory: _libraryVideosPath,
                      allowedExtensions: <String>[
                        'mp4',
                        'webm',
                        'm4v',
                        'mov',
                        'mkv',
                        'avi',
                      ],
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete video from Library'),
              ),
              FilledButton(
                onPressed: () {
                  unawaited(
                    _deleteLibraryFile(
                      kind: 'funscript',
                      initialDirectory: _libraryFunscriptsPath,
                      allowedExtensions: <String>['funscript', 'json'],
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete funscript from Library'),
              ),
              FilledButton(
                onPressed: () {
                  unawaited(
                    _deleteLibraryFile(
                      kind: 'playlist',
                      initialDirectory: _libraryExportsPath,
                      allowedExtensions: <String>['fhplaylist', 'json'],
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete playlist from Library'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLovenseMockPanel() {
    final LovenseMockCommand? lastCommand = _lovenseMockClient.lastCommand;
    final String? ruleError = _lovenseMockClient.ruleError;
    final List<LovenseMockDevice> devices = _lovenseMockClient.devices;
    final LovenseConnectionProfile selectedProfile = _selectedLovenseProfile;
    final LovenseLiveConnectionConfig? liveConfig = _liveConnectionConfigOrNull(
      profile: selectedProfile,
    );
    final ({bool isError, String text}) ruleStatus =
        _lovenseRuleStatusSummary();
    return Panel(
      title: 'Lovense',
      subtitle: _lovenseExecutionMode == LovenseExecutionMode.live
          ? 'Active profile: ${selectedProfile.displayLabel}'
          : 'Simulation profile: ${selectedProfile.displayLabel}',
      trailing: TextButton(
        onPressed: () {
          setState(() {
            _lovensePanelCollapsed = !_lovensePanelCollapsed;
          });
          unawaited(_saveLocalSettings());
        },
        style: TextButton.styleFrom(
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.text,
        ),
        child: Text(
          _lovensePanelCollapsed ? '>' : '▾',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      showBody: !_lovensePanelCollapsed,
      child: _lovensePanelCollapsed
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool stackLiveConfigFields = constraints.maxWidth < 500;
                final bool stackActionButtons = constraints.maxWidth < 440;
                final bool stackMockButtons = constraints.maxWidth < 360;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DropdownButtonFormField<LovenseExecutionMode>(
                      initialValue: _lovenseExecutionMode,
                      decoration: const InputDecoration(
                        labelText: 'Execution mode',
                        border: OutlineInputBorder(),
                      ),
                      items: const <DropdownMenuItem<LovenseExecutionMode>>[
                        DropdownMenuItem<LovenseExecutionMode>(
                          value: LovenseExecutionMode.live,
                          child: Text('Lovense live'),
                        ),
                        DropdownMenuItem<LovenseExecutionMode>(
                          value: LovenseExecutionMode.test,
                          child: Text('Lovense test'),
                        ),
                      ],
                      onChanged: (LovenseExecutionMode? mode) {
                        if (mode == null) {
                          return;
                        }
                        _setLovenseExecutionMode(mode);
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedProfile.id,
                      decoration: const InputDecoration(
                        labelText: 'Connection profile',
                        border: OutlineInputBorder(),
                      ),
                      items: _lovenseProfiles
                          .map(
                            (LovenseConnectionProfile profile) =>
                                DropdownMenuItem<String>(
                                  value: profile.id,
                                  child: Text(profile.displayLabel),
                                ),
                          )
                          .toList(),
                      onChanged: (String? profileId) {
                        if (profileId == null) {
                          return;
                        }
                        _setSelectedLovenseProfile(profileId);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey<String>(
                        'lovense-name-${selectedProfile.id}',
                      ),
                      initialValue: selectedProfile.label,
                      decoration: const InputDecoration(
                        labelText: 'Connection name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (String value) {
                        _updateSelectedLovenseProfile(
                          (LovenseConnectionProfile current) =>
                              current.copyWith(label: value),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        TextButton(
                          onPressed: _addLovenseConnectionProfile,
                          child: const Text('Add user'),
                        ),
                        TextButton(
                          onPressed: _removeSelectedLovenseConnectionProfile,
                          child: const Text('Remove user'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Users for selected playlist entry',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._lovenseProfiles.map((LovenseConnectionProfile profile) {
                      final Set<String> activeIds = _activeLovenseProfileIds()
                          .toSet();
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: activeIds.contains(profile.id),
                        onChanged: (bool? active) {
                          _toggleLovenseActiveProfileForCurrentEntry(
                            profile.id,
                            active ?? false,
                          );
                        },
                        title: Text(profile.displayLabel),
                      );
                    }),
                    const SizedBox(height: 8),
                    if (stackLiveConfigFields) ...<Widget>[
                      DropdownButtonFormField<String>(
                        initialValue: selectedProfile.scheme,
                        decoration: const InputDecoration(
                          labelText: 'Scheme',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'https',
                            child: Text('https'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'http',
                            child: Text('http'),
                          ),
                        ],
                        onChanged: (String? value) {
                          if (value == null) {
                            return;
                          }
                          _updateSelectedLovenseProfile(
                            (LovenseConnectionProfile current) =>
                                current.copyWith(scheme: value),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lovenseLiveHostController,
                        decoration: const InputDecoration(
                          labelText: 'Host',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          _updateSelectedLovenseProfile(
                            (LovenseConnectionProfile current) =>
                                current.copyWith(
                                  host: _lovenseLiveHostController.text,
                                ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lovenseLivePortController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          _updateSelectedLovenseProfile(
                            (LovenseConnectionProfile current) =>
                                current.copyWith(
                                  port: _lovenseLivePortController.text,
                                ),
                          );
                        },
                      ),
                    ] else
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedProfile.scheme,
                              decoration: const InputDecoration(
                                labelText: 'Scheme',
                                border: OutlineInputBorder(),
                              ),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem<String>(
                                  value: 'https',
                                  child: Text('https'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'http',
                                  child: Text('http'),
                                ),
                              ],
                              onChanged: (String? value) {
                                if (value == null) {
                                  return;
                                }
                                _updateSelectedLovenseProfile(
                                  (LovenseConnectionProfile current) =>
                                      current.copyWith(scheme: value),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _lovenseLiveHostController,
                              decoration: const InputDecoration(
                                labelText: 'Host',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) {
                                _updateSelectedLovenseProfile(
                                  (LovenseConnectionProfile current) =>
                                      current.copyWith(
                                        host: _lovenseLiveHostController.text,
                                      ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 88,
                            child: TextField(
                              controller: _lovenseLivePortController,
                              decoration: const InputDecoration(
                                labelText: 'Port',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) {
                                _updateSelectedLovenseProfile(
                                  (LovenseConnectionProfile current) =>
                                      current.copyWith(
                                        port: _lovenseLivePortController.text,
                                      ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lovenseLivePlatformController,
                      decoration: const InputDecoration(
                        labelText: 'Platform name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        _updateSelectedLovenseProfile(
                          (LovenseConnectionProfile current) =>
                              current.copyWith(
                                platformName:
                                    _lovenseLivePlatformController.text,
                              ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    if (stackActionButtons) ...<Widget>[
                      FilledButton.tonalIcon(
                        onPressed: _lovenseLiveEnabled && !_lovenseLiveDetecting
                            ? _detectLovenseLiveDevices
                            : null,
                        icon: const Icon(Icons.search),
                        label: Text(
                          _lovenseLiveDetecting
                              ? 'Detecting...'
                              : 'Detect devices',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _lovenseLiveEnabled
                            ? () {
                                _sendLovenseStop(
                                  'Manual stop',
                                  _displayPositionMs,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop live'),
                      ),
                    ] else
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed:
                                  _lovenseLiveEnabled && !_lovenseLiveDetecting
                                  ? _detectLovenseLiveDevices
                                  : null,
                              icon: const Icon(Icons.search),
                              label: Text(
                                _lovenseLiveDetecting
                                    ? 'Detecting...'
                                    : 'Detect devices',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _lovenseLiveEnabled
                                  ? () {
                                      _sendLovenseStop(
                                        'Manual stop',
                                        _displayPositionMs,
                                      );
                                    }
                                  : null,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('Stop live'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    StatusNote.info(
                      _lovenseLiveEnabled
                          ? (liveConfig == null
                                ? 'Live connection config incomplete.'
                                : _lovenseLiveStatus)
                          : 'Lovense test mode active. Commands run against simulated devices.',
                    ),
                    if (_lovenseLiveEnabled &&
                        _lovenseLiveRuleIssues.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      StatusNote.error(
                        _lovenseLiveRuleIssues
                            .map(
                              (LovenseLiveRuleIssue issue) => issue.toString(),
                            )
                            .join(' | '),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (selectedProfile.detectedDevices.isNotEmpty) ...<Widget>[
                      Text(
                        'Detected live devices',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...selectedProfile.detectedDevices.map((
                        LovenseLiveDevice device,
                      ) {
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedProfile.selectedDeviceIds.contains(
                            device.id,
                          ),
                          onChanged: (bool? selected) {
                            _updateSelectedLovenseProfile((
                              LovenseConnectionProfile current,
                            ) {
                              final Set<String> nextSelection = current
                                  .selectedDeviceIds
                                  .toSet();
                              if (selected == true) {
                                nextSelection.add(device.id);
                              } else {
                                nextSelection.remove(device.id);
                              }
                              return current.copyWith(
                                selectedDeviceIds: nextSelection,
                              );
                            });
                          },
                          title: Text(device.displayName),
                          subtitle: Text(
                            '${device.id} | '
                            '${_formatDeviceCapabilities(LovenseMockDevice(id: device.id, name: device.displayName, capabilities: device.ruleCapabilities))}',
                          ),
                        );
                      }),
                      const Divider(height: 24),
                    ],
                    _buildAdaptiveSwitchTile(
                      value: _lovenseMockEnabled,
                      title: 'Mock output',
                      subtitle: _lovenseMockEnabled
                          ? 'Commands are logged but not sent.'
                          : 'Mock output disabled.',
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
                        labelText:
                            'Rule text (${selectedProfile.displayLabel})',
                        helperText:
                            'Example: if pos >= 15 then vibrate(10, 800) | else stop()',
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Tooltip(
                              message:
                                  'Variables: pos, index, at, time, current, currentms, '
                                  'delta, deltams',
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(Icons.help_outline, size: 20),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Reset selected user rules',
                              onPressed: _resetLovenseMockRules,
                              icon: const Icon(Icons.restart_alt),
                            ),
                          ],
                        ),
                      ),
                      onChanged: _updateLovenseMockRules,
                    ),
                    const SizedBox(height: 10),
                    ruleError == null
                        ? const StatusNote.info('Rule script valid.')
                        : StatusNote.error(ruleError),
                    const SizedBox(height: 10),
                    ruleStatus.isError
                        ? StatusNote.error(ruleStatus.text)
                        : StatusNote.info(ruleStatus.text),
                    const SizedBox(height: 10),
                    StateRow(
                      label: 'Devices',
                      value: _lovenseLiveEnabled
                          ? '${selectedProfile.detectedDevices.length}'
                          : '${devices.length}',
                    ),
                    StateRow(
                      label: 'Capabilities',
                      value: _lovenseCapabilitiesLabel(),
                    ),
                    StateRow(
                      label: 'Device type',
                      value: _lovenseDeviceTypeLabel(),
                    ),
                    StateRow(
                      label: 'Parallel actions',
                      value: _lovenseParallelActionsLabel(),
                    ),
                    StateRow(
                      label: 'Action ranges',
                      value: _lovenseActionRangesSummary(),
                    ),
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
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (devices.isEmpty)
                      const StatusNote.error('No simulated devices configured.')
                    else ...<Widget>[
                      for (final LovenseMockDevice device
                          in devices) ...<Widget>[
                        SimulatedDeviceTile(device: device),
                        const SizedBox(height: 8),
                      ],
                    ],
                    const SizedBox(height: 10),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Rule syntax'),
                      initiallyExpanded: _lovenseRuleSyntaxExpanded,
                      onExpansionChanged: (bool expanded) {
                        setState(() {
                          _lovenseRuleSyntaxExpanded = expanded;
                        });
                      },
                      children: const <Widget>[
                        Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Example:\n'
                            'if pos >= 15 then vibrate(10, 800)\n'
                            'else stop()\n\n'
                            'Variables: pos, index, at, time, current, currentms, delta, deltams.\n'
                            'In Lovense live mode, select at least one detected device first.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (stackMockButtons) ...<Widget>[
                      FilledButton.tonalIcon(
                        onPressed: _lovenseMockEnabled
                            ? () {
                                _sendLovenseStop(
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
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _clearLovenseMock,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear'),
                        ),
                      ),
                    ] else
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _lovenseMockEnabled
                                  ? () {
                                      _sendLovenseStop(
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
                              itemCount: math.min(
                                _lovenseMockClient.history.length,
                                8,
                              ),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (BuildContext context, int index) {
                                return MockCommandTile(
                                  command: _lovenseMockClient.history[index],
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildAdaptiveSwitchTile({
    required bool value,
    required String title,
    required String subtitle,
    required ValueChanged<bool> onChanged,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 300) {
          return SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: value,
            title: Text(title),
            subtitle: Text(subtitle),
            onChanged: onChanged,
          );
        }

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Switch(value: value, onChanged: onChanged),
                  ],
                ),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        );
      },
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
    final String title = _videoName.isEmpty
        ? 'No playlist entry loaded'
        : _videoName;
    final String funscriptLabel = _funscriptName.isEmpty
        ? 'No funscript'
        : _funscriptName;
    final String actionLabel = _funscript == null
        ? '0 actions'
        : '${_funscript!.actions.length} actions';
    final String modeLabel = _lovenseLiveEnabled
        ? 'Lovense live'
        : 'Lovense test';
    final List<LovenseConnectionProfile> activeProfiles =
        _activeLovenseProfiles();
    final int selectedDeviceCount = activeProfiles
        .map(_selectedLovenseLiveDevicesForProfile)
        .fold<int>(
          0,
          (int sum, List<LovenseLiveDevice> items) => sum + items.length,
        );
    final String profileLabel = _lovenseLiveEnabled
        ? '${activeProfiles.length} user(s): ${selectedDeviceCount <= 0 ? 'no device' : '$selectedDeviceCount selected'}'
        : '${_lovenseProfiles.length} simulated user(s)';
    final String endpointLabel = _lovenseLiveEnabled
        ? '${_selectedLovenseProfile.host.trim().isEmpty ? '-' : _selectedLovenseProfile.host.trim()}:'
              '${_selectedLovenseProfile.port.trim().isEmpty ? '-' : _selectedLovenseProfile.port.trim()}'
        : 'simulated';

    return Panel(
      title: title,
      subtitle:
          '$funscriptLabel | $actionLabel | $modeLabel | $profileLabel | $endpointLabel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 14),
          _buildTimelinePanel(),
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
      borderRadius: BorderRadius.circular(18),
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
                          _buildOverlayTextButton(
                            tooltip: 'Back 10 seconds',
                            label: '-10s',
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
                          _buildOverlayTextButton(
                            tooltip: 'Forward 10 seconds',
                            label: '+10s',
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
                    if (_lovenseLiveEnabled)
                      Positioned(
                        top: 14,
                        right: 14,
                        child: FilledButton(
                          onPressed: canPlay
                              ? () {
                                  _sendLovenseStop(
                                    'Emergency stop: video paused and Lovense stop sent.',
                                    _displayPositionMs,
                                  );
                                  if (isPlaying) {
                                    _togglePlayback();
                                  }
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            side: const BorderSide(
                              color: Color(0xCCFFF8EF),
                              width: 1.6,
                            ),
                          ),
                          child: const Text(
                            'STOP',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
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

  Widget _buildOverlayTextButton({
    required String tooltip,
    required String label,
    required double size,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: Size.square(size),
          maximumSize: Size.square(size),
          backgroundColor: const Color(0xA0150D09),
          foregroundColor: const Color(0xDDFFF8EF),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
        ),
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
          final double volumeSliderWidth = compact
              ? 120
              : (constraints.maxWidth * 0.18).clamp(140.0, 240.0).toDouble();
          return Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Previous playlist entry',
                onPressed: _playlistEntries.isEmpty
                    ? null
                    : () {
                        unawaited(_loadPreviousPlaylistEntry());
                      },
                icon: const Icon(Icons.skip_previous),
                color: const Color(0xDDFFF8EF),
                disabledColor: const Color(0x66FFF8EF),
              ),
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
              SizedBox(
                width: volumeSliderWidth,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: const Color(0x66FFF8EF),
                    thumbColor: AppColors.accent,
                    overlayColor: AppColors.accentSoft.withValues(alpha: 0.20),
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
              const SizedBox(width: 2),
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
              IconButton(
                tooltip: 'Next playlist entry',
                onPressed: _playlistEntries.isEmpty
                    ? null
                    : () {
                        unawaited(_loadNextPlaylistEntry());
                      },
                icon: const Icon(Icons.skip_next),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _buildTimelineCell(
            'Current time',
            formatMs(_displayPositionMs),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTimelineCell('Next action', _formatAction(_nextAction)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTimelineCell(
            'Last action',
            _formatAction(_lastLoggedAction),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
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
        label: const Text('Clear log'),
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
    return '${action.pos} @ ${formatMs(action.atMs)}';
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
  Funscript({
    required this.actions,
    required this.sourceName,
    required this.sourcePath,
    required this.document,
  });

  final List<FunscriptAction> actions;
  final String sourceName;
  final String sourcePath;
  final Map<String, dynamic> document;

  factory Funscript.fromJson(
    Map<String, dynamic> json, {
    required String sourceName,
    String sourcePath = '',
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

    final Map<String, dynamic> document = _cloneJsonMap(json);
    if (document['actions'] is! List) {
      document['actions'] = <Map<String, int>>[
        for (final FunscriptAction action in indexed)
          <String, int>{'at': action.atMs, 'pos': action.pos},
      ];
    }

    return Funscript(
      actions: indexed,
      sourceName: sourceName,
      sourcePath: sourcePath.trim(),
      document: document,
    );
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
    this.showBody = true,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  final bool showBody;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 38,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stackHeader = constraints.maxWidth < 560;
          final Widget titleText = Text(
            title,
            maxLines: stackHeader ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          );
          final Widget subtitleText = Text(
            subtitle,
            maxLines: stackHeader ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w500,
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (stackHeader)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    titleText,
                    if (trailing != null) ...<Widget>[
                      const SizedBox(height: 8),
                      trailing!,
                    ],
                    const SizedBox(height: 10),
                    subtitleText,
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: titleText),
                    const SizedBox(width: 16),
                    Expanded(child: subtitleText),
                    if (trailing != null) ...<Widget>[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
                  ],
                ),
              if (showBody) ...<Widget>[const SizedBox(height: 16), child],
            ],
          );
        },
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
        ? AppColors.secondaryButton
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
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
  static const Color background = Color(0xFFF6EFE4);
  static const Color panel = Color(0xE6FFFBF5);
  static const Color panelStrong = Color(0xFFFFF8EF);
  static const Color border = Color(0x26502E11);
  static const Color text = Color(0xFF2F2417);
  static const Color muted = Color(0xFF6C5B45);
  static const Color accent = Color(0xFFBD5F2D);
  static const Color accentStrong = Color(0xFF8F3F16);
  static const Color accentSoft = Color(0x14BD5F2D);
  static const Color accentSoftBorder = Color(0x2EBD5F2D);
  static const Color secondaryButton = Color(0x142F2417);
  static const Color infoSoft = Color(0xFFFFF8EF);
  static const Color successSoft = Color(0x1448805A);
  static const Color successBorder = Color(0x5948805A);
  static const Color errorSoft = Color(0x149F2424);
  static const Color errorBorder = Color(0x599F2424);
  static const Color danger = Color(0xFFC1121F);
  static const Color shadow = Color(0x1F4B2B12);
  static const Color playerBackground = Color(0xFF150D09);
}
