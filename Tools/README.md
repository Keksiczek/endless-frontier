# Tools

Small one-shot scripts that produce something checked into the repo.

## MakeAppIcon.swift

Draws `App/Assets.xcassets/AppIcon.appiconset/appicon-1024.png` — the icon in
the game's own direction: deep slate night, bone hairlines, one amber lantern,
a settlement seen from the dark. The same gabled silhouette
`SettlementStructures` draws on the canvas, so the icon is the game rather than
a picture of a house.

```bash
swift Tools/MakeAppIcon.swift App/Assets.xcassets/AppIcon.appiconset/appicon-1024.png
```

`appicon-1024-previous.png` is the icon this replaced (a house under a rocket),
kept so the change is one `cp` to undo.
