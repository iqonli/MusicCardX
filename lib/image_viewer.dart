import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class CardImageViewer extends StatelessWidget {
  final ui.Image image;
  const CardImageViewer({super.key, required this.image});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(title: Text('${image.width}×${image.height}')),
    // PhotoView's filterQuality switches its image-layout scaling path, which
    // does not apply to custom children. Bicubic is set on RawImage instead.
    body: PhotoView.customChild(
      childSize: Size(image.width.toDouble(), image.height.toDouble()),
      backgroundDecoration: const BoxDecoration(color: Colors.white),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * 8,
      child: RawImage(image: image, filterQuality: FilterQuality.high),
    ),
  );
}
