/// The small page that runs in a Chrome window next to Smart Kadai.
///
/// Chrome's built-in speech recognition (the Web Speech API) turns the
/// owner's speech into text, with words streaming while they speak. The page
/// sends that text to the desktop app over a local WebSocket on this PC
/// (127.0.0.1 only, never the network).
const chromeHelperPage = r'''<!doctype html>
<html lang="ta">
<head>
<meta charset="utf-8">
<title>Smart Kadai voice</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { --green:#1F6B45; --ink:#1C211B; --quiet:#565E53; --line:#D9DDD4; --red:#9A2C0E; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: "Segoe UI", "Nirmala UI", system-ui, sans-serif; background:#F4F5F1; color:var(--ink); }
  main { padding:16px; display:flex; flex-direction:column; gap:12px; min-height:100vh; }
  header { display:flex; justify-content:space-between; align-items:center; gap:8px; }
  h1 { margin:0; font-size:18px; }
  #status { font-size:13px; color:var(--quiet); }
  #status.ok { color:var(--green); font-weight:600; }
  #status.bad { color:var(--red); font-weight:600; }
  #mic { width:100%; min-height:120px; border:0; border-radius:18px; background:var(--green); color:#fff;
         font: 600 22px "Segoe UI","Nirmala UI",sans-serif; cursor:pointer; display:flex; flex-direction:column;
         align-items:center; justify-content:center; gap:4px; user-select:none; }
  #mic small { font-size:14px; font-weight:500; }
  #mic.on { background:var(--red); }
  #heard { min-height:64px; background:#fff; border:1px solid var(--line); border-radius:12px; padding:12px; font-size:18px; }
  #heard .interim { color:var(--quiet); }
  .row { display:flex; gap:8px; align-items:center; font-size:14px; }
  select { font: inherit; padding:6px 8px; border-radius:8px; border:1px solid var(--line); }
  p { margin:0; font-size:13px; color:var(--quiet); }
</style>
</head>
<body>
<main>
  <header>
    <h1>Smart Kadai voice · குரல்</h1>
    <span id="status">Connecting…</span>
  </header>
  <button id="mic" type="button" aria-pressed="false">
    <span id="micLabel">Click to speak · பேசுங்கள்</span>
    <small>or press F2 in Smart Kadai</small>
  </button>
  <div id="heard" aria-live="polite"></div>
  <div class="row">
    <label for="lang">Language</label>
    <select id="lang">
      <option value="ta-IN">Tamil and Tanglish (ta-IN)</option>
      <option value="en-IN">English (en-IN)</option>
    </select>
  </div>
  <p>Keep this window open. Chrome needs internet for speech.</p>
</main>
<script>
(() => {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  const statusEl = document.getElementById('status');
  const mic = document.getElementById('mic');
  const micLabel = document.getElementById('micLabel');
  const heard = document.getElementById('heard');
  const langSel = document.getElementById('lang');
  try { langSel.value = localStorage.getItem('sk-lang') || 'ta-IN'; } catch (e) {}

  let ws = null, rec = null, wanted = false, running = false;

  function setStatus(text, cls) { statusEl.textContent = text; statusEl.className = cls || ''; }
  function send(obj) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj)); }

  function connect() {
    ws = new WebSocket('ws://' + location.host + '/ws');
    ws.onopen = () => { setStatus('Connected to Smart Kadai', 'ok'); send({type: 'hello', supported: !!SR}); };
    ws.onclose = () => { setStatus('Smart Kadai is closed', 'bad'); setTimeout(connect, 1500); };
    ws.onmessage = (e) => {
      let m; try { m = JSON.parse(e.data); } catch (_) { return; }
      if (m.cmd === 'start') start();
      if (m.cmd === 'stop') stop();
      if (m.cmd === 'toggle') wanted ? stop() : start();
    };
  }

  function render(finalText, interim) {
    heard.innerHTML = '';
    if (finalText) heard.append(document.createTextNode(finalText + ' '));
    if (interim) { const s = document.createElement('span'); s.className = 'interim'; s.textContent = interim; heard.append(s); }
  }

  function makeRecognizer() {
    const r = new SR();
    r.lang = langSel.value;
    r.continuous = true;
    r.interimResults = true;
    r.maxAlternatives = 3;
    r.onstart = () => { running = true; send({type: 'state', listening: true}); };
    r.onresult = (ev) => {
      let interim = '';
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const res = ev.results[i];
        if (res.isFinal) {
          const alts = [];
          for (let j = 0; j < res.length; j++) alts.push(res[j].transcript.trim());
          render(alts[0], '');
          send({type: 'final', text: alts[0], alternatives: alts});
        } else {
          interim += res[0].transcript;
        }
      }
      if (interim) { render('', interim); send({type: 'partial', text: interim.trim()}); }
    };
    r.onerror = (ev) => {
      if (ev.error === 'not-allowed' || ev.error === 'service-not-allowed') {
        setStatus('Allow the microphone for this page', 'bad');
        wanted = false;
      } else if (ev.error === 'network') {
        setStatus('No internet for speech', 'bad');
      }
      send({type: 'error', error: ev.error});
    };
    r.onend = () => {
      running = false;
      // Chrome stops after a silence; keep listening while the owner wants it.
      if (wanted) { try { r.start(); } catch (_) {} } else { send({type: 'state', listening: false}); }
      updateButton();
    };
    return r;
  }

  function updateButton() {
    mic.classList.toggle('on', wanted);
    mic.setAttribute('aria-pressed', String(wanted));
    micLabel.textContent = wanted ? 'Listening… click to stop' : 'Click to speak · பேசுங்கள்';
  }

  function start() {
    if (!SR) { setStatus('Open this page in Google Chrome', 'bad'); return; }
    wanted = true; updateButton();
    if (!rec) rec = makeRecognizer();
    if (!running) { try { rec.start(); } catch (_) {} }
  }
  function stop() {
    wanted = false; updateButton();
    if (rec) { try { rec.stop(); } catch (_) {} }
  }

  mic.addEventListener('click', () => wanted ? stop() : start());
  langSel.addEventListener('change', () => {
    try { localStorage.setItem('sk-lang', langSel.value); } catch (e) {}
    const was = wanted; stop(); rec = null; if (was) setTimeout(start, 300);
  });
  if (!SR) setStatus('Open this page in Google Chrome', 'bad');
  connect();
})();
</script>
</body>
</html>
''';
