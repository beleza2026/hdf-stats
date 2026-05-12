import 'package:flutter/material.dart';

/// Tamaño en píxeles para [Image.network] / [ResizeImage]: misma apariencia en pantalla,
/// pero se decodifica a resolución cercana a la física (menos RAM y trabajo en listas largas).
int imageDecodeCachePx(double logicalExtent, double devicePixelRatio) {
  final v = (logicalExtent * devicePixelRatio).round();
  if (v < 1) return 1;
  if (v > 2048) return 2048;
  return v;
}

/// [ImageProvider] para avatares/redondos: evita decodificar fotos HD enteras en memoria.
ImageProvider<Object> resizedNetworkImageProvider(
  String url,
  double logicalSide,
  double devicePixelRatio,
) {
  final d = imageDecodeCachePx(logicalSide, devicePixelRatio);
  return ResizeImage(
    NetworkImage(url),
    width: d,
    height: d,
    allowUpscaling: false,
  );
}

/// [Image.network] con `cacheWidth` / `cacheHeight` según DPR (ideal para escudos en listas).
class DecodedNetworkImage extends StatelessWidget {
  const DecodedNetworkImage(
    this.url, {
    super.key,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
  });

  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      cacheWidth: imageDecodeCachePx(width, dpr),
      cacheHeight: imageDecodeCachePx(height, dpr),
      errorBuilder: errorBuilder,
    );
  }
}

/// Banda horizontal ancho pantalla, altura fija (estadios / headers).
class DecodedBannerNetworkImage extends StatelessWidget {
  const DecodedBannerNetworkImage(
    this.url, {
    super.key,
    required this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  final String url;
  final double height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = MediaQuery.sizeOf(context).width;
    return Image.network(
      url,
      width: double.infinity,
      height: height,
      fit: fit,
      cacheWidth: imageDecodeCachePx(w, dpr),
      cacheHeight: imageDecodeCachePx(height, dpr),
      errorBuilder: errorBuilder,
    );
  }
}
