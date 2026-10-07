import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // 🚀 BROWSER/PLAY STORE ME KHOLNE KE LIYE

class CustomBannerAd extends StatefulWidget {
  final String htmlBannerCode;

  const CustomBannerAd({Key? key, required this.htmlBannerCode}) : super(key: key);

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  late final WebViewController _controller;
  
  // 🔥 DEEP LOGIC: ANTI-ADBLOCK FLAG 🔥
  bool _isAdblockDetected = false;

  // 🛡️ AUTO-OPEN FIX: browser / Play Store sirf tab khulega jab user ne banner pe REAL tap kiya ho
  Offset? _tapDownPos;
  DateTime? _lastTapTime;
  bool get _userTappedRecently =>
      _lastTapTime != null &&
      DateTime.now().difference(_lastTapTime!) < const Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      // 🚀 TERA CLICK FILTER + MERA ADBLOCK FILTER 🚀
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();

            // 1. Initial banner load aur Adsterra ke scripts ko chalne do taaki ad dikhe
            if (url.startsWith('data:') || 
                url.startsWith('about:blank') || 
                url.contains('hannutv.blogspot.com') || 
                url.contains('highrevenueformat.com')) {
              return NavigationDecision.navigate;
            }

            // 2. 🔥 USER NE AD PE REAL TAP KIYA HAI TOH BROWSER ME KHOLO (pehle jaisa) 🔥
            if (_userTappedRecently) {
              _launchExternalBrowser(request.url);
              // Banner ke chhote se dabbe me website mat khulne do!
              return NavigationDecision.prevent;
            }

            // 3. 🛡️ BINA TAP KE AUTO REDIRECT: browser / Play Store KABHI nahi khulega
            //    - ad ke andar (iframe) ka load ad ke andar hi chalne do taaki ad screen pe dikhe
            //    - poore banner ko apne aap kahin le jaane wala redirect rok do
            return request.isMainFrame ? NavigationDecision.prevent : NavigationDecision.navigate;
          },
          // 🚀 WORLD CLASS ANTI-ADBLOCK SENSOR FOR BANNER 🚀
          onWebResourceError: (WebResourceError error) {
            final desc = error.description.toLowerCase();
            if (desc.contains('err_name_not_resolved') || 
                desc.contains('err_blocked_by_client') || 
                desc.contains('err_connection_refused')) {
              if (mounted) {
                setState(() {
                  // _isAdblockDetected = true; // disabled: Private DNS ab mandatory hai
                });
              }
            }
          },
        ),
      )
      ..loadHtmlString('''
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
              body { margin: 0; padding: 0; display: flex; justify-content: center; align-items: center; background: transparent; overflow: hidden; }
            </style>
          </head>
          <body>
            ${widget.htmlBannerCode}
            <script>
              // 🔥 DEEP HACK: Adsterra click karne par naya tab (window.open) kholta hai jo WebView me block ho jata hai. 
              // Is code se wo naya tab pakda jayega aur NavigationDelegate me bhej diya jayega!
              window.open = function(url, windowName, windowFeatures) {
                window.location.href = url;
                return null;
              };
            </script>
          </body>
        </html>
      ''', baseUrl: 'https://hannutv.blogspot.com');
  }

  // 🚀 CHROME YA PLAY STORE ME KHOLNE KA FUNCTION 🚀
  Future<void> _launchExternalBrowser(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Could not launch banner link");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60, 
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black, 
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _isAdblockDetected 
            // 🔥 AGAR PVT DNS HAI TOH BANNER ME WARNING AAYEGI 🔥
            ? Container(
                color: Colors.grey[900],
                child: const Center(
                  child: Text(
                    "Please off pvtdns / adguard", 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)
                  )
                ),
              )
            // NORMAL BANNER LOAD (Agar sab theek hai)
            : Listener(
                // real tap pakadne ke liye (WebView ke upar, touch ko disturb nahi karta)
                onPointerDown: (e) => _tapDownPos = e.position,
                onPointerUp: (e) {
                  final down = _tapDownPos;
                  if (down != null && (e.position - down).distance < 30) {
                    _lastTapTime = DateTime.now();
                  }
                },
                child: WebViewWidget(controller: _controller),
              ),
      ),
    );
  }
}