// podcast/ui/widgets/podcast_artwork_image.dart
//
// Podcast artwork widget. The music ArtImage always renders a SQUARE box with
// BoxFit.cover — correct for album art, wrong here: episode frames are 16:9,
// so covering a square box crops ~44% of the image, usually the guest's face
// and the episode title card.
//
// This widget instead:
//   • measures the image's real aspect ratio as it resolves, and lays out at
//     that ratio when asked (`natural`), or
//   • CONTAINS the art inside the given box, never cropping it, and fills the
//     leftover space with a blurred, dimmed copy of the same image, so mixed
//     ratios in one list read as deliberate rather than letterboxed.
//
// Music's ArtImage is untouched and still used everywhere in Music Mode.

import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../services/podcast_artwork.dart';

class PodcastArtworkImage extends StatefulWidget {
  final String url;

  /// Width the artwork is laid out at. Height comes from [ratio], from the
  /// image's own ratio (when [natural]), or from [height] when given.
  final double width;
  final double? height;

  /// Lay out at the image's TRUE aspect ratio once it resolves, instead of a
  /// fixed box. Used where the art is the subject (show header, player).
  final bool natural;

  /// Fixed ratio to use when not [natural]. Defaults to a guess from the URL.
  final double? ratio;

  final double radius;

  /// Paint the blurred backdrop behind contained art. Off for tiny thumbs,
  /// where the extra blur pass isn't worth it.
  final bool backdrop;

  /// Tried when [url] fails to load — typically the creator's avatar behind a
  /// show cover whose signed URL has expired. Empty for none.
  final String fallbackUrl;

  const PodcastArtworkImage({
    super.key,
    required this.url,
    required this.width,
    this.height,
    this.natural = false,
    this.ratio,
    this.radius = AppRadius.md,
    this.backdrop = true,
    this.fallbackUrl = '',
  });

  @override
  State<PodcastArtworkImage> createState() => _PodcastArtworkImageState();
}

class _PodcastArtworkImageState extends State<PodcastArtworkImage> {
  /// The image's measured ratio, once known. Null until it resolves.
  double? _measured;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// Index into [_candidates] currently being shown. Advances when a
  /// candidate fails, so a dead URL degrades to the next-best image instead
  /// of a blank tile.
  int _attempt = 0;

  /// Every URL worth trying, best first: the canonical URL, a low-res frame
  /// for videos with no HD frame, then the caller's fallback (avatar).
  List<String> get _candidates {
    final primary = PodcastArtwork.canonical(widget.url);
    return [
      if (primary.isNotEmpty) primary,
      if (PodcastArtwork.frameFallbackFor(primary) case final f?) f,
      if (widget.fallbackUrl.isNotEmpty) widget.fallbackUrl,
    ];
  }

  String get _current {
    final c = _candidates;
    return _attempt < c.length ? c[_attempt] : '';
  }

  /// Called from errorWidget (i.e. during build) — so the advance is
  /// scheduled, never done synchronously.
  void _advance(String failed) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _current != failed) return;
      setState(() {
        _attempt++;
        _measured = null;
      });
      if (widget.natural) _measure();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.natural) _measure();
  }

  @override
  void didUpdateWidget(covariant PodcastArtworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.fallbackUrl != widget.fallbackUrl) {
      _measured = null;
      _attempt = 0;
      if (widget.natural) _measure();
    }
  }

  /// Resolves the image just to learn its dimensions. Cheap: it hits the same
  /// cache the CachedNetworkImage below draws from, so the bytes are fetched
  /// once, not twice.
  void _measure() {
    final url = _current;
    if (url.isEmpty) return;
    _detach();
    final provider = CachedNetworkImageProvider(_sizedUrl,
        cacheKey: PodcastArtwork.cacheKey(_sizedUrl));
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (!mounted || h <= 0) return;
      final ratio = PodcastArtwork.clampRatio(w / h);
      if (_measured != ratio) setState(() => _measured = ratio);
    }, onError: (_, __) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  String get _sizedUrl {
    final target = widget.width >= 400
        ? PodcastArtwork.hero
        : (widget.width >= 130 ? PodcastArtwork.card : PodcastArtwork.listThumb);
    return PodcastArtwork.sized(_current, target);
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.natural
        ? (_measured ?? PodcastArtwork.presumedRatio(_current))
        : (widget.ratio ?? PodcastArtwork.presumedRatio(_current));

    final height = widget.height ?? (widget.width / ratio);
    final br = BorderRadius.circular(widget.radius);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeW = PodcastArtwork.decodeWidth(widget.width, dpr);

    Widget content;
    final src = _sizedUrl;
    // Keyed by the signature-free URL, so the bytes downloaded on one visit
    // are served on the next even though YouTube has re-signed the URL.
    final key = PodcastArtwork.cacheKey(src);
    if (src.isEmpty) {
      content = _placeholder();
    } else {
      final image = CachedNetworkImage(
        imageUrl: src,
        cacheKey: key,
        // CONTAIN, never cover: the whole frame stays visible. In natural mode
        // the box already matches the image, so contain is a no-op there and
        // simply guarantees nothing is ever cropped.
        fit: BoxFit.contain,
        width: widget.width,
        height: height,
        memCacheWidth: decodeW,
        placeholder: (_, __) => Container(color: AppColors.card),
        errorWidget: (_, __, ___) {
          _advance(_current);
          return _placeholder();
        },
      );

      content = (widget.backdrop && !widget.natural)
          ? Stack(
              fit: StackFit.expand,
              children: [
                // Blurred, dimmed fill so the contained art sits on something
                // of its own rather than a flat grey plate.
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: CachedNetworkImage(
                    imageUrl: src,
                    cacheKey: key,
                    fit: BoxFit.cover,
                    memCacheWidth: (decodeW / 3).round().clamp(32, 400),
                    placeholder: (_, __) => Container(color: AppColors.card),
                    errorWidget: (_, __, ___) =>
                        Container(color: AppColors.card),
                  ),
                ),
                Container(color: Colors.black.withOpacity(0.45)),
                Center(child: image),
              ],
            )
          : image;
    }

    return SizedBox(
      width: widget.width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          color: AppColors.card,
          boxShadow: const [
            BoxShadow(
                color: Color(0x1AFFFFFF), blurRadius: 16, spreadRadius: -8),
          ],
        ),
        child: ClipRRect(borderRadius: br, child: content),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.card,
        alignment: Alignment.center,
        child: Icon(Icons.podcasts_rounded,
            color: AppColors.textTertiary,
            size: (widget.width * 0.34).clamp(16.0, 64.0)),
      );
}
