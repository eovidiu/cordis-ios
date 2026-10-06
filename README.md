# cordis-ios

A native Swift (iOS 17+/macOS 14+) port of the [cordis](https://github.com/cordiverse/cordis) meta-framework core and loader (commit `f8ea3cd`, `cordis@4.0.0-rc.10`; paper [arXiv 2608.25512](https://arxiv.org/abs/2608.25512)). Apps are built from plugins that can be switched on and off at runtime: removing a plugin reverts every effect it installed, and a plugin runs only while every service it declares is provided.
