# Browser home dashboard — local acceptance, 2026-10-30

The browser entry screen now opens as a home dashboard with a short mission overview, a room-code Join card, a Create card, and access to local play and the full guide. The cards stay in a centered column on laptop screens. The native touch input still filters and capitalizes room codes, and Join becomes available when a valid six-character code is entered.

The local Godot Web export was checked in Chromium at [390×844](evidence/browser-home-dashboard-2026-10-30/prompt-heist-dashboard-phone.png), [390×480](evidence/browser-home-dashboard-2026-10-30/prompt-heist-dashboard-short-phone.png), and [1280×720](evidence/browser-home-dashboard-2026-10-30/prompt-heist-dashboard-laptop.png). Join and Create are both visible without scrolling at 390×844; the shorter viewport scrolls to the lower controls. On a phone-sized touch viewport, entering a lowercase code produced uppercase `ABC234`, enabled Join, and opened the online entry screen with that code. Create opened the online entry screen with an empty code. No browser page errors occurred. Godot regression tests and mobile UI smoke passed.

This is a local Chromium layout and interaction check. The Render deployment and a physical-phone view of the new dashboard remain to be checked after merge.
