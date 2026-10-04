# MacIPTV

Read README.md and DEVELOPMENT.md before changing the project.

Keep the Universal Intel / Apple Silicon build. Preserve native playback, keyboard navigation and isolated test data. Never commit private playlists, credentials, local application data, generated logs or vendor binaries. Public screenshots must use synthetic catalog data, and illustrations must be labelled as illustrations.

Do not claim physical Intel testing, Apple notarization or audio/visual verification unless actually performed. AppKit/LibVLC changes require a native playback check; catalog changes require parser and browser tests.

## Linux port

Read the Linux README.md and DEVELOPMENT.md. Keep Resources/index.html and info.html shared with the Mac application; Linux branding/platform CSS belong in the GTK host. Linux changes live in Linux/. Run the Python core tests for parser, store and EPG changes, original browser tests for catalog changes, and an isolated GTK/LibVLC smoke test for player/window/bridge changes. Never load the user's data in a smoke test. Linux data belongs in the private XDG linuxiptv-data directory, not in the application installation folder.
