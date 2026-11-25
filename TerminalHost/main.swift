//
//  main.swift
//  Glass Power Tools Terminal Host
//
//  The small app that keeps a Mac's local terminals running (D66, D115): launchd starts it with
//  `--tmux-host <tmux>`, and it runs tmux and waits for it. It carries the app's bundle ID and is
//  signed as the app is, so macOS asks for, and keeps, folder permissions in Glass Power Tools' name.
//  Its whole program is `MacTmuxHost`; nothing of the app's is linked.
//

import GlassTerminalHost

MacTmuxHost.main()
