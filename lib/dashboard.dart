import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart'; 
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';

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
  atOptions = { 'key' : 'a39df283f6ad10c34e229e5715bceff5', 'format' : 'iframe', 'height' : 50, 'width' : 320, 'params' : {} };
</script>
<script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
''';

List<Map<String, dynamic>> continueWatchingList = [];

// 🔥 100X PERFORMANCE JSON PARSER 🔥
List<Map<String, dynamic>> _parseTMDBJson(Map<String, dynamic> params) {
  final String responseBody = params['body'];
  final String? forceMediaType = params['forceType'];
  final List rawData = json.decode(responseBody)['results'] ?? [];
  return rawData.where((m) => m['media_type'] != 'person').map((m) => {
    'id': m['id'],
    'title': m['title'] ?? m['name'] ?? 'Unknown',
    'overview': m['overview'] ?? '',
    'posterUrl': m['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${m['poster_path']}' : '',
    'backdropUrl': m['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w780${m['backdrop_path']}' : '',
    'rating': (m['vote_average'] ?? 0.0).toStringAsFixed(1),
    'year': (m['release_date'] ?? m['first_air_date'] ?? '').toString().split('-').first,
    'mediaType': forceMediaType ?? m['media_type'] ?? 'movie',
  }).toList();
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  DashboardPageState createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  bool isNextAd10Sec = true;

  List<Map<String, dynamic>> trendingList = [];
  List<Map<String, dynamic>> top10India = [];
  List<Map<String, dynamic>> top10World = [];
  List<Map<String, dynamic>> actionList = [];
  List<Map<String, dynamic>> romanceList = [];
  List<Map<String, dynamic>> horrorList = [];
  List<Map<String, dynamic>> sciFiList = [];
  List<Map<String, dynamic>> kDramaList = [];
  List<Map<String, dynamic>> mature18List = [];
  List<Map<String, dynamic>> searchResults = [];

  bool isLoading = true;
  bool isSearching = false;
  final TextEditingController searchController = TextEditingController();
  Timer? debounce;

  final PageController pageController = PageController();
  Timer? carouselTimer;
  int currentPage = 0;
  Color ambientColor = const Color(0xFF050505);

  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  String selectedPlatform = 'all';

  // 🔥 REAL OTT LOGOS (USER PROVIDED) 🔥
  final List<Map<String, dynamic>> ottPlatforms = const [
    {'name': 'ALL', 'logo': '', 'providerId': 'all'},
    {'name': 'Netflix', 'logo': 'https://static.vecteezy.com/system/resources/previews/020/190/493/non_2x/netflix-logo-netflix-icon-free-free-vector.jpg', 'providerId': '8'},
    {'name': 'Prime', 'logo': 'https://television-b26f.kxcdn.com/wp-content/uploads/2023/03/Amazon-Prime-Video-Logo-2023.png', 'providerId': '9'},
    {'name': 'JioCinema', 'logo': 'https://miro.medium.com/v2/resize:fit:2000/1*Nehq1KYRgFWTanqsLwWeFQ.png', 'providerId': '220'},
    {'name': 'Disney+', 'logo': 'https://logos-world.net/wp-content/uploads/2021/02/Disney-Symbol.png', 'providerId': '337'},
    {'name': 'HBO Max', 'logo': 'https://sm.ign.com/ign_in/news/m/max-changi/max-changing-its-name-back-to-hbo-max-warner-bros-discovery_5g77.jpg', 'providerId': '384'},
    {'name': 'Apple TV+', 'logo': 'https://www.apple.com/v/apple-tv/c/images/meta/apple-tv__ft1nltyknfmi_og.png?202609180346', 'providerId': '350'},
    {'name': 'Hulu', 'logo': 'https://www.thisishulu.com/app/uploads/2023/10/logo-gradient-3up.svg', 'providerId': '15'},
  ];

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _blinkAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(_blinkController);
    
    initPresenceTracking();
    loadAllDashboards();
    startCarousel();
  }

  Future<void> initPresenceTracking() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await FirebaseAuth.instance.signInAnonymously();
      user = FirebaseAuth.instance.currentUser;
    }
    if (user != null) {
      DatabaseReference presenceRef = FirebaseDatabase.instance.ref("active_users/${user.uid}");
      FirebaseDatabase.instance.ref(".info/connected").onValue.listen((event) {
        if (event.snapshot.value == false) return;
        presenceRef.onDisconnect().remove();
        presenceRef.set({'online': true, 'is_logged_in': !user!.isAnonymous, 'last_active': ServerValue.timestamp});
      });
    }
  }

  void startCarousel() {
    carouselTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (pageController.hasClients && trendingList.isNotEmpty) {
        int next = currentPage + 1;
        if (next >= (trendingList.length > 20 ? 20 : trendingList.length)) next = 0;
        pageController.animateToPage(next, duration: const Duration(milliseconds: 1200), curve: Curves.easeInOutCubic);
      }
    });
  }

  Future<void> _updateAmbientColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    try {
      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(NetworkImage(imageUrl));
      if (mounted) setState(() { ambientColor = palette.darkVibrantColor?.color ?? palette.dominantColor?.color ?? const Color(0xFF050505); });
    } catch (_) {}
  }

  @override
  void dispose() {
    _blinkController.dispose();
    carouselTimer?.cancel();
    pageController.dispose();
    searchController.dispose();
    debounce?.cancel();
    super.dispose();
  }

  // 🔥 DEEP OTT FILTERING ENGINE 🔥
  Future<void> loadAllDashboards([String? providerId]) async {
    setState(() { isLoading = true; selectedPlatform = providerId ?? 'all'; });
    try {
      String base = 'https://hannutvpn.hritikmishra862.workers.dev/3';
      String prov = (providerId != null && providerId != 'all') ? '&with_watch_providers=$providerId&watch_region=IN' : '';

      var responses = await Future.wait([
        http.get(Uri.parse('$base/trending/all/day?language=en-US$prov'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/movie?language=en-US&region=IN&sort_by=popularity.desc$prov'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/tv?language=en-US&sort_by=popularity.desc$prov'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=28$prov&sort_by=popularity.desc'), headers: kApiHeaders), 
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=10749$prov&sort_by=popularity.desc'), headers: kApiHeaders), 
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=27$prov&sort_by=popularity.desc'), headers: kApiHeaders), 
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=878$prov&sort_by=popularity.desc'), headers: kApiHeaders), // SciFi
        http.get(Uri.parse('$base/discover/tv?language=en-US&with_original_language=ko$prov&sort_by=popularity.desc'), headers: kApiHeaders), // KDrama
        http.get(Uri.parse('$base/discover/movie?language=en-US&include_adult=true&with_genres=10749,18$prov&sort_by=popularity.desc'), headers: kApiHeaders), 
      ]);

      trendingList = await compute(_parseTMDBJson, {'body': responses[0].body, 'forceType': null});
      top10India = await compute(_parseTMDBJson, {'body': responses[1].body, 'forceType': 'movie'});
      top10World = await compute(_parseTMDBJson, {'body': responses[2].body, 'forceType': 'tv'});
      actionList = await compute(_parseTMDBJson, {'body': responses[3].body, 'forceType': 'movie'});
      romanceList = await compute(_parseTMDBJson, {'body': responses[4].body, 'forceType': 'movie'});
      horrorList = await compute(_parseTMDBJson, {'body': responses[5].body, 'forceType': 'movie'});
      sciFiList = await compute(_parseTMDBJson, {'body': responses[6].body, 'forceType': 'movie'});
      kDramaList = await compute(_parseTMDBJson, {'body': responses[7].body, 'forceType': 'tv'});
      mature18List = await compute(_parseTMDBJson, {'body': responses[8].body, 'forceType': 'movie'});
      
      if (trendingList.isNotEmpty) _updateAmbientColor(trendingList[0]['posterUrl']);
      if (mounted) setState(() => isLoading = false);
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 🔥 DEEP PREDICTIVE SEARCH 🔥
  void onSearchChanged(String value) {
    if (value.isEmpty) { setState(() { isSearching = false; searchResults = []; }); return; }
    setState(() => isSearching = true);
    if (debounce?.isActive ?? false) debounce!.cancel();
    debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => isLoading = true);
      try {
        final url = 'https://hannutvpn.hritikmishra862.workers.dev/3/search/multi?query=${Uri.encodeComponent(value)}&language=en-US&include_adult=true';
        final res = await http.get(Uri.parse(url), headers: kApiHeaders);
        setState(() { searchResults = _parseTMDBJson({'body': res.body, 'forceType': null}); isLoading = false; });
      } catch (_) { setState(() => isLoading = false); }
    });
  }

  void launchPlayerDirect(Map<String, dynamic> media) {
    if (!continueWatchingList.any((m) => m['id'] == media['id'])) continueWatchingList.insert(0, media);

    final type = media['mediaType'] ?? 'movie';
    final tId = media['id'] is int ? media['id'] : int.tryParse(media['id'].toString()) ?? 0;
    int currentAdDuration = isNextAd10Sec ? 10 : 15;
    isNextAd10Sec = !isNextAd10Sec;

    Navigator.push(context, MaterialPageRoute(builder: (context) => SkippableAdScreen(adDuration: currentAdDuration, nextScreen: VideoPlayerPage(tmdbId: tId, mediaType: type, season: 1, episode: 1, movieTitle: media['title'] ?? 'Title', overview: media['overview'] ?? '', rating: media['rating'] ?? '9.0', year: media['year'] ?? '2024')))).then((_) => setState(() {}));
  }

  // 🔥 DEEP FILTER POPUP 🔥
  void _showDeepCategoryPopup(String title, String type, String genreOrLang) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF0F0F0F), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        String url = genreOrLang == "ko" 
            ? 'https://hannutvpn.hritikmishra862.workers.dev/3/discover/tv?language=en-US&with_original_language=ko&sort_by=popularity.desc'
            : 'https://hannutvpn.hritikmishra862.workers.dev/3/discover/$type?language=en-US&with_genres=$genreId&sort_by=popularity.desc';
            
        return FutureBuilder<http.Response>(
          future: http.get(Uri.parse(url), headers: kApiHeaders),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: Colors.redAccent)));
            final List raw = json.decode(snapshot.data!.body)['results'];
            return Container(
              height: MediaQuery.of(context).size.height * 0.85, padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("$title - Top 50 🔥", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: raw.length,
                      itemBuilder: (context, index) {
                        final media = raw[index];
                        if (media['poster_path'] == null) return const SizedBox();
                        return TvFocusButton(
                          onTap: () { Navigator.pop(context); launchPlayerDirect({'id': media['id'], 'title': media['name'] ?? media['title'], 'posterUrl': 'https://image.tmdb.org/t/p/w300${media['poster_path']}', 'mediaType': type}); },
                          borderRadius: BorderRadius.circular(8),
                          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: 'https://image.tmdb.org/t/p/w300${media['poster_path']}', fit: BoxFit.cover, memCacheWidth: 200)),
                        );
                      },
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 🔥 24 HOUR FIREBASE NOTIFICATIONS 🔥
  void _showNotifications() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent)),
        title: Row(children: const [Icon(Icons.notifications_active, color: Colors.redAccent), SizedBox(width: 10), Text("Firebase Alerts", style: TextStyle(color: Colors.white))]),
        content: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Today Special: New episodes of trending anime added. All servers stable.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            const Text("Update your app to v1.3.0!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => launchUrl(Uri.parse('https://t.me/HANNUTV'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download, color: Colors.white), label: const Text("Download Update", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  // 🔥 SUPPORT & LOGIN BOTTOM SHEET 🔥
  void _showSupportSheet() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    bool isGuest = currentUser == null || currentUser.isAnonymous;

    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("HANNUTV Support (v1.3.0)", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            if (isGuest)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {}, // Google Signin call here
                icon: const Icon(Icons.g_mobiledata, color: Colors.black, size: 32),
                label: const Text('Login / Sync Watchlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.telegram, color: Colors.blueAccent, size: 40), title: const Text("Join Telegram", style: TextStyle(color: Colors.white)),
              onTap: () => launchUrl(Uri.parse('https://t.me/HANNUTV'), mode: LaunchMode.externalApplication),
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Colors.greenAccent, size: 40), title: const Text("Join WhatsApp Channel", style: TextStyle(color: Colors.white)),
              onTap: () => launchUrl(Uri.parse('https://whatsapp.com/channel/0029VbE2Pb17z4kmfjF04P0v'), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      )
    );
  }

  // 🔥 8D GIANT TOP 10 NUMBER UI 🔥
  Widget buildGiantTop10List(String title, List<Map<String, dynamic>> moviesData) {
    if (moviesData.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 10), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: moviesData.length > 10 ? 10 : moviesData.length,
            itemBuilder: (context, index) {
              final media = moviesData[index];
              return TvFocusButton(
                onTap: () => launchPlayerDirect(media), borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 140, margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // GIANT BACKGROUND NUMBER (8D Look)
                      Positioned(left: -15, bottom: -30, child: Text('${index + 1}', style: TextStyle(fontSize: 160, fontWeight: FontWeight.w900, color: Colors.white.withOpacity(0.08), letterSpacing: -10))),
                      // ACTUAL POSTER ON TOP
                      Positioned(
                        right: 0, top: 10, bottom: 10, width: 105,
                        child: Container(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 15)]),
                          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: media['posterUrl'] != '' ? media['posterUrl'] : 'https://via.placeholder.com/300', fit: BoxFit.cover, memCacheWidth: 200)),
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
    );
  }

  Widget buildHorizontalList(String title, List<Map<String, dynamic>> moviesData) {
    if (moviesData.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 10), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: moviesData.length,
            itemBuilder: (context, index) {
              final media = moviesData[index];
              return TvFocusButton(
                onTap: () => launchPlayerDirect(media), borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 110, margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: media['posterUrl'] != '' ? media['posterUrl'] : 'https://via.placeholder.com/300', fit: BoxFit.cover, memCacheWidth: 200)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // 🔥 GLOWING GENRES FIXED LIST (No Red Screen) 🔥
  Widget buildGenresSection() {
    final genres = [
      {'name': 'Action', 'color': const [Color(0xFFFF5252), Color(0xFFB71C1C)], 'id': '28'},
      {'name': 'Romance', 'color': const [Color(0xFFFF4081), Color(0xFF880E4F)], 'id': '10749'},
      {'name': 'Thriller', 'color': const [Color(0xFF448AFF), Color(0xFF0D47A1)], 'id': '53'},
      {'name': 'Horror', 'color': const [Color(0xFF607D8B), Color(0xFF263238)], 'id': '27'},
      {'name': 'Sci-Fi', 'color': const [Color(0xFF00E676), Color(0xFF1B5E20)], 'id': '878'},
      {'name': 'Drama', 'color': const [Color(0xFFFFC107), Color(0xFFFF6F00)], 'id': '18'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 24, 16, 10), child: Text("Genres", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
        SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: genres.length,
            itemBuilder: (context, index) {
              final g = genres[index];
              return TvFocusButton(
                onTap: () => _showDeepCategoryPopup(g['name'] as String, 'movie', g['id'] as String), borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 120, margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: g['color'] as List<Color>, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: (g['color'] as List<Color>)[0].withOpacity(0.4), blurRadius: 10, spreadRadius: 1)],
                  ),
                  child: Center(child: Text(g['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, shadows: [Shadow(color: Colors.black, blurRadius: 5)]))),
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF050505), // Ultra Dark
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, automaticallyImplyLeading: false, 
        title: Row(children: [Image.asset('assets/logo.png', height: 28, errorBuilder: (_,__,___) => const Icon(Icons.movie, color: Colors.redAccent, size: 28)), const SizedBox(width: 8), const Text('HANNUTV', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))]),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () => setState(() => isSearching = true)),
          IconButton(icon: const Icon(Icons.bookmark_added, color: Colors.white), onPressed: () {}), // Watchlist Page
          IconButton(icon: const Icon(Icons.notifications, color: Colors.white), onPressed: _showNotifications),
          IconButton(icon: const Icon(Icons.support_agent, color: Colors.white), onPressed: _showSupportSheet),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔥 AMBIENT TOP CAROUSEL 🔥
            AnimatedContainer(
              duration: const Duration(milliseconds: 1000), curve: Curves.easeInOut,
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [ambientColor.withOpacity(0.7), const Color(0xFF050505)], stops: const [0.0, 0.7])),
              child: Stack(
                children: [
                  SizedBox(
                    height: 500,
                    child: trendingList.isEmpty ? const SizedBox() : PageView.builder(
                      controller: pageController, itemCount: trendingList.length > 20 ? 20 : trendingList.length,
                      onPageChanged: (index) { setState(() => currentPage = index); _updateAmbientColor(trendingList[index]['posterUrl']); },
                      itemBuilder: (context, index) {
                        return Container(
                          decoration: BoxDecoration(image: DecorationImage(image: CachedNetworkImageProvider(trendingList[index]['posterUrl'] != '' ? trendingList[index]['posterUrl'] : 'https://via.placeholder.com/600x900'), fit: BoxFit.cover, alignment: Alignment.topCenter)),
                          foregroundDecoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [const Color(0xFF050505), Colors.transparent, Colors.black.withOpacity(0.6)])),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        // 🔥 TABS & BLINKING LIVE TV 🔥
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)), child: const Text("HANNU TRENDING", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("Anime", "tv", "16"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Anime", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("Movies", "movie", "28"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Movies", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("Series", "tv", "10759"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Series", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("KDrama", "tv", "ko"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("KDrama", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveTvChannelsPage())), borderRadius: BorderRadius.circular(20), 
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), 
                                  child: Row(children: [const Text("Live TV", style: TextStyle(color: Colors.white)), const SizedBox(width: 6), FadeTransition(opacity: _blinkAnimation, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)))])
                                )
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trendingList.isNotEmpty && !isSearching)
                    Positioned(
                      bottom: 20, left: 16, right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(trendingList[currentPage]['title'] ?? 'Title', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, fontFamily: 'serif', letterSpacing: 1.0, shadows: [Shadow(color: Colors.black, blurRadius: 10)]), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(children: [const Icon(Icons.thumb_up, color: Colors.amber, size: 16), const SizedBox(width: 4), Text(trendingList[currentPage]['rating'], style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)), const SizedBox(width: 12), Text(trendingList[currentPage]['year'], style: const TextStyle(color: Colors.white70)), const SizedBox(width: 12), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(4)), child: const Text("HD", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))]),
                          const SizedBox(height: 12),
                          Text(trendingList[currentPage]['overview'], style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: TvFocusButton(onTap: () => launchPlayerDirect(trendingList[currentPage]), borderRadius: BorderRadius.circular(30), child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(30)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.play_arrow, color: Colors.white), SizedBox(width: 8), Text("Watch Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))])))),
                              const SizedBox(width: 16),
                              Expanded(child: TvFocusButton(onTap: () {}, borderRadius: BorderRadius.circular(30), child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: Colors.transparent, border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(30)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add, color: Colors.white), SizedBox(width: 8), Text("My List", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))])))),
                            ],
                          )
                        ],
                      ),
                    ),
                ],
              ),
            ),
            
            // 🔥 SEARCH RESULTS FIX 🔥
            if (isSearching && searchController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: searchController, style: const TextStyle(color: Colors.white), autofocus: true,
                  decoration: InputDecoration(hintText: 'Search Google API / TMDB...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), prefixIcon: const Icon(Icons.search, color: Colors.redAccent), suffixIcon: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () { setState(() { isSearching = false; searchController.clear(); searchResults.clear(); }); })),
                  onChanged: onSearchChanged,
                ),
              ),

            if (isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator(color: Colors.redAccent)))
            else if (isSearching)
              GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: searchResults.length,
                itemBuilder: (context, index) {
                  final movie = searchResults[index];
                  return TvFocusButton(
                    onTap: () => launchPlayerDirect(movie), borderRadius: BorderRadius.circular(8),
                    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: movie['posterUrl'] != '' ? movie['posterUrl'] : 'https://via.placeholder.com/300', fit: BoxFit.cover, memCacheWidth: 200)),
                  );
                },
              )
            else ...[
              // 🔥 REAL OTT PLATFORM LOGOS 🔥
              SizedBox(
                height: 65,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: ottPlatforms.length,
                  itemBuilder: (context, index) {
                    final srv = ottPlatforms[index];
                    final isSelected = selectedPlatform == srv['providerId'];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      child: TvFocusButton(
                        onTap: () { loadAllDashboards(srv['providerId']); }, borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(30), border: Border.all(color: isSelected ? Colors.white : Colors.white24)),
                          child: Row(
                            children: [
                              if (srv['logo'] != "") ...[ClipOval(child: CachedNetworkImage(imageUrl: srv['logo'], height: 35, width: 35, fit: BoxFit.cover)), const SizedBox(width: 10)],
                              Text(srv['name'], style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              buildGiantTop10List('Top 10 in India', top10India),
              buildGenresSection(),
              buildGiantTop10List('Top 10 Worldwide', top10World),
              
              if (continueWatchingList.isNotEmpty) buildHorizontalList('Continue Watching', continueWatchingList),
              
              // 🔥 DYNAMIC OTT CATEGORIES (Changes when OTT is clicked) 🔥
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Action', actionList),
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Romance', romanceList),
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Horror', horrorList),
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Sci-Fi', sciFiList),
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} KDrama', kDramaList),
              buildHorizontalList('18+ Mature & Erotic 🔥', mature18List),
              
              const SizedBox(height: 60),
            ],
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
  const TvFocusButton({super.key, required this.child, required this.onTap, required this.borderRadius});
  @override
  State<TvFocusButton> createState() => TvFocusButtonState();
}
class TvFocusButtonState extends State<TvFocusButton> {
  bool hasFocus = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focus) { if (mounted) setState(() => hasFocus = focus); },
      child: InkWell(
        onTap: widget.onTap, borderRadius: widget.borderRadius,
        child: AnimatedContainer(duration: const Duration(milliseconds: 150), decoration: BoxDecoration(borderRadius: widget.borderRadius, border: Border.all(color: hasFocus ? Colors.redAccent : Colors.transparent, width: hasFocus ? 3.5 : 0), boxShadow: hasFocus ? [BoxShadow(color: Colors.redAccent.withOpacity(0.65), blurRadius: 10)] : []), child: widget.child),
      ),
    );
  }
}

// 🔥 LIVE TV CODE RESTORED EXACTLY AS PREVIOUS 🔥
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
      final response = await http.get(Uri.parse('https://iptv-org.github.io/iptv/index.category.m3u'));
      if (response.statusCode == 200) {
        List<String> lines = response.body.split('\n');
        final Map<String, Map<String, String>> byUrl = {}; 
        final Map<String, Set<String>> catsByUrl = {};
        String currentName = ''; String currentLogo = ''; String currentGroup = '';

        for (String rawLine in lines) {
          final String line = rawLine.trim();
          if (line.startsWith('#EXTINF:')) {
            RegExp logoRegex = RegExp(r'tvg-logo="([^"]*)"');
            var match = logoRegex.firstMatch(line);
            currentLogo = match != null ? match.group(1)! : '';
            var groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
            currentGroup = groupMatch != null ? groupMatch.group(1)!.trim() : '';
            List<String> splitComma = line.split(',');
            if (splitComma.length > 1) currentName = splitComma.last.trim();
          } else if (line.startsWith('http')) {
            if (currentName.isNotEmpty) {
              final cats = currentGroup.split(';').map((c) => c.trim()).where((c) => c.isNotEmpty).map((c) => c.toLowerCase() == 'undefined' ? 'Other' : c).toList();
              if (cats.isEmpty) cats.add('Other');
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
          for (final c in cats) { counts[c] = (counts[c] ?? 0) + 1; }
          parsed.add(ch);
        });

        final List<String> sortedCats = counts.keys.toList()..sort((a, b) {
            if (a == 'Other') return 1;
            if (b == 'Other') return -1;
            return counts[b]!.compareTo(counts[a]!);
          });

        setState(() {
          allChannels = parsed; filteredChannels = parsed; categoryCounts = counts;
          categories = ['All', ...sortedCats]; isLoading = false;
        });
      }
    } catch (_) { setState(() => isLoading = false); }
  }

  void filterChannels(String query) {
    setState(() {
      filteredChannels = allChannels.where((c) {
        final matchesName = c['name']!.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = selectedCategory == 'All' || (c['group'] ?? '').split(';').contains(selectedCategory);
        return matchesName && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(backgroundColor: const Color(0xFF151515), title: const Text('Live TV Channels', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), iconTheme: const IconThemeData(color: Colors.white)),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(16.0), child: TextField(controller: tvSearchController, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Search Live Channels...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.black87, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), prefixIcon: const Icon(Icons.search, color: Colors.redAccent)), onChanged: filterChannels)),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final cat = categories[i]; final bool selected = cat == selectedCategory;
                return ChoiceChip(label: Text('$cat (${cat == 'All' ? allChannels.length : categoryCounts[cat]})'), selected: selected, selectedColor: Colors.redAccent, backgroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Colors.white12), labelStyle: TextStyle(color: Colors.white, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal), onSelected: (_) { selectedCategory = cat; filterChannels(tvSearchController.text); });
              },
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : GridView.builder(
                    padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.8), itemCount: filteredChannels.length,
                    itemBuilder: (context, index) {
                      final ch = filteredChannels[index];
                      return InkWell(
                        onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => SkippableAdScreen(adDuration: 30, nextScreen: VideoPlayerPage(tmdbId: 0, mediaType: 'tv', season: 1, episode: 1, movieTitle: ch['name']!, overview: 'Live TV Broadcast', rating: 'Live', year: 'Now', customUrl: ch['url'])))); },
                        child: Container(
                          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Expanded(child: Padding(padding: const EdgeInsets.all(8.0), child: ch['logo']!.isNotEmpty ? CachedNetworkImage(imageUrl: ch['logo']!, errorWidget: (_, __, ___) => const Icon(Icons.tv, color: Colors.white54, size: 40)) : const Icon(Icons.tv, color: Colors.white54, size: 40))), Container(padding: const EdgeInsets.all(8), width: double.infinity, decoration: const BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.vertical(bottom: Radius.circular(12))), child: Text(ch['name']!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center))]),
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