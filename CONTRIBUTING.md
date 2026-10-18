# Contributing to DeepSeek-chan

Bug reports, little stories, artwork improvements, accessibility work, and platform ports are welcome.

## Before changing code

Read the relevant source and README section, then keep the change focused. Build with `zsh scripts/package-debug.sh` and run `zsh scripts/check.sh`. Do not submit API keys, personal preferences, screenshots containing private information, generated app bundles, or DMGs in a pull request.

For a bug report, include the app version, macOS version, processor, number of displays, steps to reproduce, and expected/actual behavior. For a visual issue, a cropped screenshot of the app is helpful.

## Pet behavior

Keep dialogue brief and friendly. Do not interrupt an unsent chat draft or an eye break. Keep one routine active at a time, honor Reduce Motion, and test outfit changes, dismissal, drag pauses, and stale queued lines when relevant. Keep English interface controls separate from her multilingual phrases.

## Artwork

Include provenance and redistribution information for new art. Keep genuine transparency and the existing atlas/manifest contracts. Render and inspect affected crops with `Tests/RenderActions.swift`; a JSON bounds check does not prove a figure is visually intact. Do not count mirrored images or speed changes as new illustrated poses.

## Windows and Linux

These ports are planned, not implemented. Start a focused issue describing the proposed platform layer and how it will be tested. Desktop windows, input/idle detection, accessibility, key storage, and installers need native equivalents. Please do not label an untested cross-compiled binary as a supported release.

## Pull requests

Explain the user-visible change, the checks you ran, and anything you could not verify. Test changes that cross behavior boundaries; avoid tests that only assert source strings. Use synthetic credentials and a mock transport for dialogue tests.

By contributing, you agree to license your original code contributions under the repository's MIT license. Artwork contributions must clearly state their own provenance and any applicable third-party restrictions.
