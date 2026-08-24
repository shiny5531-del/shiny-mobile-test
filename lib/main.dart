import 'package:flutter/material.dart';

void main() {
  runApp(const ShinyMobileTestApp());
}

const String appVersion = 'v0.1.2-test';

class ShinyMobileTestApp extends StatelessWidget {
  const ShinyMobileTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '파크골프 스코어카드',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F8A70)),
        useMaterial3: true,
      ),
      home: const ScoreCardPage(),
    );
  }
}

class CourseInfo {
  const CourseInfo(this.name, this.label, this.color);

  final String name;
  final String label;
  final Color color;
}

const List<CourseInfo> courses = [
  CourseInfo('A', 'A 빨강', Color(0xFFD94141)),
  CourseInfo('B', 'B 청색', Color(0xFF2877D4)),
  CourseInfo('C', 'C 노랑', Color(0xFFE0A800)),
  CourseInfo('D', 'D 하양', Color(0xFFEFEFEF)),
];

const List<int> defaultPars = [3, 3, 3, 3, 4, 4, 4, 4, 5];

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
  int _playerCount = 4;

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDate(DateTime.now());
    _holes = List.generate(18, (index) {
      final isFirstNine = index < 9;
      final holeNumber = (index % 9) + 1;
      return HoleEntry(
        course: isFirstNine ? 'A' : 'B',
        hole: holeNumber,
        par: defaultPars[holeNumber - 1],
        distanceController: TextEditingController(),
        scoreControllers: List.generate(4, (_) => TextEditingController()),
      );
    });
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

  void _setDefaultCoursePair(String first, String second) {
    setState(() {
      for (var index = 0; index < _holes.length; index++) {
        _holes[index].course = index < 9 ? first : second;
        _holes[index].hole = (index % 9) + 1;
        _holes[index].par = defaultPars[_holes[index].hole - 1];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('파크골프 스코어카드'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildGameInfo(),
            const SizedBox(height: 16),
            _buildCourseQuickButtons(),
            const SizedBox(height: 16),
            _buildPlayerInputs(),
            const SizedBox(height: 16),
            _buildScoreTable(),
            const SizedBox(height: 16),
            _buildTotals(),
            const SizedBox(height: 12),
            Center(
              child: Text(
                appVersion,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _placeController,
          decoration: const InputDecoration(
            labelText: '경기장',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _dateController,
          decoration: const InputDecoration(
            labelText: '날짜',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildCourseQuickButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: () => _setDefaultCoursePair('A', 'B'),
          child: const Text('A-B 기본'),
        ),
        FilledButton.tonal(
          onPressed: () => _setDefaultCoursePair('C', 'D'),
          child: const Text('C-D 기본'),
        ),
      ],
    );
  }

  Widget _buildPlayerInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          value: _playerCount,
          decoration: const InputDecoration(
            labelText: '플레이어 수',
            border: OutlineInputBorder(),
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
          },
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _playerCount; index++) ...[
          TextField(
            controller: _playerControllers[index],
            decoration: InputDecoration(
              labelText: '플레이어 ${index + 1}',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildScoreTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 12,
        headingRowHeight: 44,
        dataRowMinHeight: 58,
        dataRowMaxHeight: 66,
        columns: [
          const DataColumn(label: Text('홀')),
          const DataColumn(label: Text('거리(m)')),
          const DataColumn(label: Text('파')),
          for (var index = 0; index < _playerCount; index++)
            DataColumn(label: Text(_playerName(index))),
        ],
        rows: [
          for (var index = 0; index < _holes.length; index++)
            DataRow(
              cells: [
                DataCell(_buildHolePicker(index)),
                DataCell(_numberField(_holes[index].distanceController, 'm')),
                DataCell(_buildParPicker(index)),
                for (var player = 0; player < _playerCount; player++)
                  DataCell(
                    _numberField(
                      _holes[index].scoreControllers[player],
                      '타',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHolePicker(int index) {
    final hole = _holes[index];
    final info = _courseInfo(hole.course);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 32,
          decoration: BoxDecoration(
            color: info.color,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: hole.course,
          dropdownColor: Colors.white,
          underline: const SizedBox.shrink(),
          items: [
            for (final course in courses)
              DropdownMenuItem(
                value: course.name,
                child: Text(course.label),
              ),
          ],
          selectedItemBuilder: (_) => [
            for (final course in courses)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: course.color,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  course.name,
                  style: TextStyle(
                    color: course.name == 'D'
                        ? const Color(0xFF303030)
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              hole.course = value;
            });
          },
        ),
        const SizedBox(width: 4),
        DropdownButton<int>(
          value: hole.hole,
          underline: const SizedBox.shrink(),
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
          },
        ),
      ],
    );
  }

  Widget _buildParPicker(int index) {
    return DropdownButton<int>(
      value: _holes[index].par,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: 3, child: Text('3')),
        DropdownMenuItem(value: 4, child: Text('4')),
        DropdownMenuItem(value: 5, child: Text('5')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _holes[index].par = value;
        });
      },
    );
  }

  Widget _numberField(TextEditingController controller, String suffix) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          suffixText: suffix,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTotals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '합계',
          style: Theme.of(context).textTheme.titleLarge,
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
    );
  }

  Widget _totalChip(String label, String value) {
    return Chip(
      label: Text('$label $value'),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}
