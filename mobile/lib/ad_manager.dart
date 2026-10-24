import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdManager with WidgetsBindingObserver {
  AdManager._();
  static final AdManager instance = AdManager._();

  // Build with --dart-define=TEST_ADS=true to use Google test ad IDs.
  static const bool _test = bool.fromEnvironment('TEST_ADS');

  static const String _bannerId = _test
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-4455023088168031/9834642813';
  static const String _appOpenId = _test
      ? 'ca-app-pub-3940256099942544/9257395921'
      : 'ca-app-pub-4455023088168031/1868347878';
  static const String _interstitialId = _test
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-4455023088168031/1537350393';

  static const Duration _retryDelay = Duration(seconds: 30);
  static const Duration _interstitialEvery = Duration(minutes: 2);
  static const Duration _gap = Duration(seconds: 20);

  BannerAd? _banner;
  final ValueNotifier<int> _bannerVersion = ValueNotifier<int>(0);
  AppOpenAd? _appOpen;
  InterstitialAd? _interstitial;
  Timer? _timer;

  bool _started = false;
  bool _showing = false;
  bool _resumed = true;
  bool _firstOpenPending = true;
  bool _skipNextResume = false;
  DateTime _lastFullScreen = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> initialize() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await MobileAds.instance.initialize();
    _loadBanner();
    _loadAppOpen();
    _loadInterstitial();
    _timer = Timer.periodic(_interstitialEvery, (_) => _showInterstitial());
  }

  /// Call right before opening the gallery so returning from it
  /// does not trigger an App Open ad.
  void skipNextAppOpen() => _skipNextResume = true;

  bool get _canShow =>
      _started &&
      !_showing &&
      _resumed &&
      DateTime.now().difference(_lastFullScreen) > _gap;

  void _loadBanner() {
    _banner?.dispose();
    _banner = BannerAd(
      adUnitId: _bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _bannerVersion.value++,
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _banner = null;
          _bannerVersion.value++;
          Future.delayed(_retryDelay, () {
            if (_started) _loadBanner();
          });
        },
      ),
    )..load();
  }

  void _loadAppOpen() {
    AppOpenAd.load(
      adUnitId: _appOpenId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpen = ad;
          if (_firstOpenPending) {
            _firstOpenPending = false;
            _showAppOpen();
          }
        },
        onAdFailedToLoad: (_) {
          Future.delayed(_retryDelay, () {
            if (_started) _loadAppOpen();
          });
        },
      ),
    );
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) {
          Future.delayed(_retryDelay, () {
            if (_started) _loadInterstitial();
          });
        },
      ),
    );
  }

  void _showAppOpen() {
    final ad = _appOpen;
    if (ad == null || !_canShow) return;
    _appOpen = null;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
        _lastFullScreen = DateTime.now();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _showing = false;
        _loadAppOpen();
      },
    );
    ad.show();
  }

  void _showInterstitial() {
    final ad = _interstitial;
    if (ad == null || !_canShow) return;
    _interstitial = null;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
        _lastFullScreen = DateTime.now();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _showing = false;
        _loadInterstitial();
      },
    );
    ad.show();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumed = true;
      if (_skipNextResume) {
        _skipNextResume = false;
        return;
      }
      _showAppOpen();
    } else {
      _resumed = false;
    }
  }

  Widget bannerSlot() {
    return ValueListenableBuilder<int>(
      valueListenable: _bannerVersion,
      builder: (context, version, child) {
        final banner = _banner;
        return SizedBox(
          width: double.infinity,
          height: banner == null ? 0 : banner.size.height.toDouble(),
          child: banner == null
              ? const SizedBox.shrink()
              : Center(child: AdWidget(ad: banner)),
        );
      },
    );
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _banner?.dispose();
    _appOpen?.dispose();
    _interstitial?.dispose();
  }
}
