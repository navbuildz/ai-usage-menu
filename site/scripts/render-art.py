"""Render publication graphics from real, fixture-backed AI Usage Menu captures.

Run on the build Mac with Pillow, NumPy, Node (Sharp), and site dependencies installed.
The output is local; the production website needs none of these authoring tools.
"""
import subprocess
from functools import lru_cache
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

SITE = Path(__file__).resolve().parents[1]
ROOT = SITE.parent
CAP = ROOT / "handoff/screenshots"
OUT = SITE / "public/art"
WINDOW = CAP / "window"
W, H = 1200, 800
SAMPLE = Image.Resampling.LANCZOS
FG, MUTED, EDGE, SHELL = "#F6F7FF", "#B5B6D0", "#42415C", "#15182C"
INTER = SITE / "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2"
MONO = "/System/Library/Fonts/Menlo.ttc"


@lru_cache(maxsize=48)
def font(size, weight=550, mono=False):
    face = ImageFont.truetype(str(MONO if mono else INTER), size)
    if not mono:
        face.set_variation_by_axes([weight])
    return face


def text(canvas, xy, content, size, fill=FG, weight=550, anchor="la", mono=False):
    ImageDraw.Draw(canvas).text(xy, content, fill=fill, font=font(size, weight, mono), anchor=anchor)


def artwork(path):
    return Image.open(path).convert("RGBA")


def fit(image, width):
    return image.resize((width, round(image.height * width / image.width)), SAMPLE)


def rounded(image, radius=18):
    alpha = Image.new("L", image.size)
    ImageDraw.Draw(alpha).rounded_rectangle((0, 0, image.width-1, image.height-1), radius, fill=255)
    image = image.copy()
    image.putalpha(np_min_alpha(image.getchannel("A"), alpha))
    return image


def np_min_alpha(a, b):
    return Image.fromarray(np.minimum(np.asarray(a), np.asarray(b)))


def panel(bg, xy, item, blur=18, drop=18, opacity=.53, border=None, radius=18):
    x, y = xy
    shadow = Image.new("RGBA", bg.size)
    mask = item.getchannel("A").point(lambda n: round(n * opacity))
    shadow.paste((0,0,0,255), (x,y+drop,x+item.width,y+drop+item.height), mask)
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    bg.alpha_composite(item, xy)
    if border:
        ImageDraw.Draw(bg).rounded_rectangle((x,y,x+item.width-1,y+item.height-1),radius,outline=border,width=1)


def roundrect(size, fill, edge, radius=18):
    im = Image.new("RGBA",size)
    ImageDraw.Draw(im).rounded_rectangle((0,0,size[0]-1,size[1]-1),radius,fill=fill,outline=edge,width=2)
    return im


def guard_disk():
    # The user's later explicit approval allows this run at 12 GB of free space.
    result = subprocess.run(["df","-h","/System/Volumes/Data"],check=True,text=True,capture_output=True)
    print(result.stdout.splitlines()[-1],flush=True)
    import shutil
    if shutil.disk_usage("/System/Volumes/Data").free < 12_000_000_000:
        raise RuntimeError("Less than 12 GB free: image generation stopped.")


@lru_cache(maxsize=6)
def backdrop(light=False, aurora=False, size=(W,H)):
    w,h=size
    yy,xx=np.mgrid[0:h,0:w]
    x,y=xx/w,yy/h
    lut=([(223,227,250),(243,243,252),(228,214,247)] if light else
         [(23,24,66),(11,14,32),(58,21,76)] if aurora else
         [(24,26,46),(17,20,36),(29,30,50)])
    t=.68*x+.32*y
    arr=np.stack([np.interp(t,[0,.54,1],[p[i] for p in lut]) for i in range(3)],axis=-1)
    def glow(cx,cy,wx,wy,color,power):
        nonlocal arr
        a=power*np.exp(-(((x-cx)/wx)**2+((y-cy)/wy)**2))
        arr=arr*(1-a[...,None])+np.array(color)*a[...,None]
    if aurora:
        ridge=.72-.25*x+.08*np.cos(5*x)
        wave=np.exp(-((y-ridge)/.19)**2)
        alpha=(wave*(.24 if light else .29)*np.exp(-((x-.58)/.65)**2))[...,None]
        col=(np.array([106,112,251])*(1-x[...,None])+np.array([198,107,235])*x[...,None])
        arr=arr*(1-alpha)+col*alpha
        glow(.08,.36,.38,.42,(67,102,210),.20)
        glow(.89,.63,.29,.30,(203,115,237),.17)
    else:
        glow(.5,.45,.50,.46,(59,59,85),.26)
    return Image.fromarray(np.uint8(np.clip(arr,0,255))).convert("RGBA")


def base(*args, **kwargs):
    return backdrop(*args, **kwargs).copy()


def tile(n, width):
    return fit(artwork(CAP / "dock" / f"usage-{n}-1024.png"), width)


def gauge(n, theme, width=38):
    # Preserve the gauge pixels, including the health colors, from the app renderer.
    im=artwork(CAP / "icon" / f"menu-{n}-{theme}.png")
    a=np.asarray(im).copy()
    if theme=="dark":
        mag=a[:,:,:3].max(axis=2).astype(float)/255
        a[:,:,3]=np.round(mag*255).astype("uint8")
        for c in range(3): a[:,:,c]=np.clip(a[:,:,c]/np.maximum(mag,.0001),0,255)
    else:
        mag=1-a[:,:,:3].min(axis=2).astype(float)/255
        a[:,:,3]=np.round(mag*255).astype("uint8")
        for c in range(3): a[:,:,c]=np.clip(255-(255.-a[:,:,c])/np.maximum(mag,.0001),0,255)
    im=Image.fromarray(a)
    return fit(im.crop(im.getbbox()),width)


def menu_badge(n,theme,scale=1):
    light=theme=="light"
    im=roundrect((248,94), "#F2F1F8" if light else "#292941", "#FFFFFF" if light else "#59576F",47)
    icon=gauge(n,theme,49)
    im.alpha_composite(icon,(36,(94-icon.height)//2))
    text(im,(106,46),f"{n}%",40,fill="#171829" if light else FG,weight=680,anchor="lm")
    return fit(im,round(im.width*scale))


def hero(light):
    theme="light" if light else "dark"
    bg=base(light,True)
    w=fit(rounded(artwork(WINDOW/f"hero-{theme}.png"),18),460)
    # Reflected window glass fades into the stage below the window.
    reflection=ImageOps.flip(w).resize((w.width,59),SAMPLE)
    reflection.putalpha(Image.fromarray(np.uint8(np.asarray(reflection.getchannel("A"))*np.linspace(.13,0,59)[:,None])))
    bg.alpha_composite(reflection.filter(ImageFilter.GaussianBlur(2)),(292,105+w.height+3))
    panel(bg,(292,105),w,blur=31,drop=30,border="#E5E1EF" if light else "#49485D",radius=21)
    panel(bg,(110,87),menu_badge(94,theme,.81),blur=20,drop=12)
    icon=tile(72,294)
    panel(bg,(758,406),icon,blur=19,drop=24)
    return bg


def trio():
    bg=base(); d=ImageDraw.Draw(bg)
    d.rounded_rectangle((90,390,1110,565),radius=62,fill="#242639",outline="#45465A",width=2)
    d.line((149,393,1051,393),fill="#535266",width=2)
    for i,n in enumerate((30,72,94)):
        x=140+i*320
        im=tile(n,273)
        reflection=ImageOps.flip(im).resize((273,37),SAMPLE)
        reflection.putalpha(Image.fromarray(np.uint8(np.asarray(reflection.getchannel("A"))*np.linspace(.26,0,37)[:,None])))
        bg.alpha_composite(reflection,(x,489))
        panel(bg,(x,227),im,blur=17,drop=15)
        text(bg,(x+136,619),{30:"Healthy",72:"Near limit",94:"High usage"}[n],26,MUTED,540,anchor="mm")
    return bg


def strips(light):
    theme="light" if light else "dark"
    bg=base(light,True)
    for i,n in enumerate((30,72,94)):
        y=132+186*i; width=934
        strip=roundrect((width,107),"#ECEAF6" if light else "#25273B","#FFFFFF" if light else "#59576D",23)
        ink="#202134" if light else FG
        label={30:"Healthy",72:"Near limit",94:"High usage"}[n]
        text(strip,(35,50),label,28,ink,610,anchor="lm")
        icon=gauge(n,theme,49); strip.alpha_composite(icon,(width-185,(107-icon.height)//2))
        text(strip,(width-112,52),str(n)+"%",34,ink,670,anchor="lm")
        panel(bg,(133,y),strip,blur=17,drop=14)
    return bg


def breakdown():
    bg=base()
    shot=artwork(WINDOW/"breakdown-dark.png")
    # Keep the rank order, original period, totals and tips in one intact crop.
    card=rounded(fit(shot.crop((0,374,380,733)),652),24)
    card=card.rotate(1.4, Image.Resampling.BICUBIC,expand=True)
    panel(bg,(251,89),card,blur=26,drop=19)
    return bg


def pair():
    bg=base()
    for i,name in enumerate(("high-dark","codex-plan-dark")):
        cap=artwork(WINDOW/f"{name}.png")
        card=fit(rounded(cap.crop((0,0,cap.width,372 if i==0 else 351)),18),495)
        panel(bg,(74+i*556,172+i*34),card,blur=23,drop=18,border="#414156",radius=22)
    return bg


def terminal():
    bg=base()
    console=roundrect((514,351),"#0B0D17","#404255",16)
    lines=(ROOT/"app/Tests/Fixtures/subscription.txt").read_text().splitlines()
    d=ImageDraw.Draw(console); d.line((0,61,514,61),fill=EDGE,width=1)
    text(console,(22,18),"Claude Code",19,MUTED,620)
    text(console,(24,89),"/usage",27,FG,600,mono=True)
    for i,line in enumerate(lines[2:5]):
        a,b=line.split(": ",1)
        text(console,(24,156+59*i),a,19,MUTED,mono=True)
        text(console,(24,180+59*i),b.split(" ·")[0],20,FG,mono=True)
    panel(bg,(52,215),console,22,17)
    d=ImageDraw.Draw(bg);d.line((577,390,624,390),fill="#B5A7FF",width=3)
    d.line((612,379,625,390,612,401),fill="#B5A7FF",width=3)
    shot=artwork(WINDOW/"high-dark.png").crop((0,0,380,375))
    panel(bg,(648,147),fit(rounded(shot,15),498),22,17,border=EDGE,radius=19)
    return bg


def code():
    bg=base()
    for i,(name,path) in enumerate([
        ("Claude Code reader","app/Sources/ClaudeCodeProvider.swift"),
        ("Codex session reader","app/Sources/CodexProvider.swift"),
        ("Optional update check","app/Sources/Updater/UpdateService.swift")]):
        y=110+i*186; card=roundrect((926,145),SHELL,EDGE,21)
        text(card,(34,33),"{ }",33,"#B6A5FF",mono=True)
        text(card,(130,25),name,32,weight=655)
        text(card,(130,84),path,21,MUTED,mono=True)
        panel(bg,(135,y),card,13,10)
    return bg


def compare():
    bg=base()
    card=roundrect((942,432),SHELL,EDGE,22)
    text(card,(35,34),"AI Usage Menu",42,weight=720)
    d=ImageDraw.Draw(card)
    for i,(k,v) in enumerate([("Usage source","Local CLI and session logs"),("License","MIT"),("Displays","Menu bar and Dock"),("Price","Free")]):
        y=134+i*75;d.line((34,y-14,904,y-14),fill=EDGE,width=1)
        text(card,(35,y),k,25,MUTED);text(card,(354,y),v,25,FG,620)
    panel(bg,(129,183),card,28,20)
    return bg


def onboard():
    bg=base()
    shot=fit(rounded(artwork(WINDOW/"onboarding-dark.png"),17),698)
    panel(bg,(251,112),shot,28,22,border=EDGE,radius=25)
    return bg


def privacy():
    # Original accessible diagram. SVG is also kept as editable source.
    svg="""<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800" viewBox="0 0 1200 800" role="img" aria-labelledby="t d">
<title id="t">How AI Usage Menu reads usage on your Mac</title><desc id="d">Claude Code usage and Codex session logs feed into AI Usage Menu. No usage data is sent to the cloud.</desc>
<rect width="1200" height="800" fill="#101322"/><rect x="76" y="110" width="1048" height="570" rx="36" fill="#171a2f" stroke="#41435c" stroke-width="2"/>
<g font-family="Helvetica Neue, sans-serif" fill="#f6f7ff"><text x="126" y="190" font-size="30" font-weight="700">On your Mac</text>
<g fill="#24263e" stroke="#484966" stroke-width="2"><rect x="126" y="248" width="324" height="112" rx="20"/><rect x="126" y="403" width="324" height="112" rx="20"/><rect x="620" y="302" width="407" height="146" rx="24"/></g>
<g font-size="30" font-weight="700"><text x="154" y="294">Claude Code</text><text x="154" y="449">Codex</text><text x="652" y="367">AI Usage Menu</text></g>
<g font-size="24" fill="#b5b6d0"><text x="154" y="333">/usage output</text><text x="154" y="488">Local session logs</text><text x="652" y="409">Menu bar and Dock</text></g>
<g fill="none" stroke="#bdadff" stroke-linecap="round" stroke-linejoin="round" stroke-width="4"><path d="M450 304 H494 Q512 304 512 322 V351 Q512 375 535 375 H609 M595 363 l14 12 -14 12"/><path d="M450 459 H494 Q512 459 512 438 V398 Q512 375 535 375"/>
<path d="M151 606 c-22 0-25-29-4-35 5-25 42-24 48-2 23-3 32 32 7 36 h-12 M142 552 l66 68"/></g>
<text x="241" y="603" font-size="28" font-weight="600">Nothing sent</text></g></svg>"""
    target=OUT/"privacy.svg";target.write_text(svg)
    with TemporaryDirectory(dir=ROOT/"app/build") as tmp:
        temp=Path(tmp)/"privacy.png"
        subprocess.run(["node","--input-type=module","-e","import sharp from 'sharp'; await sharp(process.argv[1]).png().toFile(process.argv[2])",str(target),str(temp)],cwd=SITE,check=True)
        return artwork(temp)


def og(slug, lines, visual):
    im=base(False,True,(1200,630))
    logo=artwork(ROOT/"brand/02-logos/lockups/horizontal-dark-background-1020.png")
    logo=fit(logo.crop(logo.getbbox()),252); im.alpha_composite(logo,(56,53))
    if slug=="home":
        for i,n in enumerate((30,72,94)):
            panel(im,(618+i*173,262-25*i),tile(n,194),13,13)
    else:
        panel(im,(635,167),rounded(fit(visual,510),17),24,18,border=EDGE,radius=18)
    for i,line in enumerate(lines):
        text(im,(55,224+i*67),line,55,weight=760)
    text(im,(58,540),"aiusagemenu.com",25,MUTED,545)
    return im


def reset_timeline():
    # Use the two exact source reset entries from the real anonymized CLI fixture.
    lines=(ROOT/"app/Tests/Fixtures/subscription.txt").read_text().splitlines()
    bg=base()
    card=roundrect((984,500),SHELL,EDGE,25)
    text(card,(48,45),"Two reset windows",48,weight=715)
    for i,l in enumerate(lines[2:4]):
        title,rate=l.split(": ",1)
        reset=rate.split(" · resets ",1)[1].split(" (",1)[0]
        y=180+i*146
        ImageDraw.Draw(card).ellipse((52,y+13,70,y+31),fill="#BD9CFF")
        if i==0:
            ImageDraw.Draw(card).line((61,y+40,61,y+147),fill=EDGE,width=3)
        text(card,(94,y),title,31,weight=650)
        text(card,(94,y+51),reset+" PT",27,MUTED,570)
    panel(bg,(108,150),card,18,14)
    return bg


def phone_composition(name, image):
    # At narrow widths preserve a legible close-up instead of reducing the whole desktop stage.
    if name.startswith("hero-"):
        light=name=="hero-light"
        phone=base(light,True,(480,320))
        theme="light" if light else "dark"
        shown=artwork(WINDOW/f"hero-{theme}.png").crop((0,0,390,387))
        frame=fit(rounded(shown,15),296)
        panel(phone,(24,40),frame,blur=11,drop=8)
        dock=tile(72,124)
        panel(phone,(335,166),dock,blur=8,drop=7)
        panel(phone,(333,51),menu_badge(94,theme,.51),blur=7,drop=6)
        return phone.convert("RGB")
    # The tall ranking capture uses a tight crop of the actual period and ranked rows.
    if name=="breakdown":
        phone=base(False,False,(480,320))
        shot=artwork(WINDOW/"breakdown-dark.png").crop((0,385,380,732))
        panel(phone,(59,4),fit(rounded(shot,10),354),blur=11,drop=9)
        return phone.convert("RGB")
    if name=="pair":
        phone=base(False,False,(480,320))
        for i,n in enumerate(("high-dark","codex-plan-dark")):
            shot=artwork(WINDOW/f"{n}.png").crop((0,0,380,337))
            panel(phone,(8+235*i,51+i*16),fit(rounded(shot,11),229),blur=8,drop=8)
        return phone.convert("RGB")
    if name in ("trio","strips-dark","strips-light","privacy","code","compare","terminal","onboarding"):
        bounds={"trio":(72,74,1128,778),"strips-dark":(70,40,1132,748),
                "strips-light":(70,40,1132,748),"privacy":(44,28,1154,768),
                "code":(79,52,1123,748),"compare":(87,60,1113,744),
                "terminal":(24,16,1176,784),"onboarding":(160,104,1048,696)}
        return image.crop(bounds[name]).resize((480,320),SAMPLE)
    return fit(image,480)


def write_set(name, im):
    guard_disk()
    im=im.convert("RGB")
    for w in (480,800,1200):
        small=phone_composition(name,im) if w==480 else fit(im,w) if w==800 else im
        stem=name if w==1200 else f"{name}-{w}"
        small.save(OUT/f"{stem}.avif",quality=71,speed=8)
        small.save(OUT/f"{stem}.webp",quality=83,method=4)
        small.save(OUT/f"{stem}.png",compress_level=7)


def main():
    guard_disk()
    OUT.mkdir(parents=True,exist_ok=True)
    guards={"hero-dark":lambda:hero(False),"hero-light":lambda:hero(True),
            "trio":trio,"strips-dark":lambda:strips(False),"strips-light":lambda:strips(True),
            "breakdown":breakdown,"pair":pair,"terminal":terminal,"code":code,"compare":compare,
            "onboarding":onboard,"privacy":privacy}
    for name,render in guards.items():
        print("Rendering",name,flush=True);write_set(name,render())
    cards=[
        ("home",["Know your AI usage.","Stay in control."],"trio"),
        ("claude-code-usage",["Claude Code usage","on your Mac."],"high-dark"),
        ("codex-usage",["Codex usage,","at a glance."],"codex-plan-dark"),
        ("claude-usage-limits",["Claude usage limits,","explained."],"timeline"),
        ("open-source",["Open source, MIT.","Read every line."],"code"),
        ("privacy",["Nothing to paste.","Nothing leaves","your Mac."],"privacy"),
        ("compare",["Mac usage trackers,","compared."],"compare"),
        ("download",["Download","AI Usage Menu."],"onboarding")]
    for slug,lines,source in cards:
        guard_disk()
        path=OUT/f"{source}.png"
        visual=reset_timeline() if source=="timeline" else artwork(path if path.exists() else WINDOW/f"{source}.png")
        if source in ("high-dark","codex-plan-dark"):
            visual=visual.crop((0,0,visual.width,353))
        og(slug,lines,visual).convert("RGB").save(OUT/f"og-{slug}.png",compress_level=7)


if __name__=="__main__":
    main()
