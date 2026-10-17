# Theming

Every color, size and font in the client comes from **design tokens**. A theme is a small
JSON file that sets token values; it contains no CSS, no scripts and no layout. The design
system (canvas "Showdown Desktop", Mono direction) defines the tokens; this page describes
how the client uses them.

## Built-in themes

| id | Name | Notes |
|---|---|---|
| `midnight-dark` | Midnight Dark | Default. Defines **every** token (the schema). |
| `classic-light` | Classic Light | `extends: midnight-dark`, overrides surfaces, text, accent… |
| `high-contrast` | High Contrast | `extends: midnight-dark`, 2px borders, no shadows, yellow focus ring |

Files: `client/assets/themes/<id>.sdtheme.json`.

## Writing a community theme

Put `<id>.sdtheme.json` into the user themes folder
(Linux: `~/.local/share/godot/app_userdata/Showdown Desktop/themes/`) and pick it in the
theme gallery or in settings.

```json
{
  "format": 1,
  "name": "Sandstorm",
  "author": "your name",
  "extends": "midnight-dark",
  "tokens": {
    "color.surface.app": "#15120E",
    "color.surface.panel": "#1D1914",
    "color.text.primary": "#E8DCCB",
    "color.accent.default": "#9A5716",
    "color.text.on-accent": "#FFFFFF",
    "color.focus.ring": "#F2B45A"
  }
}
```

- `extends` names any theme; missing keys come from it (chains allowed, max depth 8).
- Colors are `#RRGGBB` or `#RRGGBBAA`. Numbers are plain numbers (px, seconds, 0–1 for `mix.*`).
- `font.family.ui` / `font.family.mono` may name the bundled Atkinson Hyperlegible fonts or any
  installed system font.

### Validation (why themes need no sandbox)

A theme is data only. On load the client:

- rejects files over 64 KB, invalid JSON or an unknown `format`
- ignores unknown keys, values of the wrong type and numbers out of range (with a warning)
- checks WCAG contrast for text and control pairs (e.g. `color.text.primary` on
  `color.surface.panel` ≥ 4.5:1, type and status badge ink ≥ 4.5:1) and lists failures as warnings
- never loads files, scripts or URLs named in a theme

Warnings are shown in the theme gallery and in the log. A broken theme can make the client look
odd but never break it.

## Token reference

The full list with values is `client/assets/themes/midnight-dark.sdtheme.json`. Groups:

| Group | Keys |
|---|---|
| Surfaces | `color.surface.{app,panel,raised,sunken,overlay,hover,pressed,selected}`, `color.field.{bg,ground,line}` |
| Borders | `color.border.{subtle,default,strong,control}`, `border.width.{default,focus}` |
| Text | `color.text.{primary,secondary,muted,disabled,inverse,on-accent,on-danger}` |
| Accent | `color.accent.{default,hover,pressed,subtle,text}`, `color.focus.ring` |
| Feedback | `color.{danger,success,warning,plugin}.*` |
| Battle | `color.hp.{high,mid,low,track,outline}`, `color.boost.{up,down}.{bg,fg}`, `mix.type.tint` |
| Types / status | `color.type.<type>.{bg,fg}` (18 types), `color.status.<brn,par,slp,frz,psn,tox>.{bg,fg}`, `color.badge.border` |
| Type & sizes | `font.family.{ui,mono}`, `font.size.{xs,sm,md,lg,xl,2xl}` |
| Layout | `space.{xs,sm,md,lg,xl,2xl,3xl}` (4px grid), `radius.{sm,md,lg,full}` |
| Elevation | `shadow.{sm,md,lg}.{offset,size,color}` |
| Motion | `motion.{instant,fast,base,slow}` (s), `motion.hp.{base,per-percent,max}`, `delay.tooltip.{show,hide,neighbor}`, `toast.lifetime.{info,action}`, `toast.max` |

## Using the theme in code

Screens and components never hard-code colors. They pick a **theme type variation**:

| Variation | Base | Use |
|---|---|---|
| `PrimaryButton`, `GhostButton`, `DangerButton`, `SmallButton`, `IconButton`, `SlotButton` | Button | Button styles (default Button = secondary) |
| `MoveButton_<type>` | Button | Move buttons tinted by type (`MoveButton` component) |
| `AppBackground`, `RaisedPanel`, `SunkenPanel`, `OverlayPanel`, `FieldPanel`, `FlatPanel` | PanelContainer | Surfaces |
| `SecondaryLabel`, `MutedLabel`, `CapsLabel`, `HeadingLabel`, `TitleLabel`, `DisplayLabel`, `MonoLabel`, `MonoSmallLabel`, `DangerLabel`, `SuccessLabel`, `WarningLabel`, `PluginLabel` | Label | Typography |
| `TypeBadge_<type>`, `StatusBadge_<code>`, `BoostUpChip`, `BoostDownChip`, `VolatileChip`, `FieldChip`, `PluginBadge`, `KbdLabel` | Label | Badges and chips (prefer the components) |
| `AppHeader`, `DockPanel`, `DockHeader`, `BattleHeader`, `HudCard`, `ChoicePanel`, `FieldChipPanel`, `FieldChipSmallPanel`, `MiniSprite`, `LogPanel`, `LogTurnPanel`, `WaitingBanner` | PanelContainer | Battle screen surfaces |

Components in `src/ui/components/`: `HPBar` (animated), `TypeBadge`, `StatusBadge`, `BoostChip`, `MoveButton`,
`IconView`, `DockPanel`, `ConditionChip`, `TeamStrip`, `PokemonSlot`, `HudCard`, `BattleStage`, `BattleLogView`.
For custom drawing, read a token: `Themes.color("color.hp.high")` (plugins: `api.get_token(key)`).

Keep a Control (or Window) chain from the root to every screen: Godot passes the theme down only
through Control/Window parents.

## Icons

37 hand-drawn icons from the design system in `client/assets/icons/` (free to use in this
project; no third-party icon set): `weather-*`, `terrain-*`, `hazard-*`, `screen-*` for field
conditions and `ui-*` for the interface.

- 16px grid, 1.5px stroke, drawn **white** so the theme can tint them.
- Imported at 2x (`svg/scale=2.0` in the `.import` files) and shown at 16 logical px, so they stay
  sharp up to 200 % UI scale. Keep that setting when adding icons.
- In buttons: `button.icon = Icons.get_icon("ui-import")`; the theme's icon colors tint it.
- Elsewhere: `IconView.new("weather-rain", "color.text.secondary")` (tinted by a token).
- Design rule: every icon is paired with a text label or a tooltip, never color alone.
- `LineEdit.right_icon` draws icons untinted at texture size; don't use it with these icons.

## Switching and scaling

- `Themes.apply(id)` rebuilds the Godot theme and applies it to the window at runtime.
- `Themes.set_ui_scale(0.75 … 1.5)` scales the whole UI; fonts are re-rendered sharp.
- Both are saved in `settings.cfg` (section `appearance`).
- Command line for one run: `--theme=classic-light --ui-scale=1.25`.
- Events: `EventBus.theme_changed(id)`, `EventBus.ui_scale_changed(scale)`.
- Motion: `Themes.motion("motion.base")`, `Themes.fade(...)`, `Themes.hp_duration(delta_percent)`.
  Easing: standard = `Tween.TRANS_CUBIC` + `EASE_OUT`, exit = `EASE_IN`, linear for timers.
  **Reduce motion** (`--reduce-motion`, setting `appearance/reduce_motion`): moves become
  instant, fades are capped at 80 ms, HP bars jump to the new value.

## Reviewing themes

The **theme gallery** shows every component in every state with a live theme switcher and scale
slider: button "Theme gallery" in the dev console, or `--screen=theme-gallery`.

Render it to a PNG (needs a display, not `--headless`). Screenshots render into an offscreen
viewport of exactly `--screenshot-size` (default `1280x800`), so the window manager can't change it:

```bash
godot --path client -- --screen=theme-gallery --theme=high-contrast --screenshot=/tmp/hc.png
```

During a live battle (with `tools/local_server.sh` running): add `--server=local --search=gen9randombattle
--screenshot-turn=3 --quit-after-screenshot`.
