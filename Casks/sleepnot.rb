cask "sleepnot" do
  version "1.0"
  # Filled in after the first GitHub Release: run `make zip` and paste the
  # printed sha256 below, then bump version together with MARKETING_VERSION.
  sha256 "8aaca1f1bfba7f1dff362b25e520d1bf3f485d3b3c6f632a2b9e6b6ec8988bc2"

  url "https://github.com/us/sleepnot/releases/download/v#{version}/SLEEPNOT-#{version}.zip"
  name "SLEEPNOT"
  desc "Tiny menu bar utility that blocks idle system sleep while letting the display sleep"
  homepage "https://github.com/us/sleepnot"

  app "SLEEPNOT.app"
end
