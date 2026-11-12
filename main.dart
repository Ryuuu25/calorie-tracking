import 'dart:convert';
import 'dart:math' show min, max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

// ---------- constants & helpers ----------
const nutKeys = ['kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g', 'sodium_mg'];
const meals = ['breakfast', 'lunch', 'dinner', 'snack'];
const mealNames = {
  'breakfast': ['Breakfast', 'সকালের নাস্তা'],
  'lunch': ['Lunch', 'দুপুরের খাবার'],
  'dinner': ['Dinner', 'রাতের খাবার'],
  'snack': ['Snacks', 'নাস্তা'],
};
const nutNames = {
  'kcal': ['Calories', 'ক্যালরি', 'kcal'],
  'protein_g': ['Protein', 'প্রোটিন', 'g'],
  'carbs_g': ['Carbs', 'কার্বস', 'g'],
  'fat_g': ['Fat', 'ফ্যাট', 'g'],
  'fiber_g': ['Fiber', 'ফাইবার', 'g'],
  'sugar_g': ['Sugar', 'চিনি', 'g'],
  'sodium_mg': ['Sodium', 'সোডিয়াম', 'mg'],
};

final app = AppState();
String t(String en, String bn) => app.bn ? bn : en;
String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
double pd(String k) => (app.profile[k] as num).toDouble();
double numOf(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
String mealName(String m) => mealNames[m]![app.bn ? 1 : 0];
String nutText(String k, double v) {
  final n = nutNames[k]!;
  final val = (k == 'kcal' || k == 'sodium_mg') ? v.round().toString() : v.toStringAsFixed(1);
  return '${n[app.bn ? 1 : 0]}: $val ${n[2]}';
}

String defaultMeal() {
  final h = DateTime.now().hour;
  if (h < 11) return 'breakfast';
  if (h < 16) return 'lunch';
  if (h < 18) return 'snack';
  return 'dinner';
}

Map<String, double> sumN(Iterable<Map<String, double>> list) {
  final m = {for (final k in nutKeys) k: 0.0};
  for (final x in list) {
    for (final k in nutKeys) {
      m[k] = m[k]! + (x[k] ?? 0);
    }
  }
  return m;
}

// ---------- models ----------
class Food {
  final String id, nameEn, nameBn, category, servingEn, servingBn;
  final double servingG;
  final Map<String, double> n; // per 100 g
  final bool custom;
  Food({
    required this.id, required this.nameEn, required this.nameBn, required this.category,
    required this.servingG, required this.servingEn, required this.servingBn,
    required this.n, this.custom = false,
  });
  String name(bool bn) => bn && nameBn.isNotEmpty ? nameBn : nameEn;
  Map<String, double> forGrams(double g) => {for (final k in nutKeys) k: (n[k] ?? 0) * g / 100};
  factory Food.fromJson(Map<String, dynamic> j) {
    final s = Map<String, dynamic>.from(j['serving'] as Map);
    final p = Map<String, dynamic>.from(j['per_100g'] as Map);
    return Food(
      id: j['id'], nameEn: j['name_en'], nameBn: j['name_bn'] ?? '', category: j['category'] ?? 'other',
      servingG: (s['grams'] as num).toDouble(), servingEn: s['label_en'], servingBn: s['label_bn'],
      n: {for (final k in nutKeys) k: ((p[k] ?? 0) as num).toDouble()},
      custom: j['builtin'] != true,
    );
  }
  Map<String, dynamic> toJson() => {
        'id': id, 'name_en': nameEn, 'name_bn': nameBn, 'category': category,
        'serving': {'label_en': servingEn, 'label_bn': servingBn, 'grams': servingG},
        'per_100g': n, 'builtin': !custom,
      };
}

class Entry {
  final String id, date, meal, nameEn, nameBn;
  final double grams;
  final Map<String, double> n; // totals for this entry
  Entry({required this.id, required this.date, required this.meal, required this.nameEn,
      required this.nameBn, required this.grams, required this.n});
  String name(bool bn) => bn && nameBn.isNotEmpty ? nameBn : nameEn;
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'], date: j['date'], meal: j['meal'], nameEn: j['nameEn'], nameBn: j['nameBn'],
        grams: (j['grams'] as num).toDouble(),
        n: {for (final k in nutKeys) k: (((j['n'] as Map)[k]) ?? 0).toDouble()},
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'meal': meal, 'nameEn': nameEn, 'nameBn': nameBn, 'grams': grams, 'n': n,
      };
}

const actTypes = <List<dynamic>>[
  ['walk', 3.5, 'Walking (normal pace)', 'হাঁটা (স্বাভাবিক গতি)'],
  ['brisk', 5.0, 'Brisk walking', 'দ্রুত হাঁটা'],
  ['steps', 0.0, 'Steps (step counter)', 'স্টেপ (স্টেপ কাউন্টার)'],
  ['jog', 7.0, 'Jogging', 'জগিং'],
  ['run', 9.8, 'Running', 'দৌড়ানো'],
  ['cycle', 6.0, 'Cycling', 'সাইকেল চালানো'],
  ['swim', 6.0, 'Swimming', 'সাঁতার'],
  ['football', 7.0, 'Football', 'ফুটবল'],
  ['cricket', 4.8, 'Cricket', 'ক্রিকেট'],
  ['badminton', 5.5, 'Badminton', 'ব্যাডমিন্টন'],
  ['gym', 3.5, 'Gym (weights)', 'জিম (ওজন)'],
  ['hiit', 8.0, 'HIIT / Aerobics', 'হিট / অ্যারোবিক্স'],
  ['yoga', 2.5, 'Yoga', 'যোগব্যায়াম'],
  ['stairs', 8.0, 'Climbing stairs', 'সিঁড়ি ভাঙা'],
  ['dance', 4.8, 'Dancing', 'নাচ'],
  ['house', 3.3, 'Housework', 'ঘরের কাজ'],
];
String actName(String k) => actTypes.firstWhere((x) => x[0] == k)[app.bn ? 3 : 2] as String;

class Act {
  final String id, date, key;
  final double val, kcal;
  Act({required this.id, required this.date, required this.key, required this.val, required this.kcal});
  factory Act.fromJson(Map<String, dynamic> j) => Act(
        id: j['id'], date: j['date'], key: j['key'],
        val: (j['val'] as num).toDouble(), kcal: (j['kcal'] as num).toDouble(),
      );
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'key': key, 'val': val, 'kcal': kcal};
}

// ---------- state ----------
class AppState extends ChangeNotifier {
  late SharedPreferences prefs;
  List<Food> builtin = [], custom = [];
  List<Entry> log = [];
  List<Act> acts = [];
  List<Map<String, dynamic>> weights = []; // {d, kg}
  bool bn = false;
  String day = ymd(DateTime.now());
  Map<String, dynamic> profile = {
    'sex': 'male', 'age': 25.0, 'height': 170.0, 'weight': 70.0,
    'activity': 1.2, 'loss': 0.5, 'goal': 2000.0, 'eb': 50.0,
  };

  List<Food> get foods => [...custom, ...builtin];

  List<Map<String, dynamic>> _list(String key) =>
      (jsonDecode(prefs.getString(key) ?? '[]') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    final raw = await rootBundle.loadString('assets/bd_foods.json');
    builtin = (jsonDecode(raw)['foods'] as List).map((e) => Food.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    custom = _list('custom').map(Food.fromJson).toList();
    log = _list('log').map(Entry.fromJson).toList();
    acts = _list('acts').map(Act.fromJson).toList();
    weights = _list('weights');
    bn = prefs.getBool('bn') ?? false;
    profile = {...profile, ...Map<String, dynamic>.from(jsonDecode(prefs.getString('profile') ?? '{}') as Map)};
  }

  void _save() {
    prefs.setString('custom', jsonEncode(custom.map((f) => f.toJson()).toList()));
    prefs.setString('log', jsonEncode(log.map((e) => e.toJson()).toList()));
    prefs.setString('acts', jsonEncode(acts.map((a) => a.toJson()).toList()));
    prefs.setString('weights', jsonEncode(weights));
    prefs.setString('profile', jsonEncode(profile));
    prefs.setBool('bn', bn);
    notifyListeners();
  }

  void setBn(bool v) { bn = v; _save(); }
  void shiftDay(int n) { day = ymd(DateTime.parse(day).add(Duration(days: n))); notifyListeners(); }
  void addCustom(Food f) { custom.insert(0, f); _save(); }
  void deleteFood(String id) { custom.removeWhere((f) => f.id == id); _save(); }
  void removeEntry(String id) { log.removeWhere((e) => e.id == id); _save(); }
  double get curWeight => weights.isNotEmpty ? (weights.last['kg'] as num).toDouble() : pd('weight');
  double burn(String key, double v) {
    if (key == 'steps') return v * curWeight * 0.000571;
    final met = (actTypes.firstWhere((x) => x[0] == key)[1] as num).toDouble();
    return met * curWeight * v / 60;
  }
  void addAct(String key, double v) {
    acts.add(Act(id: DateTime.now().microsecondsSinceEpoch.toString(), date: day, key: key, val: v, kcal: burn(key, v)));
    _save();
  }
  void removeAct(String id) { acts.removeWhere((a) => a.id == id); _save(); }
  void setProfile(Map<String, dynamic> p) { profile = {...profile, ...p}; _save(); }

  void addEntry(Food f, double grams, String meal) {
    log.add(Entry(
      id: DateTime.now().microsecondsSinceEpoch.toString(), date: day, meal: meal,
      nameEn: f.nameEn, nameBn: f.nameBn, grams: grams, n: f.forGrams(grams),
    ));
    _save();
  }

  void addWeight(double kg) {
    final d = ymd(DateTime.now());
    weights.removeWhere((w) => w['d'] == d);
    weights.add({'d': d, 'kg': kg});
    weights.sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));
    _save();
  }

  void removeWeight(String d) { weights.removeWhere((w) => w['d'] == d); _save(); }
}

// ---------- app ----------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Calorie Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
        darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green, brightness: Brightness.dark),
        themeMode: ThemeMode.system,
        home: const Root(),
      );
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  int i = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) {
          final pages = [const TodayPage(), const FoodList(), const WeightPage()];
          return Scaffold(
            appBar: AppBar(
              title: Text(t('Calorie Tracker', 'ক্যালরি ট্র্যাকার')),
              actions: [
                TextButton(onPressed: () => app.setBn(!app.bn), child: Text(app.bn ? 'EN' : 'বাং')),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SettingsPage())),
                ),
              ],
            ),
            body: pages[i],
            bottomNavigationBar: NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => setState(() => i = v),
              destinations: [
                NavigationDestination(icon: const Icon(Icons.today_outlined), label: t('Today', 'আজ')),
                NavigationDestination(icon: const Icon(Icons.restaurant_menu), label: t('Foods', 'খাবার')),
                NavigationDestination(icon: const Icon(Icons.monitor_weight_outlined), label: t('Weight', 'ওজন')),
              ],
            ),
          );
        },
      );
}

// ---------- today ----------
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) {
          final es = app.log.where((e) => e.date == app.day).toList();
          final ac = app.acts.where((a) => a.date == app.day).toList();
          final tot = sumN(es.map((e) => e.n));
          final burned = ac.fold(0.0, (s, a) => s + a.kcal);
          final bonus = burned * pd('eb') / 100;
          final goal = pd('goal') + bonus;
          final eaten = tot['kcal']!;
          return ListView(padding: const EdgeInsets.all(12), children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => app.shiftDay(-1)),
              Text(app.day == ymd(DateTime.now()) ? t('Today', 'আজ') : app.day,
                  style: Theme.of(c).textTheme.titleMedium),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => app.shiftDay(1)),
            ]),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${eaten.round()} / ${goal.round()} kcal', style: Theme.of(c).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: goal > 0 ? (eaten / goal).clamp(0.0, 1.0) : 0,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 8),
                  Text(eaten <= goal
                      ? '${(goal - eaten).round()} kcal ${t('left', 'বাকি')}'
                      : '${(eaten - goal).round()} kcal ${t('over', 'বেশি')}'),
                  Text(
                    '${t('Goal', 'লক্ষ্য')} ${pd('goal').round()} + ${t('activity', 'কার্যকলাপ')} ${bonus.round()} · ${t('Burned', 'খরচ')} ${burned.round()} kcal',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    for (final k in nutKeys.skip(1)) Text(nutText(k, tot[k]!)),
                  ]),
                ]),
              ),
            ),
            for (final m in meals) ..._mealSection(c, m, es.where((e) => e.meal == m).toList()),
            ..._actSection(c, ac, burned),
          ]);
        },
      );

  List<Widget> _mealSection(BuildContext c, String m, List<Entry> es) {
    final kcal = es.fold(0.0, (s, e) => s + e.n['kcal']!);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Expanded(child: Text(mealName(m), style: Theme.of(c).textTheme.titleSmall)),
          Text('${kcal.round()} kcal'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => PickerPage(meal: m))),
          ),
        ]),
      ),
      for (final e in es)
        Dismissible(
          key: ValueKey(e.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red.shade300,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => app.removeEntry(e.id),
          child: ListTile(
            dense: true,
            title: Text(e.name(app.bn)),
            subtitle: Text('${e.grams.round()} g'),
            trailing: Text('${e.n['kcal']!.round()} kcal'),
          ),
        ),
    ];
  }

  List<Widget> _actSection(BuildContext c, List<Act> ac, double burned) => [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Expanded(child: Text(t('Activity', 'কার্যকলাপ'), style: Theme.of(c).textTheme.titleSmall)),
            Text('${burned.round()} kcal'),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => showActSheet(c)),
          ]),
        ),
        for (final a in ac)
          Dismissible(
            key: ValueKey(a.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red.shade300,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) => app.removeAct(a.id),
            child: ListTile(
              dense: true,
              title: Text(actName(a.key)),
              subtitle: Text(a.key == 'steps' ? '${a.val.round()} ${t('steps', 'স্টেপ')}' : '${a.val.round()} ${t('min', 'মিনিট')}'),
              trailing: Text('−${a.kcal.round()} kcal'),
            ),
          ),
      ];
}

Future<void> showActSheet(BuildContext ctx) =>
    showModalBottomSheet(context: ctx, isScrollControlled: true, builder: (_) => const ActSheet());

class ActSheet extends StatefulWidget {
  const ActSheet({super.key});
  @override
  State<ActSheet> createState() => _ActSheetState();
}

class _ActSheetState extends State<ActSheet> {
  String key = 'walk';
  final ctl = TextEditingController(text: '30');
  @override
  Widget build(BuildContext context) {
    final v = numOf(ctl);
    final kcal = app.burn(key, v);
    final steps = key == 'steps';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t('Add activity', 'কার্যকলাপ যোগ করুন'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: key,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [for (final a in actTypes) DropdownMenuItem(value: a[0] as String, child: Text(a[app.bn ? 3 : 2] as String))],
            onChanged: (x) => setState(() {
              key = x!;
              ctl.text = key == 'steps' ? '5000' : '30';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: steps ? t('Number of steps', 'কত স্টেপ') : t('Minutes', 'কত মিনিট'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('≈ ${kcal.round()} kcal ${t('burned', 'খরচ')}', style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${t('Estimated for your weight', 'আপনার ওজন অনুযায়ী অনুমান')} (${app.curWeight.round()} kg). '
            '${t('If you log steps, do not also log the same walk.', 'স্টেপ যোগ করলে একই হাঁটা আবার যোগ করবেন না।')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: v > 0 ? () { app.addAct(key, v); Navigator.pop(context); } : null,
              child: Text(t('Add', 'যোগ করুন')),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- foods ----------
class PickerPage extends StatelessWidget {
  final String meal;
  const PickerPage({super.key, required this.meal});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: Text('${t('Add to', 'যোগ করুন')}: ${mealName(meal)}')),
          body: FoodList(meal: meal),
        ),
      );
}

class FoodList extends StatefulWidget {
  final void Function(Food)? onPick;
  final String? meal;
  const FoodList({super.key, this.onPick, this.meal});
  @override
  State<FoodList> createState() => _FoodListState();
}

class _FoodListState extends State<FoodList> {
  String q = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) {
          final ql = q.toLowerCase();
          final list = app.foods
              .where((f) => ql.isEmpty || f.nameEn.toLowerCase().contains(ql) || f.nameBn.contains(q))
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t('Search food', 'খাবার খুঁজুন'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => q = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(t('New food', 'নতুন খাবার')),
                    onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const NewFoodPage())),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.blender_outlined),
                    label: Text(t('Mix foods', 'খাবার মিশান')),
                    onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MixPage())),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final f = list[i];
                  final kcal = f.forGrams(f.servingG)['kcal']!;
                  return ListTile(
                    title: Text(f.name(app.bn)),
                    subtitle: Text('${kcal.round()} kcal · ${app.bn ? f.servingBn : f.servingEn} (${f.servingG.round()} g)'),
                    trailing: f.custom ? const Icon(Icons.person_outline, size: 18) : null,
                    onTap: () => widget.onPick != null ? widget.onPick!(f) : showLogSheet(c, f, meal: widget.meal),
                    onLongPress: f.custom ? () => _confirmDelete(c, f) : null,
                  );
                },
              ),
            ),
          ]);
        },
      );

  void _confirmDelete(BuildContext c, Food f) => showDialog(
        context: c,
        builder: (_) => AlertDialog(
          title: Text(t('Delete this food?', 'খাবারটি মুছবেন?')),
          content: Text(f.name(app.bn)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(t('Cancel', 'বাতিল'))),
            TextButton(
              onPressed: () { app.deleteFood(f.id); Navigator.pop(c); },
              child: Text(t('Delete', 'মুছুন')),
            ),
          ],
        ),
      );
}

Future<void> showLogSheet(BuildContext ctx, Food f, {String? meal}) => showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => LogSheet(food: f, meal: meal),
    );

class LogSheet extends StatefulWidget {
  final Food food;
  final String? meal;
  const LogSheet({super.key, required this.food, this.meal});
  @override
  State<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<LogSheet> {
  late String meal = widget.meal ?? defaultMeal();
  bool byGram = false;
  final ctl = TextEditingController(text: '1');
  double get grams => byGram ? numOf(ctl) : numOf(ctl) * widget.food.servingG;

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    final nut = f.forGrams(grams);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(f.name(app.bn), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text('${app.bn ? f.servingBn : f.servingEn} (${f.servingG.round()} g)')),
              ButtonSegment(value: true, label: Text(t('Grams', 'গ্রাম'))),
            ],
            selected: {byGram},
            onSelectionChanged: (s) => setState(() {
              byGram = s.first;
              ctl.text = byGram ? '100' : '1';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: byGram ? t('Amount (g)', 'পরিমাণ (গ্রাম)') : t('Number of servings', 'কত পরিবেশন'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in meals)
              ChoiceChip(label: Text(mealName(m)), selected: meal == m, onSelected: (_) => setState(() => meal = m)),
          ]),
          const SizedBox(height: 12),
          Text('${grams.round()} g', style: Theme.of(context).textTheme.labelLarge),
          Wrap(spacing: 14, runSpacing: 4, children: [for (final k in nutKeys) Text(nutText(k, nut[k]!))]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: grams > 0 ? () { app.addEntry(f, grams, meal); Navigator.pop(context); } : null,
              child: Text(t('Add', 'যোগ করুন')),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- new food (name + calories) ----------
class NewFoodPage extends StatefulWidget {
  const NewFoodPage({super.key});
  @override
  State<NewFoodPage> createState() => _NewFoodPageState();
}

class _NewFoodPageState extends State<NewFoodPage> {
  final name = TextEditingController(), kcal = TextEditingController(), per = TextEditingController(text: '100');
  final extra = {for (final k in nutKeys.skip(1)) k: TextEditingController()};

  Widget field(TextEditingController c, String label, {bool text = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: text ? TextInputType.text : const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label),
        ),
      );

  void save() {
    final g = numOf(per);
    if (name.text.trim().isEmpty || numOf(kcal) <= 0 || g <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Enter a name, calories and amount', 'নাম, ক্যালরি ও পরিমাণ দিন')),
      ));
      return;
    }
    final n = {'kcal': numOf(kcal) * 100 / g};
    for (final k in nutKeys.skip(1)) {
      n[k] = numOf(extra[k]!) * 100 / g;
    }
    app.addCustom(Food(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}', nameEn: name.text.trim(), nameBn: name.text.trim(),
      category: 'custom', servingG: g, servingEn: '1 serving', servingBn: '১ পরিবেশন', n: n, custom: true,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: Text(t('New food', 'নতুন খাবার'))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            field(name, t('Food name', 'খাবারের নাম'), text: true),
            field(kcal, t('Calories (kcal)', 'ক্যালরি (kcal)')),
            field(per, t('Calories are for how many grams?', 'এই ক্যালরি কত গ্রামের জন্য?')),
            ExpansionTile(
              title: Text(t('More nutrition (optional, same amount)', 'আরও পুষ্টি (ঐচ্ছিক, একই পরিমাণ)')),
              childrenPadding: const EdgeInsets.only(top: 8),
              children: [
                for (final k in nutKeys.skip(1)) field(extra[k]!, '${nutNames[k]![app.bn ? 1 : 0]} (${nutNames[k]![2]})'),
              ],
            ),
            FilledButton(onPressed: save, child: Text(t('Save food', 'সংরক্ষণ করুন'))),
          ]),
        ),
      );
}

// ---------- mix foods ----------
class _Part {
  final Food food;
  final TextEditingController c;
  _Part(this.food) : c = TextEditingController(text: food.servingG.round().toString());
}

class MixPage extends StatefulWidget {
  const MixPage({super.key});
  @override
  State<MixPage> createState() => _MixPageState();
}

class _MixPageState extends State<MixPage> {
  final name = TextEditingController();
  final parts = <_Part>[];

  double grams() => parts.fold(0.0, (s, p) => s + numOf(p.c));
  Map<String, double> total() => sumN(parts.map((p) => p.food.forGrams(numOf(p.c))));

  Future<void> addPart() async {
    final f = await Navigator.push<Food>(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(title: Text(t('Pick ingredient', 'উপাদান বাছুন'))),
          body: FoodList(onPick: (f) => Navigator.pop(c, f)),
        ),
      ),
    );
    if (f != null) setState(() => parts.add(_Part(f)));
  }

  void save() {
    final g = grams();
    if (name.text.trim().isEmpty || parts.length < 2 || g <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Enter a name and add at least 2 foods', 'একটি নাম দিন এবং অন্তত ২টি খাবার যোগ করুন')),
      ));
      return;
    }
    final tot = total();
    app.addCustom(Food(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}', nameEn: name.text.trim(), nameBn: name.text.trim(),
      category: 'mix', servingG: g, servingEn: '1 serving', servingBn: '১ পরিবেশন',
      n: {for (final k in nutKeys) k: tot[k]! * 100 / g}, custom: true,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tot = total();
    return ListenableBuilder(
      listenable: app,
      builder: (c, _) => Scaffold(
        appBar: AppBar(title: Text(t('Mix foods', 'খাবার মিশান'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(t('Example: Muri 30 g + Soybean oil 5 g = Muri makha', 'যেমন: মুড়ি ৩০ গ্রাম + সয়াবিন তেল ৫ গ্রাম = মুড়ি মাখা')),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: t('Name of the mix', 'মিশ্রণের নাম')),
          ),
          const SizedBox(height: 12),
          for (final p in parts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.food.name(app.bn)),
              subtitle: SizedBox(
                width: 120,
                child: TextField(
                  controller: p.c,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(suffixText: 'g', isDense: true, labelText: t('Amount', 'পরিমাণ')),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => parts.remove(p)),
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(t('Add ingredient', 'উপাদান যোগ করুন')),
            onPressed: addPart,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t('Total', 'মোট')}: ${grams().round()} g · ${tot['kcal']!.round()} kcal',
                    style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: 6),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  for (final k in nutKeys.skip(1)) Text(nutText(k, tot[k]!)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: save, child: Text(t('Save as new food', 'নতুন খাবার হিসেবে সংরক্ষণ করুন'))),
        ]),
      ),
    );
  }
}

// ---------- weight ----------
class WeightPage extends StatefulWidget {
  const WeightPage({super.key});
  @override
  State<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends State<WeightPage> {
  final ctl = TextEditingController();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) {
          final w = app.weights;
          final vals = w.map((e) => (e['kg'] as num).toDouble()).toList();
          final recent = vals.length > 30 ? vals.sublist(vals.length - 30) : vals;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: ctl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(border: const OutlineInputBorder(), labelText: t("Today's weight (kg)", 'আজকের ওজন (কেজি)')),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = numOf(ctl);
                  if (v > 0) { app.addWeight(v); ctl.clear(); }
                },
                child: Text(t('Save', 'সংরক্ষণ')),
              ),
            ]),
            const SizedBox(height: 16),
            if (recent.length >= 2)
              SizedBox(
                height: 160,
                child: CustomPaint(painter: LinePainter(recent, Theme.of(c).colorScheme.primary), size: Size.infinite),
              ),
            if (vals.length >= 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${t('Change since first entry', 'প্রথম এন্ট্রি থেকে পরিবর্তন')}: ${(vals.last - vals.first).toStringAsFixed(1)} kg'),
              ),
            for (final e in w.reversed)
              ListTile(
                dense: true,
                title: Text('${e['kg']} kg'),
                subtitle: Text(e['d'] as String),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => app.removeWeight(e['d'] as String)),
              ),
          ]);
        },
      );
}

class LinePainter extends CustomPainter {
  final List<double> v;
  final Color color;
  LinePainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final lo = v.reduce(min) - 0.5, hi = v.reduce(max) + 0.5;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = s.width * i / (v.length - 1);
      final y = s.height * (1 - (v[i] - lo) / (hi - lo));
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ---------- settings ----------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String sex = app.profile['sex'];
  late double activity = [1.2, 1.375, 1.55].contains(pd('activity')) ? pd('activity') : 1.2, loss = pd('loss'), eb = pd('eb');
  late final age = TextEditingController(text: pd('age').round().toString());
  late final height = TextEditingController(text: pd('height').round().toString());
  late final weight = TextEditingController(text: pd('weight').toString());
  late final goal = TextEditingController(text: pd('goal').round().toString());

  void calc() {
    final w = numOf(weight), h = numOf(height), a = numOf(age);
    final bmr = 10 * w + 6.25 * h - 5 * a + (sex == 'male' ? 5 : -161);
    var g = bmr * activity - loss * 7700 / 7;
    final floor = sex == 'male' ? 1500.0 : 1200.0; // safety minimum
    g = max(g, floor);
    setState(() => goal.text = g.round().toString());
  }

  void save() {
    app.setProfile({
      'sex': sex, 'age': numOf(age), 'height': numOf(height), 'weight': numOf(weight),
      'activity': activity, 'loss': loss, 'eb': eb, 'goal': max(numOf(goal), 800.0),
    });
    Navigator.pop(context);
  }

  Widget num_(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => Scaffold(
          appBar: AppBar(title: Text(t('Daily goal', 'দৈনিক লক্ষ্য'))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<String>(
              value: sex,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: t('Sex', 'লিঙ্গ')),
              items: [
                DropdownMenuItem(value: 'male', child: Text(t('Male', 'পুরুষ'))),
                DropdownMenuItem(value: 'female', child: Text(t('Female', 'মহিলা'))),
              ],
              onChanged: (v) => setState(() => sex = v!),
            ),
            const SizedBox(height: 12),
            num_(age, t('Age', 'বয়স')),
            num_(height, t('Height (cm)', 'উচ্চতা (সেমি)')),
            num_(weight, t('Weight (kg)', 'ওজন (কেজি)')),
            DropdownButtonFormField<double>(
              value: activity,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: t('Everyday life (not counting workouts)', 'দৈনন্দিন জীবন (ব্যায়াম বাদে)')),
              items: [
                DropdownMenuItem(value: 1.2, child: Text(t('Mostly sitting', 'বেশিরভাগ সময় বসে'))),
                DropdownMenuItem(value: 1.375, child: Text(t('On my feet some of the day', 'দিনের কিছু সময় দাঁড়িয়ে/হেঁটে'))),
                DropdownMenuItem(value: 1.55, child: Text(t('On my feet most of the day', 'দিনের বেশিরভাগ সময় দাঁড়িয়ে/হেঁটে'))),
              ],
              onChanged: (v) => setState(() => activity = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              value: loss,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: t('Weight loss per week', 'সপ্তাহে ওজন কমানো')),
              items: const [
                DropdownMenuItem(value: 0.25, child: Text('0.25 kg')),
                DropdownMenuItem(value: 0.5, child: Text('0.5 kg')),
                DropdownMenuItem(value: 0.75, child: Text('0.75 kg')),
              ],
              onChanged: (v) => setState(() => loss = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              value: eb,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: t('Add burned calories to food budget', 'খরচ হওয়া ক্যালরি খাবারের বাজেটে যোগ')),
              items: const [
                DropdownMenuItem(value: 0.0, child: Text('0%')),
                DropdownMenuItem(value: 50.0, child: Text('50%')),
                DropdownMenuItem(value: 100.0, child: Text('100%')),
              ],
              onChanged: (v) => setState(() => eb = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: calc, child: Text(t('Calculate my daily calories', 'আমার দৈনিক ক্যালরি হিসাব করুন'))),
            const SizedBox(height: 12),
            num_(goal, t('Daily calorie goal (you can edit)', 'দৈনিক ক্যালরি লক্ষ্য (পরিবর্তন করা যাবে)')),
            Text(
              t('This is only an estimate. If you have a health condition, please check with a doctor or dietitian.',
                  'এটি শুধু একটি অনুমান। কোনো স্বাস্থ্য সমস্যা থাকলে ডাক্তার বা পুষ্টিবিদের সাথে কথা বলুন।'),
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: save, child: Text(t('Save', 'সংরক্ষণ'))),
          ]),
        ),
      );
}
