# Renders the "Zennit and the Index" intro into addon textures.
#
#   1. Patches tools\intro\source.html so ?#s=<scene>&f=<frame> draws one still, full-window.
#   2. Screenshots all 8 scenes x 3 frames with headless Edge or Chrome (1024x512, stretched from 16:9;
#      the in-game viewer squeezes it back).
#   3. Packs each scene into a 2048x1024 sheet (2x2 cells; cell order: left to right, top to bottom, the
#      4th cell empty) and writes Media\intro_<n>.blp (DXT1 with mipmaps).
#
#   powershell -ExecutionPolicy Bypass -File tools\intro\render_intro.ps1 [-Format tga]
#
# Scene numbers are the story's: 1 to 32 are season one, 33 is "The Index today" (no picture of its own), and season two's
# scenes follow it from 34 (Season2.lua). -Source and -Work render a copy of the page into a folder of your own, so two
# renders cannot step on each other; -PngOnly stops after the screenshots (no sheets, nothing written to Media).
param([ValidateSet("blp", "tga")][string]$Format = "blp", [switch]$SkipRender,
      [ValidateSet("storybook", "lines")][string]$Style = "storybook",
      [string]$SceneList = "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59",  # for example "9,10"; a text list because -File flattens 9,10 into 910
      [string]$Source = "", [string]$Work = "", [switch]$PngOnly)
$ErrorActionPreference = "Stop"
$sceneIds = @($SceneList -split '[,\s]+' | Where-Object { $_ } | ForEach-Object { [int]$_ })
$here = $PSScriptRoot
$root = Split-Path -Parent (Split-Path -Parent $here)
$media = Join-Path $root "Media"
$work = if ($Work) { $Work } else { Join-Path ([IO.Path]::GetTempPath()) "summoncore_intro" }
New-Item -ItemType Directory -Force $media, $work | Out-Null

# --- 1. patch the page ---
$html = [IO.File]::ReadAllText($(if ($Source) { $Source } else { Join-Path $here "source.html" }))
$tail = [regex]'update\(0\);\s*requestAnimationFrame\(loop\);\s*\}\)\(\);'
if (-not $tail.IsMatch($html)) { throw "source.html changed: could not find the start-up code to patch" }
$patch = @'
// Chrome does not pass document CSS into <use> copies, so unpack each one into real shapes first.
function expandUses() {
  Array.prototype.slice.call(document.querySelectorAll('#stage use')).forEach(function (u) {
    var id = (u.getAttribute('href') || '').slice(1);
    var sym = document.getElementById(id);
    if (!sym) return;
    var vb = (sym.getAttribute('viewBox') || '0 0 100 100').split(/[ ,]+/).map(Number);
    var x = +u.getAttribute('x') || 0, y = +u.getAttribute('y') || 0;
    var w = +u.getAttribute('width') || vb[2], h = +u.getAttribute('height') || vb[3];
    var k = Math.min(w / vb[2], h / vb[3]);
    var g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.setAttribute('class', 'sym-' + id);
    g.setAttribute('transform', 'translate(' + (x + (w - vb[2] * k) / 2 - vb[0] * k) + ' ' + (y + (h - vb[3] * k) / 2 - vb[1] * k) + ') scale(' + k + ')');
    if (u.getAttribute('opacity')) g.setAttribute('opacity', u.getAttribute('opacity'));
    Array.prototype.slice.call(sym.childNodes).forEach(function (c) { g.appendChild(c.cloneNode(true)); });
    u.parentNode.replaceChild(g, u);
  });
}
var q = new URLSearchParams(location.hash.slice(1));
  if (q.has('s')) {
    document.documentElement.classList.add('shot');
    stage.setAttribute('preserveAspectRatio', 'none');
    if (q.has('line')) {
      document.documentElement.classList.add('line');
      document.querySelector('svg defs').insertAdjacentHTML('beforeend', '<pattern id="spinesLine" width="30" height="70" patternUnits="userSpaceOnUse"><path d="M7 6V66M22 4V66" stroke="#2b230a" stroke-width="1" fill="none"/></pattern>');
    }
    render(+q.get('s'), +q.get('f'), +q.get('f'));
    if (q.has('line')) expandUses();
    // the neon look letters in bold capitals, which run wider: every label is set a little smaller so it keeps its place
    if (q.has('line')) Array.prototype.slice.call(document.querySelectorAll('#stage text')).forEach(function (t) {
      var size = parseFloat(t.getAttribute('font-size') || getComputedStyle(t).fontSize);
      if (size) { t.setAttribute('font-size', (size * 0.8).toFixed(1)); t.style.fontSize = (size * 0.8).toFixed(1) + 'px'; }
    });
  } else { update(0); requestAnimationFrame(loop); }
})();
'@
$lineCss = 'html.shot.line .stage{background:#000}' +
  'html.shot.line #stage{filter:drop-shadow(0 0 2px rgba(255,210,60,.35))}' +
  # outlines only: every shape loses its fill and gets a thin neon stroke
  'html.shot.line path,html.shot.line rect,html.shot.line circle,html.shot.line ellipse,html.shot.line polygon,html.shot.line polyline,html.shot.line line{fill:none!important;stroke:#ffd23f!important;stroke-width:2.2px!important;stroke-linejoin:round;stroke-linecap:round;vector-effect:non-scaling-stroke}' +
  # glows, shading and full-frame backdrops are dropped
  'html.shot.line [fill="url(#amber)"],html.shot.line [fill="url(#zglow)"],html.shot.line [fill="url(#glowR)"],html.shot.line [fill="url(#lampGlow)"],html.shot.line [fill="url(#vig)"],html.shot.line [fill="url(#shadeL)"],html.shot.line [fill="url(#shadeR)"],html.shot.line [fill="url(#wall)"],html.shot.line rect[width="960"][height="540"],html.shot.line rect[width="1600"][height="900"]{display:none!important}' +
  # bookshelves become fine vertical lines
  'html.shot.line pattern path{stroke:#4a3c10!important;stroke-width:1.2px!important}' +
  'html.shot.line [fill="url(#spines)"]{fill:url(#spinesLine)!important;stroke:#6f5a16!important}' +
  # solid blue shapes, like the fish: dark clothes, the ritual circle, the wizard
  'html.shot.line [fill="#2F2D38"][fill][fill],html.shot.line [fill="#4A4A5E"][fill][fill],html.shot.line [fill="#2B2140"][fill][fill],html.shot.line [fill="#5B3FA0"][fill][fill],html.shot.line [fill="#7A52C7"][fill][fill],html.shot.line [fill="#3E5B4E"][fill][fill]{fill:#1f45c8!important}' +
  # a quiet background: the hall and shelves are thin and dim
  'html.shot.line .sym-hall path,html.shot.line .sym-hall polygon,html.shot.line .sym-hall rect,html.shot.line .sym-hall circle,html.shot.line .sym-hall line{stroke:#6a5718!important;stroke-width:1.3px!important}' +
  'html.shot.line .sym-hall [fill="url(#spines)"]{fill:url(#spinesLine)!important;stroke:#6a5718!important}' +
  # solid characters: filled black so nothing behind shows through, with a bolder, brighter outline
  'html.shot.line :is(.sym-zenit,.sym-clerkFront,.sym-clerkBack,.sym-book,.sym-form,.sym-auditor,.sym-poogs) :is(path,rect,circle,ellipse,polygon):not([fill="none"]){fill:#000!important}' +
  'html.shot.line :is(.sym-zenit,.sym-clerkFront,.sym-clerkBack,.sym-book,.sym-form,.sym-auditor,.sym-poogs) :is(path,rect,circle,ellipse,polygon,line){stroke:#ffe270!important;stroke-width:2.6px!important}' +
  # the figures inside the ritual circles (someone else, the goat): bright white outline over a dark fill so they stand out from the circle
  'html.shot.line .feature path,html.shot.line .feature circle,html.shot.line .feature ellipse,html.shot.line .feature rect,html.shot.line .feature polygon{fill:#07102e!important;stroke:#fff3b0!important;stroke-width:3px!important}' +
  'html.shot.line .feature path[fill="none"]{fill:none!important}' +
  # green leader lines and labels
  'html.shot.line text{fill:#6dff9a!important;stroke:none!important}' +
  'html.shot.line text[fill][fill][fill][fill][fill]{fill:#6dff9a!important}'
$baseCss = 'html.shot,html.shot body{margin:0;padding:0;overflow:hidden;background:#000}html.shot main>*:not(.stage){display:none}html.shot header,html.shot .bigplay{display:none}html.shot .stage{position:fixed;left:0;top:0;width:100vw;height:100vh;max-width:none;border:0;border-radius:0;aspect-ratio:auto}'
# the neon look's colours (a colour for each subject, glowing tube lines, capital labels) are in lines.css, which
# tools\intro\render_intro.py reads too
$guideCss = [IO.File]::ReadAllText((Join-Path $here "lines.css"))
$css = '<style>' + $baseCss + $lineCss + $guideCss + '</style></head>'
$patched = $tail.Replace($html, { param($m) $patch }).Replace("</head>", $css)
$page = Join-Path $work "render.html"
[IO.File]::WriteAllText($page, $patched)
$url = "file:///" + $page.Replace("\", "/")

# --- 2. screenshots ---
$browser = @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw "Edge or Chrome not found" }
$styleFlag = switch ($Style) { "lines" { "&line=1" } default { "" } }
$namePrefix = switch ($Style) { "lines" { "intro_l" } default { "intro_" } }
$scenes = $sceneIds.Count
$done = 0
foreach ($n in $sceneIds) {
    if ($SkipRender) { break }
    $s = $n - 1
    for ($f = 0; $f -lt 3; $f++) {
        $png = Join-Path $work ("{0}_s{1}_f{2}.png" -f $Style, $s, $f)
        Remove-Item -LiteralPath $png -ErrorAction SilentlyContinue
        $p = Start-Process -FilePath $browser -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
            "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            "--user-data-dir=`"$work\edge-profile`"", "--window-size=1024,512", "--virtual-time-budget=8000", "--screenshot=`"$png`"", "`"$url#s=$s&f=$f$styleFlag`"")
        if (-not (Test-Path -LiteralPath $png)) { throw "no screenshot for scene $s frame $f" }
    }
    $done++
    "rendered scene {0} ({1}/{2})" -f ($s + 1), $done, $scenes
}
if ($PngOnly) { "frames are in $work (" + $Style + "_s<scene-1>_f<0-2>.png)"; return }

# --- 3. sheets ---
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class SheetGen {
    public const int Cell = 1024, CellH = 512, W = 2048, H = 1024;

    public static Bitmap Compose(string[] frames) {
        var sheet = new Bitmap(W, H, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(sheet)) {
            g.Clear(Color.Black);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            for (int i = 0; i < frames.Length; i++) {
                using (var img = Image.FromFile(frames[i]))
                    // Crop the edges: the wobble filter smears the page background in there.
                    g.DrawImage(img, new Rectangle((i % 2) * Cell, (i / 2) * CellH, Cell, CellH),
                        8, 6, img.Width - 16, img.Height - 12, GraphicsUnit.Pixel);
            }
        }
        return sheet;
    }

    static byte[] Pixels(Bitmap bmp) {
        var d = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var buf = new byte[Math.Abs(d.Stride) * bmp.Height];
        System.Runtime.InteropServices.Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        bmp.UnlockBits(d);
        return buf; // BGRA, stride = width*4
    }

    public static void WriteTga(Bitmap bmp, string path) {
        int w = bmp.Width, h = bmp.Height;
        var px = Pixels(bmp);
        using (var fs = new FileStream(path, FileMode.Create))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write((byte)0); bw.Write((byte)0); bw.Write((byte)2);
            bw.Write((short)0); bw.Write((short)0); bw.Write((byte)0);
            bw.Write((short)0); bw.Write((short)0); bw.Write((short)w); bw.Write((short)h);
            bw.Write((byte)24); bw.Write((byte)0);
            var row = new byte[w * 3];
            for (int y = h - 1; y >= 0; y--) {
                for (int x = 0; x < w; x++) {
                    int s = (y * w + x) * 4;
                    row[x * 3] = px[s]; row[x * 3 + 1] = px[s + 1]; row[x * 3 + 2] = px[s + 2];
                }
                bw.Write(row);
            }
        }
    }

    // ---- DXT1 ----
    static int Pack565(int r, int g, int b) { return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3); }
    static void Unpack565(int c, out int r, out int g, out int b) {
        r = ((c >> 11) & 31); r = (r << 3) | (r >> 2);
        g = ((c >> 5) & 63); g = (g << 2) | (g >> 4);
        b = (c & 31); b = (b << 3) | (b >> 2);
    }

    static void EncodeBlock(byte[] px, int w, int bx, int by, byte[] outb, int o) {
        int[] r = new int[16], g = new int[16], b = new int[16];
        int minR = 255, minG = 255, minB = 255, maxR = 0, maxG = 0, maxB = 0;
        for (int i = 0; i < 16; i++) {
            int x = bx * 4 + (i & 3), y = by * 4 + (i >> 2);
            int s = (y * w + x) * 4;
            b[i] = px[s]; g[i] = px[s + 1]; r[i] = px[s + 2];
            if (r[i] < minR) minR = r[i]; if (g[i] < minG) minG = g[i]; if (b[i] < minB) minB = b[i];
            if (r[i] > maxR) maxR = r[i]; if (g[i] > maxG) maxG = g[i]; if (b[i] > maxB) maxB = b[i];
        }
        // Inset the bounding box a little: better fit for typical blocks.
        int ir = (maxR - minR) >> 4, ig = (maxG - minG) >> 4, ib = (maxB - minB) >> 4;
        int c0 = Pack565(Math.Min(255, maxR - ir), Math.Min(255, maxG - ig), Math.Min(255, maxB - ib));
        int c1 = Pack565(Math.Max(0, minR + ir), Math.Max(0, minG + ig), Math.Max(0, minB + ib));
        if (c0 < c1) { int t = c0; c0 = c1; c1 = t; }
        uint idx = 0;
        if (c0 != c1) {
            int[,] pal = new int[4, 3];
            Unpack565(c0, out pal[0, 0], out pal[0, 1], out pal[0, 2]);
            Unpack565(c1, out pal[1, 0], out pal[1, 1], out pal[1, 2]);
            for (int k = 0; k < 3; k++) {
                pal[2, k] = (2 * pal[0, k] + pal[1, k]) / 3;
                pal[3, k] = (pal[0, k] + 2 * pal[1, k]) / 3;
            }
            for (int i = 0; i < 16; i++) {
                int best = 0, bestD = int.MaxValue;
                for (int p = 0; p < 4; p++) {
                    int dr = r[i] - pal[p, 0], dg = g[i] - pal[p, 1], db = b[i] - pal[p, 2];
                    int d = dr * dr + dg * dg + db * db;
                    if (d < bestD) { bestD = d; best = p; }
                }
                idx |= (uint)best << (2 * i);
            }
        }
        outb[o] = (byte)c0; outb[o + 1] = (byte)(c0 >> 8);
        outb[o + 2] = (byte)c1; outb[o + 3] = (byte)(c1 >> 8);
        outb[o + 4] = (byte)idx; outb[o + 5] = (byte)(idx >> 8); outb[o + 6] = (byte)(idx >> 16); outb[o + 7] = (byte)(idx >> 24);
    }

    static byte[] Dxt1(byte[] px, int w, int h) {
        int bw = Math.Max(1, (w + 3) / 4), bh = Math.Max(1, (h + 3) / 4);
        var outb = new byte[bw * bh * 8];
        // Pad tiny levels (smaller than 4x4) by edge replication so a block can be read.
        if (w < 4 || h < 4) {
            var padded = new byte[16 * 4];
            for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) {
                int sx = Math.Min(x, w - 1), sy = Math.Min(y, h - 1);
                Array.Copy(px, (sy * w + sx) * 4, padded, (y * 4 + x) * 4, 4);
            }
            EncodeBlock(padded, 4, 0, 0, outb, 0);
            return outb;
        }
        for (int by = 0; by < bh; by++)
            for (int bx = 0; bx < bw; bx++)
                EncodeBlock(px, w, bx, by, outb, (by * bw + bx) * 8);
        return outb;
    }

    static byte[] Half(byte[] px, int w, int h) {
        int nw = Math.Max(1, w / 2), nh = Math.Max(1, h / 2);
        var o = new byte[nw * nh * 4];
        for (int y = 0; y < nh; y++)
            for (int x = 0; x < nw; x++)
                for (int c = 0; c < 4; c++) {
                    int x0 = Math.Min(w - 1, x * 2), x1 = Math.Min(w - 1, x * 2 + 1);
                    int y0 = Math.Min(h - 1, y * 2), y1 = Math.Min(h - 1, y * 2 + 1);
                    int sum = px[(y0 * w + x0) * 4 + c] + px[(y0 * w + x1) * 4 + c] + px[(y1 * w + x0) * 4 + c] + px[(y1 * w + x1) * 4 + c];
                    o[(y * nw + x) * 4 + c] = (byte)((sum + 2) / 4);
                }
        return o;
    }

    // BLP2, DXT1, no alpha, full mipmap chain.
    public static void WriteBlp(Bitmap bmp, string path) {
        int w = bmp.Width, h = bmp.Height;
        var levels = new System.Collections.Generic.List<byte[]>();
        var px = Pixels(bmp);
        int cw = w, ch = h;
        while (true) {
            levels.Add(Dxt1(px, cw, ch));
            if (cw == 1 && ch == 1) break;
            px = Half(px, cw, ch);
            cw = Math.Max(1, cw / 2); ch = Math.Max(1, ch / 2);
        }
        int headerSize = 4 + 4 + 4 + 4 + 4 + 64 + 64 + 1024;
        using (var fs = new FileStream(path, FileMode.Create))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write(new byte[] { (byte)'B', (byte)'L', (byte)'P', (byte)'2' });
            bw.Write((uint)1);                 // type: 1 = BLP2 texture
            bw.Write((byte)2);                 // encoding: DXT
            bw.Write((byte)0);                 // alpha depth
            bw.Write((byte)0);                 // alpha encoding: DXT1
            bw.Write((byte)1);                 // has mipmaps
            bw.Write((uint)w); bw.Write((uint)h);
            uint off = (uint)headerSize;
            for (int i = 0; i < 16; i++) { if (i < levels.Count) { bw.Write(off); off += (uint)levels[i].Length; } else bw.Write((uint)0); }
            for (int i = 0; i < 16; i++) bw.Write(i < levels.Count ? (uint)levels[i].Length : (uint)0);
            bw.Write(new byte[1024]);          // unused palette
            foreach (var l in levels) bw.Write(l);
        }
    }
}
"@

foreach ($n in $sceneIds) {
    $s = $n - 1
    $frames = 0..2 | ForEach-Object { Join-Path $work ("{0}_s{1}_f{2}.png" -f $Style, $s, $_) }
    $sheet = [SheetGen]::Compose($frames)
    $name = "$namePrefix{0}" -f ($s + 1)
    if ($Format -eq "blp") { [SheetGen]::WriteBlp($sheet, (Join-Path $media "$name.blp")); $ext = "blp" }
    else { [SheetGen]::WriteTga($sheet, (Join-Path $media "$name.tga")); $ext = "tga" }
    if ($n -eq $sceneIds[0]) { $sheet.Save((Join-Path $work "sheet1_$Style.png")) }
    $sheet.Dispose()
    "{0}.{1}  {2:N2} MB" -f $name, $ext, ((Get-Item (Join-Path $media "$name.$ext")).Length / 1MB)
}
"Preview of sheet 1: " + (Join-Path $work "sheet1_$Style.png")
