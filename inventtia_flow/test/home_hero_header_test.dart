import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/widgets/home_hero_header.dart';

void main() {
  testWidgets('el buscador se pinta delante del índigo y se puede tocar', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    final fieldKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 390,
                child: ColoredBox(
                  color: const Color(0xFFF3F5F9),
                  child: HomeHeroHeader(
                    topBar: const SizedBox(
                      height: 100,
                      child: ColoredBox(color: Color(0xFF3E4E80)),
                    ),
                    searchCard: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      child: Container(
                        height: 100,
                        color: Colors.white,
                        alignment: Alignment.topCenter,
                        child: TextField(
                          key: fieldKey,
                          decoration: const InputDecoration(
                            hintText: 'Buscar servicio o local',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    int colorAt(int x, int y) => pixels!.getUint32((y * 390 + x) * 4);

    // The gradient continues behind the card's first 26 px, not over it.
    expect(colorAt(4, 110), 0x3E4E80FF);
    expect(colorAt(20, 110), 0xFFFFFFFF);
    expect(colorAt(4, 145), 0xF3F5F9FF);

    final fieldTop = tester.getTopLeft(find.byKey(fieldKey));
    // A tap on the overlapping top edge must reach the field, not the header.
    await tester.tapAt(fieldTop + const Offset(30, 10));
    await tester.pump();
    await tester.enterText(find.byKey(fieldKey), 'Uñas');
    expect(find.text('Uñas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
