import 'control_message_policy.dart';

/// Eine Meldung an die Gegenseite, die noch nicht raus ist.
///
/// Heute nur die Ablaufmeldung (`burned`): der Empfaenger hat eine einmalige
/// Nachricht geoeffnet oder eine mit Frist ist bei ihm abgelaufen, und der
/// Absender soll seine Fassung ebenfalls entfernen.
class AusstehendeMeldung {
  final String chatId;
  final String messageId;
  final String art;

  /// Wann sie faellig wurde. Danach bemisst sich, ob die Gegenseite sie
  /// ueberhaupt noch annehmen wuerde, siehe [AusstehendeMeldungen.verfall].
  final DateTime seit;

  const AusstehendeMeldung({
    required this.chatId,
    required this.messageId,
    required this.art,
    required this.seit,
  });

  Map<String, dynamic> toMap() => {
        'chatId': chatId,
        'messageId': messageId,
        'art': art,
        'seit': seit.millisecondsSinceEpoch,
      };

  /// Liest einen Eintrag; `null`, wenn er unbrauchbar ist.
  ///
  /// Fehlt nur der Zeitpunkt, gilt [jetzt]: lieber einmal zu oft senden als
  /// einen Bestand still verfallen lassen.
  static AusstehendeMeldung? fromMap(Object? raw, {required DateTime jetzt}) {
    if (raw is! Map) return null;
    final chatId = raw['chatId'];
    final messageId = raw['messageId'];
    final art = raw['art'];
    if (chatId is! String || messageId is! String || art is! String) {
      return null;
    }
    final seitMs = raw['seit'];
    return AusstehendeMeldung(
      chatId: chatId,
      messageId: messageId,
      art: art,
      seit: seitMs is int ? DateTime.fromMillisecondsSinceEpoch(seitMs) : jetzt,
    );
  }
}

/// Die Meldungen an die Gegenseite, die noch rausmuessen.
///
/// Bis zum 07.09.2026 hing die Ablaufmeldung einer einmaligen Nachricht an
/// einem Zeitgeber, der 0,5 bis 5 Sekunden wartete, und an nichts sonst. Wer
/// in dieser Spanne die App wegwischte, den Akku verlor oder gerade kein Netz
/// hatte, hat die Meldung verloren: die Nachricht war beim Empfaenger fort
/// und stand beim Absender fuer immer. Die Zusage „auf beiden Geraeten weg"
/// war damit nur auf einem gehalten.
///
/// Jetzt wird die Meldung **zuerst festgeschrieben**, dann gesendet, und erst
/// nach dem gelungenen Senden gestrichen. Was beim Start oder beim Aufwachen
/// noch hier steht, wird nachgeholt. Der Absender bekommt sie damit auch
/// dann, wenn der Empfaenger die App gleich nach dem Lesen weglegt.
///
/// Reine Datenhaltung ohne Firebase, damit sie sich pruefen laesst — die
/// Hausregel dieses Projekts, siehe UnreadPolicy und EinmaligPolicy. Das
/// Senden selbst bleibt beim Provider.
class AusstehendeMeldungen {
  /// Mehr wird nicht gemerkt; die aelteste faellt weg. Eine Liste, die nie
  /// kuerzer wird, waere ein Leck — und wer so viele Meldungen liegen hat,
  /// hat ein anderes Problem als die aelteste davon.
  static const int hoechstens = 500;

  /// Wie lange eine Meldung nachgeholt wird. Danach wuerde die Gegenseite
  /// sie ohnehin verwerfen, siehe ControlMessagePolicy.
  static const Duration verfall = ControlMessagePolicy.lang;

  static const String _artAblauf = 'burned';

  final List<AusstehendeMeldung> _liste;

  AusstehendeMeldungen() : _liste = [];

  AusstehendeMeldungen._(this._liste);

  /// Liest, was auf der Platte lag. Unbrauchbare Eintraege werden
  /// uebergangen, nicht geworfen — ein kaputter Eintrag darf weder den Start
  /// der App kosten noch die brauchbaren daneben.
  factory AusstehendeMeldungen.fromJson(Object? raw, {DateTime? jetzt}) {
    final now = jetzt ?? DateTime.now();
    if (raw is! List) return AusstehendeMeldungen();
    final liste = <AusstehendeMeldung>[];
    for (final eintrag in raw) {
      final m = AusstehendeMeldung.fromMap(eintrag, jetzt: now);
      if (m != null) liste.add(m);
    }
    return AusstehendeMeldungen._(liste);
  }

  List<Map<String, dynamic>> toJson() =>
      _liste.map((m) => m.toMap()).toList();

  List<AusstehendeMeldung> get alle => List.unmodifiable(_liste);

  bool get istLeer => _liste.isEmpty;

  /// Eine Ablaufmeldung vormerken. Sagt, ob sie neu ist — dieselbe Meldung
  /// wird nicht zweimal gefuehrt, sonst ginge sie beim Nachholen doppelt raus.
  bool merken({
    required String chatId,
    required String messageId,
    required DateTime jetzt,
  }) {
    if (_liste.any((m) =>
        m.chatId == chatId && m.messageId == messageId && m.art == _artAblauf)) {
      return false;
    }
    _liste.add(AusstehendeMeldung(
      chatId: chatId,
      messageId: messageId,
      art: _artAblauf,
      seit: jetzt,
    ));
    while (_liste.length > hoechstens) {
      _liste.removeAt(0);
    }
    return true;
  }

  /// Die Meldung ist raus. Sagt, ob sie ueberhaupt vorgemerkt war.
  bool erledigt({required String chatId, required String messageId}) {
    final vorher = _liste.length;
    _liste.removeWhere((m) =>
        m.chatId == chatId && m.messageId == messageId && m.art == _artAblauf);
    return _liste.length != vorher;
  }

  /// Mit dem Chat gehen seine Meldungen: es gibt keine Sitzung mehr, gegen
  /// die sie signiert wuerden. Gibt zurueck, wie viele weg sind.
  int fuerChatVerwerfen(String chatId) {
    final vorher = _liste.length;
    _liste.removeWhere((m) => m.chatId == chatId);
    return vorher - _liste.length;
  }

  /// Wirft weg, was die Gegenseite nicht mehr annehmen wuerde. Gibt zurueck,
  /// wie viele weg sind.
  int verfalleneVerwerfen(DateTime jetzt) {
    final vorher = _liste.length;
    _liste.removeWhere((m) => jetzt.difference(m.seit) > verfall);
    return vorher - _liste.length;
  }
}
