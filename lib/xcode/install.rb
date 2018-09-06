require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'rexml/document'
require 'rubygems/version'
require 'shellwords'
require 'spaceship'

module XcodeInstall
  CACHE_DIR = Pathname.new("#{ENV['HOME']}/Library/Caches/XcodeInstall")

  require 'xcode/install/command'
  require 'xcode/install/curl'
  require 'xcode/install/installer'
  require 'xcode/install/installed_xcode'
  require 'xcode/install/simulator'
  require 'xcode/install/xcode'
  require 'xcode/install/version'
end
