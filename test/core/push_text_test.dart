import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Was auf dem Sperrbildschirm stehen darf — und was nie.
///
/// Daniels Regel vom 07.09.2026: „bei push benachrichtigen sollte nur stehen
/// du hast eine neue nachricht erhalten, aber nicht von wem und nicht was."
///
/// Der Text steht nicht in Dart, sondern in der Cloud Function
/// (`firebase/functions/index.js`) — er wird auf dem Server gesetzt, nicht auf
/// dem Geraet. Genau deshalb steht die Regel hier: er laesst sich sonst
/// aendern, ohne dass ein einziger Test rot wird, und niemand faellt es auf,
/// bis es auf einem Sperrbildschirm steht.
///
/// Warum das ueberhaupt eine Regel braucht und keine Empfehlung ist: der
/// FCM-Payload laeuft durch Google und wird dort protokolliert. Ein Absender
/// im Text verraet, **wer mit wem** spricht — das Metadatum, das diese App
/// nicht hergibt, auch wenn der Inhalt verschluesselt bleibt.
void main() {
  final quelle = File('firebase/functions/index.js');

  /// Der Block, aus dem die Benachrichtigung gebaut wird.
  String coverBlock(String js) {
    final start = js.indexOf('const COVER_NOTIFICATION');
    expect(start, isNot(-1),
        reason: 'COVER_NOTIFICATION ist die einzige Quelle des Textes');
    final ende = js.indexOf('};', start);
    return js.substring(start, ende + 2);
  }

  test('die Datei mit dem Text ist da, wo dieser Test sie sucht', () {
    // Ein umbenannter Pfad darf nicht dazu fuehren, dass die Regel still
    // aufhoert zu gelten.
    expect(quelle.existsSync(), isTrue,
        reason: 'firebase/functions/index.js traegt den Text der '
            'Benachrichtigung; wandert er, wandert dieser Test mit');
  });

  test('der Text lautet genau „Du hast eine neue Nachricht erhalten"', () {
    final block = coverBlock(quelle.readAsStringSync());
    expect(block, contains('body: "Du hast eine neue Nachricht erhalten"'));
  });

  test('kein Titel — iOS zeigt den App-Namen ohnehin darueber', () {
    final block = coverBlock(quelle.readAsStringSync());
    expect(block, isNot(contains('title')),
        reason: 'eine zweite Zeile waere nur weitere Flaeche, auf der etwas '
            'stehen koennte');
  });

  test('die Benachrichtigung traegt nur den Text und sonst nichts', () {
    // Kein `imageUrl`, kein `subtitle`, kein Feld, in dem sich ein Name oder
    // ein Stueck Inhalt einnisten koennte.
    final block = coverBlock(quelle.readAsStringSync());
    final felder = RegExp(r'^\s*(\w+)\s*:', multiLine: true)
        .allMatches(block)
        .map((m) => m.group(1))
        .toList();
    expect(felder, ['body'],
        reason: 'genau ein Feld. Jedes weitere waere ein Ort, an dem etwas '
            'ueber die Nachricht auf den Sperrbildschirm gelangt');
  });

  test('kein Absender und kein Inhalt reisen mit dem Push', () {
    final js = quelle.readAsStringSync();
    // Der Datenteil des Push. Er geht denselben Weg durch Google wie der Text.
    final start = js.indexOf('notification: COVER_NOTIFICATION');
    expect(start, isNot(-1));
    final sendeBlock = js.substring(start, js.indexOf('apns:', start));

    for (final verboten in ['sid', 'senderId', 'mid', 'messageId', 'p', 'body']) {
      expect(
        RegExp(r'\b' + verboten + r'\s*:').hasMatch(sendeBlock),
        isFalse,
        reason: '`$verboten` gehoert nicht in den Push — FCM-Payloads werden '
            'bei Google protokolliert',
      );
    }
  });

  test('der Absender wird auch nirgends sonst in den Push gereicht', () {
    // Die Warnung steht als Kommentar im Code. Sie ersetzt keinen Test, aber
    // ihr Fehlen ist ein Zeichen dafuer, dass jemand den Block umgebaut hat.
    final js = quelle.readAsStringSync();
    expect(js, contains('Do NOT include senderId'));
  });
}
