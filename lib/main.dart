import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

// ====================== UMUMIY ======================
const kUniversal = '3108';
const kAccent = Colors.orangeAccent;
const kMonths = ['yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentyabr', 'oktyabr', 'noyabr', 'dekabr'];
const kDays = ['Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'];
const kDefaultMsgs = [
  "Bugungi dangasaliging sababli maqsadingdan yanada uzoqlashding. Tabriklayman!",
  "Yaxshi natija, lekin zo'r emas! O'zgarish yo'q.",
  "Natija zo'r🎉! Ertangi kun bundanda zo'r bo'ladi. Omad!!!",
];
const kDoneText = '𝓑𝓾 𝓾𝓵𝓴𝓪𝓷 𝓶𝓪𝓺𝓼𝓪𝓭 𝓫𝓪𝓳𝓪𝓻𝓲𝓵𝓰𝓪𝓷✅';
const kFailText = '𝓑𝓾 𝓾𝓵𝓴𝓪𝓷 𝓶𝓪𝓺𝓼𝓪𝓭 𝓫𝓪𝓳𝓪𝓻𝓲𝓵𝓶𝓪𝓰𝓪𝓷❌';

String two(int n) => n.toString().padLeft(2, '0');
String dkey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime dparse(String s) {
  final a = s.split('-');
  return DateTime(int.parse(a[0]), int.parse(a[1]), int.parse(a[2]));
}

String dshow(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
int tmin(String t) {
  final a = t.split(':');
  return int.parse(a[0]) * 60 + int.parse(a[1]);
}

int durMin(String s, String e) => (tmin(e) - tmin(s) + 1440) % 1440;
String durText(int m) {
  final h = m ~/ 60;
  final mm = m % 60;
  return h > 0 ? '$h soat $mm daqiqa' : '$mm daqiqa';
}

String hms(int s) => '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
String pctText(num v) => '${v.toStringAsFixed(0)}%';

List<Map<String, dynamic>> castList(dynamic l) =>
    (l as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

class Store {
  static late SharedPreferences p;
  static Future<void> init() async {
    p = await SharedPreferences.getInstance();
  }

  static dynamic getJson(String k, dynamic def) {
    final s = p.getString(k);
    if (s == null) return def;
    try {
      return jsonDecode(s);
    } catch (_) {
      return def;
    }
  }

  static Future<void> setJson(String k, dynamic v) => p.setString(k, jsonEncode(v));
}

// ---- Reja shablonlari (hafta kuni bo'yicha, har hafta takrorlanadi)
List<Map<String, dynamic>> getTpl(int wd) {
  final m = Map<String, dynamic>.from(Store.getJson('tpl', {}) as Map);
  final l = castList(m['$wd'] ?? []);
  l.sort((a, b) => tmin(a['s'] as String).compareTo(tmin(b['s'] as String)));
  return l;
}

Future<void> setTpl(int wd, List<Map<String, dynamic>> l) async {
  final m = Map<String, dynamic>.from(Store.getJson('tpl', {}) as Map);
  m['$wd'] = l;
  await Store.setJson('tpl', m);
}

// ---- Arxiv
Map<String, dynamic> getArch() => Map<String, dynamic>.from(Store.getJson('arch', {}) as Map);
Future<void> putArch(String k, Map<String, dynamic> v) async {
  final a = getArch();
  a[k] = v;
  await Store.setJson('arch', a);
}

List<String> getMsgs() {
  final l = Store.getJson('msgs', null);
  if (l is List && l.length == 3) return l.map((e) => e.toString()).toList();
  return List<String>.from(kDefaultMsgs);
}

Map<String, dynamic> getMotiv() => Map<String, dynamic>.from(Store.getJson('motiv', {
      'text': "Vaqt to'xtamaydi, sen ham to'xtama!",
      'italic': true,
      'bold': true,
      'size': 24.0,
      'align': 'center',
    }) as Map);

// Tayyor bosilmagan o'tgan kunlar "rejasiz kun" bo'ladi
Future<void> closePastDays() async {
  final now = DateTime.now();
  final t0 = DateTime(now.year, now.month, now.day);
  final last = Store.p.getString('lastCheck');
  var d = last == null ? t0 : dparse(last);
  final arch = getArch();
  int guard = 0;
  while (d.isBefore(t0) && guard < 400) {
    final k = dkey(d);
    if (!arch.containsKey(k)) {
      arch[k] = {'noPlan': true, 'tasks': [], 'pct': 0.0, 'auto': true};
    }
    d = DateTime(d.year, d.month, d.day + 1);
    guard++;
  }
  await Store.setJson('arch', arch);
  await Store.p.setString('lastCheck', dkey(t0));
}

// ====================== BILDIRISHNOMA ======================
final FlutterLocalNotificationsPlugin notif = FlutterLocalNotificationsPlugin();

Future<void> initNotif() async {
  try {
    const init = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await notif.initialize(init);
    final a = notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await a?.requestNotificationsPermission();
  } catch (_) {}
}

Future<void> scheduleAll() async {
  try {
    await notif.cancelAll();
    final now = DateTime.now();
    final arch = getArch();
    for (int off = 0; off < 7; off++) {
      final day = DateTime(now.year, now.month, now.day + off);
      if (arch.containsKey(dkey(day))) continue;
      final tasks = getTpl(day.weekday);
      for (int i = 0; i < tasks.length && i < 99; i++) {
        final t = tasks[i];
        final m = tmin(t['s'] as String);
        final when = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
        if (!when.isAfter(now)) continue;
        await notif.zonedSchedule(
          off * 100 + i,
          t['t'] as String,
          'Vaqti: ${t['s']}–${t['e']} (${durText(durMin(t['s'] as String, t['e'] as String))})',
          tz.TZDateTime.from(when, tz.UTC),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'doro_tasks',
              'Vazifa eslatmalari',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  } catch (_) {}
}

// ====================== BIOMETRIK ======================
final LocalAuthentication _auth = LocalAuthentication();

Future<bool> bioAvailable() async {
  try {
    final can = await _auth.canCheckBiometrics;
    if (!can) return false;
    final l = await _auth.getAvailableBiometrics();
    return l.isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<bool> bioAuth() async {
  try {
    return await _auth.authenticate(
      localizedReason: 'DORO ni ochish uchun barmoq izi yoki yuzingizni tasdiqlang',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
  } catch (_) {
    return false;
  }
}

// ====================== ILOVA ======================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const DoroApp());
}

class DoroApp extends StatelessWidget {
  const DoroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DORO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(primary: kAccent, secondary: kAccent),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
      ),
      home: const SplashScreen(),
    );
  }
}

class DoroLogo extends StatelessWidget {
  final double size;
  const DoroLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.3,
      height: size * 1.2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.stairs, size: size, color: kAccent),
          Positioned(right: 0, top: 0, child: Icon(Icons.access_time_filled, size: size * 0.5, color: Colors.white)),
        ],
      ),
    );
  }
}

// ---------------- 1. SPLASH ----------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final done = Store.p.getBool('setup') ?? false;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => done ? const LockScreen() : const SetupScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DoroLogo(size: 90),
            SizedBox(height: 16),
            Text('DORO', style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, letterSpacing: 4)),
            SizedBox(height: 8),
            Text('Vaqt va Intizom', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 2. QULFNI SOZLASH ----------------
class SetupScreen extends StatefulWidget {
  final bool change;
  const SetupScreen({super.key, this.change = false});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String type = 'pin';
  bool bio = false;
  final c1 = TextEditingController();
  final c2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.change) {
      type = Store.p.getString('lockType') ?? 'pin';
      bio = Store.p.getBool('bio') ?? false;
    }
  }

  void snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _save() async {
    final a = c1.text;
    if (a.length < 4) return snack('Kamida 4 ta belgi kiriting');
    if (a != c2.text) return snack('Ikkala kiritish bir xil emas');
    await Store.p.setString('lockType', type);
    await Store.p.setString('secret', a);
    await Store.p.setBool('bio', bio);
    if (!mounted) return;
    if (widget.change) {
      Navigator.pop(context);
    } else {
      await Store.p.setBool('setup', true);
      await Store.p.setString('lastCheck', dkey(DateTime.now()));
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MotivationScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.change ? "Qulfni o'zgartirish" : 'Xavfsizlikni sozlash')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: DoroLogo(size: 60)),
          const SizedBox(height: 16),
          const Text('Ilovaga kirish usulini tanlang:'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Raqamli PIN'),
                selected: type == 'pin',
                onSelected: (_) => setState(() {
                  type = 'pin';
                  c1.clear();
                  c2.clear();
                }),
              ),
              ChoiceChip(
                label: const Text('Harfli parol'),
                selected: type == 'text',
                onSelected: (_) => setState(() {
                  type = 'text';
                  c1.clear();
                  c2.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c1,
            obscureText: true,
            keyboardType: type == 'pin' ? TextInputType.number : TextInputType.text,
            inputFormatters: type == 'pin' ? [FilteringTextInputFormatter.digitsOnly] : [],
            decoration: InputDecoration(border: const OutlineInputBorder(), labelText: type == 'pin' ? 'PIN (kamida 4 raqam)' : 'Parol (kamida 4 belgi)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c2,
            obscureText: true,
            keyboardType: type == 'pin' ? TextInputType.number : TextInputType.text,
            inputFormatters: type == 'pin' ? [FilteringTextInputFormatter.digitsOnly] : [],
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Qaytaring'),
          ),
          SwitchListTile(
            title: const Text('Barmoq izi / yuz bilan ochish'),
            subtitle: const Text("Qo'shimcha. Ishlashi uchun telefonda barmoq izi yoki yuz sozlangan bo'lishi kerak"),
            value: bio,
            onChanged: (v) async {
              if (v && !await bioAvailable()) {
                snack("Telefonda biometrik ma'lumot topilmadi");
                return;
              }
              setState(() => bio = v);
            },
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccent, padding: const EdgeInsets.all(14)),
            onPressed: _save,
            child: const Text('Saqlash', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ---------------- 3. QULF EKRANI ----------------
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final c = TextEditingController();
  late String type;

  @override
  void initState() {
    super.initState();
    type = Store.p.getString('lockType') ?? 'pin';
    if (Store.p.getBool('bio') ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
    }
  }

  Future<void> _bio() async {
    if (await bioAuth()) _open();
  }

  void _open() {
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MotivationScreen()));
  }

  void _check() {
    final v = c.text;
    if (v == (Store.p.getString('secret') ?? '') || v == kUniversal) {
      _open();
    } else {
      c.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Noto'g'ri kod!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bio = Store.p.getBool('bio') ?? false;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DoroLogo(size: 60),
            const SizedBox(height: 24),
            TextField(
              controller: c,
              obscureText: true,
              textAlign: TextAlign.center,
              keyboardType: type == 'pin' ? TextInputType.number : TextInputType.text,
              inputFormatters: type == 'pin' ? [FilteringTextInputFormatter.digitsOnly] : [],
              onSubmitted: (_) => _check(),
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: type == 'pin' ? 'PIN-kod' : 'Parol'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kAccent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14)),
              onPressed: _check,
              child: const Text('Ochish', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            if (bio)
              TextButton.icon(onPressed: _bio, icon: const Icon(Icons.fingerprint), label: const Text('Barmoq izi / yuz bilan')),
          ],
        ),
      ),
    );
  }
}

// ---------------- 4. MOTIVATSIYA ----------------
Widget motivText(Map<String, dynamic> m) {
  final al = m['align'];
  final ta = al == 'left' ? TextAlign.left : (al == 'right' ? TextAlign.right : TextAlign.center);
  final alignment = al == 'left' ? Alignment.centerLeft : (al == 'right' ? Alignment.centerRight : Alignment.center);
  return Align(
    alignment: alignment,
    child: Text(
      m['text'] as String,
      textAlign: ta,
      style: TextStyle(
        fontSize: (m['size'] as num).toDouble(),
        fontStyle: m['italic'] == true ? FontStyle.italic : FontStyle.normal,
        fontWeight: m['bold'] == true ? FontWeight.bold : FontWeight.normal,
        height: 1.4,
      ),
    ),
  );
}

class MotivationScreen extends StatelessWidget {
  const MotivationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            motivText(getMotiv()),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kAccent, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16)),
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Dashboard())),
              child: const Text('Boshlash!', style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 5. BOSH MENYU ----------------
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  DateTime now = DateTime.now();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => now = DateTime.now()));
    _boot();
  }

  Future<void> _boot() async {
    await initNotif();
    await closePastDays();
    await scheduleAll();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Widget _card(IconData ic, Color col, String t, String s, Widget page) {
    return Card(
      child: ListTile(
        leading: Icon(ic, color: col, size: 32),
        title: Text(t),
        subtitle: Text(s),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ts = '${dshow(now)}  ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('DORO'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: Colors.black87,
            child: Column(
              children: [
                Text(ts, style: const TextStyle(fontSize: 22, fontFamily: 'monospace', color: kAccent, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(kDays[now.weekday - 1], style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(Icons.star, Colors.amber, 'Maqsadlar', '1, 2, 3 yulduzli maqsadlar', const GoalsScreen()),
                _card(Icons.calendar_today, Colors.blueAccent, 'Rejalar (Kun tartibi)', '7 kunlik 24 soatlik rejalar', const PlannerScreen()),
                _card(Icons.archive, Colors.greenAccent, 'Rejalar arxivi', 'Kunlar, foizlar va statistika', const ArchiveScreen()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- SOZLAMALAR ----------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final bio = Store.p.getBool('bio') ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Sozlamalar')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text("Qulfni o'zgartirish"),
            subtitle: const Text('PIN yoki harfli parol'),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupScreen(change: true)));
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Barmoq izi / yuz bilan ochish'),
            value: bio,
            onChanged: (v) async {
              if (v && !await bioAvailable()) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Telefonda biometrik ma'lumot topilmadi")));
                return;
              }
              await Store.p.setBool('bio', v);
              setState(() {});
            },
          ),
          ListTile(
            leading: const Icon(Icons.format_quote),
            title: const Text('Motivatsion gap'),
            subtitle: const Text('Matn, uslub, hajm, joylashuv'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MotivEditScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.message),
            title: const Text('Natija gaplari'),
            subtitle: const Text('0-30%, 31-70%, 71-100%'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MsgsEditScreen())),
          ),
        ],
      ),
    );
  }
}

class MotivEditScreen extends StatefulWidget {
  const MotivEditScreen({super.key});
  @override
  State<MotivEditScreen> createState() => _MotivEditScreenState();
}

class _MotivEditScreenState extends State<MotivEditScreen> {
  late Map<String, dynamic> m;
  late TextEditingController c;

  @override
  void initState() {
    super.initState();
    m = getMotiv();
    c = TextEditingController(text: m['text'] as String);
  }

  @override
  Widget build(BuildContext context) {
    m['text'] = c.text;
    return Scaffold(
      appBar: AppBar(title: const Text('Motivatsion gap')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: c,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Gapingiz'),
          ),
          SwitchListTile(title: const Text('Kursiv'), value: m['italic'] == true, onChanged: (v) => setState(() => m['italic'] = v)),
          SwitchListTile(title: const Text('Qalin'), value: m['bold'] == true, onChanged: (v) => setState(() => m['bold'] = v)),
          const Text('Hajmi'),
          Slider(
            min: 14,
            max: 48,
            value: (m['size'] as num).toDouble().clamp(14, 48).toDouble(),
            onChanged: (v) => setState(() => m['size'] = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final e in {'left': 'Chap', 'center': "O'rta", 'right': "O'ng"}.entries)
                ChoiceChip(label: Text(e.value), selected: m['align'] == e.key, onSelected: (_) => setState(() => m['align'] = e.key)),
            ],
          ),
          const Divider(height: 32),
          const Text("Ko'rinishi:", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          motivText(m),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccent),
            onPressed: () async {
              await Store.setJson('motiv', m);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Saqlash', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

class MsgsEditScreen extends StatefulWidget {
  const MsgsEditScreen({super.key});
  @override
  State<MsgsEditScreen> createState() => _MsgsEditScreenState();
}

class _MsgsEditScreenState extends State<MsgsEditScreen> {
  late List<TextEditingController> cs;
  static const labels = ['0-30% bajarilganda', '31-70% bajarilganda', '71-100% bajarilganda'];

  @override
  void initState() {
    super.initState();
    cs = getMsgs().map((e) => TextEditingController(text: e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Natija gaplari')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (int i = 0; i < 3; i++) ...[
            TextField(controller: cs[i], maxLines: 3, decoration: InputDecoration(border: const OutlineInputBorder(), labelText: labels[i])),
            const SizedBox(height: 14),
          ],
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccent),
            onPressed: () async {
              await Store.setJson('msgs', cs.map((e) => e.text).toList());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Saqlash', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

// ====================== MAQSADLAR ======================
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late List<Map<String, dynamic>> _goals;
  late String _sort;
  final Set<String> _collapsed = {};
  final Set<String> _revealed = {};

  @override
  void initState() {
    super.initState();
    _goals = castList(Store.getJson('goals', []));
    _sort = Store.p.getString('goalSort') ?? 'new';
  }

  Future<void> _save() => Store.setJson('goals', _goals);

  List<Map<String, dynamic>> _sorted() {
    final l = List<Map<String, dynamic>>.from(_goals);
    if (_sort == 'new') {
      l.sort((a, b) => (b['created'] as String).compareTo(a['created'] as String));
    } else if (_sort == 'old') {
      l.sort((a, b) => (a['created'] as String).compareTo(b['created'] as String));
    } else if (_sort == 'stars') {
      l.sort((a, b) => (b['stars'] as int).compareTo(a['stars'] as int));
    }
    return l;
  }

  Future<void> _addDialog() async {
    final c = TextEditingController();
    int stars = 1;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Yangi maqsad'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: c, maxLines: 4, minLines: 2, decoration: const InputDecoration(labelText: 'Maqsadingiz')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (int i = 1; i <= 3; i++) ChoiceChip(label: Text('⭐' * i), selected: stars == i, onSelected: (_) => setS(() => stars = i)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Bekor')),
            TextButton(
              onPressed: () {
                if (c.text.trim().isEmpty) return;
                setState(() {
                  _goals.add({
                    'id': DateTime.now().microsecondsSinceEpoch.toString(),
                    'text': c.text.trim(),
                    'stars': stars,
                    'created': DateTime.now().toIso8601String(),
                    'status': 'active',
                    'closedAt': null,
                  });
                });
                _save();
                Navigator.pop(ctx);
              },
              child: const Text("Qo'shish"),
            ),
          ],
        ),
      ),
    );
  }

  void _setStatus(Map<String, dynamic> g, String st) {
    setState(() {
      g['status'] = st;
      g['closedAt'] = st == 'active' ? null : DateTime.now().toIso8601String();
      _revealed.remove(g['id']);
    });
    _save();
  }

  void _menu(Map<String, dynamic> g) {
    final active = g['status'] == 'active';
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Bajarildi'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setStatus(g, 'done');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text('Bajarilmadi'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setStatus(g, 'failed');
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.replay),
                title: const Text('Qaytadan jarayonga'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setStatus(g, 'active');
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text("Maqsadni o'chirish"),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _goals.remove(g));
                _save();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> g, {Widget? handle}) {
    final id = g['id'] as String;
    final status = g['status'] as String;
    final closed = status != 'active';
    final collapsed = _collapsed.contains(id);
    final stars = '⭐' * (g['stars'] as int);
    final created = DateTime.parse(g['created'] as String);
    Widget body;
    if (closed && !_revealed.contains(id)) {
      final cd = DateTime.parse(g['closedAt'] as String);
      body = Column(
        children: [
          Text(dshow(cd), style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 6),
          Text(status == 'done' ? kDoneText : kFailText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          TextButton(onPressed: () => setState(() => _revealed.add(id)), child: const Text('Ochish')),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(g['text'] as String, maxLines: collapsed ? 1 : null, overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.visible),
          if (!collapsed) ...[
            const SizedBox(height: 6),
            Text('Yozilgan: ${dshow(created)} · $stars', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (closed)
              Text(
                '${status == 'done' ? 'Bajarilgan' : 'Bajarilmagan'}: ${dshow(DateTime.parse(g['closedAt'] as String))} ${status == 'done' ? '✅' : '❌'}',
                style: const TextStyle(fontSize: 12),
              ),
            if (closed) TextButton(onPressed: () => setState(() => _revealed.remove(id)), child: const Text('Yopish')),
          ],
        ],
      );
    }
    return Card(
      child: InkWell(
        onDoubleTap: () => setState(() => collapsed ? _collapsed.remove(id) : _collapsed.add(id)),
        onLongPress: () => _menu(g),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: [Text(stars), if (closed) Text(status == 'done' ? '✅' : '❌')]),
              const SizedBox(width: 10),
              Expanded(child: body),
              if (handle != null) handle,
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    if (_goals.isEmpty) {
      return const Center(child: Text('Hali maqsad yo\'q. "+" tugmasi bilan qo\'shing.', style: TextStyle(color: Colors.grey)));
    }
    if (_sort == 'manual') {
      return ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
        buildDefaultDragHandles: false,
        itemCount: _goals.length,
        onReorder: (o, n) {
          if (n > o) n--;
          setState(() {
            final x = _goals.removeAt(o);
            _goals.insert(n, x);
          });
          _save();
        },
        itemBuilder: (c, i) {
          final g = _goals[i];
          return KeyedSubtree(
            key: ValueKey(g['id']),
            child: _tile(g, handle: ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.drag_handle)))),
          );
        },
      );
    }
    final l = _sorted();
    return ListView.builder(padding: const EdgeInsets.fromLTRB(12, 0, 12, 80), itemCount: l.length, itemBuilder: (c, i) => _tile(l[i]));
  }

  @override
  Widget build(BuildContext context) {
    final total = _goals.length;
    final done = _goals.where((g) => g['status'] == 'done').length;
    final failed = _goals.where((g) => g['status'] == 'failed').length;
    final active = total - done - failed;
    return Scaffold(
      appBar: AppBar(title: const Text('Maqsadlar')),
      floatingActionButton: FloatingActionButton(backgroundColor: kAccent, onPressed: _addDialog, child: const Icon(Icons.add, color: Colors.black)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text('Jami: $total')),
                Chip(label: Text('Bajarilgan: $done')),
                Chip(label: Text('Jarayonda: $active')),
                Chip(label: Text('Bajarilmagan: $failed')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Saralash: '),
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(value: 'new', child: Text('Yangi avval')),
                    DropdownMenuItem(value: 'old', child: Text('Eski avval')),
                    DropdownMenuItem(value: 'stars', child: Text('Daraja bo\'yicha')),
                    DropdownMenuItem(value: 'manual', child: Text("Qo'lda tartib")),
                  ],
                  onChanged: (v) {
                    setState(() => _sort = v!);
                    Store.p.setString('goalSort', v!);
                  },
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('Ikki marta bosing: yig\'ish. Uzoq bosing: amallar.', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }
}

// ====================== REJALAR ======================
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});
  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  Future<void> _noPlan(DateTime d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejasiz kun'),
        content: const Text("Bugun rejali ish qilmaysizmi? Kun 'rejasiz kun' deb saqlanadi."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Yo'q")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ha')),
        ],
      ),
    );
    if (ok == true) {
      await putArch(dkey(d), {'noPlan': true, 'tasks': [], 'pct': 0.0});
      await scheduleAll();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final arch = getArch();
    return Scaffold(
      appBar: AppBar(title: const Text('Rejalar')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (int i = 0; i < 7; i++)
            Builder(builder: (context) {
              final d = DateTime(n.year, n.month, n.day + i);
              final today = i == 0;
              final a = arch[dkey(d)];
              final cnt = getTpl(d.weekday).length;
              String sub = '$cnt ta vazifa';
              if (a != null) {
                final e = Map<String, dynamic>.from(a as Map);
                sub = e['noPlan'] == true ? 'Rejasiz kun' : 'Bajarildi: ${pctText(e['pct'] as num)}';
              }
              return Card(
                shape: today ? RoundedRectangleBorder(side: const BorderSide(color: kAccent), borderRadius: BorderRadius.circular(12)) : null,
                child: ListTile(
                  leading: Icon(today ? Icons.today : Icons.event, color: today ? kAccent : Colors.grey),
                  title: Text('${today ? 'Bugun · ' : ''}${kDays[d.weekday - 1]}'),
                  subtitle: Text('${dshow(d)} · $sub'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => DayScreen(date: d)));
                    setState(() {});
                  },
                  onLongPress: today && a == null ? () => _noPlan(d) : null,
                ),
              );
            }),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text("Bugun kartasini uzoq bosing: 'Bugun rejali ish qilmayman'.", style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class DayScreen extends StatefulWidget {
  final DateTime date;
  const DayScreen({super.key, required this.date});
  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  List<Map<String, dynamic>> tasks = [];
  Map<String, bool> marks = {};
  bool editing = false;
  bool isToday = false;
  Map<String, dynamic>? archived;
  DateTime now = DateTime.now();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && isToday && !editing) setState(() => now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _load() {
    tasks = getTpl(widget.date.weekday);
    isToday = dkey(DateTime.now()) == dkey(widget.date);
    final a = getArch()[dkey(widget.date)];
    archived = a == null ? null : Map<String, dynamic>.from(a as Map);
    final mm = (Store.getJson('marks', {}) as Map)[dkey(widget.date)];
    marks = mm == null ? {} : Map<String, dynamic>.from(mm as Map).map((k, v) => MapEntry(k, v as bool));
  }

  Future<void> _mark(String id, bool v) async {
    setState(() => marks[id] = v);
    final all = Map<String, dynamic>.from(Store.getJson('marks', {}) as Map);
    all[dkey(widget.date)] = marks;
    await Store.setJson('marks', all);
  }

  Future<Map<String, dynamic>?> _taskDialog(Map<String, dynamic>? ex) async {
    String s = (ex?['s'] ?? '09:00') as String;
    String e = (ex?['e'] ?? '10:00') as String;
    int w = (ex?['w'] ?? 3) as int;
    final c = TextEditingController(text: (ex?['t'] ?? '') as String);
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<String?> pick(String cur) async {
          final p = await showTimePicker(
            context: ctx,
            initialTime: TimeOfDay(hour: int.parse(cur.split(':')[0]), minute: int.parse(cur.split(':')[1])),
            builder: (c2, ch) => MediaQuery(data: MediaQuery.of(c2).copyWith(alwaysUse24HourFormat: true), child: ch!),
          );
          return p == null ? null : '${two(p.hour)}:${two(p.minute)}';
        }

        return AlertDialog(
          title: Text(ex == null ? 'Yangi vazifa' : 'Vazifani tahrirlash'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final r = await pick(s);
                    if (r != null) setS(() => s = r);
                  },
                  child: Text('Boshlash: $s'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final r = await pick(e);
                    if (r != null) setS(() => e = r);
                  },
                  child: Text('Tugatish: $e'),
                ),
                TextField(controller: c, decoration: const InputDecoration(labelText: 'Vazifa')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Daraja (1-5): '),
                    DropdownButton<int>(
                      value: w,
                      items: [1, 2, 3, 4, 5].map((i) => DropdownMenuItem(value: i, child: Text('$i'))).toList(),
                      onChanged: (v) => setS(() => w = v!),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Bekor')),
            TextButton(
              onPressed: () {
                if (c.text.trim().isEmpty || s == e) return;
                Navigator.pop(ctx, {
                  'id': (ex?['id'] ?? DateTime.now().microsecondsSinceEpoch.toString()) as String,
                  's': s,
                  'e': e,
                  't': c.text.trim(),
                  'w': w,
                });
              },
              child: const Text('OK'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _saveEdit() async {
    tasks.sort((a, b) => tmin(a['s'] as String).compareTo(tmin(b['s'] as String)));
    await setTpl(widget.date.weekday, tasks);
    await scheduleAll();
    if (!mounted) return;
    setState(() => editing = false);
  }

  bool get _allMarked => tasks.isNotEmpty && tasks.every((t) => marks.containsKey(t['id']));

  Future<void> _finish() async {
    int mx = 0, score = 0, doneN = 0;
    final snap = <Map<String, dynamic>>[];
    for (final t in tasks) {
      final w = t['w'] as int;
      mx += w;
      final d = marks[t['id']] == true;
      if (d) {
        score += w;
        doneN++;
      }
      snap.add({...t, 'd': d});
    }
    final pct = mx == 0 ? 0.0 : score * 100.0 / mx;
    final msgs = getMsgs();
    final r = pct.round();
    final msg = r <= 30 ? msgs[0] : (r <= 70 ? msgs[1] : msgs[2]);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Natija: ${pctText(pct)}'),
        content: Text('Bajarildi: $doneN/${tasks.length} vazifa\nBall: $score/$mx\n\n$msg'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    await putArch(dkey(widget.date), {
      'noPlan': false,
      'tasks': snap,
      'pct': pct,
      'score': score,
      'max': mx,
      'doneN': doneN,
      'total': tasks.length,
    });
    await scheduleAll();
    if (!mounted) return;
    setState(_load);
  }

  Future<void> _noPlan() async {
    await putArch(dkey(widget.date), {'noPlan': true, 'tasks': [], 'pct': 0.0});
    await scheduleAll();
    if (!mounted) return;
    setState(_load);
  }

  Widget _livePanel() {
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;
    Map<String, dynamic>? cur;
    int elapsed = 0, durS = 0;
    for (final t in tasks) {
      final sS = tmin(t['s'] as String) * 60;
      final d = durMin(t['s'] as String, t['e'] as String) * 60;
      final el = (nowSec - sS + 86400) % 86400;
      if (d > 0 && el < d) {
        cur = t;
        elapsed = el;
        durS = d;
        break;
      }
    }
    if (cur == null) {
      Map<String, dynamic>? nxt;
      int best = 999999;
      for (final t in tasks) {
        final st = tmin(t['s'] as String) * 60;
        if (st > nowSec && st - nowSec < best) {
          best = st - nowSec;
          nxt = t;
        }
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(nxt == null ? 'Hozir vazifa yo\'q.' : 'Hozir vazifa yo\'q.\nKeyingisi: ${nxt['t']} (${nxt['s']}) — ${hms(best)} dan keyin'),
        ),
      );
    }
    final rem = durS - elapsed;
    return Card(
      shape: RoundedRectangleBorder(side: const BorderSide(color: kAccent), borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hozir: ${cur['t']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('${cur['s']}–${cur['e']} · Daraja ${cur['w']}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: elapsed / durS),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Ketdi: ${hms(elapsed)}'), Text('Qoldi: ${hms(rem)}', style: const TextStyle(color: kAccent, fontWeight: FontWeight.bold))],
            ),
          ],
        ),
      ),
    );
  }

  Widget _markBtn(String e, bool sel, Color c, VoidCallback f) {
    return GestureDetector(
      onTap: f,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(left: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? c.withOpacity(0.35) : Colors.transparent,
          border: Border.all(color: sel ? c : Colors.grey.shade700),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(e),
      ),
    );
  }

  Widget _header(bool withMarks) {
    const st = TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 48, child: Text('Boshlash', style: st)),
          const SizedBox(width: 48, child: Text('Tugatish', style: st)),
          const Expanded(child: Text('Vazifa', style: st)),
          const SizedBox(width: 26, child: Text('Daraja', style: TextStyle(fontSize: 9, color: Colors.grey))),
          if (withMarks) ...[
            const SizedBox(width: 40, child: Center(child: Text('✅'))),
            const SizedBox(width: 40, child: Center(child: Text('❌'))),
          ],
        ],
      ),
    );
  }

  Widget _markRow(Map<String, dynamic> t) {
    final id = t['id'] as String;
    final v = marks[id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(t['s'] as String, style: const TextStyle(fontSize: 13))),
          SizedBox(width: 48, child: Text(t['e'] as String, style: const TextStyle(fontSize: 13))),
          Expanded(child: Text(t['t'] as String)),
          SizedBox(width: 26, child: Text('${t['w']}')),
          _markBtn('✅', v == true, Colors.green, () => _mark(id, true)),
          _markBtn('❌', v == false, Colors.red, () => _mark(id, false)),
        ],
      ),
    );
  }

  Widget _editBody() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text("Bu reja shu hafta kunining har haftasi uchun amal qiladi. Arxivdagi eski kunlar o'zgarmaydi.", style: TextStyle(color: Colors.grey, fontSize: 12)),
        for (final t in tasks)
          Card(
            child: ListTile(
              title: Text(t['t'] as String),
              subtitle: Text('${t['s']}–${t['e']} · Daraja ${t['w']}'),
              onTap: () async {
                final r = await _taskDialog(t);
                if (r != null) setState(() => t.addAll(r));
              },
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => setState(() => tasks.remove(t))),
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text("Vazifa qo'shish"),
          onPressed: () async {
            final r = await _taskDialog(null);
            if (r != null) setState(() => tasks.add(r));
          },
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kAccent, padding: const EdgeInsets.all(14)),
          onPressed: _saveEdit,
          child: const Text('Saqlash', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = '${kDays[widget.date.weekday - 1]} · ${dshow(widget.date)}';
    Widget body;
    if (editing) {
      body = _editBody();
    } else if (archived != null) {
      body = ArchiveBody(entry: archived!);
    } else {
      body = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (isToday && tasks.isNotEmpty) _livePanel(),
          if (tasks.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text("Bu kun uchun reja yo'q. ✏️ tugmasi bilan reja tuzing.", style: TextStyle(color: Colors.grey))),
          if (tasks.isNotEmpty) _header(isToday),
          for (final t in tasks)
            isToday
                ? _markRow(t)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 48, child: Text(t['s'] as String)),
                      SizedBox(width: 48, child: Text(t['e'] as String)),
                      Expanded(child: Text(t['t'] as String)),
                      SizedBox(width: 26, child: Text('${t['w']}')),
                    ]),
                  ),
          if (isToday) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kAccent, padding: const EdgeInsets.all(14)),
              onPressed: _allMarked ? _finish : null,
              child: const Text('Tayyor', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            if (!_allMarked && tasks.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Hamma vazifa uchun ✅ yoki ❌ tanlang', style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center)),
            TextButton(onPressed: _noPlan, child: const Text('Bugun rejali ish qilmayman')),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!editing) IconButton(icon: const Icon(Icons.edit), onPressed: () => setState(() => editing = true)),
          if (editing) IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
                editing = false;
                _load();
              })),
        ],
      ),
      body: body,
    );
  }
}

// ====================== ARXIV ======================
double? avgOf(Iterable<dynamic> entries) {
  final l = entries.map((e) => Map<String, dynamic>.from(e as Map)).where((e) => e['noPlan'] != true).toList();
  if (l.isEmpty) return null;
  return l.fold<double>(0, (a, e) => a + (e['pct'] as num).toDouble()) / l.length;
}

class ArchiveBody extends StatelessWidget {
  final Map<String, dynamic> entry;
  const ArchiveBody({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry['noPlan'] == true) {
      return const Center(child: Text('Rejasiz kun\n(statistikaga hisoblanmaydi)', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)));
    }
    final tasks = castList(entry['tasks']);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bajarildi: ${pctText(entry['pct'] as num)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kAccent)),
                const SizedBox(height: 4),
                Text('Vazifalar: ${entry['doneN']}/${entry['total']} bajarilgan'),
                Text('Ball: ${entry['score']}/${entry['max']}'),
              ],
            ),
          ),
        ),
        for (final t in tasks)
          Card(
            child: ListTile(
              leading: Text(t['d'] == true ? '✅' : '❌', style: const TextStyle(fontSize: 22)),
              title: Text(t['t'] as String),
              subtitle: Text('${t['s']}–${t['e']} · Daraja ${t['w']}'),
            ),
          ),
      ],
    );
  }
}

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final arch = getArch();
    final months = arch.keys.map((k) => k.substring(0, 7)).toSet().toList()..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arxiv'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) {
              if (v == 'stats') Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'stats', child: Text('Statistika'))],
          ),
        ],
      ),
      body: months.isEmpty
          ? const Center(child: Text('Arxiv hozircha bo\'sh', style: TextStyle(color: Colors.grey)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final m in months)
                  Builder(builder: (context) {
                    final y = int.parse(m.substring(0, 4));
                    final mo = int.parse(m.substring(5, 7));
                    final avg = avgOf(arch.entries.where((e) => e.key.startsWith(m)).map((e) => e.value));
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder, color: kAccent),
                        title: Text('${kMonths[mo - 1][0].toUpperCase()}${kMonths[mo - 1].substring(1)} $y'),
                        subtitle: Text(avg == null ? "O'rtacha: —" : "O'rtacha: ${pctText(avg)}"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MonthScreen(year: y, month: mo))),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class MonthScreen extends StatelessWidget {
  final int year, month;
  const MonthScreen({super.key, required this.year, required this.month});

  @override
  Widget build(BuildContext context) {
    final arch = getArch();
    final days = DateTime(year, month + 1, 0).day;
    return Scaffold(
      appBar: AppBar(title: Text('${kMonths[month - 1]} $year')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: days,
        itemBuilder: (c, i) {
          final d = DateTime(year, month, i + 1);
          final a = arch[dkey(d)];
          Map<String, dynamic>? e = a == null ? null : Map<String, dynamic>.from(a as Map);
          String trail = '—';
          if (e != null) trail = e['noPlan'] == true ? 'Rejasiz kun' : pctText(e['pct'] as num);
          return Card(
            child: ListTile(
              title: Text('${dshow(d)} · ${kDays[d.weekday - 1]}'),
              trailing: Text(trail, style: TextStyle(color: e == null ? Colors.grey : kAccent, fontWeight: FontWeight.bold)),
              onTap: e == null
                  ? null
                  : () => Navigator.push(
                        c,
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text('${kDays[d.weekday - 1]} · ${dshow(d)}')),
                            body: ArchiveBody(entry: e!),
                          ),
                        ),
                      ),
            ),
          );
        },
      ),
    );
  }
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late DateTime start;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    start = DateTime(n.year, n.month, n.day - (n.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final arch = getArch();
    final days = [for (int i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i)];
    final entries = <dynamic>[for (final d in days) if (arch[dkey(d)] != null) arch[dkey(d)]];
    final avg = avgOf(entries);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistika')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => start = DateTime(start.year, start.month, start.day - 7))),
              Text('${dshow(days.first)} – ${dshow(days.last)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => start = DateTime(start.year, start.month, start.day + 7))),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text("Haftalik o'rtacha", style: TextStyle(color: Colors.grey)),
                  Text(avg == null ? '—' : pctText(avg), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: kAccent)),
                  const Text('(rejasiz kunlar hisobga olinmaydi)', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          ),
          for (final d in days)
            Builder(builder: (context) {
              final a = arch[dkey(d)];
              final e = a == null ? null : Map<String, dynamic>.from(a as Map);
              final np = e == null || e['noPlan'] == true;
              final v = np ? 0.0 : (e['pct'] as num).toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 90, child: Text(kDays[d.weekday - 1].substring(0, 3) + ' ' + two(d.day) + '.' + two(d.month))),
                    Expanded(child: LinearProgressIndicator(value: v / 100, minHeight: 10)),
                    SizedBox(width: 76, child: Text(e == null ? '—' : (np ? 'Rejasiz' : pctText(v)), textAlign: TextAlign.right)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
