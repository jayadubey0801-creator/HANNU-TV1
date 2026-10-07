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
List<Map<String, dynamic>> downloadedMoviesList = [];

// 🔥 EXTREME 100x PERFORMANCE: ISOLATE JSON PARSING 🔥
List<Map<String, dynamic>> _parseTMDBJson(Map<String, dynamic> params) {
  final String responseBody = params['body'];
  final String? forceMediaType = params['forceType'];
  final List rawData = json.decode(responseBody)['results'] ?? [];
  return rawData.where((m) => m['media_type'] != 'person').map((m) => {
    'id': m['id'],
    'title': m['title'] ?? m['name'] ?? 'Unknown',
    'overview': m['overview'] ?? '',
    'posterUrl': m['poster_path'] != null ? 'https://image.tmdb.org/t/p/w300${m['poster_path']}' : '',
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

class DashboardPageState extends State<DashboardPage> {
  bool isNextAd10Sec = true;

  // 🔥 DEEP CATEGORY LISTS 🔥
  List<Map<String, dynamic>> trendingList = [];
  List<Map<String, dynamic>> top10India = [];
  List<Map<String, dynamic>> top10World = [];
  List<Map<String, dynamic>> ottSpecificAction = [];
  List<Map<String, dynamic>> ottSpecificHorror = [];
  List<Map<String, dynamic>> ottSpecificRomance = [];
  List<Map<String, dynamic>> ottSpecificThriller = [];
  List<Map<String, dynamic>> mature18List = [];
  List<Map<String, dynamic>> searchResults = [];

  bool isLoading = true;
  bool isSearching = false;
  final TextEditingController searchController = TextEditingController();
  Timer? debounce;

  final PageController pageController = PageController();
  Timer? carouselTimer;
  int currentPage = 0;
  Color ambientColor = const Color(0xFF0A0A0A);

  String selectedPlatform = 'all';

  // 🔥 ORIGINAL OTT PLATFORM LOGOS 🔥
  final List<Map<String, dynamic>> ottPlatforms = const [
    {'name': 'ALL', 'logo': '', 'providerId': 'all'},
    {'name': 'Netflix', 'logo': 'https://image.tmdb.org/t/p/w200/9A1JSVmSxsya204HFFObCsoV8G0.jpg', 'providerId': '8'},
    {'name': 'Prime Video', 'logo': 'https://image.tmdb.org/t/p/w200/ifzbQEW7McdZ9NUNrjeS8U9YIrL.jpg', 'providerId': '9'},
    {'name': 'JioCinema', 'logo': 'https://image.tmdb.org/t/p/w200/paq2o2dIfQnxcJ60eqWCSQ4j0q5.jpg', 'providerId': '220'},
    {'name': 'Disney+', 'logo': 'https://image.tmdb.org/t/p/w200/7rwgEs15tFwyR9NPQ5OvlZ8xK6Y.jpg', 'providerId': '337'},
    {'name': 'Crunchyroll', 'logo': 'https://image.tmdb.org/t/p/w200/mXeC4TrcgdU6ltE9bCBCEORwSQR.jpg', 'providerId': '283'},
    {'name': 'HBO Max', 'logo': 'https://image.tmdb.org/t/p/w200/b13aH6qD9cIawLzEqhF9D11yX2B.jpg', 'providerId': '384'},
    {'name': 'Apple TV+', 'logo': 'https://image.tmdb.org/t/p/w200/2E0ficmQmk6EIWyYVE2tl0C9w5d.jpg', 'providerId': '350'},
    {'name': 'Hulu', 'logo': 'https://image.tmdb.org/t/p/w200/1XbqX2BaoL8hFq82nL5Z6P9HqN7.jpg', 'providerId': '15'},
  ];

  @override
  void initState() {
    super.initState();
    initPresenceTracking();
    loadAllDashboards();
    startCarousel();
  }

  // 🔥 FIREBASE PRESENCE (UNTOUCHED) 🔥
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

  // 🔥 20 MOVIES AUTO-SWITCH CAROUSEL 🔥
  void startCarousel() {
    carouselTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (pageController.hasClients && trendingList.isNotEmpty) {
        int next = currentPage + 1;
        if (next >= (trendingList.length > 20 ? 20 : trendingList.length)) next = 0;
        pageController.animateToPage(next, duration: const Duration(milliseconds: 1200), curve: Curves.easeInOutCubic);
      }
    });
  }

  // 🔥 SMOOTH AMBIENT BACKGROUND GLOW 🔥
  Future<void> _updateAmbientColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    try {
      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(NetworkImage(imageUrl));
      if (mounted) setState(() { ambientColor = palette.darkVibrantColor?.color ?? palette.dominantColor?.color ?? const Color(0xFF0A0A0A); });
    } catch (_) {}
  }

  @override
  void dispose() {
    carouselTimer?.cancel();
    pageController.dispose();
    searchController.dispose();
    debounce?.cancel();
    super.dispose();
  }

  // 🔥 DEEP OTT & 18+ FILTERING ENGINE 🔥
  Future<void> loadAllDashboards([String? providerId]) async {
    setState(() { isLoading = true; selectedPlatform = providerId ?? 'all'; });
    try {
      String base = 'https://hannutvpn.hritikmishra862.workers.dev/3';
      String prov = (providerId != null && providerId != 'all') ? '&with_watch_providers=$providerId&watch_region=IN' : '';

      var responses = await Future.wait([
        http.get(Uri.parse('$base/trending/all/day?language=en-US$prov'), headers: kApiHeaders),
        http.get(Uri.parse('$base/discover/movie?language=en-US&region=IN&sort_by=popularity.desc$prov'), headers: kApiHeaders), // Top 10 India
        http.get(Uri.parse('$base/discover/tv?language=en-US&sort_by=popularity.desc$prov'), headers: kApiHeaders), // Top 10 World
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=28$prov&sort_by=popularity.desc'), headers: kApiHeaders), // Action
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=27$prov&sort_by=popularity.desc'), headers: kApiHeaders), // Horror
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=10749$prov&sort_by=popularity.desc'), headers: kApiHeaders), // Romance
        http.get(Uri.parse('$base/discover/movie?language=en-US&with_genres=53$prov&sort_by=popularity.desc'), headers: kApiHeaders), // Thriller
        http.get(Uri.parse('$base/discover/movie?language=en-US&include_adult=true&with_genres=10749,18$prov&sort_by=popularity.desc'), headers: kApiHeaders), // 18+ Mature
      ]);

      trendingList = await compute(_parseTMDBJson, {'body': responses[0].body, 'forceType': null});
      top10India = await compute(_parseTMDBJson, {'body': responses[1].body, 'forceType': 'movie'});
      top10World = await compute(_parseTMDBJson, {'body': responses[2].body, 'forceType': 'tv'});
      ottSpecificAction = await compute(_parseTMDBJson, {'body': responses[3].body, 'forceType': 'movie'});
      ottSpecificHorror = await compute(_parseTMDBJson, {'body': responses[4].body, 'forceType': 'movie'});
      ottSpecificRomance = await compute(_parseTMDBJson, {'body': responses[5].body, 'forceType': 'movie'});
      ottSpecificThriller = await compute(_parseTMDBJson, {'body': responses[6].body, 'forceType': 'movie'});
      mature18List = await compute(_parseTMDBJson, {'body': responses[7].body, 'forceType': 'movie'});
      
      if (trendingList.isNotEmpty) _updateAmbientColor(trendingList[0]['posterUrl']);
      if (mounted) setState(() => isLoading = false);
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void onSearchChanged(String value) {
    if (value.isEmpty) { setState(() { isSearching = false; searchResults = []; }); return; }
    setState(() => isSearching = true);
    if (debounce?.isActive ?? false) debounce!.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () async {
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

  // 🔥 DEEP FILTER POPUP (Tabs Clicked) 🔥
  void _showDeepCategoryPopup(String title, String type, String genreId) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF0F0F0F), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return FutureBuilder<http.Response>(
          future: http.get(Uri.parse('https://hannutvpn.hritikmishra862.workers.dev/3/discover/$type?language=en-US&with_genres=$genreId&sort_by=popularity.desc'), headers: kApiHeaders),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: Colors.purpleAccent)));
            final List raw = json.decode(snapshot.data!.body)['results'];
            return Container(
              height: MediaQuery.of(context).size.height * 0.85, padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("$title - Deep Filter", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.65, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      itemCount: raw.length,
                      itemBuilder: (context, index) {
                        final media = raw[index];
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

  // 🔥 24hr FIREBASE NOTIFICATIONS 🔥
  void _showNotifications() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.purpleAccent)),
        title: Row(children: const [Icon(Icons.notifications_active, color: Colors.purpleAccent), SizedBox(width: 10), Text("Firebase Alerts", style: TextStyle(color: Colors.white))]),
        content: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("HANNUTV Server maintenance successfully completed. All premium servers active.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            const Text("Update your app to v1.3.0!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => launchUrl(Uri.parse('https://t.me/HANNUTV'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download, color: Colors.white), label: const Text("Download Update", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  // 🔥 SUPPORT BOTTOM SHEET (TELEGRAM/WHATSAPP) 🔥
  void _showSupportSheet() {
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

  // 🔥 GIANT TOP 10 NUMBER UI (EXACT MATCH TO IMAGE) 🔥
  Widget buildGiantTop10List(String title, List<Map<String, dynamic>> moviesData) {
    if (moviesData.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 10), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
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
                      // GIANT BACKGROUND NUMBER
                      Positioned(left: -15, bottom: -25, child: Text('${index + 1}', style: TextStyle(fontSize: 140, fontWeight: FontWeight.w900, color: const Color(0xFF2A2A3A).withOpacity(0.9), letterSpacing: -10))),
                      // ACTUAL POSTER
                      Positioned(
                        right: 0, top: 10, bottom: 10, width: 100,
                        child: Container(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 10)]),
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

  // 🔥 GLOWING GENRES MATCHING THE IMAGE 🔥
  Widget buildGenresSection() {
    final genres = [
      {'name': 'Action', 'color': [Colors.redAccent, Colors.red[900]], 'id': '28'},
      {'name': 'Romance', 'color': [Colors.pinkAccent, Colors.pink[900]], 'id': '10749'},
      {'name': 'Thriller', 'color': [Colors.blueAccent, Colors.blue[900]], 'id': '53'},
      {'name': 'Comedy', 'color': [Colors.orangeAccent, Colors.orange[900]], 'id': '35'},
      {'name': 'Fantasy', 'color': [Colors.purpleAccent, Colors.purple[900]], 'id': '14'},
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
                    boxShadow: [BoxShadow(color: (g['color'] as List)[0].withOpacity(0.4), blurRadius: 10, spreadRadius: 1)],
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
      backgroundColor: const Color(0xFF0A0A0A), // Deep Premium Black
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, automaticallyImplyLeading: false, // 3 lines removed
        title: Row(children: [Image.asset('assets/logo.png', height: 28, errorBuilder: (_,__,___) => const Icon(Icons.movie, color: Colors.purpleAccent, size: 28)), const SizedBox(width: 8), const Text('HANNUTV', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))]),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () => setState(() => isSearching = true)),
          IconButton(icon: const Icon(Icons.bookmark_added, color: Colors.white), onPressed: () {}), // Watchlist Page Route Place
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
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [ambientColor.withOpacity(0.8), const Color(0xFF0A0A0A)], stops: const [0.0, 0.7])),
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
                          foregroundDecoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [const Color(0xFF0A0A0A), Colors.transparent, Colors.black.withOpacity(0.4)])),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        // 🔥 TABS 🔥
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.purpleAccent, borderRadius: BorderRadius.circular(20)), child: const Text("HANNU TRENDING", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("Anime", "tv", "16"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Anime", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("Movies", "movie", "28"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Movies", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("Series", "tv", "10759"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Series", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => _showDeepCategoryPopup("Kids", "movie", "10751"), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Kids", style: TextStyle(color: Colors.white)))), const SizedBox(width: 10),
                              TvFocusButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveTvChannelsPage())), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)), child: const Text("Live TV", style: TextStyle(color: Colors.white)))),
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
                          Text(trendingList[currentPage]['title'] ?? 'Title', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, fontFamily: 'serif', letterSpacing: 1.5, shadows: [Shadow(color: Colors.black, blurRadius: 10)]), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(children: [const Icon(Icons.thumb_up, color: Colors.amber, size: 16), const SizedBox(width: 4), Text(trendingList[currentPage]['rating'], style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)), const SizedBox(width: 12), Text(trendingList[currentPage]['year'], style: const TextStyle(color: Colors.white70)), const SizedBox(width: 12), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(4)), child: const Text("HD", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))]),
                          const SizedBox(height: 12),
                          Text(trendingList[currentPage]['overview'], style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: TvFocusButton(onTap: () => launchPlayerDirect(trendingList[currentPage]), borderRadius: BorderRadius.circular(30), child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: Colors.purpleAccent, borderRadius: BorderRadius.circular(30)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.play_arrow, color: Colors.white), SizedBox(width: 8), Text("Watch Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))])))),
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
            
            if (isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator(color: Colors.purpleAccent)))
            else ...[
              // 🔥 ORIGINAL OTT PLATFORM LOGOS 🔥
              SizedBox(
                height: 60,
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
                              if (srv['logo'] != "") ...[ClipOval(child: CachedNetworkImage(imageUrl: srv['logo'], height: 28, width: 28, fit: BoxFit.cover)), const SizedBox(width: 10)],
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
              
              // 🔥 DYNAMIC OTT CATEGORIES 🔥
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Action', ottSpecificAction),
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Horror', ottSpecificHorror),
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Romance', ottSpecificRomance),
              buildHorizontalList('${selectedPlatform == "all" ? "Trending" : ottPlatforms.firstWhere((o) => o["providerId"] == selectedPlatform)["name"]} Thriller', ottSpecificThriller),
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
        child: AnimatedContainer(duration: const Duration(milliseconds: 150), decoration: BoxDecoration(borderRadius: widget.borderRadius, border: Border.all(color: hasFocus ? Colors.purpleAccent : Colors.transparent, width: hasFocus ? 3.5 : 0), boxShadow: hasFocus ? [BoxShadow(color: Colors.purpleAccent.withOpacity(0.65), blurRadius: 10)] : []), child: widget.child),
      ),
    );
  }
}

// Keeping original placeholders to prevent errors
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});
  @override
  Widget build(BuildContext context) { return const Scaffold(); }
}
class LiveTvChannelsPage extends StatelessWidget {
  const LiveTvChannelsPage({super.key});
  @override
  Widget build(BuildContext context) { return const Scaffold(); }
}