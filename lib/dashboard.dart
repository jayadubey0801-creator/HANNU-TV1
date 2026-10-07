import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_database/firebase_database.dart';
import 'video_player_page.dart';
import 'skippable_ad_screen.dart';
import 'banner_ad_widget.dart';

const String kTmdbToken =
    'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIzZDJkOTExNmM5ZGU3MjA5ZWUyNzdiYjhjYzlhZWVkOCIsIm5iZiI6MTc5MDI2OTE4NC42MjksInN1YiI6IjZhYjU1NzAwNzZiMTg1ODU3MGFjNDM4NSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.xZJX8fowhVhVJsgl-5wOW6Y7ZfUr9Zu_Ey1qMkhnPd0';

const Map<String, String> kApiHeaders = {
  'Authorization': 'Bearer $kTmdbToken',
  'accept': 'application/json',
};

const String adsterraBannerSnippet = '''
<script type="text/javascript">
  atOptions = {
    'key' : 'a39df283f6ad10c34e229e5715bceff5',
    'format' : 'iframe',
    'height' : 50,
    'width' : 320,
    'params' : {}
  };
</script>
<script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
''';

List<Map<String, dynamic>> continueWatchingList = [];
List<Map<String, dynamic>> downloadedMoviesList = [];

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  DashboardPageState createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage> {
  bool isNextAd10Sec = true;

  List<Map<String, dynamic>> trendingList = [];
  List<Map<String, dynamic>> bollywoodList = [];
  List<Map<String, dynamic>> hollywoodList = [];
  List<Map<String, dynamic>> animeList = [];
  List<Map<String, dynamic>> actionList = [];
  List<Map<String, dynamic>> comedyList = [];
  List<Map<String, dynamic>> horrorList = [];
  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> seriesRankings = [];

  bool isLoading = true;
  bool isSearching = false;
  final TextEditingController searchController = TextEditingController();
  Timer? debounce;

  final PageController pageController = PageController();
  Timer? carouselTimer;
  int currentPage = 0;

  String selectedPlatform = 'all';

  final List<Map<String, dynamic>> ottPlatforms = const [
    {'name': 'ALL VIP', 'color': Colors.red, 'providerId': 'all'},
    {'name': 'NETFLIX', 'color': Colors.redAccent, 'providerId': '8'},
    {'name': 'PRIME VIDEO', 'color': Colors.blueAccent, 'providerId': '9'},
    {'name': 'APPLE TV', 'color': Colors.white70, 'providerId': '350'},
    {'name': 'CRUNCHYROLL', 'color': Colors.orangeAccent, 'providerId': '283'},
    {'name': 'DISNEY', 'color': Colors.lightBlueAccent, 'providerId': '337'},
    {'name': 'HULU', 'color': Colors.greenAccent, 'providerId': '15'},
    {'name': 'HBO MAX', 'color': Colors.deepPurpleAccent, 'providerId': '1899'},
    {'name': 'MGM', 'color': Colors.amber, 'providerId': '34'},
    {'name': 'PARAMOUNT', 'color': Colors.blue, 'providerId': '2303'},
    {'name': 'PEACOCK', 'color': Colors.tealAccent, 'providerId': '387'},
    {'name': 'SHUDDER', 'color': Colors.red, 'providerId': '99'},
  ];

  // ===== STRICT PRIVATE DNS ENFORCER =====
  bool dnsChecked = false;
  bool dnsOn = false;
  bool dnsOffline = false;

  Future<void> checkPrivateDns() async {
    if (mounted) setState(() { dnsChecked = false; dnsOffline = false; });
    try {
      await http.get(
        Uri.parse('https://hannutvpn.hritikmishra862.workers.dev/3/configuration'),
        headers: kApiHeaders,
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      if (mounted) setState(() { dnsOffline = true; dnsOn = false; dnsChecked = true; });
      return;
    }
    bool on;
    try {
      final r = await http.get(Uri.parse('https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'))
          .timeout(const Duration(seconds: 6));
      on = r.statusCode != 200;
    } catch (_) {
      on = true;
    }
    if (!mounted) return;
    setState(() { dnsOn = on; dnsChecked = true; });
    if (on) loadAllDashboards();
  }

  Widget buildDnsGate() {
    if (!dnsChecked) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F0F),
        body: Center(child: Text('Checking secure connection...', style: TextStyle(color: Colors.white54))),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield, color: Colors.redAccent, size: 70),
              const SizedBox(height: 18),
              Text(
                dnsOffline
                    ? 'Internet connection check karo aur dobara try karo.'
                    : "⚠️ Strict Mode: Please go to your phone settings and set Private DNS to 'dns.adguard.com' to access HANNUTV and block intrusive ads.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: checkPrivateDns, child: const Text('Recheck')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    checkForUpdates();
    initPresenceTracking();
    checkPrivateDns();
    startCarousel();
  }

  Future<void> initPresenceTracking() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await FirebaseAuth.instance.signInAnonymously();
      user = FirebaseAuth.instance.currentUser;
    }
    if (user != null) {
      DatabaseReference presenceRef =
          FirebaseDatabase.instance.ref("active_users/${user.uid}");
      FirebaseDatabase.instance.ref(".info/connected").onValue.listen((event) {
        if (event.snapshot.value == false) return;
        presenceRef.onDisconnect().remove();
        presenceRef.set({
          'online': true,
          'is_logged_in': !user!.isAnonymous,
          'last_active': ServerValue.timestamp,
        });
      });
    }
  }

  Future<void> checkForUpdates() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(minutes: 5),
      ));
      await remoteConfig.fetchAndActivate();

      bool forceUpdate = remoteConfig.getBool('force_update');
      String latestVersion = remoteConfig.getString('latest_version');
      String updateLink = remoteConfig.getString('update_link');
      String currentVersion = "1.0.0";

      if (forceUpdate && currentVersion != latestVersion && latestVersion.isNotEmpty) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: const Color(0xFF151515),
              title: const Text('Update Required!',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              content: Text(
                  'A new version ($latestVersion) is available. Please update your app to continue watching securely.',
                  style: const TextStyle(color: Colors.white)),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () => launchUrl(
                      Uri.parse(updateLink.isEmpty ? 'https://t.me/HANNUTV' : updateLink),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Update Now',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
  }

  void startCarousel() {
    carouselTimer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      if (pageController.hasClients && trendingList.isNotEmpty) {
        int next = currentPage + 1;
        if (next >= (trendingList.length > 5 ? 5 : trendingList.length)) {
          next = 0;
        }
        pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    carouselTimer?.cancel();
    pageController.dispose();
    searchController.dispose();
    debounce?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> parseData(http.Response response, {String? forceMediaType}) {
    if (response.statusCode != 200) return [];
    final List rawData = json.decode(response.body)['results'] ?? [];
    return rawData.where((m) => m['media_type'] != 'person').map((m) {
      return {
        'id': m['id'],
        'title': m['title'] ?? m['name'] ?? 'Unknown',
        'overview': m['overview'] ?? '',
        'posterUrl': m['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${m['poster_path']}' : '',
        'backdropUrl': m['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/original${m['backdrop_path']}' : '',
        'rating': (m['vote_average'] ?? 0.0).toStringAsFixed(1),
        'year': (m['release_date'] ?? m['first_air_date'] ?? '').toString().split('-').first,
        'mediaType': forceMediaType ?? m['media_type'] ?? 'movie',
      };
    }).toList();
  }

  Future<void> loadAllDashboards([String? providerId, String? customFilter]) async {
    setState(() {
      isLoading = true;
      selectedPlatform = providerId ?? 'all';
    });

    try {
      // 🚀 NAYA WORKING CLOUDFLARE WORKER LINK
      String base = 'https://hannutvpn.hritikmishra862.workers.dev/3';
      String prov = (providerId != null && providerId != 'all') ? '&with_watch_providers=$providerId&watch_region=US' : '';

      String trendingUrl = '$base/trending/all/day?language=en-US$prov';
      if (customFilter == 'anime') {
        trendingUrl = '$base/discover/tv?language=en-US&with_genres=16,10764&sort_by=popularity.desc';
      }
      if (customFilter == 'sports') {
        trendingUrl = '$base/search/multi?query=WWE&language=en-US';
      }

      var responses = await Future.wait([
        http.get(Uri.parse(trendingUrl), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/movie?language=hi-IN&with_original_language=hi&sort_by=popularity.desc$prov'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_original_language=en&sort_by=popularity.desc$prov'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/tv?language=en-US&with_genres=16&sort_by=popularity.desc$prov'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=28$prov&sort_by=popularity.desc'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/tv?language=en-US&with_genres=35$prov&sort_by=popularity.desc'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=27$prov&sort_by=popularity.desc'), headers: kApiHeaders),
        http.get(Uri.parse('$base/trending/tv/week?language=en-US'), headers: kApiHeaders),
      ]);

      setState(() {
        trendingList = parseData(responses[0]);
        bollywoodList = parseData(responses[1], forceMediaType: 'movie');
        hollywoodList = parseData(responses[2], forceMediaType: 'movie');
        animeList = parseData(responses[3], forceMediaType: 'tv');
        actionList = parseData(responses[4], forceMediaType: 'movie');
        comedyList = parseData(responses[5], forceMediaType: 'tv');
        horrorList = parseData(responses[6], forceMediaType: 'movie');
        seriesRankings = parseData(responses[7], forceMediaType: 'tv');
        isLoading = false;
      });
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  void onSearchChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        isSearching = false;
        searchResults = [];
      });
      return;
    }

    setState(() => isSearching = true);

    if (debounce?.isActive ?? false) debounce!.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => isLoading = true);
      try {
        final url = 'https://hannutvpn.hritikmishra862.workers.dev/3/search/multi?query=${Uri.encodeComponent(value)}&language=en-US&include_adult=false';
        final res = await http.get(Uri.parse(url), headers: kApiHeaders);
        setState(() {
          searchResults = parseData(res);
          isLoading = false;
        });
      } catch (_) {
        setState(() => isLoading = false);
      }
    });
  }

  void launchPlayerDirect(Map<String, dynamic> media) {
    continueWatchingList.removeWhere((m) => m['id'] == media['id']);
    continueWatchingList.insert(0, media);

    final type = media['mediaType'] ?? 'movie';
    final tId = media['id'] is int ? media['id'] : int.tryParse(media['id'].toString()) ?? 0;
    const int currentAdDuration = 10; // movies: fixed 10 sec (Live TV unchanged)

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SkippableAdScreen(
          adDuration: currentAdDuration,
          nextScreen: VideoPlayerPage(
            tmdbId: tId,
            mediaType: type,
            season: 1,
            episode: 1,
            movieTitle: media['title'] ?? 'Title',
            overview: media['overview'] ?? '',
            rating: media['rating'] ?? '9.0',
            year: media['year'] ?? '2024',
          ),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  Future<void> signInWithGoogle(StateSetter setModalState) async {
    UserCredential? userCred;
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // account chooser band hua / email select ke baad bina result ke wapas aa gaya
        _showLoginError('sign_in_canceled');
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // NOTE: guest (anonymous) user ko pehle sign-out nahi karte. Agar login fail ho
      // to user guest hi rahe; login success hone par Firebase khud guest ki jagah le leta hai.
      userCred = await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _showLoginError('${e.code} ${e.message ?? ''}');
      return;
    } catch (e) {
      _showLoginError(e.toString());
      return;
    }

    final user = userCred?.user;
    if (user == null) {
      _showLoginError('no-user');
      return;
    }

    // Login ho chuka hai. Profile save / presence fail ho to bhi "Login Failed" nahi dikhana.
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': user.displayName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'last_login': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Profile save failed (login ok): $e');
    }
    try {
      initPresenceTracking();
    } catch (e) {
      debugPrint('Presence start failed (login ok): $e');
    }

    if (!mounted) return;
    setModalState(() {});
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login Successful!'), backgroundColor: Colors.green));
  }

  // Login error ka asli reason dikhata hai (pehle sab kuch sirf "Login Failed" ban jata tha)
  void _showLoginError(String raw) {
    debugPrint('GOOGLE LOGIN ERROR: $raw');
    if (!mounted) return;
    String msg;
    if (raw.contains('sign_in_canceled') || RegExp(r'(ApiException|\.api\.\w+): ?12501\b').hasMatch(raw)) {
      // user ne khud cancel kiya ho sakta hai, ya email select ke baad Google ne silently wapas bhej diya
      // (wrong SHA-1 / OAuth config me aksar yahi hota hai)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Login cancelled. Email select karke bhi yahi aaye to Firebase me SHA-1 / SHA-256 add karo'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 6)));
      return;
    }
    if (RegExp(r'(ApiException|\.api\.\w+): ?10\b').hasMatch(raw)) {
      msg = 'Login Failed (code 10): Firebase me app ka SHA-1 / SHA-256 add karo';
    } else if (raw.contains('12500')) {
      msg = 'Login Failed (12500): Firebase me support email set karo';
    } else if (raw.contains('operation-not-allowed')) {
      msg = 'Login Failed: Firebase Authentication me Google sign-in enable karo';
    } else if (raw.contains('network')) {
      msg = 'Login Failed: internet check karo';
    } else {
      msg = 'Login Failed: ${raw.length > 90 ? raw.substring(0, 90) : raw}';
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 6)));
  }

  Future<void> signOut(StateSetter setModalState) async {
    await FirebaseAuth.instance.signOut();
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    initPresenceTracking();
    setModalState(() {});
    setState(() {});
  }

  void showAdminDashboard() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            User? currentUser = FirebaseAuth.instance.currentUser;
            bool isGuest = currentUser == null || currentUser.isAnonymous;

            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFF202020),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.redAccent,
                              backgroundImage: !isGuest && currentUser.photoURL != null
                                  ? NetworkImage(currentUser.photoURL!)
                                  : null,
                              child: isGuest || currentUser!.photoURL == null
                                  ? const Icon(Icons.person, color: Colors.white, size: 35)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: isGuest ? Colors.orange : Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF202020), width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                !isGuest ? (currentUser.displayName ?? 'HANNUTV User') : 'Welcome to HANNUTV',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                !isGuest ? (currentUser.email ?? 'Synced') : 'Login to sync your data',
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (isGuest)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async => await signInWithGoogle(setModalState),
                        icon: const Icon(Icons.g_mobiledata, color: Colors.black, size: 32),
                        label: const Text('Sign in with Google',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.2),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        onPressed: () async => await signOut(setModalState),
                        icon: const Icon(Icons.logout, color: Colors.redAccent),
                        label: const Text('Logout',
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('Support & Updates',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => launchUrl(Uri.parse('https://t.me/HANNUTV'), mode: LaunchMode.externalApplication),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.1),
                                border: Border.all(color: Colors.blueAccent),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.telegram, color: Colors.blueAccent, size: 30),
                                  SizedBox(height: 8),
                                  Text('Telegram', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => launchUrl(Uri.parse('https://whatsapp.com/channel/0029VbE2Pb17z4kmfjF04P0v'),
                                mode: LaunchMode.externalApplication),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                border: Border.all(color: Colors.green),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.chat, color: Colors.green, size: 30),
                                  SizedBox(height: 8),
                                  Text('WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text('Your Watch History',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: continueWatchingList.isEmpty
                        ? const Center(child: Text('No movies watched yet.', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: continueWatchingList.length,
                            itemBuilder: (context, index) {
                              final media = continueWatchingList[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.only(bottom: 12),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(media['posterUrl'], width: 40, height: 60, fit: BoxFit.cover),
                                ),
                                title: Text(media['title'],
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Text(media['year'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.play_circle_fill, color: Colors.redAccent),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    launchPlayerDirect(media);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget buildHorizontalList(String title, List<Map<String, dynamic>> moviesData, {bool isRanking = false}) {
    if (moviesData.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: isRanking ? 190 : 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: moviesData.length,
            itemBuilder: (context, index) {
              final media = moviesData[index];
              return TvFocusButton(
                onTap: () => launchPlayerDirect(media),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: isRanking ? 120 : 110,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: NetworkImage(
                                (media['posterUrl'] != null && media['posterUrl'] != '')
                                    ? media['posterUrl']
                                    : 'https://via.placeholder.com/300x450/222222/888888',
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: isRanking
                              ? Stack(
                                  children: [
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(8),
                                            bottomRight: Radius.circular(8),
                                          ),
                                        ),
                                        child: Text('${index + 1}',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ),
                                    ),
                                    const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40)),
                                  ],
                                )
                              : const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        media['title'] ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!dnsChecked || !dnsOn) return buildDnsGate();
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_zip, color: Colors.white, size: 28),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage())),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            onPressed: () => setState(() => isSearching = true),
          ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white, size: 28),
            onPressed: showAdminDashboard,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 400,
                  child: trendingList.isEmpty
                      ? Container(color: Colors.black)
                      : PageView.builder(
                          controller: pageController,
                          itemCount: trendingList.length > 5 ? 5 : trendingList.length,
                          onPageChanged: (index) => setState(() => currentPage = index),
                          itemBuilder: (context, index) {
                            return Container(
                              decoration: BoxDecoration(
                                image: DecorationImage(
                                  image: NetworkImage(
                                    (trendingList[index]['backdropUrl'] != null && trendingList[index]['backdropUrl'] != '')
                                        ? trendingList[index]['backdropUrl']
                                        : 'https://images.unsplash.com/photo-1616530940355-351fabd9524b?q=80&w=600',
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  height: 400,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color(0xFF0F0F0F),
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveTvChannelsPage())),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.tv, color: Colors.white, size: 16),
                                    const SizedBox(width: 6),
                                    const Text('TV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            buildTopMenuButton(Icons.animation, 'Anime', onTap: () => loadAllDashboards(null, 'anime')),
                            const SizedBox(width: 12),
                            buildTopMenuButton(Icons.sports_soccer, 'Sports', onTap: () => loadAllDashboards(null, 'sports')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isSearching)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: TextField(
                            controller: searchController,
                            style: const TextStyle(color: Colors.white),
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Search Movies, Shows...',
                              hintStyle: const TextStyle(color: Colors.grey),
                              filled: true,
                              fillColor: Colors.black87,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: const BorderSide(color: Colors.redAccent)),
                              prefixIcon: const Icon(Icons.search, color: Colors.redAccent),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    isSearching = false;
                                    searchController.clear();
                                    searchResults.clear();
                                  });
                                },
                              ),
                            ),
                            onChanged: onSearchChanged,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trendingList.isNotEmpty && !isSearching)
                  Positioned(
                    bottom: 20,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trendingList[currentPage]['title'] ?? 'Title',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        TvFocusButton(
                          onTap: () => launchPlayerDirect(trendingList[currentPage]),
                          borderRadius: BorderRadius.circular(8),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                            ),
                            onPressed: () => launchPlayerDirect(trendingList[currentPage]),
                            icon: const Icon(Icons.play_arrow, size: 24),
                            label: const Text('Play Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator(color: Colors.red)))
            else if (isSearching)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: searchResults.length,
                itemBuilder: (context, index) {
                  final movie = searchResults[index];
                  return TvFocusButton(
                    onTap: () => launchPlayerDirect(movie),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: NetworkImage(
                                  (movie['posterUrl'] != null && movie['posterUrl'] != '')
                                      ? movie['posterUrl']
                                      : 'https://via.placeholder.com/300x450/222222/888888',
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          movie['title'] ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              )
            else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Text('Watch on OTT Channels', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: ottPlatforms.length,
                  itemBuilder: (context, index) {
                    final srv = ottPlatforms[index];
                    final isSelected = selectedPlatform == srv['providerId'];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: TvFocusButton(
                        onTap: () {
                          searchController.clear();
                          setState(() => isSearching = false);
                          loadAllDashboards(srv['providerId']);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected ? Colors.redAccent : Colors.grey[900],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            side: BorderSide(color: srv['color'], width: 1.5),
                          ),
                          onPressed: () {
                            searchController.clear();
                            setState(() => isSearching = false);
                            loadAllDashboards(srv['providerId']);
                          },
                          child: Text(
                            srv['name'],
                            style: TextStyle(
                              color: isSelected ? Colors.white : srv['color'],
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                child: CustomBannerAd(htmlBannerCode: adsterraBannerSnippet),
              ),
              if (seriesRankings.isNotEmpty) buildHorizontalList('Series Rankings', seriesRankings, isRanking: true),
              buildHorizontalList('HANNUTV Trending', trendingList),
              if (continueWatchingList.isNotEmpty) buildHorizontalList('Continue Watching', continueWatchingList),
              buildHorizontalList('Bollywood Hindi Movies', bollywoodList),
              buildHorizontalList('Hollywood English Movies', hollywoodList),
              buildHorizontalList('Anime Hub', animeList),
              buildHorizontalList('Action Movies', actionList),
              buildHorizontalList('Comedy Shows', comedyList),
              buildHorizontalList('Horror Movies', horrorList),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget buildTopMenuButton(IconData icon, String title, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class TvFocusButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  const TvFocusButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  @override
  State<TvFocusButton> createState() => TvFocusButtonState();
}

class TvFocusButtonState extends State<TvFocusButton> {
  bool hasFocus = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focus) {
        if (mounted) setState(() => hasFocus = focus);
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: widget.borderRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(color: hasFocus ? Colors.redAccent : Colors.transparent, width: hasFocus ? 3.5 : 0),
            boxShadow: hasFocus
                ? [BoxShadow(color: Colors.redAccent.withOpacity(0.65), blurRadius: 10)]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class LiveTvChannelsPage extends StatefulWidget {
  const LiveTvChannelsPage({super.key});

  @override
  State<LiveTvChannelsPage> createState() => LiveTvChannelsPageState();
}

class LiveTvChannelsPageState extends State<LiveTvChannelsPage> {
  List<Map<String, String>> allChannels = [];
  List<Map<String, String>> filteredChannels = [];
  bool isLoading = true;
  final TextEditingController tvSearchController = TextEditingController();

  // 📂 CATEGORIES: kaunsi category me kitne / konse channels hain
  List<String> categories = ['All'];
  Map<String, int> categoryCounts = {};
  String selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    fetchIptvData();
  }

  Future<void> fetchIptvData() async {
    try {
      // index.category.m3u = har channel ke saath uski category (group-title) aati hai
      final response = await http.get(Uri.parse('https://iptv-org.github.io/iptv/index.category.m3u'));
      if (response.statusCode == 200) {
        List<String> lines = response.body.split('\n');
        final Map<String, Map<String, String>> byUrl = {}; // ek channel ek hi baar
        final Map<String, Set<String>> catsByUrl = {};
        String currentName = '';
        String currentLogo = '';
        String currentGroup = '';

        for (String rawLine in lines) {
          final String line = rawLine.trim();
          if (line.startsWith('#EXTINF:')) {
            RegExp logoRegex = RegExp(r'tvg-logo="([^"]*)"');
            var match = logoRegex.firstMatch(line);
            currentLogo = match != null ? match.group(1)! : '';
            var groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
            currentGroup = groupMatch != null ? groupMatch.group(1)!.trim() : '';
            List<String> splitComma = line.split(',');
            if (splitComma.length > 1) {
              currentName = splitComma.last.trim();
            }
          } else if (line.startsWith('http')) {
            if (currentName.isNotEmpty) {
              final cats = currentGroup
                  .split(';')
                  .map((c) => c.trim())
                  .where((c) => c.isNotEmpty)
                  .map((c) => c.toLowerCase() == 'undefined' ? 'Other' : c)
                  .toList();
              if (cats.isEmpty) cats.add('Other');
              // adult (XXX) channels app me nahi dikhane
              if (!cats.any((c) => c.toLowerCase() == 'xxx')) {
                byUrl.putIfAbsent(line, () => {'name': currentName, 'logo': currentLogo, 'url': line});
                catsByUrl.putIfAbsent(line, () => <String>{}).addAll(cats);
              }
            }
          }
        }

        final List<Map<String, String>> parsed = [];
        final Map<String, int> counts = {};
        byUrl.forEach((url, ch) {
          final cats = catsByUrl[url]!;
          ch['group'] = cats.join(';');
          for (final c in cats) {
            counts[c] = (counts[c] ?? 0) + 1;
          }
          parsed.add(ch);
        });

        // zyada channels wali category pehle, 'Other' sabse last
        final List<String> sortedCats = counts.keys.toList()
          ..sort((a, b) {
            if (a == 'Other') return 1;
            if (b == 'Other') return -1;
            return counts[b]!.compareTo(counts[a]!);
          });

        setState(() {
          allChannels = parsed;
          filteredChannels = parsed;
          categoryCounts = counts;
          categories = ['All', ...sortedCats];
          isLoading = false;
        });
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  void filterChannels(String query) {
    setState(() {
      filteredChannels = allChannels.where((c) {
        final matchesName = c['name']!.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = selectedCategory == 'All' ||
            (c['group'] ?? '').split(';').contains(selectedCategory);
        return matchesName && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151515),
        title: const Text('Live TV Channels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: tvSearchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search Live Channels (e.g. Star, Zee, Sony)...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.black87,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.search, color: Colors.redAccent),
              ),
              onChanged: filterChannels,
            ),
          ),
          // 📂 CATEGORY CHIPS: tap karo to sirf us category ke channels dikhenge
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = categories[i];
                final bool selected = cat == selectedCategory;
                final int count = cat == 'All' ? allChannels.length : (categoryCounts[cat] ?? 0);
                return ChoiceChip(
                  label: Text('$cat ($count)'),
                  selected: selected,
                  selectedColor: Colors.redAccent,
                  backgroundColor: const Color(0xFF1A1A1A),
                  side: const BorderSide(color: Colors.white12),
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) {
                    selectedCategory = cat;
                    filterChannels(tvSearchController.text);
                  },
                );
              },
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: filteredChannels.length,
                    itemBuilder: (context, index) {
                      final ch = filteredChannels[index];
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SkippableAdScreen(
                                adDuration: 30,
                                nextScreen: VideoPlayerPage(
                                  tmdbId: 0,
                                  mediaType: 'tv',
                                  season: 1,
                                  episode: 1,
                                  movieTitle: ch['name']!,
                                  overview: 'Live TV Broadcast',
                                  rating: 'Live',
                                  year: 'Now',
                                  customUrl: ch['url'],
                                ),
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: ch['logo']!.isNotEmpty
                                      ? Image.network(ch['logo']!, errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.white54, size: 40))
                                      : const Icon(Icons.tv, color: Colors.white54, size: 40),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                width: double.infinity,
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                                ),
                                child: Text(
                                  ch['name']!,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151515),
        title: const Text('Downloads Folder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: downloadedMoviesList.isEmpty
          ? const Column(
              children: [
                SizedBox(height: 20),
                CustomBannerAd(htmlBannerCode: adsterraBannerSnippet),
                Expanded(child: Center(child: Text('No movies downloaded yet.', style: TextStyle(color: Colors.grey, fontSize: 16)))),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: downloadedMoviesList.length + 2,
              itemBuilder: (context, index) {
                if (index == 0 || index == downloadedMoviesList.length + 1) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: CustomBannerAd(htmlBannerCode: adsterraBannerSnippet),
                  );
                }
                final media = downloadedMoviesList[index - 1];
                return Card(
                  color: const Color(0xFF1A1A1A),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8),
                    leading: const Icon(Icons.movie, color: Colors.greenAccent, size: 40),
                    title: Text(media['title'] ?? 'Unknown',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('Downloaded (${media['year'] ?? ''})',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill, color: Colors.redAccent, size: 35),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Playing downloaded file...'), backgroundColor: Colors.green));
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}