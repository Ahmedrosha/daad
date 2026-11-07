# ضاد – Daad Keyboard

Arabic / English iPhone keyboard. Swift (UIKit keyboard extension + SwiftUI app).

- `App/` – containing app (setup guide + settings)
- `Keyboard/` – the keyboard extension
- `Shared/` – settings shared through App Group `group.com.daad.keyboard`
- `project.yml` – XcodeGen spec; the Xcode project is generated in CI
- `.github/workflows/ios.yml` – manual build & upload to TestFlight

Required repo secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (contents of the .p8 file).
