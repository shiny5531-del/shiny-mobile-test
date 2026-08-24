import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
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
  final TextEditingController _stepsController = TextEditingController();
  final List<TextEditingController> _playerControllers = List.generate(
    4,
    (index) => TextEditingController(text: '플레이어 ${index + 1}'),
  );

  late final List<HoleEntry> _holes;
  List<ParkGolfCourse> _baseCourses = [];
  List<ParkGolfCourse> _customCourses = [];
  List<String> _playerNameHistory = [];
  Map<String, Map<String, List<HoleTemplate>>> _holeTemplates = {};
  ParkGolfCourse? _selectedGolfCourse;
  String? _draftSelectedCourseId;
  int _playerCount = 4;
  int _activeCourseSlot = 0;
  bool _gameStarted = false;
  bool _savedOnce = false;
  bool _coursesLoaded = false;

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDate(DateTime.now());
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
    _loadInitialData();
  }

  @override
  void dispose() {
    _placeController.dispose();
    _dateController.dispose();
    _stepsController.dispose();
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
    final csvText = await rootBundle.loadString(courseCsvAssetPath);
    final rows = const LineSplitter()
        .convert(csvText)
        .skip(1)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final baseCourses = [
      for (var index = 0; index < rows.length; index++)
        ParkGolfCourse.fromCsvRow(_parseCsvLine(rows[index]), index),
    ].where((course) => course.name.isNotEmpty).toList();

    final prefs = await SharedPreferences.getInstance();
    final customRaw = prefs.getString(customCoursesStorageKey);
    final customCourses = <ParkGolfCourse>[];
    if (customRaw != null) {
      final customData = jsonDecode(customRaw) as List<dynamic>;
      for (final item in customData) {
        customCourses.add(ParkGolfCourse.fromJson(item as Map<String, dynamic>));
      }
    }

    if (!mounted) return;
    setState(() {
      _baseCourses = baseCourses;
      _customCourses = customCourses;
      final allCourses = [...customCourses, ...baseCourses];
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
      _coursesLoaded = true;
    });
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

    for (final item in rows) {
      final row = item as Map<String, dynamic>;
      final name = (row['golf_name'] as String? ?? '').trim();
      final courseType = (row['course_type'] as String? ?? '').trim().toUpperCase();
      final holeInfoRaw = (row['hole_info_json'] as String? ?? '').trim();
      if (name.isEmpty || !['A', 'B', 'C', 'D'].contains(courseType)) continue;
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

      final key = _normalCourseName(name);
      templates.putIfAbsent(key, () => {});
      templates[key]![courseType] = holes;
    }

    if (!mounted) return;
    setState(() {
      _holeTemplates = templates;
    });
    _applyHoleTemplatesForSelectedCourse();
  }

  void _applyHoleTemplatesForSelectedCourse() {
    final course = _selectedGolfCourse;
    if (course == null || _holeTemplates.isEmpty) return;
    final key = _normalCourseName(course.name);
    final templates = _holeTemplates[key];
    if (templates == null) return;

    setState(() {
      for (var index = 0; index < _holes.length; index++) {
        final hole = _holes[index];
        final courseTemplates = templates[hole.course];
        if (courseTemplates == null) continue;
        HoleTemplate? template;
        for (final item in courseTemplates) {
          if (item.hole == hole.hole) {
            template = item;
            break;
          }
        }
        if (template == null) continue;
        if (hole.distanceController.text.trim().isNotEmpty) continue;
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
      _stepsController.text = data['steps'] as String? ?? '';
      _draftSelectedCourseId = data['selectedCourseId'] as String?;
      _activeCourseSlot = data['activeCourseSlot'] as int? ?? 0;
      _gameStarted = data['gameStarted'] as bool? ?? false;
      _playerCount = data['playerCount'] as int? ?? 4;
      final players = data['players'] as List<dynamic>? ?? [];
      for (var index = 0; index < _playerControllers.length; index++) {
        final playerName = index < players.length ? players[index] as String? : null;
        _playerControllers[index].text = playerName ?? '플레이어 ${index + 1}';
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
      'steps': _stepsController.text,
      'selectedCourseId': _selectedGolfCourse?.id,
      'activeCourseSlot': _activeCourseSlot,
      'gameStarted': _gameStarted,
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
    return {
      'id': 'round-${DateTime.now().millisecondsSinceEpoch}',
      'status': status,
      'place': _placeController.text,
      'date': _dateController.text,
      'steps': _stepsController.text,
      'courseName': _selectedGolfCourse?.name,
      'courseId': _selectedGolfCourse?.id,
      'playerCount': _playerCount,
      'players': _playerControllers.map((controller) => controller.text).toList(),
      'holes': _holes.map((hole) => hole.toJson()).toList(),
      'totalPar': _parTotal(),
      'totals': [
        for (var index = 0; index < _playerCount; index++) _scoreTotal(index),
      ],
      'savedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _saveRoundRecord() async {
    await _saveDraft();
    await _rememberPlayerNames();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(savedRoundsStorageKey);
    final rounds = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    rounds.insert(0, _roundSnapshot());
    await prefs.setString(savedRoundsStorageKey, jsonEncode(rounds.take(50).toList()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('저장 기록에 남겼습니다')),
    );
  }

  Future<void> _saveInterruptedRoundAndExit() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(savedRoundsStorageKey);
    final rounds = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    rounds.insert(0, _roundSnapshotWithStatus('중단'));
    await prefs.setString(savedRoundsStorageKey, jsonEncode(rounds.take(50).toList()));
    await _rememberPlayerNames();
    setState(() {
      _gameStarted = false;
      _activeCourseSlot = 0;
    });
    await _saveDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('중단된 스코어를 저장했습니다')),
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

  void _selectGolfCourse(ParkGolfCourse course) {
    setState(() {
      _selectedGolfCourse = course;
      _placeController.text = course.name;
    });
    _applyHoleTemplatesForSelectedCourse();
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
      _selectGolfCourse(selected);
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

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
    });
    _saveDraft();
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

  Future<void> _showContributionPreview() async {
    final facts = _holeFactsForSharing();
    if (facts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유할 거리 정보가 아직 없습니다')),
      );
      return;
    }

    final payload = const JsonEncoder.withIndent('  ').convert({
      'type': 'hole_fact_contribution',
      'version': 1,
      'facts': facts,
    });

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('공유 데이터 미리보기'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(payload),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: payload));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('공유 후보 데이터를 복사했습니다')),
              );
            },
            child: const Text('복사'),
          ),
        ],
      ),
    );
  }

  String _playerName(int index) {
    final name = _playerControllers[index].text.trim();
    return name.isEmpty ? 'P${index + 1}' : name;
  }

  CourseInfo _courseInfo(String course) {
    return courses.firstWhere((item) => item.name == course);
  }

  String _courseSummary() {
    final first = _holes.first;
    final last = _holes.last;
    return '${first.course} ${first.hole}홀 - ${last.course} ${last.hole}홀 · 합계 ${_parTotal()}홀';
  }

  void _setDefaultCoursePair(String first, String second) {
    setState(() {
      for (var index = 0; index < _holes.length; index++) {
        _holes[index].course = index < 9 ? first : second;
        _holes[index].hole = (index % 9) + 1;
        _holes[index].par = defaultPars[_holes[index].hole - 1];
      }
    });
    _applyHoleTemplatesForSelectedCourse();
    _saveDraft();
  }

  void _startGame() {
    setState(() {
      _gameStarted = true;
    });
    _rememberPlayerNames();
    _saveDraft();
  }

  void _backToSetup() {
    setState(() {
      _gameStarted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_gameStarted) {
      return _buildScoreScreen();
    }
    return _buildSetupScreen();
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('파크골프 스코어카드'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
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
            FilledButton(
              onPressed: _startGame,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('경기 시작'),
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
        actions: [
          IconButton(
            tooltip: '설정',
            onPressed: _backToSetup,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '종료',
            onPressed: _saveInterruptedRoundAndExit,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
          IconButton(
            tooltip: '저장 기록',
            onPressed: _openSavedRounds,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '기록 저장',
            onPressed: _saveRoundRecord,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
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
              const Expanded(
                child: Text(
                  'A+B 코스 합계',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                width: 126,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: TextField(
                  controller: _stepsController,
                  keyboardType: TextInputType.number,
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
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 4.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 4,
            children: [
              for (var index = 0; index < _playerCount; index++)
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
          child: FilledButton.tonal(
            onPressed: () => _showCourseSlot(0),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('${_slotCourseName(0)}코스 보기'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonal(
            onPressed: () => _showCourseSlot(1),
            style: FilledButton.styleFrom(
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
                  '홀 정보 공유 후보',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '거리 입력 ${facts.length}개 · 개인 타수는 제외',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _showContributionPreview,
            child: const Text('보기'),
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
        TextField(
          controller: _dateController,
          decoration: const InputDecoration(
            labelText: '날짜',
            prefixIcon: Icon(Icons.event_outlined),
          ),
          onChanged: (_) => _saveDraft(),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _courseButton('A-B 기본', 'A', 'B'),
            _courseButton('C-D 기본', 'C', 'D'),
          ],
        ),
      ],
    );
  }

  Widget _courseButton(String label, String first, String second) {
    return OutlinedButton(
      onPressed: () => _setDefaultCoursePair(first, second),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  Widget _buildPlayerInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          _buildHoleCard(index),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildHoleCard(int index) {
    final hole = _holes[index];
    final info = _courseInfo(hole.course);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E6DE)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: info.color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: const Color(0x1F000000)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildHoleLabel(index, info),
                ),
                const SizedBox(width: 8),
                _compactNumberField(hole.distanceController, '거리', 'm'),
                const SizedBox(width: 8),
                _buildParPicker(index, info),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var player = 0; player < _playerCount; player++)
                  _playerScoreField(index, player),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoleLabel(int index, CourseInfo info) {
    final hole = _holes[index];
    return Text(
      '${hole.course}코스 ${hole.hole}홀',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: info.textColor,
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

  Widget _buildParPicker(int index, CourseInfo info) {
    return SizedBox(
      width: 58,
      child: DropdownButton<int>(
        value: _holes[index].par,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: TextStyle(color: info.textColor, fontWeight: FontWeight.w800),
        iconEnabledColor: info.textColor,
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
    return SizedBox(
      width: 96,
      child: TextField(
        controller: _holes[holeIndex].scoreControllers[playerIndex],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: _playerName(playerIndex),
          suffixText: '타',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
        ),
        onChanged: (_) {
          setState(() {});
          _saveDraft();
        },
      ),
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
          for (var index = 0; index < _playerCount; index++) ...[
            Text(
              _playerSummaryLine(
                index,
                indexes: indexes,
                total: _currentScoreTotal(index),
              ),
              style: const TextStyle(
                color: Color(0xFF173F35),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (index < _playerCount - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _totalChip(String label, String value) {
    return Chip(
      backgroundColor: Colors.white,
      label: Text('$label $value'),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
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
      ..writeln(round['date'] as String? ?? '')
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
                          '${round['date'] as String? ?? ''} · ${round['status'] as String? ?? '저장'}',
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

  @override
  void initState() {
    super.initState();
    _courses = widget.courses;
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
                    label: const Text('없는 구장 등록'),
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
                  final selected = course.id == widget.selectedCourseId;
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
                      onTap: () => Navigator.of(context).pop(course),
                    ),
                  );
                },
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
      appBar: AppBar(title: const Text('없는 구장 등록')),
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
