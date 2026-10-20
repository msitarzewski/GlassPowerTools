# App Store listing

The App Store listing for iPhone, iPad and Apple Vision Pro, and the answers App Store Connect asks
for. The Mac app is not on the App Store: it is signed with a Developer ID and updates through
Sparkle (D38).

## What is here

`metadata/` follows the layout of fastlane's `deliver`, one value per file, so a script or a person
can paste each one as it stands:

| File | Field | Limit |
|---|---|---|
| `en-US/name.txt` | Name | 30 |
| `en-US/subtitle.txt` | Subtitle | 30 |
| `en-US/promotional_text.txt` | Promotional text, which can change without a new version | 170 |
| `en-US/description.txt` | Description | 4,000 |
| `en-US/keywords.txt` | Keywords: comma-separated, no spaces, none repeated from the name or subtitle | 100 |
| `en-US/support_url.txt`, `marketing_url.txt`, `privacy_url.txt` | URLs | |
| `copyright.txt`, `primary_category.txt`, `secondary_category.txt` | App information | |
| `review_information/notes.txt` | Notes for App Review | 4,000 |

The privacy and support pages are `PRIVACY.md` and `SUPPORT.md`, which the site build renders as
glasspowertools.com/privacy.html and /support.html. The listing's claims were checked against the
help pages, which are written from the code, for iPhone, iPad and Vision Pro. Mac-only features
(the local shell, the Finder's services, default text editor) are left out.

Screenshots are not kept in the repository. They are made in two steps:
- `Tools/Screenshots/store_shots.sh` takes them from the simulators, at App Store sizes, into
  `build/appstore/screenshots/`.
- `Tools/Screenshots/store_frames.py` gives each one the site's look into `build/appstore/framed/`:
  a heading and a line from `screenshots.json`, in the site's words, on the site's dark surface.

The framed pictures are the ones uploaded (the owner chose this style on 2026-10-18).

The first version has no "What's New" text: App Store Connect asks for it from the second version.

**Versions.** The first App Store release is 1.0. TestFlight builds stay 0.4.*n* until then (the
owner, 2026-10-18), so 1.0 needs its own upload with that version number.

## Answers for App Store Connect

**Pricing and availability.** Free. Every country and region, once the owner has settled France's
encryption declaration (see below).

**Content rights.** "Does your app contain, show, or access third-party content?" No: it shows only
what is on the user's own machines.

**Age rating.** No or None to every question: no violence, mature themes, sexual content, gambling,
medical content, advertising, messaging, or content from other users, and no parental controls or
age checks of its own. "Unrestricted web access": No. The app has no web browser. The editor's HTML
preview allows no network access, and a link a terminal prints opens in the system's browser only
after the user confirms it. A remote desktop shows the user's own computer. This is a judgment call
for the owner, made with the reviewer in mind. Expected rating: 4+.

**App Privacy.** "Data Not Collected". The developer receives nothing from the app. Apple's
definition of collected is data sent off the device in a way that lets the developer or its partners
read it for longer than it takes to serve the request. Under that definition:
- the library, in the user's private CloudKit database, and the credentials, in iCloud Keychain, are
  stored in the user's own iCloud account, which the developer cannot read;
- traffic to the user's machines and to Tailscale goes to services the user chose, at the user's
  direction;
- crash reports, if the user shares them, are Apple's.

The app's privacy manifest (`App/PrivacyInfo.xcprivacy`) declares no collected data and no tracking,
and gives a reason for each "required reason" API the app uses.

**Export compliance.** The app uses standard encryption algorithms in addition to the operating
system's: SSH (SwiftNIO SSH), TLS (BoringSSL, through SwiftNIO SSL) and the session encryption of
Apple's Screen Sharing protocol. It uses no proprietary algorithms. Once App Store Connect has
accepted the answers, the matching `ITSAppUsesNonExemptEncryption` value goes into the app's
Info.plist, so later builds skip the question.

**Accessibility Nutrition Labels.** None declared yet. They are voluntary for now. Declare a
feature for a device only after the app's common tasks (add a host, connect, use the session,
disconnect) work with it on that device.

**App Review.** The notes are in `review_information/notes.txt`. The contact's name, phone and
email are entered in App Store Connect only, never here. Still open, for the owner: whether to give
the reviewer a demo server.
