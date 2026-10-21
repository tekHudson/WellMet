# Builds the three CurseForge usage infographics (HTML -> PNG via headless Chrome). Run: python3 build.py
import subprocess, pathlib
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CSS = """
*{box-sizing:border-box;margin:0}
body{width:1200px;height:var(--h,760px);background:#14110d;color:#f2e6c9;font-family:Georgia,'Times New Roman',serif;padding:44px 56px;position:relative;overflow:hidden}
body:before{content:"";position:absolute;inset:14px;border:2px solid #6b5420;border-radius:10px;pointer-events:none}
h1{font-size:46px;color:#f5c542;letter-spacing:1px}
.sub{font-size:22px;color:#b9ab86;margin:4px 0 30px}
.row{display:flex;gap:26px;align-items:stretch}
.card{flex:1;background:#201a12;border:2px solid #4a3a18;border-radius:12px;padding:22px 20px;text-align:center;position:relative}
.n{position:absolute;top:-18px;left:50%;margin-left:-18px;width:36px;height:36px;border-radius:50%;background:#f5c542;color:#14110d;font:bold 22px/36px Georgia}
.big{font-size:70px;line-height:1.1;margin:14px 0 8px}
.t{font-size:27px;color:#f5c542;margin-bottom:8px}
.d{font-size:20px;color:#d8cba8;line-height:1.35}
.arrow{align-self:center;font-size:44px;color:#6b5420;margin:0 -10px}
.key{display:inline-block;background:#2c2416;border:2px solid #f5c542;border-bottom-width:6px;border-radius:10px;padding:6px 20px;font:bold 34px monospace;color:#f5c542}
.foot{position:absolute;bottom:34px;left:56px;right:56px;text-align:center;font-size:22px;color:#b9ab86}
.foot b{color:#f5c542}
.ico{display:inline-block;width:62px;height:62px;border-radius:8px;border:3px solid #4a3a18;background:#2c2416;font-size:34px;line-height:56px}
.glow{border-color:#f5c542;box-shadow:0 0 14px #f5c542,inset 0 0 10px #f5c54288}
.ok{border-color:#4caf50;color:#6fe07a}
.q{color:#999}
.rank{display:flex;padding:20px 24px !important;align-items:center;gap:22px;background:#201a12;border:2px solid #4a3a18;border-radius:12px;padding:14px 24px;margin-bottom:14px}
.rank .num{width:46px;height:46px;border-radius:50%;background:#f5c542;color:#14110d;font:bold 28px/46px Georgia;text-align:center;flex:none}
.rank .e{font-size:34px;width:60px;text-align:center;flex:none}
.rank .tt{font-size:30px;color:#f5c542}
.rank .dd{font-size:22px;color:#d8cba8}
.chat{font:22px monospace;background:#0c0a07;border:2px solid #333;border-radius:8px;padding:10px 14px;color:#8ec7ff;text-align:left;margin-top:10px}
"""
def page(body, h=760): return f"<!doctype html><meta charset=utf-8><style>{CSS}body{{--h:{h}px}}</style><body>{body}</body>"

P = {}
P["1-get-started"] = page("""
<h1>WellMet: one key, many buffs</h1><div class=sub>Buffs the next nearby player who needs it.</div>
<div class=row>
 <div class=card><div class=n>1</div><div class=big>⌨️</div><div class=t>Bind a key</div><div class=d>Game menu → Key Bindings → <b>WellMet</b></div></div>
 <div class=arrow>➜</div>
 <div class=card><div class=n>2</div><div class=big>🧙‍♂️</div><div class=t>Stand near people</div><div class=d>Campfire, town, your party. Nothing to target.</div></div>
 <div class=arrow>➜</div>
 <div class=card><div class=n>3</div><div class=big><span class=key>KEY</span></div><div class=t>Press it</div><div class=d>Your buff lands on someone who lacks it.</div></div>
 <div class=arrow>➜</div>
 <div class=card><div class=n>4</div><div class=big>🔁</div><div class=t>Press again</div><div class=d>It moves on to the next person.</div></div>
</div>
<div class=foot>Works for <b>Paladin · Mage · Druid · Priest</b> &nbsp;|&nbsp; Settings: <b>/wellmet</b></div>
""", 580)

P["2-who-goes-first"] = page("""
<h1>Who gets buffed first?</h1><div class=sub>The key always picks the most useful target. Nearest first within each step.</div>
<div class=rank><div class=num>1</div><div class=e>🎯</div><div><div class=tt>Your target</div><div class=dd>Target someone yourself: they get it even if their buff has time left.</div></div></div>
<div class=rank><div class=num>2</div><div class=e>🤝</div><div><div class=tt>Whoever just buffed you</div><div class=dd>For 10 seconds after they do. Return the favour.</div></div></div>
<div class=rank><div class=num>3</div><div class=e>❌</div><div><div class=tt>Anyone missing a buff</div><div class=dd>You, then your group, then strangers nearby.</div></div></div>
<div class=rank><div class=num>4</div><div class=e>⏳</div><div><div class=tt>Buffs running out</div><div class=dd>Refreshed when 20% of their time is left (you set the %).</div></div></div>
<div class=foot>Settings → WellMet → <b>Priority</b></div>
""", 720)

P["3-extras"] = page("""
<h1>Handy extras</h1><div class=sub>All optional. Switch them on in settings.</div>
<div class=row>
 <div class=card><div class=t>Reminder icons</div>
  <div style="margin:14px 0"><span class="ico glow">⚔️</span> &nbsp;<span class="ico ok">✔</span> &nbsp;<span class="ico q">?</span></div>
  <div class=d><b style="color:#f5c542">Gold glow</b>: someone needs a buff.<br><b style="color:#6fe07a">Green check</b>: everyone covered.<br><b>?</b>: hidden in combat.</div>
  <div class=d style="margin-top:10px">Shift-drag to move.</div></div>
 <div class=card><div class=t>Buff requests</div>
  <div class=chat>[Party] Sam: !bok<br>[Party] Lee: !fort</div>
  <div class=d style="margin-top:14px">Players ask in chat, the key gives them what they asked for.</div>
  <div class=d style="margin-top:10px">Ctrl-click the minimap button to tell the group how.</div></div>
 <div class=card><div class=t>Strangers</div>
  <div class=big>🧍🧍🧍</div>
  <div class=d>Turn on <b>Others</b> to buff players outside your group. Needs friendly nameplates on.</div>
  <div class=d style="margin-top:10px">Settings → <b>Others</b></div></div>
</div>
<div class=foot>Group tools page: <b>/wellmet tools</b> &nbsp;|&nbsp; Others: <b>/wellmet others</b></div>
""", 600)

H = {'1-get-started': 580, '2-who-goes-first': 720, '3-extras': 600}
for name, html in P.items():
    f = pathlib.Path(f"{name}.html"); f.write_text(html)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size=1200,{H[name]}",
                    f"--screenshot={name}.png", f"file://{f.resolve()}"], check=True, capture_output=True)
    f.unlink()
    print("wrote", name + ".png")
