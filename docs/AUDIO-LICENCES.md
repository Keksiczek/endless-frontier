# Audio, and where it comes from

Everything the game makes a noise with is one of two things, and they are kept
apart on purpose.

## 1. Generated — no files, no licence

Wind, rain, crickets, the murmur of the village, fire, and the five stings
(hammer, bell, horn, chime, knell) are **synthesised at run time** by
`App/Sources/Audio/AudioEngine.swift`. Nothing is recorded, nothing is
downloaded, and there is no third-party right anywhere in it. Adding a voice
means writing a few lines of DSP, not clearing a sample.

## 2. Music — files, and therefore licences

A melody is the one thing a generator does badly, so the music is real audio.
**Every track needs a row in the table below before it ships.** A file with no
row is a file that cannot go in a build — an unlicensed track is a problem for
the App Store listing, not for whoever uploaded it.

| File | Title | Author | Source | Licence | Attribution required |
|---|---|---|---|---|---|
| `App/Resources/Audio/ambiment.m4a` | Ambiment | **TBD** | **TBD** | **TBD** | **TBD** |

> **`ambiment.m4a` is not cleared yet.** It was handed over as
> `Ambiment.mp3` on 2026-08-17 and transcoded (see below); who wrote it, where
> it came from and under what terms are unknown to this repository. Fill the row
> in before any build leaves the machine, and if the licence turns out to
> require credit, add it to Settings as well as here.

### What is safe to add

Freesound (filtered to **CC0**), OpenGameArt, Incompetech (Kevin MacLeod,
**CC-BY** — the attribution is an obligation, not a courtesy), Free Music
Archive, and paid libraries whose terms are written down. Not safe: anything
pulled off YouTube. Downloading it breaks their terms whatever the video claims,
and "royalty free" aggregator channels re-upload tracks they do not hold.

### Transcoding

Source files arrive fat — the first track was 52 MB of 320 kbps MP3 for
twenty-three minutes. The bundle carries AAC at 96 kbps, which is 16 MB and
indistinguishable for an ambient pad:

```bash
afconvert -f m4af -d aac -b 96000 -s 0 source.mp3 App/Resources/Audio/name.m4a
```

Keep the original outside the repository. Every re-encode committed is another
blob in the history for ever.

## How the music behaves

- Its own switch and volume in Settings, separate from the world's sound.
- It plays through, then leaves the valley alone for five minutes before coming
  back. Music that never stops is music nobody hears after an hour.
- It ducks under a raid rather than cutting, so the piece is still there when
  the fighting stops.
- The session is `.ambient`: the game respects the silent switch and never
  interrupts what the player is already listening to.
