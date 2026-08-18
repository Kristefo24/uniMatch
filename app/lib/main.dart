import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Official application pages per seeded university id.
const Map<String, String> kApplyUrls = {
  'uni-uok': 'https://www.uok.ac.rw/admissions/',
  'uni-eau': 'https://eau.ac.rw/apply/',
  'uni-alu': 'https://www.alueducation.com/apply/',
  'uni-auca': 'https://auca.ac.rw/apply/',
  'uni-urcmhs': 'https://apply.ur.ac.rw/',
  'uni-kepler': 'https://www.kepler.org/apply/',
  'uni-ulk': 'https://www.ulk.ac.rw/admission/',
};

/// ---------------------------------------------------------------------------
/// UniMatch Gasabo — Flutter client for the Node backend in ../server
///
/// Base URL notes:
///  - Web / Windows / desktop reach the server at localhost
///  - Android emulator reaches your PC's localhost at 10.0.2.2
///  - Real device on same Wi-Fi: use your PC's LAN IP, e.g. http://192.168.1.20:4000
/// ---------------------------------------------------------------------------
/// Set kApiUrl to your deployed backend and flip kUseHosted to true for
/// release builds. Local dev (default) falls back to localhost (web/desktop)
/// or 10.0.2.2 (Android emulator) — see RUN.md.
const String kApiUrl = 'https://your-deployed-backend.example.com';
const bool kUseHosted = false;
final String kBaseUrl = kUseHosted
    ? kApiUrl
    : (kIsWeb ? 'http://localhost:4000' : 'http://10.0.2.2:4000');

// Known seeded university ids (see server/index.js seedStore)
const List<String> kUniversityIds = [
  'uni-uok', 'uni-eau', 'uni-alu',
  'uni-auca', 'uni-urcmhs', 'uni-kepler', 'uni-ulk',
];

// Icon + universities-count metadata for the department grid.
/// Keyword-based icon lookup shared by department and programme cards — real
/// department/programme names vary a lot (see seed.js), so this matches on
/// substrings rather than an exact-name map, giving each card a sensible,
/// distinct icon instead of one generic fallback everywhere.
IconData iconForField(String text) {
  final d = text.toLowerCase();
  if (d.contains('comput') || d.contains('information tech') || d.contains('software') ||
      d.contains('network') || d.contains('science & tech') || d.contains('analytics')) return Icons.memory;
  if (d.contains('market')) return Icons.campaign_outlined;
  if (d.contains('financ')) return Icons.account_balance_wallet_outlined;
  if (d.contains('account')) return Icons.calculate_outlined;
  if (d.contains('administr') || d.contains('governance') || d.contains('procurement') || d.contains('supplies')) {
    return Icons.account_balance_outlined;
  }
  if (d.contains('business') || d.contains('management') || d.contains('economics') ||
      d.contains('entrepren') || d.contains('strategic') || d.contains('trade')) return Icons.business_center_outlined;
  if (d.contains('law')) return Icons.gavel;
  if (d.contains('educat') || d.contains('childhood')) return Icons.school_outlined;
  if (d.contains('medic') || d.contains('health') || d.contains('nursing') || d.contains('pharm') ||
      d.contains('dent') || d.contains('midwif')) return Icons.local_hospital_outlined;
  if (d.contains('film') || d.contains('media') || d.contains('communication') || d.contains('journal') ||
      d.contains('broadcast') || d.contains('animation') || d.contains('theatre') || d.contains('visual effect')) {
    return Icons.movie_creation_outlined;
  }
  if (d.contains('tourism') || d.contains('hotel') || d.contains('leisure') || d.contains('hospitality') ||
      d.contains('travel')) return Icons.hotel_outlined;
  if (d.contains('theolog')) return Icons.auto_stories_outlined;
  if (d.contains('social')) return Icons.groups_outlined;
  return Icons.school_outlined;
}

/// Every 2-subject combination from a staff-selected subject list — a
/// student is eligible for a programme if they passed any pair shown here.
List<String> subjectPairs(List<String> subs) {
  final out = <String>[];
  for (var i = 0; i < subs.length; i++) {
    for (var j = i + 1; j < subs.length; j++) out.add('${subs[i]} + ${subs[j]}');
  }
  return out;
}

const List<String> kDepartments = [
  'Computer Science', 'Software Engineering', 'Information Technology',
  'Business Administration', 'Accounting', 'Nursing', 'Medicine', 'Pharmacy',
];

// A2 combinations a student can pick on signup.
const List<Map<String, String>> kTracks = [
  {'id': 'sciences', 'label': 'Sciences (MPC/BCG)'},
  {'id': 'humanities', 'label': 'Humanities (HGL)'},
  {'id': 'languages', 'label': 'Languages (LKK)'},
  {'id': 'commerce', 'label': 'Commerce (MEG)'},
];

/// ---- Theme (matches the UniMatch design system) ----------------------------
class C {
  static const green = Color(0xFF1F5F4A);
  static const greenDark = Color(0xFF184C3B);
  static const gold = Color(0xFFF5C955);
  static const cream = Color(0xFFFBF8F3);
  static const sand = Color(0xFFF1EBE0);
  static const border = Color(0xFFEBE5D8);
  static const ink = Color(0xFF1A1A17);
  static const muted = Color(0xFF6B6960);

  // Distinct brand color per university (matches the prototype crests).
  static const _uniColors = {
    'UoK': Color(0xFF2A5C8F), 'EAU': Color(0xFF8F4B2A), 'ALU': Color(0xFFB48412),
    'AUCA': Color(0xFF7A2F4A), 'UR/CMHS': Color(0xFF164638), 'Kepler': Color(0xFFB4472A),
    'ULK': Color(0xFF2F4A7A),
  };
  static Color uni(String abbr) => _uniColors[abbr] ?? green;
}

void main() => runApp(const UniMatchApp());

/// ---- API layer -------------------------------------------------------------
class Api {
  static String? token;

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<Map<String, dynamic>> _post(String path, Map body) async {
    final r = await http.post(Uri.parse('$kBaseUrl$path'),
        headers: _headers(), body: jsonEncode(body));
    final data = r.body.isNotEmpty ? jsonDecode(r.body) : {};
    if (r.statusCode >= 400) {
      throw ApiError(data is Map ? (data['error'] ?? 'Request failed') : 'Request failed');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$kBaseUrl$path'), headers: _headers());
    final data = r.body.isNotEmpty ? jsonDecode(r.body) : {};
    if (r.statusCode >= 400) {
      throw ApiError(data is Map ? (data['error'] ?? 'Request failed') : 'Request failed');
    }
    return data;
  }

  static Future<Map<String, dynamic>> _put(String path, Map body) async {
    final r = await http.put(Uri.parse('$kBaseUrl$path'),
        headers: _headers(), body: jsonEncode(body));
    final data = r.body.isNotEmpty ? jsonDecode(r.body) : {};
    if (r.statusCode >= 400) {
      throw ApiError(data is Map ? (data['error'] ?? 'Request failed') : 'Request failed');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<void> _delete(String path) async {
    final r = await http.delete(Uri.parse('$kBaseUrl$path'), headers: _headers());
    if (r.statusCode >= 400) {
      final data = r.body.isNotEmpty ? jsonDecode(r.body) : {};
      throw ApiError(data is Map ? (data['error'] ?? 'Request failed') : 'Request failed');
    }
  }

  static Future<Map<String, dynamic>> signup(String name, String email,
          String password, String role,
          {String? track, String? universityId}) =>
      _post('/signup', {
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        if (track != null) 'track': track,
        if (universityId != null) 'universityId': universityId,
      });

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _post('/login', {'email': email, 'password': password});
    token = res['token'];
    return res;
  }

  static Future<List<dynamic>> programmes(String? dept) async =>
      await _get('/programmes${dept != null ? '?dept=${Uri.encodeQueryComponent(dept)}' : ''}') as List<dynamic>;

  /// Admin-managed criteria catalogue (with a hasData flag per code), cached
  /// for the running session — pass refresh:true to force a re-fetch.
  static Future<List<dynamic>> criteria({bool refresh = false}) async {
    if (!refresh && Session.criteriaCatalogue != null) return Session.criteriaCatalogue!;
    final list = await _get('/criteria') as List<dynamic>;
    Session.criteriaCatalogue = list;
    return list;
  }

  static Future<List<dynamic>> rank(List<Map<String, dynamic>> criteria, {String? preferredReligion}) async {
    final res = await _post('/rank', {
      'universityIds': kUniversityIds,
      'criteria': criteria,
      if (preferredReligion != null) 'preferredReligion': preferredReligion,
    });
    return List<dynamic>.from(res['ranked'] ?? []);
  }

  static Future<Map<String, dynamic>> university(String id) async =>
      Map<String, dynamic>.from(await _get('/universities/$id'));

  /// Public read of a university's staff-entered answers (campuses/combos/
  /// criteria blob) — unlike Api.staffData, no auth is required, so any
  /// A2 graduate can read another university's published data.
  static Future<Map<String, dynamic>> universityAnswers(String id) async =>
      Map<String, dynamic>.from(await _get('/universities/$id/answers'));

  /// All universities (id, abbr, name) — reuses /rank with no criteria so the
  /// signup dropdown and pickers can list them without a dedicated endpoint.
  static Future<List<dynamic>> universities() async {
    final res = await _post('/rank', {'universityIds': kUniversityIds, 'criteria': []});
    return List<dynamic>.from(res['ranked'] ?? []);
  }

  static Future<void> apply(String universityId, String programmeId, String homeArea) =>
      _post('/apply', {'universityId': universityId, 'programmeId': programmeId, 'homeArea': homeArea});

  static Future<void> shortlist(String universityId) =>
      _post('/shortlist', {'universityId': universityId});

  static Future<List<dynamic>> myShortlist() async =>
      await _get('/shortlist') as List<dynamic>;

  static Future<void> removeShortlist(String universityId) =>
      _delete('/shortlist/$universityId');

  static Future<void> rate(String universityId, int stars) =>
      _post('/rate', {'universityId': universityId, 'stars': stars});

  static Future<List<dynamic>> staffRequests() async =>
      await _get('/staff-requests') as List<dynamic>;

  static Future<void> confirmStaff(String id) => _post('/staff-requests/$id/confirm', {});
  static Future<Map<String, dynamic>> forgotPassword(String email) =>
      _post('/forgot-password', {'email': email});
  static Future<void> setStaffStatus(String id, String status) =>
      _post('/staff-requests/$id/status', {'status': status});
  static Future<void> deleteStaff(String id) => _delete('/staff-requests/$id');

  // ---- staff: own university data ----
  static Future<Map<String, dynamic>> staffData(String uniId) async =>
      Map<String, dynamic>.from(await _get('/staff/$uniId/data'));
  static Future<void> saveStaffCampuses(String uniId, List campuses) =>
      _put('/staff/$uniId/campuses', {'campuses': campuses});
  static Future<void> saveStaffCombos(String uniId, Map combos) =>
      _put('/staff/$uniId/combos', {'combos': combos});
  static Future<void> saveStaffCriteria(String uniId, Map criteria) =>
      _put('/staff/$uniId/criteria', {'criteria': criteria});
  static Future<Map<String, dynamic>> staffReport(String uniId) async =>
      Map<String, dynamic>.from(await _get('/staff/$uniId/report'));
  static Future<Map<String, dynamic>> adminReport() async =>
      Map<String, dynamic>.from(await _get('/admin/report'));

  // ---- admin: universities ----
  static Future<List<dynamic>> adminUniversities() async =>
      await _get('/admin/universities') as List<dynamic>;
  static Future<void> addUniversity(String abbr, String name, String sector) =>
      _post('/admin/universities', {'abbr': abbr, 'name': name, 'sector': sector});
  static Future<void> updateUniversity(String id, String abbr, String name, String sector) =>
      _put('/admin/universities/$id', {'abbr': abbr, 'name': name, 'sector': sector});
  static Future<void> deleteUniversity(String id) => _delete('/admin/universities/$id');

  // ---- admin: criteria ----
  static Future<List<dynamic>> adminCriteria() async =>
      await _get('/admin/criteria') as List<dynamic>;
  static Future<void> addCriterion(String label, String category, String direction) =>
      _post('/admin/criteria', {'label': label, 'category': category, 'direction': direction});
  static Future<void> updateCriterion(String code, String label, String category, String direction) =>
      _put('/admin/criteria/$code', {'label': label, 'category': category, 'direction': direction});
  static Future<void> deleteCriterion(String code) => _delete('/admin/criteria/$code');
  static Future<List<dynamic>> criteriaUsage() async =>
      await _get('/admin/criteria-usage') as List<dynamic>;

  // ---- admin: students ----
  static Future<List<dynamic>> adminStudents() async =>
      await _get('/admin/students') as List<dynamic>;
  static Future<void> setStudentSuspended(String id, bool suspended) =>
      _post('/admin/students/$id/suspended', {'suspended': suspended});
}

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

/// ---- Session ---------------------------------------------------------------
class Session {
  static String name = '';
  static String email = '';
  static String role = 'student';
  static String? uniId;
  static List<dynamic>? lastRanking;
  static List<Map<String, dynamic>> lastCriteria = [];
  static List<dynamic>? criteriaCatalogue;
  static String? selectedProgramme;
  static String homeArea = '';
  static String? preferredReligion;

  static String get initial => name.isEmpty ? 'U' : name.trim()[0].toUpperCase();
  static String get first => name.isEmpty ? '' : name.split(' ').first;
}

/// ---- Shared chrome: profile menu + admin drawer ---------------------------
Future<void> _logout(BuildContext context) async {
  Api.token = null;
  Session.name = ''; Session.email = ''; Session.role = 'student'; Session.uniId = null;
  Session.criteriaCatalogue = null;
  Session.selectedProgramme = null; Session.homeArea = ''; Session.lastRanking = null;
  Navigator.pushAndRemoveUntil(
      context, MaterialPageRoute(builder: (_) => const OnboardingScreen()), (r) => false);
}

Future<void> _editProfile(BuildContext context) async {
  final name = TextEditingController(text: Session.name);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.cream,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Edit profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
        const SizedBox(height: 16),
        TextField(controller: name, decoration: fieldDeco('Full name')),
        const SizedBox(height: 12),
        TextField(enabled: false, decoration: fieldDeco(Session.email)),
        const SizedBox(height: 20),
        primaryButton('Save', () { Session.name = name.text.trim(); Navigator.pop(ctx); }),
      ]),
    ),
  );
}

/// Circular avatar that opens a menu: Edit profile / Log out.
Widget profileAction(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: PopupMenuButton<String>(
        onSelected: (v) { if (v == 'logout') _logout(context); else if (v == 'edit') _editProfile(context); },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'header', enabled: false, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Session.name.isEmpty ? 'Signed in' : Session.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
              Text(Session.email, style: const TextStyle(color: C.muted, fontSize: 12)),
            ])),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'edit', child: Row(children: [
            Icon(Icons.edit_outlined, size: 18, color: C.green), SizedBox(width: 10), Text('Edit profile')])),
          const PopupMenuItem(value: 'logout', child: Row(children: [
            Icon(Icons.logout, size: 18, color: Color(0xFFC25A1F)), SizedBox(width: 10), Text('Log out')])),
        ],
        child: CircleAvatar(radius: 17, backgroundColor: C.green,
            child: Text(Session.initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      ),
    );

/// Navigation drawer listing every admin destination.
Drawer adminDrawer(BuildContext context) => Drawer(
      backgroundColor: C.cream,
      child: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: C.green,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 22, backgroundColor: C.gold,
                  child: Text(Session.initial, style: const TextStyle(color: C.greenDark, fontWeight: FontWeight.w700))),
              const SizedBox(height: 10),
              Text(Session.name.isEmpty ? 'Administrator' : Session.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Text(Session.email, style: const TextStyle(color: Color(0xFFCDE3DA), fontSize: 12)),
            ]),
          ),
          _drawerItem(context, Icons.dashboard_outlined, 'Dashboard', const AdminDashboard(), replace: true),
          _drawerItem(context, Icons.verified_user_outlined, 'Staff approvals', const AdminApprovalsScreen()),
          _drawerItem(context, Icons.apartment, 'Universities', const AdminUniversitiesScreen()),
          _drawerItem(context, Icons.tune, 'Evaluation criteria', const AdminCriteriaScreen()),
          _drawerItem(context, Icons.people_outline, 'Student accounts', const AdminStudentsScreen()),
          _drawerItem(context, Icons.bar_chart, 'Reports', const AdminReportsScreen()),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFC25A1F)),
            title: const Text('Log out', style: TextStyle(color: Color(0xFFC25A1F))),
            onTap: () => _logout(context),
          ),
        ]),
      ),
    );

Widget _drawerItem(BuildContext ctx, IconData icon, String label, Widget dest, {bool replace = false}) => ListTile(
      leading: Icon(icon, color: C.green),
      title: Text(label, style: const TextStyle(color: C.ink, fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.pop(ctx);
        if (replace) {
          Navigator.pushAndRemoveUntil(ctx, MaterialPageRoute(builder: (_) => dest), (r) => false);
        } else {
          Navigator.push(ctx, MaterialPageRoute(builder: (_) => dest));
        }
      },
    );

/// AppBar shared by every admin page: hamburger (drawer) + title + profile menu.
/// On sub-pages pass back:true for a small back arrow (drawer still reachable via the menu action).
AppBar adminAppBar(BuildContext context, String title, {bool back = false}) => AppBar(
      backgroundColor: C.cream, elevation: 0, foregroundColor: C.ink,
      leading: back
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context))
          : null,
      title: Text(title),
      actions: [
        if (back)
          Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer())),
        profileAction(context),
      ],
    );

/// ---- App root --------------------------------------------------------------
class UniMatchApp extends StatelessWidget {
  const UniMatchApp({super.key});
  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      scaffoldBackgroundColor: C.cream,
      colorScheme: ColorScheme.fromSeed(seedColor: C.green, primary: C.green),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'UniMatch Gasabo',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        // Body text: clean grotesque sans, matching the prototype.
        textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(
          bodyColor: C.ink, displayColor: C.ink,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: C.cream, elevation: 0, foregroundColor: C.ink,
          centerTitle: false,
          titleTextStyle: GoogleFonts.bricolageGrotesque(
              fontSize: 19, fontWeight: FontWeight.w600, color: C.ink, letterSpacing: -0.3),
        ),
      ),
      home: const OnboardingScreen(),
    );
  }
}

/// Prototype display font (Bricolage Grotesque) for headlines.
TextStyle head(double size, {Color color = C.ink, FontWeight weight = FontWeight.w600}) =>
    GoogleFonts.bricolageGrotesque(fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.5, height: 1.05);

/// ---- Shared widgets --------------------------------------------------------
Widget primaryButton(String label, VoidCallback? onTap, {bool loading = false}) {
  return SizedBox(
    height: 54,
    width: double.infinity,
    child: ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: C.green,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: loading
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
  );
}

InputDecoration fieldDeco(String hint, {IconData? icon}) => InputDecoration(
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: C.muted, size: 20) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.green, width: 1.6)),
    );

void toast(BuildContext ctx, String msg) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg), backgroundColor: C.greenDark));

/// ---- Onboarding ------------------------------------------------------------
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.greenDark,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [C.greenDark, C.green],
                ),
              ),
            ),
          ),
          Positioned(
            top: -140, right: -100,
            child: Container(
              width: 380, height: 380,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x552F8F6B), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -160, left: -120,
            child: Container(
              width: 420, height: 420,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x33F5C955), Color(0x00000000)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: const Text('U', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.greenDark)),
                  ),
                  const Spacer(),
                  Text.rich(
                    TextSpan(
                      style: head(34, color: Colors.white, weight: FontWeight.w700),
                      children: [
                        const TextSpan(text: 'Find your best-fit '),
                        TextSpan(
                          text: 'university.',
                          style: head(34, color: C.gold, weight: FontWeight.w700).copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Compare Gasabo universities on what matters to you — fees, distance, and more.',
                    style: TextStyle(color: Color(0xFFCDE3DA), fontSize: 15, height: 1.5),
                  ),
                  const Spacer(),
                  primaryButtonGold('Create free account', () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen()));
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 54, width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('I already have an account',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget primaryButtonGold(String label, VoidCallback onTap) => SizedBox(
      height: 54, width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: C.gold, foregroundColor: C.greenDark, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );

/// Reusable pill-style search field for list screens.
Widget searchField(TextEditingController c, String hint) => TextField(
      controller: c,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, color: C.muted),
        filled: true, fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.green)),
      ),
    );

/// ---- Login -----------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool loading = false;

  Future<void> _login() async {
    setState(() => loading = true);
    try {
      final res = await Api.login(email.text.trim(), pass.text);
      final user = res['user'] as Map;
      Session.name = user['name'] ?? '';
      Session.email = user['email'] ?? '';
      Session.role = user['role'] ?? 'student';
      Session.uniId = user['universityId'];
      if (!mounted) return;
      _routeByRole(context, Session.role);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: C.cream, elevation: 0, foregroundColor: C.ink),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back', style: head(28)),
              const SizedBox(height: 6),
              const Text('Log in — you\'ll land on the right home for your role.',
                  style: TextStyle(color: C.muted, fontSize: 14)),
              const SizedBox(height: 28),
              TextField(controller: email, decoration: fieldDeco('Email', icon: Icons.mail_outline)),
              const SizedBox(height: 14),
              TextField(controller: pass, obscureText: true, decoration: fieldDeco('Password', icon: Icons.lock_outline)),
              const SizedBox(height: 24),
              primaryButton('Log in', _login, loading: loading),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                  child: const Text('Forgot password?', style: TextStyle(color: C.muted)),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                  child: const Text('New here? Create an account', style: TextStyle(color: C.green)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _routeByRole(BuildContext context, String role) {
  Widget home;
  if (role == 'admin') {
    home = const AdminDashboard();
  } else if (role == 'staff') {
    home = const StaffDashboard();
  } else {
    home = const StudentHome();
  }
  Navigator.pushAndRemoveUntil(
      context, MaterialPageRoute(builder: (_) => home), (r) => false);
}

/// ---- Forgot password + OTP reset ------------------------------------------
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final email = TextEditingController();
  bool loading = false;

  Future<void> _submit() async {
    if (email.text.trim().isEmpty) { toast(context, 'Enter your email'); return; }
    setState(() => loading = true);
    try {
      final res = await Api.forgotPassword(email.text.trim());
      if (!mounted) return;
      if (res['staff'] == true) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const _StaffResetPendingScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OtpResetScreen(email: email.text.trim())));
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Forgot password', style: head(28)),
            const SizedBox(height: 6),
            const Text('Enter your email and we\'ll send a reset code. Staff resets are re-confirmed by an admin.',
                style: TextStyle(color: C.muted, fontSize: 14)),
            const SizedBox(height: 24),
            TextField(controller: email, decoration: fieldDeco('Email', icon: Icons.mail_outline)),
            const SizedBox(height: 24),
            primaryButton('Send reset code', _submit, loading: loading),
          ]),
        ),
      ),
    );
  }
}

class _StaffResetPendingScreen extends StatelessWidget {
  const _StaffResetPendingScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.shield_outlined, color: C.green, size: 48),
            const SizedBox(height: 16),
            Text('Sent to admin', style: head(24), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text('Your reset request was sent to the administrator. Your staff account is pending until an admin re-confirms it — then you can log in with a new password.',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.5)),
            const SizedBox(height: 24),
            primaryButton('Back to login', () => Navigator.pushAndRemoveUntil(
                context, MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false)),
          ]),
        ),
      ),
    );
  }
}

class OtpResetScreen extends StatefulWidget {
  final String email;
  const OtpResetScreen({super.key, required this.email});
  @override
  State<OtpResetScreen> createState() => _OtpResetScreenState();
}

class _OtpResetScreenState extends State<OtpResetScreen> {
  final otp = TextEditingController();
  final pass = TextEditingController();
  int seconds = 120;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seconds == 0) { t.cancel(); } else { setState(() => seconds--); }
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  String get mmss =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Enter reset code', style: head(28)),
            const SizedBox(height: 8),
            Text('We sent a 6-digit code to ${widget.email}. (Demo code: 123456)',
                style: const TextStyle(color: C.muted, fontSize: 14)),
            const SizedBox(height: 24),
            TextField(
              controller: otp,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
              decoration: fieldDeco('••••••'),
            ),
            const SizedBox(height: 10),
            Center(child: Text(seconds > 0 ? 'Code expires in $mmss' : 'Code expired — resend',
                style: TextStyle(color: seconds > 0 ? C.muted : Colors.red, fontWeight: FontWeight.w600))),
            const SizedBox(height: 20),
            TextField(controller: pass, obscureText: true, decoration: fieldDeco('New password', icon: Icons.lock_outline)),
            const SizedBox(height: 24),
            primaryButton('Reset password', () {
              if (otp.text.trim().isEmpty || pass.text.isEmpty) { toast(context, 'Enter the code and a new password'); return; }
              toast(context, 'Password reset — you can log in now.');
              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
            }),
          ]),
        ),
      ),
    );
  }
}

/// ---- Signup ----------------------------------------------------------------
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  String role = 'student';
  String track = 'sciences';          // A2 track (student)
  String? uniId;                       // university you work for (staff)
  List<dynamic> universities = [];     // loaded for the staff dropdown
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadUniversities();
  }

  Future<void> _loadUniversities() async {
    try {
      final list = await Api.universities();
      if (mounted) setState(() => universities = list);
    } catch (_) {
      // Dropdown just stays empty until the server is reachable.
    }
  }

  Future<void> _signup() async {
    if (role == 'staff' && uniId == null) {
      toast(context, 'Please choose the university you work for.');
      return;
    }
    setState(() => loading = true);
    try {
      await Api.signup(name.text.trim(), email.text.trim(), pass.text, role,
          track: role == 'student' ? track : null,
          universityId: role == 'staff' ? uniId : null);
      if (!mounted) return;
      if (role == 'staff') {
        toast(context, 'Staff account created — an admin must confirm it before you can log in.');
        Navigator.pop(context);
      } else {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => VerifyScreen(email: email.text.trim())));
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _roleChip(String value, String label) {
    final sel = role == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => role = value),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? C.green : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? C.green : C.border),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: sel ? Colors.white : C.ink, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _trackChip(Map<String, String> t) {
    final sel = track == t['id'];
    return GestureDetector(
      onTap: () => setState(() => track = t['id']!),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: sel ? C.green : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? C.green : C.border),
        ),
        alignment: Alignment.center,
        child: Text(t['label']!,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: sel ? Colors.white : C.ink, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: C.green, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: C.cream, elevation: 0, foregroundColor: C.ink),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create your account', style: head(28)),
              const SizedBox(height: 6),
              const Text('We\'ll send a verification link to your email — that\'s how we know it\'s really you.',
                  style: TextStyle(color: C.muted, fontSize: 14)),
              const SizedBox(height: 20),
              _label('I AM A'),
              Row(children: [
                _roleChip('student', 'A2 graduate'),
                _roleChip('staff', 'University staff'),
              ]),
              const SizedBox(height: 18),
              _label('FULL NAME'),
              TextField(controller: name, decoration: fieldDeco('e.g. Amara Mukamana')),
              const SizedBox(height: 16),
              _label('EMAIL'),
              TextField(controller: email, decoration: fieldDeco('amara@example.com')),
              const SizedBox(height: 16),

              // ---- STUDENT: A2 track ----
              if (role == 'student') ...[
                _label('A2 TRACK'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 3.2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: kTracks.map(_trackChip).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // ---- STAFF: university you work for ----
              if (role == 'staff') ...[
                _label('UNIVERSITY YOU WORK FOR'),
                DropdownButtonFormField<String>(
                  value: uniId,
                  isExpanded: true,
                  decoration: fieldDeco('Select your university…'),
                  hint: const Text('Select your university…'),
                  items: universities.map((u) {
                    final m = u as Map;
                    return DropdownMenuItem<String>(
                      value: m['id'] as String,
                      child: Text('${m['abbr']} — ${m['name']}',
                          overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => uniId = v),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Your account stays pending until an admin confirms you work at this university.',
                      style: TextStyle(color: C.muted, fontSize: 12)),
                ),
                const SizedBox(height: 16),
              ],

              _label('PASSWORD'),
              TextField(controller: pass, obscureText: true, decoration: fieldDeco('8+ characters')),
              const SizedBox(height: 24),
              primaryButton('Continue', _signup, loading: loading),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---- Email verify (2-min countdown) ---------------------------------------
class VerifyScreen extends StatefulWidget {
  final String email;
  const VerifyScreen({super.key, required this.email});
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  int seconds = 120;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (seconds == 0) {
        t.cancel();
      } else {
        setState(() => seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get mmss {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: C.cream, elevation: 0, foregroundColor: C.ink),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Verify your email', style: head(28)),
              const SizedBox(height: 8),
              Text('We sent a 6-digit code to ${widget.email}.',
                  style: const TextStyle(color: C.muted, fontSize: 14)),
              const SizedBox(height: 28),
              TextField(
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
                decoration: fieldDeco('••••••'),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(seconds > 0 ? 'Code expires in $mmss' : 'Code expired — resend it',
                    style: TextStyle(color: seconds > 0 ? C.muted : Colors.red, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 24),
              primaryButton('Verify & continue', () {
                // Demo: backend verify is token-based; continue to student home.
                Session.role = 'student';
                _routeByRole(context, 'student');
              }),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: seconds == 0 ? () => setState(() => seconds = 120) : null,
                  child: const Text('Resend code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===========================================================================
/// STUDENT
/// ===========================================================================
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  List<dynamic> unis = [];
  int? criteriaCount;
  final ScrollController _marqueeCtrl = ScrollController();
  Timer? _marqueeTimer;

  @override
  void initState() {
    super.initState();
    Api.universities().then((v) { if (mounted) setState(() => unis = v); }).catchError((_) {});
    Api.criteria().then((v) { if (mounted) setState(() => criteriaCount = v.length); }).catchError((_) {});
    // Auto-scrolling marquee — the list is rendered twice back-to-back and we
    // jump to 0 once we've scrolled past the first copy, for a seamless loop.
    _marqueeTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_marqueeCtrl.hasClients || unis.isEmpty) return;
      final max = _marqueeCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      final next = _marqueeCtrl.offset + 0.6;
      _marqueeCtrl.jumpTo(next >= max / 2 ? 0 : next);
    });
  }

  @override
  void dispose() {
    _marqueeTimer?.cancel();
    _marqueeCtrl.dispose();
    super.dispose();
  }

  String get greeting => 'Welcome,';
  String get firstName => Session.first.isEmpty ? 'Amara' : Session.first;
  String get initials {
    if (Session.name.isEmpty) return 'AM';
    final parts = Session.name.trim().split(' ');
    return (parts.length > 1 ? parts[0][0] + parts[1][0] : parts[0][0]).toUpperCase();
  }

  void _toDept() => Navigator.push(context, MaterialPageRoute(builder: (_) => const DepartmentScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: a2Drawer(context),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(children: [
                Builder(builder: (ctx) => GestureDetector(
                  onTap: () => Scaffold.of(ctx).openDrawer(),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(999)),
                    alignment: Alignment.center,
                    child: Text(initials, style: GoogleFonts.bricolageGrotesque(
                        color: const Color(0xFFF5E7B8), fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greeting, style: const TextStyle(fontSize: 11, color: C.muted)),
                  Text(firstName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.ink)),
                ])),
                profileAction(context),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [C.green, Color(0xFF164638)]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YOUR RECOMMENDATION', style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: C.gold)),
                  const SizedBox(height: 8),
                  Text('Ready to find your best-fit university?',
                      style: head(24, color: const Color(0xFFFBF8F3))),
                  const SizedBox(height: 6),
                  const Text('Pick your criteria — we\'ll rank all Gasabo universities.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFFCDE3DA), height: 1.5)),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _toDept,
                    child: Container(
                      height: 42, padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Start matching', style: TextStyle(
                            color: C.green, fontWeight: FontWeight.w600, fontSize: 13.5)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, color: C.green, size: 16),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Quick actions', style: head(17, weight: FontWeight.w500)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.55,
                children: [
                  _action('Set criteria', criteriaCount != null ? '$criteriaCount criteria' : 'criteria',
                      Icons.tune, const Color(0xFFC7EBD8), C.green, _toDept),
                  _action('Shortlist', 'Saved', Icons.bookmark_border, const Color(0xFFF7D9C4), const Color(0xFFC25A1F),
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShortlistScreen()))),
                  _action('Compare', 'Side-by-side', Icons.view_column_outlined, const Color(0xFFFBEAB4), const Color(0xFFB48412),
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompareScreen()))),
                  _action('My rankings', 'Latest match', Icons.bar_chart, const Color(0xFFD8E6F2), const Color(0xFF2A5C8F),
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RankingsEntryScreen()))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Explore Gasabo', style: head(17, weight: FontWeight.w500)),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllUniversitiesA2Screen())),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Text('See all', style: TextStyle(color: C.green, fontWeight: FontWeight.w600, fontSize: 13)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, color: C.green, size: 14),
                  ]),
                ),
              ]),
            ),
            SizedBox(
              height: 132,
              child: ListView(
                controller: _marqueeCtrl,
                scrollDirection: Axis.horizontal,
                physics: unis.isEmpty ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [...unis, ...unis].map((u) {
                  final m = u as Map;
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DetailScreen(id: m['id'], name: m['name']))),
                    child: Container(
                      width: 150,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: C.uni('${m['abbr']}'), borderRadius: BorderRadius.circular(11)),
                          alignment: Alignment.center,
                          child: Text(m['abbr'] ?? '', style: const TextStyle(
                              color: C.gold, fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                        const SizedBox(height: 10),
                        Text(m['name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.ink, height: 1.2)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _action(String t, String s, IconData i, Color bg, Color fg, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Icon(i, color: fg, size: 18)),
            const Spacer(),
            Text(t, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: C.ink)),
            const SizedBox(height: 2),
            Text(s, style: const TextStyle(fontSize: 11, color: C.muted)),
          ]),
        ),
      );
}

/// A2: browse every university (from "See all") → tap to open details.
class AllUniversitiesA2Screen extends StatefulWidget {
  const AllUniversitiesA2Screen({super.key});
  @override
  State<AllUniversitiesA2Screen> createState() => _AllUniversitiesA2ScreenState();
}

class _AllUniversitiesA2ScreenState extends State<AllUniversitiesA2Screen> {
  List<dynamic> unis = [];
  bool loading = true;
  final TextEditingController _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    Api.universities().then((v) { if (mounted) setState(() { unis = v; loading = false; }); })
        .catchError((_) { if (mounted) setState(() => loading = false); });
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? unis
        : unis.where((u) => '${(u as Map)['name']}'.toLowerCase().contains(query)).toList();
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'All universities', back: true),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: searchField(_search, 'Search by name, abbreviation, campus or department'),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _emptyView('No universities match "${_search.text.trim()}".')
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: filtered.map((u) {
                          final m = u as Map;
                          return GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => DetailScreen(id: m['id'], name: m['name']))),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                              child: Row(children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(color: C.uni('${m['abbr']}'), borderRadius: BorderRadius.circular(12)),
                                  alignment: Alignment.center,
                                  child: Text(m['abbr'] ?? '', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(m['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink))),
                                const Icon(Icons.chevron_right, color: C.muted),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ]),
    );
  }
}

/// A2: My rankings entry — no ranking yet ⇒ prompt to match first.
class RankingsEntryScreen extends StatelessWidget {
  const RankingsEntryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final has = Session.lastRanking != null && Session.lastRanking!.isNotEmpty;
    if (has) {
      return ResultsScreen(criteria: Session.lastCriteria);
    }
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'My rankings', back: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.bar_chart, color: C.green, size: 28),
            ),
            const SizedBox(height: 18),
            Text('No ranking yet', style: head(24), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            const Text('Match first — pick your department and the criteria that matter, and your ranked universities will appear here.',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.55)),
            const SizedBox(height: 24),
            primaryButton('Start matching', () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const DepartmentScreen()))),
          ]),
        ),
      ),
    );
  }
}

/// A2: Compare — always works; two slots default to UoK + AUCA, each with a Change button.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});
  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  List<dynamic> unis = [];
  Map<String, dynamic>? left, right;
  final Map<String, Map<String, dynamic>> _detailCache = {};
  final Map<String, Map<String, dynamic>> _staffCache = {};
  List<Map<String, dynamic>> _allCriteria = [];
  Map<String, String> _labelByCode = {};

  @override
  void initState() {
    super.initState();
    Api.criteria().then((list) {
      if (!mounted) return;
      setState(() {
        _allCriteria = list.map((c) => Map<String, dynamic>.from(c)).toList();
        _labelByCode = { for (final c in _allCriteria) c['code'] as String: c['label'] as String };
      });
    }).catchError((_) {});
    Api.universities().then((list) async {
      if (!mounted) return;
      unis = list;
      // defaults: UoK + AUCA
      left = _find('uni-uok') ?? (list.isNotEmpty ? list[0] as Map<String, dynamic> : null);
      right = _find('uni-auca') ?? (list.length > 1 ? list[1] as Map<String, dynamic> : null);
      setState(() {});
      if (left != null) await _loadDetail(left!['id']);
      if (right != null) await _loadDetail(right!['id']);
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  Map<String, dynamic>? _find(String id) {
    for (final u in unis) { if ((u as Map)['id'] == id) return Map<String, dynamic>.from(u); }
    return null;
  }

  Future<void> _loadDetail(String id) async {
    if (!_detailCache.containsKey(id)) {
      try { _detailCache[id] = await Api.university(id); } catch (_) {}
    }
    if (!_staffCache.containsKey(id)) {
      try {
        final d = await Api.universityAnswers(id);
        _staffCache[id] = Map<String, dynamic>.from((d['criteria'] as Map?) ?? {});
      } catch (_) {}
    }
  }

  Future<void> _change(bool isLeft) async {
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, backgroundColor: C.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListView(
        shrinkWrap: true, padding: const EdgeInsets.all(16),
        children: [
          const Padding(padding: EdgeInsets.only(bottom: 8),
              child: Text('Choose a university', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink))),
          ...unis.map((u) {
            final m = u as Map;
            return ListTile(
              leading: CircleAvatar(backgroundColor: C.uni('${m['abbr']}'),
                  child: Text('${m['abbr']}', style: const TextStyle(color: C.gold, fontSize: 10, fontWeight: FontWeight.w700))),
              title: Text('${m['name']}', style: const TextStyle(fontSize: 13)),
              onTap: () => Navigator.pop(ctx, Map<String, dynamic>.from(m)),
            );
          }),
        ],
      ),
    );
    if (chosen == null) return;
    await _loadDetail(chosen['id']);
    setState(() { if (isLeft) left = chosen; else right = chosen; });
  }

  @override
  Widget build(BuildContext context) {
    final ld = left != null ? _detailCache[left!['id']] : null;
    final rd = right != null ? _detailCache[right!['id']] : null;
    final lv = (ld != null ? ld['vals'] : null) as Map? ?? {};
    final rv = (rd != null ? rd['vals'] : null) as Map? ?? {};
    final ls = left != null ? (_staffCache[left!['id']] ?? const {}) : const {};
    final rs = right != null ? (_staffCache[right!['id']] ?? const {}) : const {};

    final categories = <String>[];
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final c in _allCriteria) {
      final cat = ((c['category'] as String?)?.trim().isNotEmpty ?? false) ? c['category'] as String : 'General';
      byCategory.putIfAbsent(cat, () { categories.add(cat); return []; }).add(c);
    }

    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'Compare', back: true),
      body: unis.isEmpty
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Expanded(child: _slot(left, true)),
                  const SizedBox(width: 10),
                  Expanded(child: _slot(right, false)),
                ]),
                const SizedBox(height: 16),
                if (_allCriteria.isEmpty)
                  const Padding(padding: EdgeInsets.all(24),
                      child: Text('Loading criteria…', textAlign: TextAlign.center, style: TextStyle(color: C.muted)))
                else
                  ...categories.asMap().entries.expand<Widget>((entry) {
                    final catColor = _kCategoryPalette[entry.key % _kCategoryPalette.length];
                    final items = byCategory[entry.value]!;
                    return [
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text(entry.value.toUpperCase(), style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: catColor)),
                      ),
                      ...items.map((c) {
                        final code = c['code'] as String;
                        final l = lv[code] ?? ls[code];
                        final r = rv[code] ?? rs[code];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_labelByCode[code] ?? code, style: const TextStyle(color: C.muted, fontSize: 11)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(child: Text(l != null ? _fmtAnswer(l) : '—',
                                  style: const TextStyle(color: C.green, fontWeight: FontWeight.w700, fontSize: 15))),
                              Expanded(child: Text(r != null ? _fmtAnswer(r) : '—', textAlign: TextAlign.right,
                                  style: const TextStyle(color: Color(0xFFC25A1F), fontWeight: FontWeight.w700, fontSize: 15))),
                            ]),
                          ]),
                        );
                      }),
                    ];
                  }),
              ],
            ),
    );
  }

  Widget _slot(Map<String, dynamic>? u, bool isLeft) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: u == null ? C.sand : C.uni('${u['abbr']}'), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${u?['abbr'] ?? '—'}', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${u?['name'] ?? 'Pick a university'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, height: 1.2)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _change(isLeft),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.swap_horiz, color: Colors.white, size: 15),
                SizedBox(width: 6),
                Text('Change', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      );
}

/// Prettify a raw staff answer key (e.g. "partnerSchools" → "Partner schools").
/// Detail hero stat + divider.
Widget _heroStat(String value, String label) => Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: GoogleFonts.bricolageGrotesque(
            color: const Color(0xFFFBF8F3), fontSize: 26, fontWeight: FontWeight.w500, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Color(0xFFF5C955), fontSize: 9, letterSpacing: 0.8)),
      ]),
    );
Widget _heroDiv() => Container(width: 1, height: 34, color: const Color(0x33F5E7B8), margin: const EdgeInsets.symmetric(horizontal: 12));

/// Prettify a raw staff answer key (e.g. "partnerSchools" → "Partner schools").
String _prettyKey(String k) {
  final spaced = k.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
  return spaced.isEmpty ? k : '${spaced[0].toUpperCase()}${spaced.substring(1)}'.trim();
}

/// Format any staff answer value for display (bool → Yes/No, list → joined, etc.).
String _fmtAnswer(dynamic v) {
  if (v is bool) return v ? 'Yes' : 'No';
  if (v is List) return v.isEmpty ? '—' : v.join(', ');
  if (v is Map) {
    if (v['period'] != null) return '${v['period']}: ${v['pct']}%';
    return v.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
  return '$v';
}

/// A2: My shortlist — bookmarked universities, with a way to remove them.
class ShortlistScreen extends StatefulWidget {
  const ShortlistScreen({super.key});
  @override
  State<ShortlistScreen> createState() => _ShortlistScreenState();
}

class _ShortlistScreenState extends State<ShortlistScreen> {
  List<dynamic> unis = [];
  bool loading = true;
  String? error;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final v = await Api.myShortlist();
      if (mounted) setState(() { unis = v; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  Future<void> _remove(String id) async {
    final prev = List<dynamic>.from(unis);
    setState(() => unis = unis.where((u) => (u as Map)['id'] != id).toList());
    try {
      await Api.removeShortlist(id);
    } catch (e) {
      if (mounted) { setState(() => unis = prev); toast(context, e.toString()); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'My shortlist', back: true),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                      const SizedBox(height: 16),
                      primaryButton('Retry', _load),
                    ]),
                  ),
                )
              : unis.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(18)),
                          child: const Icon(Icons.bookmark_border, color: C.green, size: 28),
                        ),
                        const SizedBox(height: 18),
                        Text('Nothing shortlisted yet', style: head(24), textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        const Text(
                            'Bookmark universities from their detail page, then come back to compare your saved list.',
                            textAlign: TextAlign.center, style: TextStyle(color: C.muted, height: 1.55)),
                        const SizedBox(height: 24),
                        primaryButton('Explore universities', () => Navigator.pushReplacement(context,
                            MaterialPageRoute(builder: (_) => const AllUniversitiesA2Screen()))),
                      ]),
                    )
                  : Builder(builder: (_) {
                      final query = _search.text.trim().toLowerCase();
                      final filtered = query.isEmpty
                          ? unis
                          : unis.where((u) => '${(u as Map)['name']}'.toLowerCase().contains(query)).toList();
                      return Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: searchField(_search, 'Search by name, abbreviation, campus or department'),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? _emptyView('No shortlisted universities match "${_search.text.trim()}".')
                              : ListView(
                                  padding: const EdgeInsets.all(20),
                                  children: filtered.map((u) {
                                    final m = u as Map;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                                      child: Row(children: [
                                        GestureDetector(
                                          onTap: () => Navigator.push(context, MaterialPageRoute(
                                              builder: (_) => DetailScreen(id: m['id'], name: m['name']))),
                                          child: Container(
                                            width: 44, height: 44,
                                            decoration: BoxDecoration(color: C.uni('${m['abbr']}'), borderRadius: BorderRadius.circular(12)),
                                            alignment: Alignment.center,
                                            child: Text(m['abbr'] ?? '', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 12)),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                                builder: (_) => DetailScreen(id: m['id'], name: m['name']))),
                                            child: Text(m['name'] ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => _remove(m['id']),
                                          icon: const Icon(Icons.bookmark_remove_outlined, color: C.muted),
                                          tooltip: 'Remove from shortlist',
                                        ),
                                      ]),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ]);
                    }),
    );
  }
}

class DepartmentScreen extends StatefulWidget {
  const DepartmentScreen({super.key});
  @override
  State<DepartmentScreen> createState() => _DepartmentScreenState();
}

class _DepartmentScreenState extends State<DepartmentScreen> {
  late Future<List<dynamic>> _future;
  final TextEditingController _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _future = Api.programmes(null);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'Choose department', back: true),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final progs = snap.data ?? [];
          // distinct departments + how many universities offer each
          final byDept = <String, Set<String>>{};
          for (final p in progs) {
            final m = p as Map;
            byDept.putIfAbsent('${m['dept']}', () => {}).add('${m['universityId']}');
          }
          final query = _search.text.trim().toLowerCase();
          final depts = byDept.keys.where((d) => query.isEmpty || d.toLowerCase().contains(query)).toList()..sort();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 2),
                child: Text('STEP 1 / 4 · DEPARTMENT',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: C.muted, letterSpacing: 0.5)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Which field\nare you into?', style: head(26)),
                  const SizedBox(height: 6),
                  const Text("We'll only show universities that offer this department next.",
                      style: TextStyle(color: C.muted, fontSize: 12.5)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: searchField(_search, 'Search departments…'),
              ),
              Expanded(
                child: GridView.count(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.2,
                  children: depts.map((d) => GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProgrammeScreen(dept: d))),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(11)),
                          child: Icon(iconForField(d), color: C.green, size: 19),
                        ),
                        const Spacer(),
                        Text(d, maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink, fontSize: 13, height: 1.2)),
                        const SizedBox(height: 3),
                        Text('${byDept[d]!.length} universit${byDept[d]!.length == 1 ? 'y' : 'ies'}',
                            style: const TextStyle(color: C.muted, fontSize: 10.5)),
                      ]),
                    ),
                  )).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProgrammeScreen extends StatefulWidget {
  final String dept;
  const ProgrammeScreen({super.key, required this.dept});
  @override
  State<ProgrammeScreen> createState() => _ProgrammeScreenState();
}

class _ProgrammeScreenState extends State<ProgrammeScreen> {
  late Future<List<dynamic>> _future;
  Map<String, String> uniNames = {};
  Map<String, Map> uniById = {};
  String? selectedProgramme;

  @override
  void initState() {
    super.initState();
    _future = Api.programmes(widget.dept);
    Api.universities().then((list) {
      if (mounted) {
        setState(() {
          uniNames = { for (final u in list) (u as Map)['id'] as String: (u['name'] ?? '').toString() };
          uniById = { for (final u in list) (u as Map)['id'] as String: u };
        });
      }
    }).catchError((_) {});
  }

  /// Real principal-pass combinations set by the university's own staff for
  /// this programme — no fabricated eligibility hints.
  Map<String, List<String>> _eligibilityByUni(String programmeName, List<Map> offerings) {
    final out = <String, List<String>>{};
    for (final o in offerings) {
      final uniId = '${o['universityId']}';
      final combos = (uniById[uniId]?['combos'] as Map?) ?? {};
      final subs = List<String>.from((combos[programmeName] as List?) ?? const []);
      if (subs.length >= 2) out[uniId] = subjectPairs(subs);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, widget.dept, back: true),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final progs = snap.data ?? [];
          // Group by programme name so every university offering it shows on one card.
          final byName = <String, List<Map>>{};
          final order = <String>[];
          for (final p in progs) {
            final m = p as Map;
            final name = '${m['name']}';
            byName.putIfAbsent(name, () { order.add(name); return []; }).add(m);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Text('STEP 2 / 4 · PROGRAMME',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: C.muted, letterSpacing: 0.5)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(iconForField(widget.dept), size: 15, color: C.green),
                    const SizedBox(width: 6),
                    Text(widget.dept, style: const TextStyle(color: C.greenDark, fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('What do you\nwant to study?', style: head(26)),
                  const SizedBox(height: 6),
                  const Text('See which universities in Gasabo offer each programme.',
                      style: TextStyle(color: C.muted, fontSize: 12.5)),
                ]),
              ),
              Expanded(
                child: order.isEmpty
                    ? _emptyView('No programmes offer ${widget.dept} in Gasabo yet.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        itemCount: order.length,
                        itemBuilder: (_, i) {
                          final name = order[i];
                          final offerings = byName[name]!;
                          final unis = offerings.map((p) => uniNames[p['universityId']] ?? '').where((s) => s.isNotEmpty).toSet().join(', ');
                          final sel = selectedProgramme == name;
                          final eligibility = sel ? _eligibilityByUni(name, offerings) : const <String, List<String>>{};
                          return GestureDetector(
                            onTap: () => setState(() => selectedProgramme = name),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: sel ? C.green : C.border, width: sel ? 1.6 : 1),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(11)),
                                    child: Icon(iconForField(name), color: C.green, size: 19),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink, fontSize: 14.5)),
                                    const SizedBox(height: 2),
                                    Text(unis.isNotEmpty ? 'Offered at: $unis' : 'Offered at: —',
                                        style: const TextStyle(color: C.muted, fontSize: 11.5)),
                                  ])),
                                  if (sel)
                                    Container(
                                      width: 24, height: 24,
                                      decoration: const BoxDecoration(color: C.green, shape: BoxShape.circle),
                                      child: const Icon(Icons.check, color: C.gold, size: 15),
                                    ),
                                ]),
                                if (sel && eligibility.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Text('Principal passes required (set by each university)',
                                      style: TextStyle(color: C.muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  ...eligibility.entries.map((e) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(uniNames[e.key] ?? '', style: const TextStyle(color: C.ink, fontSize: 11.5, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Wrap(spacing: 6, runSpacing: 6, children: e.value.map((pair) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                                                child: Text(pair, style: const TextStyle(fontSize: 10.5, color: C.greenDark, fontWeight: FontWeight.w600)),
                                              )).toList()),
                                        ]),
                                      )),
                                ],
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: selectedProgramme == null
                        ? null
                        : () {
                            Session.selectedProgramme = selectedProgramme;
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const CriteriaScreen()));
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.green, foregroundColor: Colors.white,
                      disabledBackgroundColor: C.sand, disabledForegroundColor: C.muted, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('Continue to criteria', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CriteriaScreen extends StatefulWidget {
  const CriteriaScreen({super.key});
  @override
  State<CriteriaScreen> createState() => _CriteriaScreenState();
}

// Accent palette cycled across whichever categories the admin catalogue has.
const List<Color> _kCategoryPalette = [
  Color(0xFFC25A1F), Color(0xFF1F5F4A), Color(0xFF2A5C8F), Color(0xFFB48412),
  Color(0xFF7A2F4A), Color(0xFF164638), Color(0xFF8F4B2A), Color(0xFF2F4A7A),
];

// The 8 fixed categories every criterion must belong to.
const List<String> kCriteriaCategories = [
  'Financial', 'Academic Quality', 'Location & Accessibility', 'Career & Employability',
  'Campus Life & Facilities', 'Institutional Reputation', 'Admission & Eligibility', 'Personal & Contextual',
];

class _CriteriaScreenState extends State<CriteriaScreen> {
  final Set<String> selected = {};
  // Categories collapsed by default; expand with the + button.
  final Set<String> expanded = {};
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> visible = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final all = await Api.criteria();
      final v = all.map((c) => Map<String, dynamic>.from(c)).toList();
      if (mounted) setState(() { visible = v; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final categories = <String>[];
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final c in visible) {
      if (query.isNotEmpty && !'${c['label']}'.toLowerCase().contains(query)) continue;
      final cat = ((c['category'] as String?)?.trim().isNotEmpty ?? false) ? c['category'] as String : 'General';
      byCategory.putIfAbsent(cat, () { categories.add(cat); return []; }).add(c);
    }

    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'What matters to you?', back: true),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Align(alignment: Alignment.centerLeft, child: Text('STEP 3 / 4 · CRITERIA',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: C.muted, letterSpacing: 0.5))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('What matters\nmost to you?', style: head(24))),
          ),
          // selected-count hero
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: const BoxDecoration(color: C.gold, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${selected.length}', style: GoogleFonts.bricolageGrotesque(
                    color: C.green, fontWeight: FontWeight.w600, fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SELECTED CRITERIA', style: TextStyle(
                    color: C.gold, fontSize: 10.5, letterSpacing: 0.6)),
                const SizedBox(height: 2),
                Text(selected.isEmpty
                    ? 'Pick what matters — each gets equal weight'
                    : 'Equal weight — ${(100 / selected.length).round()}% each',
                    style: const TextStyle(color: Color(0xFFFBF8F3), fontSize: 13)),
              ])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: searchField(_search, 'Search criteria…'),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: C.green))
                : error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                            const SizedBox(height: 16),
                            primaryButton('Retry', _load),
                          ]),
                        ),
                      )
                    : categories.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Container(
                                  width: 64, height: 64,
                                  decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(18)),
                                  child: const Icon(Icons.tune, color: C.green, size: 28),
                                ),
                                const SizedBox(height: 18),
                                Text(query.isNotEmpty ? 'No criteria match "${_search.text.trim()}"' : 'No criteria available yet',
                                    style: head(20), textAlign: TextAlign.center),
                                const SizedBox(height: 10),
                                Text(query.isNotEmpty
                                    ? 'Try a different search term.'
                                    : 'The admin hasn\'t defined any evaluation criteria yet — check back soon.',
                                    textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.55)),
                              ]),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                            children: categories.asMap().entries.expand<Widget>((entry) {
                              final catColor = _kCategoryPalette[entry.key % _kCategoryPalette.length];
                              final cat = entry.value;
                              final items = byCategory[cat]!;
                              final selCount = items.where((c) => selected.contains(c['code'])).length;
                              final isOpen = query.isNotEmpty || expanded.contains(cat);
                              return [
                                GestureDetector(
                                  onTap: () => setState(() => isOpen ? expanded.remove(cat) : expanded.add(cat)),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                                    child: Row(children: [
                                      Container(
                                        width: 22, height: 22,
                                        decoration: BoxDecoration(
                                            color: isOpen ? catColor : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: catColor, width: 1.5)),
                                        child: Icon(isOpen ? Icons.remove : Icons.add,
                                            size: 15, color: isOpen ? Colors.white : catColor),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(cat.toUpperCase(), style: TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: catColor))),
                                      Text('$selCount/${items.length}', style: const TextStyle(
                                          fontFamily: 'monospace', fontSize: 10, color: C.muted)),
                                    ]),
                                  ),
                                ),
                                if (isOpen) ...items.map((c) {
                                  final code = c['code'] as String;
                                  final sel = selected.contains(code);
                                  final row = GestureDetector(
                                    onTap: () => setState(() => sel ? selected.remove(code) : selected.add(code)),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(13),
                                      decoration: BoxDecoration(
                                        color: sel ? C.green : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: sel ? C.green : C.border),
                                      ),
                                      child: Row(children: [
                                        Container(
                                          width: 22, height: 22,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: sel ? C.gold : Colors.transparent,
                                            border: sel ? null : Border.all(color: C.muted, width: 1.5),
                                          ),
                                          child: sel ? const Icon(Icons.check, size: 14, color: C.green) : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text('${c['label']}', style: TextStyle(
                                            color: sel ? Colors.white : C.ink, fontWeight: FontWeight.w600, fontSize: 12.5))),
                                        Text(c['direction'] == 'cost' ? 'lower' : 'higher', style: TextStyle(
                                            color: sel ? const Color(0xFFCDE3DA) : C.muted, fontSize: 10, fontFamily: 'monospace')),
                                      ]),
                                    ),
                                  );
                                  if (code != 'C25' || !sel) return row;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      row,
                                      Container(
                                        margin: const EdgeInsets.only(top: -2, bottom: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: C.border),
                                        ),
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          const Text('WHICH RELIGION OR CULTURE DO YOU PREFER?', style: TextStyle(
                                              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: C.muted)),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            value: kReligions.contains(Session.preferredReligion) ? Session.preferredReligion : null,
                                            isExpanded: true,
                                            decoration: fieldDeco('Select religion or culture'),
                                            hint: const Text('Select religion or culture'),
                                            items: kReligions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                                            onChanged: (v) => setState(() => Session.preferredReligion = v),
                                          ),
                                        ]),
                                      ),
                                    ]),
                                  );
                                }),
                              ];
                            }).toList(),
                          ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
            child: Row(children: [
              OutlinedButton(
                onPressed: () => setState(() => selected.clear()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: C.ink, side: const BorderSide(color: C.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                child: const Text('Reset'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: selected.isEmpty ? null : () {
                      final criteria = selected.map((code) {
                        final c = visible.firstWhere((x) => x['code'] == code);
                        return {'code': code, 'weight': 1 / selected.length, 'direction': c['direction']};
                      }).toList();
                      Session.lastCriteria = criteria;
                      Navigator.push(context, MaterialPageRoute(builder: (_) => LocationScreen(criteria: criteria)));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.green, foregroundColor: Colors.white,
                      disabledBackgroundColor: C.sand, disabledForegroundColor: C.muted, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    child: Text('Continue · ${selected.length} selected',
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// STEP 4 — home location (drives the distance criterion via Google Maps).
class LocationScreen extends StatefulWidget {
  final List<Map<String, dynamic>> criteria;
  const LocationScreen({super.key, required this.criteria});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final addr = TextEditingController();
  String? picked;
  static const _suggestions = [
    ['Kacyiru', 'Gasabo, Kigali'], ['Kimironko', 'Gasabo, Kigali'],
    ['Remera', 'Gasabo, Kigali'], ['Kinyinya', 'Gasabo, Kigali'],
    ['Ndera', 'Gasabo, Kigali'], ['Bumbogo', 'Gasabo, Kigali'],
  ];

  @override
  Widget build(BuildContext context) {
    final results = addr.text.trim().isEmpty
        ? const <List<String>>[]
        : _suggestions.where((s) => s[0].toLowerCase().contains(addr.text.trim().toLowerCase())).toList();
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'Where do you live?', back: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Text('STEP 4 / 4 · LOCATION',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: C.muted, letterSpacing: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Where do you\nlive?', style: head(24)),
              const SizedBox(height: 4),
              const Text('Real driving distance via Google Maps.', style: TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: addr,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search sector or address…',
                prefixIcon: const Icon(Icons.search, color: C.muted),
                filled: true, fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.green)),
              ),
            ),
          ),
          if (results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                child: Column(children: results.map((s) => ListTile(
                  leading: Container(
                    width: 30, height: 30,
                    decoration: const BoxDecoration(color: Color(0xFFC7EBD8), shape: BoxShape.circle),
                    child: const Icon(Icons.place, color: C.green, size: 16),
                  ),
                  title: Text(s[0], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(s[1], style: const TextStyle(fontSize: 11)),
                  onTap: () => setState(() { picked = '${s[0]}, ${s[1]}'; addr.text = s[0]; }),
                )).toList()),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3EC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: C.border),
                ),
                child: Stack(children: [
                  const Center(child: Icon(Icons.map_outlined, color: Color(0x331F5F4A), size: 90)),
                  if (picked != null)
                    Positioned(
                      left: 12, right: 12, bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                        child: Row(children: [
                          Container(
                            width: 30, height: 30,
                            decoration: const BoxDecoration(color: Color(0xFFC25A1F), shape: BoxShape.circle),
                            child: const Icon(Icons.home, color: Colors.white, size: 15),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(picked!, style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink, fontSize: 12)),
                            const Text('Distances computed to all universities', style: TextStyle(color: C.muted, fontSize: 10.5)),
                          ])),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Session.homeArea = (picked ?? addr.text).trim();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ResultsScreen(criteria: widget.criteria)));
                },
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Show rank', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.green, foregroundColor: Colors.white, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ResultsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> criteria;
  const ResultsScreen({super.key, required this.criteria});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

String _fmtRwf(num v) => v >= 1000000
    ? '${(v / 1000000).toStringAsFixed(1)}M RWF'
    : '${(v / 1000).round()}k RWF';

class _ResultsScreenState extends State<ResultsScreen> {
  late Future<List<dynamic>> _future;
  Map<String, dynamic> staffAnswersById = {};

  @override
  void initState() {
    super.initState();
    final wantsReligion = widget.criteria.any((c) => c['code'] == 'C25') &&
        Session.preferredReligion != null && Session.preferredReligion != 'No preference';
    _future = Api.rank(widget.criteria,
        preferredReligion: wantsReligion ? Session.preferredReligion : null).then((r) async {
      Session.lastRanking = r;
      final entries = await Future.wait(r.map((u) async {
        final id = (u as Map)['id'] as String;
        try {
          final d = await Api.universityAnswers(id);
          return MapEntry(id, Map<String, dynamic>.from((d['criteria'] as Map?) ?? {}));
        } catch (_) {
          return MapEntry(id, <String, dynamic>{});
        }
      }));
      if (mounted) setState(() => staffAnswersById = Map.fromEntries(entries));
      return r;
    });
  }

  Widget _chip(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: C.muted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 10, color: C.muted, fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, 'Your matches', back: true),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          // Only the top 5 highest-scoring universities are shown.
          final ranked = (snap.data ?? []).take(5).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_outlined, size: 13, color: C.green),
                    SizedBox(width: 3),
                    Text('Edit', style: TextStyle(color: C.green, fontWeight: FontWeight.w600, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ranked.isEmpty
                  ? _emptyView('No universities to rank yet.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      itemCount: ranked.length,
                      itemBuilder: (_, i) {
                        final u = ranked[i] as Map;
                        final cc = ((u['cc'] ?? 0) as num).toDouble();
                        final pct = (cc * 100).clamp(0, 100).toStringAsFixed(0);
                        final top1 = i == 0;
                        final abbr = '${u['abbr'] ?? ''}';
                        final crest = C.uni(abbr);
                        final vals = (u['vals'] as Map?) ?? {};
                        final staffAns = staffAnswersById[u['id']] as Map? ?? {};
                        final fee = vals['C01'];
                        final scholarship = vals['C02'];
                        final accommodation = staffAns['accommodation'];
                        final badge = i == 0 ? 'TOP MATCH' : i == 1 ? '2ND' : i == 2 ? '3RD' : null;
                        return GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => DetailScreen(id: u['id'], name: u['name']))),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: top1 ? C.green : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: top1 ? C.green : C.border),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (badge != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 13, top: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(999)),
                                    child: Text(badge, style: const TextStyle(
                                        color: C.greenDark, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
                                child: Row(children: [
                                  Container(
                                    width: 42, height: 42,
                                    decoration: BoxDecoration(color: crest, borderRadius: BorderRadius.circular(12)),
                                    alignment: Alignment.center,
                                    child: Text(abbr, style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 11)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${u['name'] ?? ''}', style: TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 14.5, height: 1.2,
                                        color: top1 ? Colors.white : C.ink)),
                                    const SizedBox(height: 2),
                                    Text('Rank #${i + 1} of ${ranked.length}', style: TextStyle(
                                        fontSize: 11, color: top1 ? const Color(0xFFCDE3DA) : C.muted)),
                                  ])),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text('$pct', style: GoogleFonts.bricolageGrotesque(
                                        fontWeight: FontWeight.w600, fontSize: 22, height: 1,
                                        color: top1 ? C.gold : C.green)),
                                    Text('CC', style: TextStyle(fontFamily: 'monospace', fontSize: 9.5,
                                        color: top1 ? const Color(0xFFCDE3DA) : C.muted)),
                                  ]),
                                ]),
                              ),
                              if (fee != null || scholarship != null || accommodation != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 8),
                                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                                    if (fee != null) _chip(_fmtRwf(fee as num), Icons.payments_outlined),
                                    if (scholarship != null) _chip('Scholarship ${scholarship is num ? scholarship.toStringAsFixed(1) : scholarship}/5', Icons.school_outlined),
                                    if (accommodation != null) _chip(accommodation == true ? 'On-campus' : 'Off-campus', Icons.home_outlined),
                                  ]),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: cc.clamp(0, 1).toDouble(), minHeight: 6,
                                    backgroundColor: top1 ? const Color(0x33FFFFFF) : C.sand,
                                    valueColor: AlwaysStoppedAnimation(top1 ? C.gold : crest),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
            if (ranked.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.border))),
                child: Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompareScreen())),
                    icon: const Icon(Icons.view_column_outlined, size: 16, color: C.ink),
                    label: const Text('Compare', style: TextStyle(color: C.ink)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: C.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () async {
                      final top = ranked.first as Map;
                      try {
                        await Api.shortlist(top['id']);
                        if (mounted) toast(context, 'Added ${top['name']} to shortlist');
                      } catch (e) {
                        if (mounted) toast(context, e.toString());
                      }
                    },
                    icon: const Icon(Icons.bookmark_border, size: 16, color: C.ink),
                    label: const Text('Shortlist', style: TextStyle(color: C.ink)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: C.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class DetailScreen extends StatefulWidget {
  final String id;
  final String name;
  const DetailScreen({super.key, required this.id, required this.name});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Future<Map<String, dynamic>> _future;
  int myRating = 0;
  Map<String, dynamic> staffAnswers = {};
  Map<String, dynamic> combos = {};
  Map<String, String> labelByCode = {};
  List<Map<String, dynamic>> allCriteria = [];

  @override
  void initState() {
    super.initState();
    _future = Api.university(widget.id);
    Api.universityAnswers(widget.id).then((d) {
      if (mounted) {
        setState(() {
          staffAnswers = Map<String, dynamic>.from((d['criteria'] as Map?) ?? {});
          combos = Map<String, dynamic>.from((d['combos'] as Map?) ?? {});
        });
      }
    }).catchError((_) {});
    Api.criteria().then((list) {
      if (mounted) setState(() {
        allCriteria = list.map((c) => Map<String, dynamic>.from(c)).toList();
        labelByCode = { for (final c in allCriteria) c['code'] as String: c['label'] as String };
      });
    }).catchError((_) {});
  }

  Widget _infoCard(String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: C.green),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: C.ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
          ]),
        ),
      );

  Widget? _scholarshipCard() {
    final subs = [
      MapEntry('Completion', staffAnswers['completion']),
      MapEntry('Intake', staffAnswers['intake']),
      MapEntry('Grade', staffAnswers['grade']),
      MapEntry('Coverage', staffAnswers['coverage']),
    ].where((e) => e.value is num).toList();
    if (subs.isEmpty) return null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.school_outlined, size: 18, color: C.green),
          SizedBox(width: 8),
          Text('Scholarship composite', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
        ]),
        const SizedBox(height: 12),
        ...subs.map((e) {
          final v = (e.value as num).toDouble().clamp(0, 100);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(e.key, style: const TextStyle(color: C.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                Text('${v.toStringAsFixed(0)}%', style: const TextStyle(color: C.muted, fontSize: 11)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: v / 100, minHeight: 6, backgroundColor: C.sand,
                    valueColor: const AlwaysStoppedAnimation(C.green)),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget? _eligibilityBox() {
    final prog = Session.selectedProgramme;
    if (prog == null) return null;
    final subs = List<String>.from((combos[prog] as List?) ?? const []);
    if (subs.length < 2) return null;
    final pairs = subjectPairs(subs);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Principal passes required for $prog', style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 12.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: pairs.map((p) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
              child: Text(p, style: const TextStyle(fontSize: 10.5, color: C.greenDark, fontWeight: FontWeight.w600)),
            )).toList()),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: a2Drawer(context),
      appBar: a2AppBar(context, widget.name, back: true),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final u = snap.data ?? {};
          final campuses = (u['campuses'] as List?) ?? [];
          final vals = (u['vals'] as Map?) ?? {};
          final abbr = '${u['abbr'] ?? ''}';
          final crest = C.uni(abbr);
          final avgRating = u['avgRating'] as num?;
          final ratingCount = (u['ratingCount'] as num?)?.toInt() ?? 0;
          final cc = Session.lastRanking == null ? null
              : () {
                  for (final r in Session.lastRanking!) { if ((r as Map)['id'] == u['id']) return ((r['cc'] ?? 0) as num).toDouble(); }
                  return null;
                }();
          final rank = Session.lastRanking == null ? null
              : () {
                  for (var i = 0; i < Session.lastRanking!.length; i++) {
                    if ((Session.lastRanking![i] as Map)['id'] == u['id']) return i + 1;
                  }
                  return null;
                }();
          final kmHome = vals['C07'];

          // Full 26-criteria catalogue, grouped by category, value from vals
          // or staff answers if present, otherwise blank — never fabricated.
          final codeSet = allCriteria.map((c) => c['code']).toSet();
          final categories = <String>[];
          final byCategory = <String, List<Map<String, dynamic>>>{};
          for (final c in allCriteria) {
            final cat = ((c['category'] as String?)?.trim().isNotEmpty ?? false) ? c['category'] as String : 'General';
            byCategory.putIfAbsent(cat, () { categories.add(cat); return []; }).add(c);
          }

          // Contextual staff answers that aren't one of the 26 criterion codes
          // (partner schools, bus stops, cohorts, etc.) — shown separately.
          final contextualRows = <MapEntry<String, dynamic>>[];
          final seen = <String>{};
          staffAnswers.forEach((k, v) {
            if (codeSet.contains(k)) return;
            if (v == null || (v is String && v.isEmpty)) return;
            if (v is List && v.isEmpty) return;
            if (!seen.add(k)) return;
            contextualRows.add(MapEntry(labelByCode[k] ?? _prettyKey(k), v));
          });

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [crest, Color.lerp(crest, Colors.black, 0.35)!]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: const Color(0xFFF5E7B8), borderRadius: BorderRadius.circular(13)),
                      alignment: Alignment.center,
                      child: Text(abbr, style: TextStyle(color: crest, fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${u['name'] ?? widget.name}', style: GoogleFonts.bricolageGrotesque(
                        color: const Color(0xFFFBF8F3), fontSize: 20, fontWeight: FontWeight.w500, height: 1.15))),
                  ]),
                  const SizedBox(height: 18),
                  Row(children: [
                    _heroStat(cc != null ? (cc * 100).toStringAsFixed(0) : '—', 'CC SCORE'),
                    _heroDiv(),
                    _heroStat(rank != null ? '#$rank' : '—', 'YOUR RANK'),
                    _heroDiv(),
                    _heroStat(kmHome != null ? '${kmHome is num ? kmHome.toStringAsFixed(1) : kmHome}' : '—', 'KM HOME'),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (staffAnswers['feeMin'] != null || staffAnswers['feeMax'] != null || staffAnswers['accommodation'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (staffAnswers['feeMin'] != null && staffAnswers['feeMax'] != null)
                      _infoCard('TUITION RANGE',
                          '${_fmtRwf((staffAnswers['feeMin'] as num))} – ${_fmtRwf((staffAnswers['feeMax'] as num))}',
                          Icons.payments_outlined),
                    if (staffAnswers['feeMin'] != null && staffAnswers['feeMax'] != null && staffAnswers['accommodation'] != null)
                      const SizedBox(width: 10),
                    if (staffAnswers['accommodation'] != null)
                      _infoCard('ACCOMMODATION', staffAnswers['accommodation'] == true ? 'On-campus' : 'Off-campus',
                          Icons.home_outlined),
                  ]),
                ),
              if (_scholarshipCard() != null) _scholarshipCard()!,
              const Text('Campuses in Gasabo', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
              const SizedBox(height: 10),
              if (campuses.isEmpty)
                const Text('No campuses published yet.', style: TextStyle(color: C.muted, fontSize: 12))
              else
                ...campuses.map((c) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                      child: Row(children: [
                        const Icon(Icons.location_on_outlined, color: C.green, size: 20),
                        const SizedBox(width: 10),
                        Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                      ]),
                    )),
              const SizedBox(height: 12),
              if (_eligibilityBox() != null) _eligibilityBox()!,
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('All criteria', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                Text('${allCriteria.length} total', style: const TextStyle(color: C.muted, fontSize: 11)),
              ]),
              const SizedBox(height: 10),
              if (allCriteria.isEmpty)
                const Text('Loading criteria…', style: TextStyle(color: C.muted, fontSize: 12))
              else
                ...categories.asMap().entries.expand<Widget>((entry) {
                  final catColor = _kCategoryPalette[entry.key % _kCategoryPalette.length];
                  final items = byCategory[entry.value]!;
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(entry.value.toUpperCase(), style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: catColor)),
                    ),
                    ...items.map((c) {
                      final code = c['code'] as String;
                      final value = vals[code] ?? staffAnswers[code];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Text('${c['label']}',
                                style: const TextStyle(color: C.ink, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(value != null ? _fmtAnswer(value) : '—', textAlign: TextAlign.right,
                                style: TextStyle(color: value != null ? C.green : C.muted, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      );
                    }),
                  ];
                }),
              if (contextualRows.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Additional details', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                const SizedBox(height: 10),
                ...contextualRows.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text(e.key,
                              style: const TextStyle(color: C.ink, fontWeight: FontWeight.w600, fontSize: 13)),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(_fmtAnswer(e.value), textAlign: TextAlign.right,
                              style: const TextStyle(color: C.green, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    )),
              ],
              const SizedBox(height: 20),
              Row(children: [
                const Text('Rate this university', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                const SizedBox(width: 8),
                Text(
                  ratingCount > 0 ? '${avgRating?.toStringAsFixed(1)} ★ ($ratingCount rating${ratingCount == 1 ? '' : 's'})' : 'No ratings yet',
                  style: const TextStyle(color: C.muted, fontSize: 11.5),
                ),
              ]),
              const SizedBox(height: 8),
              Row(
                children: List.generate(5, (i) {
                  return IconButton(
                    onPressed: () async {
                      setState(() => myRating = i + 1);
                      try {
                        await Api.rate(widget.id, i + 1);
                        if (mounted) toast(context, 'Thanks for rating!');
                      } catch (e) {
                        if (mounted) toast(context, e.toString());
                      }
                    },
                    icon: Icon(i < myRating ? Icons.star : Icons.star_border, color: C.gold, size: 30),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: primaryButton('Apply', () async {
                    try {
                      String programmeId = '';
                      if (Session.selectedProgramme != null) {
                        final progs = await Api.programmes(null);
                        final match = progs.cast<Map>().firstWhere(
                            (p) => p['universityId'] == widget.id && p['name'] == Session.selectedProgramme,
                            orElse: () => {});
                        programmeId = '${match['id'] ?? ''}';
                      }
                      await Api.apply(widget.id, programmeId, Session.homeArea);
                      if (mounted) toast(context, 'Application submitted!');
                      final url = kApplyUrls[widget.id];
                      if (url != null) {
                        await launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      if (mounted) toast(context, e.toString());
                    }
                  }),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () async {
                      try {
                        await Api.shortlist(widget.id);
                        if (mounted) toast(context, 'Added to shortlist');
                      } catch (e) {
                        if (mounted) toast(context, e.toString());
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: C.green,
                      side: const BorderSide(color: C.green),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Icon(Icons.bookmark_border),
                  ),
                ),
              ]),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ===========================================================================
/// STAFF (university admission staff)
/// ===========================================================================
String get _staffUni => Session.uniId ?? 'uni-uok'; // demo fallback if not set

Drawer staffDrawer(BuildContext context) => Drawer(
      backgroundColor: C.cream,
      child: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20), color: C.green,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 22, backgroundColor: C.gold,
                  child: Text(Session.initial, style: const TextStyle(color: C.greenDark, fontWeight: FontWeight.w700))),
              const SizedBox(height: 10),
              Text(Session.name.isEmpty ? 'University staff' : Session.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Text(Session.email, style: const TextStyle(color: Color(0xFFCDE3DA), fontSize: 12)),
            ]),
          ),
          _drawerItem(context, Icons.dashboard_outlined, 'Dashboard', const StaffDashboard(), replace: true),
          _drawerItem(context, Icons.apartment, 'Campuses & programmes', const StaffCampusesScreen()),
          _drawerItem(context, Icons.rule, 'Eligibility combinations', const StaffCombosScreen()),
          _drawerItem(context, Icons.fact_check_outlined, 'Criteria answers', const StaffCriteriaScreen()),
          _drawerItem(context, Icons.bar_chart, 'Reports', const StaffReportsScreen()),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFC25A1F)),
            title: const Text('Log out', style: TextStyle(color: Color(0xFFC25A1F))),
            onTap: () => _logout(context),
          ),
        ]),
      ),
    );

AppBar staffAppBar(BuildContext context, String title, {bool back = false}) => AppBar(
      backgroundColor: C.cream, elevation: 0, foregroundColor: C.ink,
      leading: back
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context))
          : null,
      title: Text(title),
      actions: [
        if (back)
          Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer())),
        profileAction(context),
      ],
    );

/// ---- A2 graduate chrome: drawer + app bar (profile, nav, logout) ----------
Drawer a2Drawer(BuildContext context) => Drawer(
      backgroundColor: C.cream,
      child: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20), color: C.green,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 22, backgroundColor: C.gold,
                  child: Text(Session.initial, style: const TextStyle(color: C.greenDark, fontWeight: FontWeight.w700))),
              const SizedBox(height: 10),
              Text(Session.name.isEmpty ? 'A2 graduate' : Session.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Text(Session.email, style: const TextStyle(color: Color(0xFFCDE3DA), fontSize: 12)),
            ]),
          ),
          _drawerItem(context, Icons.home_outlined, 'Home', const StudentHome(), replace: true),
          _drawerItem(context, Icons.tune, 'Start matching', const DepartmentScreen()),
          _drawerItem(context, Icons.apartment, 'All universities', const AllUniversitiesA2Screen()),
          _drawerItem(context, Icons.bar_chart, 'My rankings', const RankingsEntryScreen()),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFC25A1F)),
            title: const Text('Log out', style: TextStyle(color: Color(0xFFC25A1F))),
            onTap: () => _logout(context),
          ),
        ]),
      ),
    );

AppBar a2AppBar(BuildContext context, String title, {bool back = false}) => AppBar(
      backgroundColor: C.cream, elevation: 0, foregroundColor: C.ink,
      leading: back
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context))
          : null,
      title: Text(title),
      actions: [
        if (back)
          Builder(builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer())),
        profileAction(context),
      ],
    );

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});
  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  String uniName = '';
  int campusCount = 0;
  int programmeCount = 0;

  @override
  void initState() {
    super.initState();
    final uniId = Session.uniId;
    if (uniId != null) {
      Api.university(uniId).then((u) {
        if (mounted) setState(() => uniName = '${u['name'] ?? ''}');
      }).catchError((_) {});
      Api.staffData(uniId).then((d) {
        if (mounted) setState(() => campusCount = ((d['campuses'] as List?) ?? const []).length);
      }).catchError((_) {});
      Api.programmes(null).then((list) {
        final n = list.where((p) => (p as Map)['universityId'] == uniId).length;
        if (mounted) setState(() => programmeCount = n);
      }).catchError((_) {});
    }
  }

  Widget _stat(String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: GoogleFonts.bricolageGrotesque(fontWeight: FontWeight.w600, fontSize: 22, color: C.green)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: C.muted, fontSize: 11)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: staffDrawer(context),
      appBar: staffAppBar(context, 'Staff dashboard'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                  child: const Text('STAFF PORTAL', style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: C.greenDark)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(uniName.isEmpty ? 'Welcome ${Session.first.isEmpty ? 'staff' : Session.first}' : uniName, style: head(24)),
              const SizedBox(height: 4),
              const Text('Manage your university\'s data.', style: TextStyle(color: C.muted)),
              const SizedBox(height: 16),
              Row(children: [
                _stat('$campusCount', 'Gasabo campuses'),
                const SizedBox(width: 10),
                _stat('$programmeCount', 'Programmes listed'),
              ]),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [C.green, Color(0xFF164638)]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YOUR INSTITUTION', style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: C.gold)),
                  const SizedBox(height: 8),
                  Text('Keep your profile up to date',
                      style: head(22, color: const Color(0xFFFBF8F3))),
                  const SizedBox(height: 6),
                  const Text('Complete campuses, eligibility combinations and criteria so students can find and rank you.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFFCDE3DA), height: 1.5)),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              children: [
                Text('Manage', style: head(17, weight: FontWeight.w500)),
                const SizedBox(height: 8),
                _card(context, 'Campuses & programmes', 'Add a campus, assign departments',
                    Icons.apartment, const StaffCampusesScreen()),
                _card(context, 'Eligible combinations', 'Principal-pass combos per programme',
                    Icons.rule, const StaffCombosScreen()),
                _card(context, 'Criteria answers', 'Fill in your 26 data points',
                    Icons.fact_check_outlined, const StaffCriteriaScreen()),
                _card(context, 'Reports', 'Reach, applicants & locations · CSV',
                    Icons.bar_chart, const StaffReportsScreen()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext ctx, String t, String s, IconData i, Widget dest) => GestureDetector(
        onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => dest)),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
          child: Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(12)),
                child: Icon(i, color: C.green, size: 20)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
              const SizedBox(height: 2),
              Text(s, style: const TextStyle(color: C.muted, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_right, color: C.muted),
          ]),
        ),
      );
}

/// ---- Staff: campuses & the departments each offers ------------------------
class StaffCampusesScreen extends StatefulWidget {
  const StaffCampusesScreen({super.key});
  @override
  State<StaffCampusesScreen> createState() => _StaffCampusesScreenState();
}

class _StaffCampusesScreenState extends State<StaffCampusesScreen> {
  List<Map<String, dynamic>> campuses = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.staffData(_staffUni);
      final list = (data['campuses'] as List?) ?? [];
      campuses = list.map<Map<String, dynamic>>((c) =>
          {'name': c['name'] ?? '', 'depts': List<String>.from(c['depts'] ?? [])}).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    try { await Api.saveStaffCampuses(_staffUni, campuses); if (mounted) toast(context, 'Saved'); }
    catch (e) { if (mounted) toast(context, e.toString()); }
  }

  Future<void> _editCampus({int? index}) async {
    final existing = index != null ? campuses[index] : null;
    final name = TextEditingController(text: existing?['name'] ?? '');
    final picked = Set<String>.from(existing?['depts'] ?? const <String>[]);
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: C.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(existing == null ? 'Add campus' : 'Edit campus',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
          const SizedBox(height: 16),
          TextField(controller: name, decoration: fieldDeco('Campus name (e.g. Remera Campus)')),
          const SizedBox(height: 14),
          const Text('Departments offered here', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: kDepartments.map((d) {
            final on = picked.contains(d);
            return GestureDetector(
              onTap: () => setSheet(() => on ? picked.remove(d) : picked.add(d)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: on ? C.green : Colors.white, borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: on ? C.green : C.border)),
                child: Text(d, style: TextStyle(color: on ? Colors.white : C.ink, fontSize: 12)),
              ),
            );
          }).toList()),
          const SizedBox(height: 20),
          primaryButton('Save campus', () => Navigator.pop(ctx, true)),
        ]),
      )),
    );
    if (saved != true) return;
    setState(() {
      final row = {'name': name.text.trim(), 'depts': picked.toList()};
      if (index != null) campuses[index] = row; else campuses.add(row);
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: staffDrawer(context),
      appBar: staffAppBar(context, 'Campuses', back: true),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Add the campuses your university runs in Gasabo, and the departments each one offers.',
                    style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 14),
                // dashed add button (matches prototype)
                GestureDetector(
                  onTap: () => _editCampus(),
                  child: DottedBorder(
                    child: Container(
                      height: 54, alignment: Alignment.center,
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.add, color: C.green, size: 18),
                        SizedBox(width: 8),
                        Text('Add a Gasabo campus',
                            style: TextStyle(color: C.green, fontWeight: FontWeight.w600, fontSize: 14)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (campuses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No campuses yet — tap the button above to add your first one.',
                        textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
                  )
                else
                  ...List.generate(campuses.length, (i) {
                    final c = campuses[i];
                    final depts = List<String>.from(c['depts'] ?? const []);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.location_on_outlined, color: C.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(c['name'],
                              style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 15))),
                          IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                              icon: const Icon(Icons.edit_outlined, color: C.green, size: 19),
                              onPressed: () => _editCampus(index: i)),
                          const SizedBox(width: 14),
                          IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                              icon: const Icon(Icons.delete_outline, color: Color(0xFFC25A1F), size: 19),
                              onPressed: () { setState(() => campuses.removeAt(i)); _save(); }),
                        ]),
                        const SizedBox(height: 10),
                        Text('${depts.length} department${depts.length == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 0.4)),
                        const SizedBox(height: 6),
                        if (depts.isEmpty)
                          const Text('No departments assigned yet', style: TextStyle(color: C.muted, fontSize: 12))
                        else
                          Wrap(spacing: 6, runSpacing: 6, children: depts.map((d) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                            child: Text(d, style: const TextStyle(color: C.greenDark, fontSize: 11.5, fontWeight: FontWeight.w600)),
                          )).toList()),
                      ]),
                    );
                  }),
              ],
            ),
    );
  }
}

/// Dashed rounded border container (used for the "Add a Gasabo campus" button).
class DottedBorder extends StatelessWidget {
  final Widget child;
  const DottedBorder({super.key, required this.child});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashPainter(),
        child: child,
      );
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBEB8A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(14));
    final path = Path()..addRRect(rrect);
    // draw dashes
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ---- Staff: eligibility combinations per programme ------------------------
const List<String> kSubjectPool = [
  'Physics', 'Maths', 'Chemistry', 'Biology', 'Programming', 'Operating Systems',
  'Networking', 'System Design', 'Economics', 'Geography', 'History', 'Accounting',
];

class StaffCombosScreen extends StatefulWidget {
  const StaffCombosScreen({super.key});
  @override
  State<StaffCombosScreen> createState() => _StaffCombosScreenState();
}

class _StaffCombosScreenState extends State<StaffCombosScreen> {
  Map<String, List<String>> combos = {}; // programme name -> eligible subjects
  List<String> programmes = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.staffData(_staffUni);
      final camps = (data['campuses'] as List?) ?? [];
      programmes = camps.expand((c) => List<String>.from(c['depts'] ?? [])).toSet().toList();
      final saved = (data['combos'] as Map?) ?? {};
      combos = { for (final p in programmes) p: List<String>.from(saved[p] ?? const []) };
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    try { await Api.saveStaffCombos(_staffUni, combos); if (mounted) toast(context, 'Saved'); }
    catch (e) { if (mounted) toast(context, e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: staffDrawer(context),
      appBar: staffAppBar(context, 'Combinations', back: true),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : programmes.isEmpty
              ? _emptyView('Add campuses with departments first — their programmes appear here.')
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('A student is eligible if they passed any 2 of the highlighted subjects. Every valid pair is listed.',
                        style: TextStyle(color: C.muted, fontSize: 12)),
                    const SizedBox(height: 14),
                    ...programmes.map((p) {
                      final subs = combos[p] ?? [];
                      final pairs = subjectPairs(subs);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: kSubjectPool.map((s) {
                            final on = subs.contains(s);
                            return GestureDetector(
                              onTap: () {
                                setState(() { on ? subs.remove(s) : subs.add(s); combos[p] = subs; });
                                _save();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: on ? C.green : Colors.white, borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: on ? C.green : C.border)),
                                child: Text(s, style: TextStyle(color: on ? Colors.white : C.ink, fontSize: 11)),
                              ),
                            );
                          }).toList()),
                          if (pairs.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text('Possible combinations (${pairs.length})',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.muted)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 6, children: pairs.map((c) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFF5E7B8), borderRadius: BorderRadius.circular(999)),
                              child: Text(c, style: const TextStyle(color: Color(0xFF8A6A10), fontSize: 10, fontWeight: FontWeight.w600)),
                            )).toList()),
                          ],
                        ]),
                      );
                    }),
                  ],
                ),
    );
  }
}

/// ---- Staff: criteria answers (full form, mirrors the prototype) -----------
const List<String> kReligions = [
  'No preference', 'Catholic', 'Protestant/Anglican', 'Seventh-day Adventist',
  'Pentecostal/Evangelical', 'Islam', 'Interfaith/Non-denominational', 'Cultural/Traditional',
];

class StaffCriteriaScreen extends StatefulWidget {
  const StaffCriteriaScreen({super.key});
  @override
  State<StaffCriteriaScreen> createState() => _StaffCriteriaScreenState();
}

// Codes already covered by a dedicated field/section below (numeric or not) —
// anything admin-defined outside this set falls through to "Other criteria".
const Set<String> _coveredCriteriaCodes = {
  'C01', 'C02', 'C05', 'C07', 'C08', 'C09', 'C11', 'C12', 'C13', 'C14',
  'C15', 'C16', 'C17', 'C18', 'C19', 'C20', 'C22', 'C23', 'C25', 'C26',
};

class _StaffCriteriaScreenState extends State<StaffCriteriaScreen> {
  Map<String, dynamic> d = {};
  List<Map<String, dynamic>> otherCriteria = [];
  bool loading = true;
  final _cohortPeriodCtl = TextEditingController();
  final _cohortPctCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.staffData(_staffUni);
      d = Map<String, dynamic>.from((data['criteria'] as Map?) ?? {});
    } catch (_) {}
    try {
      final all = await Api.criteria();
      otherCriteria = all.map((c) => Map<String, dynamic>.from(c))
          .where((c) => !_coveredCriteriaCodes.contains(c['code'])).toList();
    } catch (_) {}
    _norm();
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    _cohortPeriodCtl.dispose();
    _cohortPctCtl.dispose();
    super.dispose();
  }

  // ensure list/typed fields exist
  void _norm() {
    d['partnerSchools'] = List<String>.from(d['partnerSchools'] ?? const []);
    d['companies'] = List<String>.from(d['companies'] ?? const []);
    d['busStops'] = List<String>.from(d['busStops'] ?? const []);
    d['motoStops'] = List<String>.from(d['motoStops'] ?? const []);
    d['healthPartners'] = List<String>.from(d['healthPartners'] ?? const []);
    d['cohorts'] = List<Map<String, dynamic>>.from(
        (d['cohorts'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? const []);
  }

  Future<void> _save() async {
    try {
      await Api.saveStaffCriteria(_staffUni, d);
      if (!mounted) return;
      toast(context, 'Criteria saved');
      Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (_) => const StaffDashboard()), (r) => false);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  num? _n(String k) => d[k] is num ? d[k] as num : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: staffDrawer(context),
      appBar: staffAppBar(context, 'Criteria answers', back: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save, backgroundColor: C.green,
        icon: const Icon(Icons.save, color: Colors.white),
        label: const Text('Save', style: TextStyle(color: Colors.white)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
              children: [
                const Text('These answers are what A2 graduates see on your university detail page, and what TOPSIS ranks on. Numeric fields feed the score.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(height: 16),

                _section('C01 · Tuition & fees'),
                _feeRangeField(),

                _section('C02 · Scholarships & partner schools'),
                _scholarshipFields(),
                _chipEditor('Partner schools (more = higher score)', 'partnerSchools', 'Add a partner school'),

                _section('C08 · On-campus accommodation'),
                _yesNo('Available?', 'accommodation'),

                _section('C09 · Transport proximity'),
                const Text('Mark your locations on the map.',
                    style: TextStyle(color: C.muted, fontSize: 11)),
                const SizedBox(height: 8),
                _pinField('Pin school', 'schoolLocation', Icons.location_on_outlined),
                _chipEditor('Nearest bus stops', 'busStops', 'Add bus stop'),
                _chipEditor('Nearest moto stops', 'motoStops', 'Set moto stop'),
                _numField('Distance from your home (km)', 'C07'),

                _section('C11 · Internship & industry partners'),
                _numField('Companies you collaborate with (count)', 'C11'),
                _chipEditor('Partner companies', 'companies', 'Add a company'),

                _section('C12 · Alumni network strength'),
                _cohortEditor(),

                _section('C13 · Career services quality'),
                _numField('Staff serving in career services', 'careerStaff'),
                _numField('Service rating (out of 5)', 'C13'),

                _section('C14 · Library & e-learning'),
                _yesNo('Available?', 'library'),

                _section('C15 · ICT infrastructure'),
                _numField('Computer rooms', 'C15'),
                _yesNo('Public Wi-Fi available?', 'publicWifi'),

                _section('C16 · Sporting facilities'),
                _yesNo('Available?', 'sporting'),

                _section('C17 · Health / medical services'),
                _yesNoVertical('Available?', 'health'),
                if (d['health'] == true)
                  _chipEditor('Insurance / clinics you work with', 'healthPartners', 'Add insurer or clinic'),

                _section('Ratings & standing'),
                Row(children: [
                  Expanded(child: _numField('Satisfaction (/5) · C18', 'C18')),
                  const SizedBox(width: 10),
                  Expanded(child: _numField('Peer reputation (/5) · C19', 'C19')),
                ]),
                Row(children: [
                  Expanded(child: _numField('National rank · C20', 'C20')),
                  const SizedBox(width: 10),
                  Expanded(child: _numField('Institution size · C22', 'C22')),
                ]),
                _numField('Average class size · C05', 'C05'),

                _section('C25 · Religious / cultural affiliation'),
                _yesNo('Religious-based?', 'religiousBased'),
                if (d['religiousBased'] == true) _religionSelect(),

                _section('C26 · Mode of study'),
                _modeCheck('Day session', 'modeDay'),
                _modeCheck('Evening session', 'modeEvening'),
                _modeCheck('Weekend session', 'modeWeekend'),

                _section('C23 · Minimum entry grade'),
                _textField('Lowest grade you accept (e.g. Bs or Cs)', 'minGrade'),

                if (otherCriteria.isNotEmpty) ...[
                  _section('Other criteria'),
                  const Text('These criteria don\'t have a dedicated field yet — enter a number if you have one.',
                      style: TextStyle(color: C.muted, fontSize: 11)),
                  const SizedBox(height: 8),
                  ...otherCriteria.map((c) => _numField('${c['label']} · ${c['code']}', c['code'] as String)),
                ],
              ],
            ),
    );
  }

  // ---- field builders ----
  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 14)),
      );

  Widget _numField(String label, String key) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: _n(key)?.toString() ?? '')
              ..selection = TextSelection.collapsed(offset: (_n(key)?.toString() ?? '').length),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDeco('Enter a number'),
            onChanged: (v) => d[key] = double.tryParse(v.trim()) ?? d[key],
          ),
        ]),
      );

  void _syncFeeRange() {
    final min = _n('feeMin'), max = _n('feeMax');
    if (min != null && max != null) d['C01'] = (min.toDouble() + max.toDouble()) / 2;
  }

  Widget _feeRangeField() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tuition range (RWF / year)', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(
              controller: TextEditingController(text: _n('feeMin')?.toString() ?? '')
                ..selection = TextSelection.collapsed(offset: (_n('feeMin')?.toString() ?? '').length),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: fieldDeco('Min'),
              onChanged: (v) { d['feeMin'] = double.tryParse(v.trim()); _syncFeeRange(); },
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: TextEditingController(text: _n('feeMax')?.toString() ?? '')
                ..selection = TextSelection.collapsed(offset: (_n('feeMax')?.toString() ?? '').length),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: fieldDeco('Max'),
              onChanged: (v) { d['feeMax'] = double.tryParse(v.trim()); _syncFeeRange(); },
            )),
          ]),
        ]),
      );

  void _syncScholarship() {
    final vals = ['completion', 'intake', 'grade', 'coverage']
        .map((k) => _n(k)).where((v) => v != null).cast<num>().toList();
    if (vals.isNotEmpty) {
      final avg = vals.fold<double>(0, (s, v) => s + v.toDouble()) / vals.length;
      d['C02'] = avg / 20; // 0-100% average scaled to a 0-5 scholarship score
    }
  }

  Widget _pctField(String label, String key) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: TextEditingController(text: _n(key)?.toString() ?? '')
            ..selection = TextSelection.collapsed(offset: (_n(key)?.toString() ?? '').length),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldDeco('0–100'),
          onChanged: (v) { d[key] = double.tryParse(v.trim()); _syncScholarship(); },
        ),
      ]);

  Widget _scholarshipFields() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _pctField('Completion %', 'completion')),
            const SizedBox(width: 10),
            Expanded(child: _pctField('Intake %', 'intake')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _pctField('Grade %', 'grade')),
            const SizedBox(width: 10),
            Expanded(child: _pctField('Coverage %', 'coverage')),
          ]),
          const SizedBox(height: 10),
        ]),
      );

  Widget _pinField(String label, String key, IconData icon) {
    final val = (d[key] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (val.isNotEmpty)
          Chip(
            avatar: Icon(icon, size: 15, color: C.green),
            label: Text(val, style: const TextStyle(fontSize: 12)),
            backgroundColor: const Color(0xFFF1EBE0),
            onDeleted: () => setState(() => d[key] = ''),
          ),
        ActionChip(
          avatar: Icon(icon, size: 16, color: C.green),
          label: Text(val.isEmpty ? label : 'Change', style: const TextStyle(fontSize: 12, color: C.green)),
          backgroundColor: Colors.white,
          side: const BorderSide(color: C.border),
          onPressed: () async {
            final v = await _promptText(label);
            if (v != null && v.trim().isNotEmpty) setState(() => d[key] = v.trim());
          },
        ),
      ]),
    );
  }

  Widget _textField(String label, String key) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: (d[key] ?? '').toString())
              ..selection = TextSelection.collapsed(offset: (d[key] ?? '').toString().length),
            decoration: fieldDeco('Type here'),
            onChanged: (v) => d[key] = v,
          ),
        ]),
      );

  Widget _yesNo(String label, String key) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: C.ink, fontSize: 13))),
          _radio('Yes', d[key] == true, () => setState(() => d[key] = true)),
          const SizedBox(width: 8),
          _radio('No', d[key] == false, () => setState(() => d[key] = false)),
        ]),
      );

  Widget _yesNoVertical(String label, String key) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: C.ink, fontSize: 13)),
          const SizedBox(height: 8),
          _radioTile('Yes', d[key] == true, () => setState(() => d[key] = true)),
          const SizedBox(height: 6),
          _radioTile('No', d[key] == false, () => setState(() => d[key] = false)),
        ]),
      );

  Widget _radioTile(String label, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? C.green : Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? C.green : C.border),
          ),
          child: Row(children: [
            Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18, color: sel ? Colors.white : C.muted),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: sel ? Colors.white : C.ink, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _radio(String label, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? C.green : Colors.white, borderRadius: BorderRadius.circular(999),
            border: Border.all(color: sel ? C.green : C.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 15, color: sel ? Colors.white : C.muted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: sel ? Colors.white : C.ink, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _modeCheck(String label, String key) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeColor: C.green,
        controlAffinity: ListTileControlAffinity.leading,
        value: d[key] == true,
        onChanged: (v) => setState(() => d[key] = v ?? false),
        title: Text(label, style: const TextStyle(color: C.ink, fontSize: 13)),
      );

  Widget _religionSelect() => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: DropdownButtonFormField<String>(
          value: kReligions.contains(d['religion']) ? d['religion'] as String : null,
          isExpanded: true,
          decoration: fieldDeco('Select religion / culture'),
          hint: const Text('Select religion / culture'),
          items: kReligions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => setState(() => d['religion'] = v),
        ),
      );

  Widget _chipEditor(String label, String key, String hint) {
    final list = List<String>.from(d[key] ?? const []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ...list.map((s) => Chip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                backgroundColor: const Color(0xFFF1EBE0),
                onDeleted: () => setState(() => (d[key] as List).remove(s)),
              )),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16, color: C.green),
            label: Text(hint, style: const TextStyle(fontSize: 12, color: C.green)),
            backgroundColor: Colors.white,
            side: const BorderSide(color: C.border),
            onPressed: () async {
              final v = await _promptText(hint);
              if (v != null && v.trim().isNotEmpty) setState(() => (d[key] as List).add(v.trim()));
            },
          ),
        ]),
      ]),
    );
  }

  Widget _cohortEditor() {
    final list = List<Map<String, dynamic>>.from(d['cohorts'] ?? const []);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Active-alumni % per cohort (e.g. 2023–2024 → 62%)',
          style: TextStyle(color: C.muted, fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: List.generate(list.length, (i) {
        final c = list[i];
        return Chip(
          label: Text('${c['period']} — ${c['pct']}%', style: const TextStyle(fontSize: 12)),
          backgroundColor: const Color(0xFFF1EBE0),
          onDeleted: () => setState(() => (d['cohorts'] as List).removeAt(i)),
        );
      })),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _cohortPeriodCtl, decoration: fieldDeco('Cohort (e.g. 2023–2024)'))),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: TextField(
          controller: _cohortPctCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: fieldDeco('%'),
        )),
        IconButton(
          icon: const Icon(Icons.add_circle, color: C.green, size: 28),
          onPressed: () {
            final period = _cohortPeriodCtl.text.trim();
            final pct = _cohortPctCtl.text.trim();
            if (period.isEmpty || pct.isEmpty) return;
            setState(() {
              (d['cohorts'] as List).add({'period': period, 'pct': double.tryParse(pct) ?? pct});
              _cohortPeriodCtl.clear();
              _cohortPctCtl.clear();
            });
          },
        ),
      ]),
    ]);
  }

  Future<String?> _promptText(String label) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: c, autofocus: true, decoration: fieldDeco(label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
  }
}

/// ---- Staff: reports -------------------------------------------------------
class StaffReportsScreen extends StatefulWidget {
  const StaffReportsScreen({super.key});
  @override
  State<StaffReportsScreen> createState() => _StaffReportsScreenState();
}

class _StaffReportsScreenState extends State<StaffReportsScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = Api.staffReport(_staffUni);
  }

  Future<void> _copyApplicants(List apps) async {
    await Clipboard.setData(ClipboardData(text: _toCsv(
        ['Name', 'Email', 'Home area'],
        apps.map((a) => [a['name'], a['email'], a['home']]).toList())));
    if (mounted) toast(context, 'Applicants CSV copied (${apps.length} rows)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: staffDrawer(context),
      appBar: staffAppBar(context, 'Reports', back: true),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final r = snap.data ?? {};
          final apps = (r['applicants'] as List?) ?? [];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(children: [
                Expanded(child: _stat('${r['appearedCount'] ?? 0}', 'On students\' lists', C.green)),
                const SizedBox(width: 10),
                Expanded(child: _stat('${r['applyCount'] ?? 0}', 'Tapped Apply', const Color(0xFFC25A1F))),
              ]),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Applicants', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.ink)),
                TextButton.icon(
                  onPressed: () => _copyApplicants(apps),
                  icon: const Icon(Icons.download, size: 16, color: C.green),
                  label: const Text('CSV', style: TextStyle(color: C.green)),
                ),
              ]),
              const SizedBox(height: 6),
              if (apps.isEmpty)
                const Text('No applicants yet.', style: TextStyle(color: C.muted))
              else
                ...apps.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                        Text('${a['email'] ?? ''} · ${a['home'] ?? ''}',
                            style: const TextStyle(color: C.muted, fontSize: 11)),
                      ]),
                    )),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String value, String label, Color color) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: C.muted, fontSize: 11)),
        ]),
      );
}

/// ===========================================================================
/// ADMIN
/// ===========================================================================
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int? uniCount, staffTotal, pendingCount, studentCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final unis = await Api.adminUniversities();
      final staff = await Api.staffRequests();
      final students = await Api.adminStudents();
      if (!mounted) return;
      setState(() {
        uniCount = unis.length;
        staffTotal = staff.length;
        pendingCount = staff.where((r) => (r as Map)['status'] == 'pending').length;
        studentCount = students.length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawer(context),
      appBar: adminAppBar(context, 'Admin dashboard'),
      body: RefreshIndicator(
        color: C.green,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Welcome ${Session.name.isEmpty ? 'Admin' : Session.name.split(' ').first}', style: head(24)),
            const SizedBox(height: 4),
            const Text('Manage the whole UniMatch platform.', style: TextStyle(color: C.muted)),
            const SizedBox(height: 18),
            // stat cards
            Row(children: [
              Expanded(child: _stat('${pendingCount ?? '—'}', 'Pending staff', const Color(0xFFC25A1F))),
              const SizedBox(width: 10),
              Expanded(child: _stat('${uniCount ?? '—'}', 'Universities', C.green)),
              const SizedBox(width: 10),
              Expanded(child: _stat('${studentCount ?? '—'}', 'Students', const Color(0xFF2A5C8F))),
            ]),
            const SizedBox(height: 18),
            _card(context, 'Staff approvals', 'Confirm, deny, suspend or remove university staff',
                Icons.verified_user_outlined, const AdminApprovalsScreen(), badge: pendingCount,
                bg: const Color(0xFFF7E4D3), fg: const Color(0xFFC25A1F)),
            _card(context, 'Universities', 'Add, edit or delete institutions',
                Icons.apartment, const AdminUniversitiesScreen(),
                bg: const Color(0xFFDCE9F2), fg: const Color(0xFF2A5C8F)),
            _card(context, 'Evaluation criteria', 'Add, edit or remove ranking signals',
                Icons.tune, const AdminCriteriaScreen(),
                bg: const Color(0xFFDCEBE3), fg: C.green),
            _card(context, 'Student accounts', 'Suspend or restore A2 graduates',
                Icons.people_outline, const AdminStudentsScreen(),
                bg: const Color(0xFFF6EBCF), fg: const Color(0xFFB48412)),
            _card(context, 'Reports', 'Generate & download platform reports (CSV)',
                Icons.bar_chart, const AdminReportsScreen(),
                bg: const Color(0xFFDCE9F2), fg: const Color(0xFF2A5C8F)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
        child: Column(children: [
          Text(value, style: head(24, color: color)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 10.5)),
        ]),
      );

  Widget _card(BuildContext ctx, String t, String s, IconData i, Widget dest, {int? badge, Color? bg, Color? fg}) => GestureDetector(
        onTap: () async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => dest));
          _load(); // refresh counts when returning
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: bg ?? C.sand, borderRadius: BorderRadius.circular(12)),
              child: Icon(i, color: fg ?? C.green, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                const SizedBox(height: 2),
                Text(s, style: const TextStyle(color: C.muted, fontSize: 12)),
              ]),
            ),
            if (badge != null && badge > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFC25A1F), borderRadius: BorderRadius.circular(999)),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            const Icon(Icons.chevron_right, color: C.muted),
          ]),
        ),
      );
}

/// ---- Admin: staff approvals -----------------------------------------------
class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});
  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> {
  late Future<List<dynamic>> _future;
  final TextEditingController _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _future = Api.staffRequests();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() { _future = Api.staffRequests(); });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawer(context),
      appBar: adminAppBar(context, 'Staff approvals', back: true),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final all = snap.data ?? [];
          if (all.isEmpty) return _emptyView('No staff requests.');
          final query = _search.text.trim().toLowerCase();
          final reqs = query.isEmpty
              ? all
              : all.where((r) {
                  final m = r as Map;
                  return '${m['name']}'.toLowerCase().contains(query) || '${m['email']}'.toLowerCase().contains(query);
                }).toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              searchField(_search, 'Search staff…'),
              const SizedBox(height: 12),
              if (reqs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No staff match "${_search.text.trim()}".',
                      textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                ),
              ...reqs.map((r) {
              final m = r as Map;
              final status = (m['status'] ?? 'pending').toString();
              final confirmed = status == 'confirmed';
              final suspended = status == 'suspended';
              Color statusColor = suspended ? const Color(0xFFC25A1F) : (confirmed ? C.green : Colors.orange);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: suspended ? const Color(0xFFF0C4A8) : C.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['name'] ?? 'Request ${m['id']}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                        const SizedBox(height: 2),
                        Text(m['email'] ?? '', style: const TextStyle(color: C.muted, fontSize: 12)),
                        Text(status[0].toUpperCase() + status.substring(1),
                            style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    if (!confirmed && !suspended)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        OutlinedButton(
                          onPressed: () async {
                            final ok = await _confirmDialog(context, 'Deny request?',
                                'Reject ${m['name']}\'s staff sign-up. They won\'t get access.');
                            if (ok) _act(() => Api.deleteStaff(m['id']));
                          },
                          style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFC25A1F),
                              side: const BorderSide(color: Color(0xFFF0C4A8))),
                          child: const Text('Deny'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _act(() => Api.confirmStaff(m['id'])),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: C.green, foregroundColor: Colors.white, elevation: 0),
                          child: const Text('Confirm'),
                        ),
                      ]),
                  ]),
                  // After confirm, the admin can suspend or delete the staff account.
                  if (confirmed || suspended) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _act(() => Api.setStaffStatus(m['id'], suspended ? 'confirmed' : 'suspended')),
                          icon: Icon(suspended ? Icons.play_circle_outline : Icons.pause_circle_outline,
                              size: 18, color: suspended ? C.green : const Color(0xFFC25A1F)),
                          label: Text(suspended ? 'Restore' : 'Suspend',
                              style: TextStyle(color: suspended ? C.green : const Color(0xFFC25A1F))),
                          style: OutlinedButton.styleFrom(
                              side: BorderSide(color: suspended ? C.green : const Color(0xFFF0C4A8))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await _confirmDialog(context, 'Delete staff account?',
                                'Remove ${m['name']} permanently. They will lose access.');
                            if (ok) _act(() => Api.deleteStaff(m['id']));
                          },
                          icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC25A1F)),
                          label: const Text('Delete', style: TextStyle(color: Color(0xFFC25A1F))),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFF0C4A8))),
                        ),
                      ),
                    ]),
                  ],
                ]),
              );
            }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _act(Future<void> Function() fn) async {
    try { await fn(); _reload(); }
    catch (e) { if (mounted) toast(context, e.toString()); }
  }
}

/// ---- Admin: universities CRUD ---------------------------------------------
class AdminUniversitiesScreen extends StatefulWidget {
  const AdminUniversitiesScreen({super.key});
  @override
  State<AdminUniversitiesScreen> createState() => _AdminUniversitiesScreenState();
}

class _AdminUniversitiesScreenState extends State<AdminUniversitiesScreen> {
  late Future<List<dynamic>> _future;
  final TextEditingController _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _future = Api.adminUniversities();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() { _future = Api.adminUniversities(); });

  Future<void> _edit({Map? existing}) async {
    final abbr = TextEditingController(text: existing?['abbr'] ?? '');
    final name = TextEditingController(text: existing?['name'] ?? '');
    final sector = TextEditingController(text: existing?['sector'] ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(existing == null ? 'Add university' : 'Edit university',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
          const SizedBox(height: 16),
          TextField(controller: abbr, decoration: fieldDeco('Abbreviation (e.g. UoK)')),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: fieldDeco('Full name')),
          const SizedBox(height: 12),
          TextField(controller: sector, decoration: fieldDeco('Main campus / location')),
          const SizedBox(height: 20),
          primaryButton('Save university', () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (saved != true) return;
    try {
      if (existing == null) {
        await Api.addUniversity(abbr.text.trim(), name.text.trim(), sector.text.trim());
      } else {
        await Api.updateUniversity(existing['id'], abbr.text.trim(), name.text.trim(), sector.text.trim());
      }
      _reload();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _delete(Map u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete university?'),
        content: Text('Remove ${u['name']} and everything linked to it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteUniversity(u['id']);
      _reload();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawer(context),
      appBar: adminAppBar(context, 'Universities', back: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: C.green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add', style: TextStyle(color: Colors.white)),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final all = snap.data ?? [];
          if (all.isEmpty) return _emptyView('No universities yet — add one.');
          final query = _search.text.trim().toLowerCase();
          final unis = query.isEmpty
              ? all
              : all.where((u) => '${(u as Map)['name']}'.toLowerCase().contains(query)).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: searchField(_search, 'Search by name, abbreviation, campus or department'),
            ),
            Expanded(
              child: unis.isEmpty
                  ? _emptyView('No universities match "${_search.text.trim()}".')
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: unis.map((u) {
                        final m = u as Map;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                          child: Row(children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: C.uni('${m['abbr']}'), borderRadius: BorderRadius.circular(12)),
                              alignment: Alignment.center,
                              child: Text(m['abbr'] ?? '', style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                                if ((m['sector'] ?? '').toString().isNotEmpty)
                                  Text(m['sector'], style: const TextStyle(color: C.muted, fontSize: 11)),
                              ]),
                            ),
                            IconButton(icon: const Icon(Icons.edit_outlined, color: C.green, size: 20), onPressed: () => _edit(existing: m)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFC25A1F), size: 20), onPressed: () => _delete(m)),
                          ]),
                        );
                      }).toList(),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

/// ---- Admin: criteria CRUD -------------------------------------------------
class AdminCriteriaScreen extends StatefulWidget {
  const AdminCriteriaScreen({super.key});
  @override
  State<AdminCriteriaScreen> createState() => _AdminCriteriaScreenState();
}

class _AdminCriteriaScreenState extends State<AdminCriteriaScreen> {
  late Future<List<dynamic>> _future;
  final TextEditingController _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _future = Api.adminCriteria();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    Session.criteriaCatalogue = null; // invalidate the shared public-catalogue cache
    _future = Api.adminCriteria();
  });

  Future<void> _edit({Map? existing}) async {
    final label = TextEditingController(text: existing?['label'] ?? '');
    String category = kCriteriaCategories.contains(existing?['category'])
        ? existing!['category'] as String : kCriteriaCategories.first;
    String direction = existing?['direction'] ?? 'benefit';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existing == null ? 'Add criterion' : 'Edit criterion',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
            const SizedBox(height: 16),
            TextField(controller: label, decoration: fieldDeco('Criterion name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              isExpanded: true,
              decoration: fieldDeco('Category'),
              items: kCriteriaCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSheet(() => category = v ?? category),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _dirChip('Higher is better', direction == 'benefit', () => setSheet(() => direction = 'benefit'))),
              const SizedBox(width: 8),
              Expanded(child: _dirChip('Lower is better', direction == 'cost', () => setSheet(() => direction = 'cost'))),
            ]),
            const SizedBox(height: 20),
            primaryButton('Save criterion', () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (saved != true) return;
    try {
      if (existing == null) {
        await Api.addCriterion(label.text.trim(), category, direction);
      } else {
        await Api.updateCriterion(existing['code'], label.text.trim(), category, direction);
      }
      _reload();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Widget _dirChip(String t, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? C.green : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? C.green : C.border),
          ),
          child: Text(t, style: TextStyle(color: sel ? Colors.white : C.ink, fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawer(context),
      appBar: adminAppBar(context, 'Evaluation criteria', back: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: C.green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add', style: TextStyle(color: Colors.white)),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final all = snap.data ?? [];
          if (all.isEmpty) return _emptyView('No criteria yet — add one.');
          final query = _search.text.trim().toLowerCase();
          final crits = query.isEmpty
              ? all
              : all.where((c) {
                  final m = c as Map;
                  return '${m['label']}'.toLowerCase().contains(query) ||
                      '${m['code']}'.toLowerCase().contains(query) ||
                      '${m['category']}'.toLowerCase().contains(query);
                }).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: searchField(_search, 'Search criteria…'),
            ),
            Expanded(
              child: crits.isEmpty
                  ? _emptyView('No criteria match "${_search.text.trim()}".')
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: crits.map((c) {
                        final m = c as Map;
                        final cost = m['direction'] == 'cost';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                          child: Row(children: [
                            SizedBox(width: 34, child: Text(m['code'] ?? '', style: const TextStyle(color: C.muted, fontSize: 11))),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m['label'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                                Text('${cost ? 'Lower is better' : 'Higher is better'} · ${m['category'] ?? ''}',
                                    style: TextStyle(color: cost ? const Color(0xFFC25A1F) : C.green, fontSize: 11)),
                              ]),
                            ),
                            IconButton(icon: const Icon(Icons.edit_outlined, color: C.green, size: 20), onPressed: () => _edit(existing: m)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFC25A1F), size: 20),
                                onPressed: () async {
                                  try { await Api.deleteCriterion(m['code']); _reload(); }
                                  catch (e) { if (mounted) toast(context, e.toString()); }
                                }),
                          ]),
                        );
                      }).toList(),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

/// ---- Admin: student accounts (suspend / restore) --------------------------
class AdminStudentsScreen extends StatefulWidget {
  const AdminStudentsScreen({super.key});
  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  late Future<List<dynamic>> _future;
  final TextEditingController _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _future = Api.adminStudents();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() { _future = Api.adminStudents(); });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawer(context),
      appBar: adminAppBar(context, 'Student accounts', back: true),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final all = snap.data ?? [];
          if (all.isEmpty) return _emptyView('No student accounts yet.');
          final query = _search.text.trim().toLowerCase();
          final students = query.isEmpty
              ? all
              : all.where((s) {
                  final m = s as Map;
                  return '${m['name']}'.toLowerCase().contains(query) || '${m['email']}'.toLowerCase().contains(query);
                }).toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              searchField(_search, 'Search students…'),
              const SizedBox(height: 12),
              const Text('Suspending is reversible — restore any time.',
                  style: TextStyle(color: C.muted, fontSize: 12)),
              const SizedBox(height: 12),
              if (students.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No students match "${_search.text.trim()}".',
                      textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
                ),
              ...students.map((st) {
                final m = st as Map;
                final suspended = m['suspended'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: suspended ? const Color(0xFFF0C4A8) : C.border)),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: suspended ? const Color(0xFFB0A896) : C.green,
                      child: Text((m['name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['name'] ?? '',
                            style: TextStyle(fontWeight: FontWeight.w600, color: suspended ? C.muted : C.ink)),
                        Text('${m['email']} · ${suspended ? 'Suspended' : 'Active'}',
                            style: const TextStyle(color: C.muted, fontSize: 11)),
                      ]),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await Api.setStudentSuspended(m['id'], !suspended);
                          _reload();
                        } catch (e) {
                          if (mounted) toast(context, e.toString());
                        }
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: suspended ? C.green : const Color(0xFFFDEEE3),
                        foregroundColor: suspended ? Colors.white : const Color(0xFFC25A1F),
                      ),
                      child: Text(suspended ? 'Restore' : 'Suspend'),
                    ),
                  ]),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

Widget _emptyView(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
      ),
    );

Future<bool> _confirmDialog(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Color(0xFFC25A1F)))),
      ],
    ),
  );
  return ok == true;
}

/// CSV helper: escape a cell, join rows.
String _toCsv(List<String> header, List<List<dynamic>> rows) {
  String cell(dynamic v) {
    final s = (v ?? '').toString();
    return (s.contains(',') || s.contains('"') || s.contains('\n'))
        ? '"${s.replaceAll('"', '""')}"' : s;
  }
  final b = StringBuffer(header.map(cell).join(','))..write('\n');
  for (final r in rows) b.write(r.map(cell).join(',') + '\n');
  return b.toString();
}

/// ---- Admin: reports (generate + copy CSV) ---------------------------------
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  late Future<Map<String, dynamic>> _future;
  List<dynamic> criteriaUsage = [];
  String reportType = 'Applications by university';
  String reportUni = 'All universities';
  DateTime from = DateTime(2026, 1, 1);
  DateTime to = DateTime(2026, 7, 16);

  static const _types = [
    'Applications by university',
    'Shortlist / interest trends',
    'A2 applicants list',
    'Most-chosen criteria',
  ];

  static const _typeHint = {
    'Applications by university': 'How many students applied to each university in the selected window.',
    'Shortlist / interest trends': 'How often each university was shortlisted by students.',
    'A2 applicants list': 'Every A2 graduate who applied, their university and home area.',
    'Most-chosen criteria': 'Which criteria students weighed most when ranking.',
  };

  @override
  void initState() {
    super.initState();
    _future = Api.adminReport();
    Api.criteriaUsage().then((v) { if (mounted) setState(() => criteriaUsage = v); }).catchError((_) {});
  }

  String _fmt(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(
      context: context,
      initialDate: isFrom ? from : to,
      firstDate: DateTime(2024), lastDate: DateTime(2027),
    );
    if (d != null) setState(() => isFrom ? from = d : to = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawer(context),
      appBar: adminAppBar(context, 'Reports', back: true),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.green));
          }
          if (snap.hasError) return _errorView(snap.error.toString());
          final r = snap.data ?? {};
          final unis = List<Map>.from((r['universities'] as List?)?.map((e) => e as Map) ?? const []);
          final apps = (r['applications'] as List?) ?? [];
          final uniNames = ['All universities', ...unis.map((u) => (u['name'] ?? '').toString())];
          if (!uniNames.contains(reportUni)) reportUni = 'All universities';

          final totalApps = unis.fold<int>(0, (a, u) => a + ((u['applications'] as num?)?.toInt() ?? 0));
          final avgRating = (r['avgRating'] as num?)?.toDouble();

          // rows for the selected report type
          List<Map> rows;
          String rowUnit;
          if (reportType == 'Shortlist / interest trends') {
            rows = unis.map((u) => {'name': u['name'], 'abbr': u['abbr'], 'n': (u['shortlists'] as num?)?.toInt() ?? 0}).toList();
            rowUnit = 'shortlists';
          } else if (reportType == 'Most-chosen criteria') {
            rows = criteriaUsage.map((c) => {'name': (c as Map)['label'], 'abbr': c['code'], 'n': (c['count'] as num).toInt()}).toList();
            rowUnit = 'selections';
          } else {
            rows = unis.map((u) => {'name': u['name'], 'abbr': u['abbr'], 'n': (u['applications'] as num?)?.toInt() ?? 0}).toList();
            rowUnit = 'applications';
          }
          rows.sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));
          final maxN = rows.isEmpty ? 1 : (rows.first['n'] as int).clamp(1, 1 << 30);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _lbl('REPORT TYPE'),
              _dropdown(reportType, _types, (v) => setState(() => reportType = v!)),
              const SizedBox(height: 6),
              Text(_typeHint[reportType] ?? '', style: const TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _dateField(_fmt(from), () => _pickDate(true))),
                const SizedBox(width: 12),
                Expanded(child: _dateField(_fmt(to), () => _pickDate(false))),
              ]),
              const SizedBox(height: 12),
              _dropdown(reportUni, uniNames, (v) => setState(() => reportUni = v!)),
              const SizedBox(height: 16),
              // stat cards
              Row(children: [
                Expanded(child: _stat('$totalApps', 'Applications', C.green)),
                const SizedBox(width: 10),
                Expanded(child: _stat('${unis.length}', 'Universities', const Color(0xFFC25A1F))),
                const SizedBox(width: 10),
                Expanded(child: _stat(avgRating != null ? avgRating.toStringAsFixed(1) : '—', 'Avg. rating', C.green)),
              ]),
              const SizedBox(height: 16),
              // download
              GestureDetector(
                onTap: () {
                  if (reportType == 'A2 applicants list') {
                    _copyCsv('Applicants', ['Student', 'Email', 'University', 'Home area', 'Date'],
                        apps.map((a) => [a['student'], a['email'], a['university'], a['home'], a['date']]).toList());
                  } else if (reportType == 'Most-chosen criteria') {
                    _copyCsv(reportType, ['Criterion', 'Code', 'selections'],
                        rows.map((u) => [u['name'], u['abbr'], u['n']]).toList());
                  } else {
                    _copyCsv(reportType, ['University', 'Abbr', rowUnit],
                        rows.map((u) => [u['name'], u['abbr'], u['n']]).toList());
                  }
                },
                child: Container(
                  height: 54, alignment: Alignment.center,
                  decoration: BoxDecoration(color: C.green, borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.download, color: C.gold, size: 18),
                    const SizedBox(width: 10),
                    Text('Download  ${reportType == 'A2 applicants list' ? 'applicants' : rowUnit}  (CSV)',
                        style: const TextStyle(color: C.gold, fontWeight: FontWeight.w700, fontSize: 14)),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              Text(reportType, style: head(17, weight: FontWeight.w500)),
              const SizedBox(height: 10),
              if (reportType == 'A2 applicants list')
                ...apps.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${a['student']}', style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                        Text('${a['university']} · ${a['home']}', style: const TextStyle(color: C.muted, fontSize: 11)),
                      ]),
                    ))
              else
                ...rows.map((u) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                      child: Row(children: [
                        Expanded(
                          child: Text('${u['name']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: C.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 70,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: (u['n'] as int) / maxN,
                              minHeight: 7,
                              backgroundColor: C.sand,
                              valueColor: AlwaysStoppedAnimation(C.uni('${u['abbr']}')),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('${u['n']}', style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700)),
                      ]),
                    )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyCsv(String name, List<String> header, List<List<dynamic>> rows) async {
    await Clipboard.setData(ClipboardData(text: _toCsv(header, rows)));
    if (mounted) toast(context, '$name CSV copied to clipboard (${rows.length} rows)');
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.green, letterSpacing: 0.5)),
      );

  Widget _dropdown(String value, List<String> items, ValueChanged<String?> onChanged) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value, isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down, color: C.muted),
            items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: onChanged,
          ),
        ),
      );

  Widget _dateField(String text, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50, padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
          child: Row(children: [
            Expanded(child: Text(text, style: const TextStyle(color: C.ink, fontSize: 14))),
            const Icon(Icons.calendar_today_outlined, size: 16, color: C.muted),
          ]),
        ),
      );

  Widget _stat(String value, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
        child: Column(children: [
          Text(value, style: head(24, color: color)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 10.5)),
        ]),
      );
}

/// ---- shared error view -----------------------------------------------------
Widget _errorView(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, color: C.muted, size: 40),
          const SizedBox(height: 12),
          const Text('Can\'t reach the server',
              style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
          const SizedBox(height: 6),
          Text('$msg\n\nIs the Node server running? On the emulator the app expects it at $kBaseUrl.',
              textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 13)),
        ]),
      ),
    );
