cask "sleepnot" do
  version "1.2"
  # Filled in after the first GitHub Release: run `make zip` and paste the
  # printed sha256 below, then bump version together with MARKETING_VERSION.
  sha256 "985bd0f9fe6858fe09bf56461080c45f75d6693e66d07f9dffda10fdc7819ce3"

  url "https://github.com/us/sleepnot/releases/download/v#{version}/SLEEPNOT-#{version}.zip"
  name "SLEEPNOT"
  desc "Tiny menu bar utility that blocks idle system sleep while letting the display sleep"
  homepage "https://github.com/us/sleepnot"

  app "SLEEPNOT.app"
end
