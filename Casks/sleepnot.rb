cask "sleepnot" do
  version "1.1"
  # Filled in after the first GitHub Release: run `make zip` and paste the
  # printed sha256 below, then bump version together with MARKETING_VERSION.
  sha256 "2ee7a66ffa314ac03fe2ea669eaed35fbcff59a6e2cf1e3def2f811162ba0839"

  url "https://github.com/us/sleepnot/releases/download/v#{version}/SLEEPNOT-#{version}.zip"
  name "SLEEPNOT"
  desc "Tiny menu bar utility that blocks idle system sleep while letting the display sleep"
  homepage "https://github.com/us/sleepnot"

  app "SLEEPNOT.app"
end
