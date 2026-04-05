# PostgresGUI - A native PostgreSQL client for macOS

![PostgresGUI screenshot in dark mode](https://github.com/PostgresGUI/website/blob/main/public/screenshots2/PostgresGUI%20-%20Dark%20mode.png?raw=true)

[![Version](https://img.shields.io/badge/version-1.1.4-blue.svg)](https://postgresgui.com)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%20Sequoia+-lightgrey.svg)](https://www.apple.com/macos)

PostgresGUI supports macOS 15 Sequoia and newer.

## Getting started

Requirements:
- macOS 15 Sequoia or later
- Xcode with a macOS 15 SDK or newer

1. Clone the repository:
   ```bash
   git clone https://github.com/PostgresGUI/app.git
   cd app
   ```

2. Open the project in Xcode:
   ```bash
   open PostgresGUI.xcodeproj
   ```

3. IMPORTANT: Configure code signing:
   - Select the **PostgresGUI** target in the project navigator
   - Go to **Signing & Capabilities** tab
   - Select your **Team** from the dropdown (use your Apple ID's "Personal Team" if you don't have a paid developer account)

4. Build and run with `Cmd+R`

### Submitting Pull Requests

When you select your team in step 3, Xcode modifies `project.pbxproj` with your team ID. **Do not include this change in your pull request.**

### Why Code Signing is Required

This app uses macOS Keychain to securely store database passwords. Keychain access requires a valid code signature, so even local development builds need to be signed with your team ID.

## Support

- Visit [postgresgui.com/support](https://postgresgui.com/support) for help and documentation
- Report bugs on [GitHub Issues](https://github.com/yourusername/postgresgui/issues)

## Acknowledgments

PostgresGUI is built on the shoulders of giants. Special thanks to:

- The [PostgresNIO](https://github.com/vapor/postgres-nio) team for the excellent PostgreSQL client library
- The [Swift NIO](https://github.com/apple/swift-nio) project for the networking foundation
