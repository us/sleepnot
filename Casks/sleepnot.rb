cask "sleepnot" do
  version "1.0"
  # Filled in after the first GitHub Release: run `make zip` and paste the
  # printed sha256 below, then bump version together with MARKETING_VERSION.
  sha256 "REPLACE_WITH_SHA256_AFTER_FIRST_RELEASE"

  url "https://github.com/us/sleepnot/releases/download/v#{version}/SLEEPNOT-#{version}.zip"
  name "SLEEPNOT"
  desc "Tiny menu bar utility that blocks idle system sleep while letting the display sleep"
  homepage "https://github.com/us/sleepnot"

  app "SLEEPNOT.app"
end
