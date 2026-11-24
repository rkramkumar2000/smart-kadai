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
- **Billing screen**: speak (through Chrome, below), type, scan a barcode
  (USB scanners type into the search box), or tap quick items. Shows what was heard, the matched product,
  size, quantity and price, with manual correction. Cash, UPI or credit saves
  the bill and lowers stock.
- **Login**: the owner sets a 4-digit PIN on first run. Staff logins can bill
  and see stock, but not profit, prices, purchases, reports or settings.
  Five wrong PINs lock the login for 30 seconds. The lock button returns to
  the PIN screen.
- **Stock**: levels, low and out-of-stock alerts (badge in the menu), stock
  value, corrections with a reason, history per product, and an order list
  sent on WhatsApp.
- **Purchases**: suppliers and what the shop owes them, payments, supplier
  bills typed in or read from a photo or PDF. Saving raises stock and updates
  the cost price including GST.
- **Reading bill photos**: uses Claude (Anthropic API, key in Settings). The
  owner checks every line before saving.
- **Reports**: today, last 7 days, this month. Sales, profit, purchases,
  supplier dues, sales by day, payment split, best sellers. Sales and purchase
  lines export to Excel (CSV with Tamil names).
- **Bill printing**: 58 mm or 80 mm thermal roll, or A5, through the Windows
  print dialog. Optional print on every bill.
- **Settings**: shop details on the bill, printer, logins, AI key, backup.
- Offline local SQLite database on the PC.

## Voice through Chrome (free)

Speech-to-text uses Google Chrome's built-in speech recognition, which is
free and supports Tamil (ta-IN) with words streaming while you speak.

1. When Smart Kadai starts, it opens a small **Smart Kadai voice** window in
   Chrome. The first time, click **Allow** for the microphone.
2. Click the big button in that window, or press **F2** in Smart Kadai, and
   speak. Each item goes on the bill when you finish saying it.
3. Choose **English (en-IN)** in the window if the speaker uses only English.

Needs Google Chrome and internet. The page runs on `127.0.0.1:47811` on this
PC only. Every phrase heard is saved in the `voice_log` table with what it
became, so accuracy can be checked after a few days at the counter. The
speech service is behind `lib/voice/speech_service.dart`, so a paid service
(for example Sarvam AI) can replace Chrome later without changing billing.

To try the helper without the app: `dart run tool/voice_helper_preview.dart`.

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
| `lib/auth` | Logins, PIN hashing, owner and staff permissions |
| `lib/purchases` | Suppliers, purchase bills, payments, bill photo reader |
| `lib/reports` | Sales and purchase figures, CSV export |
| `lib/printing` | Bill PDF for thermal rolls and A5 |
| `lib/ui` | Desktop screens: login, shell, billing, products, stock, purchases, reports, settings |
