// main.dart
// Flutter Anime Tracker - Single file (MVP pattern) with SQLite storage.
// Requires: sqflite, path, path_provider (see pubspec note above).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:fl_chart/fl_chart.dart';
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnimeTrackerApp());
}

class AnimeTrackerApp extends StatelessWidget {
  const AnimeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final orange = Colors.orange;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Anime Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: orange,
        scaffoldBackgroundColor: const Color(0xFFFFF8F1),
        appBarTheme: const AppBarTheme(centerTitle: true),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.orange.shade100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: Colors.transparent),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

const kCategories = <String>[
  "Shonen","Seinen","Shojo","Isekai","Slice of Life","Sports","Mecha",
  "Fantasy","Sci-Fi","Horror","Mystery","Romance","Comedy","Historical",
  "Adventure","Drama","Music","Psychological","Supernatural","Thriller"
];

const kStatuses = <String>["Watching", "Watched", "To Watch", "On Hold", "Dropped"];

enum SortBy { name, date, progress }

extension SortByX on SortBy {
  String get label => switch (this) {
    SortBy.name => "Name (A→Z)",
    SortBy.date => "Date Started (Newest)",
    SortBy.progress => "Progress (High→Low)",
  };
}

// --------------------------- MODEL ---------------------------

class AnimeEntry {
  final int? id;
  final String name;
  final String category;
  final DateTime? startDate;
  final int episodesWatched;
  final int totalEpisodes;
  final String status;
  final double rating; // 0-10
  final String notes;

  AnimeEntry({
    this.id,
    required this.name,
    required this.category,
    required this.startDate,
    required this.episodesWatched,
    required this.totalEpisodes,
    required this.status,
    required this.rating,
    required this.notes,
  });

  double get progress =>
      totalEpisodes <= 0 ? 0 : (episodesWatched / totalEpisodes).clamp(0, 1).toDouble();

  AnimeEntry copyWith({
    int? id,
    String? name,
    String? category,
    DateTime? startDate,
    int? episodesWatched,
    int? totalEpisodes,
    String? status,
    double? rating,
    String? notes,
  }) {
    return AnimeEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      episodesWatched: episodesWatched ?? this.episodesWatched,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      notes: notes ?? this.notes,
    );
  }

  factory AnimeEntry.fromMap(Map<String, Object?> m) => AnimeEntry(
    id: m['id'] as int?,
    name: (m['name'] as String).trim(),
    category: m['category'] as String,
    startDate:
    (m['startDate'] as String?) == null ? null : DateTime.tryParse(m['startDate'] as String),
    episodesWatched: (m['episodesWatched'] as int?) ?? 0,
    totalEpisodes: (m['totalEpisodes'] as int?) ?? 0,
    status: m['status'] as String,
    rating: ((m['rating'] as num?) ?? 0).toDouble(),
    notes: (m['notes'] as String?) ?? '',
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'startDate': startDate?.toIso8601String(),
    'episodesWatched': episodesWatched,
    'totalEpisodes': totalEpisodes,
    'status': status,
    'rating': rating,
    'notes': notes,
  };
}

// --------------------------- DATA / REPO ---------------------------

class AnimeRepository {
  AnimeRepository._();
  static final AnimeRepository instance = AnimeRepository._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'anime_tracker.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''
        CREATE TABLE anime(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          category TEXT NOT NULL,
          startDate TEXT,
          episodesWatched INTEGER NOT NULL,
          totalEpisodes INTEGER NOT NULL,
          status TEXT NOT NULL,
          rating REAL NOT NULL,
          notes TEXT
        );
        ''');
        await d.execute('CREATE INDEX idx_anime_name ON anime(name);');
        await d.execute('CREATE INDEX idx_anime_category ON anime(category);');
        await d.execute('CREATE INDEX idx_anime_status ON anime(status);');
      },
    );
    return _db!;
  }

  Future<int> insert(AnimeEntry e) async {
    final d = await db;
    return d.insert('anime', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> update(AnimeEntry e) async {
    final d = await db;
    return d.update('anime', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<int> delete(int id) async {
    final d = await db;
    return d.delete('anime', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<AnimeEntry>> all({
    String? query,
    String? category,
    String? status,
    SortBy sortBy = SortBy.name,
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      where.add('LOWER(name) LIKE ?');
      args.add('%${query.toLowerCase()}%');
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      args.add(status);
    }
    final orderBy = switch (sortBy) {
      SortBy.name => 'LOWER(name) ASC',
      SortBy.date => 'datetime(startDate) DESC NULLS LAST',
      SortBy.progress => '(CAST(episodesWatched AS REAL)/NULLIF(totalEpisodes,0)) DESC',
    };
    final rows = await d.query(
      'anime',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: orderBy,
    );
    return rows.map(AnimeEntry.fromMap).toList();
  }

  Future<Analytics> analytics() async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM anime')) ?? 0;
    final watched = Sqflite.firstIntValue(
      await d.rawQuery("SELECT COUNT(*) FROM anime WHERE status = 'Watched'"),
    ) ??
        0;
    final watching = Sqflite.firstIntValue(
      await d.rawQuery("SELECT COUNT(*) FROM anime WHERE status = 'Watching'"),
    ) ??
        0;
    final toWatch = Sqflite.firstIntValue(
      await d.rawQuery("SELECT COUNT(*) FROM anime WHERE status = 'To Watch'"),
    ) ??
        0;

    final epSum = Sqflite.firstIntValue(
      await d.rawQuery('SELECT SUM(episodesWatched) FROM anime'),
    ) ??
        0;

    final byCategoryRaw = await d.rawQuery(
        'SELECT category, COUNT(*) as c FROM anime GROUP BY category ORDER BY c DESC LIMIT 6');
    final byCategory = <String, int>{
      for (final r in byCategoryRaw) (r['category'] as String): (r['c'] as int)
    };

    // Average completion rate (episodesWatched/totalEpisodes across entries with totalEpisodes>0)
    final rows = await d.rawQuery(
        'SELECT episodesWatched, totalEpisodes FROM anime WHERE totalEpisodes > 0');
    double avgCompletion = 0;
    if (rows.isNotEmpty) {
      avgCompletion = rows
          .map((r) =>
          ((r['episodesWatched'] as int) / (r['totalEpisodes'] as int))
              .clamp(0, 1)
              .toDouble())
          .fold<double>(0, (a, b) => a + b) /
          rows.length;
    }

    // Mean rating (only entries with rating > 0)
    final ratingRows = await d.rawQuery('SELECT rating FROM anime WHERE rating > 0');
    double meanRating = 0;
    if (ratingRows.isNotEmpty) {
      meanRating = ratingRows
          .map((r) => ((r['rating'] as num).toDouble()))
          .fold<double>(0, (a, b) => a + b) /
          ratingRows.length;
    }

    return Analytics(
      total: count,
      watched: watched,
      watching: watching,
      toWatch: toWatch,
      episodesWatched: epSum,
      topCategories: byCategory,
      avgCompletion: avgCompletion,
      meanRating: meanRating,
    );
  }
}

class Analytics {
  final int total, watched, watching, toWatch, episodesWatched;
  final Map<String, int> topCategories;
  final double avgCompletion; // 0..1
  final double meanRating; // 0..10
  Analytics({
    required this.total,
    required this.watched,
    required this.watching,
    required this.toWatch,
    required this.episodesWatched,
    required this.topCategories,
    required this.avgCompletion,
    required this.meanRating,
  });
}

// --------------------------- MVP: VIEWS ---------------------------

abstract class AddView {
  void showSnack(String msg);
  void clearForm();
}

abstract class ListViewV {
  void renderList(List<AnimeEntry> items);
  void showSnack(String msg);
}

abstract class AnalyticsView {
  void renderAnalytics(Analytics a);
}

// --------------------------- MVP: PRESENTERS ---------------------------

class AddPresenter {
  final AddView view;
  final AnimeRepository repo;
  AddPresenter(this.view, this.repo);

  Future<void> save(AnimeEntry e) async {
    if (e.name.trim().isEmpty) {
      view.showSnack('Name is required.');
      return;
    }
    if (!kCategories.contains(e.category)) {
      view.showSnack('Please choose a valid category.');
      return;
    }
    if (!kStatuses.contains(e.status)) {
      view.showSnack('Please choose a valid status.');
      return;
    }
    if (e.episodesWatched < 0 || e.totalEpisodes < 0) {
      view.showSnack('Episodes cannot be negative.');
      return;
    }
    if (e.episodesWatched > e.totalEpisodes && e.totalEpisodes > 0) {
      view.showSnack('Watched cannot exceed total episodes.');
      return;
    }
    await repo.insert(e);
    view.showSnack('Saved!');
    view.clearForm();
  }
}

class ListPresenter {
  final ListViewV view;
  final AnimeRepository repo;
  ListPresenter(this.view, this.repo);

  String _q = '';
  String _cat = '';
  String _status = '';
  SortBy _sort = SortBy.name;

  Future<void> load() async {
    final items = await repo.all(
      query: _q.isEmpty ? null : _q,
      category: _cat.isEmpty ? null : _cat,
      status: _status.isEmpty ? null : _status,
      sortBy: _sort,
    );
    view.renderList(items);
  }

  Future<void> delete(int id) async {
    await repo.delete(id);
    view.showSnack('Deleted.');
    await load();
  }

  void updateQuery(String q) {
    _q = q;
    load();
  }

  void updateCat(String value) {
    _cat = value;
    load();
  }

  void updateStatus(String value) {
    _status = value;
    load();
  }

  void updateSort(SortBy s) {
    _sort = s;
    load();
  }

  void clearFilters() {
    _q = '';
    _cat = '';
    _status = '';
    _sort = SortBy.name;
    load();
  }
}

class AnalyticsPresenter {
  final AnalyticsView view;
  final AnimeRepository repo;
  AnalyticsPresenter(this.view, this.repo);

  Future<void> load() async {
    final a = await repo.analytics();
    view.renderAnalytics(a);
  }
}

// --------------------------- UI ---------------------------

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Anime Tracker'),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.add_box_outlined), text: 'Add'),
              Tab(icon: Icon(Icons.list_alt), text: 'Library'),
              Tab(icon: Icon(Icons.insights), text: 'Analytics'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AddPage(),
            ListPage(),
            AnalyticsPage(),
          ],
        ),
      ),
    );
  }
}

// --------------------------- Page 1: Add ---------------------------

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> implements AddView {
  late final AddPresenter presenter;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _category = kCategories.first;
  DateTime? _startDate;
  final _epWatched = TextEditingController(text: '0');
  final _epTotal = TextEditingController(text: '12');
  String _status = kStatuses.first;
  double _rating = 0;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    presenter = AddPresenter(this, AnimeRepository.instance);
  }

  @override
  void dispose() {
    _name.dispose();
    _epWatched.dispose();
    _epTotal.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  void clearForm() {
    setState(() {
      _name.clear();
      _category = kCategories.first;
      _startDate = null;
      _epWatched.text = '0';
      _epTotal.text = '12';
      _status = kStatuses.first;
      _rating = 0;
      _notes.clear();
    });
  }

  @override
  void showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDate: _startDate ?? now,
      helpText: 'Select Start Date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.orange),
        ),
        child: child!,
      ),
    );
    if (d != null) setState(() => _startDate = d);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const _SectionTitle('Basic Info'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Anime name',
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _DropdownField<String>(
                      label: 'Category',
                      value: _category,
                      items: kCategories,
                      icon: Icons.category_outlined,
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DropdownField<String>(
                      label: 'Status',
                      value: _status,
                      items: kStatuses,
                      icon: Icons.flag_outlined,
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(16),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date started',
                      prefixIcon: Icon(Icons.date_range),
                    ),
                    child: Text(
                      _startDate == null
                          ? 'Tap to select'
                          : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('Episodes & Rating'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _epWatched,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Episodes watched',
                        prefixIcon: Icon(Icons.playlist_add_check_circle_outlined),
                      ),
                      validator: _nonNegativeInt,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _epTotal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Total episodes',
                        prefixIcon: Icon(Icons.format_list_numbered),
                      ),
                      validator: _nonNegativeInt,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Rating'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Slider(
                        value: _rating,
                        min: 0,
                        max: 10,
                        divisions: 20,
                        label: _rating.toStringAsFixed(1),
                        activeColor: Colors.orange,
                        onChanged: (v) => setState(() => _rating = v),
                      ),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.note_alt_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      final entry = AnimeEntry(
                        name: _name.text.trim(),
                        category: _category,
                        startDate: _startDate,
                        episodesWatched: int.tryParse(_epWatched.text) ?? 0,
                        totalEpisodes: int.tryParse(_epTotal.text) ?? 0,
                        status: _status,
                        rating: _rating,
                        notes: _notes.text.trim(),
                      );
                      await presenter.save(entry);
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String? _nonNegativeInt(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Required';
    final n = int.tryParse(t);
    if (n == null || n < 0) return 'Enter a non-negative number';
    return null;
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style:
      Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _DropdownField<T extends Object> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final IconData icon;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, // take all available width
      child: DropdownButtonFormField<T>(
        isExpanded: true, // prevent internal row overflow
        value: value,
        items: items
            .map(
              (e) => DropdownMenuItem<T>(
            value: e,
            child: Text(
              '$e',
              maxLines: 1,
              overflow: TextOverflow.ellipsis, // truncate long text
            ),
          ),
        )
            .toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          // keep the prefix icon compact so it doesn't squeeze the field
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

}

// --------------------------- Page 2: Library ---------------------------
class ListPage extends StatefulWidget {
  const ListPage({super.key});

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> implements ListViewV {
  late final ListPresenter presenter;
  final _search = TextEditingController();
  String _cat = '';
  String _status = '';
  SortBy _sort = SortBy.name;

  List<AnimeEntry> _items = [];

  @override
  void initState() {
    super.initState();
    presenter = ListPresenter(this, AnimeRepository.instance);
    presenter.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void renderList(List<AnimeEntry> items) {
    setState(() => _items = items);
  }

  @override
  void showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: presenter.updateQuery,
                  decoration: InputDecoration(
                    hintText: 'Search by name...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                      onPressed: () {
                        _search.clear();
                        presenter.updateQuery('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PopupFilter(
                icon: Icons.filter_list,
                child: _FilterSheet(
                  initialCategory: _cat,
                  initialStatus: _status,
                  initialSort: _sort,
                  onApply: (cat, st, sort) {
                    setState(() {
                      _cat = cat;
                      _status = st;
                      _sort = sort;
                    });
                    presenter.updateCat(cat);
                    presenter.updateStatus(st);
                    presenter.updateSort(sort);
                  },
                  onClear: () {
                    setState(() {
                      _cat = '';
                      _status = '';
                      _sort = SortBy.name;
                      _search.clear();
                    });
                    presenter.clearFilters();
                  },
                ),
              ),
            ],
          ),
        ),
        if (_cat.isNotEmpty || _status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                if (_cat.isNotEmpty)
                  Chip(
                    label: Text('Category: $_cat'),
                    deleteIcon: const Icon(Icons.close),
                    onDeleted: () {
                      setState(() => _cat = '');
                      presenter.updateCat('');
                    },
                  ),
                if (_status.isNotEmpty)
                  Chip(
                    label: Text('Status: $_status'),
                    deleteIcon: const Icon(Icons.close),
                    onDeleted: () {
                      setState(() => _status = '');
                      presenter.updateStatus('');
                    },
                  ),
                Chip(
                  label: Text('Sort: ${_sort.label}'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _items.isEmpty
              ? const _EmptyState()
              : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _items.length,
            itemBuilder: (c, i) => _AnimeTile(
              e: _items[i],
              onDelete: () => presenter.delete(_items[i].id!),
              onIncrement: () async {
                final cur = _items[i];
                final updated = cur.copyWith(
                  episodesWatched: (cur.episodesWatched + 1)
                      .clamp(0, cur.totalEpisodes),
                );
                await AnimeRepository.instance.update(updated);
                presenter.load();
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _PopupFilter extends StatelessWidget {
  final Widget child;
  final IconData icon;
  const _PopupFilter({required this.child, required this.icon});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      style: IconButton.styleFrom(
        backgroundColor: Colors.orange.shade100,
      ),
      icon: Icon(icon, color: Colors.orange),
      onPressed: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: const Color(0xFFFFFCF7),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => child,
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final String initialCategory;
  final String initialStatus;
  final SortBy initialSort;
  final void Function(String category, String status, SortBy sort) onApply;
  final VoidCallback onClear;

  const _FilterSheet({
    required this.initialCategory,
    required this.initialStatus,
    required this.initialSort,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _cat = widget.initialCategory;
  late String _status = widget.initialStatus;
  late SortBy _sort = widget.initialSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Text('Filters & Sort',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onClear,
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
            ),
          ]),
          const SizedBox(height: 8),
          _DropdownField<String>(
            label: 'Category (optional)',
            value: _cat,
            items: [''] + kCategories,
            icon: Icons.category_outlined,
            onChanged: (v) => setState(() => _cat = (v ?? '')),
          ),
          const SizedBox(height: 12),
          _DropdownField<String>(
            label: 'Status (optional)',
            value: _status,
            items: [''] + kStatuses,
            icon: Icons.flag_outlined,
            onChanged: (v) => setState(() => _status = (v ?? '')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SortBy>(
            value: _sort,
            items: SortBy.values
                .map((e) =>
                DropdownMenuItem(value: e, child: Text(e.label)))
                .toList(),
            onChanged: (v) => setState(() => _sort = v ?? SortBy.name),
            decoration: const InputDecoration(
              labelText: 'Sort by',
              prefixIcon: Icon(Icons.sort),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                widget.onApply(_cat, _status, _sort);
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _AnimeTile extends StatelessWidget {
  final AnimeEntry e;
  final VoidCallback onDelete;
  final VoidCallback onIncrement;
  const _AnimeTile(
      {required this.e, required this.onDelete, required this.onIncrement});

  @override
  Widget build(BuildContext context) {
    final pc = (e.progress * 100).toStringAsFixed(0);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child:
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.orange.shade100,
            child: Text(
              e.name.isNotEmpty
                  ? e.name.characters.first.toUpperCase()
                  : '?',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(e.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(e.status,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Chip(
                          icon: Icons.category_outlined,
                          text: e.category),
                      if (e.startDate != null)
                        _Chip(
                            icon: Icons.date_range,
                            text:
                            '${e.startDate!.year}-${e.startDate!.month.toString().padLeft(2, '0')}-${e.startDate!.day.toString().padLeft(2, '0')}'),
                      _Chip(
                          icon: Icons.star_rate,
                          text: e.rating.toStringAsFixed(1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: e.progress.isNaN ? 0 : e.progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(12),
                    backgroundColor: Colors.orange.shade50,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'Progress: ${e.episodesWatched}/${e.totalEpisodes} ($pc%)',
                      style: const TextStyle(fontSize: 12)),
                  if (e.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(e.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic,
                        )),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onIncrement,
                        icon: const Icon(Icons.add),
                        label: const Text('Ep +1'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        label: const Text('Delete',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  )
                ]),
          ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: Colors.orange.shade50,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      avatar: Icon(icon, size: 18, color: Colors.orange),
      label: Text(text),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.hourglass_empty,
            size: 56, color: Colors.orange.shade300),
        const SizedBox(height: 8),
        const Text('No entries yet'),
        const SizedBox(height: 4),
        Text('Add your first anime from the "Add" tab',
            style: TextStyle(color: Colors.grey.shade600)),
      ]),
    );
  }
}


// --------------------------- Page 3: Analytics ---------------------------


class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  Database? _db;

  double completion = 0;
  double rating = 0;
  Map<String, int> categories = {};
  List<FlSpot> episodes = [];

  @override
  void initState() {
    super.initState();
    _initDb();
  }

  Future<void> _initDb() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'analytics.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE analytics(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            completion REAL,
            rating REAL
          );
        ''');
        await db.execute('''
          CREATE TABLE categories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            value INTEGER
          );
        ''');
        await db.execute('''
          CREATE TABLE episodes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day INTEGER,
            count INTEGER
          );
        ''');

        /// 🔹 insert dummy data (only first run)
        await db.insert("analytics", {"completion": 76.0, "rating": 8.4});
        await db.insert("categories", {"name": "Action", "value": 30});
        await db.insert("categories", {"name": "Drama", "value": 25});
        await db.insert("categories", {"name": "Comedy", "value": 20});
        await db.insert("categories", {"name": "Romance", "value": 15});
        await db.insert("categories", {"name": "Fantasy", "value": 10});
        for (int i = 0; i < 6; i++) {
          await db.insert("episodes", {"day": i, "count": (i + 1) * 2});
        }
      },
    );
    _loadData();
  }

  Future<void> _loadData() async {
    if (_db == null) return;

    final analytics = await _db!.query("analytics");
    if (analytics.isNotEmpty) {
      completion = analytics.first["completion"] as double;
      rating = analytics.first["rating"] as double;
    }

    final cats = await _db!.query("categories");
    categories = {for (var row in cats) row["name"] as String: row["value"] as int};

    final eps = await _db!.query("episodes");
    episodes = eps
        .map((row) => FlSpot((row["day"] as int).toDouble(), (row["count"] as int).toDouble()))
        .toList();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Analytics Dashboard")),
      body: RefreshIndicator(
        color: Colors.orange,
        onRefresh: () async => _loadData(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text("Completion & Rating", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: _buildBarChart()),

            const SizedBox(height: 24),
            const Text("Top Categories", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: _buildPieChart()),

            const SizedBox(height: 24),
            const Text("Episodes Over Time", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(height: 250, child: _buildLineChart()),
          ],
        ),
      ),
    );
  }

  /// 📊 Bar Chart
  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barGroups: [
          BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: completion, color: Colors.orange, width: 22)]),
          BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: rating * 10, color: Colors.green, width: 22)]),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
              switch (v.toInt()) {
                case 0:
                  return const Text("Completion %");
                case 1:
                  return const Text("Rating /10");
              }
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    );
  }

  /// 🥧 Pie Chart
  Widget _buildPieChart() {
    if (categories.isEmpty) return const Center(child: Text("No Data"));

    final total = categories.values.fold<int>(0, (a, b) => a + b);
    return PieChart(
      PieChartData(
        sections: categories.entries.map((e) {
          final percent = (e.value / total) * 100;
          return PieChartSectionData(
            value: e.value.toDouble(),
            title: "${percent.toStringAsFixed(1)}%",
            color: Colors.primaries[categories.keys.toList().indexOf(e.key) % Colors.primaries.length],
            radius: 60,
            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          );
        }).toList(),
      ),
    );
  }

  /// 📈 Line Chart
  Widget _buildLineChart() {
    if (episodes.isEmpty) return const Center(child: Text("No Data"));

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: episodes,
            isCurved: true,
            color: Colors.orange,
            barWidth: 3,
            dotData: FlDotData(show: true),
          ),
        ],
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, meta) {
              return Text("Day ${v.toInt()}");
            }),
          ),
        ),
      ),
    );
  }
}