cask "clipboardapp" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/anlostsheep/clipboard/releases/download/v#{version}/ClipboardApp-v#{version}-macos.zip"
  name "Clipboard"
  desc "Menu bar clipboard history manager"
  homepage "https://github.com/anlostsheep/clipboard"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "ClipboardApp.app"

  zap trash: [
    "~/Library/Application Support/com.local.clipboard-manager",
    "~/Library/Preferences/com.local.clipboard-manager.plist",
  ]

  caveats <<~EOS
    Clipboard is a self-signed, un-notarized open-source beta.

    Auto-paste needs Accessibility permission:
      System Settings -> Privacy & Security -> Accessibility -> enable ClipboardApp.

    Updates are delivered through Homebrew:
      brew upgrade --cask clipboardapp
  EOS
end
