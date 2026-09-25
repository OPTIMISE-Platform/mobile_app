# Theme and lists

Which colour role, spacing step and list building block a widget should use, and
the rules they depend on.

## Scope

Covers `lib/theme.dart` (the two `ThemeData`, `AppColors`, `Spacing`,
`MyTheme.getSomeColor`) and the grouped-list widgets in `lib/widgets/shared/`
(`GroupedListTile`, `SlicePosition`, `SectionListHeader`) plus
`lib/widgets/settings/settings_section.dart`. Not about the smart service widgets
under `lib/widgets/tabs/dashboard/smart_service_widgets/`, which are configured
by the server and only take the chart palette from here.

## Colours

Surfaces are achromatic; colour means something (brand control, error, warning).
The colour scheme is written by hand, not derived with `ColorScheme.fromSeed`.

### Fill or ink

The brand turquoise `#32b8ba` reads only 2.4:1 on white. It is a **fill** with
dark content on top, never text on a light surface. For text, icons, thin lines
and indicators on the page use the **ink**:

| Need | Read |
|---|---|
| Brand fill with content on it (FAB, filled button, selected chip) | `colorScheme.primaryContainer` / `context.appColors.app`, content `onPrimaryContainer` (black) |
| Brand colour as text, icon, line, indicator on a surface | `colorScheme.primary` / `context.appColors.appInk` |
| Warning icon or text on a surface | `context.appColors.warnInk` |
| Warning as a background (swipe to delete) | `context.appColors.warn`, content black |
| Error | `colorScheme.error` / `context.appColors.error` |

In the light theme `primary` is the ink `#007c7c` because Material's default
widgets (tabs, text buttons, checkboxes, switches) paint `primary` as text. In
the dark theme fill and ink are both `#32b8ba`. `MyTheme.appColor` is the static
fill for code that runs without a `BuildContext`.

### Outline and outlineVariant

`outline` (`#8a8a8a` light, `#7a7a7a` dark) is the boundary of a control: switch
off-state, outlined buttons and inputs. It reaches 3:1 and must not be used for
dividers. Faint lines (dividers, card borders, list hairlines) use
`outlineVariant`.

### Surfaces

| Layer | Light | Dark | Role |
|---|---|---|---|
| Page | `#f5f5f5` | `#0a0a0a` | `surface`, scaffold |
| Bars, cards, dialogs, sheets, list surfaces | white | `#171717` | `surfaceContainerLow` |
| Muted controls (switch track, chips) | `#ebebeb` | `#262626` | `surfaceContainerHigh`/`Highest` |

App bar, navigation bar and header strips directly under the app bar share the
card tone; a hairline sits under the whole header and above the navigation bar.

### Chart series

`MyTheme.getSomeColor(i)` rotates through six hues checked for colour-vision
deficiency. One set serves both themes because series colours are assigned while
data loads. Green, gold and pink stay under 3:1 on white, so a series needs its
name next to it (legend or label), never the colour alone.

## Spacing

Use a step of `Spacing` (4, 6, 8, 12, 16, 24 as `xxs` to `xl`) instead of a
literal. `Spacing.inset` is 12 all round; scrollables use
`Spacing.listPadding(context)` (see Lists).

## Lists

Rows that belong together sit on one rounded surface on the page, separated by an
inset hairline. A long list must stay lazily built, so the surface is not one
widget around all rows: each row draws its slice.

- Wrap the row in `GroupedListTile(position: SlicePosition.forIndex(i, count), child: ...)`.
  `count` is the number of rows **in that section as shown**, not the builder's
  `itemCount` (which may include headers, fillers or a loading row).
- Pick the hairline inset so it starts at the title: `insetNoLeading` (16),
  `insetIconLeading` (56, 24px icon), `insetButtonLeading` (80, 48px interactive
  leading such as the favourite star; the default).
- Give the `ListView` `padding: Spacing.listPadding(context)`; `GroupedListTile`
  adds the 16px side margin. An explicit `padding` switches off ListView's own
  system-inset padding, and the app draws edge to edge (target SDK 36), so the
  helper adds the bottom system inset; on the main tabs the Scaffold has already
  removed it and the helper yields 12.
- `SectionListHeader(title)` goes above a section's first row.
- Settings sections build their rows through `SettingsSection.of(title, rows)`,
  which computes positions from the rows actually produced, so a conditionally
  hidden last row keeps the surface's rounded bottom.

### Keys

Any list whose rows can be added, removed, reordered or shifted by a header must
key each row by its item's id and pass a `findChildIndexCallback` that returns
the index in the current build. Without it, `ListView.builder` matches rows by
position and hands a row's state (expanded, transitioning, probing) to the item
that moved into its slot. The key must be unique among siblings: gateways are
keyed by hostname because `coreId` is empty for manually added ones, and an
index suffix is no identity because it changes below every insertion.
