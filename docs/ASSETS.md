# Asset provenance

What is in `assets/`, where it came from, and what that means for distributing
this repository.

---

## Summary

| Asset | Used for | Source | Redistributable? |
|---|---|---|---|
| `assets/icons/` (142 PNG) | Card art | Sci-Fi Skill Icon Pack — commercial purchase | **No — see below** |
| `assets/portraits/` (4 PNG) | Enemy portraits | Sci-Fi Character Icons — commercial purchase | **No — see below** |
| `assets/fonts/Exo-*.ttf` | All UI type | [Exo](https://fonts.google.com/specimen/Exo) by Natanael Gama | Yes — SIL Open Font License 1.1 |

## The licensing problem

The two icon packs were bought from an asset marketplace and **ship no licence
file**. Marketplace licences of this kind almost always permit use *inside* a
released game while prohibiting redistribution of the source art — and a public
git repository redistributes it.

**Therefore: this repository should stay private** unless the purchased packs are
removed or their licences are checked and found to permit redistribution.

If the repository ever needs to be public, either:

1. Remove `assets/icons/` and `assets/portraits/` from git history, add them to
   `.gitignore`, and document how a developer supplies their own; or
2. Replace them with assets under a permissive licence (CC0, CC-BY); or
3. Confirm in writing that the purchased licence allows source redistribution.

Option 1 is the usual answer. Note that deleting the files in a new commit is
**not** sufficient — they remain in history and must be stripped with
`git filter-repo` or equivalent.

## Fonts

`Exo` is licensed under the SIL Open Font License 1.1, which permits bundling and
redistribution provided the licence travels with it. The full licence text is at
[`assets/fonts/OFL.txt`](../assets/fonts/OFL.txt).

Attribution: **Exo** designed by Natanael Gama.

## Card icon convention

Icon colour is keyed to card kind so a hand reads as shapes before it reads as
words:

| Colour | Card kind |
|---|---|
| Red | attack |
| Cyan/blue | tech |
| Green | manoeuvre |
| Violet | status (drawback cards) |

Assignments live in the `icon` field of `content/cards.json` and can be retuned
without touching code.

## Assets deliberately not used

The purchased **cyberpunk HUD panel** set was evaluated and rejected. Those
panels are fixed-shape with an asymmetric notch cut into one edge, so stretching
them to arbitrary panel sizes mangles the artwork and 9-slicing cannot preserve
the notch. UI panels are Godot `StyleBoxFlat` matched to the same cyan palette
instead. Using that specific angular look would need purpose-cut 9-slice frames
rather than the shipped PNGs.
