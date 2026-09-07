import 'package:flutter_test/flutter_test.dart';
import 'package:kryptaapp/features/messenger/data/models/message_model.dart';
import 'package:kryptaapp/features/messenger/logic/self_destruct_policy.dart';

/// Die Loeschregel eines Chats — sie gehoert **beiden** Seiten.
///
/// Bis zum 04.09.2026 war sie Hausordnung: jede Seite stellte fuer sich ein,
/// wie lange ihre eigenen Nachrichten liegen. Daniels Ansage kehrt das um.
/// Stellt einer auf fuenf Minuten, gilt das im ganzen Chat, auch drueben.
///
/// Damit beide dasselbe sehen, muss die Aenderung reisen — und beim
/// Aufeinandertreffen zweier Aenderungen muessen **beide Geraete dieselbe**
/// gewinnen lassen. Die Wanduhr taugt dafuer nicht: geht eine der beiden
/// nach, verlaeren sie sich dauerhaft. Massgeblich ist deshalb ein Zaehler,
/// der bei jeder Aenderung steigt, und bei Gleichstand die groessere Kennung.
///
/// Neu dazu kommt **Direkt nach dem Lesen**: keine Uhr, sondern der Moment,
/// in dem der Empfaenger den Chat verlaesst.
void main() {
  group('Die Regel reist in der Art mit', () {
    test('eine Frist', () {
      expect(
        SelfDestructPolicy.artFuerRegel(
            frist: const Duration(minutes: 5), version: 3),
        'sdChanged:300000:3',
      );
    });

    test('ausgeschaltet', () {
      expect(SelfDestructPolicy.artFuerRegel(version: 1), 'sdChanged:off:1');
    });

    test('direkt nach dem Lesen', () {
      expect(SelfDestructPolicy.artFuerRegel(nachLesen: true, version: 7),
          'sdChanged:read:7');
    });

    test('und wird wieder herausgelesen', () {
      final regel = SelfDestructPolicy.regelAusArt('sdChanged:300000:3');
      expect(regel?.frist, const Duration(minutes: 5));
      expect(regel?.nachLesen, isFalse);
      expect(regel?.version, 3);

      final aus = SelfDestructPolicy.regelAusArt('sdChanged:off:1');
      expect(aus?.frist, isNull);
      expect(aus?.nachLesen, isFalse);

      final lesen = SelfDestructPolicy.regelAusArt('sdChanged:read:7');
      expect(lesen?.nachLesen, isTrue);
      expect(lesen?.frist, isNull);
    });

    test('eine Meldung ohne Zaehler ist Bestand und zaehlt als null', () {
      // Build 100 schickt noch die alte Form. Sie darf nicht verloren gehen,
      // aber jede spaetere Aenderung soll sie ueberstimmen.
      final alt = SelfDestructPolicy.regelAusArt('sdChanged:300000');
      expect(alt?.frist, const Duration(minutes: 5));
      expect(alt?.version, 0);
      expect(SelfDestructPolicy.regelAusArt('sdChanged:off')?.frist, isNull);
    });

    test('eine fremde Art ist keine Regelaenderung', () {
      expect(SelfDestructPolicy.regelAusArt('screenshot'), isNull);
      expect(SelfDestructPolicy.istChatFristAenderung('screenshot'), isFalse);
      expect(SelfDestructPolicy.istChatFristAenderung('sdChanged:read:2'),
          isTrue);
    });

    test('Unsinn gilt als ausgeschaltet, nicht als erfundene Frist', () {
      // Fail-closed in die harmlose Richtung: lieber keine Frist als eine
      // ausgedachte, die den halben Verlauf raeumt.
      expect(SelfDestructPolicy.regelAusArt('sdChanged:abc:2')?.frist, isNull);
      expect(SelfDestructPolicy.regelAusArt('sdChanged:-5')?.frist, isNull);
    });

    test('eine unverschaemt kurze fremde Frist wird angehoben', () {
      expect(SelfDestructPolicy.regelAusArt('sdChanged:1:4')?.frist,
          SelfDestructPolicy.mindestFrist);
    });
  });

  group('Wenn zwei Aenderungen aufeinandertreffen', () {
    test('die spaetere gewinnt', () {
      expect(
        SelfDestructPolicy.fremdeRegelUebernehmen(
            meineVersion: 2, fremdeVersion: 3, meineId: 'a', fremdeId: 'b'),
        isTrue,
      );
    });

    test('eine aeltere Meldung aendert nichts mehr', () {
      expect(
        SelfDestructPolicy.fremdeRegelUebernehmen(
            meineVersion: 3, fremdeVersion: 2, meineId: 'a', fremdeId: 'b'),
        isFalse,
      );
    });

    test('bei Gleichstand entscheidet die groessere Kennung — auf beiden '
        'Geraeten gleich', () {
      // Der eigentliche Punkt: die Regel muss auf beiden Seiten dasselbe
      // Ergebnis liefern, sonst stehen sie dauerhaft verschieden.
      expect(
        SelfDestructPolicy.fremdeRegelUebernehmen(
            meineVersion: 4, fremdeVersion: 4, meineId: 'anna', fremdeId: 'ben'),
        isTrue,
        reason: 'bei mir gewinnt die fremde, weil ben > anna',
      );
      expect(
        SelfDestructPolicy.fremdeRegelUebernehmen(
            meineVersion: 4, fremdeVersion: 4, meineId: 'ben', fremdeId: 'anna'),
        isFalse,
        reason: 'drueben verliert dieselbe Meldung — beide landen bei ben',
      );
    });
  });

  group('Direkt nach dem Lesen', () {
    Message nachricht({
      DateTime? gelesenAm,
      String von = 'marco',
      SystemEventKind? hinweis,
      bool einmalig = false,
    }) =>
        Message(
          id: 'm1',
          chatId: 'c1',
          senderId: von,
          recipientId: von == 'ich' ? 'marco' : 'ich',
          encryptedContent: 'x',
          timestamp: DateTime(2026, 9, 4, 12),
          deliveredAt: DateTime(2026, 9, 4, 12),
          readAt: gelesenAm,
          systemEvent: hinweis,
          einmalig: einmalig,
        );

    final gelesen = DateTime(2026, 9, 4, 12, 5);

    test('eine gelesene Nachricht ist faellig, sobald der Chat verlassen wird',
        () {
      expect(
        SelfDestructPolicy.nachLesenFaellig(nachricht(gelesenAm: gelesen),
            regelNachLesen: true),
        isTrue,
      );
    });

    test('eine ungelesene bleibt', () {
      expect(
        SelfDestructPolicy.nachLesenFaellig(nachricht(),
            regelNachLesen: true),
        isFalse,
      );
    });

    test('ohne diese Regel wird nichts verbrannt', () {
      expect(
        SelfDestructPolicy.nachLesenFaellig(nachricht(gelesenAm: gelesen),
            regelNachLesen: false),
        isFalse,
      );
    });

    test('ein Hinweis im Verlauf bleibt stehen', () {
      // Ein Hinweis, der ausgerechnet dann verschwindet, wenn man ihn
      // braucht, waere sinnlos — dieselbe Regel wie bei der Frist.
      expect(
        SelfDestructPolicy.nachLesenFaellig(
            nachricht(gelesenAm: gelesen, hinweis: SystemEventKind.screenshot),
            regelNachLesen: true),
        isFalse,
      );
    });

    test('eine einmalige Nachricht geht mit dem Oeffnen, nicht mit dem Verlassen',
        () {
      // Ihr `readAt` steht schon bei der Zustellung, wenn der Chat gerade
      // offen ist — gelesen ist damit die Blase, nicht der Inhalt. Der
      // liegt hinter dem Tor, und das Tor verbraucht sie. Bis zum 07.09.2026
      // raeumte „Direkt nach dem Lesen" sie beim Verlassen des Chats weg,
      // ungeoeffnet, auf beiden Geraeten: wer nur kurz hineinsah, hatte sie
      // verloren, ohne sie je gesehen zu haben.
      expect(
        SelfDestructPolicy.nachLesenFaellig(
            nachricht(gelesenAm: gelesen, einmalig: true),
            regelNachLesen: true),
        isFalse,
      );
    });

    test('die Uhr laeuft in einem solchen Chat nicht mit', () {
      // „Direkt nach dem Lesen" ist keine Frist. Ohne Chat-Frist und ohne
      // eigene Frist gibt es keinen Ablaufzeitpunkt.
      expect(SelfDestructPolicy.deadline(nachricht(gelesenAm: gelesen)),
          isNull);
    });
  });

  group('Was eine Ablaufmeldung in einem solchen Chat raeumen darf', () {
    Message meine({Duration? frist}) => Message(
          id: 'm1',
          chatId: 'c1',
          senderId: 'ich',
          recipientId: 'marco',
          encryptedContent: 'x',
          timestamp: DateTime(2026, 9, 4, 12),
          deliveredAt: DateTime(2026, 9, 4, 12),
          selfDestructDuration: frist,
        );

    test('meine eigene Nachricht, wenn die Regel des Chats sie vergaenglich '
        'macht', () {
      // Ohne das bliebe die Nachricht beim Absender stehen, waehrend sie beim
      // Empfaenger verschwindet — genau der Fehler, den die einmalige
      // Nachricht am 04.09. hatte. Eine Regel, die beiden gehoert, ist
      // dieselbe Zusage wie eine Frist an der Nachricht.
      expect(
        SelfDestructPolicy.acceptBurn(meine(), 'ich', chatVergaenglich: true),
        isTrue,
      );
    });

    test('ohne eine solche Regel weiterhin nicht', () {
      // Die Schranke bleibt: sonst koennte die Gegenseite mit erfundenen
      // Meldungen beliebige Nachrichten von meinem Geraet raeumen.
      expect(
        SelfDestructPolicy.acceptBurn(meine(), 'ich'),
        isFalse,
      );
    });

    test('und nie eine fremde Nachricht', () {
      final fremd = Message(
        id: 'm2',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: DateTime(2026, 9, 4, 12),
      );
      expect(
        SelfDestructPolicy.acceptBurn(fremd, 'ich', chatVergaenglich: true),
        isFalse,
      );
    });

    test('der Empfaenger meldet den Ablauf auch bei einer Chat-Regel', () {
      final fremd = Message(
        id: 'm2',
        chatId: 'c1',
        senderId: 'marco',
        recipientId: 'ich',
        encryptedContent: 'x',
        timestamp: DateTime(2026, 9, 4, 12),
      );
      expect(
        SelfDestructPolicy.announceBurn(fremd, 'ich', chatVergaenglich: true),
        isTrue,
      );
      expect(SelfDestructPolicy.announceBurn(fremd, 'ich'), isFalse);
    });
  });

  // ─── Daniels Regelwerk vom 07.09.2026 ────────────────────────────────
  //
  // Seine Worte: „nachrichten zum 1 mal ansehen sollten vom löschtimer nicht
  // betroffen sein, sie sollten da bleiben und dann nach dem schliessen der
  // nachricht verschwinden. die passwortgeschützten nachrichten sollten die
  // gleichen regeln gelten wie für normale nachrichten. wenn man die
  // allgemeine einstellung im chat hat nach dem lesen löschen, sollten
  // nachrichten im chat bleiben bis sie gelesen wurden und wenn der empfänger
  // den chat verlässt oder die app verlässt direkt entfernt werden. ebenfalls
  // überall ausser bei den nachrichten zum 1 mal öffnen. der allgemeine
  // selbstlösch timer sollte aber sonst ab zustellung gelten."
  //
  // Vier Aussagen, hier zusammen an einer Stelle. Sie standen bisher in drei
  // Dateien verteilt, und genau dazwischen ist die einmalige Nachricht
  // durchgefallen: sie erbte die Chat-Frist und wurde von „Direkt nach dem
  // Lesen" ungeoeffnet weggeraeumt.
  group('Daniels Regelwerk vom 07.09.2026', () {
    Message m({
      required String von,
      bool einmalig = false,
      bool passwort = false,
      DateTime? gelesenAm,
      Duration? eigeneFrist,
    }) =>
        Message(
          id: 'm1',
          chatId: 'c1',
          senderId: von,
          recipientId: von == 'ich' ? 'marco' : 'ich',
          encryptedContent: 'x',
          timestamp: DateTime(2026, 9, 7, 12),
          deliveredAt: DateTime(2026, 9, 7, 12),
          readAt: gelesenAm,
          selfDestructDuration: eigeneFrist,
          selfDestructFromChat: eigeneFrist == null,
          einmalig: einmalig,
          isPasswordProtected: passwort,
          passwordUnlocked: !passwort,
        );

    final zustellung = DateTime(2026, 9, 7, 12);
    const chatFrist = Duration(minutes: 5);

    test('1. die einmalige Nachricht kennt keinen Loeschtimer', () {
      expect(
        SelfDestructPolicy.deadline(m(von: 'marco', einmalig: true),
            chatTimer: chatFrist),
        isNull,
      );
    });

    test('1. und auch „Direkt nach dem Lesen" laesst sie stehen', () {
      // Ihr Lesevermerk steht schon bei der Zustellung, wenn der Chat offen
      // ist. Gelesen ist dann die Blase, nicht der Inhalt.
      expect(
        SelfDestructPolicy.nachLesenFaellig(
            m(von: 'marco', einmalig: true, gelesenAm: zustellung),
            regelNachLesen: true),
        isFalse,
      );
    });

    test('2. die passwortgeschuetzte folgt derselben Regel wie eine normale',
        () {
      // Keine Sonderbehandlung, ausdruecklich. Die Folge, offen gesagt: steht
      // der Chat auf „Direkt nach dem Lesen", kann sie beim Verlassen des
      // Chats verschwinden, bevor sie jemand entsperrt hat — genau wie eine
      // gewoehnliche, die niemand gelesen hat. Das ist die Regel, nicht ein
      // Versehen.
      final gesperrt = m(von: 'marco', passwort: true, gelesenAm: zustellung);
      final gewoehnlich = m(von: 'marco', gelesenAm: zustellung);

      expect(
        SelfDestructPolicy.deadline(gesperrt, chatTimer: chatFrist),
        SelfDestructPolicy.deadline(gewoehnlich, chatTimer: chatFrist),
      );
      expect(
        SelfDestructPolicy.nachLesenFaellig(gesperrt, regelNachLesen: true),
        SelfDestructPolicy.nachLesenFaellig(gewoehnlich, regelNachLesen: true),
      );
    });

    test('3. „nach dem Lesen loeschen": ungelesen bleibt, gelesen geht', () {
      expect(
        SelfDestructPolicy.nachLesenFaellig(m(von: 'marco'),
            regelNachLesen: true),
        isFalse,
        reason: 'ungelesen bleibt sie liegen, egal wie lange',
      );
      expect(
        SelfDestructPolicy.nachLesenFaellig(
            m(von: 'marco', gelesenAm: zustellung),
            regelNachLesen: true),
        isTrue,
        reason: 'geraeumt wird beim Verlassen von Chat oder App',
      );
    });

    test('4. der allgemeine Timer rechnet ab der Zustellung, nicht ab dem Lesen',
        () {
      // Ungelesen und gelesen ergeben denselben Ablaufzeitpunkt.
      final ablauf = zustellung.add(chatFrist);
      expect(SelfDestructPolicy.deadline(m(von: 'marco'), chatTimer: chatFrist),
          ablauf);
      expect(
        SelfDestructPolicy.deadline(m(von: 'marco', gelesenAm: zustellung),
            chatTimer: chatFrist),
        ablauf,
      );
    });
  });
}
