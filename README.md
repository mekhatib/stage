# Stage

A native macOS app for DevRev Computer demos. Stage runs [Computer](https://app.devrev.ai) as several demo personas at the same time, each with its own sign-in, so you can switch between people during a demo without logging out and in.

- **Demos** group the people for one story, for example "Acme support escalation".
- **People** each get their own Computer session and their own sign-in, kept separate from your browser and from each other.
- Sessions stay signed in between launches and keep running in the background, so switching is instant.

Requires macOS 26 (Tahoe) or later. Runs on Apple Silicon and Intel Macs.

## Install

1. Download `Stage-<version>.zip` from the [latest release](../../releases/latest) and double-click it to unzip.
2. Move `Stage.app` to your Applications folder.
3. Open Stage. Because it isn't signed with an Apple Developer ID, macOS blocks the first launch:
   - Open **System Settings → Privacy & Security**, scroll to the message about Stage, and click **Open Anyway**. Confirm with your password.
   - Or run this once in Terminal: `xattr -dr com.apple.quarantine /Applications/Stage.app`

## Use

1. **Create a demo.** Give it a name and the DevRev organization it uses: the part after `app.devrev.ai/` in the org's URL.
2. **Add people.** Name, role and sign-in email. Every person must be a member of the demo's organization.
3. **Sign in each person once.** Select them, choose the email-code (passwordless) sign-in, and enter the code from their inbox. Google sign-in doesn't work inside apps, so use the email option.

Stage opens each person's Computer chat directly and keeps them there.

| Shortcut | Action |
| --- | --- |
| ⌘1–9 | Switch to a person in the current demo |
| ⌘⌥1–9 | Switch demo |
| ⌘N | Add person |
| ⌘⇧N | New demo |
| ⌘⇧H | Back to the Computer chat |
| ⌘R | Reload |

Right-click a person to power them on or off, edit them, move them to another demo, sign them out, or refresh their data.

### Troubleshooting

- **"You do not have access to view this page"** after entering the code: the email isn't a member of that organization, or the organization name is wrong. Invite the email to the org in DevRev, then right-click the person → **Sign Out and Reset**.
- **A banner says someone isn't in the org:** DevRev signed them into a different organization. Fix the membership or click **Use …** to switch them.
- **Lists look out of date** (for example deleted chats still showing): right-click the person → **Refresh Data**. DevRev may ask for a new sign-in code.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh            # builds ~/Applications/Stage.app
./package.sh          # builds and zips dist/Stage-<version>.zip for a release
```

`build.sh` uses the macOS 26 SDK when it's installed, because the macOS 27 SDK needs a SwiftUI compiler plugin that only ships with full Xcode. With Xcode installed you can use the current SDK: `SDK=$(xcrun --show-sdk-path) ./build.sh`.

Data is stored in `~/Library/Application Support/Stage`: `demos.json`, `sessions.json`, and `stage.log` (page paths only, never sign-in codes).
