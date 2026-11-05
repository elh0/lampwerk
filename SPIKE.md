# CloudKit spike (step 4 of studio-brain/specs/sync-web-build-brief.md)

## Done (2026-11-05)
- iCloud + CloudKit (container iCloud.com.lampwerk.app), aps-environment, Background Modes > remote-notification (Lampwerk-Info.plist merges into the generated Info.plist). `-allowProvisioningUpdates` registered the container; no clicks needed.
- Debug-only test: long-press "Saved on this phone" on the plots screen (Lampwerk/Debug/CloudKitSpike.swift). CKSyncEngine, private zone "Plots", record spike-plot of type Plot (fields json, name, modifiedAt); public LiveLink record (json, name, expiresAt).
- Local web test pages in spike-web/ (index.html private read/rename/save, public.html#<id>). Token goes in spike-web/token.js (gitignored). Serve with `python3 -m http.server 8765` in spike-web/.

## Left
Web API token for iCloud.com.lampwerk.app, then the three tests on the phone and laptop.
