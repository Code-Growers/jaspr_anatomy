/// Styles of the overlay. They live in a shadow root, so they neither leak
/// into the page nor pick up the page's own styles.
const String overlayCss = '''
:host { all: initial; }
* { box-sizing: border-box; }
.root { font: 12px/1.4 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; color: #e7eaf0; }

/* Outlines over the page */
.flat { position: absolute; left: 0; top: 0; width: 0; height: 0; pointer-events: none; }
.box { position: absolute; border: 1px solid hsl(var(--h) 85% 55% / .9); border-radius: 2px; }
.tag { position: absolute; left: calc(-1px + var(--dx, 0px)); bottom: 100%; padding: 0 4px; font-size: 10px;
  line-height: 14px; white-space: nowrap; color: #fff; background: hsl(var(--h) 70% 36%);
  border-radius: 3px 3px 3px 0; }
/* No room above the box: the label goes inside it. */
.box.inside > .tag { bottom: auto; top: -1px; border-radius: 2px 0 3px 0; }
.box.small > .tag { display: none; }
.flat.focused .box { opacity: .22; }
.flat.focused .box.same { opacity: 1; background: hsl(var(--h) 85% 55% / .14); }
.flat.focused .box.on { opacity: 1; border-width: 2px; background: hsl(var(--h) 85% 55% / .24); }
.flat.focused .box.on > .tag, .flat.focused .box.same > .tag { display: block; z-index: 1; }
.flat.finding .box { opacity: .12; }
.box.sel { opacity: 1 !important; box-shadow: 0 0 0 2px #fff, 0 0 0 4px hsl(var(--h) 85% 50%); }
.mark { position: absolute; border: 2px dashed #ff5d5d; background: rgb(255 93 93 / .14); border-radius: 3px; }
.mark.ok { border-color: #37c978; background: rgb(55 201 120 / .14); }
.picking-shield { position: fixed; inset: 0; cursor: crosshair; pointer-events: auto; }

/* Layers */
.stage { position: fixed; inset: 0 340px 0 0; background: radial-gradient(circle at 50% 40%, #1b2130, #0b0e14);
  overflow: hidden; perspective: 2600px; pointer-events: auto; cursor: grab; user-select: none;
  touch-action: none; }
.stage.left { inset: 0 0 0 340px; }
.stage.wide { inset: 0; }
.stage.dragging { cursor: grabbing; }
.world { position: absolute; left: 0; top: 0; transform-style: preserve-3d; --sep: 64px; --zoom: 1; }
.page { position: absolute; left: 0; top: 0; background: rgb(255 255 255 / .06);
  outline: 2px solid rgb(255 255 255 / .28); }
/* Each plane is a tinted sheet: dark enough to read as a surface, clear
   enough to see the sheets below through it. */
.plane { position: absolute; transform: translateZ(calc(var(--sep) * var(--d)));
  background: hsl(var(--h) 55% 30% / .5); border: 2px solid hsl(var(--h) 90% 66%); border-radius: 3px;
  transition: opacity .12s; }
/* Labels keep their size on screen however far the camera zooms. */
.plane > .tag { left: -2px; bottom: 100%; font-size: 11px; line-height: 15px; transform-origin: 0 100%;
  transform: scale(calc(1 / var(--zoom))); }
.plane:hover { background: hsl(var(--h) 65% 42% / .7); }
.world.focused .plane { opacity: .38; }
.world.focused .plane.same { opacity: 1; background: hsl(var(--h) 70% 45% / .75); }
.world.focused .plane.on { opacity: 1; background: hsl(var(--h) 75% 50% / .85); border-color: #fff; }
.plane.sel { opacity: 1 !important; border-color: #fff; }
.hint { position: absolute; left: 14px; bottom: 10px; color: #8b95a7; pointer-events: none; }
/* Layers that carry a copy of the page: the tint would hide it. */
.skin { position: absolute; left: 0; top: 0; width: 0; height: 0; pointer-events: none; }
.world.skinned .plane { background: transparent; border: 1px solid hsl(var(--h) 90% 66% / .6); }
/* Names would cover the page; they appear for what the pointer is on. */
.world.skinned .plane > .tag { display: none; }
.world.skinned .plane:hover > .tag, .world.skinned .plane.on > .tag, .world.skinned .plane.same > .tag,
.world.skinned .plane.sel > .tag { display: block; }
.world.skinned .plane:hover { background: hsl(var(--h) 80% 55% / .14); border-width: 2px; }
.world.skinned.focused .plane { opacity: .3; }
.world.skinned.focused .plane.same { opacity: 1; background: hsl(var(--h) 80% 55% / .16); }
.world.skinned.focused .plane.on { opacity: 1; background: hsl(var(--h) 80% 55% / .22); border-color: #fff; }

/* Panel */
.panel { position: fixed; top: 0; right: 0; bottom: 0; width: 340px; display: flex; flex-direction: column;
  background: #151920; border-left: 1px solid #2a303b; pointer-events: auto;
  box-shadow: -8px 0 24px rgb(0 0 0 / .28); }
.panel.left { right: auto; left: 0; border-left: 0; border-right: 1px solid #2a303b;
  box-shadow: 8px 0 24px rgb(0 0 0 / .28); }
button.icon { padding: 3px 6px; min-width: 24px; }
.bar { display: flex; align-items: center; gap: 6px; padding: 7px 10px; border-bottom: 1px solid #232a35; }
.bar.wrap { flex-wrap: wrap; }
.title { font-weight: 600; font-size: 13px; margin-right: auto; }
.label { color: #8b95a7; white-space: nowrap; }
button { font: inherit; color: inherit; background: #222834; border: 1px solid #323a48; border-radius: 6px;
  padding: 3px 8px; cursor: pointer; white-space: nowrap; }
button:hover { background: #2b3342; }
button.active { background: #2f6feb; border-color: #2f6feb; color: #fff; }
button.danger:hover { background: #7a2630; border-color: #a33442; }
.seg { display: inline-flex; }
.seg button { border-radius: 0; margin-left: -1px; }
.seg button:first-child { border-radius: 6px 0 0 6px; margin-left: 0; }
.seg button:last-child { border-radius: 0 6px 6px 0; }
input[type=search] { flex: 1; min-width: 0; font: inherit; color: inherit; background: #0f1319;
  border: 1px solid #323a48; border-radius: 6px; padding: 4px 8px; outline: none; }
input[type=search]:focus { border-color: #2f6feb; }
input[type=range] { flex: 1; min-width: 60px; accent-color: #2f6feb; }
.tabs { display: flex; border-bottom: 1px solid #232a35; }
.tabs button { flex: 1; border: 0; border-bottom: 2px solid transparent; border-radius: 0; background: none;
  padding: 7px 4px; color: #a9b2c2; }
.tabs button.active { background: none; border-bottom-color: #2f6feb; color: #fff; }
.body { flex: 1; overflow: auto; padding: 6px 0; min-height: 80px; }
.row { display: flex; align-items: center; gap: 6px; padding: 2px 10px; cursor: pointer; white-space: nowrap; }
.row:hover, .row.on { background: #222834; }
.row.sel { background: #25324b; }
.row.same .name { color: #fff; font-weight: 600; }
.sw { width: 8px; height: 8px; border-radius: 2px; background: hsl(var(--h) 85% 55%); flex: none; }
.name { overflow: hidden; text-overflow: ellipsis; }
.dim { color: #8b95a7; }
.pill { font-size: 10px; padding: 0 5px; border-radius: 999px; background: #2a3342; color: #b9c3d6; flex: none; }
.count { margin-left: auto; color: #8b95a7; font-variant-numeric: tabular-nums; flex: none; }
.section { padding: 8px 10px 4px; color: #8b95a7; text-transform: uppercase; font-size: 10px; letter-spacing: .06em; }
.note { padding: 4px 10px 8px; color: #a9b2c2; white-space: normal; }
.finding { padding: 7px 10px; cursor: pointer; white-space: normal; border-bottom: 1px solid #1d232c; }
.finding:hover { background: #1c212b; }
.finding.sel { background: #25324b; }
.finding .kind { display: inline-block; font-size: 10px; padding: 0 6px; border-radius: 999px; margin-bottom: 3px; }
.kind.duplicatesComponent { background: #5a2330; color: #ffb3bf; }
.kind.twinComponents { background: #4a3a17; color: #ffd98a; }
.kind.repeatedInline { background: #1f3a5c; color: #a9d0ff; }
code { font: 11px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; color: #c9d4e6; }
.details { border-top: 1px solid #2a303b; padding: 8px 10px; max-height: 36%; overflow: auto; flex: none; }
.details h4 { margin: 0 0 4px; font-size: 13px; font-weight: 600; display: flex; align-items: center; gap: 6px;
  flex-wrap: wrap; }
.details p { margin: 2px 0; color: #a9b2c2; }
a { color: #7fb0ff; text-decoration: none; cursor: pointer; }
a:hover { text-decoration: underline; }
.foot { display: flex; gap: 6px; align-items: center; padding: 7px 10px; border-top: 1px solid #232a35; flex: none; }
.foot .label { margin-left: auto; overflow: hidden; text-overflow: ellipsis; }
.reopen.left { right: auto; left: 12px; }
.reopen { position: fixed; right: 12px; bottom: 12px; pointer-events: auto; background: #151920; color: #e7eaf0;
  border: 1px solid #323a48; border-radius: 999px; padding: 6px 12px; box-shadow: 0 4px 14px rgb(0 0 0 / .3); }
''';
