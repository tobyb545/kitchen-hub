import Foundation

/// The page served at http://<ipad>:8080 — open it on a phone (or scan the QR code on the
/// iPad's Home screen) and add it to the home screen for one-tap sending.
enum SendPage {
    static let html = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-title" content="Kitchen">
    <title>Send to Kitchen</title>
    <style>
    :root { --bg:#faf7f2; --card:#fff; --text:#2b2118; --muted:#7a6a5c; --accent:#e26a3b; --line:#eadfd3; --ok:#2e7d4f; --err:#b3261e; }
    @media (prefers-color-scheme: dark) { :root { --bg:#1b1612; --card:#26201b; --text:#f3ebe3; --muted:#b5a596; --accent:#f48c5f; --line:#3a312a; --ok:#6fcf97; --err:#f2a39c; } }
    * { box-sizing: border-box; }
    body { margin:0; background:var(--bg); color:var(--text); font:17px/1.45 -apple-system, system-ui, sans-serif; padding:24px 16px 48px; }
    main { max-width:560px; margin:0 auto; }
    h1 { font-size:28px; margin:0 0 4px; }
    p.sub { color:var(--muted); margin:0 0 24px; }
    .card { background:var(--card); border:1px solid var(--line); border-radius:18px; padding:18px; margin-bottom:16px; }
    label { font-weight:600; display:block; margin-bottom:8px; }
    input, textarea { width:100%; font:inherit; color:inherit; background:transparent; border:1px solid var(--line); border-radius:12px; padding:12px; }
    textarea { min-height:180px; resize:vertical; }
    button { width:100%; margin-top:12px; font:inherit; font-weight:600; color:#fff; background:var(--accent); border:0; border-radius:12px; padding:14px; }
    button:disabled { opacity:.6; }
    .row { display:flex; gap:8px; }
    .row button { margin-top:0; width:auto; padding:12px 16px; }
    #status { min-height:24px; font-weight:600; text-align:center; margin-top:8px; }
    .ok { color:var(--ok); } .err { color:var(--err); }
    p.hint { color:var(--muted); font-size:15px; margin:-4px 0 10px; }
    input[type=file] { padding:10px; }
    .timers { display:grid; grid-template-columns:repeat(4,1fr); gap:8px; }
    .timers button { margin:0; padding:12px 0; background:transparent; color:var(--accent); border:1px solid var(--line); }
    </style>
    </head>
    <body>
    <main>
      <h1>🍳 Send to Kitchen</h1>
      <p class="sub">Paste a recipe link or the recipe itself and it'll appear on the kitchen iPad, formatted and ready to cook.</p>
      <div class="card">
        <label for="url">Recipe link</label>
        <div class="row">
          <input id="url" type="url" inputmode="url" placeholder="https://…" autocomplete="off">
          <button type="button" onclick="pasteInto('url')">Paste</button>
        </div>
        <button id="sendUrl" onclick="send('url')">Send link</button>
      </div>
      <div class="card">
        <label for="text">…or paste recipe text</label>
        <textarea id="text" placeholder="Title&#10;&#10;Ingredients&#10;200g pasta&#10;…&#10;&#10;Method&#10;1. Boil the pasta…"></textarea>
        <button id="sendText" onclick="send('text')">Send text</button>
      </div>
      <div class="card">
        <label for="photos">…or photos and screenshots</label>
        <p class="hint">Cookbook pages, recipe cards or screenshots. Pick as many as you like: one recipe over several photos, or several different recipes at once. They'll be sorted out.</p>
        <input id="photos" type="file" accept="image/*" multiple>
        <button id="sendPhotos" onclick="sendPhotos()">Send photos</button>
      </div>
      <div id="status" role="status"></div>
      <div class="card">
        <label>Quick timer on the iPad</label>
        <div class="timers">
          <button onclick="timer(1)">1m</button><button onclick="timer(5)">5m</button>
          <button onclick="timer(10)">10m</button><button onclick="timer(20)">20m</button>
        </div>
      </div>
    </main>
    <script>
    const statusEl = document.getElementById('status');
    function show(msg, cls) { statusEl.textContent = msg; statusEl.className = cls || ''; }
    async function pasteInto(id) {
      try { document.getElementById(id).value = await navigator.clipboard.readText(); } catch (e) { show('Long-press the box and choose Paste.', ''); }
    }
    async function send(kind) {
      const el = document.getElementById(kind);
      const value = el.value.trim();
      if (!value) { show('Nothing to send yet.', 'err'); return; }
      const btns = document.querySelectorAll('button'); btns.forEach(b => b.disabled = true);
      show('Sending… formatting can take a few seconds.', '');
      try {
        const res = await fetch('/api/recipe', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({[kind]: value}) });
        const data = await res.json();
        if (data.ok) { show('✓ “' + data.title + '” is on the kitchen iPad', 'ok'); el.value = ''; }
        else { show(data.error || 'Something went wrong', 'err'); }
      } catch (e) { show('Couldn’t reach the iPad — is Kitchen Hub open?', 'err'); }
      btns.forEach(b => b.disabled = false);
    }
    async function shrink(file) {
      const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' });
      const s = Math.min(1, 2200 / Math.max(bmp.width, bmp.height));
      const c = document.createElement('canvas');
      c.width = Math.round(bmp.width * s); c.height = Math.round(bmp.height * s);
      c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
      return c.toDataURL('image/jpeg', 0.85);
    }
    async function sendPhotos() {
      const input = document.getElementById('photos');
      if (!input.files.length) { show('Choose a photo first.', 'err'); return; }
      const btns = document.querySelectorAll('button'); btns.forEach(b => b.disabled = true);
      show('Sending… reading the photo can take a little while.', '');
      try {
        const images = [];
        for (const f of input.files) images.push(await shrink(f));
        const res = await fetch('/api/photos', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ images }) });
        const data = await res.json();
        if (data.ok) {
          const t = data.titles || [data.title];
          show(t.length === 1 ? '✓ “' + t[0] + '” is on the kitchen iPad' : '✓ ' + t.length + ' recipes added: ' + t.join(', '), 'ok');
          input.value = '';
        }
        else { show(data.error || 'Something went wrong', 'err'); }
      } catch (e) { show('Couldn’t send the photo — is Kitchen Hub open?', 'err'); }
      btns.forEach(b => b.disabled = false);
    }
    async function timer(min) {
      try {
        await fetch('/api/timer', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({minutes:min, label: min + ' min timer'}) });
        show('✓ ' + min + ' minute timer started', 'ok');
      } catch (e) { show('Couldn’t reach the iPad', 'err'); }
    }
    const shared = new URLSearchParams(location.search).get('url');
    if (shared) { document.getElementById('url').value = shared; }
    </script>
    </body>
    </html>
    """
}
