# Sync setup

Sync runs when the app starts, every 3 minutes, when you close a note, and when you press **Sync now** in the sidebar. You can always write offline.

## Proton Drive (or OneDrive / Dropbox)

1. Install the provider's Windows app and sign in.
2. Create a folder inside the synced drive, e.g. `Proton Drive\CaretNotes`.
3. CaretNotes → Settings → Sync → **Synced folder** → choose that folder.
4. On every other computer, choose the same folder.

CaretNotes writes its files there and the Proton Drive app uploads them. If the Proton Drive app creates its own "Name clash" copies, CaretNotes recognizes them and asks you how to merge them.

> Android: the Proton Drive Android app doesn't offer a synced folder, so Proton sync on Android will need another route. That will be decided when the Android version is built. Google Drive and WebDAV will work there directly.

## Google Drive

Google requires every app that isn't in a store to have its own sign-in client. It's free and takes about 5 minutes:

1. Open <https://console.cloud.google.com/>, create a project (any name).
2. **APIs & Services → Library**: enable **Google Drive API**.
3. **APIs & Services → OAuth consent screen**: choose *External*, fill in the app name and your email, add yourself as a **test user**.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → application type **Desktop app**.
5. Copy the **Client ID** and **Client secret** into CaretNotes → Settings → Sync → Google Drive, then press **Sign in with Google**.

CaretNotes only gets access to the files it creates (`drive.file` scope), stored in a `CaretNotes` folder in your Drive. While the Google app is in "Testing" mode, Google signs you out about once a week. Press *Sign in* again when the sidebar asks. Publishing the consent screen removes that limit.

## WebDAV (Nextcloud, ownCloud, NAS)

Enter the folder's WebDAV address (Nextcloud: `https://<server>/remote.php/dav/files/<user>/CaretNotes`), your user name and an app password. The password is stored encrypted with Windows DPAPI.

## How sync decides

CaretNotes keeps a copy of each note as it was at the last sync, so it can tell who changed what:

- Changed on one device only: that version wins.
- Changed on one device, deleted on the other: the edit wins and the note comes back.
- Changed on both: you choose. **Combine both** merges strokes, text and pages by their ids; **Keep this** / **Keep other** pick one; **Keep both** saves the other version as a copy.
- Nothing is ever deleted for good by sync. Replaced versions go to **Recently deleted** for 30 days.
- A note that is open in the editor is left alone until you close it.
