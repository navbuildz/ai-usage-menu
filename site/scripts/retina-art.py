"""Encode crops from the opt-in RECORD_SITE AppKit capture tests."""
from pathlib import Path
from PIL import Image
import runpy

project = Path(__file__).resolve().parents[2]
source = project / 'handoff/screenshots/site-retina'
dest = project / 'site/public/art/retina'
dest.mkdir(exist_ok=True)
tools = runpy.run_path(str(project / 'site/scripts/render-art.py'))
tools['guard_disk']()
def save(name, image):
    for ext, options in [('avif', {'quality':80,'speed':8}), ('webp',{'quality':86}), ('png', {'compress_level':8})]:
        image.save(dest/f'{name}.{ext}', **options)
for theme in ('light','dark'):
    for name, filename, bounds in [
        ('hero','hero',None),('mobile','normal',(0,0,760,752)),
        ('activity','breakdown',(0,755,760,1465)),
        ('claude','normal',(0,0,760,590)),('codex','codex-plan',(0,0,760,640))]:
        shot=Image.open(source/f'{filename}-{theme}@2x.png').convert('RGB')
        save(f'{name}-{theme}',shot.crop(bounds) if bounds else shot)
    for value in (30,72,94):
        save(f'menu-{value}-{theme}',tools['gauge'](value,theme,36))
frames=[Image.open(source/f'dock-frame-{i}.png').convert('RGBA') for i in range(19)]
sheet=Image.new('RGBA',(192*len(frames),192))
for i,frame in enumerate(frames):sheet.paste(frame,(i*192,0))
sheet.save(dest/'dock-sequence.webp',quality=89)
for n in [30,72,94]:
    save(f'dock-{n}', Image.open(project/f'handoff/screenshots/dock/usage-{n}-1024.png').resize((224,224),Image.Resampling.LANCZOS))
