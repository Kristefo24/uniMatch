import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart'
    show FlutterMap, MapController, MapOptions, TileLayer, MarkerLayer, Marker,
        CameraConstraint, InteractionOptions, InteractiveFlag, LatLngBounds;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'csv_download_stub.dart' if (dart.library.html) 'csv_download_web.dart' as csv_download;

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
const String kApiUrl = 'https://unimatch-production-276f.up.railway.app';
const bool kUseHosted = true;
final String kBaseUrl = kUseHosted
    ? kApiUrl
    : (kIsWeb ? 'http://localhost:4000' : 'http://10.0.2.2:4000');

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

/// Every 2-subject pair from the subjects staff marked acceptable within one
/// A2 combination for a programme — e.g. selecting Maths/Chemistry/Biology
/// for MCB means "Maths + Chemistry" OR "Maths + Biology" OR "Chemistry +
/// Biology" all qualify. Capped naturally at 3 subjects per combination.
List<String> subjectPairs(List<String> subs) {
  final out = <String>[];
  for (var i = 0; i < subs.length; i++) {
    for (var j = i + 1; j < subs.length; j++) out.add('${subs[i]} + ${subs[j]}');
  }
  return out;
}

// A small curated palette, cycled by combination code -- consistent
// everywhere a code is shown, echoing the existing per-university color
// convention (C.uni(abbr)). Purely visual: doesn't imply any semantics.
const _comboPalette = [
  Color(0xFF2A5C8F), Color(0xFFB4472A), Color(0xFF1F5F4A), Color(0xFF7A2F4A),
  Color(0xFFB48412), Color(0xFF164638), Color(0xFF8F4B2A), Color(0xFF2F4A7A),
];
Color comboColor(String code) => _comboPalette[code.hashCode.abs() % _comboPalette.length];

/// Shared "eligible principal passes" card -- one colored chip per
/// combination code with its qualifying subject pairs, used identically on
/// DetailScreen and ProgrammeScreen. Renders nothing for an empty map --
/// never fabricates eligibility that staff didn't actually set.
Widget eligibilityCard(Map<String, List<String>> byCode, {String? title}) {
  if (byCode.isEmpty) return const SizedBox.shrink();
  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    if (title != null) ...[
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 12.5)),
      const SizedBox(height: 8),
    ],
    Wrap(spacing: 8, runSpacing: 8, children: byCode.entries.map((e) {
      final color = comboColor(e.key);
      final pairs = subjectPairs(e.value);
      if (pairs.isEmpty) return const SizedBox.shrink();
      return Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            child: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          ...pairs.map((pair) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(pair, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              )),
        ]),
      );
    }).toList()),
  ]);
}


/// Shared OpenStreetMap Nominatim helpers — used by both the A2 graduate's
/// home-location map (`LocationScreen`) and staff's university/transport
/// pin map (`StaffCriteriaScreen`). Nominatim's usage policy requires a
/// distinct User-Agent and discourages high-frequency requests.
const kNominatimUA = {'User-Agent': 'UniMatchGasabo/1.0'};
String coordsLabel(LatLng p) => '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';

/// Resolves a lat/lng to a human-readable address, or null on any failure —
/// callers fall back to `coordsLabel(p)` themselves.
Future<String?> reverseGeocodeAddress(LatLng p) async {
  try {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${p.latitude}&lon=${p.longitude}');
    final res = await http.get(uri, headers: kNominatimUA);
    final data = jsonDecode(res.body) as Map;
    return data['display_name'] as String?;
  } catch (_) {
    return null;
  }
}

const List<String> kDepartments = [
  'Business, Economics & Management',
  'Computing, IT & Engineering',
  'Health & Medical Sciences',
  'Education & Social Sciences',
  'Law, Governance & Public Affairs',
  'Arts, Humanities & Communication',
  'Agriculture, Environment & Natural Sciences',
  'Architecture, Construction, Hospitality & Tourism',
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
          {String? track, String? universityId}) async {
    final res = await _post('/signup', {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      if (track != null) 'track': track,
      if (universityId != null) 'universityId': universityId,
    });
    if (res['token'] != null) token = res['token'];
    return res;
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _post('/login', {'email': email, 'password': password});
    token = res['token'];
    return res;
  }

  static Future<Map<String, dynamic>> updateMe({
    String? name, String? track, String? photo, String? homeArea, double? homeLat, double? homeLng,
  }) =>
      _put('/me', {
        if (name != null) 'name': name,
        if (track != null) 'track': track,
        if (photo != null) 'photo': photo,
        if (homeArea != null) 'homeArea': homeArea,
        if (homeLat != null) 'homeLat': homeLat,
        if (homeLng != null) 'homeLng': homeLng,
      });

  /// The student's own last saved ranking snapshot ({ranked, criteria,
  /// updatedAt}), or null if they've never genuinely ranked — lets "My
  /// rankings" show a real result after a fresh login/session.
  static Future<Map<String, dynamic>?> myLastRanking() async {
    final r = await _get('/me/last-ranking');
    return r == null ? null : Map<String, dynamic>.from(r);
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

  /// Admin-managed subject-combination catalogue (e.g. PCB, MPC), cached for
  /// the running session — pass refresh:true to force a re-fetch.
  static Future<List<dynamic>> combinations({bool refresh = false}) async {
    if (!refresh && Session.comboCatalogue != null) return Session.comboCatalogue!;
    final list = await _get('/combinations') as List<dynamic>;
    Session.comboCatalogue = list;
    return list;
  }

  static Future<List<dynamic>> rank(List<Map<String, dynamic>> criteria, {
    String? preferredReligion, String? dept, String? programme, double? homeLat, double? homeLng,
    double? budgetMin, double? budgetMax,
  }) async {
    final res = await _post('/rank', {
      // No universityIds -> server scores every live university, so a
      // newly admin-added one is rankable immediately, no rebuild needed.
      'criteria': criteria,
      if (preferredReligion != null) 'preferredReligion': preferredReligion,
      if (dept != null) 'dept': dept,
      if (programme != null) 'programme': programme,
      if (homeLat != null) 'homeLat': homeLat,
      if (homeLng != null) 'homeLng': homeLng,
      if (budgetMin != null) 'budgetMin': budgetMin,
      if (budgetMax != null) 'budgetMax': budgetMax,
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
  /// No universityIds filter -> always every live university, admin
  /// add/remove reflected immediately.
  static Future<List<dynamic>> universities() async {
    final res = await _post('/rank', {'criteria': []});
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

  /// The current student's own previously-submitted rating for a university,
  /// or null if they've never rated it — lets the 5-star widget remember
  /// their choice across sessions instead of always starting at 0.
  static Future<int?> myRating(String universityId) async {
    final res = await _get('/rate/$universityId');
    return res is Map ? res['stars'] as int? : null;
  }

  static Future<List<dynamic>> staffRequests() async =>
      await _get('/staff-requests') as List<dynamic>;

  static Future<void> confirmStaff(String id) => _post('/staff-requests/$id/confirm', {});
  static Future<Map<String, dynamic>> forgotPassword(String email) =>
      _post('/forgot-password', {'email': email});
  static Future<void> resetPassword(String email, String otp, String password) =>
      _post('/reset-password', {'email': email, 'otp': otp, 'password': password});
  static Future<void> setStaffStatus(String id, String status) =>
      _post('/staff-requests/$id/status', {'status': status});
  static Future<void> deleteStaff(String id) => _delete('/staff-requests/$id');

  // ---- staff: own university data ----
  static Future<Map<String, dynamic>> staffData(String uniId) async =>
      Map<String, dynamic>.from(await _get('/staff/$uniId/data'));
  static Future<void> saveStaffCampuses(String uniId, List campuses) =>
      _put('/staff/$uniId/campuses', {'campuses': campuses});
  // Saves both together in one request so they can never desync from a
  // network hiccup hitting just one of two separate saves.
  static Future<void> saveStaffCampusesAndProgrammes(String uniId, List campuses, List programmes) =>
      _put('/staff/$uniId/campuses-programmes', {'campuses': campuses, 'programmes': programmes});
  static Future<void> saveStaffCombos(String uniId, Map combos) =>
      _put('/staff/$uniId/combos', {'combos': combos});
  static Future<void> saveStaffProgrammes(String uniId, List programmes) =>
      _put('/staff/$uniId/programmes', {'programmes': programmes});
  /// Renames a programme everywhere it's referenced (its programme row(s)
  /// AND its combinations entry), so it can never re-orphan itself the way
  /// a plain combos-key edit would.
  static Future<void> renameStaffProgramme(String uniId, String oldName, String newName) =>
      _put('/staff/$uniId/programmes/rename', {'oldName': oldName, 'newName': newName});
  /// Removes a programme by name everywhere it's referenced -- not just its
  /// combinations -- so it disappears from Campuses and every graduate-
  /// facing screen too.
  static Future<void> deleteStaffProgramme(String uniId, String name) =>
      _delete('/staff/$uniId/programmes/${Uri.encodeComponent(name)}');
  static Future<void> saveStaffCriteria(String uniId, Map criteria) =>
      _put('/staff/$uniId/criteria', {'criteria': criteria});
  static Future<Map<String, dynamic>> staffReport(String uniId) async =>
      Map<String, dynamic>.from(await _get('/staff/$uniId/report'));
  static Future<void> updateUniversityPhoto(String uniId, String? photo) =>
      _put('/staff/$uniId/photo', {'photo': photo});
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

  // ---- admin: subject-combination catalogue ----
  static Future<List<dynamic>> adminCombinations() async =>
      await _get('/admin/combinations') as List<dynamic>;
  static Future<void> addCombination(String code, List<String> subjects) =>
      _post('/admin/combinations', {'code': code, 'subjects': subjects});
  static Future<void> updateCombination(String code, List<String> subjects) =>
      _put('/admin/combinations/$code', {'subjects': subjects});
  static Future<void> deleteCombination(String code) => _delete('/admin/combinations/$code');
  static Future<Map<String, dynamic>> universityPopularity() async =>
      Map<String, dynamic>.from(await _get('/admin/university-popularity'));

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
  static List<dynamic>? comboCatalogue;
  static String? selectedProgramme;
  static String homeArea = '';
  static double? homeLat;
  static double? homeLng;
  static String? preferredReligion;
  static String? track;
  static String? selectedDept;
  static double? budgetMin;
  static double? budgetMax;
  static String? photo;

  static String get initial => name.isEmpty ? 'U' : name.trim()[0].toUpperCase();
  static String get first => name.isEmpty ? '' : name.split(' ').first;
}

/// Decodes a photo data: URI (e.g. "data:image/jpeg;base64,...") into an
/// ImageProvider, or null if unset/unparseable.
ImageProvider? _decodeAvatarPhoto(String? p) {
  if (p == null || p.isEmpty) return null;
  try {
    final b64 = p.contains(',') ? p.split(',').last : p;
    return MemoryImage(base64Decode(b64));
  } catch (_) {
    return null;
  }
}

/// Bumped whenever Session.photo changes so every mounted userAvatar(),
/// on whichever page/role it's shown on, repaints immediately — the app
/// has no shared state container, so this is the one signal that stands
/// in for "the avatar changed, please redraw."
final ValueNotifier<int> _avatarVersion = ValueNotifier<int>(0);
void _bumpAvatar() => _avatarVersion.value++;

/// The logged-in user's own avatar — their uploaded photo when set, else
/// their initial on a colored circle. Used everywhere the current user's
/// identity is shown (app bar menu, every role's drawer header).
Widget userAvatar({double radius = 17, Color bg = C.green, Color fg = Colors.white}) {
  return ValueListenableBuilder<int>(
    valueListenable: _avatarVersion,
    builder: (context, _, __) {
      final img = _decodeAvatarPhoto(Session.photo);
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        backgroundImage: img,
        child: img == null
            ? Text(Session.initial, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: radius * 0.68))
            : null,
      );
    },
  );
}

/// A university's badge/crest as displayed to admin and A2 graduate users —
/// the staff-uploaded photo when set, else the existing colored-abbreviation
/// box. Callers already hold the university Map (from /rank, /admin/universities
/// or /universities/:id, all of which now include `photo`), so this reads
/// straight off it rather than needing its own Session-style version counter.
Widget universityLogo(Map u, {
  double size = 44, double radius = 12, double fontSize = 12,
  bool circle = false, Color? bg, Color? textColor,
}) {
  final abbr = '${u['abbr'] ?? ''}';
  final img = _decodeAvatarPhoto(u['photo'] as String?);
  final bgColor = bg ?? C.uni(abbr);
  final txtColor = textColor ?? C.gold;
  if (circle) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bgColor,
      backgroundImage: img,
      child: img == null
          ? Text(abbr, style: TextStyle(color: txtColor, fontWeight: FontWeight.w700, fontSize: fontSize))
          : null,
    );
  }
  return Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(radius),
      image: img == null ? null : DecorationImage(image: img, fit: BoxFit.cover),
    ),
    alignment: Alignment.center,
    child: img == null
        ? Text(abbr, style: TextStyle(color: txtColor, fontWeight: FontWeight.w700, fontSize: fontSize))
        : null,
  );
}

/// ---- Shared chrome: profile menu + admin drawer ---------------------------
Future<void> _logout(BuildContext context) async {
  Api.token = null;
  Session.name = ''; Session.email = ''; Session.role = 'student'; Session.uniId = null;
  Session.criteriaCatalogue = null;
  Session.comboCatalogue = null;
  Session.selectedProgramme = null; Session.homeArea = ''; Session.lastRanking = null;
  Session.track = null;
  Session.homeLat = null; Session.homeLng = null; Session.selectedDept = null;
  Session.budgetMin = null; Session.budgetMax = null; Session.preferredReligion = null;
  Session.photo = null;
  _bumpAvatar();
  Navigator.pushAndRemoveUntil(
      context, MaterialPageRoute(builder: (_) => const OnboardingScreen()), (r) => false);
}

Future<void> _editProfile(BuildContext context) async {
  final name = TextEditingController(text: Session.name);
  String? track = Session.track;
  String? photo = Session.photo;
  bool saving = false;
  bool uploadingPhoto = false;
  List<dynamic> combos = [];
  if (Session.role == 'student') {
    try { combos = await Api.combinations(); } catch (_) {}
  }
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.cream,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Edit profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: uploadingPhoto ? null : () async {
              try {
                final file = await ImagePicker().pickImage(
                    source: ImageSource.gallery, maxWidth: 320, maxHeight: 320, imageQuality: 70);
                if (file == null) return;
                final bytes = await file.readAsBytes();
                final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
                final dataUri = 'data:image/$ext;base64,${base64Encode(bytes)}';
                setSheet(() { photo = dataUri; uploadingPhoto = true; });
                try {
                  // Auto-saves immediately on pick — the photo doesn't wait for the
                  // "Save" button, and every avatar shown app-wide (any role) updates
                  // right away via _bumpAvatar(). For staff, the same photo also
                  // becomes their university's photo — one upload, shown everywhere
                  // a photo is needed, no separate "institution photo" control.
                  final jobs = <Future>[Api.updateMe(photo: dataUri)];
                  if (Session.role == 'staff' && Session.uniId != null) {
                    jobs.add(Api.updateUniversityPhoto(Session.uniId!, dataUri));
                  }
                  await Future.wait(jobs);
                  Session.photo = dataUri;
                  _bumpAvatar();
                  if (ctx.mounted) toast(ctx, 'Photo updated');
                } catch (e) {
                  if (ctx.mounted) toast(ctx, 'Could not save photo: $e');
                } finally {
                  if (ctx.mounted) setSheet(() => uploadingPhoto = false);
                }
              } catch (e) {
                if (ctx.mounted) toast(ctx, 'Could not open photo picker: $e');
              }
            },
            child: Stack(children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: C.green,
                backgroundImage: _decodeAvatarPhoto(photo),
                child: _decodeAvatarPhoto(photo) == null
                    ? Text(Session.initial, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700))
                    : null,
              ),
              if (uploadingPhoto)
                const Positioned.fill(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Color(0x99000000),
                    child: SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                  ),
                ),
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: C.gold, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, size: 16, color: C.greenDark),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(controller: name, decoration: fieldDeco('Full name')),
        const SizedBox(height: 12),
        TextField(enabled: false, decoration: fieldDeco(Session.email)),
        if (Session.role == 'student') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: track,
            isExpanded: true,
            decoration: fieldDeco('A2 combination'),
            hint: const Text('Select your combination'),
            items: combos.map((c) => DropdownMenuItem(
                value: c['code'] as String,
                child: Text('${c['code']} (${List<String>.from(c['subjects'] ?? const []).join(' / ')})'))).toList(),
            onChanged: (v) => setSheet(() => track = v),
          ),
        ],
        const SizedBox(height: 20),
        primaryButton('Save', () async {
          setSheet(() => saving = true);
          try {
            await Api.updateMe(name: name.text.trim(), track: track, photo: photo);
            Session.name = name.text.trim();
            Session.track = track;
            Session.photo = photo;
            _bumpAvatar();
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            setSheet(() => saving = false);
            if (ctx.mounted) toast(ctx, e.toString());
          }
        }, loading: saving),
      ]),
    )),
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
        child: userAvatar(radius: 17, bg: C.green),
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
              userAvatar(radius: 22, bg: C.gold, fg: C.greenDark),
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
          _drawerItem(context, Icons.rule_folder_outlined, 'Subject combinations', const AdminCombosScreen()),
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
      navigatorObservers: [routeObserver],
    );
  }
}

/// Lets a screen refresh itself when it becomes visible again after a
/// pushed route above it is popped (e.g. StaffCriteriaScreen re-reading
/// campuses after returning from Campuses & programmes) — more reliable
/// than awaiting a specific Navigator.push's Future, which doesn't fire on
/// every way a route can be left (e.g. the browser back button on web).
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

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
      Session.track = user['track'];
      Session.photo = user['photo'];
      Session.homeArea = user['homeArea'] ?? '';
      Session.homeLat = (user['homeLat'] as num?)?.toDouble();
      Session.homeLng = (user['homeLng'] as num?)?.toDouble();
      _bumpAvatar();
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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) =>
            OtpResetScreen(email: email.text.trim(), demoOtp: res['otp'] as String?)));
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
  final String? demoOtp;
  const OtpResetScreen({super.key, required this.email, this.demoOtp});
  @override
  State<OtpResetScreen> createState() => _OtpResetScreenState();
}

class _OtpResetScreenState extends State<OtpResetScreen> {
  final otp = TextEditingController();
  final pass = TextEditingController();
  int seconds = 120;
  bool submitting = false;
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
            Text(widget.demoOtp != null
                    ? 'We sent a 6-digit code to ${widget.email}. No email service is configured for this '
                        'deployment, so your code is shown here instead: ${widget.demoOtp}'
                    : 'We sent a 6-digit code to ${widget.email}.',
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
            primaryButton('Reset password', () async {
              if (otp.text.trim().isEmpty || pass.text.isEmpty) { toast(context, 'Enter the code and a new password'); return; }
              setState(() => submitting = true);
              try {
                await Api.resetPassword(widget.email, otp.text.trim(), pass.text);
                if (!mounted) return;
                toast(context, 'Password reset — you can log in now.');
                Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
              } catch (e) {
                if (mounted) { setState(() => submitting = false); toast(context, e.toString()); }
              }
            }, loading: submitting),
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
  String? track;                      // A2 combination code (student)
  String? uniId;                       // university you work for (staff)
  List<dynamic> universities = [];     // loaded for the staff dropdown
  List<dynamic> combos = [];           // loaded for the student combination dropdown
  bool loading = false;
  bool universitiesLoading = false;
  bool universitiesError = false;
  bool combosLoading = false;
  bool combosError = false;

  @override
  void initState() {
    super.initState();
    _loadUniversities();
    _loadCombinations();
  }

  Future<void> _loadUniversities() async {
    setState(() { universitiesLoading = true; universitiesError = false; });
    try {
      final list = await Api.universities();
      if (mounted) setState(() { universities = list; universitiesLoading = false; });
    } catch (_) {
      if (mounted) setState(() { universitiesLoading = false; universitiesError = true; });
    }
  }

  Future<void> _loadCombinations({bool refresh = false}) async {
    setState(() { combosLoading = true; combosError = false; });
    try {
      final list = await Api.combinations(refresh: refresh);
      if (mounted) setState(() { combos = list; combosLoading = false; });
    } catch (_) {
      if (mounted) setState(() { combosLoading = false; combosError = true; });
    }
  }

  Future<void> _signup() async {
    if (role == 'staff' && uniId == null) {
      toast(context, 'Please choose the university you work for.');
      return;
    }
    if (role == 'student' && track == null) {
      toast(context, 'Please choose your A2 combination.');
      return;
    }
    setState(() => loading = true);
    try {
      final res = await Api.signup(name.text.trim(), email.text.trim(), pass.text, role,
          track: role == 'student' ? track : null,
          universityId: role == 'staff' ? uniId : null);
      if (!mounted) return;
      if (role == 'staff') {
        toast(context, 'Staff account created — an admin must confirm it before you can log in.');
        Navigator.pop(context);
      } else {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => VerifyScreen(
                email: email.text.trim(),
                user: (res['user'] as Map?)?.cast<String, dynamic>())));
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

              // ---- STUDENT: A2 combination ----
              if (role == 'student') ...[
                _label('A2 COMBINATION'),
                if (combosLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(color: C.green),
                  )
                else if (combosError)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Expanded(child: Text("Couldn't load combinations", style: TextStyle(color: C.muted, fontSize: 12))),
                      TextButton(onPressed: () => _loadCombinations(refresh: true), child: const Text('Retry')),
                    ]),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: track,
                    isExpanded: true,
                    decoration: fieldDeco('Select your combination'),
                    hint: const Text('Select your combination'),
                    items: combos.map((c) => DropdownMenuItem(
                        value: c['code'] as String,
                        child: Text('${c['code']} (${List<String>.from(c['subjects'] ?? const []).join(' / ')})'))).toList(),
                    onChanged: (v) => setState(() => track = v),
                  ),
                const SizedBox(height: 16),
              ],

              // ---- STAFF: university you work for ----
              if (role == 'staff') ...[
                _label('UNIVERSITY YOU WORK FOR'),
                if (universitiesLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(color: C.green),
                  )
                else if (universitiesError)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Expanded(child: Text("Couldn't load universities", style: TextStyle(color: C.muted, fontSize: 12))),
                      TextButton(onPressed: _loadUniversities, child: const Text('Retry')),
                    ]),
                  )
                else
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
  final Map<String, dynamic>? user;
  const VerifyScreen({super.key, required this.email, this.user});
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
                final user = widget.user;
                Session.role = 'student';
                if (user != null) {
                  Session.name = user['name'] ?? '';
                  Session.email = user['email'] ?? '';
                  Session.track = user['track'];
                  Session.photo = user['photo'];
                  _bumpAvatar();
                }
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
  final ScrollController _marqueeCtrl = ScrollController();
  Timer? _marqueeTimer;

  @override
  void initState() {
    super.initState();
    Api.universities().then((v) { if (mounted) setState(() => unis = v); }).catchError((_) {});
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
                  _action('Set criteria', '23 criteria',
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
                        universityLogo(m, size: 40, radius: 11, fontSize: 11),
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
                                universityLogo(m, size: 44, radius: 12, fontSize: 12),
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
class RankingsEntryScreen extends StatefulWidget {
  const RankingsEntryScreen({super.key});
  @override
  State<RankingsEntryScreen> createState() => _RankingsEntryScreenState();
}

class _RankingsEntryScreenState extends State<RankingsEntryScreen> {
  bool loading = true;
  List<dynamic>? preloaded;

  @override
  void initState() {
    super.initState();
    final hasLive = Session.lastRanking != null && Session.lastRanking!.isNotEmpty;
    if (hasLive) {
      loading = false;
      return;
    }
    // No in-memory result (fresh login/session) — try restoring the
    // student's last saved ranking snapshot from the server instead of
    // just showing "No ranking yet".
    Api.myLastRanking().then((r) {
      if (!mounted) return;
      final ranked = r?['ranked'] as List?;
      if (ranked != null && ranked.isNotEmpty) {
        Session.lastCriteria = List<Map<String, dynamic>>.from(
            ((r!['criteria'] as List?) ?? const []).map((c) => Map<String, dynamic>.from(c)));
        setState(() { preloaded = ranked; loading = false; });
      } else {
        setState(() => loading = false);
      }
    }).catchError((_) { if (mounted) setState(() => loading = false); });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: a2AppBar(context, 'My rankings', back: true),
        body: const Center(child: CircularProgressIndicator(color: C.green)),
      );
    }
    final hasLive = Session.lastRanking != null && Session.lastRanking!.isNotEmpty;
    if (hasLive || preloaded != null) {
      return ResultsScreen(criteria: Session.lastCriteria, preloaded: preloaded);
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
  List<dynamic> _allProgrammes = [];

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
    Api.programmes(null).then((list) {
      _allProgrammes = list;
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
    final jobs = <Future<void>>[];
    if (!_detailCache.containsKey(id)) {
      jobs.add(() async {
        try { _detailCache[id] = await Api.university(id); } catch (_) {}
      }());
    }
    if (!_staffCache.containsKey(id)) {
      jobs.add(() async {
        try {
          final d = await Api.universityAnswers(id);
          _staffCache[id] = Map<String, dynamic>.from((d['criteria'] as Map?) ?? {});
        } catch (_) {}
      }());
    }
    await Future.wait(jobs);
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
              leading: universityLogo(m, size: 32, fontSize: 10, circle: true),
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
    // Live-computed once per build — both sides share the same
    // Session.homeLat/homeLng null-check, so C07 is blank together or
    // numeric together, never mismatched.
    final kmHomeL = ld != null ? resolveHomeDistanceKm(ld, _allProgrammes) : null;
    final kmHomeR = rd != null ? resolveHomeDistanceKm(rd, _allProgrammes) : null;

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
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  Widget? cardFor(Map<String, dynamic>? uni) {
                    if (uni == null) return null;
                    final campusPins = uni['campusPins'] as Map?;
                    if (campusPins == null || campusPins.isEmpty) return null;
                    return CampusDistancesCard(
                      campusPins: Map<String, dynamic>.from(campusPins),
                      initialCampusName: resolveDisplayCampusName(uni, _allProgrammes),
                    );
                  }
                  final lCard = cardFor(ld);
                  final rCard = cardFor(rd);
                  if (lCard == null && rCard == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: lCard ?? const SizedBox.shrink()),
                      const SizedBox(width: 10),
                      Expanded(child: rCard ?? const SizedBox.shrink()),
                    ]),
                  );
                }),
                const SizedBox(height: 4),
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
                        // Same per-code formatting DetailScreen already
                        // trusts (C07 in km, C25 as a religion name, C26
                        // as mode names, etc.) instead of raw numbers.
                        final l = _valueForCode(code, lv, ls, kmHomeL);
                        final r = _valueForCode(code, rv, rs, kmHomeR);
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
          if (u != null) ...[
            universityLogo(u, size: 36, circle: true, bg: Colors.white.withValues(alpha: 0.9), textColor: C.uni('${u['abbr']}')),
            const SizedBox(height: 8),
          ],
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

/// Great-circle distance in km between two lat/lng points (Haversine).
/// Mirrors server/topsis.js's haversineKm — used client-side for the staff
/// pin-map live preview and for live-computing a student's distance from
/// home (see resolveHomeDistanceKm below); the server is still authoritative
/// wherever ranking itself is computed.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

LatLng? _campusPinPoint(Map<String, dynamic> uni, String name) {
  final campusPins = Map<String, dynamic>.from(uni['campusPins'] ?? const {});
  final p = campusPins[name];
  final school = p is Map ? p['schoolLocation'] : null;
  if (school is! Map) return null;
  return LatLng((school['lat'] as num).toDouble(), (school['lng'] as num).toDouble());
}

/// Which campus is actually relevant to a student's dept/programme choice —
/// mirrors server/index.js's resolveCampusForUni exactly: exact programme's
/// own campus > single/nearest dept-offering campus > nearest campus
/// overall (when the uni doesn't offer their dept, or no dept is chosen at
/// all — e.g. checking a uni their ranking didn't recommend). Shared by the
/// live home-distance calculation and the campus-location map widget so
/// both always agree on which campus they're describing.
String? resolveDisplayCampusName(Map<String, dynamic> uni, List<dynamic> allProgrammes) {
  final campuses = List<Map>.from(uni['campuses'] ?? const []);

  String? nearest(List<Map> among) {
    if (Session.homeLat == null || Session.homeLng == null) return null;
    String? best;
    double bestKm = double.infinity;
    for (final c in among) {
      final pt = _campusPinPoint(uni, c['name'] as String);
      if (pt == null) continue;
      final km = haversineKm(Session.homeLat!, Session.homeLng!, pt.latitude, pt.longitude);
      if (km < bestKm) { bestKm = km; best = c['name'] as String; }
    }
    return best;
  }

  String? campusName;
  // Tier 1: exact programme's own campus.
  if (Session.selectedProgramme != null) {
    final exact = allProgrammes.cast<Map>().firstWhere(
      (p) => p['universityId'] == uni['id'] && p['name'] == Session.selectedProgramme && ('${p['campus'] ?? ''}').isNotEmpty,
      orElse: () => {});
    if (exact.isNotEmpty) campusName = exact['campus'] as String;
  }
  // Tier 2: campus(es) offering the selected dept.
  if (campusName == null && Session.selectedDept != null) {
    final offering = campuses.where((c) => List<String>.from(c['depts'] ?? const []).contains(Session.selectedDept)).toList();
    if (offering.length == 1) {
      campusName = offering[0]['name'] as String;
    } else if (offering.length > 1) {
      campusName = nearest(offering) ?? offering[0]['name'] as String;
    }
  }
  // Tier 3: not offering the selected dept (or no dept chosen at all) -> nearest campus overall.
  campusName ??= nearest(campuses) ?? (campuses.isNotEmpty ? campuses[0]['name'] as String : null);
  return campusName;
}

/// Distance from the student's home pin to whichever campus is actually
/// relevant to them (see resolveDisplayCampusName). No home pin -> null,
/// never a stale/fabricated number.
double? resolveHomeDistanceKm(Map<String, dynamic> uni, List<dynamic> allProgrammes) {
  if (Session.homeLat == null || Session.homeLng == null) return null;
  final campusName = resolveDisplayCampusName(uni, allProgrammes);
  final pt = campusName != null ? _campusPinPoint(uni, campusName) : null;
  if (pt != null) return haversineKm(Session.homeLat!, Session.homeLng!, pt.latitude, pt.longitude);
  // Legacy single-pin universities with no per-campus data at all.
  final legacy = uni['schoolLocation'];
  if (legacy is Map) {
    return haversineKm(Session.homeLat!, Session.homeLng!, (legacy['lat'] as num).toDouble(), (legacy['lng'] as num).toDouble());
  }
  return null;
}

Widget _kmChip(IconData icon, String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      ]),
    );

/// Campus-to-bus / campus-to-moto distances for a university, with
/// left/right navigation when more than one campus has pins set — used on
/// DetailScreen and CompareScreen. Renders nothing if no campus has any
/// distance set yet, matching the "never fabricate" rule used everywhere else.
class CampusDistancesCard extends StatefulWidget {
  final Map<String, dynamic> campusPins; // campusName -> pins map
  final String? initialCampusName;
  const CampusDistancesCard({super.key, required this.campusPins, this.initialCampusName});

  @override
  State<CampusDistancesCard> createState() => _CampusDistancesCardState();
}

class _CampusDistancesCardState extends State<CampusDistancesCard> {
  late int _index;

  List<MapEntry<String, dynamic>> get _entries => widget.campusPins.entries.where((e) {
        final v = e.value;
        return v is Map && (v['schoolToBusKm'] != null || v['schoolToMotoKm'] != null);
      }).toList();

  @override
  void initState() {
    super.initState();
    final i = widget.initialCampusName != null
        ? _entries.indexWhere((e) => e.key == widget.initialCampusName)
        : -1;
    _index = i >= 0 ? i : 0;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    final i = _index.clamp(0, entries.length - 1);
    final name = entries[i].key;
    final pins = entries[i].value as Map;
    final busKm = pins['schoolToBusKm'] as num?;
    final motoKm = pins['schoolToMotoKm'] as num?;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 13)),
          ),
          if (entries.length > 1) ...[
            InkWell(
              onTap: i > 0 ? () => setState(() => _index = i - 1) : null,
              child: Icon(Icons.chevron_left, size: 18, color: i > 0 ? C.ink : C.border),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('${i + 1}/${entries.length}', style: const TextStyle(fontSize: 11, color: C.muted)),
            ),
            InkWell(
              onTap: i < entries.length - 1 ? () => setState(() => _index = i + 1) : null,
              child: Icon(Icons.chevron_right, size: 18, color: i < entries.length - 1 ? C.ink : C.border),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (busKm != null) _kmChip(Icons.directions_bus, 'Bus · ${busKm.toStringAsFixed(2)} km', const Color(0xFF2A5C8F)),
          if (motoKm != null) _kmChip(Icons.two_wheeler, 'Moto · ${motoKm.toStringAsFixed(2)} km', const Color(0xFFC25A1F)),
        ]),
      ]),
    );
  }
}

/// Resolves what to show a student for one criterion code on DetailScreen —
/// null means "staff never set this," which the caller hides entirely
/// rather than rendering a placeholder.
dynamic _valueForCode(String code, Map vals, Map staffAnswers, num? kmHome) {
  switch (code) {
    case 'C07':
      return kmHome != null ? '${kmHome.toStringAsFixed(2)} km' : null;
    case 'C12':
      return vals['C12'] != null ? '${(vals['C12'] as num).toStringAsFixed(1)}%' : null;
    case 'C14':
      return staffAnswers['library'];
    case 'C16':
      return staffAnswers['sporting'];
    case 'C17':
      return staffAnswers['health'];
    case 'C23':
      return (staffAnswers['minGrade'] as String?)?.trim().isNotEmpty == true ? staffAnswers['minGrade'] : null;
    case 'C25':
      // Unset (staff never touched it) -> null, hidden like everything
      // else. Explicitly false ("not religious-based") still shows 'None'
      // as a real answer.
      if (staffAnswers['religiousBased'] == null) return null;
      return staffAnswers['religiousBased'] == true ? (staffAnswers['religion'] ?? 'None') : 'None';
    case 'C26':
      final modes = <String>[
        if (staffAnswers['modeDay'] == true) 'Day',
        if (staffAnswers['modeEvening'] == true) 'Evening',
        if (staffAnswers['modeWeekend'] == true) 'Weekend',
      ];
      return modes.isEmpty ? null : modes.join(', ');
    default:
      return vals[code] ?? staffAnswers[code];
  }
}

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
                                          child: universityLogo(m, size: 44, radius: 12, fontSize: 12),
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
  Map<String, Map> uniById = {};

  @override
  void initState() {
    super.initState();
    _future = Api.programmes(null);
    Api.universities().then((list) {
      if (mounted) setState(() => uniById = { for (final u in list) (u as Map)['id'] as String: u });
    }).catchError((_) {});
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// True only if the student's own combination is explicitly listed
  /// against at least one programme in this department, at any university.
  /// A programme/university with no combos configured at all does NOT
  /// count as a match -- by product decision, unconfigured means blocked
  /// here (unlike the purely informational eligibilityCard elsewhere,
  /// which stays open when unset).
  bool _hasMatchingOffering(List<Map> deptProgrammes) {
    final track = Session.track;
    if (track == null) return false;
    for (final p in deptProgrammes) {
      final uni = uniById['${p['universityId']}'];
      final raw = (uni?['combos'] as Map?)?['${p['name']}'];
      if (raw is! Map) continue;
      final matched = raw.keys.any((k) =>
          '$k' == track && subjectPairs(List<String>.from(raw[k] as List)).isNotEmpty);
      if (matched) return true;
    }
    return false;
  }

  Future<void> _showNotEligibleDialog(String dept, List<Map> deptProgrammes) {
    final track = Session.track;
    final accepted = <String>{};
    for (final p in deptProgrammes) {
      final raw = (uniById['${p['universityId']}']?['combos'] as Map?)?['${p['name']}'];
      if (raw is Map) {
        raw.forEach((k, v) {
          if (subjectPairs(List<String>.from(v as List)).isNotEmpty) accepted.add('$k');
        });
      }
    }
    final String msg;
    if (track == null) {
      msg = "Add your A2 combination to your profile first so we can check whether you're eligible to enter $dept.";
    } else if (accepted.isEmpty) {
      msg = 'Your $track combination is not eligible to enter $dept — no university has set up combination requirements for it yet.';
    } else {
      msg = 'Your $track combination is not eligible to enter $dept. Accepted combinations: ${accepted.join(', ')}.';
    }
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not eligible for this department'),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
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
                  children: depts.map((d) {
                    final deptProgrammes = progs.where((p) => '${(p as Map)['dept']}' == d).cast<Map>().toList();
                    final eligible = _hasMatchingOffering(deptProgrammes);
                    return GestureDetector(
                      onTap: () {
                        if (!eligible) {
                          _showNotEligibleDialog(d, deptProgrammes);
                          return;
                        }
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProgrammeScreen(dept: d)));
                      },
                      child: Opacity(
                        opacity: eligible ? 1 : 0.55,
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
                            Text(
                              eligible
                                  ? '${byDept[d]!.length} universit${byDept[d]!.length == 1 ? 'y' : 'ies'}'
                                  : 'Not open for your combination',
                              style: const TextStyle(color: C.muted, fontSize: 10.5),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
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

  /// The subjects the university's own staff marked acceptable for this
  /// programme, keyed by A2 combination code — no fabricated eligibility
  /// hints. Any 2 of the listed subjects together qualify (e.g. Maths,
  /// Chemistry, Biology under MCB means Maths+Chemistry OR Maths+Biology OR
  /// Chemistry+Biology). Shows only the logged-in student's own combination
  /// when it's set for this programme; otherwise falls back to every
  /// combination staff DID set.
  Map<String, List<MapEntry<String, List<String>>>> _eligibilityByUni(String programmeName, List<Map> offerings) {
    final out = <String, List<MapEntry<String, List<String>>>>{};
    for (final o in offerings) {
      final uniId = '${o['universityId']}';
      final raw = (uniById[uniId]?['combos'] as Map?)?[programmeName];
      if (raw is! Map) continue; // unset, or old pre-combination shape
      final byCode = <String, List<String>>{};
      raw.forEach((k, v) {
        final subs = List<String>.from(v as List);
        if (subjectPairs(subs).isNotEmpty) byCode['$k'] = subs;
      });
      if (byCode.isEmpty) continue;
      final track = Session.track;
      out[uniId] = (track != null && byCode.containsKey(track))
          ? [MapEntry(track, byCode[track]!)]
          : byCode.entries.toList();
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
                          final eligibility = sel
                              ? _eligibilityByUni(name, offerings)
                              : const <String, List<MapEntry<String, List<String>>>>{};
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
                                  if (Session.track == null)
                                    Text('Principal passes (set by each university)',
                                        style: const TextStyle(color: C.muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
                                  if (Session.track == null) const SizedBox(height: 6),
                                  ...eligibility.entries.map((e) {
                                    final uniName = uniNames[e.key] ?? '';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: eligibilityCard(Map.fromEntries(e.value),
                                          title: eligibility.length > 1 ? uniName : null),
                                    );
                                  }),
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
                            Session.selectedDept = widget.dept;
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
  // Categories collapsed by default; expand with the + button. Accordion
  // behavior — opening one category closes whichever other was open.
  String? expandedCategory;
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
                              final isOpen = query.isNotEmpty || expandedCategory == cat;
                              return [
                                GestureDetector(
                                  onTap: () => setState(() => expandedCategory = expandedCategory == cat ? null : cat),
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
                                  if (!sel || (code != 'C25' && code != 'C01')) return row;
                                  Widget panelBody;
                                  if (code == 'C25') {
                                    panelBody = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                                    ]);
                                  } else {
                                    final lo = (Session.budgetMin ?? 500000).clamp(500000, 20000000).toDouble();
                                    final hi = (Session.budgetMax ?? 20000000).clamp(500000, 20000000).toDouble();
                                    panelBody = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      const Text('YOUR BUDGET RANGE (RWF / YEAR)', style: TextStyle(
                                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: C.muted)),
                                      const SizedBox(height: 4),
                                      Text('${_fmtRwf(lo)} – ${_fmtRwf(hi)}',
                                          style: const TextStyle(color: C.ink, fontWeight: FontWeight.w700, fontSize: 13)),
                                      RangeSlider(
                                        values: RangeValues(lo, hi),
                                        min: 500000, max: 20000000, divisions: 39,
                                        activeColor: C.green, inactiveColor: C.sand,
                                        labels: RangeLabels(_fmtRwf(lo), _fmtRwf(hi)),
                                        onChanged: (v) => setState(() {
                                          Session.budgetMin = v.start;
                                          Session.budgetMax = v.end;
                                        }),
                                      ),
                                    ]);
                                  }
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
                                        child: panelBody,
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
                    onPressed: selected.length < 2 ? null : () {
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
                    child: Text(selected.length < 2 ? 'Select at least 2 criteria' : 'Continue · ${selected.length} selected',
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
  final MapController _mapController = MapController();
  static const _gasabo = LatLng(-1.9358, 30.0930);

  String? picked;
  LatLng? pin;
  List<Map<String, dynamic>> searchResults = [];
  Timer? _debounce;
  bool locating = false;

  @override
  void dispose() {
    addr.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng p) async {
    setState(() { pin = p; locating = true; });
    final label = await reverseGeocodeAddress(p);
    if (mounted) setState(() { picked = label ?? coordsLabel(p); locating = false; });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) { setState(() => searchResults = []); return; }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search'
          '?format=json&limit=5&countrycodes=rw&q=${Uri.encodeQueryComponent('$q, Kigali, Rwanda')}');
      final res = await http.get(uri, headers: kNominatimUA);
      final list = (jsonDecode(res.body) as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
      if (mounted) setState(() => searchResults = list);
    } catch (_) {
      if (mounted) setState(() => searchResults = []);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) toast(context, 'Turn on location services to use this.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'Location access was denied — allow it in your browser to use this.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final p = LatLng(pos.latitude, pos.longitude);
      final label = await reverseGeocodeAddress(p);
      if (!mounted) return;
      setState(() {
        pin = p;
        picked = label ?? coordsLabel(p);
        addr.text = picked ?? '';
        searchResults = [];
      });
      _mapController.move(p, 15);
    } catch (e) {
      if (mounted) toast(context, 'Could not get your location: $e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void _selectResult(Map<String, dynamic> r) {
    final lat = double.tryParse('${r['lat']}');
    final lon = double.tryParse('${r['lon']}');
    setState(() {
      picked = r['display_name'] as String?;
      addr.text = picked ?? '';
      searchResults = [];
    });
    if (lat != null && lon != null) {
      final p = LatLng(lat, lon);
      setState(() => pin = p);
      _mapController.move(p, 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = searchResults;
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
              const Text('Search your address, or tap the map to drop a pin.', style: TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: addr,
              onChanged: _onSearchChanged,
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
                child: Column(children: results.map((r) => ListTile(
                  leading: Container(
                    width: 30, height: 30,
                    decoration: const BoxDecoration(color: Color(0xFFC7EBD8), shape: BoxShape.circle),
                    child: const Icon(Icons.place, color: C.green, size: 16),
                  ),
                  title: Text('${r['display_name'] ?? ''}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  onTap: () => _selectResult(r),
                )).toList()),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(20)),
                  child: Stack(children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _gasabo,
                        initialZoom: 13,
                        onTap: (_, point) => _reverseGeocode(point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.unimatch.gasabo',
                        ),
                        if (pin != null)
                          MarkerLayer(markers: [
                            Marker(
                              point: pin!,
                              width: 36, height: 36,
                              child: const Icon(Icons.location_on, color: Color(0xFFC25A1F), size: 36),
                            ),
                          ]),
                      ],
                    ),
                    if (locating)
                      const Positioned(top: 12, right: 12,
                          child: SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: C.green))),
                    Positioned(
                      top: 12, left: 12,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: locating ? null : _useCurrentLocation,
                          child: const Padding(
                            padding: EdgeInsets.all(9),
                            child: Icon(Icons.my_location, color: Color(0xFFC25A1F), size: 20),
                          ),
                        ),
                      ),
                    ),
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
                            Expanded(child: Text(picked!,
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink, fontSize: 12))),
                          ]),
                        ),
                      ),
                  ]),
                ),
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
                  Session.homeLat = pin?.latitude;
                  Session.homeLng = pin?.longitude;
                  Api.updateMe(homeArea: Session.homeArea, homeLat: Session.homeLat, homeLng: Session.homeLng)
                      .catchError((_) => <String, dynamic>{});
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
  // When set, shows this exact saved snapshot instead of calling Api.rank()
  // — used to restore "My rankings" after a fresh login/session, where
  // Session's dept/programme/home-location context has been reset and a
  // live re-fetch could no longer reproduce the same result.
  final List<dynamic>? preloaded;
  const ResultsScreen({super.key, required this.criteria, this.preloaded});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

String _fmtRwf(num v) => v >= 1000000
    ? '${(v / 1000000).toStringAsFixed(1)}M RWF'
    : '${(v / 1000).round()}k RWF';

class _ResultsScreenState extends State<ResultsScreen> {
  late Future<List<dynamic>> _future;
  Map<String, dynamic> staffAnswersById = {};
  Map<String, String> labelByCode = {};

  @override
  void initState() {
    super.initState();
    Api.criteria().then((list) {
      if (mounted) {
        setState(() => labelByCode = { for (final c in list) '${c['code']}': '${c['label']}' });
      }
    }).catchError((_) {});
    final wantsReligion = widget.criteria.any((c) => c['code'] == 'C25') &&
        Session.preferredReligion != null && Session.preferredReligion != 'No preference';
    final rankFuture = widget.preloaded != null
        ? Future.value(widget.preloaded!)
        : Api.rank(widget.criteria,
            preferredReligion: wantsReligion ? Session.preferredReligion : null,
            dept: Session.selectedDept,
            programme: Session.selectedProgramme,
            homeLat: Session.homeLat,
            homeLng: Session.homeLng,
            budgetMin: Session.budgetMin,
            budgetMax: Session.budgetMax);
    _future = rankFuture.then((r) async {
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

  /// Why this university ranked where it did -- its single strongest and
  /// weakest contributing criterion, from the same TOPSIS computation that
  /// produced its score. Real, data-driven; renders nothing if the code is
  /// missing (e.g. only one criterion was selected).
  Widget _reasonPill(IconData icon, String tag, String? label, Color color) {
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(tag, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.3)),
        ]),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

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
                        final outsideDept = u['outsideDept'] == true;
                        final strongestLabel = labelByCode[u['bestCode']];
                        final weakestLabel = labelByCode[u['worstCode']];
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
                              if (badge != null && !outsideDept)
                                Padding(
                                  padding: const EdgeInsets.only(left: 13, top: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(999)),
                                    child: Text(badge, style: const TextStyle(
                                        color: C.greenDark, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                                  ),
                                ),
                              if (outsideDept)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFB4472A).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: const Color(0xFFB4472A).withValues(alpha: 0.4)),
                                    ),
                                    child: Text('Doesn\'t offer ${Session.selectedDept ?? 'your department'}',
                                        style: const TextStyle(color: Color(0xFFB4472A), fontSize: 9.5, fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
                                child: Row(children: [
                                  universityLogo(u, size: 42, radius: 12, fontSize: 11, bg: crest),
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
                              if (strongestLabel != null || weakestLabel != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
                                  child: Row(children: [
                                    Expanded(child: _reasonPill(Icons.trending_up, 'STRONGEST', strongestLabel, C.green)),
                                    const SizedBox(width: 8),
                                    Expanded(child: _reasonPill(Icons.trending_down, 'NEEDS WORK', weakestLabel, const Color(0xFFB4472A))),
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
  bool showAdditionalDetails = false;
  int? programmeCount;
  List<dynamic> allProgrammes = [];

  @override
  void initState() {
    super.initState();
    _future = Api.university(widget.id);
    Api.myRating(widget.id).then((s) {
      if (mounted) setState(() => myRating = s ?? 0);
    }).catchError((_) {});
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
    Api.programmes(null).then((list) {
      allProgrammes = list;
      final n = list.where((p) => (p as Map)['universityId'] == widget.id).length;
      if (mounted) setState(() => programmeCount = n);
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

  Widget? _eligibilityBox() {
    final prog = Session.selectedProgramme;
    if (prog == null) return null;
    final raw = combos[prog];
    if (raw is! Map) return null; // unset, or old pre-combination shape
    final byCode = <String, List<String>>{};
    raw.forEach((k, v) {
      final subs = List<String>.from(v as List);
      if (subjectPairs(subs).isNotEmpty) byCode['$k'] = subs;
    });
    if (byCode.isEmpty) return null;
    final track = Session.track;
    final entries = (track != null && byCode.containsKey(track)) ? {track: byCode[track]!} : byCode;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
      child: eligibilityCard(entries,
          title: track != null && byCode.containsKey(track)
              ? 'Your principal passes for $prog ($track)'
              : 'Principal passes required for $prog'),
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
          // Live-computed from the student's home pin against whichever
          // campus is relevant to them — never a stale/replayed number. No
          // home pin set -> blank.
          final kmHome = resolveHomeDistanceKm(u, allProgrammes);

          // Full criteria catalogue, grouped by category, value from vals
          // or staff answers if present, otherwise blank — never fabricated.
          final codeSet = allCriteria.map((c) => c['code']).toSet();
          // C08 (on-campus accommodation) already has its own dedicated
          // ACCOMMODATION info card above — don't repeat it in the
          // categorized breakdown.
          final displayCriteria = allCriteria.where((c) => c['code'] != 'C08').toList();
          final categories = <String>[];
          final byCategory = <String, List<Map<String, dynamic>>>{};
          for (final c in displayCriteria) {
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
                    universityLogo(u, size: 52, radius: 13, fontSize: 15,
                        bg: const Color(0xFFF5E7B8), textColor: crest),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${u['name'] ?? widget.name}', style: GoogleFonts.bricolageGrotesque(
                        color: const Color(0xFFFBF8F3), fontSize: 20, fontWeight: FontWeight.w500, height: 1.15))),
                  ]),
                  const SizedBox(height: 18),
                  Row(children: [
                    _heroStat('${campuses.length}', 'CAMPUSES'),
                    _heroDiv(),
                    _heroStat(programmeCount != null ? '$programmeCount' : '—', 'PROGRAMMES'),
                    _heroDiv(),
                    _heroStat(ratingCount > 0 ? avgRating!.toStringAsFixed(1) : '—', 'RATING'),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (vals['C01'] != null || staffAnswers['accommodation'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (vals['C01'] != null)
                      _infoCard('TUITION', _fmtRwf(vals['C01'] as num), Icons.payments_outlined),
                    if (vals['C01'] != null && staffAnswers['accommodation'] != null)
                      const SizedBox(width: 10),
                    if (staffAnswers['accommodation'] != null)
                      _infoCard('ACCOMMODATION', staffAnswers['accommodation'] == true ? 'On-campus' : 'Off-campus',
                          Icons.home_outlined),
                  ]),
                ),
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
              Builder(builder: (_) {
                final campusPins = u['campusPins'] as Map?;
                if (campusPins == null || campusPins.isEmpty) return const SizedBox.shrink();
                final campusName = resolveDisplayCampusName(u, allProgrammes);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Getting there', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                    const SizedBox(height: 8),
                    CampusDistancesCard(
                      campusPins: Map<String, dynamic>.from(campusPins),
                      initialCampusName: campusName,
                    ),
                  ]),
                );
              }),
              if (_eligibilityBox() != null) _eligibilityBox()!,
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('All criteria', style: TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                Text('${displayCriteria.length} total', style: const TextStyle(color: C.muted, fontSize: 11)),
              ]),
              const SizedBox(height: 10),
              if (displayCriteria.isEmpty)
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
                      final value = _valueForCode(code, vals, staffAnswers, kmHome);
                      final names = code == 'C02'
                          ? List<String>.from(staffAnswers['partnerSchools'] ?? const [])
                          : code == 'C11'
                              ? List<String>.from(staffAnswers['companies'] ?? const [])
                              : code == 'C17'
                                  ? List<String>.from(staffAnswers['healthPartners'] ?? const [])
                                  : code == 'C12'
                                      ? List<Map>.from(staffAnswers['cohorts'] ?? const [])
                                          .map((c) => '${c['period']} · ${c['pct']}%').toList()
                                      : const <String>[];
                      final busKm = code == 'C09' ? staffAnswers['schoolToBusKm'] as num? : null;
                      final motoKm = code == 'C09' ? staffAnswers['schoolToMotoKm'] as num? : null;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                          if (names.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 6, children: names.map((n) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                                  child: Text(n, style: const TextStyle(fontSize: 10.5, color: C.greenDark, fontWeight: FontWeight.w600)),
                                )).toList()),
                          ],
                          if (busKm != null || motoKm != null) ...[
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              if (busKm != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                                  child: Text('Bus stop · ${busKm.toStringAsFixed(2)} km',
                                      style: const TextStyle(fontSize: 10.5, color: C.greenDark, fontWeight: FontWeight.w600)),
                                ),
                              if (motoKm != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                                  child: Text('Moto stop · ${motoKm.toStringAsFixed(2)} km',
                                      style: const TextStyle(fontSize: 10.5, color: C.greenDark, fontWeight: FontWeight.w600)),
                                ),
                            ]),
                          ],
                        ]),
                      );
                    }),
                  ];
                }),
              if (contextualRows.isNotEmpty) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => setState(() => showAdditionalDetails = !showAdditionalDetails),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(showAdditionalDetails ? 'Hide additional details' : 'Show additional details',
                        style: const TextStyle(color: C.green, fontWeight: FontWeight.w600, fontSize: 12.5)),
                    const SizedBox(width: 4),
                    Icon(showAdditionalDetails ? Icons.expand_less : Icons.expand_more, size: 16, color: C.green),
                  ]),
                ),
                if (showAdditionalDetails) ...[
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
// No fallback to a real university — an unset uniId should fail requests
// safely (404/empty state) rather than silently expose or edit someone
// else's real data.
String get _staffUni => Session.uniId ?? '';

Drawer staffDrawer(BuildContext context) => Drawer(
      backgroundColor: C.cream,
      child: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20), color: C.green,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              userAvatar(radius: 22, bg: C.gold, fg: C.greenDark),
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
              userAvatar(radius: 22, bg: C.gold, fg: C.greenDark),
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
    _load();
  }

  void _load() {
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
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              children: [
                Text('Manage', style: head(17, weight: FontWeight.w500)),
                const SizedBox(height: 8),
                _card(context, 'Campuses & programmes', 'Add campuses, departments and programmes',
                    Icons.apartment, const StaffCampusesScreen(), onReturn: _load),
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

  Widget _card(BuildContext ctx, String t, String s, IconData i, Widget dest, {VoidCallback? onReturn}) => GestureDetector(
        onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => dest)).then((_) => onReturn?.call()),
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
  // Flat list of {name, dept, campus} — each programme belongs to exactly
  // one campus, so ranking can tell "Computing, IT & Engineering at Remera"
  // apart from the same department at Main Campus.
  List<Map<String, dynamic>> allProgrammes = [];
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
      final progs = (data['programmes'] as List?) ?? [];
      allProgrammes = progs.map<Map<String, dynamic>>((p) => {
            'name': '${(p as Map)['name'] ?? ''}',
            'dept': '${p['dept'] ?? ''}',
            'campus': '${p['campus'] ?? ''}',
          }).where((p) => (p['dept'] as String).isNotEmpty).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    try {
      final rows = allProgrammes
          .map((p) => {'name': p['name'], 'dept': p['dept'], 'campus': p['campus']})
          .toList();
      // One atomic request — two independent saves could partially fail
      // (e.g. a deleted campus's programmes surviving because only the
      // campuses save reached the server), silently losing data.
      await Api.saveStaffCampusesAndProgrammes(_staffUni, campuses, rows);
      if (mounted) toast(context, 'Saved');
    } catch (e) { if (mounted) toast(context, e.toString()); }
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

  Future<void> _editCampus({int? index}) async {
    final existing = index != null ? campuses[index] : null;
    final oldName = existing?['name'] as String?;
    final name = TextEditingController(text: existing?['name'] ?? '');
    final picked = Set<String>.from(existing?['depts'] ?? const <String>[]);
    final oldDepts = Set<String>.from(existing?['depts'] ?? const <String>[]);
    // Departments can be legitimately assigned to more than one campus, so
    // exact campus-name matching is always authoritative -- a stale tag
    // (e.g. left over from a rename) is only safe to attribute here without
    // asking staff when there's literally no other campus it could belong
    // to (this university has just the one).
    final soleCampus = oldName != null && campuses.length <= 1;
    final localProgs = <String, List<String>>{};
    for (final p in allProgrammes) {
      final dept = p['dept'] as String;
      if (!oldDepts.contains(dept)) continue;
      if (p['campus'] != oldName && !soleCampus) continue;
      final list = localProgs.putIfAbsent(dept, () => []);
      if (!list.any((n) => n.toLowerCase() == (p['name'] as String).toLowerCase())) list.add(p['name'] as String);
    }
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: C.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        // Constant size regardless of how many departments/programmes are
        // added — the middle section scrolls internally instead of growing
        // the whole sheet past the screen, which used to hide the title and
        // the Save button with no way to get back to them.
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(children: [
                Expanded(
                  child: Text(existing == null ? 'Add campus' : 'Edit campus',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: C.muted),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: name, decoration: fieldDeco('Campus name (e.g. Remera Campus)')),
                  if (existing != null) ...[
                    const SizedBox(height: 6),
                    const Text('Renaming clears this campus\'s saved map pins (school/bus/moto) — re-place them under Criteria answers afterwards.',
                        style: TextStyle(color: C.muted, fontSize: 10.5, fontStyle: FontStyle.italic, height: 1.3)),
                  ],
                  const SizedBox(height: 14),
                  const Text('Departments offered here', style: TextStyle(color: C.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    // Closed list — exactly the 8 uniform departments, no free-text
                    // additions, so every university's department taxonomy stays consistent.
                    ...kDepartments.map((d) {
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
                    }),
                  ]),
                  if (picked.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text('Programmes per department', style: TextStyle(color: C.muted, fontSize: 12)),
                    const Text('Leave a department empty and the department name itself is used as its programme.',
                        style: TextStyle(color: C.muted, fontSize: 11, height: 1.4)),
                    const SizedBox(height: 10),
                    ...(picked.toList()..sort()).map((d) {
                      final progs = localProgs.putIfAbsent(d, () => []);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d, style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink, fontSize: 12.5)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            ...progs.map((name) => Chip(
                                  label: Text(name, style: const TextStyle(fontSize: 12)),
                                  backgroundColor: const Color(0xFFF1EBE0),
                                  onDeleted: () => setSheet(() => progs.remove(name)),
                                )),
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 16, color: C.green),
                              label: const Text('Add programme', style: TextStyle(fontSize: 12, color: C.green)),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: C.border),
                              onPressed: () async {
                                final v = await _promptText('Programme name');
                                if (v == null || v.trim().isEmpty) return;
                                final trimmed = v.trim();
                                if (progs.any((n) => n.toLowerCase() == trimmed.toLowerCase())) {
                                  toast(ctx, '$trimmed is already added to this department.');
                                  return;
                                }
                                setSheet(() => progs.add(trimmed));
                              },
                            ),
                          ]),
                        ]),
                      );
                    }),
                  ],
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: primaryButton('Save campus', () => Navigator.pop(ctx, true)),
            ),
          ]),
        ),
      )),
    );
    if (saved != true) return;
    final newName = name.text.trim();
    setState(() {
      final row = {'name': newName, 'depts': picked.toList()};
      if (index != null) campuses[index] = row; else campuses.add(row);
      // Remove every row this sheet considered "belonging" to this campus --
      // the same broadened criteria used to populate localProgs above, not
      // just an exact old-name tag match -- so a stale-tagged row can't
      // survive alongside a freshly re-added duplicate. Retagged to
      // (possibly renamed) newName below.
      allProgrammes.removeWhere((p) {
        final dept = p['dept'] as String;
        if (!oldDepts.contains(dept)) return false;
        return p['campus'] == oldName || soleCampus;
      });
      for (final d in picked) {
        for (final pname in (localProgs[d] ?? const <String>[])) {
          allProgrammes.add({'name': pname, 'dept': d, 'campus': newName});
        }
      }
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
                const Text('Add the campuses your university runs in Gasabo, the departments each one offers, and the programmes under each department.',
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
                              onPressed: () {
                                setState(() {
                                  final removedName = campuses[i]['name'];
                                  campuses.removeAt(i);
                                  allProgrammes.removeWhere((p) => p['campus'] == removedName);
                                });
                                _save();
                              }),
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

class StaffCombosScreen extends StatefulWidget {
  const StaffCombosScreen({super.key});
  @override
  State<StaffCombosScreen> createState() => _StaffCombosScreenState();
}

class _StaffCombosScreenState extends State<StaffCombosScreen> {
  // programme name -> allowed combination code -> subjects that count for it
  // (any 2 of them together qualify as valid principal passes)
  Map<String, Map<String, List<String>>> combos = {};
  List<String> programmes = [];
  String? expandedProgramme; // only one panel open at a time
  List<dynamic> _catalogue = []; // admin-managed combination codes + their base subjects
  bool loading = true;

  List<String> get _catalogueCodes => _catalogue.map((c) => c['code'] as String).toList();
  List<String> _catalogueSubjects(String code) =>
      List<String>.from(_catalogue.firstWhere((c) => c['code'] == code, orElse: () => {'subjects': const []})['subjects'] ?? const []);

  /// Every entry to show on this screen -- current real programmes AND any
  /// saved combos entry that no longer matches one (a rename, or a
  /// programme removed on Campuses) -- shown together as one list rather
  /// than split into a separate section, since staff can now rename an
  /// entry right here instead of needing it to already be a "real" programme.
  List<String> get _allEntries => {...programmes, ...combos.keys}.toList()..sort();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([Api.programmes(null), Api.staffData(_staffUni), Api.combinations()]);
      final progs = results[0] as List<dynamic>;
      final data = results[1] as Map<String, dynamic>;
      _catalogue = results[2] as List<dynamic>;
      programmes = progs.where((p) => (p as Map)['universityId'] == _staffUni)
          .map((p) => '${(p as Map)['name']}').toSet().toList();
      final saved = (data['combos'] as Map?) ?? {};
      combos = {
        // Keep everything already saved -- even under a programme name
        // that's been renamed/removed since -- so that _save()'s full
        // round-trip write can never erase staff-entered data for a
        // programme this session simply doesn't have loaded.
        for (final entry in saved.entries)
          if (entry.value is Map)
            '${entry.key}': (entry.value as Map).map((k, v) => MapEntry('$k', List<String>.from(v as List))),
        // Then make sure every CURRENT programme has an editable entry.
        for (final p in programmes)
          if (saved[p] is! Map) p: <String, List<String>>{},
      };
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    // Saves live on every toggle — no toast here, since a run of chip taps
    // would otherwise pop it repeatedly and look broken.
    try { await Api.saveStaffCombos(_staffUni, combos); }
    catch (e) { if (mounted) toast(context, e.toString()); }
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

  /// Add a subject to a combination that isn't part of its fixed abbreviation
  /// (e.g. a school may also teach Physics alongside MCB) — added subjects
  /// count immediately since the only reason to add one is to select it.
  Future<void> _addSubject(String programme, String code) async {
    final name = await _promptText('Subject name (e.g. Physics)');
    if (name == null || name.trim().isEmpty) return;
    final list = combos[programme]![code] ?? <String>[];
    if (!list.contains(name.trim())) list.add(name.trim());
    setState(() => combos[programme]![code] = list);
    _save();
  }

  void _toggleAllowed(String programme, String code) {
    setState(() {
      if (combos[programme]!.containsKey(code)) {
        combos[programme]!.remove(code); // no longer eligible with this combination
      } else {
        combos[programme]![code] = <String>[]; // eligible; subjects picked next
      }
    });
    _save();
  }

  void _toggleSubject(String programme, String code, String subject) {
    final list = combos[programme]![code] ?? <String>[];
    if (list.contains(subject)) {
      list.remove(subject);
    } else {
      list.add(subject);
    }
    setState(() => combos[programme]![code] = list);
    _save();
  }

  /// Remove a saved entry that no longer matches any current programme name
  /// (e.g. left over from a rename, or a programme that's since been
  /// removed on Campuses) -- these can never be reached from the accordion
  /// above since it only lists current programmes, so this is the only way
  /// to clear one out.
  /// Deletes the programme itself -- not just its saved combinations -- so
  /// it disappears everywhere, including Campuses and every graduate-facing
  /// screen. Works the same for an already-orphaned combos-only entry (no
  /// matching programme row to remove, so just its combos entry goes).
  Future<void> _deleteEntry(String name) async {
    final isReal = programmes.contains(name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this programme?'),
        content: Text(isReal
            ? '"$name" will be permanently removed everywhere, including Campuses, along with its saved combinations.'
            : '"$name"\'s saved combinations will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteStaffProgramme(_staffUni, name);
      if (expandedProgramme == name) setState(() => expandedProgramme = null);
      await _load();
      if (mounted) toast(context, 'Deleted "$name"');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  /// Renames a programme everywhere it's referenced (server-side: its
  /// programme row(s) AND its combos entry move together), so it can never
  /// re-orphan itself the way a plain local combos-key edit would.
  Future<void> _renameEntry(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename programme'),
        content: TextField(controller: controller, autofocus: true, decoration: fieldDeco('Programme name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;
    try {
      await Api.renameStaffProgramme(_staffUni, oldName, newName);
      setState(() {
        if (expandedProgramme == oldName) expandedProgramme = newName;
      });
      await _load();
      if (mounted) toast(context, 'Renamed to "$newName"');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: staffDrawer(context),
      appBar: staffAppBar(context, 'Combinations', back: true),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : _allEntries.isEmpty
              ? _emptyView('Add campuses with departments first — their programmes appear here.')
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('Every A2 graduate studies one fixed combination (e.g. PCB). For each programme, first '
                        'choose which combinations are allowed to take it — not every combination qualifies for every '
                        'programme. Then mark which subjects within each allowed combination count: any 2 of them '
                        'together are accepted as principal passes.',
                        style: TextStyle(color: C.muted, fontSize: 12, height: 1.4)),
                    const SizedBox(height: 14),
                    ..._allEntries.map((p) {
                      // Defensive: every entry shown here must have a backing
                      // map, whatever path led to it appearing in
                      // _allEntries -- guarantees the `!`s below can never
                      // null-check-crash the whole screen.
                      combos.putIfAbsent(p, () => <String, List<String>>{});
                      final set = combos[p]!.entries.where((e) => subjectPairs(e.value).isNotEmpty).length;
                      final isOpen = expandedProgramme == p;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          GestureDetector(
                            onTap: () => setState(() => expandedProgramme = isOpen ? null : p),
                            child: Row(children: [
                              Expanded(child: Text(p, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink))),
                              Text('$set combination${set == 1 ? '' : 's'} set',
                                  style: const TextStyle(fontSize: 11, color: C.muted)),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18, color: C.muted),
                                tooltip: 'Rename',
                                onPressed: () => _renameEntry(p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                tooltip: 'Delete',
                                onPressed: () => _deleteEntry(p),
                              ),
                              Icon(isOpen ? Icons.expand_less : Icons.expand_more, color: C.muted),
                            ]),
                          ),
                          if (isOpen) ...[
                            const SizedBox(height: 12),
                            const Text('WHICH COMBINATIONS CAN TAKE THIS PROGRAMME?',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.muted, letterSpacing: 0.4)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 6, children: _catalogueCodes.map((code) {
                              final allowed = combos[p]!.containsKey(code);
                              return GestureDetector(
                                onTap: () => _toggleAllowed(p, code),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: allowed ? C.greenDark : Colors.white, borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: allowed ? C.greenDark : C.border)),
                                  child: Text(code, style: TextStyle(
                                      color: allowed ? Colors.white : C.ink, fontSize: 11.5, fontWeight: FontWeight.w600)),
                                ),
                              );
                            }).toList()),
                            if (combos[p]!.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              ...combos[p]!.keys.map((code) {
                                final chosen = combos[p]![code] ?? const [];
                                // Fixed abbreviation subjects plus any custom ones staff added for
                                // this combination (e.g. Physics alongside MCB) — a custom subject
                                // stays in the pool as long as it's selected.
                                final subs = [
                                  ..._catalogueSubjects(code),
                                  ...chosen.where((s) => !_catalogueSubjects(code).contains(s)),
                                ];
                                final pairs = subjectPairs(chosen);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('$code — pick every subject that counts',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.greenDark)),
                                    const SizedBox(height: 4),
                                    Wrap(spacing: 6, runSpacing: 6, children: [
                                      ...subs.map((s) {
                                        final on = chosen.contains(s);
                                        return GestureDetector(
                                          onTap: () => _toggleSubject(p, code, s),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                                color: on ? C.green : Colors.white, borderRadius: BorderRadius.circular(999),
                                                border: Border.all(color: on ? C.green : C.border)),
                                            child: Text(s, style: TextStyle(color: on ? Colors.white : C.ink, fontSize: 11)),
                                          ),
                                        );
                                      }),
                                      ActionChip(
                                        avatar: const Icon(Icons.add, size: 14, color: C.green),
                                        label: const Text('Add subject', style: TextStyle(fontSize: 11, color: C.green)),
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(color: C.border),
                                        onPressed: () => _addSubject(p, code),
                                      ),
                                    ]),
                                    if (pairs.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(spacing: 6, runSpacing: 6, children: pairs.map((pr) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: C.sand, borderRadius: BorderRadius.circular(999)),
                                            child: Text(pr, style: const TextStyle(fontSize: 10.5, color: C.ink, fontWeight: FontWeight.w600)),
                                          )).toList()),
                                    ],
                                  ]),
                                );
                              }),
                            ],
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
  'C01', 'C02', 'C05', 'C06', 'C07', 'C08', 'C09', 'C10', 'C11', 'C12',
  'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'C19', 'C20', 'C21', 'C22', 'C23',
  'C25', 'C26',
};

class _StaffCriteriaScreenState extends State<StaffCriteriaScreen> with RouteAware {
  Map<String, dynamic> d = {};
  List<Map<String, dynamic>> otherCriteria = [];
  bool loading = true;
  List<Map<String, dynamic>> _campuses = [];
  String? _activeCampus;
  bool _hasProgrammes = false;
  final _cohortPeriodCtl = TextEditingController();
  final _cohortPctCtl = TextEditingController();
  final _partnerSchoolCtl = TextEditingController();
  final _companyCtl = TextEditingController();
  final _transportMapController = MapController();
  final _popupMapController = MapController();
  static const _gasabo = LatLng(-1.9358, 30.0930);
  // Generous rectangle covering Gasabo district — a soft UX bound (not a
  // precise legal boundary) so staff can't pan/zoom the pin map away from it.
  static final _gasaboBounds = LatLngBounds(const LatLng(-2.05, 29.98), const LatLng(-1.83, 30.23));
  String _pinMode = 'school'; // 'school' | 'bus' | 'moto'
  Map<String, Map<String, dynamic>> _criteriaByCode = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void didPopNext() {
    // Fires whenever a route pushed on top of this one (e.g. Campuses &
    // programmes, or the C09 pin popup) is popped, however it was left.
    // Only re-reads the campus/programme list — NOT the full criteria blob,
    // since pins placed via the popup live only in local state (`d`) until
    // the main Save button is pressed; overwriting `d` here would silently
    // discard an in-progress, unsaved pin the moment its popup closes.
    _refreshCampuses();
  }

  // True if there's anything for an A2 graduate to actually see: either an
  // explicitly named programme, or a campus with at least one department
  // assigned — a department with no named programme still counts (the
  // department name itself becomes the programme, per listProgrammes()'s
  // synthetic-programme fallback server-side) so staff who use that
  // shortcut aren't blocked here forever.
  bool _computeHasProgrammes(List<Map<String, dynamic>> campuses, List? rawProgrammes) =>
      (rawProgrammes ?? const []).isNotEmpty ||
      campuses.any((c) => (c['depts'] as List).isNotEmpty);

  Future<void> _refreshCampuses() async {
    try {
      final data = await Api.staffData(_staffUni);
      final list = (data['campuses'] as List?) ?? [];
      final newCampuses = list.map<Map<String, dynamic>>((c) =>
          {'name': c['name'] ?? '', 'depts': List<String>.from(c['depts'] ?? [])}).toList();
      final hasProgrammes = _computeHasProgrammes(newCampuses, data['programmes'] as List?);
      if (!mounted) return;
      setState(() {
        _campuses = newCampuses;
        _hasProgrammes = hasProgrammes;
        // Keep the current selection if it still exists; otherwise fall
        // back to the first campus rather than silently resetting a
        // selection the staff is actively working with.
        if (_activeCampus == null || !_campuses.any((c) => c['name'] == _activeCampus)) {
          _activeCampus = _campuses.isNotEmpty ? _campuses[0]['name'] as String : null;
        }
        // Give any newly added campus an empty pin slot, matching what
        // _normCampusPins() does on first load.
        final pins = (d['campusPins'] as Map?) ?? <String, dynamic>{};
        for (final c in _campuses) {
          final name = c['name'] as String;
          if (pins[name] is! Map) {
            pins[name] = {'schoolLocation': null, 'busStops': <Map>[], 'motoStops': <Map>[]};
          }
        }
        d['campusPins'] = pins;
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final data = await Api.staffData(_staffUni);
      d = Map<String, dynamic>.from((data['criteria'] as Map?) ?? {});
      final list = (data['campuses'] as List?) ?? [];
      _campuses = list.map<Map<String, dynamic>>((c) =>
          {'name': c['name'] ?? '', 'depts': List<String>.from(c['depts'] ?? [])}).toList();
      _hasProgrammes = _computeHasProgrammes(_campuses, data['programmes'] as List?);
    } catch (_) {}
    try {
      final all = await Api.criteria();
      final allCopy = all.map((c) => Map<String, dynamic>.from(c)).toList();
      _criteriaByCode = {for (final c in allCopy) c['code'] as String: c};
      otherCriteria = allCopy.where((c) => !_coveredCriteriaCodes.contains(c['code'])).toList();
    } catch (_) {}
    _activeCampus = _campuses.isNotEmpty ? (_campuses[0]['name'] as String) : null;
    _norm();
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _cohortPeriodCtl.dispose();
    _cohortPctCtl.dispose();
    _partnerSchoolCtl.dispose();
    _companyCtl.dispose();
    super.dispose();
  }

  // ensure list/typed fields exist
  void _norm() {
    d['partnerSchools'] = List<String>.from(d['partnerSchools'] ?? const []);
    d['companies'] = List<String>.from(d['companies'] ?? const []);
    d['healthPartners'] = List<String>.from(d['healthPartners'] ?? const []);
    d['cohorts'] = List<Map<String, dynamic>>.from(
        (d['cohorts'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? const []);
    _normCampusPins();
  }

  // Transport pins now live per campus: d['campusPins'][campusName] = {
  //   schoolLocation, busStops, motoStops }. One-time migration: an older
  // single university-wide pin set gets copied into the (only) campus it
  // could belong to. With 2+ campuses it's ambiguous which one the old pins
  // were for, so they're left untouched (unused, harmless) and staff just
  // re-pin each campus fresh.
  void _normCampusPins() {
    final raw = d['campusPins'];
    d['campusPins'] = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final pins = d['campusPins'] as Map<String, dynamic>;
    final legacySchool = d['schoolLocation'];
    final legacyBus = _normStops(d['busStops']);
    final legacyMoto = _normStops(d['motoStops']);
    final hasLegacy = legacySchool is Map || legacyBus.isNotEmpty || legacyMoto.isNotEmpty;
    if (hasLegacy && pins.isEmpty && _campuses.length == 1) {
      final name = _campuses[0]['name'] as String;
      pins[name] = {'schoolLocation': legacySchool, 'busStops': legacyBus, 'motoStops': legacyMoto};
      d.remove('schoolLocation');
      d.remove('busStops');
      d.remove('motoStops');
    }
    for (final c in _campuses) {
      final name = c['name'] as String;
      final p = (pins[name] is Map) ? Map<String, dynamic>.from(pins[name]) : <String, dynamic>{};
      p['schoolLocation'] = p['schoolLocation'] is Map ? p['schoolLocation'] : null;
      p['busStops'] = _normStops(p['busStops']);
      p['motoStops'] = _normStops(p['motoStops']);
      pins[name] = p;
    }
  }

  // Live reference into d['campusPins'][activeCampus] — mutating the
  // returned map (as the existing pin-editing code does throughout) writes
  // straight through to `d`, same as the old flat d['schoolLocation'] did.
  Map<String, dynamic> get _pins {
    final pins = d['campusPins'] as Map<String, dynamic>;
    final name = _activeCampus;
    if (name == null) return <String, dynamic>{'schoolLocation': null, 'busStops': [], 'motoStops': []};
    return pins.putIfAbsent(name, () => <String, dynamic>{
      'schoolLocation': null, 'busStops': <Map>[], 'motoStops': <Map>[],
    }) as Map<String, dynamic>;
  }

  void _setActiveCampus(String name) => setState(() => _activeCampus = name);

  List<Map<String, dynamic>> _normStops(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['lat'] != null && e['lng'] != null).toList();
  }

  Future<void> _onTransportMapTap(LatLng p) async {
    if (_pinMode == 'school') {
      final label = await reverseGeocodeAddress(p) ?? coordsLabel(p);
      if (mounted) setState(() => _pins['schoolLocation'] = {'lat': p.latitude, 'lng': p.longitude, 'label': label});
    } else {
      final name = await _promptText(_pinMode == 'bus' ? 'Bus stop name' : 'Moto stop name');
      if (name == null || name.trim().isEmpty) return;
      final key = _pinMode == 'bus' ? 'busStops' : 'motoStops';
      setState(() => (_pins[key] as List).add({'name': name.trim(), 'lat': p.latitude, 'lng': p.longitude}));
    }
  }

  List<Marker> _markersFor(Map<String, dynamic> pins) {
    final markers = <Marker>[];
    final school = pins['schoolLocation'] as Map?;
    if (school != null) {
      markers.add(Marker(
        point: LatLng((school['lat'] as num).toDouble(), (school['lng'] as num).toDouble()),
        width: 34, height: 34,
        child: const Icon(Icons.school, color: C.greenDark, size: 34),
      ));
    }
    for (final s in (pins['busStops'] as List).cast<Map>()) {
      markers.add(Marker(
        point: LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
        width: 28, height: 28,
        child: const Icon(Icons.directions_bus, color: Color(0xFF2A5C8F), size: 28),
      ));
    }
    for (final s in (pins['motoStops'] as List).cast<Map>()) {
      markers.add(Marker(
        point: LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
        width: 28, height: 28,
        child: const Icon(Icons.two_wheeler, color: Color(0xFFC25A1F), size: 28),
      ));
    }
    return markers;
  }

  LatLng? _schoolPoint(Map<String, dynamic> pins) {
    final school = pins['schoolLocation'] as Map?;
    if (school == null) return null;
    return LatLng((school['lat'] as num).toDouble(), (school['lng'] as num).toDouble());
  }

  /// Preview only — not interactive. Placing pins now happens exclusively in
  /// the full-screen popup (_openPinPopup), which gives staff a much larger
  /// view to tap precisely instead of this small embedded map.
  Widget _transportMap() {
    final school = _schoolPoint(_pins);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          key: ValueKey(_activeCampus),
          mapController: _transportMapController,
          options: MapOptions(
            initialCenter: school ?? _gasabo,
            initialZoom: 13,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            cameraConstraint: CameraConstraint.contain(bounds: _gasaboBounds),
            minZoom: 11,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.unimatch.gasabo',
            ),
            MarkerLayer(markers: _markersFor(_pins)),
          ],
        ),
      ),
    );
  }

  Future<void> _openPinPopup(String mode) async {
    setState(() => _pinMode = mode);
    final campusLabel = _activeCampus ?? '';
    final modeLabel = mode == 'school' ? 'Pin school' : (mode == 'bus' ? 'Add bus stop' : 'Set moto stop');
    final school = _schoolPoint(_pins);
    await Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (popupCtx) => Scaffold(
        appBar: AppBar(
          backgroundColor: C.green, foregroundColor: Colors.white,
          title: Text('$modeLabel — $campusLabel', style: const TextStyle(fontSize: 16)),
        ),
        body: FlutterMap(
          mapController: _popupMapController,
          options: MapOptions(
            initialCenter: school ?? _gasabo,
            initialZoom: 15,
            cameraConstraint: CameraConstraint.contain(bounds: _gasaboBounds),
            minZoom: 11,
            onTap: (_, point) async {
              await _onTransportMapTap(point);
              if (popupCtx.mounted) Navigator.pop(popupCtx);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.unimatch.gasabo',
            ),
            MarkerLayer(markers: _markersFor(_pins)),
          ],
        ),
      ),
    ));
  }

  /// Live preview only — the authoritative distance is computed and stored
  /// server-side on save. Null when the school isn't pinned yet, or there
  /// are no stops of this type yet (never fabricates a distance).
  double? _nearestKm(String key) {
    final school = _pins['schoolLocation'] as Map?;
    if (school == null) return null;
    final stops = (_pins[key] as List).cast<Map>();
    if (stops.isEmpty) return null;
    return stops.map((s) => haversineKm(
        (school['lat'] as num).toDouble(), (school['lng'] as num).toDouble(),
        (s['lat'] as num).toDouble(), (s['lng'] as num).toDouble())).reduce(math.min);
  }

  // Tapping opens the full-screen pin popup directly in this mode — placing
  // pins no longer happens on the small inline map.
  Widget _pinModeChip(String mode, String label, IconData icon, Color color) {
    final on = _pinMode == mode;
    return GestureDetector(
      onTap: () => _openPinPopup(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 3))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          if (on) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check_circle, size: 14, color: Colors.white),
          ],
        ]),
      ),
    );
  }

  /// Converts the yes/no toggles and free-text minimum grade into real
  /// numeric scores so every criterion can actually feed TOPSIS when an A2
  /// graduate selects it — computed once here at save time. The visible
  /// staff UI stays exactly as-is (still yes/no, still free text); this
  /// just derives the number behind it. Never fabricates: a field the
  /// staff never touched is removed from d, not defaulted to 0.
  void _deriveNumericCriteria() {
    void boolToNum(String flag, String code) {
      if (d[flag] == true) d[code] = 1;
      else if (d[flag] == false) d[code] = 0;
      else d.remove(code);
    }
    boolToNum('accommodation', 'C08');
    boolToNum('library', 'C14');
    boolToNum('sporting', 'C16');
    boolToNum('religiousBased', 'C25');

    // C17: richer than yes/no — count of insurance/clinic partners, the
    // same "more partners scores higher" pattern already used for C02/C11.
    if (d['health'] != null) {
      d['C17'] = List.from(d['healthPartners'] ?? const []).length;
    } else {
      d.remove('C17');
    }

    // C26: count of study modes offered — more flexibility scores higher.
    if (d['modeDay'] != null || d['modeEvening'] != null || d['modeWeekend'] != null) {
      d['C26'] = [d['modeDay'], d['modeEvening'], d['modeWeekend']].where((m) => m == true).length;
    } else {
      d.remove('C26');
    }

    // C23: parse the free-text minimum grade into a points scale (lower =
    // easier entry = better, matching the 'cost' direction) — staff-defined
    // scale: A=1, B=2, C=3, D=4, F=5. If several letters are mentioned
    // (e.g. "Bs or Cs"), take the most lenient one (highest number) since
    // that's the real floor a student needs to clear.
    const gradeScale = {'A': 1, 'B': 2, 'C': 3, 'D': 4, 'F': 5};
    final gradeMatches = RegExp(r'\b([ABCDF])S?\b', caseSensitive: false)
        .allMatches((d['minGrade'] as String?) ?? '')
        .map((m) => gradeScale[m.group(1)!.toUpperCase()]!)
        .toList();
    if (gradeMatches.isEmpty) {
      d.remove('C23');
    } else {
      d['C23'] = gradeMatches.reduce((a, b) => a > b ? a : b);
    }
  }

  // Every criterion a graduate can actually be ranked on must be filled —
  // C07 (server-computed from home distance) is the only exception.
  Set<String> get _requiredCriteriaCodes => {
        ..._coveredCriteriaCodes.where((c) => c != 'C07'),
        ...otherCriteria.map((c) => c['code'] as String),
      };

  String _labelFor(String code) => _criteriaByCode[code]?['label'] ?? code;

  List<String> _validate() {
    final missing = <String>[];
    for (final code in _requiredCriteriaCodes) {
      if (code == 'C09') continue; // checked per-campus below
      if (d[code] is! num) missing.add('${_labelFor(code)} · $code');
    }
    for (final c in _campuses) {
      final name = c['name'] as String;
      final pins = (d['campusPins'] as Map)[name] as Map?;
      if (pins == null || pins['schoolLocation'] == null) {
        missing.add('C09 · Transport proximity ($name)');
      }
    }
    if (d['religiousBased'] == true && d['religion'] == null) {
      missing.add('C25 · Religious / cultural affiliation (select a religion)');
    }
    if (d['health'] == true && List.from(d['healthPartners'] ?? const []).isEmpty) {
      missing.add('C17 · Health / medical services (add at least one partner)');
    }
    return missing;
  }

  Future<void> _showMissingFieldsDialog(List<String> missing) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('A few fields are still missing'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: missing.map((m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('•  $m', style: const TextStyle(fontSize: 13)),
                  )).toList(),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  Future<void> _save() async {
    try {
      _deriveNumericCriteria();
      final missing = _validate();
      if (missing.isNotEmpty) {
        await _showMissingFieldsDialog(missing);
        return;
      }
      await Api.saveStaffCriteria(_staffUni, d);
      if (!mounted) return;
      // No toast here — it was popping mid-transition as this screen
      // unmounts, since the SnackBar and the immediate navigation below
      // share the app's single ScaffoldMessenger. Landing back on the
      // dashboard already confirms the save succeeded.
      Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (_) => const StaffDashboard()), (r) => false);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  num? _n(String k) => d[k] is num ? d[k] as num : null;

  // Filling in criteria before any campus/programme exists would produce
  // numbers with nothing for an A2 graduate to actually match against.
  bool get _blocked => _campuses.isEmpty || !_hasProgrammes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: staffDrawer(context),
      appBar: staffAppBar(context, 'Criteria answers', back: true),
      floatingActionButton: (loading || _blocked) ? null : FloatingActionButton.extended(
        onPressed: _save, backgroundColor: C.green,
        icon: const Icon(Icons.save, color: Colors.white),
        label: const Text('Save', style: TextStyle(color: Colors.white)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: C.green))
          : _blocked
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.apartment, color: C.muted, size: 40),
                      const SizedBox(height: 14),
                      const Text('Add your campuses and programmes first',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(
                        _campuses.isEmpty
                            ? 'Criteria answers (including map pins) are set per campus — add at least one campus before filling this in.'
                            : 'Add at least one programme so A2 graduates have something to match your criteria against.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: C.muted, fontSize: 12.5, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      primaryButton('Go to Campuses & programmes', () {
                        // didPopNext() refreshes the campus/programme list
                        // automatically once this route is back on top.
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffCampusesScreen()));
                      }),
                    ]),
                  ),
                )
              : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
              children: [
                const Text('These answers are what A2 graduates see on your university detail page, and what TOPSIS ranks on. Numeric fields feed the score.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(height: 16),

                _section('C01 · Tuition & fees'),
                _numField('Tuition (RWF / year)', 'C01'),

                _section('C02 · Scholarships & partner schools'),
                const Text('More partner schools raises this criterion\'s score.',
                    style: TextStyle(color: C.muted, fontSize: 11, height: 1.4)),
                const SizedBox(height: 10),
                _numField('Scholarships offered / year', 'C02'),
                const SizedBox(height: 4),
                _partnerSchoolsField(),

                _section('C08 · On-campus accommodation'),
                _yesNo('Available?', 'accommodation'),

                _section('C09 · Transport proximity'),
                if (_campuses.isEmpty)
                  const Text('Add a campus first, under Campuses & programmes — pins are set per campus.',
                      style: TextStyle(color: C.muted, fontSize: 11.5, fontStyle: FontStyle.italic, height: 1.4))
                else ...[
                  const Text('Pick a campus, then mark its school location and any nearby bus/moto stops. Each campus gets its own pins.',
                      style: TextStyle(color: C.muted, fontSize: 11, height: 1.4)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: _campuses.map((c) {
                    final name = c['name'] as String;
                    final on = _activeCampus == name;
                    return GestureDetector(
                      onTap: () => _setActiveCampus(name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: on ? C.ink : Colors.white, borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: on ? C.ink : C.border)),
                        child: Text(name, style: TextStyle(color: on ? Colors.white : C.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 12),
                  const Text('Tap a button to open a full-screen map and place that pin.',
                      style: TextStyle(color: C.muted, fontSize: 11, height: 1.4)),
                  const SizedBox(height: 8),
                  Stack(children: [
                    _transportMap(),
                    Positioned(
                      left: 10, right: 10, bottom: 10,
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        _pinModeChip('school', 'Pin school', Icons.location_on, C.greenDark),
                        _pinModeChip('bus', 'Add bus stop', Icons.directions_bus, const Color(0xFF2A5C8F)),
                        _pinModeChip('moto', 'Set moto stop', Icons.two_wheeler, const Color(0xFFC25A1F)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  if (_pins['schoolLocation'] == null)
                    const Text('Tap "Pin school" to mark this campus on the map.',
                        style: TextStyle(color: C.muted, fontSize: 10.5, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 6),
                  if (_pins['schoolLocation'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Chip(
                        avatar: const Icon(Icons.school, size: 15, color: C.greenDark),
                        label: Text((_pins['schoolLocation'] as Map)['label'] ?? 'School', style: const TextStyle(fontSize: 12)),
                        backgroundColor: const Color(0xFFDCEBE3),
                        onDeleted: () => setState(() => _pins['schoolLocation'] = null),
                      ),
                    ),
                  if (_pins['schoolLocation'] != null) ...[
                    Builder(builder: (_) {
                      final busKm = _nearestKm('busStops');
                      final motoKm = _nearestKm('motoStops');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            busKm != null ? 'Nearest bus stop: ${busKm.toStringAsFixed(2)} km' : 'Nearest bus stop: add a bus stop pin to compute.',
                            style: TextStyle(fontSize: 11, color: busKm != null ? C.ink : C.muted,
                                fontStyle: busKm != null ? FontStyle.normal : FontStyle.italic),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            motoKm != null ? 'Nearest moto stop: ${motoKm.toStringAsFixed(2)} km' : 'Nearest moto stop: add a moto stop pin to compute.',
                            style: TextStyle(fontSize: 11, color: motoKm != null ? C.ink : C.muted,
                                fontStyle: motoKm != null ? FontStyle.normal : FontStyle.italic),
                          ),
                        ]),
                      );
                    }),
                  ],
                  Wrap(spacing: 6, runSpacing: 6, children: (_pins['busStops'] as List).cast<Map>().map((s) => Chip(
                        avatar: const Icon(Icons.directions_bus, size: 14, color: Color(0xFF2A5C8F)),
                        label: Text('${s['name']}', style: const TextStyle(fontSize: 12)),
                        backgroundColor: const Color(0xFFDCE9F2),
                        onDeleted: () => setState(() => (_pins['busStops'] as List).remove(s)),
                      )).toList()),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: (_pins['motoStops'] as List).cast<Map>().map((s) => Chip(
                      avatar: const Icon(Icons.two_wheeler, size: 14, color: Color(0xFFC25A1F)),
                      label: Text('${s['name']}', style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFFF7E4D3),
                      onDeleted: () => setState(() => (_pins['motoStops'] as List).remove(s)),
                    )).toList()),
                ],
                _section('C11 · Internship & industry partners'),
                const Text('More partner companies raises this criterion\'s score.',
                    style: TextStyle(color: C.muted, fontSize: 11, height: 1.4)),
                const SizedBox(height: 10),
                _companiesField(),

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
                const Text('A longer track record scores higher.',
                    style: TextStyle(color: C.muted, fontSize: 11, height: 1.4)),
                const SizedBox(height: 6),
                _numField('Years of operation · C21', 'C21'),
                _numField('Average class size · C05', 'C05'),
                Row(children: [
                  Expanded(child: _numField('Completion rate (%) · C06', 'C06')),
                  const SizedBox(width: 10),
                  Expanded(child: _numField('Employment rate (%) · C10', 'C10')),
                ]),

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
                  const Text('These criteria don\'t have a dedicated field yet — enter a number for each.',
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

  Widget _partnerSchoolsField() {
    final list = List<String>.from(d['partnerSchools'] ?? const []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PARTNER SCHOOLS (${list.length})', style: const TextStyle(
            color: C.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        if (list.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: list.map((s) => Chip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                backgroundColor: const Color(0xFFDCEBE3),
                deleteIconColor: C.greenDark,
                onDeleted: () => setState(() {
                  (d['partnerSchools'] as List).remove(s);
                  d['C02'] = (d['partnerSchools'] as List).length;
                }),
              )).toList()),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(child: TextField(
            controller: _partnerSchoolCtl,
            decoration: fieldDeco('Add partner school…'),
          )),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_circle, color: C.green, size: 32),
            onPressed: () {
              final v = _partnerSchoolCtl.text.trim();
              if (v.isEmpty) return;
              setState(() {
                (d['partnerSchools'] as List).add(v);
                d['C02'] = (d['partnerSchools'] as List).length;
                _partnerSchoolCtl.clear();
              });
            },
          ),
        ]),
      ]),
    );
  }

  Widget _companiesField() {
    final list = List<String>.from(d['companies'] ?? const []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PARTNER COMPANIES (${list.length})', style: const TextStyle(
            color: C.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        if (list.isNotEmpty) ...[
          Wrap(spacing: 6, runSpacing: 6, children: list.map((s) => Chip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                backgroundColor: const Color(0xFFDCE9F2),
                deleteIconColor: const Color(0xFF2A5C8F),
                onDeleted: () => setState(() {
                  (d['companies'] as List).remove(s);
                  d['C11'] = (d['companies'] as List).length;
                }),
              )).toList()),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(child: TextField(
            controller: _companyCtl,
            decoration: fieldDeco('Add partner company…'),
          )),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_circle, color: C.green, size: 32),
            onPressed: () {
              final v = _companyCtl.text.trim();
              if (v.isEmpty) return;
              setState(() {
                (d['companies'] as List).add(v);
                d['C11'] = (d['companies'] as List).length;
                _companyCtl.clear();
              });
            },
          ),
        ]),
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

  /// Averages the cohorts' percentages into d['C12'] so alumni-network
  /// strength actually feeds TOPSIS — the per-cohort list itself is
  /// display-only, only the average is a scored criterion.
  void _syncC12() {
    final cohorts = List<Map>.from(d['cohorts'] ?? const []);
    final pcts = cohorts
        .map((c) => c['pct'] is num ? (c['pct'] as num).toDouble() : double.tryParse('${c['pct']}'))
        .whereType<double>().toList();
    if (pcts.isEmpty) { d.remove('C12'); return; }
    d['C12'] = double.parse((pcts.reduce((a, b) => a + b) / pcts.length).toStringAsFixed(2));
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
          onDeleted: () => setState(() { (d['cohorts'] as List).removeAt(i); _syncC12(); }),
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
              _syncC12();
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

  void _downloadApplicants(List apps) {
    csv_download.downloadCsv('applicants.csv', _toCsv(
        ['Name', 'Email', 'Home area'],
        apps.map((a) => [a['name'], a['email'], a['home']]).toList()));
    if (mounted) toast(context, 'Downloading applicants.csv (${apps.length} rows)');
  }

  void _downloadHomeAreas(List areas) {
    csv_download.downloadCsv('reach-by-area.csv', _toCsv(
        ['Home area', 'Applicants'],
        areas.map((a) => [a['home'], a['count']]).toList()));
    if (mounted) toast(context, 'Downloading reach-by-area.csv (${areas.length} rows)');
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
          final areas = (r['homeAreas'] as List?) ?? [];
          final avgRating = (r['avgRating'] as num?)?.toDouble();
          final ratingCount = (r['ratingCount'] as num?)?.toInt() ?? 0;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(children: [
                Expanded(child: _stat('${r['appearedCount'] ?? 0}', 'On students\' lists', C.green)),
                const SizedBox(width: 10),
                Expanded(child: _stat('${r['shortlistCount'] ?? 0}', 'Shortlisted', const Color(0xFF2A5C8F))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _stat('${r['applyCount'] ?? 0}', 'Tapped Apply', const Color(0xFFC25A1F))),
                const SizedBox(width: 10),
                Expanded(child: _stat(ratingCount > 0 ? avgRating!.toStringAsFixed(1) : '—',
                    ratingCount > 0 ? '$ratingCount rating${ratingCount == 1 ? '' : 's'}' : 'No ratings yet', C.gold)),
              ]),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Applicants', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.ink)),
                TextButton.icon(
                  onPressed: apps.isEmpty ? null : () => _downloadApplicants(apps),
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
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Reach by home area', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.ink)),
                TextButton.icon(
                  onPressed: areas.isEmpty ? null : () => _downloadHomeAreas(areas),
                  icon: const Icon(Icons.download, size: 16, color: C.green),
                  label: const Text('CSV', style: TextStyle(color: C.green)),
                ),
              ]),
              const SizedBox(height: 6),
              if (areas.isEmpty)
                const Text('No applicant home areas yet.', style: TextStyle(color: C.muted))
              else
                ...areas.map((a) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                      child: Row(children: [
                        Expanded(child: Text('${a['home']}', style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink, fontSize: 13))),
                        Text('${a['count']}', style: const TextStyle(color: C.green, fontWeight: FontWeight.w700)),
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
      final results = await Future.wait([Api.adminUniversities(), Api.staffRequests(), Api.adminStudents()]);
      final unis = results[0], staff = results[1], students = results[2];
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
            const _UniversityPopularityChart(),
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
            _card(context, 'Subject combinations', 'Add, edit or remove A2 combination codes',
                Icons.rule_folder_outlined, const AdminCombosScreen(),
                bg: const Color(0xFFF1EBE0), fg: C.greenDark),
            _card(context, 'Student accounts', 'Suspend or restore A2 graduates',
                Icons.people_outline, const AdminStudentsScreen(), badge: studentCount,
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

/// Pie chart of what share of A2 graduates' most recent ranked list included
/// each university — colors reuse C.uni(abbr) so they match every other
/// university reference in the app. Tap a slice or a legend entry for a
/// small "ABBR: NN%" detail popup (no hover — this app also targets touch).
class _UniversityPopularityChart extends StatefulWidget {
  const _UniversityPopularityChart();
  @override
  State<_UniversityPopularityChart> createState() => _UniversityPopularityChartState();
}

class _UniversityPopularityChartState extends State<_UniversityPopularityChart> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    Api.universityPopularity().then((v) {
      if (mounted) setState(() { data = v; loading = false; });
    }).catchError((_) { if (mounted) setState(() => loading = false); });
  }

  void _showDetail(Map u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 14,
              decoration: BoxDecoration(color: C.uni('${u['abbr']}'), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('${u['abbr']}: ${(u['pct'] as num).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
            '${u['name']}\n${u['count']} of ${data!['totalStudents']} graduate${data!['totalStudents'] == 1 ? '' : 's'} had this university in their latest ranked list.',
            style: const TextStyle(color: C.muted, fontSize: 12.5, height: 1.4)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('UNIVERSITY POPULARITY', style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: C.muted)),
        const SizedBox(height: 4),
        const Text('Share of A2 graduates whose latest ranked list included each university.',
            style: TextStyle(color: C.muted, fontSize: 11.5, height: 1.35)),
        const SizedBox(height: 14),
        if (loading)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: C.green)))
        else if (data == null)
          const Text('Could not load popularity data.', style: TextStyle(color: C.muted, fontSize: 12))
        else if ((data!['totalStudents'] as int) == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No A2 graduates have ranked universities yet.', style: TextStyle(color: C.muted, fontSize: 12)),
          )
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTapUp: (details) {
                final unis = List<Map>.from(data!['universities'] as List);
                // localPosition is already relative to this GestureDetector,
                // which is sized exactly to the CustomPaint below it.
                final local = details.localPosition;
                const size = 160.0;
                const center = Offset(size / 2, size / 2);
                final dx = local.dx - center.dx, dy = local.dy - center.dy;
                final dist = math.sqrt(dx * dx + dy * dy);
                if (dist > size / 2) return;
                var angle = math.atan2(dy, dx) + math.pi / 2;
                if (angle < 0) angle += 2 * math.pi;
                double cum = 0;
                for (final u in unis) {
                  final pct = (u['pct'] as num).toDouble();
                  final sweep = pct / 100 * 2 * math.pi;
                  if (sweep <= 0) continue;
                  if (angle >= cum && angle < cum + sweep) { _showDetail(u); return; }
                  cum += sweep;
                }
              },
              child: CustomPaint(
                size: const Size(160, 160),
                painter: _PiePainter(List<Map>.from(data!['universities'] as List)),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Wrap(spacing: 12, runSpacing: 10, children: List<Map>.from(data!['universities'] as List).map((u) {
                return GestureDetector(
                  onTap: () => _showDetail(u),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: C.uni('${u['abbr']}'), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${u['abbr']} · ${(u['pct'] as num).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 11.5, color: C.ink, fontWeight: FontWeight.w600)),
                  ]),
                );
              }).toList()),
            ),
          ]),
      ]),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<Map> universities;
  _PiePainter(this.universities);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    double startAngle = -math.pi / 2;
    bool any = false;
    for (final u in universities) {
      final pct = (u['pct'] as num).toDouble();
      final sweep = pct / 100 * 2 * math.pi;
      if (sweep <= 0) continue;
      any = true;
      final paint = Paint()..color = C.uni('${u['abbr']}')..style = PaintingStyle.fill;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, true, paint);
      startAngle += sweep;
    }
    if (!any) {
      final paint = Paint()..color = C.sand..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) => oldDelegate.universities != universities;
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
                            universityLogo(m, size: 44, radius: 12, fontSize: 12),
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

/// ---- Admin: subject-combination catalogue ----------------------------------
class AdminCombosScreen extends StatefulWidget {
  const AdminCombosScreen({super.key});
  @override
  State<AdminCombosScreen> createState() => _AdminCombosScreenState();
}

class _AdminCombosScreenState extends State<AdminCombosScreen> {
  late Future<List<dynamic>> _future;
  final TextEditingController _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    _future = Api.adminCombinations();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    Session.comboCatalogue = null; // invalidate the shared public-catalogue cache
    _future = Api.adminCombinations();
  });

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

  Future<void> _edit({Map? existing}) async {
    final code = TextEditingController(text: existing?['code'] ?? '');
    final subjects = List<String>.from(existing?['subjects'] ?? const []);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existing == null ? 'Add combination' : 'Edit combination',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.ink)),
            const SizedBox(height: 16),
            TextField(
              controller: code,
              enabled: existing == null, // code is fixed once created — delete + re-add to rename
              textCapitalization: TextCapitalization.characters,
              decoration: fieldDeco('Code (e.g. PCB)'),
            ),
            const SizedBox(height: 16),
            const Text('SUBJECTS', style: TextStyle(
                color: C.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ...subjects.map((s) => Chip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    backgroundColor: const Color(0xFFDCEBE3),
                    onDeleted: () => setSheet(() => subjects.remove(s)),
                  )),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16, color: C.green),
                label: const Text('Add subject', style: TextStyle(fontSize: 12, color: C.green)),
                backgroundColor: Colors.white,
                side: const BorderSide(color: C.border),
                onPressed: () async {
                  final v = await _promptText('Subject name');
                  if (v != null && v.trim().isNotEmpty && !subjects.contains(v.trim())) {
                    setSheet(() => subjects.add(v.trim()));
                  }
                },
              ),
            ]),
            const SizedBox(height: 20),
            primaryButton('Save combination', () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (saved != true) return;
    final c = code.text.trim().toUpperCase();
    if (c.isEmpty) { if (mounted) toast(context, 'Code is required'); return; }
    try {
      if (existing == null) {
        await Api.addCombination(c, subjects);
      } else {
        await Api.updateCombination(c, subjects);
      }
      _reload();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: adminDrawer(context),
      appBar: adminAppBar(context, 'Subject combinations', back: true),
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
          if (all.isEmpty) return _emptyView('No combinations yet — add one.');
          final query = _search.text.trim().toLowerCase();
          final rows = query.isEmpty
              ? all
              : all.where((c) {
                  final m = c as Map;
                  return '${m['code']}'.toLowerCase().contains(query) ||
                      List<String>.from(m['subjects'] ?? const []).any((s) => s.toLowerCase().contains(query));
                }).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: searchField(_search, 'Search combinations…'),
            ),
            Expanded(
              child: rows.isEmpty
                  ? _emptyView('No combinations match "${_search.text.trim()}".')
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: rows.map((c) {
                        final m = c as Map;
                        final subs = List<String>.from(m['subjects'] ?? const []);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink)),
                                Text(subs.isEmpty ? 'No subjects set' : subs.join(' / '),
                                    style: const TextStyle(color: C.muted, fontSize: 11)),
                              ]),
                            ),
                            IconButton(icon: const Icon(Icons.edit_outlined, color: C.green, size: 20), onPressed: () => _edit(existing: m)),
                            IconButton(icon: const Icon(Icons.delete_outline, color: Color(0xFFC25A1F), size: 20),
                                onPressed: () async {
                                  try { await Api.deleteCombination(m['code']); _reload(); }
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
                    _downloadCsv('Applicants', ['Student', 'Email', 'University', 'Home area', 'Date'],
                        apps.map((a) => [a['student'], a['email'], a['university'], a['home'], a['date']]).toList());
                  } else if (reportType == 'Most-chosen criteria') {
                    _downloadCsv(reportType, ['Criterion', 'Code', 'selections'],
                        rows.map((u) => [u['name'], u['abbr'], u['n']]).toList());
                  } else {
                    _downloadCsv(reportType, ['University', 'Abbr', rowUnit],
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

  void _downloadCsv(String name, List<String> header, List<List<dynamic>> rows) {
    final filename = '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.csv';
    csv_download.downloadCsv(filename, _toCsv(header, rows));
    if (mounted) toast(context, 'Downloading $filename (${rows.length} rows)');
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
