import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/tema.dart';

/// Hoja de estilo del markdown que devuelven las IA (asistente CU18 y Reporte con IA CU15):
/// misma paleta que el resto de la app, con titulos, tablas, citas y bloques de codigo.
MarkdownStyleSheet hojaEstiloMarkdown(BuildContext context) {
  const base = TextStyle(color: Paleta.ink, fontSize: 14.5, height: 1.4);
  final borde = BorderSide(color: Paleta.paperLinea);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: base,
    strong: base.copyWith(fontWeight: FontWeight.w700),
    em: base.copyWith(fontStyle: FontStyle.italic),
    listBullet: base,
    h1: base.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
    h2: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
    h3: base.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
    code: fuenteMono(fontSize: 12.5, color: Paleta.ink),
    codeblockDecoration: BoxDecoration(
      color: Paleta.paperLinea,
      borderRadius: BorderRadius.circular(6),
    ),
    blockquote: base.copyWith(color: Paleta.inkSuave),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: Paleta.rojo, width: 3)),
    ),
    tableHead: base.copyWith(fontWeight: FontWeight.w700),
    tableBody: base.copyWith(fontSize: 13),
    tableBorder: TableBorder.all(color: Paleta.paperLinea),
    tableHeadAlign: TextAlign.left,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    horizontalRuleDecoration: BoxDecoration(border: Border(top: borde)),
  );
}
