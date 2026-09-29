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
data loads. Every hue holds at least 3:1 on #ffffff, #f5f5f5, #0a0a0a and
#171717 (`test/chart_palette_test.dart`); other surfaces are not covered. A
series still gets its name next to it (legend or label), never the colour alone.
Text drawn on a series colour (pie slice values) is black or white, whichever
contrasts more.

## Spacing

Use a step of `Spacing` (4, 6, 8, 12, 16, 24 as `xxs` to `xl`) instead of a
literal. `Spacing.inset` is 12 all round; scrollables use
`Spacing.listPadding(context)` (see Lists).

## Lists

Rows that belong together sit on one rounded surface on the page, separated by an
inset hairline. A long list must stay lazily built, so the surface is not one
widget around all rows: each row draws its slice (`GroupedListTile` with a
`SlicePosition`). Build lists through `SectionedListView`, which computes the
positions, headers, keys and index lookup; do not compute them by hand.

- `SectionedListView(sections: [ListSection<T>(id: ..., title: ..., items: ...,
  keyOf: ..., itemBuilder: (context, item, position) => ...)])`. Write the type
  argument on `ListSection`, or the closures are inferred as `Object?`.
- `id` must be unique among the sections and stable: rows are keyed by
  `(section id, item key)`, so an id taken from the index or the title would
  re-key every later row when a section comes or goes.
- `keyOf` must be unique within its section and name the item, not its index.
  Gateways use the hostname because `coreId` is empty for manually added ones.
  A repeated row key from real data (a gateway paired twice) is told apart by
  its occurrence and logged; a duplicate section id is a bug and throws in debug.
- A header is shown only for a section with a `title` that has rows; positions
  count the rows actually shown, so a hidden last row keeps the rounded bottom.
- `leading` and `trailing` take unkeyed extras such as a page header or the 72px
  gap that keeps the last row clear of a FAB.
- The row builder wraps its content in `GroupedListTile(position: position, ...)`
  and picks the hairline inset so it starts at the title: `insetNoLeading` (16),
  `insetIconLeading` (56, 24px icon), `insetIconLeading40` (64, the 40px leading icon of
  device and group rows), `insetButtonLeading` (80, 48px interactive leading).
- Padding defaults to `Spacing.listPadding(context)`. An explicit `padding`
  switches off ListView's own system-inset padding, and the app draws edge to
  edge (target SDK 36), so the helper adds the bottom system inset; on the main
  tabs the Scaffold has already removed it and the helper yields 12.
- Settings sections build their rows through `SettingsSection.of(title, rows)`
  and hand them over with `toListSection()`.
- The reorder page is the exception: `ReorderableListView` needs its own keyed
  children.

### Paged device lists

Device lists that page through the device search use `PagedDeviceList` with a
`DeviceSearchPages(AppState())` source instead of calling `loadDevices()` from
the item builder. It shows the spinner while loading, `emptyText` only once the
source has ended, and otherwise the sections plus an invisible next-page row that
requests one page when it is created. The row is keyed by a token the device
mixin advances after every load, so a page that adds no visible row (all devices
inactive) still leads to the next request, rebuilds of the same state do not, and
a failed page ends the list until the next search. `untilEnded: true` keeps asking
until the source reports the end, for the location page. The sensor picker and
group editing keep their own paging.
