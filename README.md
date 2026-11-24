# Smart Kadai

A simple, fast billing and shop app for Tamil Nadu grocery shops. The Windows
desktop app comes first; Android follows from the same Flutter code.

## What works now

- **Product catalogue**: product ID, English, Tamil and Tanglish names,
  category, brand, description, barcode, purchase and selling price, minimum
  stock, status, created and updated dates.
- **Variants**: one product sold in many sizes (Groundnut 250 GRAM, 500 GRAM,
  1 KG, 5 KG, 10 KG; Hamam Soap 1 PIECE, 1 BOX).
- **Units**: KG, GRAM, LITRE, ML, PIECE, PACKET, BOX, DOZEN, BAG. Fixed
  conversions (1 KG = 1000 GRAM) are automatic; for BOX, PACKET and BAG the
  owner enters how many stock units one holds. Selling 250 GRAM of a product
  stocked in KG lowers stock by 0.25 KG.
- **Voice billing parser and matcher** for Tamil, English, Tanglish and mixed
  speech: `ரெண்டு கடலை மிட்டாய்`, `Two Hamam soap`, `அஞ்சு சாக்லேட்`,
  `Oru kilo kadalai`, `அரை கிலோ கடலை`, `Two packet chocolate`. Handles several
  items in one breath, quantity before or after the name, short names,
  spelling and pronunciation differences, and filler words. Unsure matches are
  shown for confirmation, and every correction is learned.
- **Billing screen**: type, scan a barcode (USB scanners type into the search
  box), tap quick items, or speak. Shows what was heard, the matched product,
  size, quantity and price, with manual correction. Cash, UPI or credit saves
  the bill and lowers stock.
- Offline local SQLite database on the PC.

## Not yet connected

- **The microphone and speech-to-text service.** The app talks to speech
  through `lib/voice/speech_service.dart`. Until a service is chosen (phase 0
  test: Sarvam AI, Google Cloud Speech-to-Text or AI4Bharat IndicConformer),
  type what was said into the billing search box to exercise the same parser.

## Run and test

```
flutter pub get
flutter test
flutter run -d windows
```

GitHub Actions builds the Windows app on every push to `main`; download it
from the run's **smart-kadai-windows** artifact.

## Code map

| Folder | What is in it |
| --- | --- |
| `lib/core` | Units and conversion |
| `lib/catalogue` | Product and variant model |
| `lib/data` | SQLite schema, repository, starter catalogue |
| `lib/voice` | Tamil transliteration, sound keys, number and unit words, utterance parser, product matcher, speech service interface |
| `lib/billing` | Bill and bill lines, stock change per line |
| `lib/ui` | Desktop screens: shell, billing, products, product form |
