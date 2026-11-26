import 'phonetic.dart';
import 'vocabulary.dart';

/// Things the owner can say instead of pressing a key.
enum VoiceCommand {
  /// Save the bill as cash: "bill podu", "பில் போடு", "cash", "முடிஞ்சது".
  saveCash,

  /// Save as UPI: "UPI", "GPay", "PhonePe".
  saveUpi,

  /// Save as credit (kadan): "கடன்", "credit", "கணக்கு".
  saveCredit,

  /// Clear the whole bill: "cancel", "கேன்சல்", "எல்லாம் வேண்டாம்".
  clear,

  /// Remove the last item: "கடைசி வேண்டாம்", "venda", "undo".
  removeLast,

  /// Say the total aloud: "total", "மொத்தம் எவ்வளவு".
  total,
}

const _phrases = <VoiceCommand, List<String>>{
  VoiceCommand.saveCash: [
    'bill podu', 'bill pottu', 'bill potu', 'பில் போடு', 'பில் போட்டு', //
    'save', 'save bill', 'bill save', 'cash', 'கேஷ்', 'காஷ்', 'panam',
    'பணம்', 'cash bill', 'mudinjathu', 'mudinjidhu', 'முடிஞ்சது',
    'முடிந்தது', 'அவ்வளவு தான்', 'avvalavu than', 'avlo than', 'அவ்ளோ தான்',
    'that is all', 'thats all', 'done', 'print',
  ],
  VoiceCommand.saveUpi: [
    'upi', 'யுபிஐ', 'யூபிஐ', 'gpay', 'g pay', 'ஜிபே', 'ஜி பே', 'phonepe', //
    'phone pe', 'போன்பே', 'போன் பே', 'paytm', 'பேடிஎம்', 'upi bill',
  ],
  VoiceCommand.saveCredit: [
    'kadan', 'கடன்', 'credit', 'கிரெடிட்', 'kanakku', 'கணக்கு', //
    'kanakula', 'கணக்குல', 'கணக்கில்', 'kadan bill',
  ],
  VoiceCommand.clear: [
    'cancel', 'கேன்சல்', 'clear', 'கிளியர்', 'ellam venda', //
    'எல்லாம் வேண்டாம்', 'bill venda', 'பில் வேண்டாம்', 'cancel bill',
    'clear bill', 'அழி', 'azhi', 'new bill', 'புது பில்',
  ],
  VoiceCommand.removeLast: [
    'kadaisi venda', 'கடைசி வேண்டாம்', 'athu venda', 'அது வேண்டாம்', //
    'venda', 'வேண்டாம்', 'vendam', 'remove last', 'remove', 'undo',
    'last remove', 'delete', 'நீக்கு', 'neekku', 'last venda',
  ],
  VoiceCommand.total: [
    'total', 'டோட்டல்', 'மொத்தம்', 'mottham', 'motham', 'mothama', //
    'எவ்வளவு', 'evvalavu', 'evlo', 'எவ்ளோ', 'மொத்தம் எவ்வளவு',
    'total evlo', 'how much',
  ],
};

/// Sound keys of the words that matter: "ok", "please" and "podu" dropped.
String _norm(String text) {
  final v = Vocabulary.instance;
  return splitWords(text)
      .map(wordKey)
      .where(
        (k) =>
            k.isNotEmpty &&
            k != ',' &&
            !v.joins.contains(k) &&
            !v.fillers.contains(k),
      )
      .join(' ');
}

final Map<String, VoiceCommand> _byKey = {
  for (final e in _phrases.entries)
    for (final p in e.value)
      if (_norm(p).isNotEmpty) _norm(p): e.key,
};

/// The command in [text] when the whole phrase is a command, else null.
/// "ok bill podu" and "சரி கேன்சல்" are commands; "ரெண்டு கடலை, cash" is
/// an order, so a command word inside an order never saves the bill.
VoiceCommand? detectCommand(String text) {
  final key = _norm(text);
  if (key.isEmpty || key.split(' ').length > 4) return null;
  return _byKey[key];
}
