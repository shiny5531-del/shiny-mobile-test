import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const ShinyMobileTestApp());
}

const String appVersion = 'v0.1.4-test';
const String draftStorageKey = 'park_golf_scorecard_draft_v1';
const String customCoursesStorageKey = 'park_golf_custom_courses_v1';
const String courseCsvAssetPath = 'assets/data/park_golf_courses_kr.csv';

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
  CourseInfo('A', 'A 코스', Color(0xFFE54848), Colors.white),
  CourseInfo('B', 'B 코스', Color(0xFF2673CF), Colors.white),
  CourseInfo('C', 'C 코스', Color(0xFFF0C337), Color(0xFF2D2D2D)),
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

class ScoreCardPage extends StatefulWidget {
  const ScoreCardPage({super.key});

  @override
  State<ScoreCardPage> createState() => _ScoreCardPageState();
}

class _ScoreCardPageState extends State<ScoreCardPage> {
  final TextEditingController _placeController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final List<TextEditingController> _playerControllers = List.generate(
    4,
    (index) => TextEditingController(text: '플레이어 ${index + 1}'),
  );

  late final List<HoleEntry> _holes;
  List<ParkGolfCourse> _baseCourses = [];
  List<ParkGolfCourse> _customCourses = [];
  ParkGolfCourse? _selectedGolfCourse;
  String? _draftSelectedCourseId;
  int _playerCount = 4;
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
    await _loadCourses();
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
      _draftSelectedCourseId = data['selectedCourseId'] as String?;
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
      'selectedCourseId': _selectedGolfCourse?.id,
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
        const SnackBar(content: Text('이 기기에 저장했습니다')),
      );
    }
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
    return '${first.course} ${first.hole}홀 - ${last.course} ${last.hole}홀';
  }

  void _setDefaultCoursePair(String first, String second) {
    setState(() {
      for (var index = 0; index < _holes.length; index++) {
        _holes[index].course = index < 9 ? first : second;
        _holes[index].hole = (index % 9) + 1;
        _holes[index].par = defaultPars[_holes[index].hole - 1];
      }
    });
    _saveDraft();
  }

  void _startGame() {
    setState(() {
      _gameStarted = true;
    });
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
            tooltip: '저장',
            onPressed: () => _saveDraft(showMessage: true),
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _buildScoreCards(),
            const SizedBox(height: 12),
            _buildTotals(),
          ],
        ),
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
        for (var index = 0; index < _holes.length; index++) ...[
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
                  child: _buildHolePicker(index, info),
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

  Widget _buildHolePicker(int index, CourseInfo info) {
    final hole = _holes[index];
    final foreground = info.textColor;

    return Row(
      children: [
        DropdownButton<String>(
          value: hole.course,
          dropdownColor: Colors.white,
          underline: const SizedBox.shrink(),
          style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
          iconEnabledColor: foreground,
          items: [
            for (final course in courses)
              DropdownMenuItem(
                value: course.name,
                child: Text(
                  course.label,
                  style: TextStyle(
                    color: course.textColor == Colors.white
                        ? course.color
                        : const Color(0xFF2D2D2D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              hole.course = value;
            });
            _saveDraft();
          },
        ),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: hole.hole,
          underline: const SizedBox.shrink(),
          style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
          iconEnabledColor: foreground,
          items: [
            for (var number = 1; number <= 9; number++)
              DropdownMenuItem(value: number, child: Text('$number홀')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              hole.hole = value;
              hole.par = defaultPars[value - 1];
            });
            _saveDraft();
          },
        ),
      ],
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

  Widget _buildTotals() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF173F35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '합계',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _totalChip('파', _parTotal().toString()),
              for (var index = 0; index < _playerCount; index++)
                _totalChip(_playerName(index), _scoreTotal(index).toString()),
            ],
          ),
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
