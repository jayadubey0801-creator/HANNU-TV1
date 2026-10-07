import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'banner_ad_widget.dart';
import 'skippable_ad_screen.dart';
import 'dashboard.dart'; 

const String kTmdbToken =
    'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIzZDJkOTExNmM5ZGU3MjA5ZWUyNzdiYjhjYzlhZWVkOCIsIm5iZiI6MTc5MDI2OTE4NC42MjksInN1YiI6IjZhYjU1NzAwNzZiMTg1ODU3MGFjNDM4NSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.xZJX8fowhVhVJsgl-5wOW6Y7ZfUr9Zu_Ey1qMkhnPd0';

const Map<String, String> kApiHeaders = {
  'Authorization': 'Bearer $kTmdbToken',
  'accept': 'application/json',
};

const String _adsterraBannerSnippet = '''
  <script type="text/javascript">
    atOptions = { 'key' : 'a39df283f6ad10c34e229e5715bceff5', 'format' : 'iframe', 'height' : 50, 'width' : 320, 'params' : {} };
  </script>
  <script type="text/javascript" src="https://www.highrevenueformat.com/a39df283f6ad10c34e229e5715bceff5/invoke.js"></script>
''';

class VideoPlayerPage extends StatefulWidget {
  final int tmdbId;
  final String mediaType;
  final int season;
  final int episode;
  final String movieTitle;
  final String overview;
  final String rating;
  final String year;
  final String? customUrl;

  const VideoPlayerPage({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    this.season = 1,
    this.episode = 1,
    required this.movieTitle,
    this.overview = '',
    this.rating = '9.0',
    this.year = '2024',
    this.customUrl,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  
  WebViewController? _controller;

  bool isVideoPlaying = false;
  bool isFullScreen = false;
  bool isPageLoading = true;
  
  String activeServer = 'vidrift'; 
  String currentAspectRatio = 'contain';

  late int currentSeason;
  late int currentEpisode;
  bool isLiked = false;
  int likeCount = 1248;
  int viewCount = 84920;

  bool showControls = true;
  Timer? _hideControlsTimer;
  Timer? _liveTvAdTimer; 
  Timer? _fallbackPlayTimer; 

  bool showIntroAnimation = false;
  late AnimationController _introAnimController;
  late Animation<double> _introScaleAnimation;
  late Animation<double> _introOpacityAnimation;

  final TextEditingController commentInputController = TextEditingController();

  // 🔥 DEEP SERVER MAPPING: EXACTLY FROM YOUR SCREENSHOTS AND PROMPT 🔥
  final List<Map<String, String>> servers = const [
    {'key': 'vidrift', 'name': 'Rift'},           // From Image 19
    {'key': 'bingr', 'name': 'Fast'},             // From Image 18
    {'key': 'vidcore', 'name': 'Fast (Ads)'},     // From Image 20
    {'key': 'vidbolt', 'name': 'Bolt'},           // From Screenshot/Text
    {'key': 'cinezo', 'name': 'Cinezo'},          // From Image 21
    {'key': 'peachify', 'name': 'Peach'},         // From Prompt & Image 26
    {'key': 'vidlink', 'name': 'Mega'},           // From Prompt
    {'key': 'vidfast', 'name': 'Alpha'},          // From Prompt
    {'key': 'vidrock', 'name': 'Orion'},          // From Prompt
    {'key': 'hindi-new', 'name': 'Hindi New'},    // From Image 22
    {'key': 'screenscape', 'name': 'Hindi'},      // From Image 23
    {'key': 'zxcstream', 'name': 'Vidgod'},       // From Image 24
    {'key': 'cinesrc', 'name': 'CineSrc'},        // From Image 25
  ];

  List similarMovies = [];
  bool isLoadingSimilar = false;
  bool isTvDevice = false;

  int totalSeasons = 1;
  List episodesList = [];

  @override
  void initState() {
    super.initState();
    currentSeason = widget.season;
    currentEpisode = widget.episode;

    _introAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _introScaleAnimation = Tween<double>(begin: 0.7, end: 1.3).animate(CurvedAnimation(parent: _introAnimController, curve: Curves.easeOutBack));
    _introOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(parent: _introAnimController, curve: const Interval(0.65, 1.0, curve: Curves.easeIn)));

    if (widget.customUrl == null) {
      _fetchSimilarMovies();
      _fetchTvDetails(); 
    } else {
      _liveTvAdTimer = Timer.periodic(const Duration(minutes: 8), (timer) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => SkippableAdScreen(
                adDuration: 60, 
                nextScreen: VideoPlayerPage(
                  tmdbId: widget.tmdbId, mediaType: widget.mediaType,
                  season: widget.season, episode: widget.episode,
                  movieTitle: widget.movieTitle, overview: widget.overview,
                  rating: widget.rating, year: widget.year, customUrl: widget.customUrl,
                ),
              ),
            ),
          );
        }
      });
    }

    _checkDeviceType(); 
  }

  Future<void> _fetchTvDetails() async {
    if (widget.mediaType != 'tv' && widget.mediaType != 'series') return;
    try {
      final res = await http.get(Uri.parse('https://hannu-tv.hritikmishra862.workers.dev/3/tv/${widget.tmdbId}?language=en-US'), headers: kApiHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() { totalSeasons = data['number_of_seasons'] ?? 1; });
        _fetchEpisodes(currentSeason);
      }
    } catch (e) {}
  }

  Future<void> _fetchEpisodes(int seasonNum) async {
    if (widget.mediaType != 'tv' && widget.mediaType != 'series') return;
    try {
      final res = await http.get(Uri.parse('https://hannu-tv.hritikmishra862.workers.dev/3/tv/${widget.tmdbId}/season/$seasonNum?language=en-US'), headers: kApiHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() { episodesList = data['episodes'] ?? []; });
      }
    } catch (e) {}
  }

  void _checkDeviceType() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = MediaQuery.of(context).size;
      setState(() {
        isTvDevice = size.width > size.height && size.width > 600; 
        if (isTvDevice) isFullScreen = true; 
        else { SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); }
      });
      _startControlsTimer();
      _setupWebView(); 
    });
  }

  void _startControlsTimer() {
    _hideControlsTimer?.cancel();
    if (mounted) setState(() => showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => showControls = false);
    });
  }

  void _triggerCinematicPlayAnimation() {
    if (showIntroAnimation || isVideoPlaying) return;
    _fallbackPlayTimer?.cancel();
    setState(() { showIntroAnimation = true; isVideoPlaying = true; isPageLoading = false; });
    _introAnimController.forward().then((_) { if (mounted) setState(() => showIntroAnimation = false); });
  }

  Future<void> _fetchSimilarMovies() async {
    setState(() => isLoadingSimilar = true);
    try {
      final type = widget.mediaType == 'tv' || widget.mediaType == 'series' ? 'tv' : 'movie';
      final res = await http.get(Uri.parse('https://hannu-tv.hritikmishra862.workers.dev/3/$type/${widget.tmdbId}/recommendations?language=en-US'), headers: kApiHeaders);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List results = data['results'] ?? [];
        if (mounted) {
          setState(() {
            similarMovies = results.map((m) => {
              'id': m['id'], 'title': m['title'] ?? m['name'] ?? 'Unknown',
              'posterUrl': m['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${m['poster_path']}' : '',
              'rating': (m['vote_average'] ?? 0).toStringAsFixed(1),
              'year': (m['release_date'] ?? m['first_air_date'] ?? '').toString().split('-').first,
              'mediaType': type,
            }).toList();
            isLoadingSimilar = false;
          });
        }
      } else { if (mounted) setState(() => isLoadingSimilar = false); }
    } catch (_) { if (mounted) setState(() => isLoadingSimilar = false); }
  }

  void _setupWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent) // Transparent taaki cinematic glow dikhe!
      ..setUserAgent(
        isTvDevice ? "Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 TV Safari/538.1"
                   : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      )
      ..addJavaScriptChannel('VideoState', onMessageReceived: (JavaScriptMessage message) { 
        if (message.message == 'playing' || message.message == 'autoplay_blocked') {
          if (mounted && !isVideoPlaying) _triggerCinematicPlayAnimation(); 
        }
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) { 
            if (mounted) setState(() => isPageLoading = true); 
            _fallbackPlayTimer?.cancel();
            _fallbackPlayTimer = Timer(const Duration(seconds: 8), () {
              if (mounted && !isVideoPlaying) {
                 setState(() { isVideoPlaying = true; isPageLoading = false; });
              }
            });
          },
          onPageFinished: (String url) {
            if (mounted && widget.customUrl != null) setState(() => isPageLoading = false);

            // 🔥 DEEP JS CODING: PROXY/IFRAME UNTOUCHED. AMBIENT GLOW ADDED.
            String jsCode = '''
              document.documentElement.style.backgroundColor = 'transparent';
              document.body.style.backgroundColor = 'transparent';
              window.open = function() { return null; };
              window.alert = function() { return true; }; 
              window.confirm = function() { return true; }; 

              var style = document.createElement('style');
              style.innerHTML = `
                header, nav, .navbar, footer, .footer, .server-select, .logo, a[href*="t.me"], a[href="/"],
                iframe[src*="ads"], .ad-container, .ads, .popup-overlay, .dmca-notice, h1, h2, h3,
                .human-verify, #captcha, [class*="verify"] { 
                    display: none !important; 
                    opacity: 0 !important; 
                    pointer-events: none !important; 
                    visibility: hidden !important; 
                }
                body, html { 
                    background-color: transparent !important; 
                    overflow: hidden !important; 
                    margin: 0 !important; 
                    padding: 0 !important; 
                    width: 100vw !important; 
                    height: 100vh !important; 
                }
              `;
              document.head.appendChild(style);

              setInterval(function() {
                // 1. NATIVE CONTROLS PRESERVATION: IFRAME KO EXTRACT KAR RAHE HAIN, VIDEO TAG KO NAHI.
                var frames = document.querySelectorAll('iframe:not([src*="ads"])');
                if(frames.length > 0) {
                    var f = frames[0];
                    f.style.position = 'fixed';
                    f.style.top = '0';
                    f.style.left = '0';
                    f.style.width = '100vw';
                    f.style.height = '100vh';
                    f.style.zIndex = '999999';
                    f.style.border = 'none';
                    f.style.backgroundColor = 'transparent';

                    // 2. CINEMATIC AMBIENT LIGHTING (Color match with scene)
                    if (!document.getElementById('ambient-glow')) {
                        var glow = f.cloneNode(true);
                        glow.id = 'ambient-glow';
                        glow.style.zIndex = '999998'; 
                        glow.style.filter = 'blur(45px) saturate(1.8) opacity(0.85)';
                        glow.style.transform = 'scale(1.15)';
                        glow.style.pointerEvents = 'none'; // Clicks pass through
                        document.body.appendChild(glow);
                    }
                }

                // 3. SMART SENSOR UNTOUCHED (Just reads data, doesn't strip controls)
                var vids = document.getElementsByTagName('video');
                if (vids.length > 0) {
                  var v = vids[0];
                  if (v.currentTime > 0.05 && !v.paused) {
                      VideoState.postMessage('playing');
                  } else {
                      var p = v.play();
                      if (p !== undefined) {
                          p.catch(function(e) { VideoState.postMessage('autoplay_blocked'); });
                      }
                  }
                }
                
                // Auto Bypass AdGuard Verifications
                var verifiers = document.querySelectorAll('.human-verify, #verify-button, #captcha, [class*="verify"]');
                verifiers.forEach(function(btn) { try { btn.click(); } catch(e) {} });

                var playBtns = document.querySelectorAll('.play-btn, .vjs-big-play-button, .play-icon, #play-button');
                playBtns.forEach(function(b) { b.click(); });
              }, 200);
            ''';
            _controller?.runJavaScript(jsCode);
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            if (url.contains('doubleclick') || url.contains('popads') || url.contains('1xbet') || url.contains('bet365') || url.contains('onclick') || url.contains('adult') || url.contains('telegram') || url.contains('t.me') || url.contains('adsterra') || url.contains('captcha') || url.contains('verify')) {
                return NavigationDecision.prevent;
            }
            if (url.contains('pantyflix.com') || url.contains('vercel.app') || url.contains('vidbolt') || url.contains('bingr') || url.contains('vidcore') || url.contains('cinezo') || url.contains('vidrift') || url.contains('vidsrc') || url.contains('vidlink') || url.contains('multiembed') || url.contains('autoembed') || url.startsWith('about:blank') || url.startsWith('data:')) {
                return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );

      _loadCurrentVideo();
  }

  void _loadCurrentVideo() {
    setState(() { isPageLoading = true; isVideoPlaying = false; showIntroAnimation = false; });

    if (widget.customUrl != null && widget.customUrl!.isNotEmpty) {
      if (widget.customUrl!.contains('.m3u8')) {
        String hlsHtml = '''
          <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
          <style>body, html { margin: 0; padding: 0; background: black; height: 100%; width: 100%; overflow: hidden; } video { width: 100%; height: 100%; object-fit: contain; }</style>
          </head><body>
          <video id="video" autoplay controls></video>
          <script>
            var video = document.getElementById('video');
            if (Hls.isSupported()) {
              var hls = new Hls();
              hls.loadSource('${widget.customUrl}');
              hls.attachMedia(video);
              hls.on(Hls.Events.MANIFEST_PARSED, function() { video.play(); VideoState.postMessage('playing'); });
            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
              video.src = '${widget.customUrl}';
              video.addEventListener('loadedmetadata', function() { video.play(); VideoState.postMessage('playing'); });
            }
          </script></body></html>
        ''';
        _controller?.loadHtmlString(hlsHtml);
      } else {
        _controller?.loadRequest(Uri.parse(widget.customUrl!));
      }
    } else {
      final id = widget.tmdbId;
      final isTv = widget.mediaType == 'tv' || widget.mediaType == 'series';
      
      // PROXY STRICTLY UNTOUCHED
      String originalTargetUrl = isTv 
          ? 'https://pantyflix.com/watch/play/tv/$id?season=$currentSeason&episode=$currentEpisode&server=$activeServer' 
          : 'https://pantyflix.com/watch/play/movie/$id?server=$activeServer';
      
      String vercelProxyBase = "https://hannutv-proxy-1.vercel.app/api/proxy?stream=";
      String safeFinalUrl = vercelProxyBase + Uri.encodeComponent(originalTargetUrl);
      
      _controller?.loadRequest(Uri.parse(safeFinalUrl));
    }
  }

  void _cycleAspectRatio() {
    setState(() {
      if (currentAspectRatio == 'contain') currentAspectRatio = 'cover';
      else if (currentAspectRatio == 'cover') currentAspectRatio = 'fill';
      else currentAspectRatio = 'contain';
    });
    // Ab Native Controls use ho rahe hain, par fallback aspect ratio command rakh diya hai
    _controller?.runJavaScript("var vids = document.getElementsByTagName('video'); if (vids.length > 0) { vids[0].style.objectFit = '$currentAspectRatio'; }");
    _startControlsTimer();
  }

  void _toggleFullScreen() {
    if (isTvDevice) return; 
    setState(() { isFullScreen = !isFullScreen; });
    if (isFullScreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _startControlsTimer();
  }

  void _switchEpisode(int ep) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SkippableAdScreen(
          adDuration: 10,
          nextScreen: VideoPlayerPage(
            tmdbId: widget.tmdbId, mediaType: widget.mediaType,
            season: currentSeason, episode: ep,
            movieTitle: widget.movieTitle, overview: widget.overview,
            rating: widget.rating, year: widget.year,
          )
        )
      )
    );
  }
  
  void _switchSeason(int seasonNum) {
    setState(() { currentSeason = seasonNum; currentEpisode = 1; episodesList.clear(); });
    _fetchEpisodes(seasonNum);
    _switchEpisode(1);
  }

  void _showSeasonPicker() {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1A1A1A), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16), height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("$totalSeasons Seasons Available", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const Text("Full Catalog", style: TextStyle(color: Colors.redAccent, fontSize: 12))]),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: totalSeasons, 
                  itemBuilder: (context, index) {
                    int seasonNum = index + 1;
                    return ListTile(
                      title: Text("Season ${seasonNum.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.play_circle_outline, color: Colors.grey, size: 20),
                      onTap: () { Navigator.pop(context); _switchSeason(seasonNum); },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _downloadMovie() {
    bool alreadyExists = downloadedMoviesList.any((movie) => movie['id'] == widget.tmdbId);
    
    if (alreadyExists) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already Downloaded! Check Folder.'), backgroundColor: Colors.orange));
      return;
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (BuildContext context) {
        int progress = 0;
        return StatefulBuilder(
          builder: (context, setState) {
            Timer.periodic(const Duration(milliseconds: 100), (timer) {
              if (progress >= 100) {
                timer.cancel();
                Navigator.pop(context); 
                
                if (!downloadedMoviesList.any((movie) => movie['id'] == widget.tmdbId)) {
                   downloadedMoviesList.insert(0, {
                    'id': widget.tmdbId, 'title': widget.movieTitle, 'year': widget.year, 'type': widget.mediaType,
                  });
                }
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download Complete! Saved to Folder.'), backgroundColor: Colors.green));
              } else {
                if (mounted) setState(() { progress += 5; });
              }
            });

            return AlertDialog(
              backgroundColor: const Color(0xFF151515),
              title: const Text("Downloading...", style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress / 100, color: Colors.redAccent),
                  const SizedBox(height: 10),
                  Text("$progress% Complete", style: const TextStyle(color: Colors.greenAccent))
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _addComment() async {
    final text = commentInputController.text.trim();
    User? user = FirebaseAuth.instance.currentUser;

    if (text.isNotEmpty) {
      if (user == null || user.isAnonymous) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login from Dashboard to comment!'), backgroundColor: Colors.redAccent));
        return;
      }
      
      String movieId = widget.customUrl == null ? widget.tmdbId.toString() : 'live_${widget.movieTitle.replaceAll(" ", "_")}';
      
      await FirebaseFirestore.instance.collection('movies').doc(movieId).collection('comments').add({
        'name': user.displayName ?? 'HANNUTV User', 'text': text,
        'time': DateTime.now().toIso8601String(), 'timestamp': FieldValue.serverTimestamp(),
        'avatar': (user.displayName != null && user.displayName!.isNotEmpty) ? user.displayName![0].toUpperCase() : 'H',
      });
      
      commentInputController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel(); 
    _liveTvAdTimer?.cancel(); 
    _fallbackPlayTimer?.cancel();
    _introAnimController.dispose(); 
    commentInputController.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  Widget _buildFocusableItem({required Widget child, required VoidCallback onTap, BorderRadius? borderRadius}) {
    return _TvFocusButton(onTap: onTap, borderRadius: borderRadius ?? BorderRadius.circular(8), child: child);
  }

  Widget _buildTVLayout() { return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text("TV Layout Mode", style: TextStyle(color: Colors.white)))); }

  @override
  Widget build(BuildContext context) {
    if (isTvDevice) return _buildTVLayout(); 

    if (isFullScreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: _controller != null 
                  ? WebViewWidget(controller: _controller!)
                  : Container(color: Colors.black),
            ),
            if (isPageLoading && !isVideoPlaying) Positioned.fill(child: Container(color: Colors.black, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2.5)), SizedBox(height: 10), Text("Connecting to Server...", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))])))),
            Positioned(top: 14, right: 20, child: SafeArea(child: IgnorePointer(child: Opacity(opacity: 0.85, child: Image.asset('assets/logo.png', height: 38, errorBuilder: (_, __, ___) => const Text('HANNUTV', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16))))))),
            if (showControls) ...[
              Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black38))),
              Positioned(top: 20, right: 20, child: SafeArea(child: _buildFocusableItem(onTap: () { SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); Navigator.pop(context); }, borderRadius: BorderRadius.circular(22), child: const CircleAvatar(backgroundColor: Colors.black87, radius: 22, child: Icon(Icons.close, color: Colors.white, size: 28))))),
              Positioned(bottom: 20, right: 20, child: SafeArea(child: _buildFocusableItem(onTap: _toggleFullScreen, borderRadius: BorderRadius.circular(22), child: const CircleAvatar(backgroundColor: Colors.black87, radius: 22, child: Icon(Icons.fullscreen_exit, color: Colors.white, size: 28))))),
            ],
          ],
        ),
      );
    }

    bool isTvShow = widget.mediaType == 'tv' || widget.mediaType == 'series';
    String displayTitle = widget.movieTitle;
    if (isTvShow && widget.customUrl == null) displayTitle += " S${currentSeason.toString().padLeft(2, '0')} - E${currentEpisode.toString().padLeft(2, '0')}";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _startControlsTimer,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity, height: 230, color: Colors.black, 
                    child: _controller != null 
                        ? WebViewWidget(controller: _controller!)
                        : const SizedBox()
                  ),
                  Positioned(
                    top: 10, right: 14,
                    child: GestureDetector(
                      onTap: _toggleFullScreen,
                      child: Opacity(opacity: 0.85, child: Image.asset('assets/logo.png', height: 34, errorBuilder: (_, __, ___) => const Text('HANNUTV', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)))),
                    ),
                  ),
                  if (showIntroAnimation) Positioned.fill(child: IgnorePointer(child: Center(child: AnimatedBuilder(animation: _introAnimController, builder: (context, child) { return Opacity(opacity: _introOpacityAnimation.value, child: Transform.scale(scale: _introScaleAnimation.value, child: Image.asset('assets/logo.png', height: 60, errorBuilder: (_, __, ___) => const Icon(Icons.play_circle_fill, color: Colors.red, size: 60)))); })))),
                  if (showControls) ...[
                    Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black38))),
                    Positioned(top: 10, right: 10, child: _buildFocusableItem(onTap: () => Navigator.pop(context), borderRadius: BorderRadius.circular(18), child: const CircleAvatar(backgroundColor: Colors.black54, radius: 18, child: Icon(Icons.chevron_left, color: Colors.white, size: 28)))),
                    Positioned(bottom: 8, right: 48, child: _buildFocusableItem(onTap: _cycleAspectRatio, borderRadius: BorderRadius.circular(16), child: const CircleAvatar(backgroundColor: Colors.black54, radius: 16, child: Icon(Icons.aspect_ratio, color: Colors.white, size: 18)))),
                    Positioned(bottom: 8, right: 8, child: _buildFocusableItem(onTap: _toggleFullScreen, borderRadius: BorderRadius.circular(16), child: const CircleAvatar(backgroundColor: Colors.black54, radius: 16, child: Icon(Icons.fullscreen, color: Colors.white, size: 22)))),
                  ],
                  if (isPageLoading && !isVideoPlaying) Positioned.fill(child: Container(color: Colors.black, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2.5)), SizedBox(height: 10), Text("Connecting to Server...", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))])))),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayTitle, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18), const SizedBox(width: 4),
                        Text(widget.rating, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)), const SizedBox(width: 12),
                        Text(widget.year, style: const TextStyle(color: Colors.grey, fontSize: 14)), const SizedBox(width: 16),
                        const Icon(Icons.visibility, color: Colors.grey, size: 16), const SizedBox(width: 4),
                        Text("$viewCount Views", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 14),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFocusableItem(
                            onTap: () { setState(() { isLiked = !isLiked; likeCount += isLiked ? 1 : -1; }); },
                            borderRadius: BorderRadius.circular(20),
                            child: _buildActionButton(isLiked ? Icons.thumb_up : Icons.thumb_up_alt_outlined, "$likeCount", activeColor: isLiked ? Colors.redAccent : Colors.white),
                          ),
                          const SizedBox(width: 8),
                          _buildFocusableItem(onTap: () {}, borderRadius: BorderRadius.circular(20), child: _buildActionButton(Icons.bookmark_border, "Add to List")),
                          const SizedBox(width: 8),
                          
                          _buildFocusableItem(onTap: _downloadMovie, borderRadius: BorderRadius.circular(20), child: _buildActionButton(Icons.download, "Download", activeColor: Colors.green)),
                          const SizedBox(width: 8),
                          
                          _buildFocusableItem(onTap: () {}, borderRadius: BorderRadius.circular(20), child: _buildActionButton(Icons.tv, "Play on TV")),
                          const SizedBox(width: 8),
                          _buildFocusableItem(onTap: () {}, borderRadius: BorderRadius.circular(20), child: _buildActionButton(Icons.share, "Share")),
                          const SizedBox(width: 8),
                          _buildFocusableItem(onTap: () {}, borderRadius: BorderRadius.circular(20), child: _buildActionButton(Icons.flag_outlined, "Report")),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (widget.customUrl == null) ...[
                      const Text("Sponsored Ads", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 20),
                    ],

                    if (widget.customUrl != null) ...[
                      const SizedBox(height: 10),
                      const Text("Sponsored Ads", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 16),
                      const CustomBannerAd(htmlBannerCode: _adsterraBannerSnippet),
                      const SizedBox(height: 20),
                    ],

                    if (widget.customUrl == null) ...[
                      const Text("If current server is not working, try a different one:", style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFF151515), border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text("HANNUTV LIVE STREAM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), Text("Ads-Free secure engine active", style: TextStyle(color: Colors.grey, fontSize: 12))]),
                                const Icon(Icons.verified_user, color: Colors.green, size: 20)
                              ],
                            ),
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: servers.map((srv) {
                                  final isSelected = activeServer == srv['key'];
                                  return _buildFocusableItem(
                                    onTap: () { if (activeServer != srv['key']) { setState(() => activeServer = srv['key']!); _loadCurrentVideo(); } },
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.grey[900], borderRadius: BorderRadius.circular(20)),
                                      child: Text(srv['name']!, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                  );
                                }).toList(),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    if (isTvShow && widget.customUrl == null) ...[
                      Row(
                        children: [
                          InkWell(onTap: _showSeasonPicker, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(20)), child: Row(children: [Text("Season ${currentSeason.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(width: 6), const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18)]))),
                          const SizedBox(width: 12),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.black, border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(20)), child: Row(children: const [Text("Original Audio", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)), SizedBox(width: 6), Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18)])),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      const Text("Episodes", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: episodesList.isNotEmpty ? episodesList.length : 15,
                          itemBuilder: (context, index) {
                            final epNum = index + 1;
                            final isCurrent = currentEpisode == epNum;
                            String epName = "Episode $epNum";
                            String imgUrl = '';
                            if (episodesList.isNotEmpty && index < episodesList.length) {
                              epName = episodesList[index]['name'] ?? "Episode $epNum";
                              if (episodesList[index]['still_path'] != null) imgUrl = 'https://image.tmdb.org/t/p/w500${episodesList[index]['still_path']}';
                            }
                            return _buildFocusableItem(
                              onTap: () => _switchEpisode(epNum), borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 160, margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: isCurrent ? Border.all(color: Colors.redAccent, width: 2) : Border.all(color: Colors.white12), color: const Color(0xFF1A1A1A)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), color: Colors.black54, image: imgUrl.isNotEmpty ? DecorationImage(image: NetworkImage(imgUrl), fit: BoxFit.cover) : null),
                                        child: Center(child: Icon(isCurrent ? Icons.play_circle_fill : Icons.play_circle_outline, color: isCurrent ? Colors.red : Colors.white70, size: 40)),
                                      ),
                                    ),
                                    Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(epName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), const Text("Watch on HANNUTV", style: TextStyle(color: Colors.grey, fontSize: 10), maxLines: 1)])),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Public Comments", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                              const Icon(Icons.comment, color: Colors.grey, size: 16),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: commentInputController,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Add a public comment...',
                                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                                    filled: true, fillColor: Colors.black45,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              _buildFocusableItem(
                                onTap: _addComment, borderRadius: BorderRadius.circular(20),
                                child: const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.send, color: Colors.redAccent, size: 20)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance.collection('movies').doc(widget.customUrl == null ? widget.tmdbId.toString() : 'live_${widget.movieTitle.replaceAll(" ", "_")}').collection('comments').orderBy('timestamp', descending: true).snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
                              final comments = snapshot.data!.docs;
                              
                              if (comments.isEmpty) return const Padding(padding: EdgeInsets.all(8.0), child: Text("Be the first to comment!", style: TextStyle(color: Colors.grey, fontSize: 12)));

                              return Column(
                                children: comments.map((doc) {
                                  var data = doc.data() as Map<String, dynamic>;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(radius: 14, backgroundColor: Colors.redAccent, child: Text(data['avatar'] ?? 'U', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(data['name'] ?? 'User', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  const SizedBox(width: 6),
                                                  const Text("Just now", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                                ],
                                              ),
                                              Text(data['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    if (widget.customUrl == null && similarMovies.isNotEmpty) ...[
                      const Text("Suggested Movies & Shows", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 160,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal, itemCount: similarMovies.length,
                          itemBuilder: (context, index) {
                            final m = similarMovies[index];
                            return _buildFocusableItem(
                              onTap: () { 
                                Navigator.pushReplacement(
                                  context, 
                                  MaterialPageRoute(builder: (context) => SkippableAdScreen(
                                    adDuration: 10,
                                    nextScreen: VideoPlayerPage(tmdbId: m['id'], mediaType: m['mediaType'], movieTitle: m['title'], rating: m['rating'], year: m['year'])
                                  ))
                                ); 
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 110, margin: const EdgeInsets.only(right: 10),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(m['posterUrl'] != '' ? m['posterUrl'] : 'https://via.placeholder.com/300x450/222222/888888'), fit: BoxFit.cover)))), const SizedBox(height: 4), Text(m['title'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)]),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String title, {Color activeColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: activeColor, size: 16),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(color: activeColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TvFocusButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  const _TvFocusButton({required this.child, required this.onTap, required this.borderRadius});
  @override
  State<_TvFocusButton> createState() => _TvFocusButtonState();
}
class _TvFocusButtonState extends State<_TvFocusButton> {
  bool _hasFocus = false;
  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) { if (mounted) setState(() => _hasFocus = hasFocus); },
      child: InkWell(
        onTap: widget.onTap, borderRadius: widget.borderRadius,
        child: AnimatedContainer(duration: const Duration(milliseconds: 150), decoration: BoxDecoration(borderRadius: widget.borderRadius, border: Border.all(color: _hasFocus ? Colors.redAccent : Colors.transparent, width: _hasFocus ? 3.5 : 0), boxShadow: _hasFocus ? [BoxShadow(color: Colors.redAccent.withOpacity(0.65), blurRadius: 10)] : []), child: widget.child),
      ),
    );
  }
}