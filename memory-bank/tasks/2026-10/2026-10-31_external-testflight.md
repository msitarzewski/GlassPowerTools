# The first external TestFlight (2026-10-31)

**Ask (the owner):** "Let's also spin up the frist actual test flight. Fill in as many of the fields as possible, what
to test, what to look out for, etc." Internal TestFlight has run since 2026-10-20 (builds 491–494, the Internal
group); this is the first test for people outside the team, which needs Beta App Review.

## Done (through the App Store Connect API, his word)
- **Test information** (en-US): the beta app description (what the app is, that this test is Vision Pro, iPad and
  iPhone with the Mac from the website, iCloud, no analytics, GPLv3, bring your own machines); feedback email (the
  project's published contact); marketing URL glasspowertools.com; privacy policy glasspowertools.com/privacy.html.
- **The Testers group** (external): feedback on; a public link, limited to 100 testers (it works once a build passes
  review); the iPad app kept off Macs and the iPhone app off Vision Pro (each has its own).
- **Not set on purpose:** a beta licence agreement (empty: Apple's standard terms apply; the code is GPLv3); a demo
  account (none needed).
- **What to Test** for build 569 is drafted (outside the repository): what to try, what to watch for (wrong machine,
  a host key trusted without asking, sync losing a change, a terminal that freezes or doesn't come back, readability on
  glass, VoiceOver, crashes), what's known (servers tested), and how to send feedback.

## Uploaded (2026-10-31, after he signed in again)
- **0.4.569 (569)** for iPhone, iPad and Vision Pro, with the released Xcode 27.2 (27B52). The first try with it
  failed at the archive (`missing Metal Toolchain`: a new Xcode needs `xcodebuild -downloadComponent MetalToolchain`);
  the second uploaded both. Both builds processed (`VALID`), encryption answered by the Info.plist.
- **What to Test** written into both builds (en-US), read back. It gained one line after the owner asked whether
  links, paths and log previews were mentioned anywhere: on Vision Pro, pinch and hold a link or path; Quick Look with
  a log's end; Watch Log File.
- **Both builds added to Testers.** Internal: `IN_BETA_TESTING`. External: `READY_FOR_BETA_SUBMISSION`, so testers
  see nothing until Beta App Review passes.

## Blocked
- **Beta App Review details, and so the submission:** contact name and email ready; App Store Connect requires a
  contact phone in the same request, which only he can give. Then `POST /v1/betaAppReviewSubmissions` for each build.
