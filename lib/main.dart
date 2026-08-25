import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const ShinyMobileTestApp());
}

const String appVersion = 'v0.1.8-test';
const String draftStorageKey = 'park_golf_scorecard_draft_v1';
const String customCoursesStorageKey = 'park_golf_custom_courses_v1';
const String savedRoundsStorageKey = 'park_golf_saved_rounds_v1';
const String playerHistoryStorageKey = 'park_golf_player_history_v1';
const String courseCsvAssetPath = 'assets/data/park_golf_courses_kr.csv';
const String holeTemplateJsonAssetPath = 'assets/data/parkgolf_stage2_master.json';
const String parkGolfApiBaseUrl = 'https://s2sin.com/parkgolf';
const String coursesApiPath = '/courses.php';
const String courseHolesApiPath = '/course_holes.php';
const String submitSuggestionPath = '/submit_suggestion.php';

class ShinyMobileTestApp extends StatelessWidget {
  const ShinyMobileTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '파크골프 스코어카드',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16866A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F3),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const ScoreCardPage(),
    );
  }
}

class CourseInfo {
  const CourseInfo(this.name, this.label, this.color, this.textColor);

  final String name;
  final String label;
  final Color color;
  final Color textColor;
}

const List<CourseInfo> courses = [
  CourseInfo('A', 'A 코스', Color(0xFFFFD7D7), Color(0xFF5F1F1F)),
  CourseInfo('B', 'B 코스', Color(0xFFD8E8FF), Color(0xFF1D3C68)),
  CourseInfo('C', 'C 코스', Color(0xFFFFF2B8), Color(0xFF594600)),
  CourseInfo('D', 'D 코스', Color(0xFFFFFFFF), Color(0xFF2D2D2D)),
];

const List<int> defaultPars = [3, 3, 3, 3, 4, 4, 4, 4, 5];

class ParkGolfCourse {
  const ParkGolfCourse({
    required this.id,
    required this.region,
    required this.name,
    required this.phone,
    required this.address,
    required this.holeCount,
    this.isUserAdded = false,
  });

  final String id;
  final String region;
  final String name;
  final String phone;
  final String address;
  final int holeCount;
  final bool isUserAdded;

  factory ParkGolfCourse.fromCsvRow(List<String> row, int index) {
    String valueAt(int column) => column < row.length ? row[column].trim() : '';

    return ParkGolfCourse(
      id: 'csv-$index',
      region: valueAt(0),
      name: valueAt(1),
      phone: valueAt(2),
      address: valueAt(3),
      holeCount: int.tryParse(valueAt(4)) ?? 0,
    );
  }

  factory ParkGolfCourse.fromJson(Map<String, dynamic> json) {
    return ParkGolfCourse(
      id: json['id'] as String? ?? 'user-${DateTime.now().millisecondsSinceEpoch}',
      region: json['region'] as String? ?? '직접등록',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      holeCount: json['holeCount'] as int? ?? 0,
      isUserAdded: json['isUserAdded'] as bool? ?? true,
    );
  }

  factory ParkGolfCourse.fromServerJson(Map<String, dynamic> json) {
    final region = (json['region'] ?? '').toString().trim();
    final city = (json['city'] ?? '').toString().trim();
    final regionLabel = [
      if (region.isNotEmpty) region,
      if (city.isNotEmpty && city != region) city,
    ].join(' ');

    return ParkGolfCourse(
      id: (json['id'] ?? '').toString(),
      region: regionLabel.isEmpty ? '서버등록' : regionLabel,
      name: (json['name'] ?? '').toString().trim(),
      phone: (json['phone'] ?? '-').toString().trim(),
      address: (json['address'] ?? '').toString().trim(),
      holeCount: int.tryParse((json['hole_count'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'region': region,
      'name': name,
      'phone': phone,
      'address': address,
      'holeCount': holeCount,
      'isUserAdded': isUserAdded,
    };
  }
}

class HoleEntry {
  HoleEntry({
    required this.course,
    required this.hole,
    required this.par,
    required this.distanceController,
    required this.scoreControllers,
  });

  String course;
  int hole;
  int par;
  final TextEditingController distanceController;
  final List<TextEditingController> scoreControllers;

  Map<String, dynamic> toJson() {
    return {
      'course': course,
      'hole': hole,
      'par': par,
      'distance': distanceController.text,
      'scores': scoreControllers.map((controller) => controller.text).toList(),
    };
  }
}

class HoleTemplate {
  const HoleTemplate({
    required this.hole,
    required this.distanceM,
    required this.par,
  });

  final int hole;
  final int distanceM;
  final int par;
}

class ScoreCardPage extends StatefulWidget {
  const ScoreCardPage({super.key});

  @override
  State<ScoreCardPage> createState() => _ScoreCardPageState();
}

class _ScoreCardPageState extends State<ScoreCardPage> {
  final TextEditingController _placeController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _stepsController = TextEditingController();
  final TextEditingController _firstCourseController =
      TextEditingController(text: 'A');
  final TextEditingController _secondCourseController =
      TextEditingController(text: 'B');
  final List<TextEditingController> _playerControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final ScrollController _scoreScrollController = ScrollController();

  late final List<HoleEntry> _holes;
  List<ParkGolfCourse> _baseCourses = [];
  List<ParkGolfCourse> _customCourses = [];
  List<String> _playerNameHistory = [];
  Map<String, Map<String, List<HoleTemplate>>> _holeTemplates = {};
  ParkGolfCourse? _selectedGolfCourse;
  String? _draftSelectedCourseId;
  int _playerCount = 4;
  int _activeCourseSlot = 0;
  int _focusedHoleIndex = 0;
  int? _stepBaseline;
  bool _gameStarted = false;
  bool _hasPausedGame = false;
  bool _setupOpenedFromScore = false;
  bool _savedOnce = false;
  bool _coursesLoaded = false;
  bool _stepSensorActive = false;
  String? _stepSensorMessage;
  late final List<GlobalKey> _holeKeys;
  StreamSubscription<StepCount>? _stepCountSubscription;

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDisplayDate(DateTime.now());
    _startTimeController.text = _formatDisplayTime(DateTime.now());
    _holes = List.generate(18, (index) {
      final holeNumber = (index % 9) + 1;
      return HoleEntry(
        course: index < 9 ? 'A' : 'B',
        hole: holeNumber,
        par: defaultPars[holeNumber - 1],
        distanceController: TextEditingController(),
        scoreControllers: List.generate(4, (_) => TextEditingController()),
      );
    });
    _holeKeys = List.generate(18, (_) => GlobalKey());
    _loadInitialData();
  }

  String _formatDisplayDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}.  $month.  $day.';
  }

  String _formatDisplayTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? '오전' : '오후';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$period  ${displayHour.toString().padLeft(2, '0')}:$minute';
  }

  DateTime _selectedDateValue() {
    final numbers = RegExp(r'\d+')
        .allMatches(_dateController.text)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .toList();
    if (numbers.length >= 3) {
      return DateTime(numbers[0], numbers[1], numbers[2]);
    }
    return DateTime.now();
  }

  TimeOfDay _selectedTimeValue() {
    final text = _startTimeController.text.trim();
    final numbers = RegExp(r'\d+')
        .allMatches(text)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .toList();
    if (numbers.length >= 2) {
      var hour = numbers[0];
      final minute = numbers[1].clamp(0, 59).toInt();
      if (text.contains('오후') && hour < 12) hour += 12;
      if (text.contains('오전') && hour == 12) hour = 0;
      return TimeOfDay(hour: hour.clamp(0, 23).toInt(), minute: minute);
    }
    return TimeOfDay.now();
  }

  @override
  void dispose() {
    _placeController.dispose();
    _dateController.dispose();
    _startTimeController.dispose();
    _stepsController.dispose();
    _firstCourseController.dispose();
    _secondCourseController.dispose();
    _scoreScrollController.dispose();
    _stepCountSubscription?.cancel();
    for (final controller in _playerControllers) {
      controller.dispose();
    }
    for (final hole in _holes) {
      hole.distanceController.dispose();
      for (final controller in hole.scoreControllers) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var insideQuote = false;

    for (var index = 0; index < line.length; index++) {
      final char = line[index];
      if (char == '"') {
        insideQuote = !insideQuote;
      } else if (char == ',' && !insideQuote) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }

  Future<void> _loadInitialData() async {
    await _loadDraft();
    await _loadPlayerHistory();
    await _loadCourses();
    await _loadHoleTemplates();
  }

  Future<void> _loadPlayerHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(playerHistoryStorageKey);
    if (raw == null) return;
    final names = (jsonDecode(raw) as List<dynamic>)
        .map((item) => item.toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (!mounted) return;
    setState(() {
      _playerNameHistory = names;
    });
  }

  Future<void> _loadCourses() async {
    final serverCourses = await _loadServerCourses();
    if (serverCourses.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final customCourses = await _readCustomCourses(prefs);
      if (!mounted) return;
      setState(() {
        _baseCourses = serverCourses;
        _customCourses = customCourses;
        _selectInitialCourse([...customCourses, ...serverCourses]);
        _coursesLoaded = true;
      });
      await _loadServerHoleTemplatesForSelectedCourse(overwriteExisting: false);
      return;
    }

    final csvText = await rootBundle.loadString(courseCsvAssetPath);
    final rows = const LineSplitter()
        .convert(csvText)
        .skip(1)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final csvCourses = [
      for (var index = 0; index < rows.length; index++)
        ParkGolfCourse.fromCsvRow(_parseCsvLine(rows[index]), index),
    ].where((course) => course.name.isNotEmpty).toList();
    final csvByKey = {
      for (final course in csvCourses) _normalCourseName(course.name): course,
    };

    final jsonText = await rootBundle.loadString(holeTemplateJsonAssetPath);
    final jsonRows = jsonDecode(jsonText) as List<dynamic>;
    final jsonCourseRows = <String, Map<String, dynamic>>{};
    final jsonCourseOrder = <String>[];
    for (final item in jsonRows) {
      final row = item as Map<String, dynamic>;
      final name = (row['golf_name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final key = _normalCourseName(name);
      jsonCourseRows.putIfAbsent(key, () {
        jsonCourseOrder.add(key);
        return row;
      });
      final current = jsonCourseRows[key]!;
      final currentHoles = current['total_holes'] as int? ?? 0;
      final rowHoles = row['total_holes'] as int? ?? 0;
      if (rowHoles > currentHoles) {
        jsonCourseRows[key] = row;
      }
    }

    final usedKeys = <String>{};
    final baseCourses = <ParkGolfCourse>[
      for (var index = 0; index < jsonCourseOrder.length; index++)
        () {
          final key = jsonCourseOrder[index];
          usedKeys.add(key);
          final row = jsonCourseRows[key]!;
          final name = (row['golf_name'] as String? ?? '').trim();
          final csvCourse = csvByKey[key];
          return ParkGolfCourse(
            id: 'json-$key',
            region: csvCourse?.region ?? _regionFromTemplateName(name),
            name: csvCourse?.name ?? _displayNameFromTemplateName(name),
            phone: csvCourse?.phone ?? '-',
            address: csvCourse?.address ?? '',
            holeCount: csvCourse?.holeCount ?? (row['total_holes'] as int? ?? 0),
          );
        }(),
      for (final course in csvCourses)
        if (!usedKeys.contains(_normalCourseName(course.name))) course,
    ];

    final prefs = await SharedPreferences.getInstance();
    final customCourses = await _readCustomCourses(prefs);

    if (!mounted) return;
    setState(() {
      _baseCourses = baseCourses;
      _customCourses = customCourses;
      _selectInitialCourse([...customCourses, ...baseCourses]);
      _coursesLoaded = true;
    });
  }

  Future<List<ParkGolfCourse>> _loadServerCourses() async {
    try {
      final uri = Uri.parse('$parkGolfApiBaseUrl$coursesApiPath');
      final data = await _getJson(uri);
      final rows = data['courses'] as List<dynamic>? ?? [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(ParkGolfCourse.fromServerJson)
          .where((course) => course.id.isNotEmpty && course.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ParkGolfCourse>> _readCustomCourses(SharedPreferences prefs) async {
    final customRaw = prefs.getString(customCoursesStorageKey);
    final customCourses = <ParkGolfCourse>[];
    if (customRaw == null) return customCourses;
    final customData = jsonDecode(customRaw) as List<dynamic>;
    for (final item in customData) {
      customCourses.add(ParkGolfCourse.fromJson(item as Map<String, dynamic>));
    }
    return customCourses;
  }

  void _selectInitialCourse(List<ParkGolfCourse> allCourses) {
    final draftSelected = _draftSelectedCourseId;
    if (draftSelected != null) {
      for (final course in allCourses) {
        if (course.id == draftSelected) {
          _selectedGolfCourse = course;
          break;
        }
      }
    }
    if (_selectedGolfCourse == null && allCourses.isNotEmpty) {
      _selectedGolfCourse = allCourses.first;
    }
    if (_placeController.text.trim().isEmpty && _selectedGolfCourse != null) {
      _placeController.text = _selectedGolfCourse!.name;
    }
  }

  String _normalCourseName(String value) {
    return value
        .replaceAll(RegExp(r'\[[^\]]+\]'), '')
        .replaceAll('파크골프장', '')
        .replaceAll('파크골프', '')
        .replaceAll('구장', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim()
        .toLowerCase();
  }

  Future<void> _loadHoleTemplates() async {
    final jsonText = await rootBundle.loadString(holeTemplateJsonAssetPath);
    final rows = jsonDecode(jsonText) as List<dynamic>;
    final templates = <String, Map<String, List<HoleTemplate>>>{};
    final templateCourses = <ParkGolfCourse>[];
    final knownCourseKeys = _baseCourses.map((course) => _normalCourseName(course.name)).toSet();

    for (final item in rows) {
      final row = item as Map<String, dynamic>;
      final name = (row['golf_name'] as String? ?? '').trim();
      final courseType = (row['course_type'] as String? ?? '').trim().toUpperCase();
      final holeInfoRaw = (row['hole_info_json'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final key = _normalCourseName(name);
      if (!knownCourseKeys.contains(key)) {
        templateCourses.add(
          ParkGolfCourse(
            id: 'template-$key',
            region: _regionFromTemplateName(name),
            name: _displayNameFromTemplateName(name),
            phone: '-',
            address: '',
            holeCount: row['total_holes'] as int? ?? 0,
          ),
        );
        knownCourseKeys.add(key);
      }
      if (holeInfoRaw.isEmpty) continue;

      final holeInfo = jsonDecode(holeInfoRaw) as List<dynamic>;
      final holes = <HoleTemplate>[];
      for (final holeItem in holeInfo) {
        final hole = holeItem as Map<String, dynamic>;
        final holeNo = int.tryParse(hole['hole'].toString()) ?? 0;
        final distanceM = int.tryParse(hole['distance'].toString()) ?? 0;
        final par = int.tryParse(hole['par'].toString()) ?? 0;
        if (holeNo >= 1 && holeNo <= 9 && distanceM > 0 && par >= 3 && par <= 5) {
          holes.add(HoleTemplate(hole: holeNo, distanceM: distanceM, par: par));
        }
      }
      if (holes.isEmpty) continue;

      templates.putIfAbsent(key, () => {});
      final templateKey = ['A', 'B', 'C', 'D'].contains(courseType)
          ? courseType
          : 'AUTO${templates[key]!.length}';
      templates[key]![templateKey] = holes;
    }

    if (!mounted) return;
    setState(() {
      _holeTemplates = templates;
      if (templateCourses.isNotEmpty) {
        _baseCourses = [..._baseCourses, ...templateCourses];
      }
      if (_selectedGolfCourse == null && _draftSelectedCourseId != null) {
        for (final course in _allGolfCourses()) {
          if (course.id == _draftSelectedCourseId) {
            _selectedGolfCourse = course;
            break;
          }
        }
      }
    });
    _applyHoleTemplatesForSelectedCourse(overwriteExisting: false);
  }

  String _displayNameFromTemplateName(String value) {
    return value.replaceAll(RegExp(r'\[[^\]]+\]'), '').trim();
  }

  String _regionFromTemplateName(String value) {
    final matches = RegExp(r'\[([^\]]+)\]').allMatches(value).toList();
    if (matches.isEmpty) return '자료등록';
    return matches.map((match) => match.group(1)!).join(' ');
  }

  void _applyHoleTemplatesForSelectedCourse({bool overwriteExisting = false}) {
    final course = _selectedGolfCourse;
    if (course == null || _holeTemplates.isEmpty) return;
    final key = _normalCourseName(course.name);
    final templates = _holeTemplates[key];
    if (templates == null) return;

    setState(() {
      for (var index = 0; index < _holes.length; index++) {
        final hole = _holes[index];
        final courseTemplates = templates[hole.course] ??
            templates['AUTO${index ~/ 9}'] ??
            templates['AUTO0'];
        if (courseTemplates == null) continue;
        HoleTemplate? template;
        for (final item in courseTemplates) {
          if (item.hole == hole.hole) {
            template = item;
            break;
          }
        }
        if (template == null) continue;
        if (!overwriteExisting && hole.distanceController.text.trim().isNotEmpty) {
          continue;
        }
        hole.distanceController.text = template.distanceM.toString();
        hole.par = template.par;
      }
    });
    _saveDraft();
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final rawDraft = prefs.getString(draftStorageKey);
    if (rawDraft == null) return;

    final data = jsonDecode(rawDraft) as Map<String, dynamic>;
    final holes = data['holes'] as List<dynamic>? ?? [];
    if (!mounted) return;

    setState(() {
      _placeController.text = data['place'] as String? ?? '';
      _dateController.text = data['date'] as String? ?? _dateController.text;
      _startTimeController.text =
          data['startTime'] as String? ?? _startTimeController.text;
      _stepsController.text = data['steps'] as String? ?? '';
      _firstCourseController.text = data['firstCourse'] as String? ?? 'A';
      _secondCourseController.text = data['secondCourse'] as String? ?? 'B';
      _draftSelectedCourseId = data['selectedCourseId'] as String?;
      _activeCourseSlot = data['activeCourseSlot'] as int? ?? 0;
      _focusedHoleIndex = data['focusedHoleIndex'] as int? ?? 0;
      _stepBaseline = data['stepBaseline'] as int?;
      _gameStarted = data['gameStarted'] as bool? ?? false;
      _hasPausedGame = data['hasPausedGame'] as bool? ?? false;
      _setupOpenedFromScore = data['setupOpenedFromScore'] as bool? ?? false;
      _playerCount = data['playerCount'] as int? ?? 4;
      final players = data['players'] as List<dynamic>? ?? [];
      for (var index = 0; index < _playerControllers.length; index++) {
        final playerName = index < players.length ? players[index] as String? : null;
        _playerControllers[index].text = playerName ?? '';
      }
      for (var index = 0; index < _holes.length && index < holes.length; index++) {
        final holeData = holes[index] as Map<String, dynamic>;
        _holes[index].course = holeData['course'] as String? ?? _holes[index].course;
        _holes[index].hole = holeData['hole'] as int? ?? _holes[index].hole;
        _holes[index].par = holeData['par'] as int? ?? _holes[index].par;
        _holes[index].distanceController.text =
            holeData['distance'] as String? ?? '';
        final scores = holeData['scores'] as List<dynamic>? ?? [];
        for (var player = 0; player < 4; player++) {
          final score = player < scores.length ? scores[player] as String? : null;
          _holes[index].scoreControllers[player].text = score ?? '';
        }
      }
      _savedOnce = true;
    });
  }

  Future<void> _saveDraft({bool showMessage = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'place': _placeController.text,
      'date': _dateController.text,
      'startTime': _startTimeController.text,
      'steps': _stepsController.text,
      'firstCourse': _firstCourseController.text,
      'secondCourse': _secondCourseController.text,
      'selectedCourseId': _selectedGolfCourse?.id,
      'activeCourseSlot': _activeCourseSlot,
      'focusedHoleIndex': _focusedHoleIndex,
      'stepBaseline': _stepBaseline,
      'gameStarted': _gameStarted,
      'hasPausedGame': _hasPausedGame,
      'setupOpenedFromScore': _setupOpenedFromScore,
      'playerCount': _playerCount,
      'players': _playerControllers.map((controller) => controller.text).toList(),
      'holes': _holes.map((hole) => hole.toJson()).toList(),
      'savedAt': DateTime.now().toIso8601String(),
    };

    await prefs.setString(draftStorageKey, jsonEncode(data));
    if (!mounted) return;

    setState(() {
      _savedOnce = true;
    });
    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 경기를 자동 저장했습니다')),
      );
    }
  }

  Map<String, dynamic> _roundSnapshot() {
    return _roundSnapshotWithStatus('저장');
  }

  Map<String, dynamic> _roundSnapshotWithStatus(String status) {
    final activePlayers = _activePlayerIndexes();
    return {
      'id': 'round-${DateTime.now().millisecondsSinceEpoch}',
      'status': status,
      'place': _placeController.text,
      'date': _dateController.text,
      'startTime': _startTimeController.text,
      'steps': _stepsController.text,
      'courseName': _selectedGolfCourse?.name,
      'courseId': _selectedGolfCourse?.id,
      'playerCount': activePlayers.length,
      'players': _activePlayerNames(),
      'holes': _holes.map((hole) => hole.toJson()).toList(),
      'totalPar': _parTotal(),
      'totals': [
        for (final index in activePlayers) _scoreTotal(index),
      ],
      'savedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _saveInterruptedRoundAndExit() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(savedRoundsStorageKey);
    final rounds = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    rounds.insert(0, _roundSnapshotWithStatus('종료'));
    await prefs.setString(savedRoundsStorageKey, jsonEncode(rounds.take(50).toList()));
    await _rememberPlayerNames();
    setState(() {
      _gameStarted = false;
      _hasPausedGame = false;
      _activeCourseSlot = 0;
      _focusedHoleIndex = 0;
      _clearScoresAndRoundProgress();
    });
    await _stopStepTracking();
    await _saveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('경기를 종료하고 기록에 남겼습니다')),
    );
  }

  Future<void> _rememberPlayerNames() async {
    final currentNames = [
      for (var index = 0; index < _playerCount; index++)
        _playerControllers[index].text.trim(),
    ].where((name) => name.isNotEmpty).toList();
    final merged = <String>[
      ...currentNames,
      ..._playerNameHistory.where((name) => !currentNames.contains(name)),
    ].take(30).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(playerHistoryStorageKey, jsonEncode(merged));
    if (!mounted) return;
    setState(() {
      _playerNameHistory = merged;
    });
  }

  Future<void> _openSavedRounds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(savedRoundsStorageKey);
    final rounds = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SavedRoundsPage(
          rounds: rounds.whereType<Map<String, dynamic>>().toList(),
        ),
      ),
    );
  }

  List<ParkGolfCourse> _allGolfCourses() {
    return [..._customCourses, ..._baseCourses];
  }

  Future<void> _saveCustomCourses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      customCoursesStorageKey,
      jsonEncode(_customCourses.map((course) => course.toJson()).toList()),
    );
  }

  Future<void> _selectGolfCourse(ParkGolfCourse course) async {
    setState(() {
      _selectedGolfCourse = course;
      _placeController.text = course.name;
    });
    final appliedServerData = await _loadServerHoleTemplatesForSelectedCourse(
      overwriteExisting: true,
    );
    if (!appliedServerData) {
      _applyHoleTemplatesForSelectedCourse(overwriteExisting: true);
    }
    _saveDraft();
  }

  Future<void> _openGolfCoursePicker() async {
    final selected = await Navigator.of(context).push<ParkGolfCourse>(
      MaterialPageRoute(
        builder: (_) => GolfCoursePickerPage(
          courses: _allGolfCourses(),
          selectedCourseId: _selectedGolfCourse?.id,
          onAddCourse: _addCustomCourse,
        ),
      ),
    );
    if (selected != null) {
      await _selectGolfCourse(selected);
    }
  }

  Future<ParkGolfCourse> _addCustomCourse(ParkGolfCourse course) async {
    final savedCourse = ParkGolfCourse(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      region: course.region.trim().isEmpty ? '직접등록' : course.region.trim(),
      name: course.name.trim(),
      phone: course.phone.trim(),
      address: course.address.trim(),
      holeCount: course.holeCount,
      isUserAdded: true,
    );
    setState(() {
      _customCourses.insert(0, savedCourse);
    });
    await _saveCustomCourses();
    return savedCourse;
  }

  Future<void> _openSelectedCourseMap() async {
    final course = _selectedGolfCourse;
    if (course == null || course.address.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지도에서 볼 주소가 없습니다')),
      );
      return;
    }

    final query = Uri.encodeComponent('${course.name} ${course.address}');
    final uri = Uri.parse('https://map.kakao.com/link/search/$query');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지도 앱을 열지 못했습니다')),
      );
    }
  }

  Future<void> _pickRoundDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateValue(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dateController.text = _formatDisplayDate(picked);
    });
    _saveDraft();
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimeValue(),
    );
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    setState(() {
      _startTimeController.text = _formatDisplayTime(
        DateTime(now.year, now.month, now.day, picked.hour, picked.minute),
      );
    });
    _saveDraft();
  }

  void _clearScoresAndRoundProgress({bool resetDateTime = true}) {
    if (resetDateTime) {
      final now = DateTime.now();
      _dateController.text = _formatDisplayDate(now);
      _startTimeController.text = _formatDisplayTime(now);
    }
    _stepsController.clear();
    _stepBaseline = null;
    for (final hole in _holes) {
      for (final controller in hole.scoreControllers) {
        controller.clear();
      }
    }
  }

  Future<void> _startStepTracking({bool resetBaseline = false}) async {
    if (resetBaseline) {
      _stepBaseline = null;
    }

    final permission = await Permission.activityRecognition.request();
    if (!permission.isGranted) {
      if (!mounted) return;
      setState(() {
        _stepSensorActive = false;
        _stepSensorMessage = '걸음수 권한 필요';
      });
      return;
    }

    await _stepCountSubscription?.cancel();
    _stepCountSubscription = Pedometer.stepCountStream.listen(
      (event) {
        if (!mounted || !_gameStarted) return;
        setState(() {
          _stepBaseline ??= event.steps;
          final steps = event.steps - _stepBaseline!;
          _stepsController.text = steps < 0 ? '0' : steps.toString();
          _stepSensorActive = true;
          _stepSensorMessage = null;
        });
        _saveDraft();
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _stepSensorActive = false;
          _stepSensorMessage = '센서 미지원';
        });
      },
    );
  }

  Future<void> _stopStepTracking() async {
    await _stepCountSubscription?.cancel();
    _stepCountSubscription = null;
    if (!mounted) return;
    setState(() {
      _stepSensorActive = false;
    });
  }

  int _readNumber(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 0;
  }

  int _parTotal() {
    return _holes.fold(0, (sum, hole) => sum + hole.par);
  }

  int _scoreTotal(int playerIndex) {
    return _holes.fold(
      0,
      (sum, hole) => sum + _readNumber(hole.scoreControllers[playerIndex]),
    );
  }

  List<int> _activePlayerIndexes() {
    return [
      for (var index = 0; index < _playerCount; index++)
        if (_playerControllers[index].text.trim().isNotEmpty) index,
    ];
  }

  List<String> _activePlayerNames() {
    return [
      for (final index in _activePlayerIndexes())
        _playerControllers[index].text.trim(),
    ];
  }

  Iterable<int> _currentCourseIndexes() {
    final start = _activeCourseSlot == 0 ? 0 : 9;
    return Iterable<int>.generate(9, (index) => start + index);
  }

  String _slotCourseName(int slot) {
    final index = slot == 0 ? 0 : 9;
    return _holes[index].course;
  }

  int _currentParTotal() {
    return _currentCourseIndexes().fold(0, (sum, index) => sum + _holes[index].par);
  }

  int _currentScoreTotal(int playerIndex) {
    return _currentCourseIndexes().fold(
      0,
      (sum, index) => sum + _readNumber(_holes[index].scoreControllers[playerIndex]),
    );
  }

  int _distanceTotal(Iterable<int> indexes) {
    return indexes.fold(
      0,
      (sum, index) => sum + _readNumber(_holes[index].distanceController),
    );
  }

  Map<String, int> _scoreHighlights(int playerIndex, Iterable<int> indexes) {
    var eagleOrBetter = 0;
    var birdie = 0;
    for (final index in indexes) {
      final score = _readNumber(_holes[index].scoreControllers[playerIndex]);
      if (score == 0) continue;
      final diff = score - _holes[index].par;
      if (diff <= -2) {
        eagleOrBetter++;
      } else if (diff == -1) {
        birdie++;
      }
    }
    return {'eagleOrBetter': eagleOrBetter, 'birdie': birdie};
  }

  String _playerSummaryLine(
    int playerIndex, {
    required Iterable<int> indexes,
    required int total,
  }) {
    final highlights = _scoreHighlights(playerIndex, indexes);
    final parts = <String>[];
    if (highlights['eagleOrBetter']! > 0) {
      parts.add('이글 이상 ${highlights['eagleOrBetter']}');
    }
    if (highlights['birdie']! > 0) {
      parts.add('버디 ${highlights['birdie']}');
    }
    final suffix = parts.isEmpty ? '' : ' - ${parts.join(' / ')}';
    return '${_playerName(playerIndex)} : $total$suffix';
  }

  void _showCourseSlot(int slot) {
    setState(() {
      _activeCourseSlot = slot;
      _focusedHoleIndex = slot == 0 ? 0 : 9;
    });
    _saveDraft();
  }

  void _setScore(int holeIndex, int playerIndex, int score) {
    final safeScore = score.clamp(1, 15);
    setState(() {
      _focusedHoleIndex = holeIndex;
      _holes[holeIndex].scoreControllers[playerIndex].text = safeScore.toString();
    });
    _saveDraft();
    _advanceWhenHoleComplete(holeIndex);
  }

  void _changeScore(int holeIndex, int playerIndex, int delta) {
    final controller = _holes[holeIndex].scoreControllers[playerIndex];
    final current = int.tryParse(controller.text.trim()) ?? 3;
    _setScore(holeIndex, playerIndex, current + delta);
  }

  bool _holeScoresComplete(int holeIndex) {
    final activePlayers = _activePlayerIndexes();
    if (activePlayers.isEmpty) return false;
    for (final player in activePlayers) {
      if (_holes[holeIndex].scoreControllers[player].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _advanceWhenHoleComplete(int holeIndex) {
    if (!_holeScoresComplete(holeIndex)) return;

    final currentIndexes = _currentCourseIndexes().toList();
    final position = currentIndexes.indexOf(holeIndex);
    if (position < 0) return;

    if (position < currentIndexes.length - 1) {
      _focusHole(currentIndexes[position + 1]);
      return;
    }

    if (_activeCourseSlot == 0) {
      _showCourseSlot(1);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocusedHole());
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('마지막 홀까지 입력했습니다')),
    );
  }

  void _focusHole(int holeIndex) {
    setState(() {
      _focusedHoleIndex = holeIndex;
    });
    _saveDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocusedHole());
  }

  void _scrollToFocusedHole() {
    final context = _holeKeys[_focusedHoleIndex].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      alignment: 0.08,
    );
  }

  List<Map<String, dynamic>> _holeFactsForSharing() {
    final course = _selectedGolfCourse;
    if (course == null) return [];

    return [
      for (final hole in _holes)
        if (hole.distanceController.text.trim().isNotEmpty)
          {
            'courseId': course.id,
            'courseName': course.name,
            'courseCode': hole.course,
            'holeNo': hole.hole,
            'distanceM': _readNumber(hole.distanceController),
            'par': hole.par,
            'anonymousScores': [
              for (final controller in hole.scoreControllers)
                if (controller.text.trim().isNotEmpty) _readNumber(controller),
            ],
          },
    ];
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));

      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decodeStream(response);
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          (data['error'] as String?) ?? '서버 응답 오류 ${response.statusCode}',
          uri: uri,
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decodeStream(response);
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          (data['error'] as String?) ?? '서버 응답 오류 ${response.statusCode}',
          uri: uri,
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _loadServerHoleTemplatesForSelectedCourse({
    required bool overwriteExisting,
  }) async {
    final course = _selectedGolfCourse;
    if (course == null || int.tryParse(course.id) == null) return false;

    try {
      final uri = Uri.parse('$parkGolfApiBaseUrl$courseHolesApiPath').replace(
        queryParameters: {'course_id': course.id},
      );
      final data = await _getJson(uri);
      final rows = data['holes'] as List<dynamic>? ?? [];
      final templates = rows
          .whereType<Map<String, dynamic>>()
          .map((row) {
            final courseCode = (row['course_code'] ?? '').toString().trim();
            final holeNo = int.tryParse((row['hole_no'] ?? '').toString()) ?? 0;
            final distanceM =
                int.tryParse((row['distance_m'] ?? '').toString()) ?? 0;
            final par = int.tryParse((row['par'] ?? '').toString()) ?? 0;
            if (!['A', 'B', 'C', 'D'].contains(courseCode) ||
                holeNo < 1 ||
                holeNo > 9 ||
                distanceM < 1 ||
                par < 3 ||
                par > 5) {
              return null;
            }
            return MapEntry(
              '$courseCode-$holeNo',
              HoleTemplate(hole: holeNo, distanceM: distanceM, par: par),
            );
          })
          .whereType<MapEntry<String, HoleTemplate>>();

      final byCodeAndHole = <String, HoleTemplate>{};
      for (final entry in templates) {
        byCodeAndHole[entry.key] = entry.value;
      }
      if (byCodeAndHole.isEmpty || !mounted) return false;

      setState(() {
        for (final hole in _holes) {
          final template = byCodeAndHole['${hole.course}-${hole.hole}'];
          if (template == null) continue;
          if (!overwriteExisting && hole.distanceController.text.trim().isNotEmpty) {
            continue;
          }
          hole.distanceController.text = template.distanceM.toString();
          hole.par = template.par;
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> _submitHoleSuggestion({
    required String memo,
    required List<Map<String, dynamic>> facts,
  }) async {
    final course = _selectedGolfCourse;
    if (course == null) {
      throw const FormatException('골프장을 먼저 선택해 주세요');
    }

    final payload = {
      'suggestionType': 'hole',
      'payload': {
        'courseId': course.id,
        'courseName': course.name,
        'region': course.region,
        'address': course.address,
        'phone': course.phone,
        'roundDate': _dateController.text.trim(),
        'memo': memo.trim(),
        'appVersion': appVersion,
        'facts': facts,
      },
    };
    final uri = Uri.parse('$parkGolfApiBaseUrl$submitSuggestionPath');
    final result = await _postJson(uri, payload);
    return result['accepted'] as int? ?? facts.length;
  }

  Future<void> _showContributionConsent() async {
    final facts = _holeFactsForSharing();
    if (facts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제안할 홀 정보가 아직 없습니다')),
      );
      return;
    }

    final memoController = TextEditingController();
    final editableFacts = [
      for (final fact in facts)
        {
          'courseCode': TextEditingController(text: '${fact['courseCode']}'),
          'holeNo': TextEditingController(text: '${fact['holeNo']}'),
          'distanceM': TextEditingController(text: '${fact['distanceM']}'),
          'par': TextEditingController(text: '${fact['par']}'),
        },
    ];
    var sending = false;

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            final preparedFacts = <Map<String, dynamic>>[];
            for (final row in editableFacts) {
              final courseCode = row['courseCode']!.text.trim().toUpperCase();
              final holeNo = int.tryParse(row['holeNo']!.text.trim()) ?? 0;
              final distanceM =
                  int.tryParse(row['distanceM']!.text.trim()) ?? 0;
              final par = int.tryParse(row['par']!.text.trim()) ?? 0;
              if (courseCode.isEmpty && holeNo == 0 && distanceM == 0) {
                continue;
              }
              if (!['A', 'B', 'C', 'D'].contains(courseCode) ||
                  holeNo < 1 ||
                  holeNo > 9 ||
                  distanceM < 1 ||
                  distanceM > 300 ||
                  par < 3 ||
                  par > 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('코스, 홀, 거리, 파 값을 확인해 주세요')),
                );
                return;
              }
              preparedFacts.add({
                'courseCode': courseCode,
                'holeNo': holeNo,
                'distanceM': distanceM,
                'par': par,
              });
            }
            if (preparedFacts.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('전송할 홀 정보가 없습니다')),
              );
              return;
            }

            setDialogState(() => sending = true);
            try {
              final accepted = await _submitHoleSuggestion(
                memo: memoController.text,
                facts: preparedFacts,
              );
              if (!context.mounted) return;
              Navigator.of(context).pop(true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('홀 정보 $accepted개를 제안했습니다')),
              );
            } catch (error) {
              if (!context.mounted) return;
              setDialogState(() => sending = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('전송 실패: $error')),
              );
            }
          }

          return AlertDialog(
            title: const Text('홀 정보 제안'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${_selectedGolfCourse?.name ?? _placeController.text} · '
                      '플레이어 이름은 보내지 않습니다',
                    ),
                    const SizedBox(height: 12),
                    for (var index = 0; index < editableFacts.length; index++) ...[
                      Row(
                        children: [
                          SizedBox(
                            width: 72,
                            child: TextField(
                              controller: editableFacts[index]['courseCode'],
                              enabled: !sending,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: '코스',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: editableFacts[index]['holeNo'],
                              enabled: !sending,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '홀',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: editableFacts[index]['distanceM'],
                              enabled: !sending,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '거리',
                                suffixText: 'm',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: editableFacts[index]['par'],
                              enabled: !sending,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '파',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (index != editableFacts.length - 1)
                        const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: memoController,
                      enabled: !sending,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '메모',
                        hintText: '관리자가 확인할 내용을 적어 주세요',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: sending ? null : submit,
                child: Text(sending ? '전송 중' : '서버로 전송'),
              ),
            ],
          );
        },
      ),
    );

    memoController.dispose();
    for (final row in editableFacts) {
      for (final controller in row.values) {
        controller.dispose();
      }
    }
    if (submitted != true || !mounted) return;
  }

  String _playerName(int index) {
    final name = _playerControllers[index].text.trim();
    return name.isEmpty ? 'P${index + 1}' : name;
  }

  CourseInfo _courseInfo(String course) {
    final upper = course.trim().toUpperCase();
    for (var index = 0; index < courses.length; index++) {
      if (courses[index].name == upper) return courses[index];
    }
    final codeUnit = upper.isEmpty ? 0 : upper.codeUnitAt(0);
    final fallbackIndex = codeUnit <= 0 ? 0 : (codeUnit - 'A'.codeUnitAt(0)) % 4;
    return courses[fallbackIndex < 0 ? 0 : fallbackIndex];
  }

  String _courseSummary() {
    final first = _holes.first;
    final last = _holes.last;
    return '${first.course} ${first.hole}홀 - ${last.course} ${last.hole}홀 · 합계 ${_parTotal()}홀';
  }

  String _coursePairLabel() {
    return '${_slotCourseName(0)}+${_slotCourseName(1)}';
  }

  void _setDefaultCoursePair(String first, String second) {
    final firstCourse = first.trim().isEmpty ? 'A' : first.trim().toUpperCase();
    final secondCourse = second.trim().isEmpty ? 'B' : second.trim().toUpperCase();
    setState(() {
      _firstCourseController.text = firstCourse;
      _secondCourseController.text = secondCourse;
      for (var index = 0; index < _holes.length; index++) {
        _holes[index].course = index < 9 ? firstCourse : secondCourse;
        _holes[index].hole = (index % 9) + 1;
        _holes[index].par = defaultPars[_holes[index].hole - 1];
      }
    });
    _applyHoleTemplatesForSelectedCourse(overwriteExisting: false);
    _saveDraft();
  }

  void _startGame() {
    if (_activePlayerIndexes().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('플레이어 이름을 1명 이상 입력해 주세요')),
      );
      return;
    }

    setState(() {
      final firstCourse = _firstCourseController.text.trim().isEmpty
          ? 'A'
          : _firstCourseController.text.trim().toUpperCase();
      final secondCourse = _secondCourseController.text.trim().isEmpty
          ? 'B'
          : _secondCourseController.text.trim().toUpperCase();
      _firstCourseController.text = firstCourse;
      _secondCourseController.text = secondCourse;
      for (var index = 0; index < _holes.length; index++) {
        _holes[index].course = index < 9 ? firstCourse : secondCourse;
        _holes[index].hole = (index % 9) + 1;
      }
      _clearScoresAndRoundProgress();
      _gameStarted = true;
      _hasPausedGame = false;
      _setupOpenedFromScore = false;
      _activeCourseSlot = 0;
      _focusedHoleIndex = 0;
    });
    _rememberPlayerNames();
    _startStepTracking(resetBaseline: true);
    _saveDraft();
  }

  void _resumePausedGame() {
    setState(() {
      _gameStarted = true;
      _hasPausedGame = false;
      _setupOpenedFromScore = false;
    });
    _startStepTracking();
    _saveDraft();
  }

  void _pauseGame() {
    setState(() {
      _gameStarted = false;
      _hasPausedGame = true;
      _setupOpenedFromScore = false;
    });
    _stopStepTracking();
    _saveDraft(showMessage: true);
  }

  void _backToSetup() {
    setState(() {
      _gameStarted = false;
      _hasPausedGame = true;
      _setupOpenedFromScore = true;
    });
    _stopStepTracking();
    _saveDraft();
  }

  void _returnToScoreFromSetup() {
    setState(() {
      _gameStarted = true;
      _hasPausedGame = false;
      _setupOpenedFromScore = false;
    });
    _startStepTracking();
    _saveDraft();
  }

  @override
  Widget build(BuildContext context) {
    if (_gameStarted) {
      return _buildScoreScreen();
    }
    return PopScope(
      canPop: !_setupOpenedFromScore,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _setupOpenedFromScore) {
          _returnToScoreFromSetup();
        }
      },
      child: _buildSetupScreen(),
    );
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      appBar: AppBar(
        leading: _setupOpenedFromScore
            ? IconButton(
                tooltip: '스코어카드로 돌아가기',
                onPressed: _returnToScoreFromSetup,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: const Text('파크골프 스코어카드'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildSetupTopTabs(),
            const SizedBox(height: 12),
            if (_setupOpenedFromScore) ...[
              FilledButton.icon(
                onPressed: _returnToScoreFromSetup,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.scoreboard_outlined),
                label: const Text('스코어카드로 돌아가기'),
              ),
              const SizedBox(height: 12),
            ],
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '경기 설정',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _buildGameInfo(),
                  const SizedBox(height: 12),
                  _buildCourseQuickButtons(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _panel(child: _buildPlayerInputs()),
            const SizedBox(height: 16),
            if (_hasPausedGame) ...[
              FilledButton.tonalIcon(
                onPressed: _resumePausedGame,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('중단 경기 계속'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _startGame,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('새 경기 시작'),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _savedOnce ? '저장된 기록을 불러왔습니다' : appVersion,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupTopTabs() {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF173F35),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('경기'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: _coursesLoaded ? _openGolfCoursePicker : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0E6A55),
              minimumSize: const Size.fromHeight(44),
              side: const BorderSide(color: Color(0xFF16866A)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('골프장'),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreScreen() {
    final place = _placeController.text.trim().isEmpty
        ? '경기장 미입력'
        : _placeController.text.trim();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              _courseSummary(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          controller: _scoreScrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _buildGameActionBar(),
            const SizedBox(height: 8),
            _buildOverallSummary(),
            const SizedBox(height: 8),
            _buildCourseSwitcher(),
            const SizedBox(height: 8),
            _buildContributionPanel(),
            const SizedBox(height: 8),
            _buildCourseStatsLine(),
            _buildScoreCards(),
            const SizedBox(height: 12),
            _buildTotals(currentOnly: true),
            const SizedBox(height: 8),
            _buildNextCourseButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallSummary() {
    final indexes = Iterable<int>.generate(_holes.length);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF173F35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_coursePairLabel()} 코스 합계',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                width: 142,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: TextField(
                  controller: _stepsController,
                  keyboardType: TextInputType.number,
                  readOnly: _stepSensorActive,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF173F35),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: const InputDecoration(
                    hintText: '총 걸음수',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => _saveDraft(),
                ),
              ),
            ],
          ),
          if (_stepSensorActive || _stepSensorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              _stepSensorActive ? '폰 센서 자동 측정 중' : _stepSensorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 4.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 4,
            children: [
              for (final index in _activePlayerIndexes())
                _summaryMiniLine(
                  _playerName(index),
                  _scoreTotal(index),
                  indexes,
                  index,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameActionBar() {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.45,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: [
        _gameActionButton(
          icon: Icons.tune,
          label: '설정',
          onPressed: _backToSetup,
        ),
        _gameActionButton(
          icon: Icons.pause_circle_outline,
          label: '휴식',
          onPressed: _pauseGame,
        ),
        _gameActionButton(
          icon: Icons.history,
          label: '기록',
          onPressed: _openSavedRounds,
        ),
        _gameActionButton(
          icon: Icons.stop_circle_outlined,
          label: '종료',
          onPressed: _saveInterruptedRoundAndExit,
        ),
      ],
    );
  }

  Widget _gameActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFE5EFEA),
        foregroundColor: const Color(0xFF173F35),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _summaryMiniLine(
    String name,
    int total,
    Iterable<int> indexes,
    int playerIndex,
  ) {
    final highlights = _scoreHighlights(playerIndex, indexes);
    final text = highlights['eagleOrBetter']! > 0 || highlights['birdie']! > 0
        ? '$name $total · E${highlights['eagleOrBetter']} B${highlights['birdie']}'
        : '$name $total';
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildCourseSwitcher() {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: () => _showCourseSlot(0),
            style: FilledButton.styleFrom(
              backgroundColor:
                  _activeCourseSlot == 0 ? const Color(0xFF173F35) : const Color(0xFFE5EFEA),
              foregroundColor:
                  _activeCourseSlot == 0 ? Colors.white : const Color(0xFF173F35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('${_slotCourseName(0)}코스 보기'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: () => _showCourseSlot(1),
            style: FilledButton.styleFrom(
              backgroundColor:
                  _activeCourseSlot == 1 ? const Color(0xFF173F35) : const Color(0xFFE5EFEA),
              foregroundColor:
                  _activeCourseSlot == 1 ? Colors.white : const Color(0xFF173F35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('${_slotCourseName(1)}코스 보기'),
          ),
        ),
      ],
    );
  }

  Widget _buildContributionPanel() {
    final facts = _holeFactsForSharing();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7F3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD5E6DC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Color(0xFF16866A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '홀 정보 제안',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '거리 입력 ${facts.length}개 · 이름은 제외',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showContributionConsent,
            child: const Text('제안'),
          ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E6DE)),
      ),
      child: child,
    );
  }

  Widget _buildGameInfo() {
    final selectedCourse = _selectedGolfCourse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAF6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDCE6D9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedCourse?.name ?? '경기장을 선택하세요',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (selectedCourse != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${selectedCourse.region} · ${selectedCourse.holeCount}홀',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  selectedCourse.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _coursesLoaded ? _openGolfCoursePicker : null,
                      icon: const Icon(Icons.search),
                      label: Text(_coursesLoaded ? '골프장 선택' : '목록 읽는 중'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: '지도',
                    onPressed: _openSelectedCourseMap,
                    icon: const Icon(Icons.map_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _startTimeController,
                readOnly: true,
                onTap: _pickStartTime,
                decoration: const InputDecoration(
                  labelText: '시간',
                  suffixIcon: Icon(Icons.access_time),
                ),
                onChanged: (_) => _saveDraft(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _dateController,
                readOnly: true,
                onTap: _pickRoundDate,
                decoration: const InputDecoration(
                  labelText: '스타트 시간/날짜',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                onChanged: (_) => _saveDraft(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCourseQuickButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '코스',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.42,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _courseButton('A-B 기본', 'A', 'B'),
            _courseButton('C-D 기본', 'C', 'D'),
            _courseButton('B-A', 'B', 'A'),
            _courseButton('D-C', 'D', 'C'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _customCourseField(_firstCourseController)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('|', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            Expanded(child: _customCourseField(_secondCourseController)),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _setDefaultCoursePair(
                _firstCourseController.text,
                _secondCourseController.text,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('적용'),
            ),
            const SizedBox(width: 6),
            const Flexible(
              child: Text(
                '사용자 코스입력',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF173F35),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _customCourseField(TextEditingController controller) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      maxLength: 2,
      textAlign: TextAlign.center,
      decoration: const InputDecoration(
        counterText: '',
        labelText: '사용자 코스입력',
        isDense: true,
      ),
      onChanged: (_) => _saveDraft(),
    );
  }

  Widget _courseButton(String label, String first, String second) {
    final selected = _slotCourseName(0) == first && _slotCourseName(1) == second;
    return FilledButton(
      onPressed: () => _setDefaultCoursePair(first, second),
      style: FilledButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF173F35) : const Color(0xFFE5EFEA),
        foregroundColor: selected ? Colors.white : const Color(0xFF173F35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  Widget _buildPlayerInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '플레이어',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _playerCount,
          decoration: const InputDecoration(
            labelText: '플레이어 수',
            prefixIcon: Icon(Icons.groups_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1명')),
            DropdownMenuItem(value: 2, child: Text('2명')),
            DropdownMenuItem(value: 3, child: Text('3명')),
            DropdownMenuItem(value: 4, child: Text('4명')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _playerCount = value;
              for (var player = value; player < _playerControllers.length; player++) {
                for (final hole in _holes) {
                  hole.scoreControllers[player].clear();
                }
              }
            });
            _saveDraft();
          },
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _playerCount; index++) ...[
          TextField(
            controller: _playerControllers[index],
            decoration: InputDecoration(
              labelText: '플레이어 ${index + 1}',
              hintText: '이름입력',
              prefixIcon: const Icon(Icons.person_outline),
              suffixIcon: _playerNameHistory.isEmpty
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: '최근 이름',
                      icon: const Icon(Icons.expand_more),
                      onSelected: (name) {
                        setState(() {
                          _playerControllers[index].text = name;
                        });
                        _saveDraft();
                      },
                      itemBuilder: (context) => [
                        for (final name in _playerNameHistory)
                          PopupMenuItem(value: name, child: Text(name)),
                      ],
                    ),
            ),
            onChanged: (_) {
              setState(() {});
              _saveDraft();
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildScoreCards() {
    return Column(
      children: [
        for (final index in _currentCourseIndexes()) ...[
          KeyedSubtree(
            key: _holeKeys[index],
            child: _buildHoleCard(index),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildHoleCard(int index) {
    final hole = _holes[index];
    final info = _courseInfo(hole.course);
    final focused = index == _focusedHoleIndex;
    final completed = _holeScoresComplete(index);
    final headerColor = completed ? const Color(0xFFE4E8E3) : info.color;
    final headerTextColor = completed ? const Color(0xFF58645E) : info.textColor;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? const Color(0xFF16866A) : const Color(0xFFE0E6DE),
          width: focused ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: const Color(0x1F000000)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildHoleLabel(index, headerTextColor),
                ),
                const SizedBox(width: 8),
                _compactNumberField(hole.distanceController, '거리', 'm'),
                const SizedBox(width: 8),
                _buildParPicker(index, headerTextColor),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final player in _activePlayerIndexes())
                  _playerScoreField(index, player),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoleLabel(int index, Color textColor) {
    final hole = _holes[index];
    return Text(
      '${hole.course}코스 ${hole.hole}홀',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: textColor,
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _buildCourseStatsLine() {
    final indexes = _currentCourseIndexes();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '${_slotCourseName(_activeCourseSlot)}코스 파 ${_currentParTotal()} / 총 전장: ${_distanceTotal(indexes)}m',
        style: const TextStyle(
          color: Color(0xFF173F35),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildParPicker(int index, Color textColor) {
    return SizedBox(
      width: 66,
      child: DropdownButton<int>(
        value: _holes[index].par,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
        iconEnabledColor: textColor,
        items: const [
          DropdownMenuItem(value: 3, child: Text('P3')),
          DropdownMenuItem(value: 4, child: Text('P4')),
          DropdownMenuItem(value: 5, child: Text('P5')),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _holes[index].par = value;
          });
          _saveDraft();
        },
      ),
    );
  }

  Widget _compactNumberField(
    TextEditingController controller,
    String label,
    String suffix,
  ) {
    return SizedBox(
      width: 76,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
          filled: true,
          fillColor: const Color(0xEFFFFFFF),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
        ),
        onChanged: (_) => _saveDraft(),
      ),
    );
  }

  Widget _playerScoreField(int holeIndex, int playerIndex) {
    final controller = _holes[holeIndex].scoreControllers[playerIndex];
    final scoreText = controller.text.trim().isEmpty ? '3' : controller.text.trim();

    return Container(
      width: 156,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE6D9)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _playerName(playerIndex),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _scoreStepButton(
                icon: Icons.remove,
                label: '타수 감소',
                onPressed: () => _changeScore(holeIndex, playerIndex, -1),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FilledButton.tonal(
                    onPressed: () => _setScore(holeIndex, playerIndex, 3),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '$scoreText타',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              _scoreStepButton(
                icon: Icons.add,
                label: '타수 증가',
                onPressed: () => _changeScore(holeIndex, playerIndex, 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scoreStepButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon),
    );
  }

  Widget _buildNextCourseButton() {
    if (_activeCourseSlot == 0) {
      return FilledButton(
        onPressed: () => _showCourseSlot(1),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text('${_slotCourseName(1)}코스로 이동'),
      );
    }
    return OutlinedButton(
      onPressed: () => _showCourseSlot(0),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text('${_slotCourseName(0)}코스 다시 보기'),
    );
  }

  Widget _buildTotals({required bool currentOnly}) {
    final indexes = _currentCourseIndexes();
    final activePlayers = _activePlayerIndexes();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: currentOnly ? Colors.white : const Color(0xFF173F35),
        borderRadius: BorderRadius.circular(8),
        border: currentOnly ? Border.all(color: const Color(0xFFDCE6D9)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_slotCourseName(_activeCourseSlot)}코스 현재 합계',
            style: TextStyle(
              color: currentOnly ? const Color(0xFF173F35) : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (var item = 0; item < activePlayers.length; item++) ...[
            Text(
              _playerSummaryLine(
                activePlayers[item],
                indexes: indexes,
                total: _currentScoreTotal(activePlayers[item]),
              ),
              style: const TextStyle(
                color: Color(0xFF173F35),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (item < activePlayers.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

}

class GolfCoursePickerPage extends StatefulWidget {
  const GolfCoursePickerPage({
    super.key,
    required this.courses,
    required this.selectedCourseId,
    required this.onAddCourse,
  });

  final List<ParkGolfCourse> courses;
  final String? selectedCourseId;
  final Future<ParkGolfCourse> Function(ParkGolfCourse course) onAddCourse;

  @override
  State<GolfCoursePickerPage> createState() => _GolfCoursePickerPageState();
}

class SavedRoundsPage extends StatelessWidget {
  const SavedRoundsPage({
    super.key,
    required this.rounds,
  });

  final List<Map<String, dynamic>> rounds;

  String _shareText(Map<String, dynamic> round) {
    final players = (round['players'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();
    final totals = (round['totals'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();
    final buffer = StringBuffer()
      ..writeln('[파크골프 스코어카드]')
      ..writeln(round['courseName'] as String? ?? round['place'] as String? ?? '경기장 미입력')
      ..writeln(
        '${round['date'] as String? ?? ''} ${round['startTime'] as String? ?? ''}'
            .trim(),
      )
      ..writeln('총 걸음수 : ${round['steps'] ?? ''}')
      ..writeln('파 ${round['totalPar'] ?? 0}');
    for (var index = 0; index < players.length && index < totals.length; index++) {
      buffer.writeln('${players[index]} : ${totals[index]}');
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('저장된 기록')),
      body: SafeArea(
        child: rounds.isEmpty
            ? const Center(child: Text('저장된 기록이 없습니다'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: rounds.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final round = rounds[index];
                  final players = (round['players'] as List<dynamic>? ?? [])
                      .map((item) => item.toString())
                      .toList();
                  final totals = (round['totals'] as List<dynamic>? ?? [])
                      .map((item) => item.toString())
                      .toList();
                  final courseName = round['courseName'] as String?;
                  final place = round['place'] as String?;
                  final displayName = (courseName?.trim().isNotEmpty ?? false)
                      ? courseName!
                      : (place?.trim().isNotEmpty ?? false)
                          ? place!
                          : '경기장 미입력';

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDCE6D9)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${round['date'] as String? ?? ''} ${round['startTime'] as String? ?? ''} · ${round['status'] as String? ?? '저장'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if ((round['steps'] as String? ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '총 걸음수 : ${round['steps']}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('파 ${round['totalPar'] ?? 0}')),
                            for (var player = 0;
                                player < players.length && player < totals.length;
                                player++)
                              Chip(label: Text('${players[player]} ${totals[player]}')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => Share.share(_shareText(round)),
                            icon: const Icon(Icons.ios_share),
                            label: const Text('공유'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _GolfCoursePickerPageState extends State<GolfCoursePickerPage> {
  final TextEditingController _searchController = TextEditingController();
  late List<ParkGolfCourse> _courses;
  String? _selectedCourseId;

  @override
  void initState() {
    super.initState();
    _courses = widget.courses;
    _selectedCourseId = widget.selectedCourseId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ParkGolfCourse> _filteredCourses() {
    final keyword = _searchController.text.trim().toLowerCase();
    if (keyword.isEmpty) return _courses;
    return _courses.where((course) {
      return course.name.toLowerCase().contains(keyword) ||
          course.address.toLowerCase().contains(keyword) ||
          course.region.toLowerCase().contains(keyword);
    }).toList();
  }

  Future<void> _openAddCoursePage() async {
    final added = await Navigator.of(context).push<ParkGolfCourse>(
      MaterialPageRoute(
        builder: (_) => AddGolfCoursePage(onAddCourse: widget.onAddCourse),
      ),
    );
    if (added == null) return;
    setState(() {
      _courses = [added, ..._courses];
      _searchController.clear();
    });
    if (mounted) {
      Navigator.of(context).pop(added);
    }
  }

  Future<void> _openMap(ParkGolfCourse course) async {
    final query = Uri.encodeComponent('${course.name} ${course.address}');
    final uri = Uri.parse('https://map.kakao.com/link/search/$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final courses = _filteredCourses();
    return Scaffold(
      appBar: AppBar(
        title: const Text('골프장 선택'),
        actions: [
          IconButton(
            tooltip: '직접 등록',
            onPressed: _openAddCoursePage,
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: '이름, 지역, 주소 검색',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '등록 골프장 ${_courses.length}곳',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openAddCoursePage,
                    icon: const Icon(Icons.add),
                    label: const Text('없는 골프장 등록'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: courses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final course = courses[index];
                  final selected = course.id == _selectedCourseId;
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xFFDCE6D9),
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        course.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${course.region} · ${course.holeCount}홀\n${course.address}',
                      ),
                      isThreeLine: true,
                      leading: Icon(
                        course.isUserAdded
                            ? Icons.edit_location_alt_outlined
                            : Icons.flag_outlined,
                      ),
                      trailing: IconButton(
                        tooltip: '지도',
                        onPressed: () => _openMap(course),
                        icon: const Icon(Icons.map_outlined),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedCourseId = course.id;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: FilledButton.icon(
                onPressed: _selectedCourseId == null
                    ? null
                    : () {
                        final selectedCourse = _courses.firstWhere(
                          (course) => course.id == _selectedCourseId,
                        );
                        Navigator.of(context).pop(selectedCourse);
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.sports_golf),
                label: const Text('경기장으로 선택'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddGolfCoursePage extends StatefulWidget {
  const AddGolfCoursePage({
    super.key,
    required this.onAddCourse,
  });

  final Future<ParkGolfCourse> Function(ParkGolfCourse course) onAddCourse;

  @override
  State<AddGolfCoursePage> createState() => _AddGolfCoursePageState();
}

class _AddGolfCoursePageState extends State<AddGolfCoursePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _holeCountController = TextEditingController(text: '18');

  @override
  void dispose() {
    _nameController.dispose();
    _regionController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _holeCountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    if (name.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('골프장명과 주소를 입력해 주세요')),
      );
      return;
    }

    final course = await widget.onAddCourse(
      ParkGolfCourse(
        id: 'pending',
        region: _regionController.text.trim().isEmpty
            ? '직접등록'
            : _regionController.text.trim(),
        name: name,
        phone: _phoneController.text.trim(),
        address: address,
        holeCount: int.tryParse(_holeCountController.text.trim()) ?? 0,
        isUserAdded: true,
      ),
    );
    if (mounted) {
      Navigator.of(context).pop(course);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('없는 골프장 등록')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '골프장명',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _regionController,
              decoration: const InputDecoration(
                labelText: '지역',
                prefixIcon: Icon(Icons.public),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: '주소',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: '전화번호',
                prefixIcon: Icon(Icons.call_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _holeCountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '홀수',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('등록하고 선택'),
            ),
          ],
        ),
      ),
    );
  }
}
