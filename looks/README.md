# Looks

One rice, several appearances. A look is the Material 3 config wearing
different clothes — it never changes the bar, the sidebars, the launcher or
the keybinds, only:

* the **wallpaper**,
* the **Material You palette**, regenerated from that wallpaper (the
  `SCHEME` picks how matugen harmonises it), and
* the **desktop clock widget**.

Adding one is two files:

```
looks/<id>/look.conf    metadata + wallpaper + matugen scheme
looks/<id>/patch.json   merged into ~/.config/illogical-impulse/config.json
```

then add `<id>` to `looks/order.conf` to place it in the menu (anything not
listed there still shows up, after the ones that are).

`patch.json` is a **patch**, not a replacement: only the keys it names are
touched, everything else in the shell config is left exactly as the user set
it. `baseline.json` is merged first and holds what every look shares.

Valid clock values, from `modules/common/Config.qml`:

| key | options |
|---|---|
| `style` | `cookie`, `digital` |
| `cookie.dialNumberStyle` | `dots`, `numbers`, `full`, `none` |
| `cookie.hourHandStyle` | `classic`, `fill`, `hollow`, `hide` |
| `cookie.minuteHandStyle` | `classic`, `thin`, `medium`, `bold`, `hide` |
| `cookie.secondHandStyle` | `dot`, `line`, `classic`, `hide` |
| `cookie.dateStyle` | `border`, `rect`, `bubble`, `hide` |

and `SCHEME` is one of `scheme-content`, `scheme-expressive`,
`scheme-fidelity`, `scheme-fruit-salad`, `scheme-monochrome`,
`scheme-neutral`, `scheme-rainbow`, `scheme-tonal-spot`.
