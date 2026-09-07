import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/logic/ausstehende_meldungen.dart';

/// Die Meldungen an die Gegenseite, die noch nicht raus sind.
///
/// Der Anlass: die Ablaufmeldung einer einmaligen Nachricht ging bis zum
/// 07.09.2026 nur ueber einen Zeitgeber, der 0,5 bis 5 Sekunden wartete.
/// Wer in dieser Spanne die App wegwischte, den Akku verlor oder gerade
/// kein Netz hatte, hat die Meldung verloren — und beim Absender stand die
/// Nachricht fuer immer. Die Zusage der Funktion war damit nur auf einem
/// der beiden Geraete gehalten.
void main() {
  final jetzt = DateTime(2026, 9, 7, 12);

  group('merken', () {
    test('eine neue Meldung wird gemerkt', () {
      final liste = AusstehendeMeldungen();
      expect(liste.merken(chatId: 'c1', messageId: 'm1', jetzt: jetzt),
          isTrue);
      expect(liste.alle, hasLength(1));
      expect(liste.alle.single.chatId, 'c1');
      expect(liste.alle.single.messageId, 'm1');
      expect(liste.alle.single.art, 'burned');
      expect(liste.alle.single.seit, jetzt);
    });

    test('dieselbe Meldung wird nicht zweimal gemerkt', () {
      // Sonst ginge sie beim Nachholen zweimal raus.
      final liste = AusstehendeMeldungen();
      liste.merken(chatId: 'c1', messageId: 'm1', jetzt: jetzt);
      expect(
        liste.merken(
            chatId: 'c1',
            messageId: 'm1',
            jetzt: jetzt.add(const Duration(minutes: 1))),
        isFalse,
      );
      expect(liste.alle, hasLength(1));
      expect(liste.alle.single.seit, jetzt,
          reason: 'der erste Zeitpunkt bleibt');
    });

    test('mehr als die Obergrenze verdraengt die aelteste', () {
      // Eine Liste, die nie kuerzer wird, waere ein Leck. Wer so viele
      // Meldungen liegen hat, hat ein anderes Problem als die aelteste.
      final liste = AusstehendeMeldungen();
      for (var i = 0; i <= AusstehendeMeldungen.hoechstens; i++) {
        liste.merken(
            chatId: 'c1',
            messageId: 'm$i',
            jetzt: jetzt.add(Duration(seconds: i)));
      }
      expect(liste.alle, hasLength(AusstehendeMeldungen.hoechstens));
      expect(liste.alle.first.messageId, 'm1',
          reason: 'm0 war die aelteste und ist raus');
    });
  });

  group('erledigt', () {
    test('eine rausgegangene Meldung faellt aus der Liste', () {
      final liste = AusstehendeMeldungen();
      liste.merken(chatId: 'c1', messageId: 'm1', jetzt: jetzt);
      expect(liste.erledigt(chatId: 'c1', messageId: 'm1'), isTrue);
      expect(liste.alle, isEmpty);
    });

    test('eine unbekannte Meldung aendert nichts', () {
      final liste = AusstehendeMeldungen();
      liste.merken(chatId: 'c1', messageId: 'm1', jetzt: jetzt);
      expect(liste.erledigt(chatId: 'c1', messageId: 'm2'), isFalse);
      expect(liste.alle, hasLength(1));
    });
  });

  group('verwerfen', () {
    test('mit dem Chat gehen seine Meldungen', () {
      // Es gibt keine Sitzung mehr, gegen die sie signiert wuerden.
      final liste = AusstehendeMeldungen();
      liste.merken(chatId: 'c1', messageId: 'm1', jetzt: jetzt);
      liste.merken(chatId: 'c1', messageId: 'm2', jetzt: jetzt);
      liste.merken(chatId: 'c2', messageId: 'm3', jetzt: jetzt);
      expect(liste.fuerChatVerwerfen('c1'), 2);
      expect(liste.alle.map((m) => m.messageId), ['m3']);
    });

    test('was aelter ist, als die Gegenseite annehmen wuerde, faellt weg',
        () {
      // ControlMessagePolicy laesst `burned` dreissig Tage gelten. Eine
      // aeltere Meldung wuerde drueben verworfen; sie weiter zu schleppen
      // hiesse nur, bei jedem Start umsonst zu senden.
      final liste = AusstehendeMeldungen();
      liste.merken(
          chatId: 'c1',
          messageId: 'alt',
          jetzt: jetzt.subtract(const Duration(days: 31)));
      liste.merken(
          chatId: 'c1',
          messageId: 'frisch',
          jetzt: jetzt.subtract(const Duration(days: 29)));
      expect(liste.verfalleneVerwerfen(jetzt), 1);
      expect(liste.alle.map((m) => m.messageId), ['frisch']);
    });
  });

  group('Speichern und Laden', () {
    test('die Liste ueberlebt den Weg ueber die Platte', () {
      final liste = AusstehendeMeldungen();
      liste.merken(chatId: 'c1', messageId: 'm1', jetzt: jetzt);
      liste.merken(
          chatId: 'c2',
          messageId: 'm2',
          jetzt: jetzt.add(const Duration(seconds: 3)));

      final geladen = AusstehendeMeldungen.fromJson(liste.toJson());
      expect(geladen.alle, hasLength(2));
      expect(geladen.alle[0].chatId, 'c1');
      expect(geladen.alle[0].messageId, 'm1');
      expect(geladen.alle[0].art, 'burned');
      expect(geladen.alle[0].seit, jetzt);
      expect(geladen.alle[1].chatId, 'c2');
    });

    test('nichts auf der Platte heisst leere Liste', () {
      expect(AusstehendeMeldungen.fromJson(null).alle, isEmpty);
    });

    test('Unbrauchbares wird uebergangen, nicht geworfen', () {
      // Ein kaputter Eintrag darf nicht den Start der App kosten — und
      // nicht die brauchbaren Eintraege daneben.
      final geladen = AusstehendeMeldungen.fromJson([
        'unsinn',
        {'chatId': 'c1'},
        {
          'chatId': 'c1',
          'messageId': 'm1',
          'art': 'burned',
          'seit': jetzt.millisecondsSinceEpoch,
        },
        {'chatId': 7, 'messageId': 'm2', 'art': 'burned', 'seit': 1},
      ]);
      expect(geladen.alle.map((m) => m.messageId), ['m1']);
    });

    test('ein Eintrag ohne Zeitpunkt zaehlt als jetzt geschrieben', () {
      // Lieber einmal zu oft senden als einen Bestand still zu verlieren.
      final geladen = AusstehendeMeldungen.fromJson([
        {'chatId': 'c1', 'messageId': 'm1', 'art': 'burned'},
      ], jetzt: jetzt);
      expect(geladen.alle.single.seit, jetzt);
    });
  });
}
